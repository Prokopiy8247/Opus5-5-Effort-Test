class_name Props
extends Node3D
## Settlements and points of interest assembled from the Blender building kit.

var world: WorldGen
var pois: Dictionary = {}   # name -> Vector3 (road-side teleport point)

# name, road, position fraction along road, layout kind
const SITES := [
	["village", 0, 0.035, "village"], ["farm", 3, 0.5, "farm"], ["farm2", 12, 0.45, "farm"],
	["gasstation", 7, 0.55, "gas"], ["diner", 5, 0.3, "diner"], ["harbour", 9, 0.95, "harbour"],
	["lighthouse", 0, 0.885, "lighthouse"], ["castle", 0, 0.255, "castle"], ["windfarm", 8, 0.5, "windfarm"],
	["hamlet", 0, 0.62, "village_small"], ["alpinelodge", 4, 0.35, "lodge"], ["gas2", 1, 0.2, "gas"],
]

func build(w: WorldGen) -> void:
	world = w
	for s in SITES:
		var ri: int = s[1]
		var n: int = world.roads[ri].pts.size()
		var i := int(n * float(s[2]))
		# avoid tunnels / bridges
		for k in 40:
			if world.roads[ri].tunnel[i] == 0 and world.roads[ri].bridge[i] == 0: break
			i = (i + 5) % n
		var p := world.road_point(ri, i)
		var d := world.road_dir(ri, i)
		var f := Vector3(d.x, 0, d.z).normalized()
		var r := f.cross(Vector3.UP)
		var hw: float = world.roads[ri].width * 0.5
		pois[s[0]] = {"pos": p + Vector3.UP * 1.0, "dir": f, "road": ri, "idx": i}
		match s[3]:
			"village": _village(p, f, r, hw, 7)
			"village_small": _village(p, f, r, hw, 4)
			"farm": _farm(p, f, r, hw)
			"gas": _gas(p, f, r, hw)
			"diner": _diner(p, f, r, hw)
			"harbour": _harbour(p, f, r, hw)
			"lighthouse": _single("Lighthouse", p + r * (hw + 40.0), f)
			"castle": _single("CastleRuin", p + r * -(hw + 70.0), f)
			"windfarm": _windfarm(p, f, r, hw)
			"lodge": _single("HouseB", p + r * (hw + 18.0), f, 1.3)

func _put(kit_name: String, pos: Vector3, facing: Vector3, scale_: float = 1.0, ground: bool = true, collide: bool = true) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.mesh(kit_name, Vector3(6, 5, 8), Color(0.8, 0.75, 0.65))
	if collide:
		# push buildings away from any road they would overlap
		var ab0 := mi.mesh.get_aabb()
		var rad := Vector2(ab0.size.x, ab0.size.z).length() * 0.5 * scale_
		var ok := false
		for k in 20:
			var rs := world.raster_sample(pos.x, pos.z)
			var need: float = rad + 4.0 + (world.roads[int(rs.z)].width * 0.5 if rs.z >= 0.0 else 0.0)
			if rs.z < 0.0 or rs.x > need: ok = true; break
			pos -= facing.normalized() * 4.0
		if not ok:
			return mi
	var y := pos.y
	if ground:
		var aabb := mi.mesh.get_aabb()
		# sample the terrain under the footprint and sit on the lowest point (foundation hides the rest)
		var lowest := 1e9
		for o in [Vector2(0, 0), Vector2(aabb.position.x, aabb.position.z), Vector2(aabb.end.x, aabb.end.z), Vector2(aabb.position.x, aabb.end.z), Vector2(aabb.end.x, aabb.position.z)]:
			var q := pos + Vector3(o.x, 0, o.y) * scale_
			lowest = minf(lowest, world.height(q.x, q.z))
		y = lowest - 0.2
	var b := Basis.looking_at(facing, Vector3.UP).scaled(Vector3.ONE * scale_)
	mi.transform = Transform3D(b, Vector3(pos.x, y, pos.z))
	mi.visibility_range_end = 1400.0
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.set_meta("surface", WorldGen.Surface.CONCRETE)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		var ab := mi.mesh.get_aabb()
		bx.size = ab.size * 0.9
		cs.shape = bx
		cs.position = ab.get_center()
		body.add_child(cs)
		mi.add_child(body)
	return mi

func _single(k: String, p: Vector3, f: Vector3, s: float = 1.0) -> void:
	_put(k, p, -f, s)

func _village(p: Vector3, f: Vector3, r: Vector3, hw: float, count: int) -> void:
	var kinds := ["HouseA", "HouseB", "HouseC"]
	for i in count:
		var side := 1.0 if i % 2 == 0 else -1.0
		var along := (i - count * 0.5) * 16.0
		var pos := p + f * along + r * side * (hw + 13.0 + (i % 3) * 3.0)
		_put(kinds[i % 3], pos, -r * side)
	_put("Church", p + f * (count * 9.0 + 10.0) + r * (hw + 22.0), -r)
	for i in 6:
		var pos := p + f * ((i - 3) * 18.0) + r * (hw + 3.0) * (1.0 if i % 2 == 0 else -1.0)
		_put("StreetLamp", Vector3(pos.x, world.height(pos.x, pos.z), pos.z), f, 1.0, false, false)
	_put("SignVillage", p - f * (count * 9.0 + 20.0) + r * (hw + 2.0), f, 1.0, true, false)

func _farm(p: Vector3, f: Vector3, r: Vector3, hw: float) -> void:
	_put("Barn", p + r * (hw + 30.0), -r)
	_put("HouseA", p + r * (hw + 18.0) + f * 25.0, -r)
	_put("Silo", p + r * (hw + 42.0) - f * 14.0, -r)
	for i in 10:
		var pos := p + r * (hw + 6.0) + f * (i * 4.0 - 20.0)
		_put("Fence", pos, f, 1.0, true, false)

func _gas(p: Vector3, f: Vector3, r: Vector3, hw: float) -> void:
	_put("GasStation", p + r * (hw + 16.0), -r)
	_put("SignGas", p + r * (hw + 3.0) - f * 30.0, f, 1.0, true, false)

func _diner(p: Vector3, f: Vector3, r: Vector3, hw: float) -> void:
	_put("Diner", p + r * (hw + 16.0), -r)
	_put("SignGas", p + r * (hw + 3.0) - f * 25.0, f, 1.0, true, false)

func _harbour(p: Vector3, f: Vector3, r: Vector3, hw: float) -> void:
	for i in 4:
		_put(["HouseC", "Warehouse", "HouseA", "HouseB"][i], p + r * (hw + 14.0) * (1.0 if i % 2 == 0 else -1.0) + f * (i * 14.0 - 20.0), -r * (1.0 if i % 2 == 0 else -1.0))
	var pier := p + f * 60.0
	_put("Pier", Vector3(pier.x, 0.6, pier.z), f, 1.0, false)
	for i in 3:
		var bp := pier + r * (8.0 + i * 7.0) + f * (i * 6.0)
		_put("Boat", Vector3(bp.x, 0.1, bp.z), f, 1.0, false, false)

func _windfarm(p: Vector3, f: Vector3, r: Vector3, hw: float) -> void:
	for i in 6:
		var pos := p + r * (60.0 + (i % 2) * 70.0) + f * (i * 80.0 - 200.0)
		var t := _put("WindTurbine", pos, Vector3.FORWARD, 1.0, true, true)
		var rot := _put("TurbineRotor", Vector3(t.position.x, t.position.y + 48.0, t.position.z) + Vector3(0, 0, -2.2), Vector3.FORWARD, 1.0, false, false)
		rot.set_meta("spin", 0.6 + i * 0.07)
		rot.add_to_group("spinners")

func _process(dt: float) -> void:
	for n in get_tree().get_nodes_in_group("spinners"):
		(n as Node3D).rotate_object_local(Vector3.FORWARD, dt * (n.get_meta("spin") as float))
