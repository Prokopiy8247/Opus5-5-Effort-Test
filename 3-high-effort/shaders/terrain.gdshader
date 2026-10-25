shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Velora terrain: splat (R grass, G soil, B sand, A rock) + region weights
// (R valley, G highlands, B mesa, A coast) + procedural detail, fields, snow, wetness.

uniform sampler2D splat_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D biome_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
uniform float world_origin = -2048.0;
uniform float world_size = 4096.0;
uniform float snow_line = 330.0;
global uniform float wetness;
global uniform float snow_cover;

varying vec3 wpos;
varying vec3 wnorm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 field_color(vec2 p, float valley, out float field_mask, out float rough_add) {
	// rotated patchwork of fields, each with its own crop
	float ang = 0.42;
	mat2 r = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang)));
	vec2 q = r * p;
	vec2 cell_size = vec2(95.0, 140.0);
	vec2 id = floor(q / cell_size);
	vec2 f = fract(q / cell_size);
	float h = hash12(id);
	float edge = smoothstep(0.0, 0.03, f.x) * smoothstep(1.0, 0.97, f.x) * smoothstep(0.0, 0.025, f.y) * smoothstep(1.0, 0.975, f.y);
	field_mask = edge * step(0.22, h) * smoothstep(0.55, 0.8, valley);
	vec3 c;
	rough_add = 0.0;
	if (h < 0.42) {
		c = mix(vec3(0.62, 0.52, 0.22), vec3(0.75, 0.63, 0.3), hash12(id + 7.0)); // wheat
		c *= 0.9 + 0.1 * sin(q.x * 1.6);
	} else if (h < 0.62) {
		c = vec3(0.24, 0.36, 0.11) * (0.85 + 0.15 * sin(q.y * 2.4)); // green crop rows
	} else if (h < 0.78) {
		c = vec3(0.33, 0.24, 0.16) * (0.8 + 0.2 * sin(q.x * 3.1)); // ploughed
		rough_add = 0.05;
	} else {
		c = vec3(0.36, 0.42, 0.18); // meadow / rapeseed
		if (hash12(id + 3.1) > 0.6) c = vec3(0.78, 0.7, 0.12);
	}
	return c;
}

void fragment() {
	vec2 uv = (wpos.xz - world_origin) / world_size;
	vec4 sp = texture(splat_tex, uv);
	vec4 bio = texture(biome_tex, uv);
	float n1 = texture(noise_tex, wpos.xz * 0.0021).r;
	float n2 = texture(noise_detail, wpos.xz * 0.045).r;
	float n3 = texture(noise_detail, wpos.xz * 0.31).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);

	// --- base materials per region
	vec3 grass_valley = mix(vec3(0.20, 0.33, 0.09), vec3(0.32, 0.42, 0.13), n1);
	vec3 grass_high = mix(vec3(0.17, 0.26, 0.10), vec3(0.28, 0.32, 0.16), n1);
	vec3 grass_mesa = mix(vec3(0.42, 0.38, 0.20), vec3(0.52, 0.45, 0.26), n1);
	vec3 grass_coast = mix(vec3(0.24, 0.36, 0.13), vec3(0.38, 0.44, 0.2), n1);
	float wsum = max(bio.r + bio.g + bio.b + bio.a, 0.001);
	vec3 grass = (grass_valley * bio.r + grass_high * bio.g + grass_mesa * bio.b + grass_coast * bio.a) / wsum;
	grass *= 0.82 + 0.3 * n2;

	vec3 soil = mix(vec3(0.33, 0.25, 0.17), vec3(0.45, 0.34, 0.22), n2);
	soil = mix(soil, vec3(0.55, 0.32, 0.18), bio.b / wsum);
	vec3 sand_beach = mix(vec3(0.76, 0.69, 0.52), vec3(0.85, 0.78, 0.6), n2);
	vec3 sand_desert = mix(vec3(0.72, 0.48, 0.27), vec3(0.82, 0.58, 0.35), n2);
	vec3 sand = mix(sand_beach, sand_desert, clamp(bio.b / wsum * 1.5, 0.0, 1.0));
	vec3 rock_grey = mix(vec3(0.2, 0.2, 0.19), vec3(0.31, 0.3, 0.28), n3) * (0.85 + 0.3 * n1);
	rock_grey *= 0.88 + 0.12 * sin(wpos.y * 0.9 + n2 * 6.0);
	vec3 rock_red = mix(vec3(0.46, 0.25, 0.15), vec3(0.6, 0.36, 0.22), n3);
	// sandstone banding on mesa cliffs
	rock_red *= 0.85 + 0.15 * sin(wpos.y * 1.3 + n2 * 4.0);
	vec3 rock = mix(rock_grey, rock_red, clamp(bio.b / wsum * 1.4, 0.0, 1.0));

	float rock_w = max(sp.a, smoothstep(0.42, 0.62, slope + (n2 - 0.5) * 0.15));
	vec4 w = vec4(sp.r, sp.g, sp.b, 0.0);
	w *= (1.0 - rock_w);
	w.a = rock_w;
	float s = max(w.r + w.g + w.b + w.a, 0.001);
	w /= s;
	vec3 col = grass * w.r + soil * w.g + sand * w.b + rock * w.a;
	float rough = 0.92 * w.r + 0.95 * w.g + 0.9 * w.b + 0.82 * w.a;

	// --- fields in the valley (only on gentle grass)
	float fmask;
	float radd;
	vec3 fc = field_color(wpos.xz, bio.r / wsum, fmask, radd);
	fmask *= w.r * (1.0 - smoothstep(0.08, 0.2, slope));
	col = mix(col, fc * (0.9 + 0.2 * n2), fmask);
	rough += radd * fmask;

	// --- snow at altitude
	float snow_h = snow_line + (n1 - 0.5) * 60.0 - snow_cover * 250.0;
	float snow = smoothstep(snow_h, snow_h + 25.0, wpos.y) * (1.0 - smoothstep(0.55, 0.8, slope));
	snow = max(snow, snow_cover * smoothstep(0.3, 0.7, wnorm.y) * smoothstep(0.35, 0.6, n2 + 0.2));
	col = mix(col, vec3(0.92, 0.94, 0.98) * (0.92 + 0.08 * n3), snow);
	rough = mix(rough, 0.55, snow);

	// --- far distance: desaturate slightly toward atmosphere
	float far_f = smoothstep(800.0, 3000.0, dist);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.55, 0.15))) * 1.05, far_f * 0.25);

	// --- wetness: darker, glossier, puddles in flat soil
	float wet = wetness * (1.0 - snow);
	col *= mix(1.0, 0.62, wet * (1.0 - w.a * 0.4));
	rough = mix(rough, 0.35, wet * 0.8);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	// micro detail normal from noise
	float dn = texture(noise_detail, wpos.xz * 0.6).r - texture(noise_detail, wpos.xz * 0.6 + vec2(0.01, 0.0)).r;
	float dn2 = texture(noise_detail, wpos.xz * 0.6).r - texture(noise_detail, wpos.xz * 0.6 + vec2(0.0, 0.01)).r;
	NORMAL_MAP = normalize(vec3(0.5 + dn * 3.0 * (1.0 - far_f), 0.5 + dn2 * 3.0 * (1.0 - far_f), 1.0));
	NORMAL_MAP_DEPTH = 0.6;
}
