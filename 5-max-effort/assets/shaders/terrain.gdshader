shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// GPU-displaced streamed terrain. Each chunk is a shared flat grid; heights, holes, splat
// weights and the road mask come from baked world textures. Materials are procedural.

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D holemap : filter_nearest, repeat_disable;
uniform sampler2D splatmap : filter_linear, repeat_disable;
uniform sampler2D roadmask : filter_linear, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform float world_half = 2000.0;
uniform float grid_res = 2.0;
uniform float grid_n = 2001.0;
uniform float lod_step = 1.0;
uniform float skirt_depth = 6.0;
uniform float snow_line = 500.0;
uniform float road_sink = 0.0;
global uniform float wetness;
global uniform float night_amount;

varying vec3 world_pos;
varying vec3 world_nrm;
varying float skirt;

float h_at(ivec2 t) {
	t = clamp(t, ivec2(0), ivec2(int(grid_n) - 1));
	return texelFetch(heightmap, t, 0).r;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = (wp.xz + world_half) / grid_res;
	ivec2 t = ivec2(round(g));
	float h = h_at(t);
	int s = int(lod_step);
	float hl = h_at(t - ivec2(s, 0));
	float hr = h_at(t + ivec2(s, 0));
	float hd = h_at(t - ivec2(0, s));
	float hu = h_at(t + ivec2(0, s));
	vec3 n = normalize(vec3(hl - hr, 2.0 * grid_res * float(s), hd - hu));
	// at coarse LODs, sink the terrain under roads so it never pokes through road meshes
	if (road_sink > 0.0) {
		float rm = texture(roadmask, (wp.xz + world_half) / (2.0 * world_half)).r;
		h -= rm * road_sink;
	}
	skirt = COLOR.r;
	h -= skirt * skirt_depth;
	VERTEX.y = h;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(n, 0.0)).xyz;
	world_pos = vec3(wp.x, h, wp.z);
	world_nrm = n;
}

vec3 tint_noise(vec3 c, float n, float amt) {
	return c * (1.0 + (n - 0.5) * amt);
}

void fragment() {
	vec2 uvw = (world_pos.xz + world_half) / (2.0 * world_half);
	if (texture(holemap, uvw).r > 0.5) {
		discard;
	}
	vec4 sp = texture(splatmap, uvw);
	float rm = texture(roadmask, uvw).r;
	vec3 n = normalize(world_nrm);
	float slope = 1.0 - n.y;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	// detail noise at two scales (fade the fine one with distance)
	float d1 = texture(noise_a, world_pos.xz * 0.045).r;
	float d2 = texture(noise_b, world_pos.xz * 0.006).r;
	float d3 = texture(noise_a, world_pos.xz * 0.31).r;
	float fine = mix(d3, 0.5, smoothstep(30.0, 140.0, dist));
	// base palette
	vec3 meadow = mix(vec3(0.17, 0.31, 0.08), vec3(0.3, 0.4, 0.11), d2);
	meadow = tint_noise(meadow, d1, 0.55);
	meadow = mix(meadow, vec3(0.36, 0.33, 0.16), smoothstep(0.62, 0.8, texture(noise_b, world_pos.xz * 0.021).r) * 0.6);
	vec3 field_a = vec3(0.62, 0.5, 0.17);
	vec3 field_b = vec3(0.24, 0.4, 0.08);
	float stripes = step(0.5, fract(dot(world_pos.xz, vec2(0.21, 0.13)) * 0.9 + d2 * 3.0));
	vec3 field = mix(field_a, field_b, step(0.55, d2)) * (0.92 + stripes * 0.1);
	vec3 forest = mix(vec3(0.1, 0.17, 0.05), vec3(0.2, 0.16, 0.08), d1);
	vec3 desert = mix(vec3(0.7, 0.4, 0.2), vec3(0.58, 0.3, 0.16), d2);
	desert = mix(desert, vec3(0.78, 0.6, 0.4), smoothstep(0.55, 0.8, d1) * 0.5);
	vec3 sand = mix(vec3(0.86, 0.78, 0.6), vec3(0.78, 0.7, 0.52), d1);
	vec3 rock = mix(vec3(0.36, 0.34, 0.32), vec3(0.5, 0.47, 0.43), d1);
	rock = mix(rock, vec3(0.62, 0.33, 0.19) * (0.8 + d1 * 0.4), sp.g * 0.9);
	// banded canyon walls in the desert
	rock = mix(rock, rock * (0.85 + 0.25 * sin(world_pos.y * 0.9 + d1 * 3.0)), sp.g);
	vec3 snow = vec3(0.93, 0.95, 0.98);
	vec3 col = meadow;
	col = mix(col, field, sp.r);
	col = mix(col, forest, sp.b);
	col = mix(col, desert, sp.g);
	col = mix(col, sand, sp.a);
	// alpine: greyer grass high up
	col = mix(col, vec3(0.4, 0.42, 0.3), smoothstep(snow_line - 160.0, snow_line, world_pos.y) * (1.0 - sp.g));
	float rock_w = smoothstep(0.24, 0.42, slope + (d1 - 0.5) * 0.12);
	col = mix(col, rock, rock_w);
	float snow_w = smoothstep(snow_line - 20.0, snow_line + 40.0, world_pos.y + (d2 - 0.5) * 60.0) * (1.0 - smoothstep(0.45, 0.65, slope));
	col = mix(col, snow, snow_w);
	// far roads drawn into the terrain colour
	float far_road = rm * smoothstep(120.0, 260.0, dist);
	col = mix(col, vec3(0.2, 0.2, 0.21), far_road * step(0.2, rm) * (1.0 - step(0.5, rm)));
	col = mix(col, vec3(0.5, 0.42, 0.32), far_road * step(0.5, rm));
	col *= 0.72 + fine * 0.55;
	// wet: darker, glossier (not on snow)
	float wet = wetness * (1.0 - snow_w);
	col *= 1.0 - wet * 0.32;
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.75, rock_w), 0.35, wet * 0.8);
	ROUGHNESS = mix(ROUGHNESS, 0.55, snow_w);
	SPECULAR = 0.35;
}
