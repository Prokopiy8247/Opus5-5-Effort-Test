extends RefCounted
## Pure functions for the sky: sun / moon positions from the clock and colour ramps keyed by sun elevation.
## World axes: north = -Z, east = +X, up = +Y. Mid-latitude late-spring sun: rises ~06:35, sets ~19:25,
## peaks ~60 deg at 13:00.

const LATITUDE := 0.6632          # 38 deg
const DECLINATION := 0.1396       # 8 deg
const SOLAR_NOON := 13.0
const MOON_DECLINATION := -0.3316
const MOON_LAG := 3.0107          # hour angle offset: a near-full moon rising ~20:30, ~25 deg up by midnight

# Elevation (deg) -> [zenith, horizon, sunward glow] in linear HDR.
const SKY_KEYS: Array = [
	[-18.0, Color(0.0022, 0.0045, 0.013), Color(0.007, 0.012, 0.028), Color(0.0, 0.0, 0.0)],
	[-10.0, Color(0.006, 0.013, 0.038), Color(0.024, 0.034, 0.075), Color(0.03, 0.02, 0.03)],
	[-5.0, Color(0.024, 0.05, 0.13), Color(0.13, 0.11, 0.16), Color(0.32, 0.12, 0.06)],
	[-1.0, Color(0.06, 0.12, 0.29), Color(0.55, 0.3, 0.22), Color(1.2, 0.42, 0.12)],
	[3.0, Color(0.1, 0.22, 0.5), Color(0.95, 0.6, 0.36), Color(1.5, 0.66, 0.22)],
	[9.0, Color(0.1, 0.26, 0.62), Color(0.88, 0.76, 0.64), Color(0.7, 0.36, 0.12)],
	[20.0, Color(0.08, 0.25, 0.72), Color(0.62, 0.76, 0.9), Color(0.12, 0.08, 0.04)],
	[45.0, Color(0.055, 0.21, 0.7), Color(0.56, 0.72, 0.92), Color(0.0, 0.0, 0.0)],
]

# Elevation (deg) -> sun light colour, energy.
const SUN_KEYS: Array = [
	[-3.0, Color(1.0, 0.35, 0.12), 0.0],
	[0.5, Color(1.0, 0.42, 0.16), 0.25],
	[4.0, Color(1.0, 0.6, 0.32), 0.95],
	[10.0, Color(1.0, 0.78, 0.55), 1.45],
	[22.0, Color(1.0, 0.9, 0.76), 1.75],
	[45.0, Color(1.0, 0.96, 0.89), 1.95],
]


static func _hour_angle(hour: float) -> float:
	return (hour - SOLAR_NOON) / 24.0 * TAU


static func _horizon_dir(h: float, decl: float) -> Vector3:
	var east := -cos(decl) * sin(h)
	var north := sin(decl) * cos(LATITUDE) - cos(decl) * cos(h) * sin(LATITUDE)
	var up := sin(decl) * sin(LATITUDE) + cos(decl) * cos(h) * cos(LATITUDE)
	return Vector3(east, up, -north).normalized()


## Unit vector from the ground towards the sun.
static func sun_direction(hour: float) -> Vector3:
	return _horizon_dir(_hour_angle(hour), DECLINATION)


static func moon_direction(hour: float) -> Vector3:
	return _horizon_dir(_hour_angle(hour) + MOON_LAG, MOON_DECLINATION)


static func elevation_deg(dir: Vector3) -> float:
	return rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))


static func _find(keys: Array, el: float) -> Vector2i:
	if el <= float(keys[0][0]):
		return Vector2i(0, 0)
	for i in range(1, keys.size()):
		if el <= float(keys[i][0]):
			return Vector2i(i - 1, i)
	return Vector2i(keys.size() - 1, keys.size() - 1)


static func _t(keys: Array, ij: Vector2i, el: float) -> float:
	if ij.x == ij.y:
		return 0.0
	var a := float(keys[ij.x][0])
	var b := float(keys[ij.y][0])
	return smoothstep(0.0, 1.0, (el - a) / (b - a))


## Returns [zenith, horizon, glow] for a sun elevation in degrees.
static func sky_colors(el: float) -> Array[Color]:
	var ij := _find(SKY_KEYS, el)
	var t := _t(SKY_KEYS, ij, el)
	var out: Array[Color] = []
	for k in range(1, 4):
		out.append((SKY_KEYS[ij.x][k] as Color).lerp(SKY_KEYS[ij.y][k], t))
	return out


static func sun_color(el: float) -> Color:
	var ij := _find(SUN_KEYS, el)
	return (SUN_KEYS[ij.x][1] as Color).lerp(SUN_KEYS[ij.y][1], _t(SUN_KEYS, ij, el))


static func sun_energy(el: float) -> float:
	var ij := _find(SUN_KEYS, el)
	return lerpf(SUN_KEYS[ij.x][2], SUN_KEYS[ij.y][2], _t(SUN_KEYS, ij, el))


## 0 in daylight .. 1 in full night, from the sun elevation.
static func darkness(el: float) -> float:
	return 1.0 - smoothstep(-9.0, 2.0, el)
