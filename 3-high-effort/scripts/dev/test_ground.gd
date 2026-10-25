class_name TestGround
extends Node3D
## Flat proving ground used by automated drive tests: asphalt pad, gravel/grass/sand
## strips, a jump ramp and a wall.

const SIZE := 3000.0


func _ready() -> void:
	_pad("Asphalt", Vector3(0, 0, 0), Vector3(SIZE, 1, SIZE), Game.Surf.ASPHALT, Color(0.22, 0.22, 0.23))
	_pad("Gravel", Vector3(300, 0.002, 0), Vector3(120, 1, 1200), Game.Surf.GRAVEL, Color(0.5, 0.46, 0.4))
	_pad("Grass", Vector3(450, 0.002, 0), Vector3(120, 1, 1200), Game.Surf.GRASS, Color(0.25, 0.4, 0.15))
	_pad("Sand", Vector3(600, 0.002, 0), Vector3(120, 1, 1200), Game.Surf.SAND, Color(0.8, 0.7, 0.5))
	_ramp(Vector3(-300, 0, -400))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)


func _pad(n: String, pos: Vector3, size: Vector3, surf: int, col: Color) -> void:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = 1
	body.set_meta("surface", surf)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	pm.material = m
	mi.mesh = pm
	body.add_child(mi)
	body.position = pos
	add_child(body)


func _ramp(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Ramp"
	body.set_meta("surface", Game.Surf.CONCRETE)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 30)
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	body.add_child(mi)
	body.position = pos + Vector3(0, 1.85, 0)
	body.rotation_degrees = Vector3(9, 0, 0)
	add_child(body)
