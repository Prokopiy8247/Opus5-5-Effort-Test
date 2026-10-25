shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Skid-mark segment (MultiMesh ring buffer, see scripts/fx/skid_marks.gd).
// INSTANCE_CUSTOM = (birth time, sequence number, alpha at start, alpha at end); COLOR.rgb = mark colour.

uniform float now = 0.0;
uniform float head_seq = 0.0;
uniform float capacity = 4000.0;
uniform float seq_wrap = 1048576.0;
uniform float fade_start = 70.0;
uniform float fade_end = 150.0;

varying vec4 v_color;
varying vec4 v_custom;
varying vec2 v_local;

void vertex() {
	v_color = COLOR;
	v_custom = INSTANCE_CUSTOM;
	v_local = vec2(VERTEX.x + 0.5, VERTEX.z + 0.5);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float across = v_local.x;
	float a = mix(v_custom.z, v_custom.w, clamp(v_local.y, 0.0, 1.0));
	float edge = smoothstep(0.0, 0.16, across) * smoothstep(1.0, 0.84, across);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = vnoise(wp.xz * 2.3) * 0.6 + vnoise(wp.xz * 11.0) * 0.4;
	float tread = 0.88 + 0.12 * sin(across * 6.2831 * 3.5 + 1.0);
	float fade = 1.0 - smoothstep(fade_start, fade_end, now - v_custom.x);
	float seq_age = mod(head_seq - v_custom.y + seq_wrap, seq_wrap);
	fade *= 1.0 - smoothstep(capacity * 0.7, capacity * 0.97, seq_age);
	ALBEDO = v_color.rgb * (0.9 + 0.2 * n);
	ALPHA = clamp(a * 1.7, 0.0, 1.0) * edge * tread * (0.72 + 0.28 * n) * fade;
	ROUGHNESS = 0.72;
	SPECULAR = 0.25;
}
