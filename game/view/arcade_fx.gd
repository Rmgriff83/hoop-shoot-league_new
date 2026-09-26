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
var _t := 0.0
var _screens: Array[ShaderMaterial] = []
var _marquees: Array[ShaderMaterial] = []
var _lights: Array[OmniLight3D] = []
var _bulb_mat: ShaderMaterial
var _flare := 0.0
var _bulbs := 0
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
	if _screens.is_empty() and _marquees.is_empty() and bulbs == 0:
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
