shader_type canvas_item;
// Heading-up circular minimap: samples the baked island map around the player.

uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 center_uv = vec2(0.5);
uniform float rotation = 0.0;
uniform float radius_uv = 0.06;
uniform vec4 ring_color : source_color = vec4(1.0, 0.24, 0.5, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float c = cos(rotation);
	float s = sin(rotation);
	vec2 rp = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	vec2 muv = center_uv + rp * radius_uv;
	vec3 col = texture(map_tex, muv).rgb;
	if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) {
		col = vec3(0.04, 0.12, 0.2);
	}
	col *= 0.85;
	float alpha = 1.0 - smoothstep(0.96, 0.985, d);
	float ring = smoothstep(0.93, 0.955, d) * (1.0 - smoothstep(0.985, 1.0, d));
	col = mix(col, ring_color.rgb, ring);
	COLOR = vec4(col, alpha * 0.92);
}
