shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Grass tufts streamed around the camera. The base colour is derived from the same noise textures
// and palette as terrain.gdshader, so tufts grow out of the ground they stand on.
// COLOR.rgb = blade brightness, COLOR.a = 0 root .. 1 tip.
// INSTANCE_CUSTOM = (vale, highlands, mesa) region weights (coast = remainder); .a = forest level (8 steps)
// + random seed in the fractional part (see dressing_rules.gd build_grass).

uniform sampler2D noise_large : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
uniform float fade_start = 65.0;
uniform float fade_end = 100.0;
uniform float thin_start = 30.0;     // beyond this distance a growing share of tufts is dropped
uniform vec3 ground_grass = vec3(0.3, 0.4, 0.15);
uniform vec3 ground_sand = vec3(0.6, 0.5, 0.35);
uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_col;
varying float v_tip;
varying vec3 v_n;

// Same ground colour model as terrain.gdshader (texture average x regional tint), but without
// texture fetches: ground_grass / ground_sand are the average colours of the terrain textures
// (set by dressing_materials.gd), so the tufts follow whatever the ground textures look like.
vec3 ground_color(vec2 xz, vec4 rw) {
	float nl = textureLod(noise_large, xz * 0.0011, 0.0).r;
	float nm = textureLod(noise_large, xz * 0.0073, 0.0).r;
	float nd = textureLod(noise_detail, xz * 0.09, 0.0).r;
	vec3 meadow = ground_grass * mix(vec3(0.75, 0.9, 0.6), vec3(1.05, 1.0, 0.8), clamp(nl * 1.2 - 0.1 + nd * 0.3, 0.0, 1.0));
	vec3 alpine = ground_grass * mix(vec3(0.8, 0.85, 0.9), vec3(1.1, 1.0, 1.3), clamp(nm + nd * 0.3 - 0.2, 0.0, 1.0));
	// Mesa: dry tufts on sand flats (greener than the sand, like the scrub they are).
	vec3 scrub = mix(ground_sand * mix(vec3(1.0, 0.78, 0.55), vec3(1.15, 0.9, 0.65), clamp(nm + nd * 0.4 - 0.2, 0.0, 1.0)), ground_grass * vec3(1.2, 1.0, 0.6), 0.45);
	vec3 coastal = ground_grass * mix(vec3(0.85, 0.95, 0.85), vec3(1.1, 1.05, 1.2), nm);
	return (meadow * rw.r + alpine * rw.g + scrub * rw.b + coastal * rw.a) / max(rw.r + rw.g + rw.b + rw.a, 0.001);
}

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(base.xz, cam.xz);
	float lv = floor(INSTANCE_CUSTOM.a * 8.0);
	float seed = fract(INSTANCE_CUSTOM.a * 8.0);
	float forest = lv / 7.0;
	// Fade out toward the ring edge, and thin the far tufts (random share by seed, shrunk not popped).
	float keep = 1.0 - 0.7 * smoothstep(thin_start, fade_end, d);
	float s = (1.0 - smoothstep(fade_start, fade_end, d)) * clamp((keep + 0.15 - seed) * 6.0, 0.0, 1.0);
	float tip = COLOR.a;
	float ph = seed * 6.2831;
	vec3 off = VERTEX - base;
	float w = wind_strength * tip * (0.55 + 0.45 * sin(TIME * 1.9 + base.x * 0.21 + base.z * 0.17 + ph));
	off.xz += wind_dir * w * 0.14 + vec2(sin(TIME * 3.3 + ph), cos(TIME * 2.7 + ph)) * 0.025 * tip * wind_strength;
	VERTEX = base + off * s;
	vec4 rw = vec4(INSTANCE_CUSTOM.rgb, max(1.0 - INSTANCE_CUSTOM.r - INSTANCE_CUSTOM.g - INSTANCE_CUSTOM.b, 0.0));
	v_col = ground_color(base.xz, rw);
	// Under the canopy: slightly darker and greener.
	v_col *= mix(vec3(1.0), vec3(0.78, 0.92, 0.7), forest);
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
