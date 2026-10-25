shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;
// Hot streak for impact sparks. The particle transform is aligned to its velocity
// (GPUParticles3D.transform_align), so the quad's +Y (UV.y = 0) is the leading head.

uniform float intensity = 6.0;

void fragment() {
	float across = 1.0 - smoothstep(0.0, 1.0, abs(UV.x * 2.0 - 1.0));
	float t = UV.y;
	float along = smoothstep(0.0, 0.1, t) * pow(1.0 - t, 1.6);
	float m = across * along;
	ALBEDO = COLOR.rgb * intensity;
	ALPHA = clamp(m * COLOR.a * 1.6, 0.0, 1.0);
}
