extends Node3D
## Street + tunnel lamps. Game.world.roads.lamp_positions holds street lamp bases (road level, beside the
## kerb) and tunnel lamp points (under the crown). A pool of <= 16 shadowless OmniLight3D nodes lights the
## nearest lamps around the camera (street lamps only at night, tunnel lamps always), re-assigned a few
## times per second with distance fades so nothing pops. Every street lamp also gets a soft halo (and, when
## the dressing system that builds Lamp_Street posts is absent, an emissive head), one MultiMesh each,
## shown only after dusk. Head geometry matches the dressing Lamp_Street prop (lamp at 6.2 m, 1.75 m arm).
## Lamp_Street posts the settlements place away from street-lamp spots (fuel stations, diners) are lit too: their
## head transforms come from the Settlements node (`lamp_heads`).
## The environment controller drives update() every frame. The pool is in Game.TIME_REACTIVE_GROUP:
## after a time / weather change while the tree is paused (photo mode) it keeps processing for a moment and
## updates itself, and snap() makes the next update apply the new lighting at once (no fades).

const MAX_LIGHTS := 16
const RADIUS := 250.0
const CELL := 64.0
const LAMP_HEIGHT := 6.2
const ARM := 1.75
const UPDATE_INTERVAL := 0.2
const STREET_COLOR := Color(1.0, 0.76, 0.48)
const TUNNEL_COLOR := Color(1.0, 0.84, 0.6)

## 0 = daylight (street lamps off) .. 1 = night.
var street_factor: float = 0.0
var max_lights: int = MAX_LIGHTS
var lamp_count: int = 0

var _pos: PackedVector3Array = PackedVector3Array()
var _tunnel: PackedByteArray = PackedByteArray()
var _grid: Dictionary = {}
var _lights: Array[OmniLight3D] = []
var _assigned: PackedInt32Array = PackedInt32Array()
var _energy: PackedFloat32Array = PackedFloat32Array()
var _keep: PackedByteArray = PackedByteArray()
var _built := false
var _timer := 0.0
var _heads: MultiMeshInstance3D
var _halos: MultiMeshInstance3D
var _head_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _shown_factor := -1.0
var _cam_pos := Vector3.ZERO
var _snap := false
var _frame: int = -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group(Game.TIME_REACTIVE_GROUP)
	for i in MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.name = "Lamp%d" % i
		l.shadow_enabled = false
		l.omni_range = 20.0
		l.omni_attenuation = 1.3
		l.light_specular = 0.35
		l.light_volumetric_fog_energy = 1.4
		l.distance_fade_enabled = true
		l.distance_fade_begin = 190.0
		l.distance_fade_length = 55.0
		l.visible = false
		add_child(l)
		_lights.append(l)
	_assigned.resize(MAX_LIGHTS)
	_assigned.fill(-1)
	_energy.resize(MAX_LIGHTS)
	_energy.fill(0.0)
	_keep.resize(MAX_LIGHTS)
	_keep.fill(0)


func _try_build() -> bool:
	var w := Game.world as World
	if w == null or w.roads == null or not w.roads.done:
		return false
	var raw: PackedVector3Array = w.roads.lamp_positions
	var net := w.data.network
	var head_xf: Array[Transform3D] = []
	for p in raw:
		var near := net.nearest(p, 30.0)
		var tunnel := false
		var to_road := Vector3.ZERO
		if not near.is_empty():
			var c: Vector3 = near["position"]
			tunnel = p.y - c.y > 3.0
			to_road = Vector3(c.x - p.x, 0.0, c.z - p.z)
		if tunnel:
			_pos.append(p - Vector3(0, 1.1, 0))
			_tunnel.append(1)
		else:
			var dir := to_road.normalized() if to_road.length() > 0.1 else Vector3.FORWARD
			# Same base height rule as the dressing Lamp_Street props.
			var base := p
			var gy := w.data.height_at(p.x, p.z)
			base.y = gy - 0.05 if absf(gy - p.y) <= 1.5 else p.y - 0.15
			var head := base + Vector3.UP * LAMP_HEIGHT + dir * ARM
			_pos.append(head - Vector3(0, 0.3, 0))
			_tunnel.append(0)
			head_xf.append(Transform3D(Basis.looking_at(dir, Vector3.UP), head))
		_index_last()
	var st: Node = Game.main.get_node_or_null(^"Settlements") if Game.main != null else null
	if st != null and "lamp_heads" in st:
		for hx: Transform3D in st.get("lamp_heads"):
			_pos.append(hx.origin - Vector3(0, 0.3, 0))
			_tunnel.append(0)
			head_xf.append(hx)
			_index_last()
	lamp_count = _pos.size()
	_build_heads(head_xf)
	return true


func _index_last() -> void:
	var k := _key(_pos[_pos.size() - 1])
	if not _grid.has(k):
		_grid[k] = PackedInt32Array()
	var arr: PackedInt32Array = _grid[k]
	arr.append(_pos.size() - 1)
	_grid[k] = arr


func lit_count() -> int:
	var n := 0
	for l in _lights:
		if l.visible:
			n += 1
	return n


func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _build_heads(xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	if not Game.has_meta(&"dressing"):
		_build_head_mesh(xfs)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_halo_mat.distance_fade_min_distance = 4.0
	_halo_mat.distance_fade_max_distance = 18.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.35))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_halo_mat.albedo_texture = gt
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	quad.material = _halo_mat
	_halos = _multimesh("LampHalos", quad, xfs, Vector3(0, -0.1, 0))
	_apply_factor()


## Procedural lamp heads, only when no Lamp_Street props are placed by the dressing system.
func _build_head_mesh(xfs: Array[Transform3D]) -> void:
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(0.16, 0.16, 0.17)
	_head_mat.roughness = 0.5
	_head_mat.emission_enabled = true
	_head_mat.emission = STREET_COLOR
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.14, 0.7)
	box.material = _head_mat
	_heads = _multimesh("LampHeads", box, xfs, Vector3(0, 0.08, 0))


func _multimesh(n: String, mesh: Mesh, xfs: Array[Transform3D], offset: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var t := xfs[i]
		t.origin += offset
		mm.set_instance_transform(i, t)
	var mi := MultiMeshInstance3D.new()
	mi.name = n
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _apply_factor() -> void:
	_shown_factor = street_factor
	var on := street_factor > 0.01
	if _heads:
		_heads.visible = on
		_head_mat.emission_energy_multiplier = 7.0 * street_factor
	if _halos:
		_halos.visible = on
		_halo_mat.albedo_color = Color(STREET_COLOR.r, STREET_COLOR.g * 0.95, STREET_COLOR.b * 0.85, 0.55 * street_factor)


## Time or weather jumped: the next update picks the lamps and sets their light without fading.
func snap() -> void:
	_snap = true


## Paused tree (photo mode): the environment only ticks for a few frames after a change, so the pool
## finishes it on its own while the time-reactive pulse keeps it processing.
func _process(delta: float) -> void:
	if _frame == Engine.get_process_frames() or not get_tree().paused:
		return
	var env := get_parent()
	if env != null and env.has_method(&"street_lamp_factor"):
		street_factor = float(env.call(&"street_lamp_factor"))
	var cam := get_viewport().get_camera_3d()
	update(cam.global_position if cam != null else _cam_pos, delta)


func update(cam_pos: Vector3, delta: float) -> void:
	_frame = Engine.get_process_frames()
	_cam_pos = cam_pos
	if not _built:
		_built = _try_build()
		if not _built:
			return
	if absf(street_factor - _shown_factor) > 0.01 or (street_factor <= 0.01 and _shown_factor > 0.0):
		_apply_factor()
	var snap_now := _snap
	_snap = false
	_timer -= delta
	if _timer <= 0.0 or snap_now:
		_timer = UPDATE_INTERVAL
		_reassign(snap_now)
	for i in _lights.size():
		var l := _lights[i]
		var idx := _assigned[i]
		var target := 0.0
		if idx >= 0 and _keep[i] == 1:
			var tunnel := _tunnel[idx] == 1
			var f := 1.0 if tunnel else street_factor
			var d := _pos[idx].distance_to(cam_pos)
			target = (1.3 if tunnel else 2.6) * f * (1.0 - smoothstep(RADIUS * 0.75, RADIUS, d))
		_energy[i] = target if snap_now else move_toward(_energy[i], target, delta * 4.0)
		l.light_energy = _energy[i]
		var vis := _energy[i] > 0.002
		if l.visible != vis:
			l.visible = vis


func _reassign(snap_now := false) -> void:
	var night := street_factor > 0.01
	var cand: Array[Vector2] = []
	var c := _key(_cam_pos)
	var r := int(ceil(RADIUS / CELL))
	var r2 := RADIUS * RADIUS
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var arr: Variant = _grid.get(c + Vector2i(dx, dz))
			if arr == null:
				continue
			for idx: int in arr:
				if not night and _tunnel[idx] == 0:
					continue
				var d2 := _pos[idx].distance_squared_to(_cam_pos)
				if d2 < r2:
					cand.append(Vector2(d2, idx))
	cand.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var want := {}
	for k in mini(cand.size(), max_lights):
		want[int(cand[k].y)] = true
	# Lights keep a lamp that is still wanted; unwanted ones fade out before they are reused (at once on a snap).
	var free: Array[int] = []
	for i in _lights.size():
		var idx := _assigned[i]
		if idx >= 0 and want.has(idx) and i < max_lights:
			want.erase(idx)
			_keep[i] = 1
		else:
			_keep[i] = 0
			if i < max_lights and (idx < 0 or _energy[i] <= 0.05 or snap_now):
				free.append(i)
	for idx: int in want.keys():
		if free.is_empty():
			break
		var i: int = free.pop_front()
		_assigned[i] = idx
		_keep[i] = 1
		_energy[i] = 0.0
		var l := _lights[i]
		var tunnel := _tunnel[idx] == 1
		l.global_position = _pos[idx]
		l.light_color = TUNNEL_COLOR if tunnel else STREET_COLOR
		l.omni_range = 15.0 if tunnel else 21.0
