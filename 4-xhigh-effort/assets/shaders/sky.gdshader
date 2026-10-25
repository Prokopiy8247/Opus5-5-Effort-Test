shader_type sky;
render_mode use_debanding;
// Project-owned sky: Rayleigh-ish gradient by sun height, sunset glow, sun and moon discs,
// procedural cloud layer (coverage/darkness from weather), stars and lightning flashes.

uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 moon_dir = vec3(0.0, -0.7, -0.7);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float flash = 0.0;
uniform vec3 tint = vec3(1.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = EYEDIR;
	float sh = sun_dir.y;
	float day = smoothstep(-0.14, 0.22, sh);
	float dusk = clamp(1.0 - abs(sh - 0.02) / 0.28, 0.0, 1.0);
	vec3 zen_day = vec3(0.1, 0.28, 0.66);
	vec3 hor_day = vec3(0.5, 0.66, 0.84);
	vec3 zen_night = vec3(0.004, 0.009, 0.025);
	vec3 hor_night = vec3(0.025, 0.04, 0.08);
	vec3 zen = mix(zen_night, zen_day, day);
	vec3 hor = mix(hor_night, hor_day, day);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(hor, zen, pow(up, 0.55));
	// sunset band towards the sun azimuth
	vec3 sflat = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-4);
	float toward = max(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-4), sflat), 0.0);
	vec3 glow_col = mix(vec3(1.0, 0.42, 0.18), vec3(1.0, 0.7, 0.45), smoothstep(0.0, 0.2, sh));
	col += glow_col * dusk * pow(toward, 3.0) * (1.0 - pow(up, 0.35)) * 0.85;
	col = mix(col, col * vec3(1.05, 0.85, 0.95), dusk * 0.25);
	// sun
	float sd = dot(d, normalize(sun_dir));
	col += vec3(1.0, 0.9, 0.7) * pow(max(sd, 0.0), 220.0) * 1.2 * day;
	col += mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.95, 0.85), day) * smoothstep(0.99955, 0.99975, sd) * 30.0 * smoothstep(-0.06, 0.02, sh);
	// moon and stars
	float night = 1.0 - day;
	float md = dot(d, normalize(moon_dir));
	col += vec3(0.75, 0.82, 1.0) * smoothstep(0.99935, 0.9996, md) * 4.0 * night;
	col += vec3(0.25, 0.3, 0.45) * pow(max(md, 0.0), 40.0) * 0.2 * night;
	if (!AT_CUBEMAP_PASS && night > 0.01 && d.y > 0.0) {
		vec3 sp = floor(d * 380.0);
		float st = hash(sp);
		col += vec3(0.9, 0.95, 1.0) * smoothstep(0.9975, 1.0, st) * night * up * 1.6;
	}
	// clouds on a curved layer
	if (d.y > -0.02) {
		vec2 cuv = d.xz / (d.y + 0.11) * 0.18 + cloud_offset;
		float n = texture(cloud_noise, cuv).r * 0.65 + texture(cloud_noise, cuv * 2.7 + 3.1).r * 0.35;
		float thr = 1.0 - cloud_coverage;
		float c = smoothstep(thr - 0.12, thr + 0.28, n) * smoothstep(-0.02, 0.18, d.y);
		vec3 lit = mix(vec3(0.05, 0.06, 0.09), mix(vec3(1.0, 0.62, 0.4), vec3(1.0, 0.99, 0.97), smoothstep(0.0, 0.3, sh)), day);
		vec3 shade = mix(vec3(0.03, 0.035, 0.05), vec3(0.45, 0.48, 0.55), day);
		float self_shadow = smoothstep(0.35, 1.0, n);
		vec3 ccol = mix(lit, shade, clamp(self_shadow * 0.6 + cloud_darkness * 0.85, 0.0, 1.0));
		ccol += vec3(1.0, 0.85, 0.7) * pow(max(sd, 0.0), 12.0) * 0.45 * day * (1.0 - cloud_darkness);
		col = mix(col, ccol, c * 0.95);
		// overcast flattens the whole sky towards grey
		col = mix(col, shade * 1.1, cloud_coverage * cloud_darkness * 0.7);
	}
	// below the horizon
	if (d.y < 0.0) {
		col = mix(col, hor * 0.55, smoothstep(0.0, -0.15, d.y));
	}
	col += vec3(0.75, 0.8, 1.0) * flash;
	COLOR = col * tint;
}
