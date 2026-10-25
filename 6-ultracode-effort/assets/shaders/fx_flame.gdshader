shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;
// Exhaust backfire flame: two crossed quads along +Z (UV.y 0 = nozzle, 1 = tip) plus a glow disc
// at the nozzle (vertex colour red = 1). Driven per instance by `intensity` and `seed`.

instance uniform float intensity = 0.0;
instance uniform float seed = 0.0;

varying float v_disc;

void vertex() {
	v_disc = COLOR.r;
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

void fragment() {
	if (v_disc > 0.5) {
		vec2 d = UV * 2.0 - 1.0;
		float g = exp(-dot(d, d) * 5.0) * (1.0 - smoothstep(0.85, 1.0, length(d)));
		ALBEDO = vec3(1.0, 0.62, 0.3) * 3.0;
		ALPHA = clamp(g * intensity, 0.0, 1.0);
	} else {
		float v = UV.y;
		float u = abs(UV.x * 2.0 - 1.0);
		float n = vnoise(vec2(UV.x * 4.0 + seed * 7.0, v * 5.0 - TIME * 22.0 + seed * 13.0));
		float width = mix(0.95, 0.12, pow(v, 0.7));
		float body = 1.0 - smoothstep(width * 0.35, width, u + (n - 0.5) * 0.35);
		body *= smoothstep(1.0, 0.45 + 0.3 * n, v) * smoothstep(0.0, 0.05, v);
		vec3 core = vec3(0.7, 0.82, 1.0);
		vec3 mid = vec3(1.0, 0.72, 0.28);
		vec3 tip = vec3(1.0, 0.28, 0.06);
		vec3 c = mix(core, mid, smoothstep(0.0, 0.22, v + (1.0 - u) * -0.1));
		c = mix(c, tip, smoothstep(0.35, 0.95, v));
		ALBEDO = c * 3.5;
		ALPHA = clamp(body * intensity, 0.0, 1.0);
	}
}
