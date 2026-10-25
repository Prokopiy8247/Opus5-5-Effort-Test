shader_type spatial;
render_mode cull_disabled;
// UV.x = signed lateral metres from road centre, UV.y = metres along the road
uniform float half_width = 4.5;
uniform int kind = 0; // 0 asphalt, 1 concrete, 2 dirt, 3 gravel, 4 sand
uniform bool multi_lane = false;
uniform vec3 base_color : source_color = vec3(0.16, 0.16, 0.17);
uniform vec3 shoulder_color : source_color = vec3(0.35, 0.32, 0.28);
global uniform float wetness;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float x = UV.x; float y = UV.y; float ax = abs(x);
	float grain = vnoise(vec2(x, y) * 3.0) * 0.5 + vnoise(vec2(x, y) * 17.0) * 0.5;
	vec3 col = base_color * (0.85 + 0.3 * grain);
	float rough = 0.85;
	if (kind <= 1) {
		// wear in the wheel tracks
		float track = smoothstep(0.6, 0.0, abs(mod(ax, half_width * 0.5) - half_width * 0.25));
		col *= 1.0 - 0.08 * track;
		if (kind == 1) { float seam = step(0.97, fract(y / 6.0)); col *= 1.0 - 0.25 * seam; }
		vec3 paint = vec3(0.92, 0.92, 0.88);
		float edge = step(abs(ax - (half_width - 0.35)), 0.09);
		float centre = multi_lane ? step(ax, 0.22) * (step(ax, 0.06) + step(0.14, ax)) : step(ax, 0.08) * step(fract(y / 9.0), 0.4);
		vec3 centre_col = multi_lane ? vec3(0.95, 0.78, 0.15) : paint;
		float lane = multi_lane ? step(abs(ax - half_width * 0.5), 0.08) * step(fract(y / 12.0), 0.35) : 0.0;
		col = mix(col, paint, max(edge, lane));
		col = mix(col, centre_col, centre);
		if (ax > half_width) { col = shoulder_color * (0.8 + 0.4 * grain); rough = 0.95; }
	} else {
		float rut = smoothstep(0.5, 0.0, abs(ax - half_width * 0.45));
		col = base_color * (0.75 + 0.5 * grain);
		col *= 1.0 - 0.18 * rut;
		col = mix(col, shoulder_color, smoothstep(half_width - 1.2, half_width + 0.5, ax));
		rough = 1.0;
	}
	float wet = wetness * (kind <= 1 ? 1.0 : 0.6);
	col *= 1.0 - 0.45 * wet;
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.12, wet);
	SPECULAR = 0.5;
}
