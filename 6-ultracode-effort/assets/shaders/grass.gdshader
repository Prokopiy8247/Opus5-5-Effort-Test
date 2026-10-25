shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Grass tufts streamed around the camera. The base colour is derived from the same noise textures
// and palette as terrain.gdshader, so tufts grow out of the ground they stand on.
// COLOR.rgb = blade brightness, COLOR.a = 0 root .. 1 tip.
// INSTANCE_CUSTOM = (vale, highlands, mesa) region weights (coast = remainder), seed in .a.

uniform sampler2D noise_large : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
uniform float fade_start = 65.0;
uniform float fade_end = 100.0;
uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_col;
varying float v_tip;
varying vec3 v_n;

vec3 ground_color(vec2 xz, vec4 rw) {
	float nl = textureLod(noise_large, xz * 0.0011, 0.0).r;
	float nm = textureLod(noise_large, xz * 0.0073, 0.0).r;
	float nd = textureLod(noise_detail, xz * 0.09, 0.0).r;
	vec3 meadow = mix(vec3(0.20, 0.33, 0.09), vec3(0.36, 0.42, 0.14), clamp(nl * 1.2 - 0.1 + nd * 0.3, 0.0, 1.0));
	vec3 alpine = mix(vec3(0.24, 0.30, 0.14), vec3(0.40, 0.40, 0.24), clamp(nm + nd * 0.3 - 0.2, 0.0, 1.0));
	vec3 scrub = mix(vec3(0.45, 0.42, 0.2), vec3(0.6, 0.5, 0.26), nd);
	vec3 coastal = mix(vec3(0.30, 0.40, 0.16), vec3(0.45, 0.47, 0.25), nm);
	return (meadow * rw.r + alpine * rw.g + scrub * rw.b + coastal * rw.a) / max(rw.r + rw.g + rw.b + rw.a, 0.001);
}

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(base.xz, cam.xz);
	float s = 1.0 - smoothstep(fade_start, fade_end, d);
	float tip = COLOR.a;
	float ph = INSTANCE_CUSTOM.a * 6.2831;
	vec3 off = VERTEX - base;
	float w = wind_strength * tip * (0.55 + 0.45 * sin(TIME * 1.9 + base.x * 0.21 + base.z * 0.17 + ph));
	off.xz += wind_dir * w * 0.14 + vec2(sin(TIME * 3.3 + ph), cos(TIME * 2.7 + ph)) * 0.025 * tip * wind_strength;
	VERTEX = base + off * s;
	vec4 rw = vec4(INSTANCE_CUSTOM.rgb, max(1.0 - INSTANCE_CUSTOM.r - INSTANCE_CUSTOM.g - INSTANCE_CUSTOM.b, 0.0));
	v_col = ground_color(base.xz, rw);
	v_tip = tip;
	v_n = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.8));
}

void fragment() {
	vec3 col = v_col * mix(0.6, 1.2, v_tip) * COLOR.rgb;
	col = mix(col, vec3(0.86, 0.9, 0.95), snow_cover * v_tip * 0.6);
	col *= 1.0 - wetness * 0.2;
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_n, 0.0)).xyz);
	ROUGHNESS = mix(0.9, 0.6, wetness);
	SPECULAR = 0.15;
	BACKLIGHT = col * 0.35;
}
