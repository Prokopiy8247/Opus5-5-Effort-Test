shader_type spatial;
render_mode cull_back, diffuse_burley;

// Flat paving strip: UV.x across (0..1), UV.y metres along.

void fragment() {
	float along = UV.y / 1.5;
	float joint = smoothstep(0.46, 0.5, abs(fract(along) - 0.5));
	float edge = smoothstep(0.0, 0.06, min(UV.x, 1.0 - UV.x));
	float tile = floor(along);
	float v = fract(sin(tile * 12.9898) * 43758.5453) * 0.06;
	vec3 base = vec3(0.50, 0.49, 0.47) + v;
	base *= mix(0.78, 1.0, edge);
	base *= mix(1.0, 0.8, joint);
	ALBEDO = base;
	ROUGHNESS = 0.93;
	SPECULAR = 0.2;
}
