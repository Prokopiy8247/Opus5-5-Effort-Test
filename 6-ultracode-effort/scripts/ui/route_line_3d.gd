extends MeshInstance3D
## In-world GPS guide: a glowing ribbon slightly above the road along the next ~350 m of the route.
## The ImmediateMesh is rebuilt at 4 Hz (or when the route changes); the shader hides the part
## behind the car every frame from the car position uniform.

const SHADER := preload("res://assets/shaders/ui_route_line.gdshader")
const AHEAD_M := 350.0
const HALF_WIDTH := 0.6
const LIFT := 0.22
const REBUILD_INTERVAL := 0.25

var gps: Node
## External visibility switch (HUD hidden / photo mode).
var enabled: bool = true

var _imesh := ImmediateMesh.new()
var _mat := ShaderMaterial.new()
var _timer: float = 0.0


func _ready() -> void:
	mesh = _imesh
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if gps != null:
		gps.route_changed.connect(_on_route_changed)


func _on_route_changed() -> void:
	_timer = 0.0


func _process(delta: float) -> void:
	var car := Game.player_car
	var on: bool = enabled and gps != null and gps.active and car != null and is_instance_valid(car)
	visible = on
	if not on:
		return
	_mat.set_shader_parameter("car_pos", car.global_position)
	_mat.set_shader_parameter("car_fwd", -car.global_transform.basis.z)
	_timer -= delta
	if _timer <= 0.0:
		_timer = REBUILD_INTERVAL
		_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	var pts: PackedVector3Array = gps.points
	var cum: PackedFloat32Array = gps.cumulative
	var n := pts.size()
	if n < 2 or cum.size() != n:
		return
	var start := maxi(int(gps.progress) - 4, 0)
	var d0 := cum[start]
	var last := start
	while last < n - 1 and cum[last] - d0 < AHEAD_M:
		last += 1
	if last - start < 1:
		return
	var end_len := cum[last] - d0
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(start, last + 1):
		var p := pts[i]
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var t := Vector2(b.x - a.x, b.z - a.z)
		if t.length_squared() < 0.0001:
			t = Vector2(0, -1)
		t = t.normalized()
		var right := Vector3(-t.y, 0.0, t.x) * HALF_WIDTH
		var dist := cum[i] - d0
		var fade := clampf(dist / 10.0, 0.0, 1.0) * clampf((end_len - dist) / 90.0, 0.0, 1.0)
		if last == n - 1:
			fade = clampf(dist / 10.0, 0.0, 1.0) * clampf((end_len - dist) / 12.0 + 0.15, 0.0, 1.0)
		var up := Vector3(0.0, LIFT, 0.0)
		_imesh.surface_set_color(Color(1, 1, 1, fade))
		_imesh.surface_set_uv(Vector2(0.0, cum[i]))
		_imesh.surface_add_vertex(p - right + up)
		_imesh.surface_set_color(Color(1, 1, 1, fade))
		_imesh.surface_set_uv(Vector2(1.0, cum[i]))
		_imesh.surface_add_vertex(p + right + up)
	_imesh.surface_end()
