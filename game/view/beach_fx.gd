class_name BeachFx
extends Node
## Presentation-only beach motion. The `Ocean` plane's vertex waves come from
## ocean.gdshader fed a running clock; a slow tide slides Ocean + `Shore`
## (the foam strip) along x so the waterline creeps up the sand and back.
## Never touches the sim.

const TIDE_AMP := 0.6         # m of shoreline travel each way
const TIDE_PERIOD := 18.0     # s per full in-and-out
const WASH_AMP := 0.45        # m each wave washes up the sand (in step with the swell)
const WASH_RATE := 1.6        # rad/s — ocean.gdshader's w1
const FOAM_SCROLL := 0.12     # texture repeats per second along the strip
const SHADER := preload("res://game/court/ocean.gdshader")
## The 3D coconut palms (design "Beach Concept" 34a, 2026-10-16): the unit
## model in palm.glb (PalmTrunk + PalmFronds) drawn at every `PalmRig*` empty
## — the rig's transform is the tree's height and lean — in two MultiMeshes,
## one ShaderMaterial each; palm3d.gdshader sways and flutters them.
const PALM_SHADER := preload("res://game/court/palm3d.gdshader")
const PALM_GLB := "res://assets/arena/beach/palm.glb"
const WATER_FALLBACK := "res://assets/textures/beach_water.png"
const FOAM_FALLBACK := "res://assets/textures/beach_foam.png"
## Birds: now and then a small flock crosses the sky over the water.
const BIRD_SHADER := preload("res://game/court/bird.gdshader")
const BIRD_SHEET := "res://assets/textures/beach_bird.png"
const FLOCK_GAP := Vector2(11.0, 22.0)    # s between flocks (random in this range)
const FLOCK_X := Vector2(18.0, 34.0)     # over the water
const FLOCK_Y := Vector2(6.0, 11.0)
const FLOCK_EDGE := 46.0                 # z where a flock enters / leaves
const BIRD_SPEED := 6.0
const BIRD_SIZE := Vector2(0.9, 0.68)
## A pelican (2026-10-03): solo, a little bigger and much slower than the
## gulls, a band above them, with a lazy flap, one every PELICAN_GAP.
const PELICAN_SHEET := "res://assets/textures/beach_pelican.png"
const PELICAN_GAP := Vector2(30.0, 70.0)
const PELICAN_X := Vector2(15.0, 28.0)
const PELICAN_Y := Vector2(11.5, 14.0)   # the gulls fly FLOCK_Y 6–11
const PELICAN_SPEED := 2.4
const PELICAN_SIZE := Vector2(1.25, 0.83)
const PELICAN_FLAP_HZ := 1.1
## Tourists: one raises an arm now and then; umbrellas sway a little.
const WAVE_GAP := Vector2(12.0, 25.0)
const WAVE_S := 2.2
## A cruise ship crossing the far horizon, and an airliner high over the water.
## Neither is a billboard: the ship must stay side-on, and the plane's sprite
## already points along its travel.
const SHIP_SHEET := "res://assets/textures/beach_ship.png"
const SHIP_GAP := Vector2(70.0, 140.0)
## Kept well inside the sky cylinder (SKY_R 60): the binding number is the
## radius at the spawn CORNER, sqrt(x^2 + edge^2), not x alone.
##
## Tuned against the device: at 11 m wide and 47 m out it read as being just
## offshore rather than on the horizon. Farther and much smaller fixes the
## scale, and the edge still has to clear the visible band (about z +-16.7 at
## this distance) or the ship pops into being on screen.
const SHIP_X := 50.0
const SHIP_Y := 0.45
const SHIP_EDGE := 20.0                  # corner radius 53.9, clears the frame
const SHIP_SIZE := Vector2(7.0, 1.0)
## A third of the old pace: it should take a couple of MINUTES to cross, the
## way something that size does.
const SHIP_SPEED := Vector2(0.20, 0.32)
const PLANE_SHEET := "res://assets/textures/beach_plane.png"
const PLANE_GAP := Vector2(45.0, 100.0)
const PLANE_X := Vector2(20.0, 32.0)
const PLANE_Y := Vector2(26.0, 36.0)
const PLANE_EDGE := 28.0
const PLANE_SIZE := Vector2(6.0, 1.5)
const PLANE_SPEED := Vector2(3.6, 5.4)
## A second jet, much higher and smaller, now and then (Ross, 2026-09-30).
## Near the sky cylinder's top (SKY_Y1 50): corner radius sqrt(42² + 30²) = 51.6.
const JET_GAP := Vector2(90.0, 200.0)
const JET_X := Vector2(28.0, 42.0)
const JET_Y := Vector2(42.0, 48.0)
const JET_EDGE := 30.0
const JET_SIZE := Vector2(3.6, 0.9)
const JET_SPEED := Vector2(6.0, 9.0)

var _ocean: MeshInstance3D
var _shore: MeshInstance3D
var _ocean_mat: ShaderMaterial
var _shore_mat: StandardMaterial3D
var _ocean_base_x := 0.0
var _shore_base_x := 0.0
var _t := 0.0
var _palm_mats: Array[ShaderMaterial] = []
var _palm_rigs: Array[Node3D] = []
var _palm_multis: Array[MultiMeshInstance3D] = []
var _birds: Array[MeshInstance3D] = []
var _bird_mats: Array[ShaderMaterial] = []
var _bird_vel: Array[Vector3] = []
var _bird_phase: Array[float] = []
var _bird_base_y: Array[float] = []
var _bird_root: Node3D
var _next_flock := 10.0
var _pelican: MeshInstance3D
var _pelican_mat: ShaderMaterial
var _pelican_vel := Vector3.ZERO
var _pelican_base_y := 0.0
var _next_pelican := 20.0
var _rng := RandomNumberGenerator.new()
var _arms: Array[Node3D] = []
var _arm_rest: Array[Vector3] = []
var _umbrellas: Array[Node3D] = []
var _next_wave := 8.0
var _wave_t := -1.0
var _wave_arm := -1
## Passers-by, the ship and the plane each get their OWN timer and list. The
## birds' single-flock gate (spawn only while the sky is empty) deliberately
## does not apply here, or one slow ship would block everything else.
var _fx_root: Node3D
var _ship: MeshInstance3D
var _ship_vel := 0.0
var _next_ship := 25.0
var _plane: MeshInstance3D
var _plane_vel := 0.0
var _next_plane := 30.0
var _jet: MeshInstance3D
var _jet_vel := 0.0
var _next_jet := 60.0


## Find Ocean (required) and Shore (optional) under the arena. False → don't attach.
func setup(arena: Node) -> bool:
	_ocean = arena.find_child("Ocean", true, false) as MeshInstance3D
	if _ocean == null:
		return false
	_ocean_mat = ShaderMaterial.new()
	_ocean_mat.shader = SHADER
	var tex := _albedo_of(_ocean)
	_ocean_mat.set_shader_parameter("water", tex if tex != null else load(WATER_FALLBACK))
	_ocean.material_override = _ocean_mat
	_ocean_base_x = _ocean.position.x

	_shore = arena.find_child("Shore", true, false) as MeshInstance3D
	if _shore != null:
		var foam := _albedo_of(_shore)
		_shore_mat = StandardMaterial3D.new()
		_shore_mat.albedo_texture = foam if foam != null else load(FOAM_FALLBACK)
		_shore_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_shore_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shore_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shore_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shore_mat.uv1_scale = Vector3(0.25, 1.0, 1.0)  # 4 m foam tiles instead of 1 m
		_shore.material_override = _shore_mat
		_shore_base_x = _shore.position.x

	for n in _descendants(arena):
		if n is Node3D and n.name.begins_with("PalmRig"):
			_palm_rigs.push_back(n as Node3D)
		elif n is Node3D and n.name.begins_with("Arm") and not (n is MeshInstance3D):
			_arms.push_back(n as Node3D)
			_arm_rest.push_back((n as Node3D).rotation)
		elif n is Node3D and n.name.begins_with("Umbrella") and not (n is MeshInstance3D):
			_umbrellas.push_back(n as Node3D)
		elif n is MeshInstance3D and n.name.begins_with("UmbMesh"):
			_skin_umbrella(n as MeshInstance3D)
	# PalmRig0.. in order, so instance i is rig i (the walk above is a stack).
	_palm_rigs.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.name) < str(b.name))
	_build_palms(arena)
	_bird_root = Node3D.new()
	_bird_root.name = "Birds"
	arena.add_child(_bird_root)
	_fx_root = Node3D.new()
	_fx_root.name = "BeachLife"
	arena.add_child(_fx_root)
	# Seeded, NOT randomize(): ambient life should replay identically so a QA
	# screenshot or a test is reproducible. The unseeded call this replaces was
	# the cause of test_ambient_life's long-standing ~7 % flake.
	_rng.seed = 0xBEAC_11FE
	_next_flock = _rng.randf_range(6.0, 14.0)
	_next_wave = _rng.randf_range(WAVE_GAP.x, WAVE_GAP.y)
	_next_ship = _rng.randf_range(12.0, 30.0)
	_next_plane = _rng.randf_range(20.0, 50.0)
	_next_jet = _rng.randf_range(40.0, 120.0)
	_next_pelican = _rng.randf_range(14.0, 40.0)   # drawn last: the older timers keep their seeded values
	return true


func bird_count() -> int:
	return _birds.size()


func arm_count() -> int:
	return _arms.size()


## A loose V of 3–6 gulls entering from one side of the sky, headed across.
func spawn_flock() -> void:
	_clear_birds()
	var from_left := _rng.randf() < 0.5
	var n := _rng.randi_range(3, 6)
	var x0 := _rng.randf_range(FLOCK_X.x, FLOCK_X.y)
	var y0 := _rng.randf_range(FLOCK_Y.x, FLOCK_Y.y)
	var dir := 1.0 if from_left else -1.0
	var sheet: Texture2D = load(BIRD_SHEET)
	for i in n:
		var mi := MeshInstance3D.new()
		mi.name = "Bird%d" % i
		var quad := QuadMesh.new()
		quad.size = BIRD_SIZE
		mi.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = BIRD_SHADER
		m.set_shader_parameter("sheet", sheet)
		m.set_shader_parameter("phase", _rng.randf())
		m.set_shader_parameter("flap_hz", _rng.randf_range(2.6, 3.6))
		m.set_shader_parameter("facing", dir)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# V formation: trailing birds sit behind and beside the leader.
		var rank := (i + 1) / 2
		var side := -1.0 if i % 2 == 1 else 1.0
		mi.position = Vector3(x0 + side * rank * 1.4, y0 - rank * 0.35, -dir * (FLOCK_EDGE + rank * 1.6))
		_bird_root.add_child(mi)
		_birds.push_back(mi)
		_bird_mats.push_back(m)
		_bird_vel.push_back(Vector3(0.0, 0.0, dir * BIRD_SPEED * _rng.randf_range(0.92, 1.08)))
		_bird_phase.push_back(_rng.randf() * TAU)
		_bird_base_y.push_back(mi.position.y)
	_next_flock = _rng.randf_range(FLOCK_GAP.x, FLOCK_GAP.y)


func pelican_count() -> int:
	return 1 if _pelican != null else 0


## One pelican, low over the water, crossing the sky at its own pace.
func spawn_pelican() -> void:
	_clear_pelican()
	var from_left := _rng.randf() < 0.5
	var dir := 1.0 if from_left else -1.0
	var mi := MeshInstance3D.new()
	mi.name = "Pelican"
	var quad := QuadMesh.new()
	quad.size = PELICAN_SIZE
	mi.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = BIRD_SHADER
	m.set_shader_parameter("sheet", load(PELICAN_SHEET))
	m.set_shader_parameter("phase", _rng.randf())
	m.set_shader_parameter("flap_hz", PELICAN_FLAP_HZ)
	m.set_shader_parameter("facing", dir)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(_rng.randf_range(PELICAN_X.x, PELICAN_X.y), _rng.randf_range(PELICAN_Y.x, PELICAN_Y.y), -dir * FLOCK_EDGE)
	_bird_root.add_child(mi)
	_pelican = mi
	_pelican_mat = m
	_pelican_vel = Vector3(0.0, 0.0, dir * PELICAN_SPEED)
	_pelican_base_y = mi.position.y
	_next_pelican = _rng.randf_range(PELICAN_GAP.x, PELICAN_GAP.y)


func _clear_pelican() -> void:
	if _pelican != null:
		_pelican.queue_free()
	_pelican = null
	_pelican_mat = null


func _step_pelican(dt: float) -> void:
	if _pelican == null:
		_next_pelican -= dt
		if _next_pelican <= 0.0:
			spawn_pelican()
		return
	_pelican.position += _pelican_vel * dt
	# A long, slow lift and settle, like a glide over the swell.
	_pelican.position.y = _pelican_base_y + 0.5 * sin(_t * 0.45)
	_pelican_mat.set_shader_parameter("t", _t)
	if absf(_pelican.position.z) >= FLOCK_EDGE + 4.0:
		_clear_pelican()


func _clear_birds() -> void:
	for b in _birds:
		b.queue_free()
	_birds.clear()
	_bird_mats.clear()
	_bird_vel.clear()
	_bird_phase.clear()
	_bird_base_y.clear()


func _step_birds(dt: float) -> void:
	if _birds.is_empty():
		_next_flock -= dt
		if _next_flock <= 0.0:
			spawn_flock()
		return
	var all_out := true
	for i in _birds.size():
		var b := _birds[i]
		b.position += _bird_vel[i] * dt
		# A slow bob. NOT dt-scaled into the position — that integrates into a
		# one-way drift and the gull never comes back down. Offset from a base.
		b.position.y = _bird_base_y[i] + 0.35 * sin(_t * 1.1 + _bird_phase[i])
		_bird_mats[i].set_shader_parameter("t", _t)
		if absf(b.position.z) < FLOCK_EDGE + 4.0:
			all_out = false
	if all_out:
		_clear_birds()


## Tourists: a random arm waves for WAVE_S now and then; umbrellas sway.
func _step_tourists(dt: float) -> void:
	for k in _umbrellas.size():
		_umbrellas[k].rotation.x = 0.035 * sin(0.7 * _t + k * 2.1)
		_umbrellas[k].rotation.z = 0.025 * sin(0.53 * _t + k * 1.3)
	if _arms.is_empty():
		return
	if _wave_t < 0.0:
		_next_wave -= dt
		if _next_wave <= 0.0:
			_wave_arm = _rng.randi_range(0, _arms.size() - 1)
			_wave_t = 0.0
		return
	_wave_t += dt
	var k := _wave_arm
	var env := sin(PI * clampf(_wave_t / WAVE_S, 0.0, 1.0))
	_arms[k].rotation = _arm_rest[k] + Vector3(0.0, 0.0, 0.45 * env * sin(_wave_t * 9.0))
	if _wave_t >= WAVE_S:
		_arms[k].rotation = _arm_rest[k]
		_wave_t = -1.0
		_next_wave = _rng.randf_range(WAVE_GAP.x, WAVE_GAP.y)


func has_ship() -> bool:
	return is_instance_valid(_ship)


func has_plane() -> bool:
	return is_instance_valid(_plane)


func has_jet() -> bool:
	return is_instance_valid(_jet)


## A flat, unshaded, alpha-cut sprite quad. Used for the things that must NOT
## billboard: the ship has to stay side-on as it crosses, and the plane's
## sprite already points along its travel.
func _flat_sprite(path: String, size: Vector2, dir: float, lit: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = not lit
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Face the court (-x) with the quad's width running along z; a negative x
	# scale mirrors it for the other direction without turning it edge-on.
	mi.rotation.y = -PI / 2.0
	if dir < 0.0:
		mi.scale.x = -1.0
	_fx_root.add_child(mi)
	return mi


func spawn_ship() -> void:
	if is_instance_valid(_ship):
		return
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	# Fog is left ON: at 52 m it keeps about half the ship, which is exactly the
	# hazy dusk silhouette a real one has out there.
	_ship = _flat_sprite(SHIP_SHEET, SHIP_SIZE, dir, true)
	_ship.name = "CruiseShip"
	_ship.position = Vector3(SHIP_X, SHIP_Y, -dir * SHIP_EDGE)
	_ship_vel = dir * _rng.randf_range(SHIP_SPEED.x, SHIP_SPEED.y)
	_next_ship = _rng.randf_range(SHIP_GAP.x, SHIP_GAP.y)


func spawn_plane() -> void:
	if is_instance_valid(_plane):
		return
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	# Fog OFF here: at this range it would wash a small dark shape out entirely.
	_plane = _flat_sprite(PLANE_SHEET, PLANE_SIZE, dir, false)
	_plane.name = "Airliner"
	_plane.position = Vector3(_rng.randf_range(PLANE_X.x, PLANE_X.y),
		_rng.randf_range(PLANE_Y.x, PLANE_Y.y), -dir * PLANE_EDGE)
	_plane_vel = dir * _rng.randf_range(PLANE_SPEED.x, PLANE_SPEED.y)
	_next_plane = _rng.randf_range(PLANE_GAP.x, PLANE_GAP.y)


func spawn_jet() -> void:
	if is_instance_valid(_jet):
		return
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	_jet = _flat_sprite(PLANE_SHEET, JET_SIZE, dir, false)
	_jet.name = "Jet"
	_jet.position = Vector3(_rng.randf_range(JET_X.x, JET_X.y),
		_rng.randf_range(JET_Y.x, JET_Y.y), -dir * JET_EDGE)
	_jet_vel = dir * _rng.randf_range(JET_SPEED.x, JET_SPEED.y)
	_next_jet = _rng.randf_range(JET_GAP.x, JET_GAP.y)


func _step_life(dt: float) -> void:
	# The ship, one at a time, crossing the horizon.
	if is_instance_valid(_ship):
		_ship.position.z += _ship_vel * dt
		if absf(_ship.position.z) > SHIP_EDGE + 1.0:
			_ship.queue_free()
			_ship = null
	else:
		_next_ship -= dt
		if _next_ship <= 0.0:
			spawn_ship()
	# The plane, likewise.
	if is_instance_valid(_plane):
		_plane.position.z += _plane_vel * dt
		if absf(_plane.position.z) > PLANE_EDGE + 1.0:
			_plane.queue_free()
			_plane = null
	else:
		_next_plane -= dt
		if _next_plane <= 0.0:
			spawn_plane()
	# The high jet, its own timer.
	if is_instance_valid(_jet):
		_jet.position.z += _jet_vel * dt
		if absf(_jet.position.z) > JET_EDGE + 1.0:
			_jet.queue_free()
			_jet = null
	else:
		_next_jet -= dt
		if _next_jet <= 0.0:
			spawn_jet()


static func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.push_back(n)
		for c in n.get_children():
			stack.push_back(c)
	return out


## The palms: palm.glb's two parts, each a MultiMesh with one instance per
## PalmRig (transform = the rig's, relative to the arena, times the part's
## own), under a `Palms` node on the arena. Two draws for all ten trees; both
## cast shadows (the near pair frames the hoop from the key).
func _build_palms(arena: Node) -> void:
	if _palm_rigs.is_empty() or not ResourceLoader.exists(PALM_GLB):
		return
	var parts := _glb_parts(PALM_GLB)
	if parts.is_empty():
		return
	var root := Node3D.new()
	root.name = "Palms"
	arena.add_child(root)
	for part in parts:
		var mesh: Mesh = part["mesh"]
		var mmi := MultiMeshInstance3D.new()
		var fronds: bool = str(part["name"]).begins_with("PalmFronds")
		mmi.name = "PalmFronds" if fronds else "PalmTrunks"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = _palm_rigs.size()
		# Written as the raw buffer (12 floats an instance, like ChainNet), which
		# the headless renderer keeps where set_instance_transform is dropped.
		var buf := PackedFloat32Array()
		buf.resize(_palm_rigs.size() * 12)
		for i in _palm_rigs.size():
			var xf := _rel_xform(_palm_rigs[i], arena) * (part["xform"] as Transform3D)
			var o := i * 12
			buf[o] = xf.basis.x.x
			buf[o + 1] = xf.basis.y.x
			buf[o + 2] = xf.basis.z.x
			buf[o + 3] = xf.origin.x
			buf[o + 4] = xf.basis.x.y
			buf[o + 5] = xf.basis.y.y
			buf[o + 6] = xf.basis.z.y
			buf[o + 7] = xf.origin.y
			buf[o + 8] = xf.basis.x.z
			buf[o + 9] = xf.basis.y.z
			buf[o + 10] = xf.basis.z.z
			buf[o + 11] = xf.origin.z
		mm.buffer = buf
		mmi.multimesh = mm
		var m := ShaderMaterial.new()
		m.shader = PALM_SHADER
		var smat := mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null
		if smat is BaseMaterial3D and (smat as BaseMaterial3D).albedo_texture != null:
			m.set_shader_parameter("tex", (smat as BaseMaterial3D).albedo_texture)
		m.set_shader_parameter("flutter", fronds)
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mmi)
		_palm_mats.push_back(m)
		_palm_multis.push_back(mmi)


## The umbrellas (design 34a): the glb carries COLOR_0 (the white / red gores,
## the dark ribs) under the dither texture, but the importer leaves the
## albedo-from-vertex-colour flag off when the material also has a texture,
## so the canopy came in plain white. Set it here; the dither samples nearest.
static func _skin_umbrella(mi: MeshInstance3D) -> void:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return
	var m := mi.mesh.surface_get_material(0)
	if m is BaseMaterial3D:
		(m as BaseMaterial3D).vertex_color_use_as_albedo = true
		(m as BaseMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS


## A glb's mesh parts with their transforms inside it: [{name, mesh, xform}].
static func _glb_parts(path: String) -> Array:
	var out := []
	var scene: PackedScene = load(path)
	if scene == null:
		return out
	var inst: Node = scene.instantiate()
	for n in _descendants(inst):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.push_back({"name": n.name, "mesh": (n as MeshInstance3D).mesh, "xform": _rel_xform(n as Node3D, inst)})
	inst.free()
	return out


## A node's transform relative to an ancestor (the arena root), from the
## node's own transform and its Node3D parents' up to, not including, `top`.
static func _rel_xform(n: Node3D, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var walk: Node = n
	while walk != null and walk != top:
		if walk is Node3D:
			xf = (walk as Node3D).transform * xf
		walk = walk.get_parent()
	return xf


func palm_count() -> int:
	return _palm_rigs.size()


## MultiMeshes drawing the palms (2: trunks + nuts, fronds).
func palm_draw_count() -> int:
	return _palm_multis.size()


static func _albedo_of(mi: MeshInstance3D) -> Texture2D:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return null
	var m := mi.mesh.surface_get_material(0)
	return (m as BaseMaterial3D).albedo_texture if m is BaseMaterial3D else null


## Current shoreline displacement (m) — exposed for probes/tests.
func tide_offset() -> float:
	return TIDE_AMP * sin(TAU * _t / TIDE_PERIOD)


func _process(dt: float) -> void:
	_t += dt
	_ocean_mat.set_shader_parameter("t", _t)
	for m in _palm_mats:
		m.set_shader_parameter("t", _t)
	_step_birds(dt)
	_step_pelican(dt)
	_step_tourists(dt)
	if _fx_root != null:
		_step_life(dt)
	var tide := tide_offset()
	_ocean.position.x = _ocean_base_x + tide
	if _shore != null:
		# Slow tide plus the fast wash of each arriving swell.
		_shore.position.x = _shore_base_x + tide + WASH_AMP * sin(WASH_RATE * _t)
		_shore_mat.uv1_offset.x = fmod(_t * FOAM_SCROLL, 1.0)
		# Foam breathes with the long swell.
		_shore_mat.albedo_color.a = 0.55 + 0.4 * (0.5 + 0.5 * sin(1.6 * _t))
