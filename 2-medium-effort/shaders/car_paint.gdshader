shader_type spatial;
// Car paint: gloss / metallic / matte finishes with clearcoat, optional procedural stripes in object space.
uniform vec3 base_color : source_color = vec3(0.8, 0.1, 0.1);
uniform int finish = 0;
uniform int stripe_mode = 0;   // 0 none, 1 twin centre stripes, 2 side stripe, 3 two-tone roof
uniform vec3 stripe_color : source_color = vec3(1.0);
uniform float body_width = 1.8;
global uniform float wetness;

varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	vec3 col = base_color;
	float s = 0.0;
	float ax = abs(lpos.x);
	if (stripe_mode == 1) {
		s = step(0.08, ax) * step(ax, 0.26) * step(0.5, lnrm.y + 0.3);
	} else if (stripe_mode == 2) {
		s = step(body_width * 0.42, ax) * step(0.62, lpos.y) * step(lpos.y, 0.74);
	} else if (stripe_mode == 3) {
		s = step(1.15, lpos.y);
	}
	col = mix(col, stripe_color, s);
	ALBEDO = col;
	if (finish == 1) {
		METALLIC = 0.75; ROUGHNESS = 0.3; CLEARCOAT = 0.8; CLEARCOAT_ROUGHNESS = 0.08;
	} else if (finish == 2) {
		METALLIC = 0.05; ROUGHNESS = 0.72; CLEARCOAT = 0.0;
	} else {
		METALLIC = 0.12; ROUGHNESS = 0.2; CLEARCOAT = 1.0; CLEARCOAT_ROUGHNESS = 0.04;
	}
	ROUGHNESS = mix(ROUGHNESS, ROUGHNESS * 0.5, wetness);
}
