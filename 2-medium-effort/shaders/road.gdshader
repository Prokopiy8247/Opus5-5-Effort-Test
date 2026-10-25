shader_type spatial;
// Procedural road surface: UV.x = metres from centreline, UV.y = metres along the road.
// kind: 0 asphalt, 1 concrete, 2 dirt, 3 gravel, 4 junction pad (asphalt, no markings)
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float lane_w = 3.3;
uniform float half_w = 4.3;
uniform int kind = 0;
uniform bool double_center = false;
uniform bool yellow_center = false;
global uniform float wetness;

float line(float x, float c, float w) {
	float d = abs(x - c);
	float aa = fwidth(x) * 1.2;
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, d);
}

void fragment() {
	vec2 uv = UV;
	float n1 = texture(noise_tex, uv * 0.11).r;
	float n2 = texture(noise_tex, uv * 0.9).r;
	float n3 = texture(noise_tex, uv * vec2(0.02, 0.004)).r;
	vec3 col;
	float rough = 0.85;
	float x = uv.x;
	float ax = abs(x);
	if (kind == 0 || kind == 4) {
		col = vec3(0.16, 0.16, 0.17) * (0.8 + 0.4 * n2) * (0.9 + 0.25 * n3);
		// tyre-polished wheel tracks
		float tr = line(ax, lane_w * 0.5 - 0.85, 0.7) + line(ax, lane_w * 0.5 + 0.85, 0.7);
		col *= 1.0 - 0.12 * clamp(tr, 0.0, 1.0);
		// verge outside the shoulder: gravel shoulder
		float verge = smoothstep(lane_w + 0.05, lane_w + 0.3, ax);
		if (kind == 4) verge = 0.0;
		vec3 shoulder = vec3(0.22, 0.21, 0.2) * (0.8 + 0.4 * n2);
		col = mix(col, shoulder, verge * 0.35);
		if (kind == 0) {
			float m = 0.0;
			m += line(ax, lane_w - 0.12, 0.16);
			float dash = step(fract(uv.y / 12.0), 0.35);
			vec3 mc = vec3(0.92);
			if (double_center) {
				m += line(x, -0.12, 0.1) + line(x, 0.12, 0.1);
			} else {
				m += line(x, 0.0, 0.14) * dash;
			}
			float cm = (double_center ? line(x, -0.12, 0.1) + line(x, 0.12, 0.1) : line(x, 0.0, 0.14) * dash);
			vec3 cc = (yellow_center || double_center) ? vec3(0.95, 0.72, 0.15) : vec3(0.92);
			col = mix(col, vec3(0.92), clamp(line(ax, lane_w - 0.12, 0.16), 0.0, 1.0) * (0.75 + 0.25 * n2));
			col = mix(col, cc, clamp(cm, 0.0, 1.0) * (0.75 + 0.25 * n2));
			rough = mix(0.8, 0.6, clamp(m, 0.0, 1.0));
		}
		// beyond the deck edge (embankment skirt)
		col = mix(col, vec3(0.3, 0.32, 0.2) * (0.7 + 0.5 * n2), smoothstep(half_w + 0.1, half_w + 0.9, ax) * (kind == 4 ? 0.0 : 1.0));
	} else if (kind == 1) {
		col = vec3(0.55, 0.54, 0.5) * (0.85 + 0.3 * n2);
		float joint = line(fract(uv.y / 6.0) * 6.0, 0.0, 0.06) + line(x, 0.0, 0.05);
		col *= 1.0 - 0.35 * clamp(joint, 0.0, 1.0);
		col = mix(col, vec3(0.92), line(ax, lane_w - 0.12, 0.16));
		rough = 0.9;
	} else {
		vec3 base = kind == 2 ? vec3(0.42, 0.31, 0.2) : vec3(0.5, 0.46, 0.4);
		col = base * (0.7 + 0.6 * n2) * (0.85 + 0.3 * n1);
		// ruts and grass crown
		float rut = line(ax, lane_w * 0.45, 0.9);
		col *= 1.0 - 0.15 * rut;
		float crown = 1.0 - smoothstep(0.3, 0.9, ax);
		col = mix(col, vec3(0.3, 0.38, 0.16), crown * 0.45 * step(0.45, n2));
		col = mix(col, vec3(0.32, 0.38, 0.18) * (0.7 + 0.5 * n2), smoothstep(half_w + 0.1, half_w + 1.0, ax));
		rough = 0.97;
	}
	// wet look: darker, glossier, puddles in ruts
	float wet = wetness * (kind >= 2 && kind != 4 ? 0.6 : 1.0);
	float puddle = smoothstep(0.55, 0.7, n1) * wet;
	col *= mix(1.0, 0.55, wet);
	rough = mix(rough, 0.12, max(wet * 0.6, puddle));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5 + 0.3 * wet;
}
