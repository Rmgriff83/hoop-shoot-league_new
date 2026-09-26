class_name RimIce
extends Node3D
## Cold-streak rim: a jagged ring of ice (authored in Blender,
## tools/blender/build_rim_ice.py → assets/fx/rim_ice.glb: Shard00..11 +
## Icicle0..3) that freezes in from the outside of the rim, frosts the steel,
## and shatters — shards fly off, a cold mist puffs — when the ice breaks.
## Parented under the rim pivot like RimFire. Presentation only; the rules
## live in TimeTrial / StreakRules.

const MODEL := "res://assets/fx/rim_ice.glb"
const RING_R := SimConstants.R_RIM
const R_OUT := SimConstants.R_RIM + 0.022
const R_IN := SimConstants.R_RIM - 0.13
const FREEZE_S := 0.8
const SHATTER_S := 1.0
const FROST_ALBEDO := Color(0.8, 0.9, 1.0)
const MIST_TINT := Color(0.82, 0.9, 1.0)

var _pieces: Array[MeshInstance3D] = []
var _rest: Array[Transform3D] = []
var _mats: Array[ShaderMaterial] = []
var _vel: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _mist: Node3D
var _mist_mats: Array[ShaderMaterial] = []
var _mist_start := -10.0
var _light: OmniLight3D
var _rim_mat: StandardMaterial3D
var _base_albedo := Color.WHITE
var _iced := false
var _freeze := 0.0
var _freeze_target := 0.0
var _frost := 0.0
var _shatter_t := -1.0
var _shudder_t := -1.0
var _grab_t := -1.0
var _crack := 0.0
var _flash := 0.0
var _crystals: CPUParticles3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	var scene: PackedScene = load(MODEL)
	if scene != null:
		var inst := scene.instantiate()
		var shader: Shader = load("res://game/court/ice.gdshader")
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("freeze", 0.0)
			mat.set_shader_parameter("fade", 1.0)
			mat.set_shader_parameter("r_out", R_OUT)
			mat.set_shader_parameter("r_in", R_IN)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_pieces.append(mi)
			_mats.append(mat)
			_vel.append(Vector3.ZERO)
			_spin.append(Vector3.ZERO)
		# Reparent pieces directly under us (keeping their transform relative to
		# the glb root) so their rest transforms are simple; works off-tree too.
		for mi in _pieces:
			var xf := mi.transform
			var p := mi.get_parent()
			while p != null and p != inst:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			mi.owner = null
			mi.get_parent().remove_child(mi)
			add_child(mi)
			mi.transform = xf
			_rest.append(xf)
		inst.free()
	var puffs := RimFire.build_puffs("Mist", 0.34, MIST_TINT)
	_mist = puffs[0]
	_mist_mats = puffs[1]
	add_child(_mist)
	_crystals = _crystal_burst()
	add_child(_crystals)
	_light = OmniLight3D.new()
	_light.name = "Cold"
	_light.light_color = Color(0.55, 0.75, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 1.0
	_light.position = Vector3(0.0, 0.12, 0.0)
	add_child(_light)
	visible = false


## Give the effect the rim mesh so it can frost the steel (shares the
## override RimFire may already have installed; the two never run together).
func setup(rim: MeshInstance3D) -> void:
	if rim == null or rim.mesh == null or rim.mesh.get_surface_count() == 0:
		return
	if rim.material_override is StandardMaterial3D:
		_rim_mat = rim.material_override
	else:
		var src := rim.mesh.surface_get_material(0)
		if src is StandardMaterial3D:
			_rim_mat = (src as StandardMaterial3D).duplicate()
			rim.material_override = _rim_mat
	if _rim_mat != null:
		_base_albedo = _rim_mat.albedo_color


func is_iced() -> bool:
	return _iced


func freeze_amount() -> float:
	return _freeze


## Ice over: the ring grows in from the outside edge; the steel frosts.
func freeze() -> void:
	if _iced:
		return
	_iced = true
	_shatter_t = -1.0
	_reset_pieces()
	visible = true
	_freeze_target = 1.0
	Sfx.ice_freeze()


## A rim hit chipped the ice: a quick shudder and a crack.
func crack(_hits_left: int) -> void:
	if not _iced:
		return
	_shudder_t = 0.0
	Sfx.ice_crack()


## The ice has grabbed the ball: fissures spread and the slab groans until the
## pop (shatter) — roughly ShotSim.ICE_HOLD_S later.
func grab() -> void:
	if not _iced:
		return
	_grab_t = 0.0
	_shudder_t = 0.0
	Sfx.ice_crack()


## The ice breaks: a flash, shards blast outward and up, ice crystals spray,
## a cold mist, and the steel warms back up.
func shatter(by := "") -> void:
	if not _iced:
		return
	_iced = false
	_freeze_target = 0.0
	_shatter_t = 0.0
	_grab_t = -1.0
	_flash = 1.0
	for i in _pieces.size():
		var p := _pieces[i].position
		var out := Vector3(p.x, 0.0, p.z).normalized()
		var inner := p.length() < RING_R - 0.04
		# Inner pieces (near the hole) blast up hardest — the ball just shoved through.
		var up := _rng.randf_range(1.2, 2.2) if inner else _rng.randf_range(0.4, 1.0)
		_vel[i] = out * _rng.randf_range(0.7, 1.5) + Vector3(_rng.randf_range(-0.3, 0.3), up, _rng.randf_range(-0.3, 0.3))
		_spin[i] = Vector3(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-6.0, 6.0), _rng.randf_range(-10.0, 10.0))
	_mist_start = _t
	_mist.visible = true
	_crystals.restart()
	_crystals.emitting = true
	Sfx.ice_shatter(by == "swish")


## Instant off (end of a run): no animation.
func clear() -> void:
	_iced = false
	_freeze = 0.0
	_freeze_target = 0.0
	_shatter_t = -1.0
	_grab_t = -1.0
	_crack = 0.0
	_flash = 0.0
	_mist.visible = false
	_crystals.emitting = false
	_reset_pieces()
	visible = false
	if _rim_mat != null:
		_rim_mat.albedo_color = _base_albedo
	_light.light_energy = 0.0


func _reset_pieces() -> void:
	for i in _pieces.size():
		_pieces[i].transform = _rest[i]
		_mats[i].set_shader_parameter("fade", 1.0)
		_mats[i].set_shader_parameter("freeze", _freeze)


func _process(dt: float) -> void:
	if _light == null or _mist == null:
		return
	_t += dt
	var centre := global_position if is_inside_tree() else position
	# Freeze in / out.
	if _shatter_t < 0.0:
		var rate := 1.0 / FREEZE_S
		_freeze = move_toward(_freeze, _freeze_target, rate * dt)
	for i in _mats.size():
		_mats[i].set_shader_parameter("freeze", _freeze if _shatter_t < 0.0 else 1.0)
		_mats[i].set_shader_parameter("t", _t)
		_mats[i].set_shader_parameter("center", centre)
	# Grab: fissures spread over the hold, with a second crack partway.
	if _grab_t >= 0.0:
		var was := _grab_t
		_grab_t += dt
		_crack = clampf(_grab_t / 0.45, 0.0, 1.0)
		if was < 0.22 and _grab_t >= 0.22:
			_shudder_t = 0.0
			Sfx.ice_crack()
	elif _shatter_t < 0.0:
		_crack = move_toward(_crack, 0.0, dt * 3.0)
	_flash = move_toward(_flash, 0.0, dt * 2.5)
	for m in _mats:
		m.set_shader_parameter("crack", _crack)
	# Shudder on a crack.
	if _shudder_t >= 0.0:
		_shudder_t += dt
		var k := 1.0 + 0.05 * sin(_shudder_t * 60.0) * maxf(0.0, 1.0 - _shudder_t / 0.18)
		scale = Vector3(k, 1.0, k)
		if _shudder_t > 0.2:
			_shudder_t = -1.0
			scale = Vector3.ONE
	# Shatter: fling, tumble, fade (shards hold full opacity for the first third).
	if _shatter_t >= 0.0:
		_shatter_t += dt
		var fade := clampf(1.0 - maxf(_shatter_t - SHATTER_S * 0.35, 0.0) / (SHATTER_S * 0.65), 0.0, 1.0)
		for i in _pieces.size():
			_vel[i].y -= 6.0 * dt
			_pieces[i].position += _vel[i] * dt
			_pieces[i].rotation += _spin[i] * dt
			_mats[i].set_shader_parameter("fade", fade)
		if _shatter_t > SHATTER_S + 0.1:
			_shatter_t = -1.0
			_reset_pieces()
			_freeze = 0.0
			visible = false
	# Mist puffs after the break.
	if _mist.visible:
		var age := _t - _mist_start
		for i in _mist_mats.size():
			_mist_mats[i].set_shader_parameter("age", age - float(i) * RimFire.PUFF_STAGGER)
		if age > RimFire.PUFF_DURATION + float(RimFire.PUFFS) * RimFire.PUFF_STAGGER:
			_mist.visible = false
	# Frost on the steel and the cold light follow the ice.
	var frost_target := 1.0 if _iced else 0.0
	_frost = move_toward(_frost, frost_target, dt / FREEZE_S)
	if _rim_mat != null:
		_rim_mat.albedo_color = _base_albedo.lerp(FROST_ALBEDO, _frost)
	_light.light_energy = 0.12 * _frost + 0.3 * _flash
	for m in _mats:
		m.set_shader_parameter("frost", _frost * 0.5)


## A spray of tiny ice crystals on the break (additive, short-lived).
func _crystal_burst() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Crystals"
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = RING_R - 0.06
	p.emission_ring_inner_radius = R_IN
	p.emission_ring_height = 0.02
	p.local_coords = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 36
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color_ramp = _ramp([[0.0, Color(0.7, 0.85, 1.0, 0.7)], [0.6, Color(0.5, 0.7, 0.95, 0.45)], [1.0, Color(0.4, 0.6, 0.9, 0.0)]])
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.022)   # a crystal is ~1–2 cm; scale_amount trims it
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(RimFire.SMOKE_TEX_SOFT)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.85, 0.95, 1.0)
	m.disable_fog = true
	quad.material = m
	p.mesh = quad
	return p


static func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for st in stops:
		g.add_point(st[0], st[1])
	return g
