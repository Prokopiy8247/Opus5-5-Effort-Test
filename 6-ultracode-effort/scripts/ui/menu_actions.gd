extends RefCounted
## Actions shared by the console, pause menu and debug menu.

const FINISHES: Array[String] = ["gloss", "matte", "metallic"]
const STRIPE_NAMES: Array[String] = ["None", "Twin stripes", "Centre stripe", "Side stripe", "Rally livery", "Two-tone"]
const TUNE_LABELS := {
	"final_drive": ["Final drive", "Shorter = stronger pull in each gear but a lower top speed; longer = taller gears, fewer shifts (stock is set for top speed)"],
	"tire_pressure": ["Tyre pressure", "Lower = more grip, higher = looser and easier to slide"],
	"camber": ["Grip balance", "Shift cornering grip toward the rear (+) or front (-)"],
	"spring_f": ["Springs front", "Stiffer front = sharper turn-in, less compliance"],
	"spring_r": ["Springs rear", "Stiffer rear = more rotation"],
	"arb_f": ["Anti-roll front", "Less body roll, more understeer"],
	"arb_r": ["Anti-roll rear", "Less body roll, more oversteer"],
	"aero_f": ["Aero front", "Front downforce: grip vs drag"],
	"aero_r": ["Aero rear", "Rear downforce: high-speed stability"],
	"brake_bias": ["Brake bias", "Move braking toward the front (+) or rear (-)"],
	"ride_height": ["Ride height", "Lower = flatter, higher = rough-road clearance"],
}


## Colour from a paint name, html hex (with or without #) or a Godot colour name. Returns r < 0 when invalid.
static func parse_color(s: String) -> Color:
	var k := s.strip_edges().to_lower()
	if Game.PAINT_COLORS.has(k):
		return Game.PAINT_COLORS[k]
	var hex := k.trim_prefix("#")
	if (hex.length() == 6 or hex.length() == 3 or hex.length() == 8) and hex.is_valid_hex_number() and Color.html_is_valid(hex):
		return Color.html(hex)
	return Color.from_string(k, Color(-1, -1, -1))


static func color_name(c: Color) -> String:
	for k: String in Game.PAINT_COLORS:
		if same_color(Game.PAINT_COLORS[k], c):
			return k.capitalize()
	return "#" + c.to_html(false).to_upper()


## Paint colours are saved as 8-bit html, so compare at that precision (a reloaded preset still matches).
static func same_color(a: Color, b: Color) -> bool:
	return a.to_html(false) == b.to_html(false)


static func current_paint() -> Dictionary:
	var d := Game.current_car_data()
	return Game.get_paint(d.id) if d else {}


static func save_game() -> bool:
	return SaveGame.save_now()


## Loads the save file and puts the saved car back where it was.
static func load_game() -> bool:
	if not SaveGame.has_save():
		return false
	var d: Dictionary = SaveGame.load_now()
	if d.is_empty():
		return false
	Game.spawn_car(int(d.get("car_index", Game.current_car_index)), false)
	if d.has("position") and Game.main != null:
		var arr: Array = d["position"]
		var h := float(d.get("heading", 0.0))
		Game.main.teleport_to({"position": Vector3(float(arr[0]), float(arr[1]), float(arr[2])), "forward": Vector3(sin(h), 0.0, cos(h))})
	if d.has("time_of_day"):
		Game.set_time_of_day(float(d["time_of_day"]))
	if d.has("weather"):
		Game.set_weather(String(d["weather"]), true)
	Game.stats_changed.emit()
	return true


static func quit_game(tree: SceneTree) -> void:
	if SaveGame.enabled and Game.player_car != null:
		SaveGame.save_now()
	tree.quit()


## Teleport targets grouped for menus: [["Regions", [...]], ["Long roads", [...]], ["Places", [...]]]
static func grouped_targets() -> Array:
	var regions: Array = []
	var roads: Array = []
	var places: Array = []
	for t: Dictionary in Game.get_teleport_targets():
		match String(t.get("kind", "")):
			"region":
				regions.append(t)
			"road":
				roads.append(t)
			_:
				places.append(t)
	return [["Regions", regions], ["Long-road starts", roads], ["Points of interest", places]]


static func upgrade_name(slot: String) -> String:
	var u := Tuning.upgrade_data(slot)
	if u != null and u.slot == slot and u.display_name != "":
		return u.display_name
	return {"engine": "Engine", "tires": "Tyres", "suspension": "Suspension", "brakes": "Brakes", "weight": "Weight Reduction", "aero": "Aero"}.get(slot, slot.capitalize())


static func level_name(slot: String, lvl: int) -> String:
	var u := Tuning.upgrade_data(slot)
	if u != null and lvl < u.level_names.size():
		return u.level_names[lvl]
	return ["Stock", "Street", "Sport", "Race"][clampi(lvl, 0, 3)]


static func tune_label(key: String) -> String:
	return TUNE_LABELS[key][0] if TUNE_LABELS.has(key) else key.capitalize()


static func tune_help(key: String) -> String:
	return TUNE_LABELS[key][1] if TUNE_LABELS.has(key) else ""


static func tune_text(key: String, v: float) -> String:
	if key == "ride_height":
		return "%+d mm" % roundi(v * 1000.0)
	if absf(v) < 0.0005:
		return "0%"
	return "%+d%%" % roundi(v * 100.0)


## Rebuilds the player car with the current upgrades/tuning (keeps position and speed).
static func rebuild_car() -> void:
	Game.spawn_car(Game.current_car_index, true)
	Game.stats_changed.emit()
