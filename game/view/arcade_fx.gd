class_name ArcadeFx
extends Node
## Presentation-only arcade-hall life: the machine row's screens, flashing
## backglasses, claw and ticket wheel (shaders off TIME, so nothing here runs
## per frame for them), plus a faint warm light on each side. Mirrors BeachFx;
## never touches the sim.

## The row's live meshes (tools/blender/cage_machines.py) and their shaders.
const MACHINE_SHADERS := {
	"HallMachinesGlow": preload("res://game/court/machine_glow.gdshader"),
	"HallMachineScreens": preload("res://game/court/machine_screen.gdshader"),
	"HallClaw": preload("res://game/court/machine_claw.gdshader"),
	"HallWheel": preload("res://game/court/machine_wheel.gdshader"),
}
## The design's glass is 13 %, but three.js blends in sRGB and we blend in linear
## light, where 13 % reads as fog. 4 % lands on the same colours over these bases.
const BODY_SHADER := preload("res://game/court/machine_body.gdshader")
const BODY_GRAIN := preload("res://assets/textures/cage_machine_grain.png")
const GLASS_COLOR := Color(0.867, 0.933, 1.0, 0.04)
## The claw's vertex shader moves it, so its box covers the whole case.
const CLAW_AABB := AABB(Vector3(-0.45, 0.75, -0.45), Vector3(0.9, 1.1, 0.9))
## Runner lights around the top of the arcade HALL (Bulb*), in place of the old
## sign over the cage. ONE shared material so they all batch; each bulb's
## position in the chase is an instance uniform, and the order comes from the
## ordinal baked into its name by build_cage.py's _hall_lights.
const BULB_SHADER := preload("res://game/court/bulb.gdshader")
const FLARE_S := 0.9
## The return arrows down the deck, two rows (DeckArrow%02dL / %02dR,
## build_cage.py ARROW_XS): chase() lights each step — both rows together —
## one after another from the top of the ramp back to the shooter, sweep
## after sweep for the whole game (Ross, 2026-10-18: it used to stop after
## three) until stop_chase() at the buzzer, each step flashing CHASE_HOLD
## and the next starting CHASE_STAGGER later.
const ARROW_SHADER := preload("res://game/court/deck_arrow.gdshader")
const ARROW_STEPS := 7   # the two past the ball gate went (design 32a, 2026-10-16)
const CHASE_STAGGER := 0.11
const CHASE_HOLD := 0.3
const CHASE_GAP := 0.3
var _t := 0.0
var _machines: Array[ShaderMaterial] = []
var _lights: Array[OmniLight3D] = []
var _bulb_mat: ShaderMaterial
var _flare := 0.0
var _bulbs := 0
var _arrows: Array[ShaderMaterial] = []
var _arrow_steps: Array[int] = []   # each arrow's step (the ordinal in its name)
var _steps := 0
var _chase_t := -1.0   # < 0: no chase running
## Seeded, not randomize(): ambient life should replay identically so a QA
## screenshot or a test is reproducible.
var _rng := RandomNumberGenerator.new()


## Bind the machine row, the bulbs and the arrows. False → nothing to run.
func setup(arena: Node) -> bool:
	_bind_machines(arena)
	# Runner lights: one material for all of them. The chase order is the ordinal
	# in the name (Bulb000, Bulb001, ...), which build_cage.py lays out as one
	# continuous path around the hall — reading it from the name rather than from
	# tree order is what keeps the runner from jumping about.
	var bulbs := 0
	for n in BeachFx._descendants(arena):
		if n is MeshInstance3D and n.name.begins_with("Bulb") and not n.name.begins_with("BulbWire"):
			if _bulb_mat == null:
				_bulb_mat = ShaderMaterial.new()
				_bulb_mat.shader = BULB_SHADER
			var mi2 := n as MeshInstance3D
			mi2.material_override = _bulb_mat
			mi2.set_instance_shader_parameter("bulb_index", float(String(mi2.name).substr(4).to_int()))
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bulbs += 1
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("count", float(bulbs))
	_bulbs = bulbs
	# The ceiling string lights (HallLights, one mesh along the hall's back
	# wall / ceiling corner, design 32a): a steady warm glow, no chase.
	var ceil_lights := arena.find_child("HallLights", true, false) as MeshInstance3D
	if ceil_lights != null:
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.9, 0.69)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.9, 0.69)
		lm.emission_energy_multiplier = 0.8
		ceil_lights.material_override = lm
		ceil_lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The return arrows: the step is the ordinal in the name (00 is the top of
	# the ramp, the last step is at the shooter's feet; L/R are its two rows).
	var arrows: Array[MeshInstance3D] = []
	for n in BeachFx._descendants(arena):
		if n is MeshInstance3D and n.name.begins_with("DeckArrow"):
			arrows.push_back(n)
	arrows.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return a.name < b.name)
	for mi3 in arrows:
		var step := String(mi3.name).substr(9, 2).to_int()
		_arrow_steps.push_back(step)
		_steps = maxi(_steps, step + 1)
		var m := ShaderMaterial.new()
		m.shader = ARROW_SHADER
		var base := mi3.mesh.surface_get_material(0) if mi3.mesh != null and mi3.mesh.get_surface_count() > 0 else null
		if base is BaseMaterial3D:
			m.set_shader_parameter("tex", (base as BaseMaterial3D).albedo_texture)
		m.set_shader_parameter("lit", 0.0)
		mi3.material_override = m
		mi3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arrows.push_back(m)
	if _machines.is_empty() and bulbs == 0 and _arrows.is_empty():
		return false
	_rng.seed = 0x5EED_CA6E
	# A faint glow from each run of machines on the back wall.
	for z in [-4.5, 4.5]:
		var l := OmniLight3D.new()
		l.name = "CabGlow%s" % ("L" if z < 0.0 else "R")
		l.light_color = Color(1.0, 0.72, 0.4)
		l.light_energy = 0.5
		l.omni_range = 5.0
		l.position = Vector3(10.4, 1.5, z)
		add_child(l)
		_lights.push_back(l)
	return true


## The six meshes of the machine row: the static one gets the grain, the glass
## blends, the rest get a shader that samples the same atlas. Materials per fx,
## so freeze() stills only the PiP's copy.
func _bind_machines(arena: Node) -> void:
	var body := arena.find_child("HallMachines", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		return
	var skin := body.mesh.surface_get_material(0) as BaseMaterial3D
	var atlas: Texture2D = skin.albedo_texture if skin != null else null
	var body_mat := ShaderMaterial.new()
	body_mat.shader = BODY_SHADER
	body_mat.set_shader_parameter("atlas", atlas)
	body_mat.set_shader_parameter("grain", BODY_GRAIN)
	body.material_override = body_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mesh_name: String in MACHINE_SHADERS:
		var mi := arena.find_child(mesh_name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = MACHINE_SHADERS[mesh_name]
		if mesh_name != "HallMachineScreens":
			m.set_shader_parameter("atlas", atlas)
		if mesh_name == "HallClaw":
			m.set_shader_parameter("k", mi.position.z)
			mi.custom_aabb = CLAW_AABB
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_machines.push_back(m)
	var glass := arena.find_child("HallMachineGlass", true, false) as MeshInstance3D
	if glass != null:
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm.albedo_color = GLASS_COLOR
		glass.material_override = gm
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The row's shader materials (one each: they read TIME and nobody writes them).
func machine_materials() -> Array[ShaderMaterial]:
	return _machines


func clock() -> float:
	return _t


func bulb_count() -> int:
	return _bulbs


func arrow_count() -> int:
	return _arrows.size()


func arrow_steps() -> int:
	return _steps


## How lit step i's arrows are right now (0 dim … 1 flashing).
func arrow_lit(step: int) -> float:
	for k in _arrows.size():
		if _arrow_steps[k] == step:
			var v = _arrows[k].get_shader_parameter("lit")
			return float(v) if v != null else 0.0
	return 0.0


func chasing() -> bool:
	return _chase_t >= 0.0


## One sweep's length: every step's start plus the last flash and a gap.
func chase_period() -> float:
	return (_steps - 1) * CHASE_STAGGER + CHASE_HOLD + CHASE_GAP


## Run the return arrows: lit in succession from the top of the ramp back to
## the shooter, looping until stop_chase() — the screens call this on GO.
func chase() -> void:
	if _arrows.is_empty():
		return
	_chase_t = 0.0
	_step_chase(0.0)


## The buzzer: the arrows go dim.
func stop_chase() -> void:
	_chase_t = -1.0
	for a in _arrows:
		a.set_shader_parameter("lit", 0.0)


func _step_chase(dt: float) -> void:
	if _chase_t < 0.0:
		return
	var period := chase_period()
	_chase_t = fmod(_chase_t + dt, period)
	for k in _arrows.size():
		var since := _chase_t - _arrow_steps[k] * CHASE_STAGGER
		# Snap on, fade off linearly: with the stagger a third of the hold,
		# the trail behind the head sits at ~0.63 and ~0.27 — the design's
		# ON / MID (orange) / LOW (ember) steps on the shader's colour ramp
		# (2026-10-16). The period ends a gap after the last step's flash, so
		# one sweep never overlaps the next.
		var lit := 1.0 - since / CHASE_HOLD if since >= 0.0 and since < CHASE_HOLD else 0.0
		_arrows[k].set_shader_parameter("lit", lit)


## The string lights surge. Replaces the old marquee sign's MarqueePulse clip,
## which went with the sign — the screens call this on heat-up instead.
func flare() -> void:
	_flare = FLARE_S


## The PiP's static cage (CourtGeometry.Profile.PIP): the machine row and the
## bulbs at one instant, the lights steady, no chase — and nothing runs per frame.
var frozen := false   # CourtGeometry.Profile.PIP: built, then still


func freeze() -> void:
	frozen = true
	for m in _machines:
		m.set_shader_parameter("rate", 0.0)
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("t", 0.0)
		_bulb_mat.set_shader_parameter("flare", 0.0)
	set_process(false)


func _process(dt: float) -> void:
	_t += dt
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("t", _t)
		if _flare > 0.0:
			_flare = maxf(0.0, _flare - dt)
		_bulb_mat.set_shader_parameter("flare", 0.8 * (_flare / FLARE_S))
	for k in _lights.size():
		_lights[k].light_energy = 0.45 + 0.1 * sin(_t * 2.3 + k * 1.7)
	_step_chase(dt)
