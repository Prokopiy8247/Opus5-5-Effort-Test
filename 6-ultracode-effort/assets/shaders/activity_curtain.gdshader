shader_type spatial;
// Light curtain spanning an activity gate. Additive, brightest at road level, with a slow upward sweep.
// `flash` (per instance) lights the whole curtain when the gate is passed; `dim` fades inactive gates.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float intensity = 0.5;
instance uniform float flash = 0.0;
instance uniform float dim = 1.0;

void fragment() {
	float y = 1.0 - UV.y;
	float base = pow(1.0 - y, 2.4);
	float edge = smoothstep(0.0, 0.05, UV.x) * smoothstep(1.0, 0.95, UV.x);
	float lines = 0.6 + 0.4 * sin(UV.x * 120.0);
	float sweep = smoothstep(0.82, 1.0, sin(y * 7.0 - TIME * 2.6)) * (1.0 - y);
	float a = (base * 0.8 * lines + sweep * 0.35) * intensity * dim;
	a += flash * (0.25 + 0.75 * (1.0 - y)) * 0.9;
	ALBEDO = color.rgb;
	ALPHA = clamp(a * edge, 0.0, 1.0);
}
