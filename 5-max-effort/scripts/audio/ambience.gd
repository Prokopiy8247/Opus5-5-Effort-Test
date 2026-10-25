class_name Ambience
extends Node
## Regional ambience at the camera: birdsong by day (strongest in the vale and highlands), crickets
## at night, surf on the coast; rain mutes the birds. Cross-faded loops from the procedural SoundBank.

const KEYS := ["birds", "crickets", "sea"]

var _players: Dictionary = {}
var _level: Dictionary = {}


func _ready() -> void:
	for k in KEYS:
		var p := AudioStreamPlayer.new()
		p.name = String(k).capitalize()
		p.stream = SoundBank.get_stream(k)
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_players[k] = p
		_level[k] = 0.0


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or Game.world == null or not ("data" in Game.world) or Game.environment == null:
		return
	var data: WorldData = Game.world.get("data")
	var env := Game.environment as EnvironmentController
	var p := cam.global_position
	var region := data.region_index(p.x, p.z)
	var dark := env.get_darkness()
	var wet := env.wetness
	var ground := data.height_at(p.x, p.z)
	var target := {
		"birds": (1.0 - dark) * (1.0 if region == 1 or region == 2 else 0.35) * (1.0 - wet * 0.85),
		"crickets": smoothstep(0.45, 0.8, dark) * (0.4 if region == 2 else 1.0) * (1.0 - wet * 0.7),
		"sea": (1.0 - smoothstep(4.0, 45.0, ground)) * (1.0 if region == 0 else 0.25),
	}
	var gains := {"birds": 0.55, "crickets": 0.45, "sea": 0.7}
	for k in KEYS:
		_level[k] = lerpf(float(_level[k]), float(target[k]), 1.0 - exp(-delta * 0.8))
		var lin := float(_level[k]) * float(gains[k])
		(_players[k] as AudioStreamPlayer).volume_db = linear_to_db(maxf(lin, 0.0001))
