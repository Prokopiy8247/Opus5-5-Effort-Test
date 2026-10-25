shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;
// Soft, lit billboard puff for tyre smoke, dust, spray and exhaust (GPUParticles3D draw pass).
// Shape and billow are procedural; the particle colour (incl. alpha over life) comes from COLOR.

uniform float density : hint_range(0.0, 2.0) = 1.0;
// Depth distance (m) over which the puff fades where it meets geometry.
uniform float softness = 0.8;
uniform float billow : hint_range(0.0, 1.0) = 0.6;
uniform float noise_scale = 1.6;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.45;
uniform float near_fade = 1.4;
uniform float self_light : hint_range(0.0, 1.0) = 0.0;
// 0 = flat card facing the camera, ~1.7 = round puff.
uniform float bulge = 1.7;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_seed;
varying float v_phase;
varying float v_fade;

void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mat_world = mat_world * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	// Fill-rate guard: puffs the camera is inside (or that are invisible) collapse to nothing.
	float size = length(MODEL_MATRIX[0].xyz);
	float vz = -(VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).z;
	v_fade = smoothstep(size * 0.25 + 0.3, size * 0.6 + near_fade, vz) * step(0.004, COLOR.a * density);
	float k = v_fade > 0.0 ? 1.0 : 0.0;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(size * k, 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz) * k, 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz) * k, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// Spherical fake normal so the puff is shaded like a ball of vapour.
	NORMAL = normalize(vec3(VERTEX.x * bulge, VERTEX.y * bulge, 0.6));
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + 0.13);
	v_phase = INSTANCE_CUSTOM.y;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.37 + 7.1) * 0.35;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) {
		discard;
	}
	vec2 q = uv * noise_scale + vec2(v_seed * 17.0, v_seed * 31.0) + vec2(v_phase * 0.4, -v_phase * 0.6);
	float n = fbm(q);
	float shape = 1.0 - smoothstep(0.2, 1.0, r + (n - 0.5) * billow);
	shape *= shape * (1.0 - smoothstep(0.62, 1.0, r));
	float a = COLOR.a * shape * density * (0.75 + 0.5 * n);
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	upos.xyz /= upos.w;
	a *= clamp((VERTEX.z - upos.z) / softness, 0.0, 1.0);
	a *= v_fade * smoothstep(0.3, near_fade, -VERTEX.z);
	vec3 col = COLOR.rgb * (0.82 + 0.32 * n);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = col * backlight_amount;
	EMISSION = col * self_light;
}
