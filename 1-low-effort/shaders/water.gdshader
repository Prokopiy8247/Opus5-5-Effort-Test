shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep : source_color = vec3(0.03, 0.16, 0.24);
uniform vec3 shallow : source_color = vec3(0.1, 0.38, 0.42);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz;
	float t = TIME;
	float n1 = vnoise(uv * 0.15 + vec2(t * 0.3, t * 0.2));
	float n2 = vnoise(uv * 0.6 - vec2(t * 0.5, -t * 0.4));
	float n3 = vnoise(uv * 0.04 + vec2(t * 0.05, 0.0));
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.25, 1.0, (n2 - 0.5) * 0.5 + (n3 - 0.5) * 0.3));
	NORMAL = (VIEW_MATRIX * vec4(nrm, 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep, shallow, n3 * 0.6);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	EMISSION = vec3(0.0);
	ALPHA = 1.0;
}
