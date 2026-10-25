shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Sea / river water: layered scrolling normals, depth-based colour and shoreline foam.

uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.2);
uniform vec3 shallow_color : source_color = vec3(0.1, 0.38, 0.42);
uniform vec2 flow = vec2(0.02, 0.01);
uniform float wave_scale = 0.04;
uniform float foam_amount = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
global uniform float wind_strength;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.05 + TIME * 0.9) * 0.18 + sin(wpos.z * 0.07 + TIME * 1.1) * 0.12;
	VERTEX.y += w * (0.5 + wind_strength) * wave_scale * 10.0;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.02 + TIME * flow;
	vec2 uv2 = wpos.xz * 0.05 - TIME * flow * 1.7;
	float h1 = texture(noise_tex, uv1).r;
	float h2 = texture(noise_tex, uv2).r;
	float hx = texture(noise_tex, uv1 + vec2(0.01, 0.0)).r - h1 + texture(noise_tex, uv2 + vec2(0.01, 0.0)).r - h2;
	float hz = texture(noise_tex, uv1 + vec2(0.0, 0.01)).r - h1 + texture(noise_tex, uv2 + vec2(0.0, 0.01)).r - h2;
	float strength = 2.0 + wind_strength * 4.0;
	NORMAL_MAP = normalize(vec3(0.5 - hx * strength, 0.5 - hz * strength, 1.0));
	// water depth from the depth buffer
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float water_dist = -VERTEX.z;
	float depth = clamp(scene_dist - water_dist, 0.0, 60.0);
	float d = 1.0 - exp(-depth * 0.18);
	vec3 col = mix(shallow_color, deep_color, d);
	float foam = (1.0 - smoothstep(0.0, 1.6, depth)) * smoothstep(0.35, 0.65, h2 + 0.2) * foam_amount;
	col = mix(col, vec3(0.9, 0.93, 0.95), foam);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.4, foam);
	METALLIC = 0.0;
	SPECULAR = 0.65;
	ALPHA = clamp(0.55 + d * 0.45 + foam, 0.0, 1.0);
}
