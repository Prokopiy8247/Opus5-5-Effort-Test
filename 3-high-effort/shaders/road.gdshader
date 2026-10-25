shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural road surface. UV.x = lateral metres from centre line, UV.y = metres along road.
// road_type: 0 two-lane, 1 four-lane highway, 2 lane (no centre line), 3 dirt, 4 gravel, 5 sand

uniform int road_type = 0;
uniform float half_width = 4.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
global uniform float wetness;
global uniform float snow_cover;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_mask(float u, float center, float width) {
	float d = abs(u - center);
	float aa = fwidth(u) * 1.2;
	return 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, d);
}

float dash(float v, float len, float gap) {
	float p = mod(v, len + gap);
	float aa = fwidth(v) * 1.5;
	return smoothstep(0.0, aa, p) * (1.0 - smoothstep(len - aa, len, p));
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float au = abs(u);
	float n1 = texture(noise_tex, wpos.xz * 0.02).r;
	float n2 = texture(noise_detail, wpos.xz * 0.35).r;
	float n3 = texture(noise_detail, wpos.xz * 2.1).r;
	vec3 col;
	float rough;
	float paved = 1.0 - smoothstep(half_width - 0.05, half_width + 0.05, au);
	if (road_type <= 2) {
		// asphalt with aggregate speckle, patch repairs and darker tyre tracks
		col = vec3(0.13, 0.13, 0.135) * (0.85 + 0.25 * n3) * (0.9 + 0.2 * n1);
		float patch = smoothstep(0.62, 0.66, texture(noise_tex, wpos.xz * 0.05).r);
		col = mix(col, vec3(0.085, 0.085, 0.09), patch * 0.7);
		float lane_w = road_type == 1 ? 3.6 : half_width;
		float track_c = road_type == 1 ? mod(au, 3.6) : au;
		float tracks = smoothstep(0.35, 0.0, abs(track_c - lane_w * 0.28)) + smoothstep(0.35, 0.0, abs(track_c - lane_w * 0.72));
		col *= 1.0 - tracks * 0.12;
		rough = 0.82 - n3 * 0.08;
		// markings
		float m = 0.0;
		vec3 mcol = vec3(0.92, 0.92, 0.88);
		if (road_type != 2) {
			m = max(m, line_mask(au, half_width - 0.3, 0.15));
		}
		if (road_type == 0) {
			m = max(m, line_mask(u, 0.0, 0.13) * dash(v, 4.0, 8.0));
		} else if (road_type == 1) {
			m = max(m, line_mask(au, 0.15, 0.12));
			m = max(m, line_mask(au, 3.75, 0.13) * dash(v, 6.0, 9.0));
		}
		m *= 0.75 + 0.25 * n2;
		col = mix(col, mcol, m * paved);
		rough = mix(rough, 0.6, m);
		// gravel shoulder outside the paved width
		vec3 sh = vec3(0.36, 0.34, 0.3) * (0.75 + 0.4 * n3);
		col = mix(sh, col, paved);
		rough = mix(0.95, rough, paved);
	} else {
		vec3 base = road_type == 3 ? vec3(0.42, 0.31, 0.2) : (road_type == 4 ? vec3(0.5, 0.47, 0.42) : vec3(0.78, 0.6, 0.38));
		col = base * (0.75 + 0.35 * n3) * (0.88 + 0.24 * n1);
		// wheel ruts
		float ruts = smoothstep(0.4, 0.0, abs(au - half_width * 0.45));
		col *= 1.0 - ruts * 0.18;
		// grassy crown on dirt tracks
		if (road_type == 3) {
			float crown = (1.0 - smoothstep(0.3, 0.7, au)) * smoothstep(0.45, 0.7, n2);
			col = mix(col, vec3(0.25, 0.33, 0.12), crown * 0.6);
		}
		col = mix(col, col * 0.85 + vec3(0.03), 1.0 - paved);
		rough = 0.95;
	}
	// wet: darker, glossy, puddles in the tracks
	float wet = wetness;
	float puddle = smoothstep(0.55, 0.75, n1 + n2 * 0.3) * wet;
	col *= mix(1.0, 0.55, wet);
	rough = mix(rough, 0.12, max(wet * 0.7, puddle));
	// snow on the verges and lightly on the road
	col = mix(col, vec3(0.9, 0.92, 0.96), snow_cover * mix(0.25, 0.8, 1.0 - paved) * smoothstep(0.3, 0.7, n2));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4 + wet * 0.3;
}
