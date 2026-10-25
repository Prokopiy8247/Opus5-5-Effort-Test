class_name BrakingLine
extends MeshInstance3D
## Braking-line assist (toggle "line" in the assists): a ribbon along the road ahead of the player
## coloured by what the car must do there — blue/green = carry the speed, yellow = ease off,
## red = brake now. The safe corner speed comes from the road curvature (lateral grip limit) and
## the reachable speed from braking at a constant deceleration from the current speed.

const AHEAD := 220.0
const A_LAT := 9.0
const A_BRAKE := 8.0

var _t := 0.0


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	material_override = m


func _process(delta: float) -> void:
	var car := Game.player_car
	if not bool(Game.assists.get("line", false)) or car == null or not is_instance_valid(car) or Game.world == null \
			or not ("data" in Game.world):
		mesh = null
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.08
	var data: WorldData = Game.world.get("data")
	var p := car.global_position
	var nr := data.nearest_road(p.x, p.z, 3)
	if nr.is_empty() or float(nr["d"]) > 12.0:
		mesh = null
		return
	var ri := int(nr["road"])
	var i0 := int(nr["i"])
	var r: Dictionary = data.roads[ri]
	var n := (r["x"] as PackedFloat32Array).size()
	var closed: bool = r["closed"]
	var fwd := -car.global_transform.basis.z
	var dir := 1 if data.road_dir(ri, i0).dot(fwd) >= 0.0 else -1
	var lane := 1.75 if int(r["lanes"]) >= 2 else 0.0   # tangent follows travel, so right = own lane
	var v := maxf(car.forward_speed, 0.0)
	var grip := A_LAT * (0.85 if Surfaces.is_paved(car.surface_under) else 0.6) * lerpf(1.0, 0.75, car.wetness)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color.TRANSPARENT
	var dist := 0.0
	var k := 2
	var have_prev := false
	while dist < AHEAD:
		var i := i0 + k * dir
		if not closed and (i < 2 or i > n - 3):
			break
		i = posmod(i, n)
		var a := data.road_point(ri, posmod(i - 4 * dir, n) if closed else clampi(i - 4 * dir, 0, n - 1))
		var b := data.road_point(ri, i)
		var c := data.road_point(ri, posmod(i + 4 * dir, n) if closed else clampi(i + 4 * dir, 0, n - 1))
		var d1 := Vector2(b.x - a.x, b.z - a.z)
		var d2 := Vector2(c.x - b.x, c.z - b.z)
		var kap := absf(d1.angle_to(d2)) / maxf((d1.length() + d2.length()) * 0.5, 1.0)
		var v_safe := sqrt(grip / maxf(kap, 1e-4))
		var v_reach := sqrt(maxf(v * v - 2.0 * A_BRAKE * dist, 0.0))
		var col := Color(0.25, 0.75, 1.0, 0.7)
		if v_reach > v_safe * 1.02:
			col = Color(1.0, 0.18, 0.12, 0.85)
		elif v_reach > v_safe * 0.9:
			col = Color(1.0, 0.82, 0.15, 0.8)
		var t := (c - a)
		t.y = 0.0
		if t.length() < 0.01:
			k += 2
			continue
		var right := t.normalized().cross(Vector3.UP).normalized()
		var centre := b + right * lane + Vector3.UP * 0.1
		var l := centre - right * 0.65
		var rr := centre + right * 0.65
		col.a *= 1.0 - smoothstep(AHEAD * 0.6, AHEAD, dist)
		if have_prev:
			for q in [[prev_l, prev_c], [rr, col], [prev_r, prev_c], [prev_l, prev_c], [l, col], [rr, col]]:
				st.set_color(q[1])
				st.add_vertex(q[0])
		prev_l = l
		prev_r = rr
		prev_c = col
		have_prev = true
		dist += 4.0
		k += 2
	mesh = st.commit()
