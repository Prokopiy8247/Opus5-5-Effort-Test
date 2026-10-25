shader_type spatial;
global uniform float wetness;
global uniform float snow_amount;
varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = vnoise(wpos.xz * 0.35) * 0.45 + vnoise(wpos.xz * 2.1) * 0.35 + vnoise(wpos.xz * 0.05) * 0.2;
	vec3 col = COLOR.rgb * (0.78 + 0.45 * n);
	float s = clamp(snow_amount * smoothstep(0.55, 0.85, wnrm.y) * smoothstep(60.0, 110.0, wpos.y), 0.0, 1.0);
	col = mix(col, vec3(0.9, 0.92, 0.95), s);
	col *= 1.0 - 0.3 * wetness;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.45, wetness);
}
