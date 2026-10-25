shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Procedural terrain material. Region weights arrive as vertex colour (r vale, g highlands, b mesa, a coast).
// Layers: meadow grass, patchwork fields, alpine grass, rock (triplanar), snow, desert sand, red strata rock,
// beach sand, worn road verges. Wetness darkens and smooths everything.

uniform sampler2D noise_large : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D road_dist_tex : filter_linear, repeat_disable;
uniform float map_half = 2048.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_line = 330.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying vec4 region;
varying vec3 wnrm;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 triplanar_rock(vec3 p, vec3 n, vec3 base_a, vec3 base_b) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float x = texture(noise_detail, p.zy * 0.11).r;
	float y = texture(noise_detail, p.xz * 0.11).r;
	float z = texture(noise_detail, p.xy * 0.11).r;
	float t = x * w.x + y * w.y + z * w.z;
	float x2 = texture(noise_detail, p.zy * 0.031).r;
	float z2 = texture(noise_detail, p.xy * 0.031).r;
	float y2 = texture(noise_detail, p.xz * 0.031).r;
	float t2 = x2 * w.x + y2 * w.y + z2 * w.z;
	return mix(base_a, base_b, clamp(t * 0.6 + t2 * 0.7 - 0.2, 0.0, 1.0));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	region = COLOR;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;
	float h = wpos.y;
	vec2 xz = wpos.xz;
	float nl = texture(noise_large, xz * 0.0011).r;
	float nm = texture(noise_large, xz * 0.0073).r;
	float nd = texture(noise_detail, xz * 0.09).r;
	float nf = texture(noise_detail, xz * 0.47).r;

	// ---- Vale: meadows + patchwork fields
	vec3 grass_a = vec3(0.20, 0.33, 0.09);
	vec3 grass_b = vec3(0.36, 0.42, 0.14);
	vec3 meadow = mix(grass_a, grass_b, clamp(nl * 1.2 - 0.1 + nd * 0.3, 0.0, 1.0));
	meadow *= 0.85 + nf * 0.3;
	// Fields: rotated grid cells with crop rows.
	float ang = 0.35 + floor(nl * 4.0) * 0.4;
	mat2 rot = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang)));
	vec2 fp = rot * xz;
	vec2 cell = floor(fp / vec2(150.0, 95.0));
	float crop = hash2(cell);
	vec2 local = fract(fp / vec2(150.0, 95.0));
	float edge = smoothstep(0.0, 0.025, local.x) * smoothstep(1.0, 0.975, local.x) * smoothstep(0.0, 0.04, local.y) * smoothstep(1.0, 0.96, local.y);
	float rows = 0.5 + 0.5 * sin(fp.x * 2.2);
	vec3 field = meadow;
	if (crop < 0.25) {
		field = mix(vec3(0.62, 0.5, 0.2), vec3(0.75, 0.62, 0.28), rows * 0.6 + nd * 0.4);   // wheat
	} else if (crop < 0.45) {
		field = mix(vec3(0.3, 0.2, 0.12), vec3(0.4, 0.28, 0.17), rows);                    // ploughed
	} else if (crop < 0.65) {
		field = mix(vec3(0.24, 0.38, 0.1), vec3(0.32, 0.46, 0.13), rows);                  // green crop
	} else if (crop < 0.75) {
		field = mix(vec3(0.5, 0.48, 0.18), vec3(0.42, 0.5, 0.16), rows * 0.5 + nd * 0.5);   // hay meadow
	}
	float field_mask = edge * smoothstep(0.62, 0.8, region.r) * (1.0 - smoothstep(0.12, 0.2, slope)) * smoothstep(0.45, 0.6, nl) * (1.0 - smoothstep(55.0, 70.0, h));
	vec3 vale = mix(meadow, field, field_mask);

	// ---- Highlands: alpine grass, rock, snow
	vec3 alpine = mix(vec3(0.24, 0.3, 0.14), vec3(0.4, 0.4, 0.24), clamp(nm + nd * 0.3 - 0.2, 0.0, 1.0));
	vec3 rock_grey = triplanar_rock(wpos, n, vec3(0.32, 0.31, 0.3), vec3(0.52, 0.5, 0.47));
	vec3 hl = mix(alpine, rock_grey, smoothstep(0.22, 0.42, slope + nd * 0.1));
	float snow = smoothstep(snow_line - 25.0, snow_line + 40.0, h + nl * 70.0 + nd * 25.0) * (1.0 - smoothstep(0.22, 0.42, slope + nd * 0.15));
	snow = max(snow, snow_cover * (1.0 - smoothstep(0.35, 0.55, slope)) * smoothstep(80.0, 140.0, h));
	hl = mix(hl, vec3(0.9, 0.92, 0.96) * (0.92 + nf * 0.08), snow);

	// ---- Mesa: sand flats and banded red rock
	vec3 sand_d = mix(vec3(0.72, 0.5, 0.3), vec3(0.82, 0.62, 0.4), clamp(nm + nd * 0.4 - 0.2, 0.0, 1.0));
	sand_d *= 0.9 + nf * 0.15;
	float strata = 0.5 + 0.5 * sin(h * 1.15 + nd * 3.0 + nl * 6.0);
	vec3 red_rock = mix(vec3(0.55, 0.24, 0.13), vec3(0.74, 0.42, 0.24), strata);
	red_rock = mix(red_rock, triplanar_rock(wpos, n, vec3(0.5, 0.25, 0.14), vec3(0.7, 0.42, 0.26)), 0.4);
	vec3 scrub = vec3(0.45, 0.42, 0.2);
	vec3 mesa = mix(sand_d, scrub, smoothstep(0.55, 0.75, nm) * 0.5);
	mesa = mix(mesa, red_rock, smoothstep(0.16, 0.34, slope + nd * 0.08));

	// ---- Coast: beach sand, cliff grass, cliff rock
	vec3 beach = mix(vec3(0.78, 0.71, 0.53), vec3(0.88, 0.82, 0.64), nd);
	vec3 coastal_grass = mix(vec3(0.3, 0.4, 0.16), vec3(0.45, 0.47, 0.25), nm);
	vec3 coast = mix(coastal_grass, beach, 1.0 - smoothstep(2.6, 4.8, h + nd * 1.2));
	coast = mix(coast, triplanar_rock(wpos, n, vec3(0.38, 0.35, 0.3), vec3(0.6, 0.56, 0.48)), smoothstep(0.3, 0.5, slope));
	// Underwater sand
	coast = mix(coast, vec3(0.6, 0.55, 0.4), 1.0 - smoothstep(-0.5, 0.5, h));

	vec4 rw = region / max(region.r + region.g + region.b + region.a, 0.001);
	vec3 col = vale * rw.r + hl * rw.g + mesa * rw.b + coast * rw.a;
	// Steep slopes anywhere become rock.
	vec3 any_rock = mix(rock_grey, red_rock, rw.b);
	col = mix(col, any_rock, smoothstep(0.5, 0.7, slope) * (1.0 - snow));

	// ---- Road verges: worn dirt / gravel within a few metres of the asphalt edge
	vec2 ruv = (xz + vec2(map_half)) / (2.0 * map_half);
	float rd = texture(road_dist_tex, ruv).r * 255.0;
	float verge = 1.0 - smoothstep(0.5, 2.5 + nd * 2.5, rd);
	vec3 verge_col = mix(col * vec3(0.8, 0.72, 0.6), vec3(0.34, 0.3, 0.24), 0.5 + nf * 0.3);
	col = mix(col, verge_col, verge * 0.6 * (1.0 - snow * 0.5));

	float rough = mix(0.95, 0.82, smoothstep(0.4, 0.7, slope));
	rough = mix(rough, 0.55, snow);
	// Wetness: darker, glossier (puddles in flat spots).
	float puddle = smoothstep(0.62, 0.75, nd) * (1.0 - smoothstep(0.05, 0.12, slope));
	col *= 1.0 - wetness * 0.28;
	rough = mix(rough, 0.25, wetness * (0.35 + puddle * 0.65));

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3 + wetness * 0.3;
}
