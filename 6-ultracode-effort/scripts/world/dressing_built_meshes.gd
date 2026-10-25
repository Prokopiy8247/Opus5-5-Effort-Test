extends RefCounted
## Procedural low-poly stand-ins for the buildings kit and the roadside kit. Used by prop_library.gd
## only when the Blender kits are missing. Origin = base centre on the ground, front = -Z.
## Buildings carry a stone plinth reaching 2.5 m below the origin so they can sit on slopes.

const MB := preload("res://scripts/world/dressing_mesh_builder.gd")

const BUILDINGS := ["House_Cottage_A", "House_Cottage_B", "House_Townhouse", "Farmhouse", "Barn_Red", "Silo", "Shed_Small",
	"House_Chalet", "House_Adobe", "Gas_Station", "Diner", "Church", "Harbour_Shed", "Boathouse", "Pier_Section", "Boat_Fishing",
	"Lighthouse", "Castle_Ruin_Wall", "Castle_Ruin_Tower", "Wind_Turbine_Tower", "Wind_Turbine_Rotor", "Water_Tower",
	"Festival_Stage", "Festival_Tent", "Viewpoint_Deck"]
const ROADSIDE := ["Sign_SpeedLimit", "Sign_Chevron", "Sign_Danger_Jump", "Sign_Direction", "Delineator_Post", "GuardRail_Post",
	"Lamp_Street", "Utility_Pole", "Fence_Wood", "Wall_Stone", "Bus_Stop", "Bench", "Mailbox", "Bin", "Barrier_Jersey",
	"Cone", "Bridge_Pier", "Tunnel_Portal", "Speed_Trap_Camera", "Checkpoint_Arch", "Festival_Banner", "Flag_Pole", "Fuel_Pump", "Billboard"]

const STONE := Color(0.55, 0.52, 0.47, MB.MATTE)
const WHITE := Color(0.93, 0.92, 0.88, MB.MATTE)
const DARK := Color(0.12, 0.12, 0.13, MB.MATTE)
const WOOD := Color(0.5, 0.37, 0.24, MB.MATTE)
const STEEL := Color(0.62, 0.64, 0.66, MB.METAL)
const DARK_STEEL := Color(0.25, 0.27, 0.29, MB.METAL)
const LAMP := Color(1.0, 0.86, 0.62, MB.NIGHT_LIGHT)


static func handles(name: String) -> bool:
	return name in BUILDINGS or name in ROADSIDE


static func make(name: String) -> MB:
	var b := MB.new()
	var r := RandomNumberGenerator.new()
	r.seed = hash(name) & 0x7fffffff
	match name:
		"House_Cottage_A":
			_house_cottage_a(b, r)
		"House_Cottage_B":
			_house_cottage_b(b, r)
		"House_Townhouse":
			_house_townhouse(b, r)
		"Farmhouse":
			_farmhouse(b, r)
		"Barn_Red":
			_barn_red(b, r)
		"Silo":
			_silo(b, r)
		"Shed_Small":
			_shed_small(b, r)
		"House_Chalet":
			_house_chalet(b, r)
		"House_Adobe":
			_house_adobe(b, r)
		"Gas_Station":
			_gas_station(b, r)
		"Diner":
			_diner(b, r)
		"Church":
			_church(b, r)
		"Harbour_Shed":
			_harbour_shed(b, r)
		"Boathouse":
			_boathouse(b, r)
		"Pier_Section":
			_pier_section(b, r)
		"Boat_Fishing":
			_boat_fishing(b, r)
		"Lighthouse":
			_lighthouse(b, r)
		"Castle_Ruin_Wall":
			_castle_ruin_wall(b, r)
		"Castle_Ruin_Tower":
			_castle_ruin_tower(b, r)
		"Wind_Turbine_Tower":
			_wind_turbine_tower(b, r)
		"Wind_Turbine_Rotor":
			_wind_turbine_rotor(b, r)
		"Water_Tower":
			_water_tower(b, r)
		"Festival_Stage":
			_festival_stage(b, r)
		"Festival_Tent":
			_festival_tent(b, r)
		"Viewpoint_Deck":
			_viewpoint_deck(b, r)
		"Sign_SpeedLimit":
			_sign_speedlimit(b, r)
		"Sign_Chevron":
			_sign_chevron(b, r)
		"Sign_Danger_Jump":
			_sign_danger_jump(b, r)
		"Sign_Direction":
			_sign_direction(b, r)
		"Delineator_Post":
			_delineator_post(b, r)
		"GuardRail_Post":
			_guardrail_post(b, r)
		"Lamp_Street":
			_lamp_street(b, r)
		"Utility_Pole":
			_utility_pole(b, r)
		"Fence_Wood":
			_fence_wood(b, r)
		"Wall_Stone":
			_wall_stone(b, r)
		"Bus_Stop":
			_bus_stop(b, r)
		"Bench":
			_bench(b, r)
		"Mailbox":
			_mailbox(b, r)
		"Bin":
			_bin(b, r)
		"Barrier_Jersey":
			_barrier_jersey(b, r)
		"Cone":
			_cone(b, r)
		"Bridge_Pier":
			_bridge_pier(b, r)
		"Tunnel_Portal":
			_tunnel_portal(b, r)
		"Speed_Trap_Camera":
			_speed_trap_camera(b, r)
		"Checkpoint_Arch":
			_checkpoint_arch(b, r)
		"Festival_Banner":
			_festival_banner(b, r)
		"Flag_Pole":
			_flag_pole(b, r)
		"Fuel_Pump":
			_fuel_pump(b, r)
		"Billboard":
			_billboard(b, r)
		_:
			return null
	return b


# ------------------------------------------------------------------ shared building parts

static func plinth(b: MB, w: float, d: float, top := 0.35) -> void:
	b.block(Vector3(0, -2.5, 0), Vector3(w + 0.3, 2.5 + top, d + 0.3), STONE)


static func walls(b: MB, w: float, d: float, y0: float, h: float, col: Color, top_col := Color(0, 0, 0, -1.0)) -> void:
	b.box(Transform3D(Basis(), Vector3(0, y0 + h * 0.5, 0)), Vector3(w, h, d), col, top_col, false)


## Windows on the four walls of a w x d box. `front` / `back` / `side` are lists of offsets along the wall.
static func windows(b: MB, r: RandomNumberGenerator, w: float, d: float, y: float, front: Array, back: Array, side: Array, ww: float, wh: float, frame: Color) -> void:
	for x: float in front:
		b.window(Vector3(x, y, -d * 0.5), Vector3(0, 0, -1), ww, wh, frame, r)
	for x: float in back:
		b.window(Vector3(x, y, d * 0.5), Vector3(0, 0, 1), ww, wh, frame, r)
	for z: float in side:
		b.window(Vector3(-w * 0.5, y, z), Vector3(-1, 0, 0), ww, wh, frame, r)
		b.window(Vector3(w * 0.5, y, z), Vector3(1, 0, 0), ww, wh, frame, r)


static func door(b: MB, pos: Vector3, n: Vector3, w: float, h: float, col: Color, frame: Color) -> void:
	b.panel(pos + Vector3(0, h * 0.5, 0), n, w + 0.24, h + 0.12, frame, 0.06)
	b.panel(pos + Vector3(0, h * 0.5 - 0.02, 0), n, w, h, col, 0.1)
	var right := Vector3.UP.cross(n).normalized()
	b.box(Transform3D(Basis(right, Vector3.UP, n), pos + Vector3(0, h * 0.5, 0) + n * 0.12 + right * w * 0.32), Vector3(0.06, 0.06, 0.06), Color(0.8, 0.7, 0.3, MB.METAL))
	b.box(Transform3D(Basis(right, Vector3.UP, n), pos + Vector3(0, -0.1, 0) + n * 0.35), Vector3(w + 0.6, 0.2, 0.7), STONE)


## Flower box under a window (two-colour blossoms).
static func flower_box(b: MB, r: RandomNumberGenerator, pos: Vector3, n: Vector3, w: float) -> void:
	var right := Vector3.UP.cross(n).normalized()
	b.box(Transform3D(Basis(right, Vector3.UP, n), pos + n * 0.2), Vector3(w, 0.22, 0.25), Color(0.4, 0.26, 0.16, MB.MATTE))
	for i in 5:
		var p := pos + n * 0.22 + right * lerpf(-w * 0.4, w * 0.4, i / 4.0) + Vector3(0, 0.18, 0)
		var c := Color(0.92, 0.2, 0.25, MB.MATTE) if i % 2 == 0 else Color(0.98, 0.6, 0.72, MB.MATTE)
		b.blob(p, Vector3(0.14, 0.11, 0.1), c, r, 0.2, 0, 0.4, 0.1)


static func chimney(b: MB, pos: Vector3, h: float, col: Color) -> void:
	b.block(pos, Vector3(0.7, h, 0.7), col)
	b.block(pos + Vector3(0, h, 0), Vector3(0.85, 0.18, 0.85), MB.shade(col, 0.8))
	b.block(pos + Vector3(0, h + 0.18, 0), Vector3(0.22, 0.3, 0.22), Color(0.6, 0.35, 0.25, MB.MATTE))


## Extruded closed polygon prism along local Z (profile in XY), used for barn ends, hulls of signs, etc.
static func prism(b: MB, xf: Transform3D, profile: PackedVector2Array, z0: float, z1: float, col: Color, cap_col: Color) -> void:
	var n := profile.size()
	var c2 := Vector2.ZERO
	for p in profile:
		c2 += p
	c2 /= n
	var cen := xf * Vector3(c2.x, c2.y, (z0 + z1) * 0.5)
	for i in n:
		var a := profile[i]
		var c := profile[(i + 1) % n]
		var p0 := xf * Vector3(a.x, a.y, z0)
		var p1 := xf * Vector3(c.x, c.y, z0)
		var p2 := xf * Vector3(c.x, c.y, z1)
		var p3 := xf * Vector3(a.x, a.y, z1)
		b.quad(p0, p1, p2, p3, col, (p0 + p2) * 0.5 - cen)
		b.tri(xf * Vector3(c2.x, c2.y, z0), p0, p1, cap_col, -xf.basis.z)
		b.tri(xf * Vector3(c2.x, c2.y, z1), p3, p2, cap_col, xf.basis.z)



# ============================================================== houses

static func _house_cottage_a(b: MB, r: RandomNumberGenerator) -> void:
	var w := 8.6
	var d := 6.6
	var cream := Color(0.94, 0.88, 0.74, MB.TINT)
	var roof := Color(0.68, 0.31, 0.2, MB.MATTE)
	var trim := WHITE
	plinth(b, w, d)
	walls(b, w, d, 0.35, 4.65, cream)
	b.gable_roof(Transform3D.IDENTITY, w, d, 5.0, 3.4, 0.5, roof, cream)
	windows(b, r, w, d, 1.75, [-2.6, 2.6], [-2.6, 0.0, 2.6], [0.0], 1.1, 1.25, trim)
	windows(b, r, w, d, 3.95, [-2.2, 0.0, 2.2], [-2.2, 2.2], [], 0.95, 1.0, trim)
	b.window(Vector3(-w * 0.5, 6.0, 0), Vector3(-1, 0, 0), 0.7, 0.8, trim, r)
	b.window(Vector3(w * 0.5, 6.0, 0), Vector3(1, 0, 0), 0.7, 0.8, trim, r)
	door(b, Vector3(0, 0.35, -d * 0.5), Vector3(0, 0, -1), 1.05, 2.1, Color(0.2, 0.4, 0.3, MB.PAINT), trim)
	for x: float in [-2.6, 2.6]:
		flower_box(b, r, Vector3(x, 0.95, -d * 0.5), Vector3(0, 0, -1), 1.3)
	chimney(b, Vector3(2.7, 5.4, 0.9), 3.8, Color(0.6, 0.33, 0.24, MB.MATTE))

static func _house_cottage_b(b: MB, r: RandomNumberGenerator) -> void:
	var w := 9.4
	var d := 7.0
	var stone := Color(0.72, 0.68, 0.6, MB.MATTE)
	var slate := Color(0.32, 0.34, 0.38, MB.MATTE)
	var trim := Color(0.95, 0.94, 0.9, MB.MATTE)
	plinth(b, w, d)
	walls(b, w, d, 0.35, 4.25, stone)
	b.gable_roof(Transform3D.IDENTITY, w, d, 4.6, 3.8, 0.45, slate, stone)
	windows(b, r, w, d, 1.7, [-2.9, -1.2, 2.6], [-2.6, 0.0, 2.6], [-1.2, 1.2], 1.0, 1.2, trim)
	windows(b, r, w, d, 3.6, [-2.9, 2.6], [-2.6, 2.6], [], 0.9, 0.9, trim)
	door(b, Vector3(0.7, 0.35, -d * 0.5), Vector3(0, 0, -1), 1.0, 2.1, Color(0.66, 0.16, 0.12, MB.PAINT), trim)
	# porch canopy over the door
	b.box(Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(0.7, 2.85, -d * 0.5 - 0.55)), Vector3(1.9, 0.1, 1.2), slate)
	# dormer on the front roof slope
	var dz := -1.2
	b.block(Vector3(-1.3, 4.5, dz - 0.6), Vector3(1.8, 1.8, 2.0), stone)
	b.gable_roof(Transform3D(Basis(), Vector3(-1.3, 0, dz - 0.6)), 1.8, 2.0, 6.3, 0.9, 0.2, slate, stone, true)
	b.window(Vector3(-1.3, 5.3, dz - 1.6), Vector3(0, 0, -1), 0.8, 0.8, trim, r)
	chimney(b, Vector3(-3.6, 5.0, 0.5), 3.8, stone)
	chimney(b, Vector3(3.6, 5.0, 0.5), 3.8, stone)

static func _house_townhouse(b: MB, r: RandomNumberGenerator) -> void:
	var w := 7.2
	var d := 9.0
	var wall := Color(0.97, 0.95, 0.91, MB.TINT)
	var slate := Color(0.3, 0.32, 0.36, MB.MATTE)
	var trim := Color(0.98, 0.98, 0.96, MB.MATTE)
	plinth(b, w, d, 0.6)
	walls(b, w, d, 0.6, 8.2, wall)
	b.box(Transform3D(Basis(), Vector3(0, 8.6, 0)), Vector3(w + 0.3, 0.35, d + 0.3), trim)
	b.box(Transform3D(Basis(), Vector3(0, 3.35, 0)), Vector3(w + 0.1, 0.18, d + 0.1), trim)
	b.gable_roof(Transform3D(Basis(), Vector3(0, 0, 0)), w, d, 8.75, 3.0, 0.3, slate, wall)
	windows(b, r, w, d, 2.0, [-2.3, 2.3], [-2.3, 0.0, 2.3], [-2.5, 2.5], 1.0, 1.6, trim)
	windows(b, r, w, d, 4.9, [-2.3, 0.0, 2.3], [-2.3, 0.0, 2.3], [-2.5, 2.5], 1.0, 1.6, trim)
	windows(b, r, w, d, 7.3, [-2.3, 0.0, 2.3], [-2.3, 0.0, 2.3], [0.0], 0.9, 1.2, trim)
	door(b, Vector3(0, 0.6, -d * 0.5), Vector3(0, 0, -1), 1.1, 2.3, Color(0.12, 0.18, 0.32, MB.PAINT), trim)
	b.window(Vector3(0, 3.25, -d * 0.5), Vector3(0, 0, -1), 1.0, 0.35, trim, r)
	b.block(Vector3(0, -0.2, -d * 0.5 - 0.9), Vector3(1.8, 0.5, 0.6), STONE)
	chimney(b, Vector3(-2.6, 9.6, 2.5), 2.6, Color(0.58, 0.34, 0.26, MB.MATTE))

static func _farmhouse(b: MB, r: RandomNumberGenerator) -> void:
	var w := 12.5
	var d := 8.2
	var wall := Color(0.94, 0.92, 0.86, MB.TINT)
	var roof := Color(0.62, 0.27, 0.18, MB.MATTE)
	var trim := Color(0.3, 0.42, 0.32, MB.PAINT)
	plinth(b, w, d)
	walls(b, w, d, 0.35, 5.85, wall)
	b.gable_roof(Transform3D.IDENTITY, w, d, 6.2, 4.2, 0.55, roof, wall)
	windows(b, r, w, d, 1.75, [-4.4, -2.2, 2.2, 4.4], [-4.4, -1.5, 1.5, 4.4], [-1.6, 1.6], 1.05, 1.3, WHITE)
	windows(b, r, w, d, 4.4, [-4.4, -2.2, 0.0, 2.2, 4.4], [-4.4, -1.5, 1.5, 4.4], [-1.6, 1.6], 1.0, 1.2, WHITE)
	door(b, Vector3(0, 0.35, -d * 0.5), Vector3(0, 0, -1), 1.2, 2.2, trim, WHITE)
	# porch
	var pz := -d * 0.5 - 1.6
	for x: float in [-3.2, 3.2]:
		b.block(Vector3(x, 0.35, pz - 0.6), Vector3(0.22, 2.7, 0.22), WHITE)
	b.box(Transform3D(Basis(Vector3(1, 0, 0), -0.22), Vector3(0, 3.15, pz)), Vector3(7.2, 0.14, 3.4), roof)
	b.block(Vector3(0, 0.0, pz + 0.3), Vector3(7.0, 0.38, 2.6), Color(0.6, 0.5, 0.4, MB.MATTE))
	chimney(b, Vector3(-4.9, 7.0, 0.0), 4.4, Color(0.6, 0.36, 0.26, MB.MATTE))
	chimney(b, Vector3(4.9, 7.0, 0.0), 4.4, Color(0.6, 0.36, 0.26, MB.MATTE))

static func _barn_red(b: MB, r: RandomNumberGenerator) -> void:
	var hw := 7.0
	var hd := 11.0
	var red := Color(0.64, 0.14, 0.1, MB.MATTE)
	var trim := WHITE
	var roof := Color(0.34, 0.35, 0.37, MB.METAL)
	plinth(b, hw * 2.0, hd * 2.0, 0.3)
	walls(b, hw * 2.0, hd * 2.0, 0.3, 6.2, red)
	# gambrel roof, ridge along Z, gable ends front/back
	var prof := [Vector2(-hw - 0.45, 6.15), Vector2(-4.7, 9.4), Vector2(0, 11.0), Vector2(4.7, 9.4), Vector2(hw + 0.45, 6.15)]
	var th := Vector3(0, 0.16, 0)
	for i in 4:
		var a: Vector2 = prof[i]
		var c: Vector2 = prof[i + 1]
		var p0 := Vector3(a.x, a.y, -hd - 0.45)
		var p1 := Vector3(c.x, c.y, -hd - 0.45)
		var p2 := Vector3(c.x, c.y, hd + 0.45)
		var p3 := Vector3(a.x, a.y, hd + 0.45)
		var mid := (a + c) * 0.5
		var out := Vector3(mid.x, mid.y - 6.0, 0)
		b.quad(p0 + th, p1 + th, p2 + th, p3 + th, roof, out)
		b.quad(p0, p1, p2, p3, MB.shade(roof, 0.4), -out)
		b.quad(p0, p1, p1 + th, p0 + th, MB.shade(roof, 0.5), Vector3(0, 0, -1))
		b.quad(p3, p2, p2 + th, p3 + th, MB.shade(roof, 0.5), Vector3(0, 0, 1))
	for s: float in [-1.0, 1.0]:
		var z := s * hd
		var base := Vector3(0, 6.5, z)
		var pts := [Vector3(-hw, 6.5, z), Vector3(-4.6, 9.25, z), Vector3(0, 10.85, z), Vector3(4.6, 9.25, z), Vector3(hw, 6.5, z)]
		for i in 4:
			b.tri(base, pts[i], pts[i + 1], red, Vector3(0, 0, s))
		b.tri(Vector3(-hw, 6.2, z), Vector3(hw, 6.2, z), base, red, Vector3(0, 0, s))
		b.tri(Vector3(-hw, 6.2, z), base, Vector3(-hw, 6.5, z), red, Vector3(0, 0, s))
		b.tri(Vector3(hw, 6.2, z), Vector3(hw, 6.5, z), base, red, Vector3(0, 0, s))
	# trim boards
	for x: float in [-hw, hw]:
		for z: float in [-hd, hd]:
			b.block(Vector3(x, 0.3, z), Vector3(0.3, 6.2, 0.3), trim)
	# big doors with X braces + hayloft
	var n := Vector3(0, 0, -1)
	b.panel(Vector3(0, 2.9, -hd), n, 5.6, 5.2, trim, 0.08)
	b.panel(Vector3(0, 2.85, -hd), n, 5.2, 4.9, MB.shade(red, 0.82), 0.12)
	for sx: float in [-1.0, 1.0]:
		b.beam(Vector3(sx * 2.5, 0.5, -hd - 0.14), Vector3(sx * 0.15, 5.2, -hd - 0.14), 0.16, trim, Vector3(0, 0, 1))
		b.beam(Vector3(sx * 0.15, 0.5, -hd - 0.14), Vector3(sx * 2.5, 5.2, -hd - 0.14), 0.16, trim, Vector3(0, 0, 1))
	b.panel(Vector3(0, 8.0, -hd), n, 2.2, 2.0, trim, 0.08)
	b.panel(Vector3(0, 8.0, -hd), n, 1.8, 1.7, MB.shade(red, 0.75), 0.12)
	for z: float in [-6.0, -2.0, 2.0, 6.0]:
		b.window(Vector3(-hw, 3.6, z), Vector3(-1, 0, 0), 1.0, 1.0, trim, r)
		b.window(Vector3(hw, 3.6, z), Vector3(1, 0, 0), 1.0, 1.0, trim, r)
	b.panel(Vector3(0, 2.4, hd), Vector3(0, 0, 1), 3.6, 4.0, MB.shade(red, 0.8), 0.1)

static func _silo(b: MB, r: RandomNumberGenerator) -> void:
	var m := Color(0.8, 0.81, 0.82, MB.METAL)
	b.cyl(Transform3D(Basis(), Vector3(0, -1.0, 0)), 2.6, 2.6, 1.3, 16, STONE, true)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.3, 0)), 2.4, 2.4, 13.6, 16, m, false)
	for i in 6:
		b.cyl(Transform3D(Basis(), Vector3(0, 1.8 + i * 2.2, 0)), 2.43, 2.43, 0.14, 16, MB.shade(m, 0.8), false)
	b.cyl(Transform3D(Basis(), Vector3(0, 13.9, 0)), 2.45, 1.3, 1.4, 16, m, false)
	b.cyl(Transform3D(Basis(), Vector3(0, 15.3, 0)), 1.3, 0.0, 0.7, 16, m, false)
	b.cyl(Transform3D(Basis(), Vector3(0, 15.9, 0)), 0.3, 0.3, 0.5, 8, DARK_STEEL)
	for x: float in [-0.25, 0.25]:
		b.beam(Vector3(x, 0.4, -2.55), Vector3(x, 14.0, -2.55), 0.06, DARK_STEEL)
	for i in 26:
		b.beam(Vector3(-0.25, 0.8 + i * 0.5, -2.55), Vector3(0.25, 0.8 + i * 0.5, -2.55), 0.04, DARK_STEEL)

static func _shed_small(b: MB, r: RandomNumberGenerator) -> void:
	var wood := Color(0.48, 0.34, 0.22, MB.MATTE)
	plinth(b, 3.8, 3.0, 0.15)
	walls(b, 3.8, 3.0, 0.15, 2.35, wood)
	for i in 7:
		b.panel(Vector3(-1.65 + i * 0.55, 1.3, -1.5), Vector3(0, 0, -1), 0.05, 2.3, MB.shade(wood, 0.75), 0.02)
	b.box(Transform3D(Basis(Vector3(1, 0, 0), 0.14), Vector3(0, 2.65, 0)), Vector3(4.4, 0.12, 3.8), Color(0.28, 0.3, 0.3, MB.METAL))
	door(b, Vector3(0.6, 0.15, -1.5), Vector3(0, 0, -1), 0.9, 1.95, MB.shade(wood, 0.8), MB.shade(wood, 0.6))
	b.window(Vector3(-1.9, 1.6, 0.0), Vector3(-1, 0, 0), 0.7, 0.6, WHITE, r)

static func _house_chalet(b: MB, r: RandomNumberGenerator) -> void:
	var w := 9.5
	var d := 10.0
	var stone := Color(0.62, 0.6, 0.56, MB.MATTE)
	var timber := Color(0.43, 0.28, 0.17, MB.MATTE)
	var roof := Color(0.27, 0.24, 0.23, MB.MATTE)
	var shutter := Color(0.66, 0.15, 0.12, MB.PAINT)
	plinth(b, w, d)
	walls(b, w, d, 0.35, 2.75, stone)
	walls(b, w + 0.1, d + 0.1, 3.1, 2.8, timber)
	b.gable_roof(Transform3D.IDENTITY, w + 0.1, d + 0.1, 5.9, 4.2, 1.3, roof, timber, true)
	windows(b, r, w, d, 1.8, [-2.6, 2.6], [-2.6, 2.6], [-2.5, 2.5], 1.0, 1.1, WHITE)
	windows(b, r, w, d, 4.5, [-2.8, 0.0, 2.8], [-2.8, 2.8], [-2.5, 2.5], 1.0, 1.2, WHITE)
	b.window(Vector3(0, 7.2, -d * 0.5 - 0.05), Vector3(0, 0, -1), 1.2, 1.0, WHITE, r)
	for x: float in [-2.8, 0.0, 2.8]:
		for s: float in [-1.0, 1.0]:
			b.panel(Vector3(x + s * 0.85, 4.5, -d * 0.5 - 0.05), Vector3(0, 0, -1), 0.4, 1.3, shutter, 0.05)
	door(b, Vector3(0, 0.35, -d * 0.5), Vector3(0, 0, -1), 1.1, 2.1, timber, MB.shade(timber, 0.7))
	# balcony
	var bz := -d * 0.5 - 0.75
	b.block(Vector3(0, 3.0, bz), Vector3(w + 0.6, 0.22, 1.5), timber)
	b.block(Vector3(0, 3.22, bz - 0.68), Vector3(w + 0.6, 0.85, 0.08), MB.shade(timber, 1.15))
	b.block(Vector3(0, 4.07, bz - 0.68), Vector3(w + 0.7, 0.1, 0.16), MB.shade(timber, 0.8))
	for s: float in [-1.0, 1.0]:
		b.block(Vector3(s * (w * 0.5 + 0.25), 3.22, bz), Vector3(0.08, 0.85, 1.4), MB.shade(timber, 1.15))
		b.beam(Vector3(s * (w * 0.5 - 0.3), 1.2, -d * 0.5), Vector3(s * (w * 0.5 - 0.3), 3.0, bz - 0.5), 0.18, timber)
	for i in 6:
		var x := lerpf(-w * 0.45, w * 0.45, i / 5.0)
		flower_box(b, r, Vector3(x, 4.15, bz - 0.75), Vector3(0, 0, -1), 0.9)
	chimney(b, Vector3(2.2, 7.2, 2.5), 3.4, stone)

static func _house_adobe(b: MB, r: RandomNumberGenerator) -> void:
	var w := 8.4
	var d := 7.2
	var adobe := Color(0.84, 0.64, 0.47, MB.TINT)
	var top := Color(0.74, 0.55, 0.4, MB.TINT)
	var blue := Color(0.18, 0.42, 0.62, MB.PAINT)
	var beam := Color(0.42, 0.3, 0.2, MB.MATTE)
	b.block(Vector3(0, -2.5, 0), Vector3(w + 0.2, 2.7, d + 0.2), adobe)
	walls(b, w, d, 0.2, 3.9, adobe, top)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		b.block(Vector3(s.x * (w * 0.5 - 0.35), 4.1, s.y * (d * 0.5 - 0.35)), Vector3(0.9, 0.45, 0.9), adobe, 0.0, top)
	b.block(Vector3(0, 4.1, -d * 0.5 + 0.12), Vector3(w - 1.6, 0.25, 0.24), adobe, 0.0, top)
	for i in 6:
		var x := lerpf(-w * 0.4, w * 0.4, i / 5.0)
		b.cyl_between(Vector3(x, 3.55, -d * 0.5 + 0.2), Vector3(x, 3.6, -d * 0.5 - 0.55), 0.11, 0.1, 6, beam)
		b.cyl_between(Vector3(x, 3.55, d * 0.5 - 0.2), Vector3(x, 3.6, d * 0.5 + 0.55), 0.11, 0.1, 6, beam)
	windows(b, r, w, d, 1.9, [-2.5, 2.5], [-2.2, 2.2], [0.0], 0.9, 1.0, blue)
	door(b, Vector3(0, 0.2, -d * 0.5), Vector3(0, 0, -1), 1.1, 2.15, Color(0.45, 0.3, 0.18, MB.MATTE), blue)
	# upper block
	b.block(Vector3(-1.9, 4.1, 1.3), Vector3(4.0, 2.6, 4.0), adobe, 0.0, top)
	b.window(Vector3(-1.9, 5.4, -0.7), Vector3(0, 0, -1), 0.8, 0.8, blue, r)
	b.window(Vector3(-3.9, 5.4, 1.3), Vector3(-1, 0, 0), 0.8, 0.8, blue, r)
	for x: float in [0.5, 0.9]:
		b.beam(Vector3(x, 4.1, -0.9), Vector3(x + 0.1, 6.4, -0.6), 0.07, beam)
	for i in 5:
		b.beam(Vector3(0.5, 4.5 + i * 0.4, -0.85 + i * 0.012), Vector3(0.95, 4.5 + i * 0.4, -0.82 + i * 0.012), 0.05, beam)

# ============================================================== commercial

static func _gas_station(b: MB, r: RandomNumberGenerator) -> void:
	var white := Color(0.95, 0.95, 0.94, MB.MATTE)
	var orange := Color(0.98, 0.5, 0.12, MB.PAINT)
	var teal := Color(0.05, 0.55, 0.58, MB.PAINT)
	var conc := Color(0.7, 0.69, 0.66, MB.MATTE)
	# forecourt slab and pump islands (front part, z in -11..1)
	b.block(Vector3(0, -3.0, -5.0), Vector3(17.0, 3.08, 12.5), conc)
	for x: float in [-2.9, 2.9]:
		b.block(Vector3(x, 0.08, -5.25), Vector3(1.3, 0.22, 5.4), Color(0.85, 0.84, 0.8, MB.MATTE))
		b.block(Vector3(x, 0.3, -5.25), Vector3(0.4, 4.75, 0.4), white)
	# canopy
	b.block(Vector3(0, 5.05, -5.25), Vector3(16.0, 1.1, 11.5), white)
	b.block(Vector3(0, 5.35, -5.25), Vector3(16.12, 0.38, 11.62), orange)
	b.block(Vector3(0, 5.75, -5.25), Vector3(16.12, 0.12, 11.62), teal)
	for i in 3:
		for j in 2:
			var c := Vector3(-5.0 + i * 5.0, 5.02, -8.0 + j * 5.5)
			b.quad(c + Vector3(-1.2, 0, -0.5), c + Vector3(1.2, 0, -0.5), c + Vector3(1.2, 0, 0.5), c + Vector3(-1.2, 0, 0.5), LAMP, Vector3.DOWN)
	# shop
	var sw := 12.0
	var sd := 7.0
	var sz := 8.5
	b.block(Vector3(0, -2.5, sz), Vector3(sw + 0.3, 2.75, sd + 0.3), STONE)
	b.block(Vector3(0, 0.25, sz), Vector3(sw, 3.9, sd), white)
	b.block(Vector3(0, 4.15, sz), Vector3(sw + 0.4, 0.7, sd + 0.4), orange)
	b.block(Vector3(0, 4.85, sz), Vector3(sw + 0.4, 0.12, sd + 0.4), teal)
	var gl := Color(0.16, 0.22, 0.28, MB.GLASS)
	for i in 4:
		var x := -4.5 + i * 3.0
		if i == 2:
			continue
		b.panel(Vector3(x, 2.0, sz - sd * 0.5), Vector3(0, 0, -1), 2.6, 2.6, DARK_STEEL, 0.06)
		b.panel(Vector3(x, 2.0, sz - sd * 0.5 - 0.03), Vector3(0, 0, -1), 2.4, 2.4, Color(gl.r + 0.01 * i, gl.g, gl.b, MB.GLASS), 0.06)
	door(b, Vector3(1.5, 0.25, sz - sd * 0.5), Vector3(0, 0, -1), 1.8, 2.3, Color(0.2, 0.26, 0.3, MB.GLASS), DARK_STEEL)
	# price pylon
	b.block(Vector3(7.6, 0.0, -11.2), Vector3(0.5, 6.0, 0.5), DARK_STEEL)
	b.block(Vector3(7.6, 4.2, -11.2), Vector3(1.8, 2.6, 0.35), white)
	b.block(Vector3(7.6, 6.0, -11.2), Vector3(1.9, 0.7, 0.4), orange)
	for i in 3:
		b.panel(Vector3(7.6, 4.6 + i * 0.6, -11.4), Vector3(0, 0, -1), 1.3, 0.38, Color(0.95, 0.85, 0.3, MB.LIGHT), 0.02)
		b.panel(Vector3(7.6, 4.6 + i * 0.6, -11.0), Vector3(0, 0, 1), 1.3, 0.38, Color(0.95, 0.85, 0.3, MB.LIGHT), 0.02)

static func _diner(b: MB, r: RandomNumberGenerator) -> void:
	var w := 16.0
	var d := 8.0
	var steel := Color(0.8, 0.82, 0.84, MB.METAL)
	var red := Color(0.86, 0.12, 0.14, MB.PAINT)
	var cream := Color(0.97, 0.94, 0.86, MB.MATTE)
	var rad := d * 0.5
	b.block(Vector3(0, -2.5, 0), Vector3(w + 0.3, 2.85, d + 0.3), STONE)
	b.block(Vector3(0, 0.35, 0), Vector3(w - d, 3.9, d), steel)
	for s: float in [-1.0, 1.0]:
		b.cyl(Transform3D(Basis(), Vector3(s * (w * 0.5 - rad), 0.35, 0)), rad, rad, 3.9, 14, steel, false)
	var gl := Color(0.17, 0.24, 0.3, MB.GLASS)
	b.block(Vector3(0, 1.25, -rad), Vector3(w - d - 2.6, 1.35, 0.1), gl)
	b.block(Vector3(0, 1.25, rad), Vector3(w - d, 1.35, 0.1), gl)
	for s: float in [-1.0, 1.0]:
		b.cyl(Transform3D(Basis(), Vector3(s * (w * 0.5 - rad), 1.25, 0)), rad + 0.03, rad + 0.03, 1.35, 14, Color(0.18, 0.25, 0.31, MB.GLASS), false)
	for y: float in [0.95, 2.8]:
		b.block(Vector3(0, y, 0), Vector3(w - d, 0.22, d + 0.08), red)
		for s: float in [-1.0, 1.0]:
			b.cyl(Transform3D(Basis(), Vector3(s * (w * 0.5 - rad), y, 0)), rad + 0.04, rad + 0.04, 0.22, 14, red, false)
	# roof with overhang
	b.block(Vector3(0, 4.25, 0), Vector3(w - d, 0.3, d + 0.8), cream)
	for s: float in [-1.0, 1.0]:
		b.cyl(Transform3D(Basis(), Vector3(s * (w * 0.5 - rad), 4.25, 0)), rad + 0.4, rad + 0.4, 0.3, 14, cream, true)
	# entrance vestibule
	b.block(Vector3(0, 0.35, -rad - 0.9), Vector3(2.6, 3.2, 1.8), steel, 0.0, cream)
	door(b, Vector3(0, 0.35, -rad - 1.8), Vector3(0, 0, -1), 1.4, 2.3, Color(0.2, 0.27, 0.32, MB.GLASS), red)
	# rooftop neon sign
	b.block(Vector3(-2.6, 4.55, 0), Vector3(0.2, 1.2, 0.2), DARK_STEEL)
	b.block(Vector3(2.6, 4.55, 0), Vector3(0.2, 1.2, 0.2), DARK_STEEL)
	b.block(Vector3(0, 5.6, 0), Vector3(7.4, 1.9, 0.35), Color(0.12, 0.1, 0.16, MB.MATTE))
	var neon_a := Color(1.0, 0.3, 0.62, MB.LIGHT)
	var neon_b := Color(0.25, 0.92, 1.0, MB.LIGHT)
	for face: float in [-1.0, 1.0]:
		var n := Vector3(0, 0, face)
		b.panel(Vector3(0, 6.3, face * 0.18), n, 6.6, 0.16, neon_a, 0.03)
		b.panel(Vector3(0, 5.75, face * 0.18), n, 6.6, 0.16, neon_b, 0.03)
		for i in 5:
			b.panel(Vector3(-2.6 + i * 1.3, 6.03, face * 0.18), n, 0.7, 0.3, neon_a if i % 2 == 0 else neon_b, 0.03)
	b.blob(Vector3(w * 0.5 - rad + 2.4, 5.0, 0), Vector3(0.9, 0.9, 0.2), Color(1.0, 0.75, 0.2, MB.LIGHT), r, 0.0, 1, 0.5, 0.0)

static func _church(b: MB, r: RandomNumberGenerator) -> void:
	var w := 9.5
	var d := 18.0
	var stone := Color(0.76, 0.72, 0.64, MB.MATTE)
	var slate := Color(0.3, 0.32, 0.36, MB.MATTE)
	plinth(b, w, d)
	walls(b, w, d, 0.35, 7.3, stone)
	b.gable_roof(Transform3D.IDENTITY, w, d, 7.65, 5.6, 0.45, slate, stone, true)
	for z: float in [-5.0, -1.0, 3.0, 7.0]:
		for s: float in [-1.0, 1.0]:
			b.window(Vector3(s * w * 0.5, 3.6, z), Vector3(s, 0, 0), 1.1, 3.0, MB.shade(stone, 0.85), r, Color(0.3, 0.22, 0.4))
			b.blob(Vector3(s * (w * 0.5 + 0.06), 5.15, z), Vector3(0.05, 0.55, 0.55), MB.shade(stone, 0.85), r, 0.0, 0, 0.0, 0.0)
	b.window(Vector3(0, 4.0, d * 0.5), Vector3(0, 0, 1), 2.4, 3.2, MB.shade(stone, 0.85), r, Color(0.3, 0.22, 0.4))
	# buttresses
	for z: float in [-7.0, -3.0, 1.0, 5.0]:
		for s: float in [-1.0, 1.0]:
			b.box(Transform3D(Basis(), Vector3(s * (w * 0.5 + 0.35), 2.4, z)), Vector3(0.7, 4.8, 0.8), MB.shade(stone, 0.95))
	# bell tower at the front
	var tz := -d * 0.5 - 2.0
	b.block(Vector3(0, -2.5, tz), Vector3(4.6, 2.85, 4.6), STONE)
	b.block(Vector3(0, 0.35, tz), Vector3(4.2, 16.6, 4.2), stone)
	b.block(Vector3(0, 16.95, tz), Vector3(4.6, 0.4, 4.6), MB.shade(stone, 0.85))
	for s: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
		b.panel(Vector3(0, 14.6, tz) + s * 2.1, s, 1.2, 2.2, DARK, 0.04)
	b.panel(Vector3(0, 11.2, tz - 2.1), Vector3(0, 0, -1), 1.5, 1.5, Color(0.95, 0.94, 0.9, MB.MATTE), 0.06)
	b.panel(Vector3(0.0, 11.4, tz - 2.18), Vector3(0, 0, -1), 0.08, 0.6, DARK, 0.02)
	b.panel(Vector3(0.2, 11.2, tz - 2.18), Vector3(0, 0, -1), 0.45, 0.08, DARK, 0.02)
	b.cyl(Transform3D(Basis(), Vector3(0, 17.35, tz)), 3.0, 0.0, 9.5, 4, slate, false, false, slate, PI * 0.25)
	b.beam(Vector3(0, 26.6, tz), Vector3(0, 28.4, tz), 0.1, Color(0.8, 0.65, 0.25, MB.METAL))
	b.beam(Vector3(-0.45, 27.8, tz), Vector3(0.45, 27.8, tz), 0.09, Color(0.8, 0.65, 0.25, MB.METAL))
	door(b, Vector3(0, 0.35, tz - 2.1), Vector3(0, 0, -1), 1.6, 3.0, Color(0.36, 0.22, 0.13, MB.MATTE), MB.shade(stone, 0.8))

static func _harbour_shed(b: MB, r: RandomNumberGenerator) -> void:
	var w := 12.0
	var d := 18.0
	var wall := Color(0.86, 0.87, 0.87, MB.TINT)
	var roof := Color(0.38, 0.4, 0.42, MB.METAL)
	plinth(b, w, d, 0.3)
	walls(b, w, d, 0.3, 5.7, wall)
	for i in 19:
		var x := -w * 0.5 + 0.3 + i * 0.63
		b.panel(Vector3(x, 3.15, -d * 0.5), Vector3(0, 0, -1), 0.08, 5.6, MB.shade(wall, 0.85), 0.03)
		b.panel(Vector3(x, 3.15, d * 0.5), Vector3(0, 0, 1), 0.08, 5.6, MB.shade(wall, 0.85), 0.03)
	b.gable_roof(Transform3D.IDENTITY, w, d, 6.0, 2.4, 0.4, roof, wall, true)
	b.panel(Vector3(-1.5, 2.6, -d * 0.5 - 0.05), Vector3(0, 0, -1), 5.4, 4.6, Color(0.42, 0.45, 0.47, MB.METAL), 0.1)
	for i in 9:
		b.panel(Vector3(-1.5, 0.6 + i * 0.5, -d * 0.5 - 0.15), Vector3(0, 0, -1), 5.3, 0.05, Color(0.3, 0.32, 0.34, MB.METAL), 0.02)
	door(b, Vector3(3.6, 0.3, -d * 0.5), Vector3(0, 0, -1), 1.0, 2.1, Color(0.2, 0.32, 0.45, MB.PAINT), WHITE)
	for z: float in [-5.0, 0.0, 5.0]:
		b.window(Vector3(-w * 0.5, 3.6, z), Vector3(-1, 0, 0), 1.4, 1.0, WHITE, r)
		b.window(Vector3(w * 0.5, 3.6, z), Vector3(1, 0, 0), 1.4, 1.0, WHITE, r)
	b.block(Vector3(0, 6.6, -d * 0.5 - 0.1), Vector3(5.0, 0.9, 0.12), Color(0.1, 0.36, 0.55, MB.PAINT))

static func _boathouse(b: MB, r: RandomNumberGenerator) -> void:
	var w := 7.0
	var d := 10.0
	var wood := Color(0.52, 0.24, 0.16, MB.MATTE)
	var roof := Color(0.25, 0.25, 0.27, MB.MATTE)
	for x: float in [-3.2, 0.0, 3.2]:
		for z: float in [-4.6, 0.0, 4.6]:
			b.block(Vector3(x, -5.0, z), Vector3(0.3, 5.4, 0.3), Color(0.32, 0.26, 0.2, MB.MATTE))
	b.block(Vector3(0, 0.0, 0), Vector3(w + 0.6, 0.35, d + 0.4), Color(0.5, 0.4, 0.3, MB.MATTE))
	walls(b, w, d, 0.35, 3.9, wood)
	b.gable_roof(Transform3D.IDENTITY, w, d, 4.25, 2.9, 0.5, roof, wood, true)
	for x: float in [-w * 0.5, w * 0.5]:
		for z: float in [-d * 0.5, d * 0.5]:
			b.block(Vector3(x, 0.35, z), Vector3(0.22, 3.9, 0.22), WHITE)
	door(b, Vector3(0, 0.35, -d * 0.5), Vector3(0, 0, -1), 1.0, 2.1, WHITE, MB.shade(wood, 0.7))
	b.window(Vector3(-2.0, 2.2, -d * 0.5), Vector3(0, 0, -1), 0.9, 0.9, WHITE, r)
	b.panel(Vector3(0, 1.9, d * 0.5), Vector3(0, 0, 1), 4.6, 3.2, Color(0.08, 0.08, 0.09, MB.MATTE), 0.04)
	b.panel(Vector3(0, 3.6, d * 0.5 + 0.05), Vector3(0, 0, 1), 5.0, 0.3, WHITE, 0.06)
	for z: float in [-2.0, 2.0]:
		b.window(Vector3(-w * 0.5, 2.3, z), Vector3(-1, 0, 0), 1.0, 0.9, WHITE, r)
		b.window(Vector3(w * 0.5, 2.3, z), Vector3(1, 0, 0), 1.0, 0.9, WHITE, r)

static func _pier_section(b: MB, r: RandomNumberGenerator) -> void:
	var plank := Color(0.56, 0.44, 0.32, MB.MATTE)
	var post := Color(0.33, 0.27, 0.21, MB.MATTE)
	b.block(Vector3(0, 1.05, 0), Vector3(3.96, 0.14, 10.0), MB.shade(plank, 0.6))
	for i in 20:
		var z := -4.75 + i * 0.5
		b.block(Vector3(0, 1.18, z), Vector3(4.0, 0.12, 0.47), MB.shade(plank, r.randf_range(0.85, 1.1)))
	for x: float in [-1.6, 1.6]:
		b.block(Vector3(x, 0.88, 0), Vector3(0.25, 0.3, 10.0), post)
		for z: float in [-4.6, 0.0, 4.6]:
			b.cyl(Transform3D(Basis(), Vector3(x * 1.15, -6.0, z)), 0.17, 0.16, 7.3, 7, post, true)
	b.block(Vector3(-1.9, 1.3, 0), Vector3(0.2, 0.15, 10.0), MB.shade(plank, 0.8))
	b.block(Vector3(1.9, 1.3, 0), Vector3(0.2, 0.15, 10.0), MB.shade(plank, 0.8))
	for z: float in [-3.0, 3.0]:
		b.cyl(Transform3D(Basis(), Vector3(1.75, 1.3, z)), 0.14, 0.12, 0.45, 8, DARK_STEEL, true)

static func _boat_fishing(b: MB, r: RandomNumberGenerator) -> void:
	var zs := [-4.6, -3.6, -2.0, 0.0, 2.0, 3.8, 4.5]
	var hw := [0.05, 0.95, 1.42, 1.62, 1.56, 1.42, 1.32]
	var keel := [-0.2, -0.75, -1.0, -1.06, -1.0, -0.9, -0.7]
	var gun := [1.45, 1.2, 1.02, 0.96, 1.0, 1.06, 1.12]
	var hull := Color(0.98, 0.98, 0.97, MB.PAINT)
	var anti := Color(0.62, 0.16, 0.12, MB.MATTE)
	var deck := Color(0.6, 0.48, 0.34, MB.MATTE)
	var n := zs.size()
	for i in n - 1:
		var a := i
		var c := i + 1
		for s: float in [-1.0, 1.0]:
			var g0 := Vector3(s * float(hw[a]), float(gun[a]), float(zs[a]))
			var g1 := Vector3(s * float(hw[c]), float(gun[c]), float(zs[c]))
			var w0 := Vector3(s * float(hw[a]) * 0.92, 0.05, float(zs[a]))
			var w1 := Vector3(s * float(hw[c]) * 0.92, 0.05, float(zs[c]))
			var k0 := Vector3(0, float(keel[a]), float(zs[a]))
			var k1 := Vector3(0, float(keel[c]), float(zs[c]))
			var out := Vector3(s, 0.0, 0.0)
			if i == 0:
				out = Vector3(s * 0.5, 0, -1)
			b.quad(g0, g1, w1, w0, hull, out)
			b.quad(w0, w1, k1, k0, anti, out + Vector3(0, -0.6, 0))
			b.quad(g0 + Vector3(0, 0.12, 0), g1 + Vector3(0, 0.12, 0), g1, g0, Color(0.15, 0.32, 0.55, MB.PAINT), out)
		var d0l := Vector3(-float(hw[a]) * 0.95, float(gun[a]) - 0.25, float(zs[a]))
		var d0r := Vector3(float(hw[a]) * 0.95, float(gun[a]) - 0.25, float(zs[a]))
		var d1l := Vector3(-float(hw[c]) * 0.95, float(gun[c]) - 0.25, float(zs[c]))
		var d1r := Vector3(float(hw[c]) * 0.95, float(gun[c]) - 0.25, float(zs[c]))
		b.quad(d0l, d0r, d1r, d1l, deck, Vector3.UP)
	var zt := float(zs[n - 1])
	var hwt := float(hw[n - 1])
	b.quad(Vector3(-hwt, float(gun[n - 1]), zt), Vector3(hwt, float(gun[n - 1]), zt), Vector3(hwt * 0.92, 0.05, zt), Vector3(-hwt * 0.92, 0.05, zt), hull, Vector3(0, 0, 1))
	b.tri(Vector3(-hwt * 0.92, 0.05, zt), Vector3(hwt * 0.92, 0.05, zt), Vector3(0, float(keel[n - 1]), zt), anti, Vector3(0, 0, 1))
	# wheelhouse
	b.block(Vector3(0, 0.75, 1.0), Vector3(2.3, 2.0, 2.3), Color(0.96, 0.96, 0.94, MB.MATTE))
	b.block(Vector3(0, 1.6, 1.0), Vector3(2.34, 0.75, 2.34), Color(0.17, 0.24, 0.3, MB.GLASS))
	b.block(Vector3(0, 2.75, 1.0), Vector3(2.6, 0.14, 2.7), Color(0.15, 0.32, 0.55, MB.PAINT))
	b.cyl(Transform3D(Basis(), Vector3(0, 0.8, -1.2)), 0.08, 0.06, 5.6, 6, WHITE)
	b.beam(Vector3(0, 2.4, -1.2), Vector3(0, 3.6, -3.6), 0.07, WHITE)
	b.cyl(Transform3D(Basis(), Vector3(0, 2.9, 1.7)), 0.18, 0.18, 0.3, 8, Color(0.9, 0.9, 0.9, MB.MATTE))
	b.cyl(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.9, 1.4, 3.6)), 0.45, 0.45, 1.8, 10, Color(0.3, 0.55, 0.4, MB.MATTE), true, true)
	for z: float in [-1.5, 0.5, 2.5]:
		for s: float in [-1.0, 1.0]:
			b.blob(Vector3(s * 1.66, 0.55, z), Vector3(0.14, 0.3, 0.14), Color(0.92, 0.45, 0.1, MB.MATTE), r, 0.0, 0, 0.6, 0.1)

# ============================================================== landmarks

static func _lighthouse(b: MB, r: RandomNumberGenerator) -> void:
	var white := Color(0.96, 0.96, 0.94, MB.MATTE)
	var red := Color(0.82, 0.14, 0.12, MB.MATTE)
	b.cyl(Transform3D(Basis(), Vector3(0, -2.5, 0)), 4.4, 4.2, 3.2, 14, STONE, true)
	var y := 0.7
	var rad := 3.3
	for i in 5:
		var h := 4.0
		var r1 := rad - 0.22 * h * 0.25 * 4.0 / 4.0
		b.cyl(Transform3D(Basis(), Vector3(0, y, 0)), rad, r1, h, 14, white if i % 2 == 0 else red, false)
		y += h
		rad = r1
	for i in 3:
		var wy := 4.0 + i * 5.5
		b.window(Vector3(0, wy, -(3.3 - 0.055 * (wy - 0.7)) + 0.05), Vector3(0, 0, -1), 0.6, 1.0, white, r)
	b.cyl(Transform3D(Basis(), Vector3(0, y, 0)), rad + 1.0, rad + 1.0, 0.35, 14, DARK, true, true)
	for i in 18:
		var a := TAU * i / 18.0
		b.beam(Vector3(cos(a) * (rad + 0.9), y + 0.35, sin(a) * (rad + 0.9)), Vector3(cos(a) * (rad + 0.9), y + 1.3, sin(a) * (rad + 0.9)), 0.05, DARK)
	b.cyl(Transform3D(Basis(), Vector3(0, y + 1.25, 0)), rad + 0.92, rad + 0.92, 0.07, 14, DARK, true)
	b.cyl(Transform3D(Basis(), Vector3(0, y + 0.35, 0)), 1.7, 1.7, 2.8, 10, Color(0.2, 0.26, 0.3, MB.GLASS), false)
	b.cyl(Transform3D(Basis(), Vector3(0, y + 0.8, 0)), 0.65, 0.65, 1.6, 8, Color(1.0, 0.92, 0.7, MB.NIGHT_LIGHT), true)
	b.cyl(Transform3D(Basis(), Vector3(0, y + 3.15, 0)), 1.95, 0.0, 1.6, 10, red, false, true)
	b.cyl(Transform3D(Basis(), Vector3(0, y + 4.7, 0)), 0.12, 0.05, 0.9, 6, DARK)
	door(b, Vector3(0, 0.7, -3.3), Vector3(0, 0, -1), 1.1, 2.2, red, white)

static func _castle_ruin_wall(b: MB, r: RandomNumberGenerator) -> void:
	var stone := Color(0.6, 0.58, 0.53, MB.MATTE)
	b.block(Vector3(0, -2.5, 0), Vector3(12.4, 2.6, 2.6), MB.shade(stone, 0.9))
	var x := -6.0
	while x < 6.0:
		var wseg := r.randf_range(1.2, 2.2)
		wseg = minf(wseg, 6.0 - x)
		var h := r.randf_range(4.2, 7.0)
		if r.randf() < 0.18:
			h = r.randf_range(2.0, 3.2)
		b.block(Vector3(x + wseg * 0.5, 0.0, r.randf_range(-0.06, 0.06)), Vector3(wseg + 0.02, h, 2.2), MB.shade(stone, r.randf_range(0.9, 1.06)), 0.0, MB.shade(stone, 0.85))
		if h > 5.0 and r.randf() < 0.5:
			b.block(Vector3(x + wseg * 0.5, h, -0.6), Vector3(wseg * 0.5, 0.8, 0.8), MB.shade(stone, 0.95))
		x += wseg
	for i in 4:
		var p := Vector3(r.randf_range(-5.5, 5.5), r.randf_range(1.0, 4.0), -1.12)
		b.panel(p, Vector3(0, 0, -1), 0.25, 0.9, DARK, 0.03)
	for i in 6:
		b.blob(Vector3(r.randf_range(-6, 6), 0.2, r.randf_range(-2.4, -1.4) * (1.0 if r.randf() < 0.5 else -1.0)), Vector3(0.6, 0.4, 0.5), MB.shade(stone, 0.9), r, 0.3, 0, 0.0, 0.2, -0.5)

static func _castle_ruin_tower(b: MB, r: RandomNumberGenerator) -> void:
	var stone := Color(0.58, 0.56, 0.51, MB.MATTE)
	b.cyl(Transform3D(Basis(), Vector3(0, -3.0, 0)), 4.6, 4.4, 3.6, 12, MB.shade(stone, 0.9), true)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.5, 0)), 3.2, 3.2, 0.2, 12, Color(0.3, 0.28, 0.26, MB.MATTE), true)
	var segs := 12
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		var h := r.randf_range(10.0, 15.0)
		if i % 5 == 2:
			h = r.randf_range(6.0, 8.0)
		var c := Vector3(cos(a) * 3.6, 0.0, sin(a) * 3.6)
		var basis := Basis(Vector3.UP, -a + PI * 0.5)
		b.box(Transform3D(basis, c + Vector3(0, h * 0.5, 0)), Vector3(TAU * 3.6 / segs + 0.12, h, 1.4), MB.shade(stone, r.randf_range(0.9, 1.05)), MB.shade(stone, 0.8))
		if h > 9.0:
			b.panel(c * 1.2 + Vector3(0, h * 0.55, 0), Vector3(cos(a), 0, sin(a)), 0.25, 1.1, DARK, 0.03)
	for i in 8:
		var a := r.randf() * TAU
		b.blob(Vector3(cos(a) * 5.0, 0.2, sin(a) * 5.0), Vector3(0.7, 0.45, 0.6), MB.shade(stone, 0.9), r, 0.3, 0, 0.0, 0.2, -0.5)

static func _wind_turbine_tower(b: MB, r: RandomNumberGenerator) -> void:
	var white := Color(0.94, 0.95, 0.96, MB.MATTE)
	b.cyl(Transform3D(Basis(), Vector3(0, -1.5, 0)), 3.4, 3.4, 2.0, 16, Color(0.66, 0.65, 0.62, MB.MATTE), true)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.5, 0)), 2.0, 1.25, 59.0, 14, white, false)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.5, 0)), 2.04, 1.95, 3.0, 14, Color(0.3, 0.55, 0.45, MB.MATTE), false)
	b.panel(Vector3(0, 1.6, -2.02), Vector3(0, 0, -1), 0.9, 2.0, DARK_STEEL, 0.06)
	b.box(Transform3D(Basis(), Vector3(0, 61.0, 1.0)), Vector3(3.0, 3.0, 8.0), white)
	b.cyl(Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 61.0, -3.0)), 1.45, 1.4, 0.2, 12, white, true)
	b.block(Vector3(0, 62.5, 4.0), Vector3(0.6, 0.6, 0.6), Color(0.85, 0.15, 0.1, MB.NIGHT_LIGHT))

static func _wind_turbine_rotor(b: MB, r: RandomNumberGenerator) -> void:
	var white := Color(0.95, 0.96, 0.97, MB.MATTE)
	b.cyl(Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0, 0.6)), 1.35, 0.25, 2.6, 12, white, false, true)
	for k in 3:
		var rot := Basis(Vector3(0, 0, 1), TAU * k / 3.0)
		var prev_l := Vector3.ZERO
		var prev_t := Vector3.ZERO
		var steps := 6
		for s in steps + 1:
			var t := float(s) / steps
			var rr := lerpf(1.0, 27.0, t)
			var chord := lerpf(2.3, 0.45, pow(t, 0.8))
			var twist := lerpf(0.5, 0.08, t)
			var lead := rot * (Vector3(0, rr, 0) + Vector3(cos(twist), 0, sin(twist)) * chord * 0.35)
			var trail := rot * (Vector3(0, rr, 0) - Vector3(cos(twist), 0, sin(twist)) * chord * 0.65)
			if s > 0:
				var col := white if t < 0.92 else Color(0.85, 0.18, 0.12, MB.MATTE)
				var nrm := rot * Vector3(-sin(twist), 0, cos(twist))
				b.quad2(prev_l, lead, trail, prev_t, col, MB.shade(col, 0.92), -nrm, 0.08 * (1.0 - t) + 0.02)
			prev_l = lead
			prev_t = trail

static func _water_tower(b: MB, r: RandomNumberGenerator) -> void:
	var leg := Color(0.52, 0.54, 0.56, MB.METAL)
	var tank := Color(0.9, 0.92, 0.93, MB.PAINT)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		b.beam(Vector3(s.x * 2.7, -1.0, s.y * 2.7), Vector3(s.x * 1.9, 13.2, s.y * 1.9), 0.3, leg)
		b.block(Vector3(s.x * 2.7, -0.6, s.y * 2.7), Vector3(0.8, 0.8, 0.8), STONE)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for lvl in 2:
		var y0 := 1.5 + lvl * 5.5
		var y1 := y0 + 5.0
		var k0 := lerpf(2.7, 1.9, (y0 + 1.0) / 14.2)
		var k1 := lerpf(2.7, 1.9, (y1 + 1.0) / 14.2)
		for i in 4:
			var a: Vector2 = corners[i]
			var c: Vector2 = corners[(i + 1) % 4]
			b.beam(Vector3(a.x * k0, y0, a.y * k0), Vector3(c.x * k1, y1, c.y * k1), 0.1, leg)
			b.beam(Vector3(c.x * k0, y0, c.y * k0), Vector3(a.x * k1, y1, a.y * k1), 0.1, leg)
			b.beam(Vector3(a.x * k1, y1, a.y * k1), Vector3(c.x * k1, y1, c.y * k1), 0.14, leg)
	b.cyl(Transform3D(Basis(), Vector3(0, 13.0, 0)), 3.7, 3.7, 0.18, 16, DARK_STEEL, true, true)
	b.cyl(Transform3D(Basis(), Vector3(0, 13.2, 0)), 3.2, 3.2, 4.6, 16, tank, false, true)
	b.cyl(Transform3D(Basis(), Vector3(0, 15.0, 0)), 3.23, 3.23, 0.6, 16, Color(0.2, 0.45, 0.62, MB.PAINT), false)
	b.cyl(Transform3D(Basis(), Vector3(0, 17.8, 0)), 3.45, 0.0, 1.7, 16, Color(0.42, 0.45, 0.48, MB.METAL), false, true)
	b.blob(Vector3(0, 19.6, 0), Vector3(0.22, 0.22, 0.22), DARK_STEEL, r, 0.0, 0)
	for i in 9:
		var a := TAU * i / 9.0
		b.beam(Vector3(cos(a) * 3.65, 13.15, sin(a) * 3.65), Vector3(cos(a) * 3.65, 14.1, sin(a) * 3.65), 0.05, DARK_STEEL)

static func _festival_stage(b: MB, r: RandomNumberGenerator) -> void:
	var deck := Color(0.17, 0.17, 0.2, MB.MATTE)
	var truss := Color(0.75, 0.77, 0.8, MB.METAL)
	b.block(Vector3(0, -1.5, 0), Vector3(20.0, 3.1, 12.0), deck)
	b.block(Vector3(0, 1.55, -6.1), Vector3(20.2, 0.12, 0.3), Color(1.0, 0.55, 0.1, MB.LIGHT))
	for i in 4:
		b.block(Vector3(-7.5, 0.0 + i * 0.38, -6.4 - (3 - i) * 0.4), Vector3(3.0, 0.38, 0.4), deck)
	var towers := [Vector3(-9.6, 1.6, -5.6), Vector3(9.6, 1.6, -5.6), Vector3(-9.6, 1.6, 5.6), Vector3(9.6, 1.6, 5.6)]
	for t: Vector3 in towers:
		for o: Vector2 in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)]:
			b.beam(t + Vector3(o.x, 0, o.y), t + Vector3(o.x, 10.0, o.y), 0.08, truss)
		for k in 10:
			b.beam(t + Vector3(-0.3, k * 1.0, -0.3), t + Vector3(0.3, k * 1.0 + 1.0, 0.3), 0.05, truss)
	for z: float in [-5.6, 5.6]:
		b.beam(Vector3(-9.9, 11.4, z), Vector3(9.9, 11.4, z), 0.5, truss)
	for x: float in [-9.6, 0.0, 9.6]:
		b.beam(Vector3(x, 11.4, -5.9), Vector3(x, 11.4, 5.9), 0.5, truss)
	b.box(Transform3D(Basis(Vector3(1, 0, 0), 0.08), Vector3(0, 12.2, 0)), Vector3(21.0, 0.25, 13.5), Color(0.12, 0.12, 0.14, MB.MATTE))
	# LED wall with a sunset gradient
	var top := Color(0.45, 0.2, 0.75, MB.LIGHT)
	var mid := Color(1.0, 0.35, 0.45, MB.LIGHT)
	var bot := Color(1.0, 0.68, 0.18, MB.LIGHT)
	var zw := 5.2
	var x0 := -8.0
	var x1 := 8.0
	var n := Vector3(0, 0, -1)
	b.block(Vector3(0, 1.6, zw + 0.3), Vector3(16.6, 8.8, 0.4), DARK)
	b.tri_vc(Vector3(x0, 2.0, zw), Vector3(x1, 2.0, zw), Vector3(x1, 6.0, zw), bot, bot, mid, n)
	b.tri_vc(Vector3(x0, 2.0, zw), Vector3(x1, 6.0, zw), Vector3(x0, 6.0, zw), bot, mid, mid, n)
	b.tri_vc(Vector3(x0, 6.0, zw), Vector3(x1, 6.0, zw), Vector3(x1, 10.0, zw), mid, mid, top, n)
	b.tri_vc(Vector3(x0, 6.0, zw), Vector3(x1, 10.0, zw), Vector3(x0, 10.0, zw), mid, top, top, n)
	for i in 12:
		var a0 := PI * i / 12.0
		var a1 := PI * (i + 1) / 12.0
		var c := Vector3(0, 4.4, zw - 0.02)
		b.tri(c, c + Vector3(cos(a0) * 2.6, sin(a0) * 2.6, 0), c + Vector3(cos(a1) * 2.6, sin(a1) * 2.6, 0), Color(1.0, 0.92, 0.55, MB.LIGHT), n)
	for i in 4:
		b.panel(Vector3(0, 3.0 - i * 0.35 + 0.0, zw - 0.03), n, 10.0 - i * 1.5, 0.12, Color(0.35, 0.1, 0.4, MB.LIGHT), 0.01)
	# speakers + light bar
	for s: float in [-1.0, 1.0]:
		b.block(Vector3(s * 11.2, -0.2, -4.0), Vector3(1.6, 4.4, 1.6), DARK)
		b.block(Vector3(s * 11.2, 4.2, -4.0), Vector3(1.4, 1.6, 1.4), DARK)
		for k in 3:
			b.panel(Vector3(s * 11.2, 0.6 + k * 1.3, -4.8), Vector3(0, 0, -1), 0.9, 0.9, Color(0.22, 0.22, 0.24, MB.MATTE), 0.03)
	var cols := [Color(1, 0.3, 0.3, MB.LIGHT), Color(1, 0.8, 0.2, MB.LIGHT), Color(0.3, 1, 0.5, MB.LIGHT), Color(0.3, 0.6, 1, MB.LIGHT), Color(0.9, 0.3, 1, MB.LIGHT)]
	for i in 10:
		var x := -8.1 + i * 1.8
		b.block(Vector3(x, 10.6, -5.7), Vector3(0.5, 0.6, 0.5), DARK)
		b.panel(Vector3(x, 10.9, -5.97), Vector3(0, 0, -1), 0.36, 0.36, cols[i % 5], 0.02)
	# side banners (cloth, tinted per instance)
	for s: float in [-1.0, 1.0]:
		b.quad2(Vector3(s * 9.2, 9.5, -5.2), Vector3(s * 9.2, 9.5, -1.0), Vector3(s * 9.2, 3.0, -1.0), Vector3(s * 9.2, 3.0, -5.2), Color(0.98, 0.98, 0.98, MB.TINT), Color(0.98, 0.98, 0.98, MB.TINT), Vector3(-s, 0, 0))

static func _festival_tent(b: MB, r: RandomNumberGenerator) -> void:
	var white := Color(0.98, 0.97, 0.94, MB.MATTE)
	var tint := Color(0.98, 0.98, 0.98, MB.TINT)
	var post := Color(0.85, 0.86, 0.88, MB.METAL)
	var h := 2.6
	var apex := Vector3(0, 5.3, 0)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		b.block(Vector3(s.x * 3.9, -0.3, s.y * 3.9), Vector3(0.12, h + 0.3, 0.12), post)
	var corners := [Vector3(-4, h, -4), Vector3(4, h, -4), Vector3(4, h, 4), Vector3(-4, h, 4)]
	for i in 4:
		var a: Vector3 = corners[i]
		var c: Vector3 = corners[(i + 1) % 4]
		var out := ((a + c) * 0.5 - Vector3(0, h, 0)).normalized() + Vector3(0, 1.2, 0)
		for k in 4:
			var p0 := a.lerp(c, k / 4.0)
			var p1 := a.lerp(c, (k + 1) / 4.0)
			var col := tint if k % 2 == 0 else white
			b.tri(p0, p1, apex, col, out)
			b.tri(p0 - Vector3(0, 0.02, 0), p1 - Vector3(0, 0.02, 0), apex - Vector3(0, 0.02, 0), MB.shade(white, 0.8), -out)
		# valance
		for k in 8:
			var p0 := a.lerp(c, k / 8.0)
			var p1 := a.lerp(c, (k + 1) / 8.0)
			var vn := ((a + c) * 0.5 - Vector3(0, h, 0)).normalized()
			b.quad2(p0, p1, p1 - Vector3(0, 0.45, 0), p0 - Vector3(0, 0.45, 0), tint if k % 2 == 1 else white, white, vn)
	b.cyl(Transform3D(Basis(), apex), 0.05, 0.04, 1.2, 5, post)
	b.set_wave(1.0, apex.x + 0.05, 0.85)
	b.quad2(apex + Vector3(0.05, 1.15, 0), apex + Vector3(0.9, 1.1, 0), apex + Vector3(0.9, 0.65, 0), apex + Vector3(0.05, 0.7, 0), tint, tint, Vector3(0, 0, -1))
	b.set_wave(0.0)
	# counter
	b.block(Vector3(0, 0.0, -3.4), Vector3(5.0, 1.05, 0.7), white, 0.0, Color(0.5, 0.36, 0.24, MB.MATTE))

static func _viewpoint_deck(b: MB, r: RandomNumberGenerator) -> void:
	var plank := Color(0.56, 0.42, 0.29, MB.MATTE)
	var post := Color(0.36, 0.27, 0.19, MB.MATTE)
	b.block(Vector3(0, 0.2, 0), Vector3(8.9, 0.12, 5.96), MB.shade(plank, 0.6))
	for i in 15:
		var x := -4.2 + i * 0.6
		b.block(Vector3(x, 0.3, 0), Vector3(0.56, 0.14, 6.0), MB.shade(plank, r.randf_range(0.88, 1.08)))
	for x: float in [-4.2, 0.0, 4.2]:
		for z: float in [-2.8, 0.0, 2.8]:
			b.block(Vector3(x, -7.0, z), Vector3(0.28, 7.3, 0.28), post)
		b.beam(Vector3(x, -3.5, -2.8), Vector3(x, 0.2, 2.8), 0.14, post)
	for edge: Array in [[Vector3(-4.4, 0, -3.0), Vector3(4.4, 0, -3.0)], [Vector3(-4.4, 0, -3.0), Vector3(-4.4, 0, 2.9)], [Vector3(4.4, 0, -3.0), Vector3(4.4, 0, 2.9)]]:
		var a: Vector3 = edge[0]
		var c: Vector3 = edge[1]
		var l := a.distance_to(c)
		var cnt := int(l / 1.4)
		for k in cnt + 1:
			var p := a.lerp(c, float(k) / cnt)
			b.block(p + Vector3(0, 0.37, 0), Vector3(0.12, 1.05, 0.12), post)
		b.beam(a + Vector3(0, 1.38, 0), c + Vector3(0, 1.38, 0), 0.12, plank)
		b.beam(a + Vector3(0, 0.9, 0), c + Vector3(0, 0.9, 0), 0.06, plank)
	# coin binoculars
	b.cyl(Transform3D(Basis(), Vector3(1.6, 0.37, -2.4)), 0.07, 0.07, 1.0, 6, DARK_STEEL)
	b.box(Transform3D(Basis(Vector3(1, 0, 0), 0.25), Vector3(1.6, 1.5, -2.45)), Vector3(0.5, 0.3, 0.42), Color(0.2, 0.45, 0.35, MB.PAINT))
	# info board
	b.block(Vector3(-3.0, 0.37, 2.5), Vector3(0.1, 1.0, 0.1), post)
	b.block(Vector3(-2.2, 0.37, 2.5), Vector3(0.1, 1.0, 0.1), post)
	b.box(Transform3D(Basis(Vector3(1, 0, 0), -0.6), Vector3(-2.6, 1.45, 2.4)), Vector3(1.2, 0.8, 0.06), Color(0.15, 0.35, 0.3, MB.PAINT))

# ============================================================== roadside

static func _sign_speedlimit(b: MB, r: RandomNumberGenerator) -> void:
	b.cyl(Transform3D(Basis(), Vector3(0, -0.5, 0)), 0.04, 0.04, 2.9, 6, STEEL)
	var xf := Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 2.1, 0.03))
	b.cyl(xf, 0.42, 0.42, 0.03, 18, Color(0.85, 0.08, 0.08, MB.PAINT), true, true, Color(0.85, 0.08, 0.08, MB.PAINT))
	b.cyl(Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 2.1, -0.005)), 0.33, 0.33, 0.01, 18, Color(0.97, 0.97, 0.95, MB.MATTE), true)
	b.panel(Vector3(-0.1, 2.1, -0.02), Vector3(0, 0, -1), 0.1, 0.3, DARK, 0.01)
	b.panel(Vector3(0.1, 2.1, -0.02), Vector3(0, 0, -1), 0.14, 0.3, DARK, 0.01)

static func _sign_chevron(b: MB, r: RandomNumberGenerator) -> void:
	b.cyl(Transform3D(Basis(), Vector3(0, -0.5, 0)), 0.04, 0.04, 2.5, 6, STEEL)
	b.box(Transform3D(Basis(), Vector3(0, 1.6, 0.03)), Vector3(0.9, 0.7, 0.04), Color(0.98, 0.78, 0.05, MB.PAINT))
	for k in 2:
		var x := -0.18 + k * 0.32
		var p := Vector3(x, 1.6, -0.0)
		b.quad(p + Vector3(-0.06, 0.25, 0), p + Vector3(0.06, 0.25, 0), p + Vector3(0.2, 0, 0), p + Vector3(0.08, 0, 0), DARK, Vector3(0, 0, -1))
		b.quad(p + Vector3(0.08, 0, 0), p + Vector3(0.2, 0, 0), p + Vector3(0.06, -0.25, 0), p + Vector3(-0.06, -0.25, 0), DARK, Vector3(0, 0, -1))

static func _sign_danger_jump(b: MB, r: RandomNumberGenerator) -> void:
	b.cyl(Transform3D(Basis(), Vector3(0, -0.5, 0)), 0.04, 0.04, 2.9, 6, STEEL)
	var c := Vector3(0, 2.15, 0)
	var red := Color(0.85, 0.08, 0.08, MB.PAINT)
	var p := [c + Vector3(-0.5, -0.36, 0), c + Vector3(0.5, -0.36, 0), c + Vector3(0, 0.5, 0)]
	var q := [c + Vector3(-0.38, -0.29, -0.01), c + Vector3(0.38, -0.29, -0.01), c + Vector3(0, 0.37, -0.01)]
	b.tri(p[0], p[1], p[2], red, Vector3(0, 0, -1))
	b.tri(p[0] + Vector3(0, 0, 0.03), p[1] + Vector3(0, 0, 0.03), p[2] + Vector3(0, 0, 0.03), Color(0.6, 0.6, 0.6, MB.METAL), Vector3(0, 0, 1))
	b.tri(q[0], q[1], q[2], Color(0.97, 0.97, 0.95, MB.MATTE), Vector3(0, 0, -1))
	for i in 6:
		var a0 := PI * i / 6.0
		var a1 := PI * (i + 1) / 6.0
		var o := c + Vector3(0, -0.2, -0.02)
		b.tri(o, o + Vector3(cos(a0) * 0.22, sin(a0) * 0.14, 0), o + Vector3(cos(a1) * 0.22, sin(a1) * 0.14, 0), DARK, Vector3(0, 0, -1))
	b.panel(c + Vector3(0.06, 0.03, -0.02), Vector3(0, 0, -1), 0.28, 0.1, DARK, 0.005)

static func _sign_direction(b: MB, r: RandomNumberGenerator) -> void:
	for x: float in [-0.9, 0.9]:
		b.cyl(Transform3D(Basis(), Vector3(x, -0.5, 0.05)), 0.05, 0.05, 3.4, 6, STEEL)
	var green := Color(0.05, 0.38, 0.22, MB.PAINT)
	b.box(Transform3D(Basis(), Vector3(0, 2.2, 0)), Vector3(2.5, 1.3, 0.05), green)
	b.panel(Vector3(0, 2.2, -0.03), Vector3(0, 0, -1), 2.36, 1.16, Color(0.95, 0.95, 0.95, MB.MATTE), 0.01)
	b.panel(Vector3(0, 2.2, -0.04), Vector3(0, 0, -1), 2.26, 1.06, green, 0.01)
	for i in 2:
		var y := 2.45 - i * 0.5
		b.panel(Vector3(-0.35, y, -0.05), Vector3(0, 0, -1), 1.2, 0.14, Color(0.95, 0.95, 0.95, MB.MATTE), 0.005)
		var tip := Vector3(0.9 if i == 0 else -0.9, y, -0.06)
		var dir := 1.0 if i == 0 else -1.0
		b.tri(tip + Vector3(dir * 0.2, 0, 0), tip + Vector3(0, 0.15, 0), tip + Vector3(0, -0.15, 0), Color(0.95, 0.95, 0.95, MB.MATTE), Vector3(0, 0, -1))
		b.panel(tip + Vector3(-dir * 0.15, 0, 0.005), Vector3(0, 0, -1), 0.3, 0.07, Color(0.95, 0.95, 0.95, MB.MATTE), 0.005)

static func _delineator_post(b: MB, r: RandomNumberGenerator) -> void:
	b.block(Vector3(0, -0.3, 0), Vector3(0.12, 1.4, 0.12), Color(0.94, 0.94, 0.92, MB.MATTE))
	b.block(Vector3(0, 0.82, 0), Vector3(0.13, 0.18, 0.13), DARK)
	b.panel(Vector3(0, 0.95, -0.065), Vector3(0, 0, -1), 0.06, 0.1, Color(1.0, 0.6, 0.1, MB.PAINT), 0.01)

static func _guardrail_post(b: MB, r: RandomNumberGenerator) -> void:
	b.block(Vector3(0, -0.4, 0), Vector3(0.1, 1.2, 0.16), STEEL)
	b.block(Vector3(0, 0.45, -0.12), Vector3(0.12, 0.35, 0.1), STEEL)

static func _lamp_street(b: MB, r: RandomNumberGenerator) -> void:
	var pole := Color(0.3, 0.32, 0.34, MB.METAL)
	b.cyl(Transform3D(Basis(), Vector3(0, -0.5, 0)), 0.17, 0.15, 0.9, 8, pole, true)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.4, 0)), 0.1, 0.07, 5.9, 8, pole, true)
	var prev := Vector3(0, 6.0, 0)
	for i in 5:
		var t := float(i + 1) / 5.0
		var p := Vector3(0, 6.0 + sin(t * PI * 0.5) * 0.35, -1.7 * t)
		b.cyl_between(prev, p, 0.055, 0.05, 6, pole, i == 4)
		prev = p
	b.box(Transform3D(Basis(), Vector3(0, 6.3, -1.75)), Vector3(0.36, 0.14, 0.7), pole)
	b.quad(Vector3(-0.15, 6.22, -2.05), Vector3(0.15, 6.22, -2.05), Vector3(0.15, 6.22, -1.45), Vector3(-0.15, 6.22, -1.45), LAMP, Vector3.DOWN)

static func _utility_pole(b: MB, r: RandomNumberGenerator) -> void:
	var wood := Color(0.4, 0.31, 0.22, MB.MATTE)
	b.cyl(Transform3D(Basis(), Vector3(0, -1.0, 0)), 0.16, 0.12, 10.6, 7, wood, true)
	b.block(Vector3(0, 8.7, 0), Vector3(2.4, 0.13, 0.13), wood)
	for x: float in [-1.0, 0.0, 1.0]:
		b.cyl(Transform3D(Basis(), Vector3(x, 8.83, 0)), 0.06, 0.05, 0.25, 6, Color(0.85, 0.88, 0.9, MB.PAINT), true)
	b.beam(Vector3(-0.8, 8.7, 0), Vector3(0, 8.0, 0), 0.06, wood)
	b.beam(Vector3(0.8, 8.7, 0), Vector3(0, 8.0, 0), 0.06, wood)

static func _fence_wood(b: MB, r: RandomNumberGenerator) -> void:
	var wood := Color(0.56, 0.44, 0.31, MB.MATTE)
	for x: float in [-2.0, 2.0]:
		b.block(Vector3(x, -0.4, 0), Vector3(0.13, 1.72, 0.13), MB.shade(wood, 0.9))
	for y: float in [0.55, 1.0]:
		b.block(Vector3(0, y, 0.0), Vector3(4.1, 0.11, 0.05), wood)
	b.beam(Vector3(-1.95, 0.25, 0.04), Vector3(1.95, 1.1, 0.04), 0.07, MB.shade(wood, 0.95), Vector3(0, 0, 1))

static func _wall_stone(b: MB, r: RandomNumberGenerator) -> void:
	var stone := Color(0.6, 0.57, 0.5, MB.MATTE)
	b.block(Vector3(0, -0.4, 0), Vector3(4.0, 1.3, 0.75), stone, 0.0, MB.shade(stone, 0.9))
	for i in 8:
		b.blob(Vector3(-1.75 + i * 0.5, 0.98, 0), Vector3(0.3, 0.14, 0.36), MB.shade(stone, r.randf_range(0.85, 1.05)), r, 0.25, 0, 0.0, 0.15)

static func _bus_stop(b: MB, r: RandomNumberGenerator) -> void:
	var frame := Color(0.12, 0.35, 0.3, MB.PAINT)
	var gl := Color(0.42, 0.52, 0.58, MB.GLASS)
	b.block(Vector3(0, -0.1, 0), Vector3(4.2, 0.2, 2.0), Color(0.68, 0.67, 0.64, MB.MATTE))
	for x: float in [-1.8, 1.8]:
		for z: float in [-0.7, 0.7]:
			b.block(Vector3(x, 0.1, z), Vector3(0.09, 2.4, 0.09), frame)
	b.box(Transform3D(Basis(Vector3(1, 0, 0), -0.08), Vector3(0, 2.58, 0)), Vector3(4.1, 0.12, 1.9), frame)
	b.box(Transform3D(Basis(), Vector3(0, 1.35, 0.7)), Vector3(3.6, 2.1, 0.03), gl)
	for x: float in [-1.8, 1.8]:
		b.box(Transform3D(Basis(), Vector3(x, 1.35, 0.1)), Vector3(0.03, 2.1, 1.2), gl)
	b.block(Vector3(0, 0.45, 0.4), Vector3(2.6, 0.08, 0.4), WOOD)
	for x: float in [-1.1, 1.1]:
		b.block(Vector3(x, 0.1, 0.4), Vector3(0.08, 0.35, 0.3), DARK_STEEL)
	b.cyl(Transform3D(Basis(), Vector3(2.5, -0.3, -0.6)), 0.04, 0.04, 3.0, 6, STEEL)
	b.cyl(Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(2.5, 2.45, -0.62)), 0.28, 0.28, 0.04, 14, Color(0.95, 0.75, 0.1, MB.PAINT), true, true)
	b.panel(Vector3(2.5, 2.45, -0.65), Vector3(0, 0, -1), 0.28, 0.18, frame, 0.01)

static func _bench(b: MB, r: RandomNumberGenerator) -> void:
	for i in 3:
		b.block(Vector3(0, 0.44, -0.18 + i * 0.15), Vector3(1.8, 0.05, 0.12), WOOD)
	for i in 2:
		b.box(Transform3D(Basis(Vector3(1, 0, 0), -0.2), Vector3(0, 0.72 + i * 0.17, 0.28 + i * 0.035)), Vector3(1.8, 0.12, 0.04), WOOD)
	for x: float in [-0.75, 0.75]:
		b.block(Vector3(x, -0.1, 0), Vector3(0.06, 0.55, 0.5), DARK_STEEL)
		b.beam(Vector3(x, 0.44, 0.22), Vector3(x, 1.0, 0.33), 0.05, DARK_STEEL)

static func _mailbox(b: MB, r: RandomNumberGenerator) -> void:
	b.block(Vector3(0, -0.3, 0), Vector3(0.1, 1.35, 0.1), WOOD)
	b.block(Vector3(0, 1.05, 0), Vector3(0.28, 0.24, 0.5), Color(0.75, 0.12, 0.1, MB.PAINT))
	b.cyl(Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 1.29, -0.25)), 0.14, 0.14, 0.5, 8, Color(0.75, 0.12, 0.1, MB.PAINT), true, true)
	b.block(Vector3(0.16, 1.2, 0.1), Vector3(0.03, 0.25, 0.06), Color(0.95, 0.8, 0.2, MB.PAINT))

static func _bin(b: MB, r: RandomNumberGenerator) -> void:
	var g := Color(0.15, 0.32, 0.22, MB.PAINT)
	b.cyl(Transform3D(Basis(), Vector3(0, -0.1, 0)), 0.3, 0.33, 0.95, 10, g, true)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.85, 0)), 0.35, 0.3, 0.1, 10, DARK_STEEL, true)

static func _barrier_jersey(b: MB, r: RandomNumberGenerator) -> void:
	var conc := Color(0.72, 0.71, 0.68, MB.MATTE)
	var prof := PackedVector2Array([Vector2(-0.3, -0.05), Vector2(0.3, -0.05), Vector2(0.3, 0.08), Vector2(0.16, 0.3), Vector2(0.09, 0.81), Vector2(-0.09, 0.81), Vector2(-0.16, 0.3), Vector2(-0.3, 0.08)])
	prism(b, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), prof, -1.5, 1.5, conc, MB.shade(conc, 0.9))
	b.panel(Vector3(0, 0.6, -0.12), Vector3(0, 0, -1), 2.6, 0.12, Color(0.95, 0.35, 0.1, MB.PAINT), 0.01)

static func _cone(b: MB, r: RandomNumberGenerator) -> void:
	var orange := Color(1.0, 0.42, 0.05, MB.PAINT)
	b.block(Vector3(0, 0, 0), Vector3(0.42, 0.04, 0.42), Color(0.1, 0.1, 0.1, MB.MATTE))
	b.cyl(Transform3D(Basis(), Vector3(0, 0.04, 0)), 0.16, 0.12, 0.2, 10, orange, false)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.24, 0)), 0.12, 0.085, 0.16, 10, Color(0.95, 0.95, 0.95, MB.PAINT), false)
	b.cyl(Transform3D(Basis(), Vector3(0, 0.4, 0)), 0.085, 0.02, 0.32, 10, orange, true)

static func _bridge_pier(b: MB, r: RandomNumberGenerator) -> void:
	var conc := Color(0.66, 0.64, 0.6, MB.MATTE)
	b.block(Vector3(0, -2.0, 0), Vector3(3.4, 2.0, 3.4), MB.shade(conc, 0.9))
	b.block(Vector3(0, 0, 0), Vector3(2.0, 11.2, 2.0), conc)
	b.block(Vector3(0, 11.2, 0), Vector3(4.0, 0.9, 2.6), MB.shade(conc, 0.95))

static func _tunnel_portal(b: MB, r: RandomNumberGenerator) -> void:
	var conc := Color(0.7, 0.68, 0.64, MB.MATTE)
	b.block(Vector3(-7.4, -1.0, 0), Vector3(3.2, 10.0, 1.6), conc)
	b.block(Vector3(7.4, -1.0, 0), Vector3(3.2, 10.0, 1.6), conc)
	b.block(Vector3(0, 7.0, 0), Vector3(18.0, 2.4, 1.6), conc)
	b.block(Vector3(0, 9.4, 0), Vector3(24.0, 2.6, 1.2), MB.shade(conc, 0.9))
	b.block(Vector3(0, 6.6, -0.82), Vector3(11.6, 0.3, 0.05), Color(0.95, 0.75, 0.1, MB.PAINT))

static func _speed_trap_camera(b: MB, r: RandomNumberGenerator) -> void:
	var yellow := Color(0.98, 0.78, 0.08, MB.PAINT)
	b.cyl(Transform3D(Basis(), Vector3(0, -0.6, 0)), 0.12, 0.1, 4.8, 8, Color(0.55, 0.57, 0.6, MB.METAL), true)
	b.block(Vector3(0, 3.6, 0), Vector3(0.55, 0.65, 0.9), yellow)
	b.panel(Vector3(0, 3.95, -0.46), Vector3(0, 0, -1), 0.3, 0.3, Color(0.06, 0.08, 0.1, MB.GLASS), 0.03)
	b.panel(Vector3(0, 3.75, -0.46), Vector3(0, 0, -1), 0.4, 0.12, Color(1.0, 1.0, 0.95, MB.LIGHT), 0.03)
	for i in 4:
		b.panel(Vector3(0, 3.62 + i * 0.12, 0.46), Vector3(0, 0, 1), 0.5, 0.05, DARK, 0.01)

static func _checkpoint_arch(b: MB, r: RandomNumberGenerator) -> void:
	var a := Color(1.0, 0.55, 0.1, MB.PAINT)
	var c := Color(0.92, 0.2, 0.55, MB.PAINT)
	var segs := 22
	var ring := 8
	var rx := 9.0
	var ry := 7.6
	var tube := 0.85
	var prev: Array[Vector3] = []
	for i in segs + 1:
		var t := PI * float(i) / segs
		var cpos := Vector3(cos(t) * rx, sin(t) * ry, 0)
		var tang := Vector3(-sin(t) * rx, cos(t) * ry, 0).normalized()
		var nrm := Vector3(0, 0, 1).cross(tang).normalized()
		var pts: Array[Vector3] = []
		for k in ring:
			var ang := TAU * k / ring
			pts.append(cpos + (nrm * cos(ang) + Vector3(0, 0, 1) * sin(ang)) * tube)
		if i > 0:
			var col := a if int(i * 0.5) % 2 == 0 else c
			for k in ring:
				var k1 := (k + 1) % ring
				var mid := (prev[k] + pts[k1]) * 0.5
				var cen := Vector3(cos(t) * rx, sin(t) * ry, 0)
				b.quad(prev[k], prev[k1], pts[k1], pts[k], col, mid - cen)
		prev = pts
	for s: float in [-1.0, 1.0]:
		b.block(Vector3(s * rx, -0.2, 0), Vector3(1.9, 0.8, 1.9), Color(0.15, 0.15, 0.17, MB.MATTE))
	var top := Vector3(0, ry + 0.2, 0)
	b.box(Transform3D(Basis(), top + Vector3(0, 0.9, 0)), Vector3(7.5, 1.7, 0.4), Color(0.98, 0.98, 0.96, MB.PAINT))
	for face: float in [-1.0, 1.0]:
		var n := Vector3(0, 0, face)
		b.panel(top + Vector3(0, 1.35, face * 0.2), n, 7.1, 0.25, Color(0.1, 0.72, 0.78, MB.LIGHT), 0.02)
		b.panel(top + Vector3(0, 0.45, face * 0.2), n, 7.1, 0.25, Color(1.0, 0.82, 0.2, MB.LIGHT), 0.02)
		for i in 7:
			b.panel(top + Vector3(-3.0 + i, 0.9, face * 0.2), n, 0.5, 0.5, a if i % 2 == 0 else c, 0.02)

static func _festival_banner(b: MB, r: RandomNumberGenerator) -> void:
	var pole := Color(0.92, 0.93, 0.95, MB.METAL)
	for x: float in [-3.1, 3.1]:
		b.cyl(Transform3D(Basis(), Vector3(x, -0.5, 0)), 0.07, 0.06, 6.0, 8, pole, true)
		b.blob(Vector3(x, 5.6, 0), Vector3(0.12, 0.12, 0.12), Color(1.0, 0.75, 0.15, MB.PAINT), r, 0.0, 0)
	var cols := 8
	var cloth := Color(0.98, 0.98, 0.98, MB.TINT)
	var white := Color(0.99, 0.97, 0.9, MB.MATTE)
	b.set_wave(0.8, -3.0, 6.0, true)
	for i in cols:
		var x0 := -3.0 + 6.0 * i / cols
		var x1 := -3.0 + 6.0 * (i + 1) / cols
		for j in 2:
			var y0 := 3.3 + j * 0.8
			var y1 := y0 + 0.8
			b.quad2(Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0), cloth, cloth, Vector3(0, 0, -1))
	for face: float in [-1.0, 1.0]:
		var c := Vector3(0, 4.1, face * 0.012)
		for k in 10:
			var a0 := TAU * k / 10.0
			var a1 := TAU * (k + 1) / 10.0
			b.tri(c, c + Vector3(cos(a0) * 0.5, sin(a0) * 0.5, 0), c + Vector3(cos(a1) * 0.5, sin(a1) * 0.5, 0), white, Vector3(0, 0, face))
		b.panel(c + Vector3(0, -0.62, face * 0.004), Vector3(0, 0, face), 4.4, 0.1, white, 0.004)
	b.set_wave(0.0)

static func _flag_pole(b: MB, r: RandomNumberGenerator) -> void:
	var pole := Color(0.92, 0.93, 0.95, MB.METAL)
	b.cyl(Transform3D(Basis(), Vector3(0, -0.6, 0)), 0.07, 0.045, 8.8, 8, pole, true)
	b.blob(Vector3(0, 8.25, 0), Vector3(0.09, 0.09, 0.09), Color(1.0, 0.8, 0.2, MB.PAINT), r, 0.0, 0)
	var cloth := Color(0.98, 0.98, 0.98, MB.TINT)
	var cols := 6
	b.set_wave(1.0, 0.06, 2.4)
	for i in cols:
		var x0 := 0.06 + 2.4 * i / cols
		var x1 := 0.06 + 2.4 * (i + 1) / cols
		for j in 2:
			var y0 := 6.5 + j * 0.75
			b.quad2(Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y0 + 0.75, 0), Vector3(x0, y0 + 0.75, 0), cloth, cloth, Vector3(0, 0, -1))
	b.set_wave(0.0)

static func _fuel_pump(b: MB, r: RandomNumberGenerator) -> void:
	var white := Color(0.95, 0.95, 0.94, MB.MATTE)
	var orange := Color(0.98, 0.5, 0.12, MB.PAINT)
	b.block(Vector3(0, 0, 0), Vector3(0.95, 1.85, 0.55), white)
	b.block(Vector3(0, 1.85, 0), Vector3(1.0, 0.3, 0.6), orange)
	for face: float in [-1.0, 1.0]:
		var n := Vector3(0, 0, face)
		b.panel(Vector3(0, 1.4, face * 0.28), n, 0.55, 0.3, Color(0.4, 0.9, 1.0, MB.LIGHT), 0.02)
		b.panel(Vector3(0, 0.9, face * 0.28), n, 0.7, 0.4, DARK, 0.02)
		b.beam(Vector3(0.38, 1.2, face * 0.3), Vector3(0.45, 0.5, face * 0.33), 0.04, DARK)
	b.block(Vector3(0.5, 0.95, 0), Vector3(0.08, 0.3, 0.14), DARK)

static func _billboard(b: MB, r: RandomNumberGenerator) -> void:
	var post := Color(0.45, 0.47, 0.5, MB.METAL)
	for x: float in [-2.5, 2.5]:
		b.block(Vector3(x, -0.6, 0.15), Vector3(0.35, 3.8, 0.35), post)
	b.box(Transform3D(Basis(), Vector3(0, 5.0, 0.15)), Vector3(8.4, 4.4, 0.25), Color(0.2, 0.2, 0.22, MB.MATTE))
	var z := -0.0
	var n := Vector3(0, 0, -1)
	var sky0 := Color(1.0, 0.7, 0.32, MB.MATTE)
	var sky1 := Color(0.5, 0.32, 0.78, MB.MATTE)
	var x0 := -4.0
	var x1 := 4.0
	b.tri_vc(Vector3(x0, 4.6, z), Vector3(x1, 4.6, z), Vector3(x1, 7.0, z), sky0, sky0, sky1, n)
	b.tri_vc(Vector3(x0, 4.6, z), Vector3(x1, 7.0, z), Vector3(x0, 7.0, z), sky0, sky1, sky1, n)
	var sun := Vector3(1.6, 4.6, z - 0.01)
	for k in 12:
		var a0 := PI * k / 12.0
		var a1 := PI * (k + 1) / 12.0
		b.tri(sun, sun + Vector3(cos(a0), sin(a0), 0) * 1.3, sun + Vector3(cos(a1), sin(a1), 0) * 1.3, Color(1.0, 0.88, 0.4, MB.MATTE), n)
	var ground := Color(0.36, 0.6, 0.32, MB.MATTE)
	b.quad(Vector3(x0, 2.8, z), Vector3(x1, 2.8, z), Vector3(x1, 4.6, z), Vector3(x0, 4.6, z), ground, n)
	var road := Color(0.22, 0.22, 0.25, MB.MATTE)
	b.quad(Vector3(-2.2, 2.8, z - 0.02), Vector3(0.6, 2.8, z - 0.02), Vector3(-0.2, 4.6, z - 0.02), Vector3(-0.5, 4.6, z - 0.02), road, n)
	for k in 4:
		var t0 := k / 4.0 + 0.04
		var t1 := t0 + 0.12
		var p0 := Vector3(lerpf(-0.8, -0.35, t0), lerpf(2.8, 4.6, t0), z - 0.03)
		var p1 := Vector3(lerpf(-0.8, -0.35, t1), lerpf(2.8, 4.6, t1), z - 0.03)
		var w0 := lerpf(0.06, 0.015, t0)
		var w1 := lerpf(0.06, 0.015, t1)
		b.quad(p0 - Vector3(w0, 0, 0), p0 + Vector3(w0, 0, 0), p1 + Vector3(w1, 0, 0), p1 - Vector3(w1, 0, 0), Color(0.95, 0.95, 0.9, MB.MATTE), n)
	b.panel(Vector3(-2.2, 6.4, -0.04), n, 3.2, 0.45, Color(0.98, 0.98, 0.95, MB.MATTE), 0.01)
	b.panel(Vector3(-2.2, 5.85, -0.04), n, 2.2, 0.22, Color(0.98, 0.98, 0.95, MB.MATTE), 0.01)
	for x: float in [-2.6, 2.6]:
		b.beam(Vector3(x, 7.25, 0.1), Vector3(x, 7.6, -0.9), 0.06, post)
		b.box(Transform3D(Basis(Vector3(1, 0, 0), 0.5), Vector3(x, 7.6, -0.95)), Vector3(0.5, 0.12, 0.3), post)
		b.quad(Vector3(x - 0.2, 7.52, -1.05), Vector3(x + 0.2, 7.52, -1.05), Vector3(x + 0.2, 7.6, -0.85), Vector3(x - 0.2, 7.6, -0.85), LAMP, Vector3(0, -1, -0.4))
