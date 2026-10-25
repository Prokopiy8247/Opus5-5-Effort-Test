shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Project-owned road surface: asphalt / concrete / gravel / dirt / sand with procedural grain,
// lane markings from the lateral UV, tyre wear, wet sheen and puddles.
// UV.x = lateral offset in metres from the centre line, UV.y = distance along the road (m).

uniform int surface = 0;          // 0 asphalt, 1 concrete, 2 gravel, 3 dirt, 4 sand
uniform int marking = 1;          // 0 none, 1 two-lane dashed centre, 2 two-lane solid centre, 3 dual carriageway, 4 village dashed
uniform float half_width = 4.6;
uniform float lane_width = 3.5;
uniform float median = 0.0;
uniform float shoulder = 1.1;
uniform vec3 base_color : source_color = vec3(0.16, 0.16, 0.17);
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
global uniform float wetness;

float line(float x, float center, float w) {
	return 1.0 - smoothstep(w * 0.5 - 0.015, w * 0.5 + 0.015, abs(x - center));
}

float dashed(float v, float len, float gap) {
	return step(fract(v / (len + gap)), len / (len + gap));
}

void fragment() {
	float x = UV.x;
	float v = UV.y;
	vec2 wuv = vec2(x, v);
	float n1 = texture(noise_a, wuv * vec2(0.9, 0.25)).r;
	float n2 = texture(noise_b, wuv * vec2(0.08, 0.02)).r;
	float grain = texture(noise_a, wuv * vec2(4.0, 4.0)).r;
	vec3 col = base_color;
	float rough = 0.85;
	float ax = abs(x);
	float paved_edge = half_width;
	if (surface == 0 || surface == 1) {
		col *= 0.85 + n1 * 0.25 + grain * 0.12;
		col = mix(col, col * 0.75, smoothstep(0.55, 0.8, n2) * 0.6);
		// tyre wear: darker, smoother wheel paths in each lane
		float lanes_c = (marking == 3) ? (median * 0.5 + lane_width * 0.5) : lane_width * 0.5;
		float wear = exp(-pow((ax - lanes_c - 0.9) / 0.35, 2.0)) + exp(-pow((ax - lanes_c + 0.9) / 0.35, 2.0));
		col *= 1.0 - wear * 0.08;
		if (surface == 1) {
			col *= 1.35;
			col *= 0.95 + 0.05 * step(0.04, fract(v / 6.0));
		}
		// verge beyond the paved edge
		if (ax > paved_edge) {
			col = mix(vec3(0.33, 0.3, 0.25), vec3(0.4, 0.37, 0.3), n1);
			rough = 0.95;
		}
		vec3 white = vec3(0.86, 0.86, 0.82);
		vec3 yellow = vec3(0.86, 0.7, 0.2);
		float m = 0.0;
		float my = 0.0;
		float edge_x = half_width - shoulder - 0.08;
		if (marking == 1) {
			m += line(x, 0.0, 0.12) * dashed(v, 3.0, 9.0);
			m += line(ax, edge_x, 0.14);
		} else if (marking == 2) {
			my += line(x, -0.1, 0.1) + line(x, 0.1, 0.1);
			m += line(ax, edge_x, 0.14);
		} else if (marking == 3) {
			my += line(ax, median * 0.5 + 0.12, 0.12);
			m += line(ax, median * 0.5 + lane_width, 0.14) * dashed(v, 4.0, 8.0);
			m += line(ax, median * 0.5 + 2.0 * lane_width + 0.1, 0.18);
			if (ax < median * 0.5) {
				col = vec3(0.45, 0.45, 0.44) * (0.9 + n1 * 0.2);
			}
		} else if (marking == 4) {
			m += line(x, 0.0, 0.1) * dashed(v, 2.0, 6.0);
		}
		m = clamp(m, 0.0, 1.0) * (0.85 + grain * 0.15) * step(ax, paved_edge);
		my = clamp(my, 0.0, 1.0) * (0.85 + grain * 0.15);
		col = mix(col, white, m);
		col = mix(col, yellow, my);
		rough = mix(rough, 0.6, max(m, my));
	} else {
		// loose surfaces with ruts
		vec3 c0 = surface == 2 ? vec3(0.5, 0.47, 0.42) : (surface == 3 ? vec3(0.43, 0.32, 0.22) : vec3(0.82, 0.72, 0.52));
		col = c0 * (0.78 + n1 * 0.3 + grain * 0.2);
		float ruts = exp(-pow((ax - 0.95) / 0.32, 2.0));
		col *= 1.0 - ruts * 0.18;
		if (surface == 2) {
			col *= 0.9 + step(0.82, grain) * 0.25;
		}
		col = mix(col, col * 0.8, smoothstep(paved_edge - 0.6, paved_edge + 0.4, ax));
		rough = 0.97;
	}
	// wet look: darker with reflective puddles in low spots
	float puddle = smoothstep(0.62, 0.72, n2) * wetness;
	col *= 1.0 - wetness * 0.35;
	rough = mix(rough, 0.18, wetness * 0.75);
	rough = mix(rough, 0.03, puddle);
	col = mix(col, col * 0.6, puddle);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
