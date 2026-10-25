class_name TestTrack
extends Node3D
## Flat proving ground used by automated drive tests (and as a fallback world).
## Implements the same query API as the real world (see Game contracts).

const SIZE := 12000.0

var surface_id: StringName = &"asphalt"
var _ground: StaticBody3D


func _ready() -> void:
	_ground = StaticBody3D.new()
	_ground.name = "Ground"
	_ground.collision_layer = 1
	_ground.set_meta(&"surface", surface_id)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, 2.0, SIZE)
	cs.shape = box
	cs.position = Vector3(0, -1.0, 0)
	_ground.add_child(cs)
	add_child(_ground)
	if DisplayServer.get_name() != "headless":
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(4000, 4000)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.32, 0.33, 0.34)
		m.roughness = 0.9
		mi.material_override = m
		add_child(mi)


func set_surface(id: StringName) -> void:
	surface_id = id
	_ground.set_meta(&"surface", id)


## Adds a ramp (for jump tests): a tilted box whose top edge is `height` m above ground.
func add_ramp(at: Vector3, length: float, height: float, width := 8.0) -> void:
	var body := StaticBody3D.new()
	body.set_meta(&"surface", &"concrete")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var ang := atan2(height, length)
	var l := sqrt(length * length + height * height)
	box.size = Vector3(width, 0.5, l)
	cs.shape = box
	body.add_child(cs)
	body.transform = Transform3D(Basis(Vector3.RIGHT, ang), at + Vector3(0, height * 0.5 - 0.25, -length * 0.5))
	body.add_to_group(&"test_ramps")
	add_child(body)


func clear_ramps() -> void:
	for n in get_tree().get_nodes_in_group(&"test_ramps"):
		n.queue_free()


func height_at(_x: float, _z: float) -> float:
	return 0.0


func surface_at(_pos: Vector3) -> SurfaceData:
	return Surfaces.get_surface(surface_id)


func region_at(_pos: Vector3) -> String:
	return "Proving Ground"


func nearest_road_point(pos: Vector3) -> Dictionary:
	return {"position": Vector3(pos.x, 0.0, pos.z), "forward": Vector3(0, 0, -1), "road_id": 0, "s": 0.0}


func get_teleport_targets() -> Array:
	return [{"name": "Proving Ground", "kind": "region", "position": Vector3.ZERO, "forward": Vector3(0, 0, -1)}]
