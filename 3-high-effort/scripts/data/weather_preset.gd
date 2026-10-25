class_name WeatherPreset
extends Resource
## One weather state. The SkyWeather system blends between presets.

@export var key: String = "clear"
@export var display_name: String = "Clear"
@export_range(0.0, 1.0) var cloud_coverage: float = 0.2
@export_range(0.0, 1.0) var cloud_darkness: float = 0.0
@export var fog_density: float = 0.0004
@export var volumetric_fog: float = 0.0
@export_range(0.0, 1.0) var rain: float = 0.0
@export_range(0.0, 1.0) var wetness: float = 0.0
## Tyre grip multiplier applied to wet-sensitive surfaces.
@export var grip: float = 1.0
@export var wind: float = 0.3
@export var sun_energy: float = 1.0
@export var ambient_energy: float = 1.0
@export var lightning: bool = false
@export var tint: Color = Color(1, 1, 1)
@export var visibility_m: float = 6000.0
