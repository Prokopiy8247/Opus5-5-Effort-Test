shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;
// Snow flakes / wind-blown dust: soft round camera-facing sprites, slightly stretched along their motion
// relative to the camera (TRANSFORM[0]); size in TRANSFORM[1].x.

uniform vec3 tint = vec3(0.95, 0.96, 1.0);
uniform float opacity = 0.8;
uniform float softness = 0.6;
uniform float near_fade = 0.6;
uniform float far_fade = 22.0;

varying float v_fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = MODEL_MATRIX[1].x;
	vec3 vc = (VIEW_MATRIX * vec4(center, 1.0)).xyz;
	vec3 axis = (VIEW_MATRIX * vec4(MODEL_MATRIX[0].xyz, 0.0)).xyz;
	vec2 a2 = axis.xy;
	float al = length(a2);
	vec2 dir = al > 0.0001 ? a2 / al : vec2(0.0, 1.0);
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 off = perp * VERTEX.x * s * 2.0 + dir * VERTEX.y * (s * 2.0 + al);
	VERTEX = vc + vec3(off, 0.0);
	float dist = -vc.z;
	v_fade = smoothstep(near_fade, near_fade * 3.0, dist) * (1.0 - smoothstep(far_fade * 0.7, far_fade, dist));
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	ALBEDO = tint;
	ALPHA = clamp(opacity * (1.0 - smoothstep(1.0 - softness, 1.0, d)) * v_fade, 0.0, 1.0);
}
