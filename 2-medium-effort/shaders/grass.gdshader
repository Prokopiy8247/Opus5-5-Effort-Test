shader_type spatial;
render_mode cull_disabled;
// Grass clumps: colour from instance (terrain tint), upward normal on both faces, gentle wind sway.
varying vec3 tint;
void vertex() {
	tint = COLOR.rgb;
	float h = VERTEX.y;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.x += sin(TIME * 1.7 + wp.x * 0.3 + wp.z * 0.2) * 0.06 * h;
	VERTEX.z += cos(TIME * 1.3 + wp.z * 0.3) * 0.05 * h;
}
void fragment() {
	ALBEDO = tint;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
