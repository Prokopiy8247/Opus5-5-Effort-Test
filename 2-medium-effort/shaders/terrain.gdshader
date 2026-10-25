shader_type spatial;
// Terrain: vertex colour carries region/slope/height tint; noise adds detail; wetness darkens.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
global uniform float wetness;
global uniform float snow_cover;
uniform bool is_far = false;
uniform vec3 focus = vec3(0.0);
uniform float hide_r = 620.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (is_far && distance(wpos.xz, focus.xz) < hide_r) { discard; }
	float n1 = texture(noise_tex, wpos.xz * 0.013).r;
	float n2 = texture(noise_tex, wpos.xz * 0.11).r;
	float n3 = texture(noise_tex, wpos.xz * 0.6).r;
	vec3 col = COLOR.rgb * (0.78 + 0.32 * n1) * (0.85 + 0.25 * n2) * (0.92 + 0.16 * n3);
	float slope = 1.0 - wnrm.y;
	// rock strata on steep faces (triplanar-ish from height)
	float strata = texture(noise_tex, vec2(wpos.y * 0.15, (wpos.x + wpos.z) * 0.01)).r;
	col = mix(col, col * (0.75 + 0.5 * strata), smoothstep(0.25, 0.5, slope));
	float snow = snow_cover * smoothstep(0.35, 0.0, slope) * smoothstep(0.4, 0.6, n2 * 0.5 + 0.5 * n1 + 0.1);
	col = mix(col, vec3(0.92, 0.94, 0.97), snow);
	float wet = wetness * smoothstep(0.5, 0.2, slope);
	col *= mix(1.0, 0.7, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.45, wet);
	SPECULAR = 0.3;
}
