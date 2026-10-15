class_name AimReadout
extends Control
## Shot help's two numbers: the launch arc in degrees, and beneath it how far
## the shot would carry as a percentage of the distance to the rim (100 % =
## drops in).
##
## They hold the HEIGHT the wind-up started at while tracking the ball
## sideways. The ball sinks toward the bottom of the screen as you pull, so a
## readout that followed it vertically would drift away exactly when you are
## reading it — but it also slides left and right under your thumb, and one
## that ignored that would drift off the ball. The caller composes that anchor;
## the maths still solve from the live hand, because that is where the ball
## actually leaves from.
##
## Both are colour-coded from the real ballistics rather than from hardcoded
## thresholds, so they stay honest as the board slides and at every arena's
## distance. See _arc_color() and _power_color() for what green/amber/red mean.
##
## The arc reads live from the grab, but stays NEUTRAL while you pull — it is
## not passing judgement on an arc you are still choosing. The POWER number
## cannot exist until the throw starts (there is no speed to report while you
## are still pulling back), so it stays hidden until the flick latches. Both
## then colour together, run live for the ~130 ms of the throw, and freeze at
## the released values so you can tie the numbers to the outcome.
##
## This is the project's first projected-text component: it takes PropIcons'
## world→screen guard and Hud's label styling. Two rules learned elsewhere and
## repeated here because both fail by silently vanishing:
##   * unproject_position() returns mirrored garbage for points BEHIND the
##     camera, so is_position_behind() must be checked first.
##   * writing `position` every frame is only safe under PRESET_TOP_LEFT
##     (see the comment in game/view/hud.gd).

## Seconds the frozen numbers hold after release, and the tail spent fading.
const HOLD_S := 0.8
const FADE_S := 0.3
const FONT_SIZE := 27
## Screen offset from the projected anchor, and the gap between the two lines.
## Sits BELOW the grab height, closer to where the ball ends up once you have
## pulled, rather than floating above the point you first touched.
const OFFSET := Vector2(-34.0, 44.0)
const LINE_GAP := 34.0

const COL_IDLE := Color(0.85, 0.9, 1.0)
const COL_GREEN := Color(0.45, 0.95, 0.55)
const COL_AMBER := Color(1.0, 0.78, 0.3)
const COL_RED := Color(1.0, 0.45, 0.45)

var _cam: Camera3D
var _arc: Label
var _power: Label
## Last aim context, so a power sample can be scored without re-plumbing it.
var _angle := 0.0
var _dist := 0.0
var _rise := 0.0
var _anchor := Vector3.ZERO
var _have_aim := false
var _hold := 0.0


func setup(cam: Camera3D) -> void:
	_cam = cam
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat a flick
	_arc = _make_label()
	_power = _make_label()


func _make_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", COL_IDLE)
	# The outline is what keeps small text readable over the cage's chain-link.
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l.visible = false
	add_child(l)
	return l


## Live arc, called while the ball is held. `anchor` is the world point to pin
## to; `origin` is the real release point the shot solves from.
func aim(anchor: Vector3, angle_deg: float, origin: Vector3, geo: SimGeometry) -> void:
	var dx := geo.hoop_x - origin.x
	var dz := geo.hoop_z - origin.z
	_dist = sqrt(dx * dx + dz * dz)
	_rise = geo.hoop_y - origin.y
	_angle = angle_deg
	_anchor = anchor
	_have_aim = _dist > 1e-6
	if not _have_aim:
		clear()
		return
	if _hold > 0.0:
		return  # a frozen verdict owns the labels until it fades
	_arc.text = "%d°" % roundi(angle_deg)
	_arc.add_theme_color_override("font_color", COL_IDLE)
	_arc.visible = true


## Live throw strength during the flick. Hidden until the throw has actually
## begun: the pointer speed while still pulling DOWN says nothing about power.
func power(speed_sh: float, latched: bool, tuning: FlickTuning) -> void:
	if not _have_aim or _hold > 0.0:
		return
	if not latched:
		# Aborted throw (the finger slowed again): back to a neutral verdict.
		_power.visible = false
		_arc.add_theme_color_override("font_color", COL_IDLE)
		return
	_show_power(speed_sh, tuning)


## Freeze both numbers at what the release actually produced and hold them.
func freeze(speed_sh: float, tuning: FlickTuning) -> void:
	if not _have_aim:
		clear()
		return
	_show_power(speed_sh, tuning)
	_hold = HOLD_S + FADE_S


func clear() -> void:
	_hold = 0.0
	_have_aim = false
	if _arc != null:
		_arc.visible = false
	if _power != null:
		_power.visible = false


## Both verdicts land together, once the throw has begun.
func _show_power(speed_sh: float, tuning: FlickTuning) -> void:
	var speed := FlickMap.anchored_speed(_dist, _rise, speed_sh, tuning)
	var pct := reach_pct(_angle, speed, _dist, _rise)
	_power.text = "%d%%" % roundi(pct)
	_power.add_theme_color_override("font_color", _power_color(pct))
	_power.visible = true
	_arc.add_theme_color_override("font_color", _arc_color(_angle))


## How far the shot carries, as a percentage of the distance to the rim.
## 100 % drops through the ring's centre.
static func reach_pct(angle_deg: float, speed: float, dist: float, rise: float) -> float:
	if dist < 1e-6 or is_nan(speed):
		return 0.0
	var th := deg_to_rad(angle_deg)
	var vh := speed * cos(th)
	var vy := speed * sin(th)
	var g: float = SimConstants.G
	var disc := vy * vy - 2.0 * g * rise
	# Descending crossing of rim height — or, for a shot too flat to ever get
	# that high, the apex, so the number stays continuous and honestly short
	# instead of undefined.
	var t: float = (vy + sqrt(disc)) / g if disc >= 0.0 else vy / g
	return (vh * t) / dist * 100.0


## Red when NO flick strength could reach this arc; amber when there is barely
## any headroom left; green otherwise. Derived from the live geometry so it
## stays true for a sliding board and at every arena distance.
func _arc_color(angle_deg: float) -> Color:
	var anchor := Ballistics.speed_for_angle(FlickMap.ANCHOR_ANGLE_DEG, _dist, _rise)
	if is_nan(anchor):
		return COL_IDLE
	var need := Ballistics.speed_for_angle(angle_deg, _dist, _rise)
	var ceiling: float = FlickMap.V_MAX_FRAC * anchor
	if is_nan(need) or need > ceiling:
		return COL_RED
	if need > ceiling * 0.88:
		return COL_AMBER
	return COL_GREEN


## Green inside the clean-entry window — the ball drops through without touching
## iron. Deliberately ASYMMETRIC beyond that: amber runs further long than
## short, because the backboard turns overshoots into banks while undershoots
## just hit front rim.
func _power_color(pct: float) -> Color:
	var w: float = (SimConstants.R_RIM - SimConstants.R_BALL) / _dist * 100.0
	var d := pct - 100.0
	if absf(d) <= w:
		return COL_GREEN
	if d >= -2.0 * w and d <= 3.5 * w:
		return COL_AMBER
	return COL_RED


func _process(dt: float) -> void:
	if _hold > 0.0:
		_hold -= dt
		if _hold <= 0.0:
			clear()
			return
		modulate.a = clampf(_hold / FADE_S, 0.0, 1.0)
	else:
		modulate.a = 1.0
	if not _arc.visible and not _power.visible:
		return
	if _cam == null or not _cam.is_inside_tree() or _cam.is_position_behind(_anchor):
		_arc.visible = false
		_power.visible = false
		return
	var p := _cam.unproject_position(_anchor) + OFFSET
	_arc.position = p
	_power.position = p + Vector2(0.0, LINE_GAP)
