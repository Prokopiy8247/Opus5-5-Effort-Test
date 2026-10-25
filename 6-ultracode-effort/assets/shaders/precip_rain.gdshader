shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;
// Rain streak: a thin camera-facing ribbon stretched along the drop's motion relative to the camera
// (vector in TRANSFORM[0] written by precip_particles.gdshader). Faded very close and far away.

uniform vec3 tint = vec3(0.7, 0.75, 0.8);
uniform float opacity = 0.25;

varying float v_fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[0].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(cam - center);
	float w = max(MODEL_MATRIX[1].x, dist * 0.0011);
	vec3 to_cam = (cam - center) / max(dist, 0.001);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
	vec3 wp = center + side * VERTEX.x * 2.0 * w + axis * VERTEX.y;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	v_fade = smoothstep(0.7, 2.5, dist) * (1.0 - smoothstep(16.0, 26.0, dist));
}

void fragment() {
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * 3.14159);
	ALBEDO = tint;
	ALPHA = clamp(opacity * edge * along * v_fade, 0.0, 1.0);
}
