class_name ArcadeFx
extends Node
## Presentation-only arcade-hall life: the side-wall cabinets' screens run
## attract-mode games (arcade_screen.gdshader) and their marquees chase
## bulbs (marquee_chase.gdshader), all off one running clock, plus a faint
## warm light on each side. Mirrors BeachFx; never touches the sim.

const SCREEN_SHADER := preload("res://game/court/arcade_screen.gdshader")
const MARQUEE_SHADER := preload("res://game/court/marquee_chase.gdshader")
const PALETTES := [Color(1.0, 0.75, 0.3), Color(0.4, 1.0, 0.55), Color(0.55, 0.8, 1.0), Color(1.0, 0.45, 0.4)]
const MARQUEE_TINTS := [Color(1.0, 0.8, 0.35), Color(0.9, 0.35, 0.3), Color(0.5, 0.75, 1.0), Color(0.95, 0.55, 0.9)]
## Runner lights around the top of the arcade HALL (Bulb*), in place of the old
## sign over the cage. ONE shared material so they all batch; each bulb's
## position in the chase is an instance uniform, and the order comes from the
## ordinal baked into its name by build_cage.py's _hall_lights.
const BULB_SHADER := preload("res://game/court/bulb.gdshader")
const FLARE_S := 0.9
## The return arrows down the deck, two rows (DeckArrow%02dL / %02dR,
## build_cage.py ARROW_XS): chase() lights each step — both rows together —
## one after another from the top of the ramp back to the shooter,
## CHASE_PASSES sweeps, each step flashing CHASE_HOLD and the next starting
## CHASE_STAGGER later.
const ARROW_SHADER := preload("res://game/court/deck_arrow.gdshader")
const ARROW_STEPS := 9
const CHASE_STAGGER := 0.11
const CHASE_HOLD := 0.3
const CHASE_GAP := 0.3
const CHASE_PASSES := 3
var _t := 0.0
var _screens: Array[ShaderMaterial] = []
var _marquees: Array[ShaderMaterial] = []
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


## Bind every CabScreen* / CabMarquee* under the arena. False → nothing to run.
func setup(arena: Node) -> bool:
	var i := 0
	for n in BeachFx._descendants(arena):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.name.begins_with("CabScreen"):
			var m := ShaderMaterial.new()
			m.shader = SCREEN_SHADER
			m.set_shader_parameter("game", float(i % 4))
			m.set_shader_parameter("phase", 3.7 * i)
			m.set_shader_parameter("palette", PALETTES[i % PALETTES.size()])
			mi.material_override = m
			_screens.push_back(m)
			i += 1
		elif mi.name.begins_with("CabMarquee"):
			var m := ShaderMaterial.new()
			m.shader = MARQUEE_SHADER
			m.set_shader_parameter("phase", 1.9 * _marquees.size())
			m.set_shader_parameter("tint", MARQUEE_TINTS[_marquees.size() % MARQUEE_TINTS.size()])
			mi.material_override = m
			_marquees.push_back(m)
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
	if _screens.is_empty() and _marquees.is_empty() and bulbs == 0 and _arrows.is_empty():
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


func screen_count() -> int:
	return _screens.size()


func marquee_count() -> int:
	return _marquees.size()


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
## the shooter, CHASE_PASSES times — the screens call this on GO.
func chase() -> void:
	if _arrows.is_empty():
		return
	_chase_t = 0.0
	_step_chase(0.0)


func _step_chase(dt: float) -> void:
	if _chase_t < 0.0:
		return
	_chase_t += dt
	var period := chase_period()
	var done := _chase_t >= CHASE_PASSES * period
	for k in _arrows.size():
		var i := _arrow_steps[k]
		var lit := 0.0
		if not done:
			for pass_i in CHASE_PASSES:
				var since := _chase_t - (pass_i * period + i * CHASE_STAGGER)
				if since >= 0.0 and since < CHASE_HOLD:
					# Snap on, ease off.
					lit = maxf(lit, 1.0 - (since / CHASE_HOLD) * (since / CHASE_HOLD))
		_arrows[k].set_shader_parameter("lit", lit)
	if done:
		_chase_t = -1.0


## The string lights surge. Replaces the old marquee sign's MarqueePulse clip,
## which went with the sign — the screens call this on heat-up instead.
func flare() -> void:
	_flare = FLARE_S


func _process(dt: float) -> void:
	_t += dt
	for m in _screens:
		m.set_shader_parameter("t", _t)
	for m in _marquees:
		m.set_shader_parameter("t", _t)
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("t", _t)
		if _flare > 0.0:
			_flare = maxf(0.0, _flare - dt)
		_bulb_mat.set_shader_parameter("flare", 0.8 * (_flare / FLARE_S))
	for k in _lights.size():
		_lights[k].light_energy = 0.45 + 0.1 * sin(_t * 2.3 + k * 1.7)
	_step_chase(dt)
