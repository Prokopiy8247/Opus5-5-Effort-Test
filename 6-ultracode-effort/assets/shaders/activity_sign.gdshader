shader_type spatial;
// Danger-sign board face (QuadMesh): white board, coloured frame, warning triangle with a ramp-and-car
// pictogram, all drawn procedurally. UV (0,0) = top-left.
render_mode cull_back, diffuse_burley;

uniform vec4 frame_color : source_color = vec4(0.92, 0.12, 0.1, 1.0);
uniform vec4 board_color : source_color = vec4(0.97, 0.96, 0.92, 1.0);
uniform float aspect = 1.45;

float sd_tri(vec2 p, float r) {
	const float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) {
		p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	}
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	p.y = -p.y;
	vec3 col = board_color.rgb;
	float frame = step(0.0, sd_box(p, vec2(aspect * 0.5 - 0.05, 0.45)));
	col = mix(col, frame_color.rgb, frame);
	vec2 q = p - vec2(0.0, 0.02);
	float tri = sd_tri(q, 0.33);
	float outer = 1.0 - smoothstep(-0.004, 0.004, tri);
	float inner = 1.0 - smoothstep(-0.004, 0.004, tri + 0.07);
	col = mix(col, frame_color.rgb, outer - inner);
	float ground = step(-0.11, q.y) * step(q.y, -0.095) * step(abs(q.x), 0.17);
	float wedge = step(-0.095, q.y) * step(q.y, -0.095 + (q.x + 0.16) * 0.5) * step(-0.16, q.x) * step(q.x, -0.02);
	float body = 1.0 - step(0.0, sd_box(q - vec2(0.05, 0.02), vec2(0.055, 0.018)) - 0.006);
	float cabin = 1.0 - step(0.0, sd_box(q - vec2(0.045, 0.05), vec2(0.03, 0.014)) - 0.004);
	float ink = clamp(ground + wedge + body + cabin, 0.0, 1.0) * inner;
	col = mix(col, vec3(0.06, 0.06, 0.07), ink);
	ALBEDO = col;
	ROUGHNESS = 0.55;
	EMISSION = col * 0.1;
}
