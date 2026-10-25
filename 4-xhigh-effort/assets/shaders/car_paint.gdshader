shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Project-owned car paint: base colour, finish (gloss/metallic/matte/pearl), metallic flakes,
// clearcoat, object-space livery stripes, dirt/wetness and a soft fresnel sheen.

uniform vec4 base_color : source_color = vec4(0.8, 0.08, 0.06, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform vec4 pearl_color : source_color = vec4(0.3, 0.5, 1.0, 1.0);
uniform int stripe_mode = 0;   // 0 none, 1 twin centre stripes, 2 side band, 3 single wide centre
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.28;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_rough : hint_range(0.0, 1.0) = 0.08;
uniform float flake_amount : hint_range(0.0, 1.0) = 0.35;
uniform float pearl_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 col = base_color.rgb;
	float stripe = 0.0;
	float ax = abs(obj_pos.x);
	if (stripe_mode == 1) {
		stripe = step(0.06, ax) * step(ax, 0.17) * step(0.25, obj_nrm.y + abs(obj_nrm.z));
	} else if (stripe_mode == 2) {
		stripe = step(0.5, abs(obj_nrm.x)) * step(0.42, obj_pos.y) * step(obj_pos.y, 0.5);
	} else if (stripe_mode == 3) {
		stripe = step(ax, 0.22) * step(0.25, obj_nrm.y + abs(obj_nrm.z));
	}
	col = mix(col, stripe_color.rgb, stripe);
	// pearl: hue shift at grazing angles
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, pearl_color.rgb * max(max(col.r, col.g), col.b) * 1.2, pearl_amount * fres);
	// flakes
	float fl = hash3(floor(obj_pos * 900.0));
	float flake = smoothstep(0.82, 1.0, fl) * flake_amount * (1.0 - stripe * 0.6);
	// dirt creeps up from the sills
	float dmask = smoothstep(0.75, 0.15, obj_pos.y) * dirt_amount;
	col = mix(col, vec3(0.32, 0.27, 0.2), dmask * 0.75);
	ALBEDO = col * (1.0 - wetness * 0.12);
	METALLIC = mix(metallic_amount, 0.0, dmask);
	ROUGHNESS = clamp(roughness_amount - flake * 0.18 + dmask * 0.5 - wetness * 0.1, 0.03, 1.0);
	CLEARCOAT = clearcoat_amount * (1.0 - dmask);
	CLEARCOAT_ROUGHNESS = clamp(clearcoat_rough - wetness * 0.05, 0.0, 1.0);
	SPECULAR = 0.5 + flake * 0.4;
}
