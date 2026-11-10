shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural low-poly people and bicycles. All animation is done here, so one MultiMesh draws every person
// of one look. UV.x carries the limb id, COLOR the flat colour. Per instance (INSTANCE_CUSTOM):
// x = phase offset (bike: wheel angle), y = animation rate (rad/s), z = pose mode, w = animation amount 0..1.
// Limb ids: 0 body, 1/2 left/right thigh, 3/4 left/right upper arm, 5/6 left/right shin, 7/8 left/right forearm.
// Bike: 1 front wheel, 2 rear wheel.

uniform bool is_bike = false;
uniform float rough : hint_range(0.0, 1.0) = 0.88;

varying vec3 v_col;

void rot(inout vec3 p, inout vec3 n, vec3 pv, float a) {
	float c = cos(a);
	float s = sin(a);
	vec3 q = p - pv;
	p = pv + vec3(q.x, c * q.y - s * q.z, s * q.y + c * q.z);
	n = vec3(n.x, c * n.y - s * n.z, s * n.y + c * n.z);
}

void vertex() {
	v_col = COLOR.rgb;
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	int limb = int(UV.x + 0.5);
	float t = TIME * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.x;
	if (is_bike) {
		if (limb == 1) {
			rot(p, n, vec3(0.0, 0.34, -0.52), t);
		} else if (limb == 2) {
			rot(p, n, vec3(0.0, 0.34, 0.48), t);
		}
	} else {
		int m = int(INSTANCE_CUSTOM.z + 0.5);
		float amt = INSTANCE_CUSTOM.w;
		float s1 = sin(t);
		float s2 = -s1;
		float cl = max(cos(t), 0.0);
		float cr = max(-cos(t), 0.0);
		float hl = 0.0, hr = 0.0, kl = 0.0, kr = 0.0, al = 0.0, ar = 0.0, el = 0.0, er = 0.0;
		float lean = 0.0, drop = 0.0, bob = 0.0;
		if (m == 0) {
			al = 0.05 * sin(TIME * 0.7 + INSTANCE_CUSTOM.x) * amt;
			ar = -al;
			el = -0.12;
			er = -0.12;
		} else if (m == 1) {
			hl = 0.5 * s1 * amt;
			hr = 0.5 * s2 * amt;
			kl = -0.75 * cl * amt;
			kr = -0.75 * cr * amt;
			al = -0.5 * s1 * amt;
			ar = -0.5 * s2 * amt;
			el = -0.3;
			er = -0.3;
			bob = abs(s1) * 0.012 * amt;
		} else if (m == 2 || m == 8) {
			float k = m == 2 ? 1.0 : 0.65;
			hl = 0.95 * k * s1 * amt;
			hr = 0.95 * k * s2 * amt;
			kl = -(1.3 * cl + 0.3) * k * amt;
			kr = -(1.3 * cr + 0.3) * k * amt;
			al = -0.95 * k * s1 * amt;
			ar = -0.95 * k * s2 * amt;
			el = -1.4 * k;
			er = -1.4 * k;
			lean = -0.25 * k;
			bob = abs(s1) * 0.05 * k * amt;
		} else if (m == 3 || m == 7) {
			hl = 1.45;
			hr = 1.45;
			kl = -1.45 + 0.12 * sin(TIME * 0.4 + INSTANCE_CUSTOM.x) * amt;
			kr = -1.45;
			al = 0.25;
			ar = 0.25;
			el = -0.75;
			er = -0.75;
			drop = 0.47;
			if (m == 7) {
				ar = 1.1;
				er = -1.65;
			}
		} else if (m == 4) {
			ar = 1.05;
			er = -1.6;
			el = -0.15;
			lean = -0.05;
		} else if (m == 5) {
			ar = 0.7 + 0.4 * sin(t * 1.3) * amt;
			er = -1.2 + 0.5 * sin(t * 2.1) * amt;
			al = 0.25 + 0.25 * sin(t * 0.9 + 1.0) * amt;
			el = -0.9;
		} else if (m == 6) {
			hl = 0.85 + 0.5 * s1 * amt;
			hr = 0.85 + 0.5 * s2 * amt;
			kl = -0.75 - 0.6 * (0.5 + 0.5 * cos(t)) * amt;
			kr = -0.75 - 0.6 * (0.5 - 0.5 * cos(t)) * amt;
			al = 1.15;
			ar = 1.15;
			el = -0.15;
			er = -0.15;
			lean = -0.38;
		} else if (m == 9) {
			al = 0.55;
			ar = 0.55;
			el = -2.1;
			er = -2.1;
		}
		vec3 hipL = vec3(-0.095, 0.92, 0.0);
		vec3 hipR = vec3(0.095, 0.92, 0.0);
		vec3 shL = vec3(-0.235, 1.42, 0.0);
		vec3 shR = vec3(0.235, 1.42, 0.0);
		bool leg = false;
		if (limb == 1) {
			rot(p, n, hipL, hl);
			leg = true;
		} else if (limb == 2) {
			rot(p, n, hipR, hr);
			leg = true;
		} else if (limb == 5) {
			rot(p, n, vec3(-0.095, 0.5, 0.0), kl);
			rot(p, n, hipL, hl);
			leg = true;
		} else if (limb == 6) {
			rot(p, n, vec3(0.095, 0.5, 0.0), kr);
			rot(p, n, hipR, hr);
			leg = true;
		} else if (limb == 3) {
			rot(p, n, shL, al);
		} else if (limb == 4) {
			rot(p, n, shR, ar);
		} else if (limb == 7) {
			rot(p, n, vec3(-0.235, 1.15, 0.0), el);
			rot(p, n, shL, al);
		} else if (limb == 8) {
			rot(p, n, vec3(0.235, 1.15, 0.0), er);
			rot(p, n, shR, ar);
		}
		if (!leg && lean != 0.0) {
			rot(p, n, vec3(0.0, 0.92, 0.0), lean);
		}
		p.y += bob - drop;
	}
	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
