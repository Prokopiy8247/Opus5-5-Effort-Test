extends RefCounted
## Follows a car's arclength along one road with a local search (stable on hairpins and loops).
## `s` is cumulative: it keeps growing past the end of a loop road (Road.point_at wraps).

var road: RoadNetwork.Road
var s: float = 0.0


func reset(r: RoadNetwork.Road, at_s: float) -> void:
	road = r
	s = at_s


func update(pos: Vector3) -> void:
	var best := _search(pos, 12, 1)
	if best.y > 400.0:
		# More than 20 m away (respawn / recovery): widen the search.
		best = _search(pos, 90, 2)
	s = best.x
	var t := road.flat_tangent_at(s)
	s += clampf((pos - road.point_at(s)).dot(t), -road.ds, road.ds)
	if not road.loop:
		s = clampf(s, 0.0, road.length)


func _search(pos: Vector3, reach: int, stride: int) -> Vector2:
	var best := s
	var bd := INF
	for k in range(-reach, reach + 1, stride):
		var c := s + k * road.ds
		if not road.loop and (c < 0.0 or c > road.length):
			continue
		var p := road.point_at(c)
		var d := (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
		if d < bd:
			bd = d
			best = c
	return Vector2(best, bd)


## Signed lateral offset (m, + = right of increasing s).
func lateral(pos: Vector3) -> float:
	return (pos - road.point_at(s)).dot(road.right_at(s))


## Horizontal distance from the road centre line.
func distance(pos: Vector3) -> float:
	var p := road.point_at(s)
	return Vector2(pos.x - p.x, pos.z - p.z).length()
