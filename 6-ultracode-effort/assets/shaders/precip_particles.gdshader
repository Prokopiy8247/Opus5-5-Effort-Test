shader_type particles;
render_mode disable_velocity, disable_force;
// Precipitation living in a box that follows the camera: particles fall with the wind and wrap around the
// box, so rain / snow / dust never runs out at speed. Draw shaders read the motion-blur vector from
// TRANSFORM[0].xyz and the particle size from TRANSFORM[1].x.

uniform vec3 box_center = vec3(0.0);
uniform vec3 box_size = vec3(50.0, 26.0, 50.0);
uniform vec3 fall_velocity = vec3(0.0, -9.0, 0.0);
uniform vec3 camera_velocity = vec3(0.0);
uniform float turbulence = 0.0;
uniform float streak_time = 0.03;
uniform float min_length = 0.2;
uniform float particle_size = 0.012;
uniform float size_variation = 0.3;

float rnd(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	w = (w >> 22u) ^ w;
	return float(w) / 4294967295.0;
}

void start() {
	uint seed = INDEX * 1973u + RANDOM_SEED * 9277u + NUMBER * 26699u + 1u;
	vec3 r = vec3(rnd(seed), rnd(seed), rnd(seed));
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = box_center + (r - 0.5) * box_size;
	CUSTOM = vec4(rnd(seed), 0.85 + 0.3 * rnd(seed), 1.0 + (rnd(seed) - 0.5) * 2.0 * size_variation, 0.0);
	VELOCITY = fall_velocity * CUSTOM.y;
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	vec3 v = fall_velocity * CUSTOM.y;
	if (turbulence > 0.0) {
		float ph = CUSTOM.x * 6.2832;
		v += vec3(sin(TIME * 1.3 + ph + p.y * 0.35), 0.4 * sin(TIME * 0.9 + ph * 2.0), cos(TIME * 1.1 + ph * 1.7 + p.x * 0.25)) * turbulence;
	}
	VELOCITY = v;
	p += v * DELTA;
	vec3 rel = mod(p - box_center + box_size * 0.5, box_size) - box_size * 0.5;
	p = box_center + rel;
	vec3 rv = v - camera_velocity;
	float sp = length(rv);
	vec3 axis = sp > 0.001 ? rv / sp : vec3(0.0, -1.0, 0.0);
	TRANSFORM[0] = vec4(axis * max(sp * streak_time, min_length), 0.0);
	TRANSFORM[1] = vec4(particle_size * CUSTOM.z, 0.0, 0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, 1.0, 0.0);
	TRANSFORM[3] = vec4(p, 1.0);
}
