shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Windows and lamps that light up at night (global night_amount set by the environment).
// mode 0 = building window (random lit/unlit per window cell), 1 = lamp / beacon (always on at night).

uniform int mode = 0;
uniform vec3 day_color : source_color = vec3(0.08, 0.12, 0.16);
uniform vec3 glow_color : source_color = vec3(1.0, 0.78, 0.45);
uniform float glow = 2.5;
global uniform float night_amount;

varying vec3 wpos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float lit = 1.0;
	if (mode == 0) {
		lit = step(0.38, hash13(floor(wpos * 0.9)));
	}
	ALBEDO = day_color;
	METALLIC = mode == 0 ? 0.3 : 0.0;
	ROUGHNESS = mode == 0 ? 0.08 : 0.3;
	float n = smoothstep(0.25, 0.7, night_amount);
	EMISSION = glow_color * glow * lit * (mode == 0 ? n : 0.15 + n);
}
