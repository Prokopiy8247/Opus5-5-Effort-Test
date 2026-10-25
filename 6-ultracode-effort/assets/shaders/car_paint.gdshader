shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Project-owned car paint: gloss / matte / metallic finishes, procedural flakes,
// object-space stripes + liveries, dirt build-up and rain wetness.

uniform vec4 base_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.22;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_rough : hint_range(0.0, 1.0) = 0.06;
uniform float flake_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flake_scale = 700.0;
// 0 none, 1 twin stripes, 2 wide centre stripe, 3 side stripe, 4 rally livery, 5 two-tone
uniform int stripe_mode = 0;
uniform vec4 stripe_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform float stripe_width = 0.16;
uniform float stripe_gap = 0.07;
uniform float body_half_width = 0.9;
uniform float body_height = 1.4;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dirt_color : source_color = vec4(0.42, 0.34, 0.24, 1.0);
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float stripe_mask() {
	float ax = abs(obj_pos.x);
	float side = abs(obj_nrm.x);
	if (stripe_mode == 1) {
		float m = step(stripe_gap, ax) * step(ax, stripe_gap + stripe_width);
		return m * (1.0 - smoothstep(0.55, 0.75, side));
	} else if (stripe_mode == 2) {
		return step(ax, stripe_width * 1.6) * (1.0 - smoothstep(0.55, 0.75, side));
	} else if (stripe_mode == 3) {
		float y0 = body_height * 0.42;
		float band = step(y0, obj_pos.y) * step(obj_pos.y, y0 + 0.07);
		return band * smoothstep(0.5, 0.7, side);
	} else if (stripe_mode == 4) {
		float d = fract((obj_pos.z * 0.55 + obj_pos.y * 0.9) * 0.9);
		float diag = step(d, 0.28) * smoothstep(0.5, 0.7, side);
		float hood = step(ax, 0.32) * step(obj_pos.z, -0.9) * (1.0 - smoothstep(0.55, 0.75, side));
		return max(diag, hood);
	} else if (stripe_mode == 5) {
		return step(body_height * 0.62, obj_pos.y);
	}
	return 0.0;
}

void fragment() {
	vec3 col = base_color.rgb;
	float m = stripe_mask();
	col = mix(col, stripe_color.rgb, m);

	float rough = roughness;
	float metal = metallic;
	// Dirt: builds up from the sills upward, broken up by noise.
	float dn = vnoise(obj_pos * 6.0) * 0.6 + vnoise(obj_pos * 23.0) * 0.4;
	float dirt_h = 1.0 - smoothstep(0.15, 0.25 + dirt_amount * body_height * 0.6, obj_pos.y + dn * 0.25);
	float dirt = clamp(dirt_h * dirt_amount * 1.4, 0.0, 1.0) * smoothstep(0.25, 0.6, dn + dirt_amount * 0.5);
	col = mix(col, dirt_color.rgb, dirt * 0.9);
	rough = mix(rough, 0.9, dirt);
	metal = mix(metal, 0.0, dirt);

	// Metallic flakes perturb the normal for sparkle.
	if (flake_amount > 0.001) {
		vec3 fp = obj_pos * flake_scale;
		vec3 fn = vec3(hash3(floor(fp)), hash3(floor(fp) + 17.3), hash3(floor(fp) + 41.7)) * 2.0 - 1.0;
		NORMAL = normalize(NORMAL + fn * 0.09 * flake_amount * (1.0 - dirt));
	}
	// Wet paint: darker, glossier.
	col *= mix(1.0, 0.85, wetness * (1.0 - dirt));
	rough = mix(rough, rough * 0.4, wetness);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	CLEARCOAT = clearcoat_amount * (1.0 - dirt);
	CLEARCOAT_ROUGHNESS = clearcoat_rough;
}
