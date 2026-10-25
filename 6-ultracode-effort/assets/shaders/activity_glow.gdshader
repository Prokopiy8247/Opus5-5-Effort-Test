shader_type spatial;
// Soft additive glow. mode 0: camera-facing radial sprite (QuadMesh). mode 1: vertical light beam
// (open CylinderMesh, fades with height and at grazing angles). mode 2: pulsing ring lying on the ground.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.75, 0.2, 1.0);
uniform int mode = 0;
uniform float strength = 1.0;
instance uniform float pulse = 0.0;

void vertex() {
	if (mode == 0) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	float a;
	if (mode == 0) {
		float d = length(UV - vec2(0.5)) * 2.0;
		a = pow(max(1.0 - d, 0.0), 2.2);
		a *= 0.8 + 0.2 * sin(TIME * 3.0);
	} else if (mode == 1) {
		float h = UV.y;
		a = pow(h, 1.6) * pow(abs(dot(NORMAL, VIEW)), 1.5);
	} else {
		float d = length(UV - vec2(0.5)) * 2.0;
		float r = 0.62 + 0.2 * fract(TIME * 0.45);
		a = (1.0 - smoothstep(0.0, 0.07, abs(d - 0.8))) * 0.9 + (1.0 - smoothstep(0.0, 0.05, abs(d - r))) * (1.0 - fract(TIME * 0.45));
		a *= step(d, 1.0);
	}
	ALBEDO = color.rgb;
	ALPHA = clamp(a * (strength + pulse), 0.0, 1.0);
}
