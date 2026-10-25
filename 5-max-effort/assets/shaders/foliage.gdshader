shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Project-owned foliage: wind sway by height and world position, per-instance tint variation,
// soft back-light translucency, distance-based dither fade near the visibility range end.

uniform vec3 base_color : source_color = vec3(0.17, 0.34, 0.09);
uniform float sway = 0.12;
uniform float sway_height = 6.0;
uniform float tint_amount = 0.22;
uniform float translucency = 0.35;
global uniform float wind_strength;
global uniform float wetness;

varying float v_tint;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(sway_height, 0.1), 0.0, 1.0);
	float t = TIME * (0.9 + wind_strength * 1.4);
	float phase = dot(origin.xz, vec2(0.13, 0.17));
	float s = sin(t + phase) * 0.6 + sin(t * 2.3 + phase * 1.7) * 0.25;
	float amp = sway * (0.35 + wind_strength * 1.3) * h * h;
	VERTEX.x += s * amp;
	VERTEX.z += cos(t * 0.8 + phase) * amp * 0.5;
	v_tint = hash12(origin.xz);
}

void fragment() {
	vec3 col = base_color * (1.0 - tint_amount * 0.5 + v_tint * tint_amount);
	col = mix(col, col * vec3(1.05, 0.95, 0.75), step(0.8, v_tint) * 0.4);
	col *= COLOR.rgb;
	col *= 1.0 - wetness * 0.15;
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.45, wetness);
	SPECULAR = 0.25;
	BACKLIGHT = col * translucency;
}
