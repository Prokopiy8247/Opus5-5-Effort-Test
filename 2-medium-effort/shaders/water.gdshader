shader_type spatial;
render_mode cull_disabled, depth_draw_always;
// Sea / river / lake: animated normals, depth tint and shoreline foam.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow : source_color = vec3(0.12, 0.45, 0.5);
uniform vec3 deep : source_color = vec3(0.02, 0.12, 0.22);
global uniform float wetness;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz;
	float t = TIME;
	float a = texture(noise_tex, uv * 0.012 + vec2(t * 0.006, t * 0.004)).r;
	float b = texture(noise_tex, uv * 0.031 - vec2(t * 0.01, -t * 0.007)).r;
	float c = texture(noise_tex, uv * 0.11 + vec2(t * 0.02, t * 0.015)).r;
	vec3 nrm = normalize(vec3((a - 0.5) * 0.6 + (c - 0.5) * 0.3, 1.0, (b - 0.5) * 0.6 + (c - 0.5) * 0.3));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * ndc;
	world.xyz /= world.w;
	float water_depth = clamp(wpos.y - world.y, 0.0, 60.0);
	float dk = 1.0 - exp(-water_depth * 0.18);
	vec3 col = mix(shallow, deep, dk);
	float foam = (1.0 - smoothstep(0.0, 1.4, water_depth)) * smoothstep(0.35, 0.7, c);
	col = mix(col, vec3(0.9, 0.95, 0.97), foam * 0.8);
	ALBEDO = col;
	ALPHA = clamp(0.55 + dk * 0.45 + foam, 0.0, 1.0);
	ROUGHNESS = 0.06 + wetness * 0.1;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
