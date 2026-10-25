extends Resource
## One placed road activity (from data/events/events.json or the runtime planner). No class_name: preload it.
## gates: road arclengths, cumulative inside the event (loops may exceed the road length).
## thresholds: [bronze, silver, gold] (= 1..3 stars); km/h, points, metres or seconds depending on kind.

@export var id: String = ""
@export var kind: StringName = &""
@export var title: String = ""
@export var road_id: String = ""
## +1 / -1 travel direction along the road; 0 = either direction.
@export var dir: int = 0
@export var gates: PackedFloat32Array = PackedFloat32Array()
@export var thresholds: PackedFloat32Array = PackedFloat32Array()
@export var position: Vector3 = Vector3.ZERO
@export var length: float = 0.0
@export var extra: Dictionary = {}


func fill(d: Dictionary) -> void:
	id = String(d.get("id", ""))
	kind = StringName(String(d.get("kind", "")))
	title = String(d.get("title", id))
	road_id = String(d.get("road", ""))
	dir = int(d.get("dir", 0))
	gates = PackedFloat32Array(d.get("gates", []))
	thresholds = PackedFloat32Array(d.get("thresholds", []))
	var p: Array = d.get("pos", [0, 0, 0])
	position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	length = float(d.get("length", 0.0))
	extra = d.get("extra", {})
