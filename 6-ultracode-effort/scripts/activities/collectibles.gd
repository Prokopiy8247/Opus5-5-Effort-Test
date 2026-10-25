extends Node3D
## Festival Flags: 20 hidden collectibles (spinning waving flag + glow + light beam). An Area3D pickup on the
## trigger layer sees only the player car. Collected ids persist in Game.discovered["festival_flags"].

const ActivityData := preload("res://scripts/activities/activity_data.gd")
const GateBuilder := preload("res://scripts/activities/gate_builder.gd")
const PropLibrary := preload("res://scripts/world/prop_library.gd")
const Rules := preload("res://scripts/world/dressing_rules.gd")
const Planner := preload("res://scripts/activities/event_planner.gd")
const KEY := "festival_flags"
const REWARD := 250
const ALL_BONUS := 10000
## Clearance from a flag to the footprint of a settlement building (the glow ring has a 4.5 m radius) and to a
## small collidable prop (lamp, pump, bale).
const BUILDING_CLEAR := 5.0
const PROP_CLEAR := 1.5
## Flags further than this from their planned spot are left where they are (and reported).
const MOVE_MAX := 45.0
## World dressing kept clear of every flag (exclusions registered before Dressing builds its context): bushes,
## rocks and grass within POCKET_CORE, trees and hedges within POCKET_TREES (canopy and flag cloth clear), and
## trees / hedges within LANE_TREES of the drivable approach line from the road (event_planner.approach).
const POCKET_CORE := 3.0
const POCKET_TREES := 11.0
const LANE_TREES := 4.5
const LANE_STEP := 6.0

var manager: Node
var flags: Array[ActivityData] = []
var _nodes: Array[Node3D] = []
var _areas: Array[Area3D] = []


func setup(list: Array[ActivityData], mgr: Node) -> void:
	manager = mgr
	flags = list
	_clear_of_buildings()
	_clear_dressing()
	for i in flags.size():
		var d := flags[i]
		var root := GateBuilder.flag_node()
		root.name = d.id
		add_child(root)
		root.global_position = d.position
		var area := Area3D.new()
		area.collision_layer = 8
		area.collision_mask = 2
		area.monitorable = false
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 4.5
		cs.shape = sph
		cs.position = Vector3(0, 1.5, 0)
		area.add_child(cs)
		root.add_child(area)
		area.body_entered.connect(_on_body.bind(i))
		_nodes.append(root)
		_areas.append(area)
	refresh()
	if not SaveGame.loaded.is_connected(_on_save_loaded):
		SaveGame.loaded.connect(_on_save_loaded)


## Flags are planned at bake time from the terrain, settlement buildings are laid out at start-up: a flag that
## ended up inside or against a building (or a collidable prop) moves to the nearest clear, dry, gentle spot.
func _clear_of_buildings() -> void:
	var st: Node = Game.main.get_node_or_null(^"Settlements") if Game.main != null else null
	var w := Game.world as World
	if st == null or w == null:
		return
	var items: Variant = st.get("items")
	if not (items is Array):
		return
	var obstacles: Array = []
	for it: Dictionary in items:
		if int(it.get("col", 0)) == 0 or not it.has("xf"):
			continue
		var bb := PropLibrary.aabb(String(it["name"]))
		var xf: Transform3D = it["xf"]
		var pad := BUILDING_CLEAR if maxf(bb.size.x, bb.size.z) > 3.0 else PROP_CLEAR
		pad /= maxf(xf.basis.get_scale().x, 0.01)
		obstacles.append([xf.affine_inverse(), Rect2(bb.position.x - pad, bb.position.z - pad, bb.size.x + 2.0 * pad, bb.size.z + 2.0 * pad), String(it["name"])])
	for d in flags:
		var inside := _obstacle_at(obstacles, d.position)
		if inside == "":
			continue
		var spot := _clear_spot(obstacles, w, d.position)
		if spot == Vector3.INF:
			push_warning("[activities] %s stands at %s against %s and no clear spot was found" % [d.id, str(d.position), inside])
			continue
		print("[activities] %s moved %.1f m out of %s to %s" % [d.id, Vector2(spot.x - d.position.x, spot.z - d.position.z).length(), inside, str(spot.snappedf(0.01))])
		d.position = spot


## Keeps trees, hedges and props out of each flag's pocket and off its approach from the road: Dressing reads
## the exclusion registry when it starts (after every _ready), Settlements fills and clears it before us.
func _clear_dressing() -> void:
	var w := Game.world as World
	if w == null:
		return
	for d in flags:
		Rules.register_exclusion(d.position.x, d.position.z, POCKET_CORE, POCKET_TREES)
		var line := Planner.approach(w.data, d.position)
		if line.size() < 2:
			push_warning("[activities] %s has no drivable approach from a road" % d.id)
			continue
		var n := ceili(line[0].distance_to(line[1]) / LANE_STEP)
		for i in range(1, n + 1):
			var p := line[0].lerp(line[1], float(i) / n)
			Rules.register_exclusion(p.x, p.z, 0.0, LANE_TREES)


func _obstacle_at(obstacles: Array, p: Vector3) -> String:
	for o: Array in obstacles:
		var lp: Vector3 = (o[0] as Transform3D) * p
		if (o[1] as Rect2).has_point(Vector2(lp.x, lp.z)):
			return o[2]
	return ""


## Nearest spot (rings every 2 m) clear of every obstacle, off the roads, dry and not steep; INF when none.
func _clear_spot(obstacles: Array, w: World, from: Vector3) -> Vector3:
	var rad := 2.0
	while rad <= MOVE_MAX:
		var steps := maxi(int(TAU * rad / 2.0), 8)
		for k in steps:
			var a := TAU * k / steps
			var x := from.x + cos(a) * rad
			var z := from.z + sin(a) * rad
			var p := Vector3(x, w.data.height_at(x, z), z)
			if w.data.normal_at(x, z).y < 0.9 or w.data.road_distance_at(x, z) < 6.0 or w.water_level_at(x, z) > -INF:
				continue
			if _obstacle_at(obstacles, p) == "":
				return p
		rad += 2.0
	return Vector3.INF


func _on_save_loaded(_d: Dictionary) -> void:
	refresh()


func collected() -> Array:
	var v: Variant = Game.discovered.get(KEY, [])
	return v if v is Array else []


func is_collected(id: String) -> bool:
	return collected().has(id)


func count() -> int:
	var n := 0
	for d in flags:
		if is_collected(d.id):
			n += 1
	return n


func refresh() -> void:
	for i in flags.size():
		var got := is_collected(flags[i].id)
		_nodes[i].visible = not got
		_nodes[i].scale = Vector3.ONE
		_areas[i].set_deferred("monitoring", not got)


func _on_body(body: Node3D, i: int) -> void:
	if body != Game.player_car or i >= flags.size():
		return
	if Game.main != null and Game.main.is_loading:
		return
	var d := flags[i]
	if is_collected(d.id):
		return
	var list := collected().duplicate()
	list.append(d.id)
	Game.discovered[KEY] = list
	_areas[i].set_deferred("monitoring", false)
	var node := _nodes[i]
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.6, 1.6, 1.6), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3(0.01, 0.01, 0.01), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: node.visible = false)
	var n := count()
	var credits := REWARD + (ALL_BONUS if n == flags.size() else 0)
	manager.award(credits)
	var score := "%d / %d" % [n, flags.size()]
	Game.activity_finished.emit(d.id, {"title": "Festival Flag", "score_text": score, "personal_best": false,
		"medal": "", "stars": 0, "credits": credits, "kind": &"collectible", "value": float(n), "detail": d.title})
	Game.notify("Festival Flag found  %s" % score, "%s  ·  +%d CR" % [d.title, credits], &"collectible")
	if n == flags.size():
		Game.notify("All Festival Flags found!", "The whole festival salutes you  ·  +%d CR" % ALL_BONUS, &"activity")
	print("[activity] flag %s collected (%s)" % [d.id, score])


func get_flag_positions() -> Array:
	var out: Array = []
	for d in flags:
		out.append({"id": d.id, "name": d.title, "position": d.position, "collected": is_collected(d.id)})
	return out
