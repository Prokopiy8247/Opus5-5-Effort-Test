shader_type canvas_item;
// Heading-up minimap: rotates and crops the world map texture around the player inside a circular
// mask, grades it darker / cooler so vector roads, route and icons read on top, and vignettes the rim.
// The node's own texture is the 1024 px world map (covers x,z in [-2048, 2048]).

uniform vec2 center_uv = vec2(0.5);
uniform float heading = 0.0;
uniform float zoom_uv = 0.06;
uniform vec3 sea_color : source_color = vec3(0.07, 0.17, 0.27);
uniform float brightness = 0.6;
uniform float opacity = 0.94;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	float mask = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	float c = cos(heading);
	float s = sin(heading);
	vec2 q = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	vec2 uv = center_uv + q * zoom_uv;
	vec3 col = texture(TEXTURE, uv).rgb;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		col = sea_color;
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 0.78) * brightness;
	col *= vec3(0.9, 0.95, 1.05);
	col *= mix(1.0, 0.55, smoothstep(0.55, 1.0, r));
	COLOR = vec4(col, mask * opacity);
}
