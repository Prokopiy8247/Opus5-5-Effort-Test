shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural buildings, rocks and roadside props. COLOR.rgb = albedo, COLOR.a = surface code:
//   0 night light (lamps), .12 always-on light (screens, neon), .25 tinted gloss paint,
//   .5 window glass (individually lit at night), .75 metal, .9 tinted matte (cloth waves where UV.x > 0), 1 matte.
// INSTANCE_CUSTOM (MultiMesh): rgb = tint for the tinted codes (all zero = none), a = seed.

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float wind_strength = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec4 window_glow : source_color = vec4(1.0, 0.74, 0.42, 1.0);

varying vec3 v_wpos;
varying vec3 v_tint;
varying float v_seed;
varying float v_base;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x);
	float b = mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x);
	float c = mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x);
	float d = mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void vertex() {
	if (UV.x > 0.0) {
		float ph = INSTANCE_CUSTOM.a * 6.2831;
		VERTEX.z += sin(TIME * 3.4 + VERTEX.x * 1.3 + VERTEX.y * 0.9 + ph) * 0.16 * UV.x * wind_strength;
		VERTEX.y += sin(TIME * 2.3 + VERTEX.x * 0.8 + ph) * 0.04 * UV.x * wind_strength;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_tint = dot(INSTANCE_CUSTOM.rgb, vec3(1.0)) > 0.001 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	v_seed = INSTANCE_CUSTOM.a;
	v_base = MODEL_MATRIX[3].y;
}

void fragment() {
	vec3 col = COLOR.rgb;
	float code = COLOR.a;
	float rough = 0.86;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float n = vnoise(v_wpos * 0.9) * 0.6 + vnoise(v_wpos * 0.21) * 0.4;
	if (code < 0.06) {
		emit = col * (0.04 + night * 3.0);
		rough = 0.35;
	} else if (code < 0.18) {
		emit = col * (0.9 + night * 0.7);
		rough = 0.35;
	} else if (code < 0.37) {
		col *= v_tint;
		rough = 0.32;
	} else if (code < 0.62) {
		float lit = step(0.45, hash3(floor(COLOR.rgb * 4000.0) + vec3(v_seed * 17.0)));
		emit = window_glow.rgb * lit * night * 1.8;
		rough = 0.08;
		metal = 0.2;
	} else if (code < 0.82) {
		rough = 0.36;
		metal = 0.7;
		col *= 0.94 + n * 0.12;
	} else if (code < 0.95) {
		col *= v_tint * (0.94 + n * 0.12);
	} else {
		col *= 0.86 + n * 0.28;
	}
	float ao = mix(0.7, 1.0, smoothstep(-0.3, 1.6, v_wpos.y - v_base));
	col *= ao;
	col *= 1.0 - wetness * 0.25;
	ALBEDO = col;
	ROUGHNESS = mix(rough, rough * 0.45, wetness);
	METALLIC = metal;
	EMISSION = emit;
}
