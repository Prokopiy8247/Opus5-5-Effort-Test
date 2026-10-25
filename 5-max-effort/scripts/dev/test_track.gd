class_name TestTrack
extends Node3D
## Flat proving ground used by automated drive tests (and as a dev sandbox):
## a large asphalt pad, a gravel pad, a dirt pad, a grass pad and a jump ramp.

const PAD_GRAVEL_X := 6000.0
const PAD_DIRT_X := -6000.0
const PAD_GRASS_Z := 6000.0
const RAMP_POS := Vector3(0.0, 0.0, -3000.0)


func _ready() -> void:
	build()


func build() -> void:
	_pad(Vector3.ZERO, Vector2(12000.0, 12000.0), Surfaces.ASPHALT, Color(0.18, 0.18, 0.19))
	_pad(Vector3(PAD_GRAVEL_X, 0.02, 0.0), Vector2(2000.0, 2000.0), Surfaces.GRAVEL, Color(0.5, 0.46, 0.4))
	_pad(Vector3(PAD_DIRT_X, 0.02, 0.0), Vector2(2000.0, 2000.0), Surfaces.DIRT, Color(0.42, 0.3, 0.2))
	_pad(Vector3(0.0, 0.02, PAD_GRASS_Z), Vector2(2000.0, 2000.0), Surfaces.GRASS, Color(0.25, 0.42, 0.15))
	_ramp(RAMP_POS, 14.0, 24.0, 2.4)


func _pad(center: Vector3, size: Vector2, surface: int, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = "Pad_%s" % Surfaces.KEYS[surface]
	body.collision_layer = 1
	body.set_meta("surface", surface)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 2.0, size.y)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.uv1_triplanar = true
	pm.material = mat
	mi.mesh = pm
	body.add_child(mi)
	body.position = center
	add_child(body)


func _ramp(pos: Vector3, width: float, length: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Ramp"
	body.set_meta("surface", Surfaces.CONCRETE)
	var angle := atan2(height, length)
	var shape := BoxShape3D.new()
	var slope_len := sqrt(length * length + height * height)
	shape.size = Vector3(width, 1.0, slope_len)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = shape.size
	mi.mesh = bm
	body.add_child(mi)
	# rises towards -Z (the driving direction of the tests)
	body.transform = Transform3D(Basis(Vector3.RIGHT, angle), pos + Vector3(0.0, height * 0.5 - 0.5 * cos(angle), 0.0))
	add_child(body)


# --- world interface (shared with OpenWorld) ---------------------------------------------------
func spawn_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(-1500.0, 0.5, 5000.0))


func teleport_targets() -> Dictionary:
	return {
		"start": spawn_transform(),
		"gravel": Transform3D(Basis.IDENTITY, Vector3(PAD_GRAVEL_X, 0.6, 600.0)),
		"dirt": Transform3D(Basis.IDENTITY, Vector3(PAD_DIRT_X, 0.6, 600.0)),
		"grass": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, PAD_GRASS_Z + 600.0)),
		"ramp": Transform3D(Basis.IDENTITY, RAMP_POS + Vector3(0.0, 0.6, 400.0)),
	}


func nearest_road_transform(pos: Vector3, heading: Vector3) -> Transform3D:
	var h := Vector3(heading.x, 0.0, heading.z)
	if h.length() < 0.1:
		h = Vector3.FORWARD
	return Transform3D(Basis.looking_at(h.normalized(), Vector3.UP), Vector3(pos.x, 0.6, pos.z))


func surface_at(x: float, z: float) -> int:
	if absf(x - PAD_GRAVEL_X) < 1000.0 and absf(z) < 1000.0:
		return Surfaces.GRAVEL
	if absf(x - PAD_DIRT_X) < 1000.0 and absf(z) < 1000.0:
		return Surfaces.DIRT
	if absf(x) < 1000.0 and absf(z - PAD_GRASS_Z) < 1000.0:
		return Surfaces.GRASS
	return Surfaces.ASPHALT


func region_at(_x: float, _z: float) -> String:
	return "Proving Ground"


func height_at(_x: float, _z: float) -> float:
	return 0.0
