shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Tunnel lining: UV.x = 0..1 around the arch profile, UV.y = metres along the tunnel.
// Emissive lamp strips every 18 m along the crown, darker grime near the road.

uniform vec3 lamp_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float lamp_energy = 6.0;

void fragment() {
	float x = UV.x;
	float along = UV.y;
	float crown = 1.0 - smoothstep(0.03, 0.06, abs(x - 0.5));
	float lamp = crown * step(fract(along / 18.0), 0.18);
	float panel = step(0.02, fract(along / 6.0)) * 0.08 + 0.92;
	vec3 base = vec3(0.62, 0.6, 0.56) * panel;
	float grime = 1.0 - smoothstep(0.0, 0.18, min(x, 1.0 - x));
	base = mix(base, vec3(0.25, 0.24, 0.22), grime * 0.7);
	// reflective tiles on the lower walls
	float tiles = step(0.05, min(x, 1.0 - x)) * (1.0 - step(0.22, min(x, 1.0 - x)));
	base = mix(base, vec3(0.85, 0.85, 0.82), tiles * 0.6);
	ALBEDO = base;
	ROUGHNESS = mix(0.85, 0.35, tiles);
	EMISSION = lamp_color * lamp * lamp_energy;
}
