shader_type sky;
// Project-owned procedural sky: Rayleigh-ish gradient, sun disc + halo, moon, stars,
// two-layer animated clouds whose coverage/darkness follow the weather.

uniform vec3 zenith_day : source_color = vec3(0.18, 0.38, 0.78);
uniform vec3 horizon_day : source_color = vec3(0.62, 0.76, 0.92);
uniform vec3 zenith_night : source_color = vec3(0.01, 0.015, 0.04);
uniform vec3 horizon_night : source_color = vec3(0.03, 0.05, 0.1);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.45, 0.18);
uniform vec3 ground_color : source_color = vec3(0.28, 0.27, 0.25);
uniform float day_amount : hint_range(0.0, 1.0) = 1.0;
uniform float sunset_amount : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 2.0) = 0.0;
uniform vec3 moon_dir = vec3(0.3, 0.5, -0.8);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_noise2 : filter_linear_mipmap, repeat_enable;
uniform float time_scale = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	float hpos = max(h, 0.0);
	vec3 sun = normalize(LIGHT0_DIRECTION);
	float sun_dot = max(dot(dir, sun), 0.0);

	vec3 zen = mix(zenith_night, zenith_day, day_amount);
	vec3 hor = mix(horizon_night, horizon_day, day_amount);
	vec3 col = mix(hor, zen, pow(hpos, 0.45));
	// sunset glow around the sun azimuth near the horizon
	float glow_band = pow(1.0 - hpos, 6.0);
	col = mix(col, sunset_color * (0.6 + 0.4 * day_amount), sunset_amount * glow_band * (0.35 + 0.65 * pow(sun_dot, 3.0)));
	// overcast greys everything out
	vec3 grey = mix(vec3(0.05, 0.055, 0.06), vec3(0.58, 0.6, 0.62), day_amount) * (1.0 - cloud_darkness * 0.55);
	col = mix(col, grey, overcast);

	// sun disc + halo
	if (LIGHT0_ENABLED) {
		float disc = smoothstep(0.99955, 0.99975, sun_dot);
		float halo = pow(sun_dot, 64.0) * 0.6 + pow(sun_dot, 8.0) * 0.12;
		vec3 sun_col = LIGHT0_COLOR * (1.0 - overcast * 0.85);
		col += sun_col * (disc * 18.0 + halo) * day_amount;
	}
	// moon + stars at night
	float night = 1.0 - day_amount;
	if (night > 0.01) {
		vec3 md = normalize(moon_dir);
		float m = smoothstep(0.99935, 0.9996, dot(dir, md));
		col += vec3(0.85, 0.88, 0.95) * m * night * (1.0 - overcast);
		vec3 sp = floor(dir * 420.0);
		float s = hash(sp);
		float star = step(0.9965, s) * (0.5 + 0.5 * sin(TIME * 2.0 + s * 50.0));
		col += vec3(star) * night * hpos * (1.0 - overcast) * (1.0 - cloud_coverage);
	}
	// clouds on a virtual plane
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.08) * 0.28;
		float t = TIME * 0.004 * time_scale;
		float n1 = texture(cloud_noise, uv * 0.6 + vec2(t, t * 0.3)).r;
		float n2 = texture(cloud_noise2, uv * 1.7 + vec2(-t * 1.6, t)).r;
		float n = n1 * 0.7 + n2 * 0.45;
		float cov = mix(0.95, 0.38, cloud_coverage);
		float c = smoothstep(cov, cov + 0.32, n) * smoothstep(0.0, 0.18, h);
		vec3 lit = mix(vec3(0.08, 0.09, 0.11), vec3(1.0, 0.99, 0.97), day_amount) * (1.0 - cloud_darkness * 0.7);
		lit = mix(lit, sunset_color * 1.2, sunset_amount * 0.55);
		vec3 shade = lit * mix(0.62, 0.35, cloud_darkness);
		vec3 cloud_col = mix(lit, shade, smoothstep(0.4, 1.0, n));
		cloud_col += LIGHT0_COLOR * pow(sun_dot, 12.0) * 0.35 * day_amount;
		col = mix(col, cloud_col, c * 0.92);
	}
	col += vec3(0.75, 0.8, 1.0) * flash;
	// below horizon: dim ground tone so reflections stay sane
	if (h < 0.0) {
		col = mix(col, ground_color * (0.2 + 0.8 * day_amount) * (1.0 - overcast * 0.4), smoothstep(0.0, -0.08, h));
	}
	COLOR = col;
}
