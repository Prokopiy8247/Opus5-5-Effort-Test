class_name CarVisuals
extends Node3D
## Per-car visual state: paint/rim/lens materials, head/brake/reverse lights, steering wheel, sockets.

const STEERING_RATIO := 7.5
## Player headlights: a projected low beam (see beam_texture) over this half-angle.
const BEAM_ANGLE := 40.0
const BEAM_ENERGY := 32.0
## Traffic headlights: plain dimmer, shorter cones aimed at the road (many cars, no projector).
const TRAFFIC_BEAM_ENERGY := 5.0

var car: CarController
var paint_mats: Array[ShaderMaterial] = []
var rim_mats: Array[StandardMaterial3D] = []
var rim_default: Dictionary = {}
var lens: Dictionary = {}          # "head"/"tail"/"brake"/"reverse" -> Array[StandardMaterial3D]
var headlights: Array[SpotLight3D] = []
var sockets: Dictionary = {}       # socket name -> Transform3D (car space)
var steering_wheel: Node3D
var _steer_base: Basis
var _brake_level: float = 0.0
var _last_head := -1              # -1 = not applied yet, so the first frame always sets the lights
var _beam_energy := BEAM_ENERGY

static var _beam: ImageTexture


func _ready() -> void:
	# Head/tail lights follow the time of day: photo mode runs this group while the tree is paused.
	add_to_group(&"sunward_time_reactive")


func setup_from_model(model: Node3D, data: CarData) -> void:
	for n: String in ["head", "tail", "brake", "reverse"]:
		lens[n] = []
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			_setup_mesh_materials(n as MeshInstance3D)
		if n.name.begins_with("Socket_") and n is Node3D:
			sockets[String(n.name)] = CarFactory._relative_xf(n as Node3D, model)
	steering_wheel = model.find_child("SteeringWheel", true, false) as Node3D
	if steering_wheel:
		_steer_base = steering_wheel.transform.basis
		steering_wheel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _setup_mesh_materials(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		var mname := mat.resource_name if mat else ""
		if mname.begins_with("Paint"):
			var pm := ShaderMaterial.new()
			pm.shader = CarFactory.PAINT_SHADER
			mi.set_surface_override_material(i, pm)
			paint_mats.append(pm)
		elif mname.begins_with("Glass"):
			mi.set_surface_override_material(i, _glass_material())
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif mname.begins_with("Rim") and mat is StandardMaterial3D:
			var rm: StandardMaterial3D = mat.duplicate()
			mi.set_surface_override_material(i, rm)
			rim_mats.append(rm)
			rim_default[rm] = rm.albedo_color
		elif mat is StandardMaterial3D and (mname.begins_with("HeadlightLens") or mname.begins_with("TaillightLens") or mname.begins_with("BrakeLens") or mname.begins_with("ReverseLens")):
			var lm: StandardMaterial3D = mat.duplicate()
			lm.emission_enabled = true
			var key := "head"
			if mname.begins_with("TaillightLens"):
				key = "tail"
				lm.emission = Color(1.0, 0.05, 0.03)
			elif mname.begins_with("BrakeLens"):
				key = "brake"
				lm.emission = Color(1.0, 0.03, 0.02)
			elif mname.begins_with("ReverseLens"):
				key = "reverse"
				lm.emission = Color(1.0, 0.97, 0.9)
			else:
				lm.emission = Color(1.0, 0.96, 0.88)
			mi.set_surface_override_material(i, lm)
			(lens[key] as Array).append(lm)


static var _glass_shared: StandardMaterial3D

static func _glass_material() -> StandardMaterial3D:
	if _glass_shared == null:
		var g := StandardMaterial3D.new()
		g.resource_name = "GlassRuntime"
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.albedo_color = Color(0.06, 0.08, 0.09, 0.38)
		g.metallic = 0.2
		g.roughness = 0.03
		g.metallic_specular = 0.9
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass_shared = g
	return _glass_shared


func add_headlights() -> void:
	var player := car == null or car.is_player
	_beam_energy = BEAM_ENERGY if player else TRAFFIC_BEAM_ENERGY
	for side: String in ["L", "R"]:
		var key := "Socket_Headlight" + side
		if not sockets.has(key):
			continue
		var l := SpotLight3D.new()
		l.name = "Headlight" + side
		var t: Transform3D = sockets[key]
		var toe := deg_to_rad(1.5 if side == "L" else -1.5)
		if player:
			# Low beam: the projector shapes the beam (cut-off, hot spot, flood), so the cone itself stays level
			# and wide and never shows its round edge.
			l.transform = Transform3D(Basis.from_euler(Vector3(0.0, toe, 0.0)), t.origin)
			l.spot_range = 85.0
			l.spot_angle = BEAM_ANGLE
			l.spot_angle_attenuation = 2.0
			l.light_projector = beam_texture()
			# A spot light's projector needs its shadow transform; nothing is drawn into that shadow map.
			l.shadow_enabled = true
			l.shadow_caster_mask = 0
		else:
			l.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-5.0), toe, 0.0)), t.origin)
			l.spot_range = 45.0
			l.spot_angle = 26.0
			l.spot_angle_attenuation = 1.6
			l.spot_attenuation = 1.15
			l.shadow_enabled = false
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.light_specular = 0.4
		l.visible = false
		add_child(l)
		headlights.append(l)


## Low-beam pattern (projector texture over +-BEAM_ANGLE; u left to right, v top to bottom): a soft cut-off
## just below the lamp height that rises on the right (kerb) side, a hot spot on the road ahead and a wide,
## dimmer flood that eases off in the foreground. Walls and ceilings above the lamps only catch a faint spill,
## and the beam fades out well inside the cone, so nothing ends in a hard round edge.
static func beam_texture() -> ImageTexture:
	if _beam != null:
		return _beam
	# Built once (shared); 128 px is plenty for the soft profile.
	var n := 128
	var t := tan(deg_to_rad(BEAM_ANGLE))
	var vals := PackedFloat32Array()
	vals.resize(n * n)
	var peak := 0.0
	for py in n:
		for px in n:
			var th := ((px + 0.5) / n * 2.0 - 1.0) * t
			var tv := (1.0 - (py + 0.5) / n * 2.0) * t
			var ah := rad_to_deg(atan(th))
			var ev := rad_to_deg(atan(tv / sqrt(1.0 + th * th)))
			var off := rad_to_deg(atan(sqrt(th * th + tv * tv)))
			var cut := -0.6 + 1.6 * smoothstep(0.0, 8.0, ah)
			var below := 1.0 - smoothstep(cut - 1.5, cut + 0.5, ev)
			# Full across the lane ahead, easing off toward the verges; full just below the cut-off, easing off
			# in the foreground (the road close in needs less light); a hot spot for reach.
			var wide := 0.75 * exp(-0.5 * pow(ah / 16.0, 2.0)) + 0.25 * exp(-0.5 * pow(ah / 32.0, 2.0))
			var vert := lerpf(0.55, 1.0, smoothstep(-25.0, -4.0, ev))
			var hot := 0.7 * exp(-0.5 * (pow((ah - 1.5) / 6.0, 2.0) + pow((ev + 1.6) / 1.6, 2.0)))
			var spill := 0.02 * exp(-0.5 * pow(ah / 20.0, 2.0)) * exp(-0.5 * pow(maxf(ev - cut, 0.0) / 10.0, 2.0))
			var v := (below * (wide * vert + hot) + spill) * (1.0 - smoothstep(BEAM_ANGLE - 12.0, BEAM_ANGLE - 2.0, off))
			vals[py * n + px] = v
			peak = maxf(peak, v)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for py in n:
		for px in n:
			# Projectors are sampled as sRGB: store the encoded value so the beam keeps its linear profile.
			var v := vals[py * n + px] / peak
			img.set_pixel(px, py, Color(v, v, v).linear_to_srgb())
	_beam = ImageTexture.create_from_image(img)
	return _beam


func _process(delta: float) -> void:
	if car == null:
		return
	var braking := car.in_brake > 0.05 and car.gear != -1 or (car.gear == -1 and car.in_throttle > 0.05)
	_brake_level = move_toward(_brake_level, 1.0 if braking else 0.0, delta * 12.0)
	var night := car.headlights_on
	for m: StandardMaterial3D in lens.get("brake", []):
		m.emission_energy_multiplier = 0.25 + _brake_level * 5.0 + (0.8 if night else 0.0)
	for m: StandardMaterial3D in lens.get("tail", []):
		m.emission_energy_multiplier = 2.2 if night else 0.35
	for m: StandardMaterial3D in lens.get("reverse", []):
		m.emission_energy_multiplier = 4.0 if car.gear == -1 else 0.0
	if int(night) != _last_head:
		_last_head = int(night)
		for m: StandardMaterial3D in lens.get("head", []):
			m.emission_energy_multiplier = 6.0 if night else 0.8
		for l in headlights:
			l.visible = night
			l.light_energy = _beam_energy if night else 0.0
	if steering_wheel:
		steering_wheel.transform.basis = _steer_base * Basis(Vector3(0, 0, 1), -car.steer_angle * STEERING_RATIO)


func set_wetness(w: float) -> void:
	for m in paint_mats:
		m.set_shader_parameter("wetness", w)


func set_dirt(d: float) -> void:
	for m in paint_mats:
		m.set_shader_parameter("dirt_amount", d)
