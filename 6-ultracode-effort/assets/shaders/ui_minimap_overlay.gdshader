shader_type canvas_item;
// Clips what a minimap layer draws (vector roads, GPS route) to the map circle with a soft edge.
// center / radius / feather are in the layer's own local units (set every frame by minimap.gd).

uniform vec2 center = vec2(0.0);
uniform float radius = 130.0;
uniform float feather = 1.5;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float d = length(local_pos - center);
	COLOR.a *= 1.0 - smoothstep(radius - feather, radius, d);
}
