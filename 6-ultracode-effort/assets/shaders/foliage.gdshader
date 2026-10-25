shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Low-poly vegetation (trees, bushes, hedges, reeds, flowers). Solid, alpha-free.
// COLOR.rgb = albedo, COLOR.a = foliage mask (1 leaves, 0 bark) unless leaf_override >= 0 (kit meshes).
// INSTANCE_CUSTOM (MultiMesh): rgb = foliage tint (all zero = none), a = per-instance seed.
// Height-driven wind sway + leaf flutter, per-instance colour variation, snow and wetness response.
// Distance LOD (set on the dressing tree / hedge materials): lod.x = 1 near model (fades out), 2 far stand-in
// (fades in), between lod.y and lod.z metres from the main camera to each instance's origin. The two use
// complementary screen-space dither, so a tree is drawn exactly once and the swap moves per tree, not per chunk.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_texture = false;
uniform float leaf_override = -1.0;
uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float sway_height = 9.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec3 lod = vec3(0.0);

varying vec3 v_tint;
varying float v_leaf;
varying float v_var;
varying float v_up;
varying float v_hide;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float leaf = leaf_override >= 0.0 ? leaf_override : COLOR.a;
	float seed = INSTANCE_CUSTOM.a;
	float h = max(VERTEX.y - base.y, 0.0);
	float ph = seed * 6.2831 + dot(base.xz, vec2(0.021, 0.017));
	float gust = 0.65 + 0.35 * sin(TIME * 0.31 + base.x * 0.0037 - base.z * 0.0029);
	float bend = pow(h / sway_height, 1.5) * wind_strength * gust;
	vec2 sway = wind_dir * (0.09 + 0.08 * sin(TIME * 1.15 + ph)) * bend;
	sway += vec2(-wind_dir.y, wind_dir.x) * 0.035 * sin(TIME * 0.83 + ph * 1.7) * bend;
	VERTEX.xz += sway;
	float fl = leaf * wind_strength * clamp(h * 0.5, 0.0, 1.0) * 0.04;
	VERTEX += vec3(sin(TIME * 3.9 + VERTEX.y * 1.7 + ph), 0.5 * sin(TIME * 3.1 + VERTEX.x * 1.9), sin(TIME * 4.3 + VERTEX.z * 1.6 + ph)) * fl;
	v_tint = dot(INSTANCE_CUSTOM.rgb, vec3(1.0)) > 0.001 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	v_leaf = leaf;
	v_var = fract(seed * 13.17) - 0.5;
	v_up = NORMAL.y;
	v_hide = 0.0;
	if (lod.x > 0.5) {
		// main camera even in shadow passes, so shadows fade with the model
		float t = clamp((distance(base, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) - lod.y) / max(lod.z - lod.y, 0.001), 0.0, 1.0);
		v_hide = lod.x < 1.5 ? t : 1.0 - t;
		if (v_hide > 0.999) {
			VERTEX = base;
		}
	}
}

void fragment() {
	if (v_hide > 0.001) {
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if ((lod.x < 1.5 ? n : 0.99999 - n) < v_hide) {
			discard;
		}
	}
	vec3 col = COLOR.rgb * albedo.rgb;
	if (use_texture) {
		col *= texture(albedo_tex, UV).rgb;
	}
	col *= mix(vec3(1.0), v_tint, v_leaf);
	col *= 1.0 + v_var * 0.14 * v_leaf;
	float snow = snow_cover * smoothstep(0.35, 0.8, v_up) * (0.4 + 0.6 * v_leaf);
	col = mix(col, vec3(0.86, 0.9, 0.95), snow);
	col *= 1.0 - wetness * 0.22;
	ALBEDO = col;
	ROUGHNESS = mix(0.88, 0.55, wetness);
	SPECULAR = 0.22 + wetness * 0.2;
	BACKLIGHT = col * 0.3 * v_leaf;
}
