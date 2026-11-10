shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Road surface: UV.x = 0..1 across the paved width (incl. shoulders), <0 / >1 = verge skirt.
// UV.y = metres along the road / 4. Markings are drawn procedurally from per-instance parameters.
// Vertex colour (road_builder.gd): r = dirty-edge strength (0 around junction mouths), g = bridge-deck end
// fade (concrete takes up the asphalt look), b = dead-end apron (the road runs out into dirt).
// The paving edge goes asphalt -> dust and grit -> soil (road_verge.gdshaderinc, shared with the terrain)
// over 0.4-1.5 m with a noisy border; the lane and the edge line stay clean.

instance uniform float road_width = 8.0;      // paved lanes width (edge line to edge line)
instance uniform float shoulder = 0.9;
instance uniform int lanes = 1;               // lanes per direction
instance uniform int marking = 1;             // 0 none, 1 rural, 2 highway, 3 street
instance uniform int surface_kind = 0;        // 0 asphalt, 1 dirt, 2 gravel, 3 sand, 4 concrete
instance uniform float covered = 0.0;         // 1 under a tunnel tube: no rain wetness, puddles, snow or sky reflection

#include "res://assets/shaders/road_verge.gdshaderinc"

uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_large : filter_linear_mipmap, repeat_enable;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_mask(float x, float center, float half_w) {
	float aa = fwidth(x) * 1.2;
	return 1.0 - smoothstep(half_w - aa, half_w + aa, abs(x - center));
}

void fragment() {
	float total = road_width + shoulder * 2.0;
	float x = UV.x * total - total * 0.5;        // metres from the centre line (+ right)
	float along = UV.y * 4.0;                     // metres along the road
	float nd = texture(noise_detail, wpos.xz * 0.35).r;
	float nf = texture(noise_detail, wpos.xz * 1.7).r;
	float nl = texture(noise_large, wpos.xz * 0.02).r;
	vec3 col;
	float rough;
	float paint = 0.0;
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	float dirt_k = 0.0;                           // how much of this pixel is verge ground (wet mud look)
	if (surface_kind == 0 || surface_kind == 4) {
		// Asphalt / concrete with aggregate, patches and darker tyre tracks.
		vec3 base = surface_kind == 0 ? vec3(0.085, 0.087, 0.09) : vec3(0.42, 0.41, 0.39);
		if (surface_kind == 4) {
			// Bridge deck ends: patchy asphalt overlay thinning out into the concrete.
			float fade = smoothstep(0.35, 0.65, COLOR.g + (nd - 0.5) * 0.7 + (nf - 0.5) * 0.25);
			base = mix(base, vec3(0.085, 0.087, 0.09), fade);
		}
		col = base * (0.82 + nf * 0.3 + nd * 0.15);
		float patch = smoothstep(0.66, 0.7, nl) * (surface_kind == 0 ? 1.0 : 0.0);
		col = mix(col, base * 0.75, patch);
		float lane_w = road_width / float(lanes * 2);
		float in_lane = fract(abs(x) / lane_w);
		float tracks = (1.0 - smoothstep(0.08, 0.16, abs(in_lane - 0.28))) + (1.0 - smoothstep(0.08, 0.16, abs(in_lane - 0.72)));
		col *= 1.0 - tracks * 0.12 * step(abs(x), road_width * 0.5) * step(0.01, shoulder);
		rough = 0.82 - tracks * 0.08;
		// Shoulder slightly lighter, older asphalt.
		if (abs(x) > road_width * 0.5) {
			col *= 1.15;
		}
		// Markings
		float half_w = road_width * 0.5;
		float edge = line_mask(abs(x), half_w - 0.12, 0.075);
		float dash = step(fract(along / 12.0), 0.42);
		if (marking == 1) {
			paint = max(paint, edge);
			paint = max(paint, line_mask(x, 0.0, 0.07) * dash);
		} else if (marking == 2) {
			paint = max(paint, edge);
			// Double solid centre line (yellow) + dashed lane dividers.
			float c = max(line_mask(x, -0.16, 0.07), line_mask(x, 0.16, 0.07));
			if (c > 0.0) {
				paint_col = mix(paint_col, vec3(0.95, 0.72, 0.12), c);
			}
			paint = max(paint, c);
			for (int i = 1; i < 4; i++) {
				if (i >= lanes) break;
				float o = lane_w * float(i);
				float lmask = max(line_mask(x, o, 0.07), line_mask(x, -o, 0.07)) * step(fract(along / 15.0), 0.33);
				paint = max(paint, lmask);
			}
		} else if (marking == 3) {
			paint = max(paint, line_mask(x, 0.0, 0.06) * step(fract(along / 6.0), 0.5));
		}
		paint *= 0.75 + nf * 0.35;
		paint *= step(0.08, nd + 0.6);
		col = mix(col, paint_col, clamp(paint, 0.0, 1.0));
		rough = mix(rough, 0.6, paint);
		// Dirty edge: dust and grit first, packed soil (with grass poking through) further out.
		float hw = road_width * 0.5;
		float ed = abs(x) - hw;                                   // metres past the lane edge
		float irr = (nd - 0.5) * 0.55 + (nf - 0.5) * 0.25;       // ragged border
		float wd = mix(0.45, 1.5, smoothstep(0.25, 0.75, nl));   // transition width varies along the road
		float endk = COLOR.b + (nd - 0.5) * 0.5;                  // dead-end apron: runs out into dirt
		float dust_k = smoothstep(0.0, 1.0, (ed + irr) / wd) * COLOR.r;
		float soil_k = smoothstep(0.0, 1.0, (ed + irr * 1.4 - 0.2 - wd * 0.25) / wd) * COLOR.r;
		dust_k = max(dust_k, smoothstep(0.0, 0.6, endk));
		soil_k = max(soil_k, smoothstep(0.3, 0.9, endk));
		// The skirt always ends in the terrain's verge colour, whatever the strength.
		soil_k = max(soil_k, smoothstep(shoulder + 0.3, shoulder + 1.1, ed));
		float keep = 1.0 - paint * 0.75;                          // paint stays readable through the dust
		vec3 dust = mix(VERGE_DUST, VERGE_GRIT, smoothstep(0.55, 0.8, nf) * 0.8) * (0.8 + nd * 0.4);
		col = mix(col, dust, dust_k * 0.85 * keep);
		float verge_amt = soil_k * keep;
		vec3 soil = VERGE_SOIL * (0.8 + nf * 0.4);
		float grassy = smoothstep(0.62, 0.8, nd * 0.6 + nl * 0.5 + (nf - 0.5) * 0.3) * smoothstep(0.3, 0.9, soil_k);
		soil = mix(soil, VERGE_GRASS * (0.8 + nf * 0.5), grassy * 0.7);
		col = mix(col, soil, verge_amt);
		rough = mix(rough, 0.95, max(dust_k * 0.7, verge_amt));
		dirt_k = max(dust_k * 0.4, verge_amt);
	} else {
		// Unpaved: dirt / gravel / sand with two worn wheel ruts.
		vec3 a = surface_kind == 1 ? vec3(0.42, 0.33, 0.23) : (surface_kind == 2 ? vec3(0.4, 0.375, 0.34) : vec3(0.82, 0.74, 0.55));
		vec3 b = surface_kind == 1 ? vec3(0.32, 0.24, 0.16) : (surface_kind == 2 ? vec3(0.3, 0.285, 0.26) : vec3(0.72, 0.64, 0.46));
		col = mix(a, b, nf * 0.7 + nd * 0.3);
		float rut = (1.0 - smoothstep(0.25, 0.6, abs(abs(x) - 1.0)));
		col = mix(col, b * 0.85, rut * 0.6);
		// grass strip in the middle of gravel tracks
		if (surface_kind == 2) {
			col = mix(col, vec3(0.3, 0.36, 0.15), (1.0 - smoothstep(0.15, 0.4, abs(x))) * smoothstep(0.4, 0.6, nd));
		}
		rough = 0.95;
		// The edge of an unpaved road melts into the verge ground (same colour as the terrain beside it).
		float ed = abs(x) - road_width * 0.5;
		float irr = (nd - 0.5) * 0.6 + (nf - 0.5) * 0.3;
		float soil_k = max(smoothstep(0.0, 1.0, (ed + 0.7 + irr) / 1.2), smoothstep(shoulder + 0.3, shoulder + 1.1, ed));
		soil_k = max(soil_k, smoothstep(0.3, 0.9, COLOR.b + (nd - 0.5) * 0.5));
		vec3 soil = VERGE_SOIL * (0.8 + nf * 0.4);
		float grassy = smoothstep(0.62, 0.8, nd * 0.6 + nl * 0.5 + (nf - 0.5) * 0.3) * smoothstep(0.4, 1.0, soil_k);
		soil = mix(soil, VERGE_GRASS * (0.8 + nf * 0.5), grassy * 0.7);
		col = mix(col, soil, soil_k);
		dirt_k = soil_k;
	}
	float open_sky = 1.0 - clamp(covered, 0.0, 1.0);
	// Snow at altitude
	col = mix(col, vec3(0.88, 0.9, 0.94), snow_cover * open_sky * smoothstep(0.3, 0.8, abs(x) / (total * 0.5) + nd * 0.3));
	// Wet: darker with glossy puddles (never under a roof)
	float wet = wetness * open_sky;
	float puddle = smoothstep(0.55, 0.7, nl + nd * 0.15);
	col *= 1.0 - wet * mix(0.35, 0.28, dirt_k);
	// Wet soil is dark and satin like the terrain's, not mirror-glossy; puddles only on the paving.
	rough = mix(rough, mix(mix(0.32, 0.06, puddle), 0.27, dirt_k), wet);
	ALBEDO = col;
	ROUGHNESS = mix(rough, max(rough, 0.9), covered);
	SPECULAR = (0.4 + wet * 0.35) * mix(1.0, 0.3, covered);
	// The tube roof shades the sky's ambient light and reflections; lamps (direct light) are unaffected.
	AO = mix(1.0, 0.4, covered);
	AO_LIGHT_AFFECT = 0.0;
}
