shader_type spatial;
// Glossy vinyl for the festival inflatable arches. UV.x = metres along the tube, UV.y = around the tube
// (0.25 faces the approaching driver, 0.75 the other side).
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform float chamber = 1.5;
instance uniform float glow = 0.0;

void fragment() {
	float ch = fract(UV.x / chamber);
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(ch - 0.5));
	float face = abs(fract(UV.y * 2.0) - 0.5);
	float stripe = 1.0 - smoothstep(0.055, 0.075, face);
	// Diagonal festival pattern on the stripe.
	float diag = step(0.5, fract((UV.x + UV.y * 3.0) * 1.6));
	vec3 accent = mix(accent_color.rgb, base_color.rgb * 0.35 + accent_color.rgb * 0.65, diag * 0.35);
	vec3 col = mix(base_color.rgb, accent, stripe);
	col *= 1.0 - seam * 0.28;
	ALBEDO = col;
	ROUGHNESS = mix(0.26, 0.42, seam);
	SPECULAR = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base_color.rgb * (0.06 + glow * 1.4) + base_color.rgb * fres * 0.18;
}
