class_name Tuning
extends RefCounted
## Builds an effective CarData from base data + upgrade levels + tuning sliders.
## Upgrade definitions are data-driven (res://data/upgrades/<slot>.tres, UpgradeData).

const SLOTS: Array[String] = ["engine", "tires", "suspension", "brakes", "weight", "aero"]
const MAX_LEVEL := 3

## Tuning keys with (min, max, default) in normalised units shown in the tuning menu.
const TUNE_SPEC := {
	"final_drive": [-0.15, 0.15, 0.0],   # relative change of the final drive ratio
	"tire_pressure": [-0.2, 0.2, 0.0],   # grip vs slide trade-off
	"camber": [-0.1, 0.1, 0.0],          # front/rear grip balance (+ = more rear grip)
	"spring_f": [-0.3, 0.3, 0.0],
	"spring_r": [-0.3, 0.3, 0.0],
	"arb_f": [-0.5, 0.5, 0.0],
	"arb_r": [-0.5, 0.5, 0.0],
	"aero_f": [-0.5, 0.5, 0.0],
	"aero_r": [-0.5, 0.5, 0.0],
	"brake_bias": [-0.1, 0.1, 0.0],
	"ride_height": [-0.04, 0.06, 0.0],
}

static var _upgrade_cache: Dictionary = {}


static func upgrade_data(slot: String) -> UpgradeData:
	if not _upgrade_cache.has(slot):
		var path := "res://data/upgrades/%s.tres" % slot
		_upgrade_cache[slot] = load(path) if ResourceLoader.exists(path) else null
	return _upgrade_cache[slot]


static func build_effective(base: CarData, ups: Dictionary, tune: Dictionary) -> CarData:
	var d: CarData = base.duplicate(true)
	for slot in SLOTS:
		var lvl: int = clampi(int(ups.get(slot, 0)), 0, MAX_LEVEL)
		var u := upgrade_data(slot)
		if lvl <= 0 or u == null:
			continue
		var f := float(lvl)
		d.peak_torque *= 1.0 + u.torque_per_level * f
		d.max_rpm += u.rpm_per_level * f
		d.redline_rpm += u.rpm_per_level * f
		d.tire_grip *= 1.0 + u.grip_per_level * f
		d.spring_front *= 1.0 + u.stiffness_per_level * f
		d.spring_rear *= 1.0 + u.stiffness_per_level * f
		d.anti_roll_front *= 1.0 + u.stiffness_per_level * f
		d.anti_roll_rear *= 1.0 + u.stiffness_per_level * f
		d.ride_height -= u.lower_per_level * f
		d.brake_force *= 1.0 + u.brake_per_level * f
		d.mass *= 1.0 - u.weight_per_level * f
		d.downforce_front *= 1.0 + u.downforce_per_level * f
		d.downforce_rear *= 1.0 + u.downforce_per_level * f
		d.drag_area *= 1.0 + u.drag_per_level * f
		d.top_speed_kmh *= 1.0 + u.top_speed_per_level * f
	# Tuning sliders.
	# Final drive (+ = shorter): more wheel torque per gear, but top gear runs out of revs sooner. The top-speed
	# limit never sits above the rev limit in top gear (stock gearing leaves top speed to power and drag).
	d.final_drive *= 1.0 + float(tune.get("final_drive", 0.0))
	if d.top_speed_kmh > 0.0 and not d.gear_ratios.is_empty():
		var r_drive := d.wheel_radius_front if d.drivetrain == CarData.Drivetrain.FWD else d.wheel_radius_rear
		var v_rev := d.max_rpm * TAU / 60.0 / (d.gear_ratios[-1] * d.final_drive) * r_drive * 3.6
		d.top_speed_kmh = minf(d.top_speed_kmh, v_rev * 0.99)
	# Tyre pressure: lower = more grip and a softer, more progressive slide (lazier response, more rolling
	# drag); higher = less grip and a sharper break-away (looser, easier to slide).
	var tp := float(tune.get("tire_pressure", 0.0))
	d.tire_grip *= 1.0 - tp * 0.15
	d.slide_grip = clampf(d.slide_grip - tp * 0.25, 0.5, 0.98)
	d.peak_slip_deg *= 1.0 - tp * 0.5
	d.rolling_resistance *= 1.0 - tp * 0.5
	var camber := float(tune.get("camber", 0.0))
	d.grip_rear *= 1.0 + camber
	d.grip_front *= 1.0 - camber
	d.spring_front *= 1.0 + float(tune.get("spring_f", 0.0))
	d.spring_rear *= 1.0 + float(tune.get("spring_r", 0.0))
	d.anti_roll_front *= 1.0 + float(tune.get("arb_f", 0.0))
	d.anti_roll_rear *= 1.0 + float(tune.get("arb_r", 0.0))
	d.downforce_front *= 1.0 + float(tune.get("aero_f", 0.0))
	d.downforce_rear *= 1.0 + float(tune.get("aero_r", 0.0))
	d.brake_bias = clampf(d.brake_bias + float(tune.get("brake_bias", 0.0)), 0.4, 0.8)
	d.ride_height += float(tune.get("ride_height", 0.0))
	return d


## Performance index heuristic (100..999) and class letter from handling data.
static func performance_index(d: CarData) -> int:
	var pw := d.peak_power_hp() / (d.mass / 1000.0)  # hp per tonne
	var pi := 120.0 + 23.0 * sqrt(pw) + (d.tire_grip - 1.0) * 600.0 + (d.top_speed_kmh - 200.0) * 0.8
	pi += (d.downforce_front + d.downforce_rear) * 40.0
	if d.drivetrain == CarData.Drivetrain.AWD:
		pi += 25.0
	return clampi(int(pi), 100, 999)


static func class_for(pi: int) -> String:
	if pi >= 901:
		return "X"
	if pi >= 801:
		return "S2"
	if pi >= 701:
		return "S1"
	if pi >= 601:
		return "A"
	if pi >= 501:
		return "B"
	if pi >= 401:
		return "C"
	return "D"
