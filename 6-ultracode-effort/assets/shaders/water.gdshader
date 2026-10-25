shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Sea / river / lake water: scrolling normal maps, depth-based colour and transparency, shoreline foam.

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 shallow_color : source_color = vec3(0.12, 0.42, 0.45);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.2);
uniform vec2 flow = vec2(0.02, 0.01);
uniform float wave_scale = 0.045;
uniform float foam_amount = 1.0;
uniform float roughness_base = 0.04;
uniform float storminess : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wpos.xz * wave_scale + TIME * flow;
	vec2 uv2 = wpos.xz * wave_scale * 2.3 - TIME * flow.yx * 1.7;
	vec3 n1 = texture(normal_a, uv1).rgb;
	vec3 n2 = texture(normal_b, uv2).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.6 + storminess * 1.2;
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float water_depth = scene_depth - (-VERTEX.z);
	float t = clamp(water_depth / 9.0, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, t);
	col = mix(col, col * 0.65 + vec3(0.06, 0.07, 0.08), storminess);
	float foam = (1.0 - smoothstep(0.0, 0.9 + storminess, water_depth)) * foam_amount;
	foam *= 0.6 + 0.4 * sin(TIME * 1.3 + wpos.x * 0.35 + wpos.z * 0.2);
	col = mix(col, vec3(0.9, 0.93, 0.95), clamp(foam, 0.0, 0.8));
	ALBEDO = col;
	ALPHA = clamp(0.55 + t * 0.45 + foam, 0.0, 1.0);
	ROUGHNESS = roughness_base + storminess * 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
