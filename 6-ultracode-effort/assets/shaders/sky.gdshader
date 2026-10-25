shader_type sky;
// Sunward Roads sky. Gradient atmosphere keyed by sun elevation (colours come from the environment
// controller), sun disk + halo, phased moon, rotating star field with a faint galactic band, two animated
// cloud layers (cumulus + cirrus) whose coverage / darkness follow the weather, horizon haze and
// lightning flashes. The radiance (cubemap) pass skips the small bright details.

uniform vec3 sun_dir = vec3(0.0, 0.6, 0.8);
uniform vec3 moon_dir = vec3(0.0, 0.5, -0.86);
uniform vec3 light_dir = vec3(0.0, 0.6, 0.8);
uniform vec3 sun_light = vec3(1.0, 0.95, 0.88);
uniform vec3 moon_light = vec3(0.55, 0.62, 0.75);
uniform vec3 zenith_color = vec3(0.1, 0.3, 0.75);
uniform vec3 horizon_color = vec3(0.6, 0.76, 0.92);
uniform vec3 glow_color = vec3(0.0);
uniform vec3 ground_color = vec3(0.16, 0.16, 0.15);
uniform vec3 haze_color = vec3(0.7, 0.78, 0.88);
uniform vec3 overcast_color = vec3(0.55, 0.58, 0.62);
uniform vec3 cloud_lit = vec3(1.0);
uniform vec3 cloud_shade = vec3(0.5, 0.55, 0.65);
uniform float sun_size = 0.0115;
uniform float sun_disk_energy = 20.0;
uniform float moon_size = 0.021;
uniform float stars = 0.0;
uniform float star_angle = 0.0;
uniform float overcast = 0.0;
uniform float haze = 0.2;
uniform float cloud_coverage = 0.3;
uniform float cloud_darkness = 0.0;
uniform float cirrus = 0.4;
uniform vec2 cloud_offset = vec2(0.0);
uniform vec2 cirrus_offset = vec2(0.0);
uniform float flash = 0.0;
uniform vec3 flash_dir = vec3(0.0, 0.3, 1.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;

const vec3 POLE = vec3(0.0, 0.6157, -0.788);   // celestial north pole at 38 deg latitude

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

vec3 rotate_axis(vec3 v, vec3 k, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

vec3 atmosphere(vec3 d, float mu) {
	float y = max(d.y, 0.0);
	float hw = exp(-y * 5.0);
	vec3 col = mix(zenith_color, horizon_color, hw);
	vec2 fd = normalize(d.xz + vec2(1e-5));
	vec2 fs = normalize(sun_dir.xz + vec2(1e-5));
	float az = dot(fd, fs) * 0.5 + 0.5;
	// Dawn / dusk glow towards the sun and a soft pink arch opposite.
	col += glow_color * (pow(az, 6.0) * 0.7 + pow(az, 2.0) * 0.3) * exp(-y * 4.0);
	col += glow_color * vec3(0.55, 0.32, 0.6) * 0.22 * pow(1.0 - az, 2.0) * exp(-y * 9.0);
	float m = max(mu, 0.0);
	col += sun_light * (pow(m, 10.0) * 0.08 + pow(m, 120.0) * 0.5 + pow(m, 1400.0) * 2.0) * (1.0 - overcast * 0.85);
	col = mix(col, overcast_color * mix(0.86, 1.06, y), overcast);
	return col;
}

float cloud_shape(vec2 uv, float coverage, bool detail) {
	float n = texture(cloud_noise, uv).r;
	if (detail) {
		float dn = texture(detail_noise, uv * 3.3 + vec2(0.17, 0.53)).r;
		n = n * 0.74 + dn * 0.26;
	}
	float thr = mix(0.8, 0.14, coverage);
	return smoothstep(thr, thr + 0.16, n);
}

vec3 star_field(vec3 d) {
	vec3 r = rotate_axis(d, POLE, star_angle);
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 150.0 : 330.0;
		float thr = layer == 0 ? 0.982 : 0.988;
		float size = layer == 0 ? 0.34 : 0.36;
		vec3 p = r * scale;
		vec3 c = floor(p);
		vec3 h = hash33(c + float(layer) * 71.3);
		if (h.x > thr) {
			vec3 center = c + 0.2 + 0.6 * hash33(c + 13.7);
			float dist = length(p - center);
			float b = (1.0 - smoothstep(0.0, size, dist)) * (0.35 + 0.65 * (h.x - thr) / (1.0 - thr));
			float tw = 0.78 + 0.22 * sin(TIME * (1.5 + h.y * 4.0) + h.z * 40.0);
			vec3 tint = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.86, 0.68), h.z);
			col += tint * b * tw * (layer == 0 ? 3.2 : 1.1);
		}
	}
	// Galactic band.
	float band = exp(-pow(dot(r, normalize(vec3(0.42, 0.18, 0.89))) / 0.16, 2.0));
	float bn = textureLod(cloud_noise, vec2(atan(r.z, r.x) * 0.6, r.y * 1.4), 2.0).r;
	col += vec3(0.5, 0.55, 0.75) * band * smoothstep(0.3, 0.8, bn) * 0.035;
	return col;
}

vec3 moon_disk(vec3 d, out float mask) {
	mask = 0.0;
	float ca = dot(d, moon_dir);
	vec3 col = vec3(0.0);
	if (ca > cos(moon_size * 1.1)) {
		vec3 up0 = abs(moon_dir.y) > 0.98 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		vec3 right = normalize(cross(up0, moon_dir));
		vec3 up = cross(moon_dir, right);
		vec2 q = vec2(dot(d, right), dot(d, up)) / sin(moon_size);
		float r2 = dot(q, q);
		if (r2 < 1.0) {
			vec3 n = right * q.x + up * q.y - moon_dir * sqrt(1.0 - r2);
			float lit = smoothstep(-0.06, 0.14, dot(n, sun_dir));
			float maria = textureLod(cloud_noise, q * 0.32 + vec2(0.31, 0.62), 1.0).r;
			float alb = 0.62 + 0.38 * (1.0 - smoothstep(0.38, 0.62, maria));
			mask = 1.0 - smoothstep(0.9, 1.0, r2);
			col = moon_light * 1.8 * (lit * alb + 0.02) * mask;
		}
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float mu = dot(d, sun_dir);
	vec3 col;
	if (d.y >= 0.0) {
		col = atmosphere(d, mu);
	} else {
		col = mix(atmosphere(vec3(d.x, 0.0, d.z), mu), ground_color, smoothstep(0.0, 0.22, -d.y));
	}

	float night_vis = stars * (1.0 - overcast) * smoothstep(-0.02, 0.18, d.y);
	float mmask;
	vec3 mc = moon_disk(d, mmask);
	col = mix(col, col * (1.0 - mmask) + mc, (1.0 - overcast * 0.92) * mix(0.3, 1.0, stars) * smoothstep(-0.03, 0.02, d.y));
	if (!AT_CUBEMAP_PASS) {
		if (night_vis > 0.001) {
			col += star_field(d) * night_vis * (1.0 - mmask);
		}
		// Sun disk with limb darkening.
		float cs = cos(sun_size);
		float disk = smoothstep(cs, mix(cs, 1.0, 0.25), mu);
		float t = clamp((1.0 - mu) / (1.0 - cs), 0.0, 1.0);
		col += sun_light * sun_disk_energy * disk * (1.0 - 0.45 * t * t) * (1.0 - overcast * 0.9) * smoothstep(-0.02, 0.01, d.y);
	}
	float mca = max(dot(d, moon_dir), 0.0);
	col += moon_light * (pow(mca, 900.0) * 0.25 + pow(mca, 24.0) * 0.05) * stars * (1.0 - overcast * 0.6);

	float cloud_a = 0.0;
	if (d.y > 0.0) {
		vec2 p = d.xz / (d.y + 0.06);
		float fade = smoothstep(0.0, 0.2, d.y);
		// Cirrus: high, thin and streaky.
		if (cirrus > 0.001) {
			vec2 cu = vec2(p.x * 0.11 + p.y * 0.04, p.y * 0.035) + cirrus_offset;
			float cn = texture(cloud_noise, cu).r * texture(detail_noise, cu * vec2(2.0, 9.0)).r;
			float ci = smoothstep(0.24, 0.55, cn) * cirrus * fade * 0.55;
			vec3 ccol = cloud_lit * 1.05 + glow_color * 0.35;
			col = mix(col, ccol, ci);
		}
		// Cumulus.
		vec2 uv = p * 0.19 + cloud_offset;
		float c0 = cloud_shape(uv, cloud_coverage, !AT_CUBEMAP_PASS);
		// Sampled outside the branch so mip selection stays well defined.
		vec2 toward = normalize(light_dir.xz + vec2(1e-4)) * 0.018;
		float c1 = AT_CUBEMAP_PASS ? c0 : cloud_shape(uv + toward, cloud_coverage, true);
		if (c0 > 0.002) {
			float shade = clamp(0.9 + (c0 - c1) * 2.6 - c0 * 0.6, 0.0, 1.0);
			vec3 ccol = mix(cloud_shade, cloud_lit, shade);
			// Silver lining on thin edges towards the sun, warm rims at dawn / dusk.
			float m = max(mu, 0.0);
			ccol += sun_light * pow(m, 12.0) * (1.0 - c0) * 1.6 * (1.0 - cloud_darkness);
			ccol += glow_color * 0.4 * (1.0 - c0) * exp(-d.y * 4.0);
			cloud_a = c0 * fade * mix(0.92, 1.0, cloud_darkness);
			col = mix(col, ccol, cloud_a);
		}
	}

	// Horizon haze (above and below the horizon line).
	col = mix(col, haze_color, haze * exp(-abs(d.y) * 7.0));

	if (flash > 0.0) {
		float f = 0.35 + 0.65 * pow(max(dot(d, flash_dir), 0.0), 3.0);
		col += flash * vec3(0.82, 0.88, 1.0) * (0.25 + cloud_a * 1.5 + overcast * 0.6) * f;
	}
	COLOR = max(col, vec3(0.0));
}
