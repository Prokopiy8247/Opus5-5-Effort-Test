extends RefCounted
## One civilian traffic vehicle: its progress on the lane graph (shared by both simulation LODs),
## driver parameters, reaction state and the node currently representing it (pooled merged-mesh
## MeshInstance3D in kinematic LOD, pooled CarController driven by a RoadFollower in physics LOD).

const LaneGraph := preload("res://scripts/traffic/lane_graph.gd")

enum Mode { KINEMATIC, PHYSICS }

## Lateral speed of a lane change (m/s).
const LANE_CHANGE_RATE := 1.15

var uid: int = 0
var type_index: int = 0
var data: Resource
var paint: Dictionary = {}
var length: float = 4.0
var half_width: float = 0.9
var mode: int = Mode.KINEMATIC

# --- path state
var lane: LaneGraph.Lane
var s: float = 0.0
var conn: LaneGraph.Connector
var c: float = 0.0
## Current lateral offset magnitude (eases toward lane.offset + nudge, e.g. during lane changes).
var off: float = 0.0
## Extra offset toward the verge (m) taken to edge past an oncoming race car over the centre line.
var nudge: float = 0.0
var prev_lane: LaneGraph.Lane
var decision: LaneGraph.Decision
var choice: LaneGraph.Connector
## Permission to enter the junction ahead (give-way satisfied).
var go: bool = false

# --- driver
var speed: float = 0.0
var v_desired: float = 20.0
var corner_factor: float = 1.0
var time_gap: float = 1.8
var v_target: float = 0.0
## Curve / junction / lane-end limit (v_target = min(speed_cap, follow_limit)).
var speed_cap: float = INF
var follow_limit: float = INF
var accel_now: float = 0.0
var lead_gap: float = INF
var lead_speed: float = 0.0
var lead_is_player: bool = false
## uid of the traffic vehicle that sets lead_gap (-1: none, the player or another obstacle).
var lead_uid: int = -1
## Speed limit for squeezing past an obstacle beside the lane (player on the hard shoulder...).
var pass_cap: float = INF

# --- reactions
var hazard: bool = false
## Brakes in a straight line at speed (handbrake only to hold it once stopped).
var hazard_brake: float = 0.5
## Shunted (a moderate knock that left it straight in its lane): brakes to shaken_floor, then carries on.
var shaken_t: float = 0.0
var shaken_v: float = 0.0
var shaken_floor: float = 0.0
## No way on its type may take (only a vehicle placed by hand on such a lane): it holds before the junction and
## is removed as soon as nobody can see it.
var leaving: bool = false
var wreck: bool = false
var offlane: bool = false
var hazard_t: float = 0.0
var recover_after: float = 6.0
var recoveries: int = 0
var recovering: bool = false
var recover_t: float = 0.0
var unseen_t: float = 0.0
var blocked_t: float = 0.0
var honk_cd: float = 0.0
var flash_t: float = -1.0
var wait_t: float = 0.0
var waited: bool = false
var stuck_t: float = 0.0
var flip_t: float = 0.0
var offlane_t: float = 0.0
var lane_change_t: float = 0.0

# --- representation
var visual: Node3D
var car: CarController
## Kinematic LOD near the player: pooled box collider that keeps the vehicle solid.
var body: AnimatableBody3D
var follower: RoadFollower
var light_state: int = -1
var promoted_ms: int = 0
var prev_vel: Vector3 = Vector3.ZERO
var jolt: float = 0.0
## Far kinematic vehicles update every other frame: time carried to the next update / used this frame.
var skip_dt: float = 0.0
var tick_dt: float = 0.0
var position: Vector3 = Vector3.ZERO
var heading: Vector3 = Vector3.FORWARD


func enter_lane(l: LaneGraph.Lane, at_s: float) -> void:
	lane = l
	s = at_s
	conn = null
	c = 0.0
	off = l.offset
	nudge = 0.0
	prev_lane = null
	decision = null
	choice = null
	go = false


func enter_conn(cn: LaneGraph.Connector) -> void:
	conn = cn
	c = 0.0
	prev_lane = null
	decision = null
	choice = null
	go = false
	wait_t = 0.0


## Point on the planned path `ahead` metres from the current progress (used for steering look-ahead,
## obstacle probes and kinematic placement).
func path_point(ahead: float) -> Vector3:
	if conn != null:
		return _after_conn(conn, c + ahead)
	# Until a give-way turn is cleared, keep looking straight down the lane (no creeping into the turn).
	if choice != null and decision != null and (go or choice.yield_mode == LaneGraph.Yield.NONE):
		var d := lane.sdist(s, decision.at_s)
		if ahead > d:
			return _after_conn(choice, ahead - maxf(d, 0.0))
	var o := move_toward(off, lane.offset + nudge, LANE_CHANGE_RATE * ahead / maxf(speed, 4.0))
	var s2 := lane.advance(s, ahead)
	if not lane.road.loop:
		s2 = clampf(s2, 0.0, lane.road.length)
	return lane.point(s2, o)


func _after_conn(cn: LaneGraph.Connector, cc: float) -> Vector3:
	if cc <= cn.length:
		return cn.point(cc)
	var l := cn.to_lane
	var s2 := l.advance(cn.to_s, cc - cn.length)
	if not l.road.loop:
		s2 = clampf(s2, 0.0, l.road.length)
	return l.point(s2, l.offset)


## Kinematic movement along the path by `d` metres (lane -> connector -> lane transitions).
func move(d: float) -> void:
	var guard := 0
	while d > 0.0 and guard < 4:
		guard += 1
		if conn != null:
			var rem := conn.length - c
			if d < rem:
				c += d
				return
			d -= rem
			enter_lane(conn.to_lane, conn.to_s)
			continue
		if choice != null and decision != null:
			var dd := lane.sdist(s, decision.at_s)
			if dd <= d:
				d -= maxf(dd, 0.0)
				enter_conn(choice)
				continue
		s = lane.advance(s, d)
		if not lane.road.loop:
			s = clampf(s, 0.0, lane.road.length)
		d = 0.0


## Physics LOD: updates the progress from the car position.
func track(p: Vector3) -> void:
	if conn != null:
		c = conn.project(p, c)
		if c >= conn.length - 0.4:
			var cn := conn
			enter_lane(cn.to_lane, cn.to_s)
			s = project_lane(p, s)
		return
	s = project_lane(p, s)
	if choice != null and decision != null:
		var d := lane.sdist(s, decision.at_s)
		if d <= 0.0:
			var cn2 := choice
			enter_conn(cn2)
			c = cn2.project(p, minf(-d, cn2.length))


## Closest centreline arclength to p near s0 (a few Newton-like projection steps).
func project_lane(p: Vector3, s0: float) -> float:
	var r := lane.road
	var ss := s0
	for i in 4:
		var q := r.point_at(ss)
		var t := r.flat_tangent_at(ss)
		var step := clampf((p.x - q.x) * t.x + (p.z - q.z) * t.z, -15.0, 15.0)
		ss += step
		ss = fposmod(ss, r.length) if r.loop else clampf(ss, 0.0, r.length)
		if absf(step) < 0.05:
			break
	return ss


## Curve / turn speed limit at and just ahead of the current progress.
func curve_limit(brake: float) -> float:
	if conn != null:
		return conn.vmax
	var v := lane.speed_at(s) * corner_factor
	if choice != null and decision != null:
		var d := lane.sdist(s, decision.at_s)
		v = minf(v, sqrt(choice.vmax * choice.vmax + 2.0 * brake * maxf(d - 2.0, 0.0)))
	return v


## Transform for kinematic LOD: on the lane surface (with banking) or along the connector.
func kinematic_transform() -> Transform3D:
	if conn == null:
		return road_transform(lane.road, s, off * lane.dir, lane.dir)
	var f := conn.tangent(c)
	return _frame(conn.point(c), f, Vector3(-f.z, 0.0, f.x))


## Pose on the road surface at arclength s and signed lateral offset (+ = right of increasing s), facing
## along dir (+1 increasing s): follows the grade and the banking. Same frame as
## RoadNetwork.Road.surface_point / tangent_at, with three spline lookups.
static func road_transform(r: RoadNetwork.Road, at_s: float, lateral: float, dir: int) -> Transform3D:
	var a := r.point_at(at_s - r.ds)
	var b := r.point_at(at_s + r.ds)
	var tf := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var rt := Vector3(-tf.z, 0.0, tf.x)
	var bank := r.bank_at(at_s)
	var p := r.point_at(at_s) + rt * lateral + Vector3.UP * (lateral * bank)
	return _frame(p, (b - a).normalized() * dir, (rt + Vector3.UP * bank) * dir)


static func _frame(p: Vector3, f: Vector3, side: Vector3) -> Transform3D:
	var up := side.cross(f).normalized()
	if up.y < 0.2:
		up = Vector3.UP
	var z := -f.normalized()
	var x := up.cross(z).normalized()
	z = x.cross(up).normalized()
	return Transform3D(Basis(x, up, z), p)
