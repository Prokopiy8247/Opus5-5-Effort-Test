shader_type sky;
render_mode use_debanding;

// Velora sky: physically-flavoured gradient driven by sun elevation, sun disk, moving
// procedural clouds whose coverage/darkness come from the weather system, stars at night.

uniform vec3 day_zenith : source_color = vec3(0.22, 0.45, 0.85);
uniform vec3 day_horizon : source_color = vec3(0.68, 0.8, 0.95);
uniform vec3 sunset_horizon : source_color = vec3(1.0, 0.55, 0.25);
uniform vec3 night_zenith : source_color = vec3(0.01, 0.015, 0.04);
uniform vec3 night_horizon : source_color = vec3(0.04, 0.06, 0.12);
uniform float cloud_coverage = 0.3;
uniform float cloud_darkness = 0.0;
uniform float cloud_time = 0.0;
uniform float star_strength = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 overcast_color : source_color = vec3(0.55, 0.58, 0.62);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sun_h = sun_dir.y;
	float day = smoothstep(-0.12, 0.25, sun_h);
	float sunset = smoothstep(0.45, 0.0, abs(sun_h - 0.02)) * smoothstep(-0.2, 0.0, sun_h);
	float hgt = clamp(d.y, 0.0, 1.0);
	float horizon_f = pow(1.0 - hgt, 3.0);
	vec3 zen = mix(night_zenith, day_zenith, day);
	vec3 hor = mix(night_horizon, day_horizon, day);
	float toward_sun = pow(max(dot(normalize(vec3(d.x, 0.0, d.z) + 0.0001), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 0.0001)), 0.0), 3.0);
	hor = mix(hor, sunset_horizon, sunset * (0.45 + 0.55 * toward_sun));
	vec3 col = mix(zen, hor, horizon_f);
	// below horizon: dim ground haze
	if (d.y < 0.0) {
		col = mix(hor, hor * 0.55, smoothstep(0.0, -0.3, d.y));
	}
	// overcast flattening
	col = mix(col, overcast_color * mix(0.08, 1.0, day), cloud_darkness * 0.85);
	// sun disk + glow
	float sd = dot(d, sun_dir);
	float disk = smoothstep(0.9994, 0.9997, sd);
	float glow = pow(max(sd, 0.0), 300.0) * 0.6 + pow(max(sd, 0.0), 12.0) * 0.18;
	col += (vec3(1.0, 0.92, 0.75) * disk * 30.0 + vec3(1.0, 0.75, 0.45) * glow) * day * (1.0 - cloud_darkness * 0.9);
	// moon (opposite the sun)
	float md = dot(d, -sun_dir);
	col += vec3(0.75, 0.8, 0.9) * smoothstep(0.9996, 0.9998, md) * (1.0 - day) * 2.0;
	// stars
	if (d.y > 0.0) {
		vec3 sp = floor(d * 280.0);
		float st = step(0.9975, hash(sp)) * (1.0 - day) * star_strength * (1.0 - cloud_coverage);
		col += vec3(st) * 1.5;
	}
	// clouds on a flat layer projected to the dome
	if (d.y > 0.01) {
		vec2 uv = d.xz / (d.y + 0.08) * 0.35;
		float n = texture(cloud_noise, uv * 0.6 + vec2(cloud_time * 0.004, cloud_time * 0.0015)).r;
		float n2 = texture(cloud_noise, uv * 1.7 - vec2(cloud_time * 0.006, 0.0)).r;
		float c = n * 0.7 + n2 * 0.3;
		float thresh = mix(0.72, 0.2, cloud_coverage);
		float cm = smoothstep(thresh, thresh + 0.22, c) * smoothstep(0.01, 0.15, d.y);
		vec3 lit = mix(vec3(1.0), sunset_horizon * 1.2, sunset * 0.6);
		vec3 cloud_col = mix(vec3(0.05, 0.06, 0.08), lit, day);
		cloud_col *= mix(1.0, 0.35, cloud_darkness);
		cloud_col *= 0.75 + 0.35 * (1.0 - n2);
		col = mix(col, cloud_col, cm * 0.92);
	}
	COLOR = col;
}
