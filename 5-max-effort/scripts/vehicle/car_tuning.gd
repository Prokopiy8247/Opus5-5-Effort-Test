class_name CarTuning
extends RefCounted
## Data-driven upgrades and tuning. A runtime copy of a CarDefinition is produced from the base
## definition + upgrade levels (res://data/upgrades/*.tres) + tuning sliders.

const PARTS := ["engine", "tires", "suspension", "brakes", "weight", "aero"]
const TUNING_DEFAULTS := {
	"final_drive": 1.0, "brake_bias": -1.0, "tire_balance": 0.0, "springs": 1.0, "arb_front": 1.0,
	"arb_rear": 1.0, "downforce": 1.0, "diff_lock": -1.0, "ride_height": 0.0, "steer_lock": 1.0,
}
const TUNING_RANGES := {
	"final_drive": [0.85, 1.18], "brake_bias": [0.5, 0.78], "tire_balance": [-0.08, 0.08], "springs": [0.75, 1.4],
	"arb_front": [0.4, 1.8], "arb_rear": [0.4, 1.8], "downforce": [0.5, 1.6], "diff_lock": [0.0, 1.0],
	"ride_height": [-0.03, 0.05], "steer_lock": [0.85, 1.15],
}

static var _upgrades: Dictionary = {}


static func upgrades() -> Dictionary:
	if _upgrades.is_empty():
		var dir := "res://data/upgrades/"
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				var fname := f.trim_suffix(".remap")
				if not fname.ends_with(".tres"):
					continue
				var u := load(dir + fname) as UpgradeDef
				if u != null:
					_upgrades["%s_%d" % [u.part, u.level]] = u
	return _upgrades


static func get_upgrade(part: String, level: int) -> UpgradeDef:
	return upgrades().get("%s_%d" % [part, level])


static func build(base: CarDefinition, levels: Dictionary, tuning: Dictionary) -> CarDefinition:
	var d := base.duplicate(true) as CarDefinition
	for part in PARTS:
		var lvl := int(levels.get(part, 0))
		for l in range(1, lvl + 1):
			var u := get_upgrade(part, l)
			if u == null:
				continue
			d.max_torque_nm *= u.torque_mult
			d.mass *= u.mass_mult
			d.tire_grip *= u.grip_mult
			d.offroad_grip *= u.offroad_mult
			d.brake_torque *= u.brake_mult
			d.downforce_area += u.downforce_add
			d.drag_area *= u.drag_mult
			d.spring_hz_front *= u.spring_mult
			d.spring_hz_rear *= u.spring_mult
			d.anti_roll_front *= u.arb_mult
			d.anti_roll_rear *= u.arb_mult
			d.redline_rpm += u.redline_add
	var t := TUNING_DEFAULTS.duplicate()
	t.merge(tuning, true)
	d.final_drive *= float(t["final_drive"])
	if float(t["brake_bias"]) >= 0.0:
		d.brake_bias = float(t["brake_bias"])
	d.grip_front *= 1.0 + float(t["tire_balance"])
	d.grip_rear *= 1.0 - float(t["tire_balance"])
	d.spring_hz_front *= sqrt(float(t["springs"]))
	d.spring_hz_rear *= sqrt(float(t["springs"]))
	d.anti_roll_front *= float(t["arb_front"])
	d.anti_roll_rear *= float(t["arb_rear"])
	d.downforce_area *= float(t["downforce"])
	if float(t["diff_lock"]) >= 0.0:
		d.diff_lock = float(t["diff_lock"])
	d.com_offset.y += float(t["ride_height"]) * 0.6
	d.travel_down += float(t["ride_height"])
	d.steer_lock_deg *= float(t["steer_lock"])
	# keep top speed consistent: more drag with more downforce
	d.drag_area += (d.downforce_area - base.downforce_area) * 0.12
	d.power_kw = snappedf(d.peak_power_kw(), 1.0)
	return d


static func stats(d: CarDefinition) -> Dictionary:
	## 0..10 presentation stats derived from the handling data.
	var pw := d.peak_power_kw() / (d.mass / 1000.0)
	var top := sqrt(maxf(d.peak_power_kw() * 1000.0 * 0.85 / (0.5 * 1.225 * maxf(d.drag_area, 0.2)), 1.0))
	top = pow(d.peak_power_kw() * 1000.0 * 0.85 / (0.5 * 1.225 * maxf(d.drag_area, 0.2)), 1.0 / 3.0) * 3.6
	var grip := d.tire_grip * (d.grip_front + d.grip_rear) * 0.5
	var handling := grip * 6.0 + d.downforce_area * 1.6 + (d.anti_roll_front + d.anti_roll_rear) / 20000.0 - (d.mass - 1300.0) / 900.0
	var braking := d.brake_torque / d.mass * 2.2 + grip * 2.5
	var offroad := d.offroad_grip * 4.5 + (d.travel_up + d.travel_down) * 14.0 + (1.5 if d.drivetrain == CarDefinition.Drivetrain.AWD else 0.0)
	return {
		"speed": clampf((minf(top, d.top_speed_kmh * 1.05) - 140.0) / 21.0, 0.5, 10.0),
		"acceleration": clampf(pw / 45.0 + (1.2 if d.drivetrain == CarDefinition.Drivetrain.AWD else 0.0), 0.5, 10.0),
		"handling": clampf(handling, 0.5, 10.0),
		"braking": clampf(braking, 0.5, 10.0),
		"offroad": clampf(offroad, 0.5, 10.0),
	}


static func performance_index(d: CarDefinition) -> int:
	var pw := d.peak_power_kw() / (d.mass / 1000.0)
	var grip := (d.grip_front + d.grip_rear) * 0.5 * d.tire_grip
	return clampi(int(130.0 + pw * 1.2 + grip * 260.0 + d.top_speed_kmh * 0.55 + d.downforce_area * 120.0), 100, 998)
