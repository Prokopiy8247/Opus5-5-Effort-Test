shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
// Car glass: darker, reflective from outside; lightly tinted when seen from the cockpit (back faces).
global uniform float wetness;
void fragment() {
	ALBEDO = vec3(0.05, 0.07, 0.09);
	METALLIC = 0.6;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALPHA = FRONT_FACING ? clamp(0.62 + fres * 0.3, 0.0, 0.95) : 0.14;
}
