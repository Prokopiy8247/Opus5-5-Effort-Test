extends Node3D
## Places the baked props (buildings, landmarks, festival hub, roadside furniture).
## - Buildings/landmarks: scene instances with trimesh collision and visibility ranges.
## - Roadside furniture: one MultiMesh per (chunk, kind); smashable on contact (Forza-style):
##   the instance is hidden and a short-lived physics debris piece flies off.
## - Wind turbine rotors spin; signs get Label3D text (speed limits, route names).

const CHUNK := 256.0
const ORIGIN := -2048.0
const MULTI_KINDS := ["reflector_post", "chevron", "street_lamp", "sign_curve_l", "sign_curve_r", "sign_speed", "sign_route",
	"fence_wood", "hay_bale", "smash_board"]
const SMASH_RADIUS := {"reflector_post": 0.6, "chevron": 0.8, "street_lamp": 0.7, "sign_curve_l": 0.8, "sign_curve_r": 0.8,
	"sign_speed": 0.7, "sign_route": 1.6, "fence_wood": 2.1, "hay_bale": 1.2, "smash_board": 1.6}
const VIS := {"reflector_post": 260.0, "chevron": 420.0, "street_lamp": 700.0, "sign_curve_l": 380.0, "sign_curve_r": 380.0,
	"sign_speed": 380.0, "sign_route": 500.0, "fence_wood": 400.0, "hay_bale": 600.0, "smash_board": 900.0}

var world: Node
var data: WorldData
var smashables: Dictionary = {}       # Vector2i -> Array[{kind, xf, mm, idx, alive}]
var rotors: Array[Node3D] = []
var exclusion: Array = []             # [Vector2 pos, radius] for vegetation
var smashed_count: int = 0
var _debris: Array = []
var _smash_sound: AudioStreamPlayer3D
var extra_props: Array = []


func setup(w: Node) -> void:
	world = w
	data = w.get("data")
	name = "Props"
	_smash_sound = AudioStreamPlayer3D.new()
	_smash_sound.stream = SoundBank.get_stream("thump")
	_smash_sound.max_distance = 80.0
	add_child(_smash_sound)
	var props: Array = data.meta.get("props", [])
	# activity furniture (gates, speed cameras, ramps, danger signs, festival boards) from data/activities
	var acts := ActivityDef.load_all()
	extra_props.append_array(ActivityDef.world_props(acts))
	exclusion.append_array(ActivityDef.exclusions(acts))
	var per_chunk: Dictionary = {}
	for p in props + extra_props:
		var kind: String = p["k"]
		var pos := Vector3(float(p["p"][0]), float(p["p"][1]), float(p["p"][2]))
		var yaw := float(p.get("r", 0.0))
		if MULTI_KINDS.has(kind):
			var key := _chunk(pos)
			if not per_chunk.has(key):
				per_chunk[key] = {}
			var d: Dictionary = per_chunk[key]
			if not d.has(kind):
				d[kind] = []
			(d[kind] as Array).append(p)
		else:
			_instance(kind, pos, yaw, p)
	for key in per_chunk:
		_build_multi(key, per_chunk[key])


func add_dynamic_props(list: Array) -> void:
	## activities add their own smashables/gates before setup
	extra_props.append_array(list)


func _chunk(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - ORIGIN) / CHUNK)), int(floor((p.z - ORIGIN) / CHUNK)))


func _instance(kind: String, pos: Vector3, yaw: float, p: Dictionary) -> void:
	var ps := PropLibrary.scene(kind)
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	inst.name = "%s_%d" % [kind, get_child_count()]
	PropLibrary.apply_to_scene(inst)
	var big := kind in ["lighthouse", "castle_ruin", "wind_turbine", "church", "silo", "festival_stage", "festival_arch"]
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visibility_range_end = 3200.0 if big else 1700.0
		mi.visibility_range_end_margin = 80.0
	add_child(inst)
	inst.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(float(p.get("sx", 1.0)), 1.0, 1.0)), pos)
	exclusion.append([Vector2(pos.x, pos.z), 18.0 if not big else 30.0])
	if kind == "wind_turbine":
		for c in inst.find_children("*", "Node3D", true, false):
			if CarFactory.base_name(String(c.name)) == "Rotor":
				rotors.append(c)
	# static collision from the render mesh (trimesh) for solid props
	if kind in ["festival_flag", "festival_tent"]:
		_box_collision(inst, 0.6)
		return
	if kind == "checkpoint_gate":
		return  # drive-through arch
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if CarFactory.base_name(String(mi.name)) == "Rotor":
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", Surfaces.CONCRETE)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	if kind == "sign_region":
		_label(inst, String(p.get("text", "")), Vector3(0, 2.6, -0.1), 64)


func _box_collision(inst: Node3D, shrink: float) -> void:
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var aabb := mi.mesh.get_aabb()
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size * shrink
		cs.shape = box
		cs.position = aabb.get_center()
		body.add_child(cs)
		mi.add_child(body)


func _label(parent: Node3D, text: String, at: Vector3, size: int, color: Color = Color.WHITE) -> void:
	if text == "":
		return
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font(true)
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	l.position = at
	l.rotation = Vector3(0, PI, 0)
	l.visibility_range_end = 220.0
	parent.add_child(l)


func _build_multi(key: Vector2i, kinds: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "PropChunk_%d_%d" % [key.x, key.y]
	add_child(holder)
	if not smashables.has(key):
		smashables[key] = []
	for kind in kinds:
		var mesh := PropLibrary.mesh(kind)
		if mesh == null:
			continue
		var list: Array = kinds[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var p: Dictionary = list[i]
			var pos := Vector3(float(p["p"][0]), float(p["p"][1]), float(p["p"][2]))
			if p.has("y"):
				pos.y = maxf(pos.y, float(p["y"]) - 0.25)
			var xf := Transform3D(Basis(Vector3.UP, float(p.get("r", 0.0))), pos)
			mm.set_instance_transform(i, xf)
			(smashables[key] as Array).append({"kind": kind, "xf": xf, "mm": mm, "idx": i, "alive": true})
			if kind == "sign_speed":
				_sign_text(holder, xf, str(int(p.get("v", 60))), Vector3(0, 2.15, -0.05), 90, Color(0.05, 0.05, 0.05))
			elif kind == "sign_route":
				_sign_text(holder, xf, String(p.get("text", "")), Vector3(0, 2.6, -0.06), 48, Color.WHITE)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = VIS.get(kind, 500.0)
		mmi.visibility_range_end_margin = 30.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in ["street_lamp", "sign_route", "hay_bale"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)


func _sign_text(holder: Node3D, xf: Transform3D, text: String, at: Vector3, size: int, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font(true)
	l.font_size = size
	l.pixel_size = 0.0045 if size < 80 else 0.004
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.visibility_range_end = 160.0
	l.transform = xf * Transform3D(Basis(Vector3.UP, PI), at)
	holder.add_child(l)


func _process(delta: float) -> void:
	for r in rotors:
		r.rotate_object_local(Vector3(0, 0, 1), delta * (0.6 + float(Game.environment.get("wind") if Game.environment else 0.3) * 0.9))
	for i in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		d["t"] = float(d["t"]) - delta
		if float(d["t"]) <= 0.0:
			(d["n"] as Node).queue_free()
			_debris.remove_at(i)


func _physics_process(_delta: float) -> void:
	Game.prof_begin("props_smash")
	var car := Game.player_car
	if car == null or not is_instance_valid(car):
		Game.prof_end("props_smash")
		return
	var v := car.linear_velocity
	if v.length() < 3.0:
		Game.prof_end("props_smash")
		return
	var p := car.global_position
	var key := _chunk(p)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var list: Array = smashables.get(Vector2i(key.x + dx, key.y + dz), [])
			for s in list:
				if not s["alive"]:
					continue
				var xf: Transform3D = s["xf"]
				var d := Vector2(xf.origin.x - p.x, xf.origin.z - p.z).length()
				if d < float(SMASH_RADIUS.get(s["kind"], 0.8)) + 1.1 and absf(xf.origin.y - p.y) < 3.0:
					_smash(s, car)
	Game.prof_end("props_smash")


func remove_smashable_near(pos: Vector3, radius: float) -> void:
	## hides an already-smashed prop (restored from the save) without debris
	for s in smashables.get(_chunk(pos), []):
		var xf: Transform3D = s["xf"]
		if s["alive"] and xf.origin.distance_to(pos) < radius:
			s["alive"] = false
			(s["mm"] as MultiMesh).set_instance_transform(int(s["idx"]), Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), xf.origin - Vector3(0, 50, 0)))


func _smash(s: Dictionary, car: CarController) -> void:
	s["alive"] = false
	var mm: MultiMesh = s["mm"]
	var xf: Transform3D = s["xf"]
	mm.set_instance_transform(int(s["idx"]), Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), xf.origin - Vector3(0, 50, 0)))
	smashed_count += 1
	var body := RigidBody3D.new()
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 25.0
	var mi := MeshInstance3D.new()
	mi.mesh = mm.mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var aabb := mm.mesh.get_aabb()
	box.size = aabb.size.max(Vector3(0.2, 0.2, 0.2))
	cs.shape = box
	cs.position = aabb.get_center()
	body.add_child(cs)
	add_child(body)
	body.global_transform = xf
	var v := car.linear_velocity
	body.linear_velocity = v * randf_range(0.7, 1.05) + Vector3.UP * randf_range(3.0, 6.0)
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	_debris.append({"n": body, "t": 7.0})
	car.apply_central_impulse(-v.normalized() * minf(v.length(), 30.0) * 8.0)
	_smash_sound.global_position = xf.origin
	_smash_sound.pitch_scale = randf_range(1.2, 1.7)
	_smash_sound.play()
	if s["kind"] == "smash_board" and Game.activities != null and Game.activities.has_method("on_board_smashed"):
		Game.activities.call("on_board_smashed", xf.origin)
