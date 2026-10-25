shader_type spatial;
// Festival jump ramp. COLOR.r = 1 on the deck (UV.x across 0..1, UV.y = 0 at the lip .. 1 at the entry):
// dark grippy deck, white edge lines, yellow chevrons pointing at the lip, accent lip band.
// Other faces: diagonal hazard stripes in the accent colour.
render_mode cull_back, diffuse_burley;

uniform vec4 accent : source_color = vec4(0.94, 0.14, 0.12, 1.0);

void fragment() {
	vec3 col;
	if (COLOR.r > 0.5) {
		float x = abs(UV.x - 0.5);
		float chev = step(0.5, fract(UV.y * 5.0 + x * 2.2)) * step(x, 0.32);
		col = mix(vec3(0.13, 0.13, 0.14), vec3(0.98, 0.8, 0.12), chev * 0.9);
		col = mix(col, vec3(0.95, 0.95, 0.93), step(0.44, x));
		col = mix(col, accent.rgb, step(UV.y, 0.07));
		ROUGHNESS = 0.85;
	} else {
		float st = step(0.5, fract((UV.x + UV.y) * 3.0));
		col = mix(accent.rgb, vec3(0.96, 0.96, 0.94), st);
		ROUGHNESS = 0.6;
	}
	ALBEDO = col;
}
