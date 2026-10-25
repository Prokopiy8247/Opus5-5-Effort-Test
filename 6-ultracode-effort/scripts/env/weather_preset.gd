extends Resource
## One weather state (data/weather/<id>.tres). All numeric fields are blended linearly while the
## weather changes, so a transition is simply blend(from, to, t). Defaults live in configure() and are
## written to disk by tools/make_weather_presets.gd.

const BLENDED: Array[StringName] = [
	&"cloud_coverage", &"cloud_darkness", &"overcast", &"cirrus", &"cloud_speed", &"haze",
	&"sun_energy", &"ambient_energy", &"shadow_softness", &"exposure", &"saturation", &"contrast",
	&"fog_density", &"fog_color", &"fog_tint", &"aerial_perspective", &"fog_sky_affect", &"volumetric_density",
	&"rain", &"wind", &"wetness", &"lightning_per_minute", &"lights_on", &"sky_tint", &"low_fog",
]

@export var id: StringName = &"clear"
@export var display_name: String = "Clear"

@export_group("Sky")
## 0..1 share of the sky covered by the low cumulus layer.
@export_range(0.0, 1.0) var cloud_coverage: float = 0.3
## 0 = bright fair-weather clouds, 1 = dark storm bases.
@export_range(0.0, 1.0) var cloud_darkness: float = 0.0
## Flattens the blue sky gradient into a uniform cloud deck.
@export_range(0.0, 1.0) var overcast: float = 0.0
## High streaky clouds.
@export_range(0.0, 1.0) var cirrus: float = 0.4
@export var cloud_speed: float = 1.0
## Horizon haze strength.
@export_range(0.0, 1.0) var haze: float = 0.25
## Multiplies the clear-sky colours (slight grading per weather).
@export var sky_tint: Color = Color(1, 1, 1)

@export_group("Light")
@export var sun_energy: float = 1.0
@export var ambient_energy: float = 1.0
## 0 = crisp shadows, 1 = soft diffuse shadows.
@export_range(0.0, 1.0) var shadow_softness: float = 0.0
@export var exposure: float = 1.0
@export var saturation: float = 1.0
@export var contrast: float = 1.0

@export_group("Fog")
## Exponential fog density (1/m).
@export var fog_density: float = 0.00022
## Fog colour for weather fog (multiplied by the current light level).
@export var fog_color: Color = Color(0.7, 0.76, 0.84)
## 0 = fog takes the sky colour behind objects, 1 = flat fog_color.
@export_range(0.0, 1.0) var fog_tint: float = 0.0
@export_range(0.0, 1.0) var aerial_perspective: float = 0.9
@export_range(0.0, 1.0) var fog_sky_affect: float = 0.0
@export var volumetric_density: float = 0.0
## Height-fog density of a low fog layer that follows the terrain under the camera (fog weather).
@export var low_fog: float = 0.0

@export_group("Precipitation")
@export_range(0.0, 1.0) var rain: float = 0.0
@export_range(0.0, 1.0) var wind: float = 0.15
## Surface wetness this weather converges to.
@export_range(0.0, 1.0) var wetness: float = 0.0
@export var lightning_per_minute: float = 0.0
## 1 = vehicles switch their lights on even in daylight.
@export_range(0.0, 1.0) var lights_on: float = 0.0


func blend(a: Resource, b: Resource, t: float) -> void:
	for p in BLENDED:
		set(p, lerp(a.get(p), b.get(p), t))
	id = b.get(&"id")
	display_name = b.get(&"display_name")


func copy_from(src: Resource) -> void:
	blend(src, src, 1.0)


func configure(weather_id: StringName) -> void:
	id = weather_id
	match weather_id:
		&"clear":
			display_name = "Clear"
			cloud_coverage = 0.34
			cloud_darkness = 0.0
			overcast = 0.0
			cirrus = 0.45
			cloud_speed = 1.0
			haze = 0.22
			sky_tint = Color(1.0, 1.0, 1.0)
			sun_energy = 1.0
			ambient_energy = 0.8
			shadow_softness = 0.0
			exposure = 0.9
			saturation = 1.22
			contrast = 1.06
			fog_density = 0.00016
			fog_color = Color(0.72, 0.8, 0.9)
			fog_tint = 0.0
			aerial_perspective = 0.92
			fog_sky_affect = 0.0
			volumetric_density = 0.0
			rain = 0.0
			wind = 0.15
			wetness = 0.0
			lightning_per_minute = 0.0
			lights_on = 0.0
		&"cloudy":
			display_name = "Cloudy"
			cloud_coverage = 0.8
			cloud_darkness = 0.35
			overcast = 0.55
			cirrus = 0.25
			cloud_speed = 1.5
			haze = 0.35
			sky_tint = Color(0.94, 0.96, 1.0)
			sun_energy = 0.45
			ambient_energy = 1.15
			shadow_softness = 0.55
			exposure = 1.08
			saturation = 1.04
			contrast = 1.0
			fog_density = 0.00032
			fog_color = Color(0.68, 0.72, 0.78)
			fog_tint = 0.3
			aerial_perspective = 0.75
			fog_sky_affect = 0.08
			volumetric_density = 0.0012
			rain = 0.0
			wind = 0.5
			wetness = 0.0
			lightning_per_minute = 0.0
			lights_on = 0.0
		&"rain":
			display_name = "Rain"
			cloud_coverage = 1.0
			cloud_darkness = 0.55
			overcast = 0.92
			cirrus = 0.0
			cloud_speed = 2.0
			haze = 0.55
			sky_tint = Color(0.9, 0.94, 1.0)
			sun_energy = 0.14
			ambient_energy = 1.05
			shadow_softness = 1.0
			exposure = 1.18
			saturation = 0.94
			contrast = 1.02
			fog_density = 0.0016
			fog_color = Color(0.55, 0.6, 0.66)
			fog_tint = 0.6
			aerial_perspective = 0.45
			fog_sky_affect = 0.25
			volumetric_density = 0.004
			wind = 0.55
			wetness = 0.85
			lightning_per_minute = 0.0
			lights_on = 1.0
			rain = 0.85
		&"fog":
			display_name = "Fog"
			cloud_coverage = 1.0
			cloud_darkness = 0.1
			overcast = 1.0
			cirrus = 0.0
			cloud_speed = 0.4
			haze = 1.0
			sky_tint = Color(0.96, 0.97, 1.0)
			sun_energy = 0.22
			ambient_energy = 1.2
			shadow_softness = 1.0
			exposure = 1.12
			saturation = 0.9
			contrast = 0.98
			fog_density = 0.0026
			fog_color = Color(0.74, 0.77, 0.8)
			fog_tint = 0.85
			aerial_perspective = 0.25
			fog_sky_affect = 0.9
			volumetric_density = 0.006
			low_fog = 0.0075
			rain = 0.0
			wind = 0.05
			wetness = 0.25
			lightning_per_minute = 0.0
			lights_on = 1.0
		&"storm":
			display_name = "Storm"
			cloud_coverage = 1.0
			cloud_darkness = 0.9
			overcast = 1.0
			cirrus = 0.0
			cloud_speed = 3.6
			haze = 0.7
			sky_tint = Color(0.82, 0.88, 1.0)
			sun_energy = 0.05
			ambient_energy = 0.72
			shadow_softness = 1.0
			exposure = 1.12
			saturation = 0.88
			contrast = 1.06
			fog_density = 0.0019
			fog_color = Color(0.4, 0.44, 0.5)
			fog_tint = 0.7
			aerial_perspective = 0.35
			fog_sky_affect = 0.35
			volumetric_density = 0.006
			low_fog = 0.003
			rain = 1.0
			wind = 1.0
			wetness = 1.0
			lightning_per_minute = 5.0
			lights_on = 1.0
