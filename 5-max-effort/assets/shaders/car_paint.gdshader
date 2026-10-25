shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Project-owned car paint: base colour + finish (metallic/roughness/clearcoat), metallic flake
// sparkle, optional twin racing stripes in object space, and a wet look in rain.

uniform vec4 base_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float clearcoat : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.05;
uniform float flake : hint_range(0.0, 1.0) = 0.0;
uniform float pearl : hint_range(0.0, 1.0) = 0.0;
uniform bool stripes = false;
uniform vec4 stripe_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform float stripe_width = 0.13;
uniform float stripe_gap = 0.045;
global uniform float wetness;

varying vec3 obj_pos;
varying vec3 obj_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 col = base_color.rgb;
	if (stripes) {
		float x = abs(obj_pos.x);
		float s = smoothstep(stripe_gap - 0.003, stripe_gap, x) * (1.0 - smoothstep(stripe_gap + stripe_width, stripe_gap + stripe_width + 0.003, x));
		float facing = smoothstep(0.25, 0.55, obj_normal.y + abs(obj_normal.z) * 0.7);
		col = mix(col, stripe_color.rgb, s * facing);
	}
	float f = hash13(floor(obj_pos * 1400.0));
	float view_d = length(VERTEX);
	// flakes are sub-pixel beyond a few metres: fade them early so they never alias into white noise
	float sparkle = pow(f, 18.0) * flake * (1.0 - smoothstep(1.5, 5.0, view_d));
	// pearl: hue shift towards the rim
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, col.gbr * 0.6 + col * 0.6, pearl * rim * rim);
	ALBEDO = col * (0.97 + f * 0.06 * flake * (1.0 - smoothstep(6.0, 20.0, view_d)));
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, roughness * 0.55, wetness);
	SPECULAR = 0.55;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = mix(clearcoat_roughness, 0.02, wetness);
	EMISSION = (col * 0.7 + vec3(0.3)) * sparkle * 0.07;
}
