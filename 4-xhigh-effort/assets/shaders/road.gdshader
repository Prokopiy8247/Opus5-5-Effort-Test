shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Project-owned road surface. UV.x = lateral metres from the centre line, UV.y = metres along.
// Classes: 0 highway, 1 regional, 2 mountain, 3 village, 4 gravel, 5 dirt.

uniform int road_class = 1;
uniform float half_w = 4.5;
uniform float lane_w = 3.4;
uniform float shoulder = 1.1;
uniform float median = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
global uniform float wetness;

float line_mask(float x, float a, float b, float aa) {
	return smoothstep(a - aa, a, x) * (1.0 - smoothstep(b, b + aa, x));
}

float dash(float s, float on_len, float period) {
	return step(mod(s, period), on_len);
}

void fragment() {
	float u = UV.x;
	float s = UV.y;
	float au = abs(u);
	float aa = fwidth(u) * 1.2 + 0.004;
	float n1 = texture(noise_tex, vec2(u * 0.11, s * 0.035)).r;
	float n2 = texture(noise_tex, vec2(u, s) * 0.45).r;
	float n3 = texture(noise_tex, vec2(u, s) * 3.1).r;
	vec3 col;
	float rough;
	float paint = 0.0;
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	bool paved = road_class <= 3;
	if (au > half_w + 0.02) {
		// verge and embankment skirt
		float t = smoothstep(half_w, half_w + 1.6, au);
		vec3 gravel = mix(vec3(0.26, 0.25, 0.23), vec3(0.36, 0.34, 0.31), n3);
		vec3 earth = mix(vec3(0.15, 0.22, 0.07), vec3(0.24, 0.3, 0.1), n2);
		earth = mix(earth, vec3(0.3, 0.25, 0.18), n3 * 0.5);
		col = mix(gravel, earth, t);
		rough = 0.95;
	} else if (paved) {
		vec3 asphalt = mix(vec3(0.085, 0.087, 0.09), vec3(0.15, 0.15, 0.155), n1 * 0.6 + n3 * 0.4);
		// patch repairs and wheel-path polishing
		float patchm = smoothstep(0.62, 0.66, texture(noise_tex, vec2(u * 0.05, s * 0.012)).r);
		asphalt = mix(asphalt, asphalt * 0.75, patchm);
		float lane_pos = mod(au - median * 0.5, lane_w);
		float wheel = line_mask(lane_pos, lane_w * 0.22, lane_w * 0.36, 0.3) + line_mask(lane_pos, lane_w * 0.64, lane_w * 0.78, 0.3);
		asphalt *= 1.0 - wheel * 0.12;
		col = asphalt;
		rough = mix(0.82, 0.7, wheel);
		float edge_in = half_w - shoulder;
		// solid edge lines
		paint = max(paint, line_mask(au, edge_in - 0.16, edge_in, aa));
		if (road_class == 0) {
			// highway: double yellow at the median, dashed lane dividers
			float m0 = median * 0.5;
			float yl = line_mask(au, m0 - 0.02, m0 + 0.13, aa);
			if (yl > 0.0) {
				paint_col = mix(paint_col, vec3(0.95, 0.75, 0.15), yl);
			}
			paint = max(paint, yl);
			col = mix(col, vec3(0.2, 0.2, 0.19), 1.0 - smoothstep(m0 - 0.05, m0, au));
			paint = max(paint, line_mask(au, m0 + lane_w - 0.07, m0 + lane_w + 0.07, aa) * dash(s, 4.0, 12.0));
		} else if (road_class == 1) {
			paint = max(paint, line_mask(au, -0.1, 0.07, aa) * dash(s, 3.0, 9.0));
		} else if (road_class == 2) {
			float dl = line_mask(au, 0.07, 0.19, aa);
			paint = max(paint, dl);
			paint_col = mix(paint_col, vec3(0.95, 0.78, 0.2), dl);
		} else {
			paint = max(paint, line_mask(au, -0.1, 0.06, aa) * dash(s, 1.5, 4.5));
		}
		// worn paint
		paint *= smoothstep(0.15, 0.35, n3 + 0.2);
	} else {
		// gravel / dirt with ruts and a crowned centre
		vec3 g0 = road_class == 4 ? vec3(0.48, 0.46, 0.42) : vec3(0.47, 0.37, 0.26);
		vec3 g1 = road_class == 4 ? vec3(0.62, 0.6, 0.55) : vec3(0.6, 0.48, 0.34);
		col = mix(g0, g1, n3 * 0.7 + n1 * 0.3);
		float rut = line_mask(au, lane_w * 0.18, lane_w * 0.42, 0.35);
		col *= 1.0 - rut * 0.14;
		col = mix(col, col * 1.12, 1.0 - smoothstep(0.0, 0.6, au));
		rough = 0.97;
	}
	col = mix(col, paint_col, clamp(paint, 0.0, 1.0));
	rough = mix(rough, 0.6, paint);
	// rain: darker, glossier, puddles in low spots
	float puddle = smoothstep(0.55, 0.7, texture(noise_tex, vec2(u * 0.08, s * 0.02)).r) * (paved ? 1.0 : 1.3);
	float wet = clamp(wetness, 0.0, 1.0);
	col *= 1.0 - wet * (0.35 + 0.25 * puddle);
	rough = mix(rough, 0.08, wet * (0.55 + 0.45 * clamp(puddle, 0.0, 1.0)));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	NORMAL_MAP = texture(noise_nrm, vec2(u, s) * 0.7).rgb;
	NORMAL_MAP_DEPTH = paved ? 0.25 * (1.0 - wet) : 0.9;
}
