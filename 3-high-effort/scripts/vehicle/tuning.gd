class_name Tuning
extends RefCounted
## Applies stored upgrades + tuning sliders to a Car, and computes the resulting PI/class.

const UPGRADE_DIR := "res://data/upgrades/"
## tuning slider: key -> [min, max, default, label, unit]
const SLIDERS := {
	"final": [0.85, 1.15, 1.0, "Final drive", "x"],
	"pressure": [-1.0, 1.0, 0.0, "Tyre pressure", ""],
	"camber": [-3.0, 0.0, -1.0, "Camber", "deg"],
	"spring": [0.7, 1.4, 1.0, "Spring stiffness", "x"],
	"arb": [0.5, 1.6, 1.0, "Anti-roll bars", "x"],
	"aero": [0.5, 1.6, 1.0, "Downforce", "x"],
	"bias": [-0.1, 0.1, 0.0, "Brake bias (front +)", ""],
}

static var _defs: Array[UpgradeDef] = []


static func defs() -> Array[UpgradeDef]:
	if _defs.is_empty():
		var files := ResourceLoader.list_directory(UPGRADE_DIR)
		var names: Array[String] = []
		for f in files:
			if f.ends_with(".tres"):
				names.append(f)
		names.sort()
		for f in names:
			var d := load(UPGRADE_DIR + f) as UpgradeDef
			if d:
				_defs.append(d)
	return _defs


static func apply(car: Car) -> void:
	var c := Game.custom_for(car.spec.id)
	var mods := {"mod_power": 1.0, "mod_grip": 1.0, "mod_brake": 1.0, "mod_mass": 1.0, "mod_spring": 1.0,
		"mod_arb": 1.0, "mod_downforce": 1.0, "mod_top": 1.0}
	var ups: Dictionary = c.get("upgrades", {})
	for d in defs():
		var lvl := int(ups.get(d.key, 0))
		for m in d.effects:
			var arr: Array = d.effects[m]
			mods[m] = float(mods.get(m, 1.0)) * float(arr[clampi(lvl, 0, arr.size() - 1)])
	var tune: Dictionary = c.get("tune", {})
	car.mod_power = mods.mod_power
	car.mod_grip = mods.mod_grip
	car.mod_brake = mods.mod_brake
	car.mod_mass = mods.mod_mass
	car.mod_top = mods.mod_top
	car.mod_spring = mods.mod_spring * float(tune.get("spring", 1.0))
	car.mod_arb = mods.mod_arb * float(tune.get("arb", 1.0))
	car.mod_downforce = mods.mod_downforce * float(tune.get("aero", 1.0))
	car.mod_final = float(tune.get("final", 1.0))
	car.mod_tire_pressure = float(tune.get("pressure", 0.0))
	car.mod_camber = float(tune.get("camber", -1.0)) + 1.0
	car.mod_brake_bias = float(tune.get("bias", 0.0))
	car.refresh_tuning()


static func pi_of(spec: CarSpec) -> int:
	var c := Game.custom_for(spec.id)
	var ups: Dictionary = c.get("upgrades", {})
	var pi := spec.pi
	for d in defs():
		pi += int(ups.get(d.key, 0)) * d.pi_per_level
	return mini(pi, 999)


static func class_of(pi: int) -> String:
	if pi >= 999:
		return "X"
	if pi > 900:
		return "S2"
	if pi > 800:
		return "S1"
	if pi > 700:
		return "A"
	if pi > 600:
		return "B"
	if pi > 500:
		return "C"
	return "D"


static func class_color(cls: String) -> Color:
	match cls:
		"D":
			return Color(0.35, 0.75, 0.95)
		"C":
			return Color(0.95, 0.85, 0.25)
		"B":
			return Color(1.0, 0.55, 0.2)
		"A":
			return Color(0.95, 0.25, 0.3)
		"S1":
			return Color(0.75, 0.35, 0.95)
		"S2":
			return Color(0.3, 0.45, 1.0)
	return Color(0.3, 0.95, 0.5)
