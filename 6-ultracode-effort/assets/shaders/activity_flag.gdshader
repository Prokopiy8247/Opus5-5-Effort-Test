shader_type spatial;
// Festival Flag collectible: waving cloth that slowly spins around its pole, with a sun emblem and glow.
// The mesh starts at the pole (local x = 0) and extends along +x.
render_mode cull_disabled, diffuse_burley;

uniform vec4 color_a : source_color = vec4(1.0, 0.74, 0.16, 1.0);
uniform vec4 color_b : source_color = vec4(0.93, 0.22, 0.38, 1.0);
uniform float spin_speed = 0.7;
uniform float glow_strength = 0.55;

void vertex() {
	float w = max(VERTEX.x, 0.0);
	VERTEX.z += sin(w * 3.4 - TIME * 5.2) * 0.13 * w;
	VERTEX.y += sin(w * 2.2 - TIME * 3.6) * 0.035 * w;
	float a = TIME * spin_speed;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	VERTEX.xz = rot * VERTEX.xz;
	NORMAL.xz = rot * NORMAL.xz;
}

void fragment() {
	vec2 p = (UV - vec2(0.42, 0.5)) * vec2(1.6, 1.0);
	float d = length(p);
	float sun = 1.0 - smoothstep(0.17, 0.19, d);
	float ang = atan(p.y, p.x);
	float rays = step(0.5, fract(ang * 12.0 / 6.28318)) * (1.0 - smoothstep(0.27, 0.29, d)) * (1.0 - sun);
	float hem = smoothstep(0.9, 0.93, UV.x) + (1.0 - smoothstep(0.04, 0.07, UV.y)) + smoothstep(0.93, 0.96, UV.y);
	vec3 col = mix(color_b.rgb, color_a.rgb, clamp(sun + rays * 0.85, 0.0, 1.0));
	col = mix(col, vec3(1.0, 0.97, 0.9), clamp(hem, 0.0, 1.0) * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.7;
	EMISSION = col * glow_strength;
}
