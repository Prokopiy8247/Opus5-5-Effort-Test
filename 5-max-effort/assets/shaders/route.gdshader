shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// GPS route ribbon: scrolling chevrons, fades with distance from the camera.

uniform vec4 color : source_color = vec4(0.22, 0.86, 0.94, 1.0);

void fragment() {
	float u = UV.x - TIME * 1.6;
	float v = UV.y * 2.0 - 1.0;
	float chev = fract(u - abs(v) * 0.45);
	float shape = smoothstep(0.0, 0.08, chev) * (1.0 - smoothstep(0.42, 0.5, chev));
	float edge = 1.0 - smoothstep(0.75, 1.0, abs(v));
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(250.0, 600.0, dist);
	ALBEDO = color.rgb * 1.6;
	ALPHA = (0.25 + shape * 0.6) * edge * fade * color.a;
}
