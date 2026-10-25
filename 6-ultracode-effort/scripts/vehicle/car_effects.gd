extends Node3D
## Per-car visual effects (child "CarEffects" of a CarController): tyre smoke, surface dust / snow
## powder, rain spray, skid marks, exhaust vapour + backfire flames, impact sparks / debris,
## dirt + wetness on the paint and brake-disc glow.
## Player cars get full detail; AI / traffic cars (car.is_player == false) get a reduced set
## (rear-wheel smoke + dust, skid marks, sparks) that only runs near the camera.

## Emitted on pops from this node's own detector (only used when the car has no CarAudio
## emitting `backfire`; otherwise the flames follow CarAudio's pops and this stays silent).
signal backfire(strength: float)

const FxLib := preload("res://scripts/fx/fx_library.gd")
const SkidMarks := preload("res://scripts/fx/skid_marks.gd")
const BrakeGlow := preload("res://scripts/fx/brake_glow.gd")

const NPC_MAX_ACTIVE := 6
const NPC_RANGE := 90.0
const SEG_MIN := 0.35
const SEG_BREAK := 4.0
const FLAME_TIME := 0.11
const DIRT_RATE := 1.0 / 70.0
## CarAudio emits pops when it renders them, ~one buffer ahead of playback.
const AUDIO_LATENCY := 0.07
const AUDIO_POP_MIN := 0.45

class WheelFx:
	var smoke: GPUParticles3D
	var dust: GPUParticles3D
	var dust_mat: ParticleProcessMaterial
	var dust_color: Color = Color(0.55, 0.45, 0.32, 0.6)
	var snow_look: bool = false
	var spray: GPUParticles3D
	var marking: bool = false
	var mark_last: Vector3
	var mark_last_alpha: float = 0.0
	var mark_alpha: float = 0.0

static var _npc_active: int = 0
static var _dirt_memory: Dictionary = {}

var car: CarController
var full_detail: bool = true
## 0 clean .. 1 caked; persists per car id while the game runs.
var dirt: float = 0.0

var _built: bool = false
var _active: bool = true
var _npc_slot: bool = false
var _q: float = 1.0
var _wheels: Array[WheelFx] = []
var _exhausts: Array[GPUParticles3D] = []
var _flames: Array[MeshInstance3D] = []
var _flash: OmniLight3D
var _sparks: Array[GPUParticles3D] = []
var _debris: Array[GPUParticles3D] = []
var _impacts: Array[Vector4] = []
var _impact_idx: int = 0
var _scrape: GPUParticles3D
var _prev_velocity: Vector3 = Vector3.ZERO
var _scrape_speed: float = 0.0
var _scrape_local: Vector3 = Vector3.ZERO
var _brakes: BrakeGlow
var _skids: SkidMarks
var _visual: CarVisuals
var _lod_timer: float = 0.0
var _wet_timer: float = 0.0
var _water_timer: float = 0.0
var _splash_wet: float = 0.0
var _in_water: bool = false
var _dirt_sent: float = -1.0
var _pop_chance: float = 0.5
var _arm_t: float = 0.0
var _pops: int = 0
var _pop_timer: float = 0.0
var _pop_cd: float = 0.0
var _flame_t: float = 0.0
var _flame_power: float = 1.0
var _prev_limiter: bool = false
var _prev_shifting: bool = false
var _exhaust_kick: float = 0.0
var _audio_checked: bool = false
var _audio_pops: bool = false
var _audio_queue: Array[Vector2] = []
var _built_ms: int = 0
var _cost_us_max: int = 0
var _cost_us_sum: int = 0
var _cost_n: int = 0


func _ready() -> void:
	car = get_parent() as CarController
	if car == null:
		set_process(false)
		return
	if not car.impact.is_connected(_on_impact):
		car.impact.connect(_on_impact)
	_try_build()


func _exit_tree() -> void:
	if _npc_slot:
		_npc_slot = false
		_npc_active = maxi(_npc_active - 1, 0)
	if _built and not full_detail and _active:
		# Pooled traffic cars must take a slot again when they re-enter the tree.
		_active = false
		_set_emitters_on(false)
		for fx in _wheels:
			fx.marking = false
	if _built and full_detail and car != null and car.data != null:
		_dirt_memory[car.data.id] = dirt


func _try_build() -> void:
	if _built or car.data == null or car.wheels.is_empty():
		return
	_built = true
	_built_ms = Time.get_ticks_msec()
	full_detail = car.is_player
	_q = FxLib.quality_scale()
	_visual = car.get_node_or_null("Visual") as CarVisuals
	var big := AABB(Vector3(-60, -6, -60), Vector3(120, 36, 120))
	for w in car.wheels:
		var fx := WheelFx.new()
		if full_detail or not w.front:
			fx.smoke = _emitter(FxLib.smoke_process(), FxLib.soft_material(&"smoke"), _n(80 if full_detail else 28), 3.4, big)
			fx.dust_mat = FxLib.dust_process()
			fx.dust = _emitter(fx.dust_mat, FxLib.soft_material(&"dust"), _n(90 if full_detail else 32), 3.2, big)
		if full_detail:
			fx.spray = _emitter(FxLib.spray_process(), FxLib.soft_material(&"spray"), _n(90), 1.0, AABB(Vector3(-30, -4, -30), Vector3(60, 14, 60)))
		_wheels.append(fx)
	_build_exhaust()
	_build_impact_fx()
	if full_detail:
		_brakes = BrakeGlow.new()
		if not _brakes.setup(car):
			_brakes = null
		dirt = float(_dirt_memory.get(car.data.id, 0.0))
		_pop_chance = clampf((car.data.exhaust_rasp - 0.1) * 1.5 + (0.08 if car.data.turbo else 0.0), 0.05, 0.95)
	else:
		_active = false
		_set_emitters_on(false)


func _n(base: int) -> int:
	return maxi(int(base * _q), 4)


func _emitter(proc: ParticleProcessMaterial, draw: Material, amount: int, lifetime: float, aabb: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = proc
	p.draw_pass_1 = FxLib.quad()
	p.material_override = draw
	p.local_coords = false
	p.fixed_fps = 0
	p.amount_ratio = 0.0
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = aabb
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.emitting = true
	add_child(p)
	return p


func _oneshot(proc: ParticleProcessMaterial, mesh: Mesh, draw: Material, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = proc
	p.draw_pass_1 = mesh
	if draw != null:
		p.material_override = draw
	p.local_coords = false
	p.fixed_fps = 0
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-10, -6, -10), Vector3(20, 14, 20))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(p)
	return p


func _build_exhaust() -> void:
	if not full_detail:
		return
	var tips: Array[Vector3] = []
	if _visual != null:
		for key: String in ["Socket_Exhaust", "Socket_Exhaust2"]:
			if _visual.sockets.has(key):
				tips.append((_visual.sockets[key] as Transform3D).origin)
	if tips.is_empty():
		# No model sockets (placeholder car): low on the rear bumper, slightly right of centre.
		tips.append(Vector3(car.data.body_size.x * 0.25, 0.3, car.data.body_size.z * 0.5))
	var mid := Vector3.ZERO
	for t in tips:
		var e := _emitter(FxLib.exhaust_process(), FxLib.soft_material(&"exhaust"), _n(22), 1.4, AABB(Vector3(-12, -4, -12), Vector3(24, 12, 24)))
		e.position = t + Vector3(0, 0, 0.04)
		_exhausts.append(e)
		var f := MeshInstance3D.new()
		f.mesh = FxLib.flame_mesh()
		f.position = t + Vector3(0, 0, 0.02)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		f.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		f.visible = false
		add_child(f)
		_flames.append(f)
		mid += t
	mid /= float(tips.size())
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.55, 0.22)
	_flash.omni_range = 2.6
	_flash.omni_attenuation = 1.4
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.light_specular = 0.3
	_flash.position = mid + Vector3(0, 0.08, 0.35)
	_flash.visible = false
	add_child(_flash)


func _build_impact_fx() -> void:
	var n_pool := 2 if full_detail else 1
	for i in n_pool:
		var s := _oneshot(FxLib.spark_process(), FxLib.spark_quad(), FxLib.spark_material(), _n(72 if full_detail else 32), 0.65)
		s.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		_sparks.append(s)
		if full_detail:
			_debris.append(_oneshot(FxLib.debris_process(), FxLib.debris_mesh(), null, _n(14), 1.1))
	if full_detail:
		_scrape = _emitter(FxLib.scrape_process(), FxLib.spark_material(), _n(90), 0.5, AABB(Vector3(-20, -6, -20), Vector3(40, 14, 40)))
		_scrape.draw_pass_1 = FxLib.spark_quad()
		_scrape.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
		_scrape.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not _built:
		_try_build()
		if not _built:
			return
	if not full_detail:
		_lod_timer -= delta
		if _lod_timer <= 0.0:
			_lod_timer = 0.3
			_update_npc_lod()
		if not _active:
			_impacts.clear()
			return
	var t0 := Time.get_ticks_usec()
	if _skids == null or not is_instance_valid(_skids):
		_skids = SkidMarks.ensure(self) as SkidMarks
	if full_detail:
		_update_water(delta)
	_update_wheels(delta)
	if full_detail:
		_update_exhaust(delta)
		_update_backfire(delta)
		_update_paint(delta)
		_update_scrape()
		if _brakes != null:
			_brakes.update(delta)
	_process_impacts()
	var us := Time.get_ticks_usec() - t0
	_cost_us_max = maxi(_cost_us_max, us)
	_cost_us_sum += us
	_cost_n += 1


func _physics_process(_delta: float) -> void:
	_scrape_speed = 0.0
	if _scrape == null or car == null or car.get_contact_count() == 0:
		return
	var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
	if st == null:
		return
	for i in st.get_contact_count():
		var rel := st.get_contact_local_velocity_at_position(i) - st.get_contact_collider_velocity_at_position(i)
		var nrm := st.get_contact_local_normal(i)
		var slide := (rel - nrm * rel.dot(nrm)).length()
		if slide > _scrape_speed:
			_scrape_speed = slide
			_scrape_local = car.to_local(st.get_contact_collider_position(i))


func _update_scrape() -> void:
	if _scrape == null:
		return
	var r := smoothstep(3.0, 18.0, _scrape_speed)
	if r > 0.0:
		_scrape.transform = Transform3D(Basis.IDENTITY if car.forward_speed >= 0.0 else Basis(Vector3.UP, PI), _scrape_local)
	_set_ratio(_scrape, r)


func _update_npc_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_squared_to(car.global_position) < NPC_RANGE * NPC_RANGE
	if near and not _active and _npc_active < NPC_MAX_ACTIVE:
		_npc_active += 1
		_npc_slot = true
		_active = true
		_set_emitters_on(true)
	elif not near and _active:
		_active = false
		if _npc_slot:
			_npc_slot = false
			_npc_active = maxi(_npc_active - 1, 0)
		_set_emitters_on(false)
		for fx in _wheels:
			fx.marking = false


func _set_emitters_on(on: bool) -> void:
	for fx in _wheels:
		for p: GPUParticles3D in [fx.smoke, fx.dust, fx.spray]:
			if p != null:
				p.amount_ratio = 0.0
				p.emitting = on


static func _dust_factor(id: StringName) -> float:
	match id:
		&"sand":
			return 1.2
		&"dirt":
			return 1.0
		&"snow":
			return 1.0
		&"gravel":
			return 0.85
		&"grass":
			return 0.3
	return 0.6


func _update_wheels(delta: float) -> void:
	var v := car.speed_ms
	var back := 1.0 if car.forward_speed >= -0.5 else -1.0
	# The tyre model flags ABS-limited wheels as locked (skid 0.8); ABS stops should only scuff lightly.
	var abs_cap := car.assist_abs and car.abs_active
	var flip := Basis.IDENTITY if back > 0.0 else Basis(Vector3.UP, PI)
	# Rewind scrubbing replays a recorded path: no smoke, dust, spray or marks along it.
	var live := not car.rewinding
	for i in mini(car.wheels.size(), _wheels.size()):
		var w := car.wheels[i]
		var fx := _wheels[i]
		var s := w.surface
		var smoke_i := 0.0
		var dust_i := 0.0
		var spray_i := 0.0
		var mark_i := 0.0
		if live and w.contact and s != null:
			var slide := w.skid
			if abs_cap and w.brake_force > 1.0 and not (car.in_handbrake > 0.1 and not w.front):
				slide = minf(slide, 0.32)
			var paved := s.paved
			# A dry-looking paved road fades its smoke and marks out as it gets wet (the wet surface has none).
			var damp := smoothstep(0.08, CarController.WET_LOOK, w.wetness) if s.smokes else 0.0
			if s.smokes:
				smoke_i = smoothstep(0.16, 0.75, slide) * (1.0 - damp)
			elif not paved:
				var roll := smoothstep(3.0, 24.0, v) * (0.3 if w.front else 0.6)
				dust_i = clampf((roll + smoothstep(0.08, 0.6, slide) * 0.9) * _dust_factor(s.id), 0.0, 1.0)
			# Per-wheel wetness: 0 on covered road (tunnels), so no spray under a roof.
			if paved and w.wetness > 0.3:
				spray_i = (w.wetness - 0.3) / 0.7 * smoothstep(6.0, 28.0, v) * (0.55 if w.front else 1.0)
			if _in_water:
				spray_i = maxf(spray_i, smoothstep(1.5, 10.0, v))
			if s.skid_color.a > 0.0:
				mark_i = smoothstep(0.2, 0.7, slide) * s.skid_color.a * (1.0 - damp * 0.5)
				if s.id == &"sand" or s.id == &"snow":
					mark_i = maxf(mark_i, s.skid_color.a * 0.4 * smoothstep(0.5, 3.0, v))
		if not live:
			fx.mark_alpha = 0.0
		var contact_local := w.mount - Vector3.UP * (w.length + w.radius)
		if fx.smoke != null:
			fx.smoke.position = contact_local + Vector3(0, 0.12, 0.08 * back)
			_set_ratio(fx.smoke, smoke_i)
		if fx.dust != null:
			fx.dust.transform = Transform3D(flip, contact_local + Vector3(0, 0.1, w.radius * 0.5 * back))
			if dust_i > 0.0:
				_tint_dust(fx, s, delta)
			_set_ratio(fx.dust, dust_i)
		if fx.spray != null:
			fx.spray.transform = Transform3D(flip, contact_local + Vector3(0, 0.14, w.radius * 0.6 * back))
			_set_ratio(fx.spray, spray_i)
		_update_mark(fx, w, mark_i, delta)


func _set_ratio(p: GPUParticles3D, r: float) -> void:
	if absf(p.amount_ratio - r) > 0.02 or (r == 0.0 and p.amount_ratio != 0.0):
		p.amount_ratio = r


func _tint_dust(fx: WheelFx, s: SurfaceData, delta: float) -> void:
	var target := s.particle_color
	if s.id == &"grass":
		# Grass kicks up a light haze of soil and clippings rather than a green cloud.
		target = target.lerp(Color(0.7, 0.66, 0.52, 0.38), 0.65)
	# Airborne dust scatters light: keep it a little lighter than the ground it comes from.
	var lit := Color(target.r, target.g, target.b).lerp(Color(0.96, 0.93, 0.87), 0.2)
	target = Color(lit.r, lit.g, lit.b, target.a)
	# Blend while a plume is live (the colour applies to live particles too); snap when idle.
	var c := target if fx.dust.amount_ratio == 0.0 else fx.dust_color.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	if absf(c.r - fx.dust_color.r) + absf(c.g - fx.dust_color.g) + absf(c.b - fx.dust_color.b) + absf(c.a - fx.dust_color.a) > 0.004:
		fx.dust_color = c
		fx.dust_mat.color = c
	var snow := s.id == &"snow"
	if snow != fx.snow_look:
		fx.snow_look = snow
		fx.dust.material_override = FxLib.soft_material(&"snow" if snow else &"dust")


func _update_mark(fx: WheelFx, w: CarController.Wheel, target: float, delta: float) -> void:
	fx.mark_alpha = move_toward(fx.mark_alpha, target, delta * 4.0)
	if _skids == null or not w.contact or w.surface == null or fx.mark_alpha < 0.01:
		fx.marking = false
		return
	var p := w.point
	if not fx.marking:
		fx.marking = true
		fx.mark_last = p
		fx.mark_last_alpha = 0.0
		return
	var d := p.distance_to(fx.mark_last)
	if d > SEG_BREAK:
		fx.mark_last = p
		fx.mark_last_alpha = 0.0
		return
	if d < SEG_MIN:
		return
	_skids.add_segment(fx.mark_last, p, w.normal, w.width * 0.85, w.surface.skid_color, fx.mark_last_alpha, fx.mark_alpha)
	fx.mark_last = p
	fx.mark_last_alpha = fx.mark_alpha


func _update_exhaust(delta: float) -> void:
	if _exhausts.is_empty():
		return
	var d := car.data
	var rpm_f := clampf((car.rpm - d.idle_rpm) / maxf(d.redline_rpm - d.idle_rpm, 1.0), 0.0, 1.0)
	var speed_fade := 1.0 - clampf(car.speed_ms / 30.0, 0.0, 1.0) * 0.75
	var r := clampf((0.16 + car.throttle_applied * 0.55 + rpm_f * 0.2) * speed_fade + _exhaust_kick, 0.0, 1.0)
	_exhaust_kick = maxf(_exhaust_kick - delta * 3.0, 0.0)
	for e in _exhausts:
		_set_ratio(e, r)


func _update_backfire(delta: float) -> void:
	if _flames.is_empty():
		return
	if not _audio_checked:
		_hook_audio()
	if _audio_pops:
		# CarAudio decides when the engine pops; flames follow its buffered output.
		var i := _audio_queue.size() - 1
		while i >= 0:
			var q := _audio_queue[i]
			q.x -= delta
			if q.x <= 0.0:
				_do_pop(q.y, false)
				_audio_queue.remove_at(i)
			else:
				_audio_queue[i] = q
			i -= 1
	else:
		_detect_pops(delta)
	if _flame_t > 0.0:
		_flame_t -= delta
		var k := clampf(_flame_t / FLAME_TIME, 0.0, 1.0)
		for f in _flames:
			f.set_instance_shader_parameter(&"intensity", k * _flame_power)
		if _flash != null:
			_flash.light_energy = k * k * 2.4 * _flame_power
		if _flame_t <= 0.0:
			for f in _flames:
				f.visible = false
			if _flash != null:
				_flash.visible = false


func _hook_audio() -> void:
	var a := car.get_node_or_null("CarAudio")
	if a != null and a.has_signal(&"backfire"):
		_audio_checked = true
		_audio_pops = true
		a.connect(&"backfire", _on_audio_pop)
	elif Time.get_ticks_msec() - _built_ms > 3000:
		_audio_checked = true


func _on_audio_pop(strength: float) -> void:
	if strength >= AUDIO_POP_MIN and _audio_queue.size() < 6:
		_audio_queue.append(Vector2(AUDIO_LATENCY, strength))


## Own pop detector (used when no CarAudio emits pops): lift-off at high rpm, limiter hits, upshifts.
func _detect_pops(delta: float) -> void:
	var d := car.data
	var thr := car.in_throttle
	var rpm_frac := car.rpm / maxf(d.redline_rpm, 1.0)
	_pop_cd = maxf(_pop_cd - delta, 0.0)
	if thr > 0.7 and rpm_frac > 0.72:
		_arm_t = 0.35
	else:
		_arm_t -= delta
	if thr < 0.15 and _arm_t > 0.0:
		_arm_t = 0.0
		if randf() < _pop_chance:
			_queue_pops(randi_range(1, 3) + (1 if rpm_frac > 0.9 else 0))
	var lim := car.limiter_hit
	if lim and not _prev_limiter and _pop_cd <= 0.0 and randf() < _pop_chance * 0.6:
		_queue_pops(1)
	_prev_limiter = lim
	var sh := car.shifting
	if sh and not _prev_shifting and rpm_frac > 0.8 and thr > 0.5 and randf() < _pop_chance * 0.7:
		_queue_pops(1)
	_prev_shifting = sh
	if _pops > 0:
		_pop_timer -= delta
		if _pop_timer <= 0.0:
			_pops -= 1
			_pop_timer = randf_range(0.055, 0.15)
			_do_pop(randf_range(0.65, 1.0), true)


func _queue_pops(n: int) -> void:
	if _pops == 0:
		_pop_timer = 0.0
	_pops = mini(_pops + n, 4)
	_pop_cd = 0.25


func _do_pop(power: float, announce: bool) -> void:
	_flame_power = clampf(power, 0.3, 1.0)
	_flame_t = FLAME_TIME * (0.6 + 0.4 * _flame_power) + randf() * 0.04
	for f in _flames:
		var wd := randf_range(0.11, 0.16) * (0.75 + 0.25 * _flame_power)
		f.scale = Vector3(wd, wd, randf_range(0.28, 0.55) * (0.55 + 0.45 * _flame_power))
		f.set_instance_shader_parameter(&"seed", randf() * 10.0)
		f.set_instance_shader_parameter(&"intensity", _flame_power)
		f.visible = true
	if _flash != null and _flame_power > 0.55:
		_flash.visible = true
		_flash.light_energy = 2.4 * _flame_power
	_exhaust_kick = 0.5 * _flame_power
	if announce:
		backfire.emit(_flame_power)


func _on_impact(strength: float, world_position: Vector3) -> void:
	# May arrive from the physics step: queue and handle in _process.
	if _impacts.size() < 4:
		_impacts.append(Vector4(world_position.x, world_position.y, world_position.z, strength))


func _process_impacts() -> void:
	if _impacts.is_empty():
		_prev_velocity = car.linear_velocity
		return
	for imp in _impacts:
		var s := imp.w
		if s < 2.0 or _sparks.is_empty():
			continue
		var pos := Vector3(imp.x, imp.y, imp.z)
		# Velocity from before the hit: the car may already be bouncing back.
		var dir := _prev_velocity
		dir.y = 0.0
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP) if dir.length() > 1.0 else car.global_basis.orthonormalized()
		var sp := _sparks[_impact_idx % _sparks.size()]
		sp.global_transform = Transform3D(basis, pos)
		sp.amount_ratio = clampf(s / 8.0, 0.35, 1.0)
		sp.restart()
		sp.emitting = true
		if s > 5.0 and not _debris.is_empty():
			var db := _debris[_impact_idx % _debris.size()]
			db.global_transform = Transform3D(basis, pos)
			db.amount_ratio = clampf(s / 14.0, 0.35, 1.0)
			db.restart()
			db.emitting = true
		_impact_idx += 1
	_impacts.clear()
	_prev_velocity = car.linear_velocity


func _update_water(delta: float) -> void:
	_water_timer -= delta
	if _water_timer <= 0.0:
		_water_timer = 0.2
		_in_water = false
		var wld := Game.world
		if wld != null and wld.has_method("water_level_at"):
			var p := car.global_position
			var lvl: float = wld.water_level_at(p.x, p.z)
			_in_water = lvl > -1e9 and p.y < lvl + 0.05 and car.wheels_on_ground > 0
		if _in_water:
			_splash_wet = 1.0
	_splash_wet = maxf(_splash_wet - delta / 40.0, 0.0)


static func _dirt_factor(id: StringName) -> float:
	match id:
		&"dirt":
			return 1.0
		&"gravel":
			return 0.75
		&"sand":
			return 0.6
		&"grass":
			return 0.35
		&"snow":
			return 0.12
	return 0.5


func _update_paint(delta: float) -> void:
	if _visual == null:
		return
	var gain := 0.0
	for w in car.wheels:
		if w.contact and w.surface != null and not w.surface.paved and not car.rewinding:
			gain += _dirt_factor(w.surface.id)
	gain *= 0.25 * DIRT_RATE * clampf(car.speed_ms / 18.0, 0.0, 1.6)
	var wash := CarController.wetness * 0.012 + (0.2 if _in_water else 0.0)
	dirt = clampf(dirt + (gain - wash) * delta, 0.0, 1.0)
	if absf(dirt - _dirt_sent) > 0.01:
		_dirt_sent = dirt
		_visual.set_dirt(dirt)
	_wet_timer -= delta
	if _wet_timer <= 0.0:
		_wet_timer = 0.5
		_visual.set_wetness(maxf(CarController.wetness, _splash_wet))


# ------------------------------------------------------------------ API

func set_dirt_level(d: float) -> void:
	dirt = clampf(d, 0.0, 1.0)
	_dirt_sent = -1.0


## Snapshot for tests / debug overlays. Resets the CPU cost counters.
func debug_state() -> Dictionary:
	var cost := [_cost_us_sum / maxi(_cost_n, 1), _cost_us_max]
	_cost_us_sum = 0
	_cost_n = 0
	_cost_us_max = 0
	var smoke := 0.0
	var dust := 0.0
	var spray := 0.0
	for fx in _wheels:
		if fx.smoke != null:
			smoke = maxf(smoke, fx.smoke.amount_ratio)
		if fx.dust != null:
			dust = maxf(dust, fx.dust.amount_ratio)
		if fx.spray != null:
			spray = maxf(spray, fx.spray.amount_ratio)
	return {"active": _active, "smoke": snappedf(smoke, 0.01), "dust": snappedf(dust, 0.01), "spray": snappedf(spray, 0.01),
		"marks": _skids.segment_count() if _skids != null else 0, "dirt": snappedf(dirt, 0.001),
		"brake_heat": snappedf(_brakes.max_heat(), 0.01) if _brakes != null else -1.0, "in_water": _in_water,
		"scrape": snappedf(_scrape.amount_ratio, 0.01) if _scrape != null else 0.0,
		"cpu_us_avg": cost[0], "cpu_us_max": cost[1]}
