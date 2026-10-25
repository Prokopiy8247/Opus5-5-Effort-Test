shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D blade_tex : source_color, filter_linear_mipmap;
global uniform float wind_strength;
global uniform float wetness;
global uniform float snow_cover;

varying vec3 wpos;
varying float hgt;

void vertex() {
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hgt = 1.0 - UV.y;
	float sway = sin(TIME * 1.7 + wpos.x * 0.35 + wpos.z * 0.27) * (0.08 + wind_strength * 0.25) * hgt * hgt;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
	// shrink tufts away beyond ~110 m (per-instance range)
	float d = length(world_origin - CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(85.0, 120.0, d);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 t = texture(blade_tex, UV);
	if (t.a < 0.5) {
		discard;
	}
	float v = fract(sin(dot(floor(wpos.xz * 0.15), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 base = mix(vec3(0.18, 0.3, 0.08), vec3(0.36, 0.42, 0.14), v);
	base = mix(base * 0.55, base * 1.15, hgt);
	base *= mix(1.0, 0.7, wetness);
	base = mix(base, vec3(0.9, 0.92, 0.96), snow_cover * 0.8);
	ALBEDO = base * t.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
