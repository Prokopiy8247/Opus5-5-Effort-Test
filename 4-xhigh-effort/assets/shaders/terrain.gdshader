shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Project-owned terrain shading driven by the baked control map (region weights + crop fields)
// and detail map (road verges, forest floor, sand, snow); slope rock with desert strata.

uniform sampler2D control_map : filter_linear, repeat_disable;
uniform sampler2D detail_map : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float half_size = 2048.0;
global uniform float wetness;
global uniform float snow_cover;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

vec3 crop_color(int id, float n) {
	if (id == 1) return mix(vec3(0.62, 0.45, 0.12), vec3(0.74, 0.56, 0.18), n);  // ripe wheat
	if (id == 2) return mix(vec3(0.24, 0.38, 0.1), vec3(0.34, 0.48, 0.16), n);  // young crop
	if (id == 3) return mix(vec3(0.27, 0.19, 0.12), vec3(0.36, 0.26, 0.17), n); // ploughed
	if (id == 4) return mix(vec3(0.42, 0.36, 0.5), vec3(0.5, 0.42, 0.58), n);   // lavender
	return mix(vec3(0.36, 0.44, 0.12), vec3(0.46, 0.52, 0.16), n);              // meadow hay
}

void fragment() {
	vec2 muv = (wpos.xz + half_size) / (2.0 * half_size);
	vec4 ctl = texture(control_map, muv);
	vec4 det = texture(detail_map, muv);
	float wd = ctl.r;
	float wm = ctl.g;
	float wc = ctl.b;
	float wf = max(0.0, 1.0 - wd - wm - wc);
	float n1 = texture(noise_tex, wpos.xz * 0.0065).r;
	float n2 = texture(noise_tex, wpos.xz * 0.055).r;
	float n3 = texture(noise_tex, wpos.xz * 0.6).r;
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	vec3 grass_f = mix(vec3(0.12, 0.25, 0.05), vec3(0.24, 0.36, 0.08), n1);
	grass_f = mix(grass_f, vec3(0.38, 0.42, 0.16), smoothstep(0.55, 0.8, n2) * 0.4);
	vec3 grass_m = mix(vec3(0.2, 0.27, 0.11), vec3(0.3, 0.33, 0.17), n1);
	vec3 desert = mix(vec3(0.6, 0.35, 0.19), vec3(0.72, 0.46, 0.27), n1);
	desert = mix(desert, vec3(0.5, 0.42, 0.25), smoothstep(0.6, 0.8, n2) * 0.35);
	vec3 coastg = mix(vec3(0.27, 0.36, 0.13), vec3(0.44, 0.47, 0.22), n1);
	vec3 base = grass_f * wf + grass_m * wm + desert * wd + coastg * wc;
	// crop fields with plough rows
	float fcode = ctl.a * 255.0 / 40.0;
	if (fcode > 0.5) {
		int fid = int(floor(fcode + 0.5));
		float ang = float(fid) * 1.3;
		float rows = 0.5 + 0.5 * sin(dot(wpos.xz, vec2(cos(ang), sin(ang))) * 2.2);
		vec3 crop = crop_color(fid, n2) * mix(0.82, 1.08, rows);
		base = mix(base, crop, smoothstep(0.5, 0.9, fcode) * (1.0 - det.r));
	}
	base = mix(base, base * vec3(0.62, 0.7, 0.58), det.g * 0.55);
	vec3 sand = mix(vec3(0.78, 0.7, 0.52), vec3(0.88, 0.8, 0.62), n2);
	sand = mix(sand, vec3(0.86, 0.62, 0.4), wd);
	base = mix(base, sand, det.b);
	base = mix(base, mix(base, vec3(0.3, 0.27, 0.2), 0.5) * (0.8 + 0.4 * n3), smoothstep(0.35, 0.95, det.r) * 0.45);
	// rock on steep ground; desert rock shows horizontal strata
	float rockw = smoothstep(0.2, 0.34, slope + (n2 - 0.5) * 0.12);
	vec3 rock = mix(vec3(0.36, 0.35, 0.33), vec3(0.52, 0.5, 0.47), n2);
	float strata = 0.5 + 0.5 * sin(wpos.y * 0.85 + n2 * 4.0);
	vec3 rock_d = mix(vec3(0.5, 0.26, 0.15), vec3(0.74, 0.47, 0.3), strata);
	rock = mix(rock, rock_d, wd);
	base = mix(base, rock, rockw);
	float snow = max(det.a, snow_cover * smoothstep(240.0, 330.0, wpos.y + n2 * 30.0));
	snow *= 1.0 - rockw * 0.55;
	base = mix(base, vec3(0.9, 0.92, 0.96), snow);
	base *= 0.86 + 0.28 * n3;
	float wet = clamp(wetness, 0.0, 1.0) * (1.0 - snow);
	ALBEDO = base * (1.0 - wet * 0.28);
	ROUGHNESS = clamp(mix(0.95, 0.55, wet) - rockw * 0.05 - snow * 0.25, 0.05, 1.0);
	NORMAL_MAP = texture(noise_nrm, wpos.xz * 0.21).rgb;
	NORMAL_MAP_DEPTH = 0.6 + rockw * 0.8;
}
