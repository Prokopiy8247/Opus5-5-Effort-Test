shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Project-owned water: depth-tinted, scrolling normal waves, shoreline foam, fresnel.

uniform vec3 shallow_color : source_color = vec3(0.16, 0.48, 0.52);
uniform vec3 deep_color : source_color = vec3(0.03, 0.15, 0.24);
uniform float depth_scale = 6.0;
uniform float wave_scale = 0.02;
uniform float wave_speed = 0.035;
uniform float wave_strength = 0.55;
uniform float foam_width = 1.4;
uniform vec2 flow = vec2(0.0, 0.0);
uniform sampler2D noise_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
global uniform float wetness;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 uv = wpos.xz * wave_scale;
	vec2 fl = flow * TIME;
	vec3 n1 = texture(noise_a, uv + vec2(t, t * 0.7) + fl * 0.02).rgb;
	vec3 n2 = texture(noise_b, uv * 2.3 - vec2(t * 1.3, -t * 0.4) + fl * 0.03).rgb;
	vec3 nm = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm * 0.5 + 0.5, wave_strength * (1.0 + wetness * 0.6));
	// water depth from the scene depth buffer
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	world.xyz /= world.w;
	float scene_depth = -world.z;
	float surf_depth = -VERTEX.z;
	float depth = max(scene_depth - surf_depth, 0.0);
	float k = clamp(depth / depth_scale, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, k);
	float foam = (1.0 - smoothstep(0.0, foam_width, depth)) * (0.6 + 0.4 * sin(TIME * 1.7 + wpos.x * 0.3 + wpos.z * 0.2));
	col = mix(col, vec3(0.92, 0.95, 0.96), foam * 0.75);
	ALBEDO = col;
	ALPHA = clamp(0.55 + k * 0.45 + foam * 0.3, 0.0, 1.0);
	ROUGHNESS = 0.04 + foam * 0.5;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
