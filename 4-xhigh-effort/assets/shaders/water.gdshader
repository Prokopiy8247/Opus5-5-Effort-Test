shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Project-owned water: depth-tinted colour, shoreline foam, scrolling normal layers.
// flow = 0 for the sea; rivers pass their flow direction in UV (UV.y metres downstream).

uniform vec4 deep_color : source_color = vec4(0.02, 0.11, 0.17, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.09, 0.36, 0.38, 1.0);
uniform float flow = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
global uniform float wetness;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.05 + TIME * 0.9) * 0.12 + sin(wpos.z * 0.07 + TIME * 1.3) * 0.08;
	VERTEX.y += w * (1.0 - flow);
}

void fragment() {
	vec2 base_uv = mix(wpos.xz, vec2(UV.x, UV.y - TIME * 1.4), flow);
	vec2 uv1 = base_uv * 0.035 + TIME * vec2(0.011, 0.007);
	vec2 uv2 = base_uv * 0.09 - TIME * vec2(0.009, 0.013);
	vec3 n = normalize(texture(noise_nrm, uv1).rgb * 0.5 + texture(noise_nrm, uv2).rgb * 0.5);
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vpos.xyz /= vpos.w;
	float wdepth = clamp(VERTEX.z - vpos.z, 0.0, 200.0);
	float t = clamp(wdepth / 7.0, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, t);
	float foam_n = texture(noise_tex, base_uv * 0.25 + TIME * 0.02).r;
	float foam = (1.0 - smoothstep(0.0, 1.4, wdepth)) * smoothstep(0.35, 0.65, foam_n + 0.25);
	col = mix(col, vec3(0.9, 0.95, 0.95), foam * 0.8);
	ALBEDO = col;
	ALPHA = clamp(mix(0.45, 0.97, smoothstep(0.0, 3.0, wdepth)) + foam * 0.4, 0.0, 1.0);
	ROUGHNESS = mix(0.03, 0.12, foam) + wetness * 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.65;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.7;
}
