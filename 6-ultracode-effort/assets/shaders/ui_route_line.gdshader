shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// GPS guide ribbon: UV.x = 0..1 across, UV.y = metres along the whole route (stable while the mesh
// is rebuilt). Soft edges, a bright core and chevrons scrolling in the travel direction. Vertex
// alpha fades the ends; the part under / behind the car is hidden.

uniform vec3 color : source_color = vec3(1.0, 0.3, 0.72);
uniform float energy = 1.35;
uniform vec3 car_pos = vec3(0.0, -10000.0, 0.0);
uniform vec3 car_fwd = vec3(0.0, 0.0, -1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x * 2.0 - 1.0;
	float au = abs(u);
	float along = UV.y;
	float body = 1.0 - smoothstep(0.62, 1.0, au);
	float core = 1.0 - smoothstep(0.0, 0.3, au);
	float phase = fract(along * 0.16 + au * 0.42 - TIME * 0.85);
	float chevron = smoothstep(0.0, 0.07, phase) * (1.0 - smoothstep(0.32, 0.42, phase));
	vec2 d = world_pos.xz - car_pos.xz;
	float ahead = smoothstep(-2.0, 7.0, dot(d, normalize(car_fwd.xz + vec2(1e-4))));
	float dist = length(d);
	float vis = COLOR.a * max(ahead * smoothstep(2.5, 7.0, dist), step(18.0, dist));
	float a = (body * 0.14 + core * 0.12 + chevron * body * 0.62) * vis;
	ALBEDO = color * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
