class_name FlickInput
extends Node
## Full-screen gesture capture: press in the lower grab zone to pick up, flick
## upward and release to shoot. Listens in _unhandled_input (not Control GUI) —
## robust regardless of scene structure, and UI Buttons above still consume
## their clicks first. Handles ONLY touch events: the project enables
## emulate_touch_from_mouse, so mouse input (real or injected) always arrives
## as touch too, and handling both would double-process every gesture.
## Pointer velocity is smoothed with a time-corrected EMA
## (alpha = 1 − exp(−dt/TAU)) so 60 Hz mouse and 120 Hz touch feel identical.

signal grab_pressed
## Finger position (screen px) while holding — fired on the press and every
## drag event, so the held ball can follow the finger.
signal drag_moved(pos: Vector2)
## Wind-up charge (px): accumulated from finger motion that is predominantly
## VERTICAL — pulling down charges, easing back up discharges, sideways motion
## changes nothing (so a thumb arcing across the screen can't sneak in charge).
## Latched the moment the upward flick starts, so the throw doesn't drain it.
## Fired on the press (0) and every drag, for the arc preview.
signal windup_changed(pull_px: float)
## Live throw strength while the flick is under way. `speed_sh` is the smoothed
## pointer speed in screen-heights/s — the same quantity the release sample
## carries — and `latched` says the throw has actually begun (below that, the
## finger is still pulling back and the speed means nothing about power).
## The EMA lags ~40 ms and so reads LOW while accelerating: this is a feel cue
## for a live gauge, never the verdict. The value at flick_released is honest.
signal flick_charging(speed_sh: float, latched: bool)
signal flick_released(sample: Dictionary)

## EMA time constant (s) — frame-rate-independent equivalent of the old
## per-event SMOOTH=0.45 at 60 fps.
const TAU_SMOOTH := 0.04
## Presses above this fraction of the screen height are ignored (UI zone).
const GRAB_ZONE_TOP_FRAC := 0.45

## Below this smoothed speed (px/s) the heading is noise; curl isn't sampled.
const MIN_HEADING_SPEED := 60.0
## Upward speed (screen-heights/s) at which the wind-up charge latches: slower
## upward motion is "easing off the pull" and discharges; faster is the throw.
const FLICK_LATCH_SH := 0.5

var _tracking := false
var _press_pos := Vector2.ZERO
var _press_usec := 0
var _last_pos := Vector2.ZERO
var _last_usec := 0
var _vel := Vector2.ZERO
## Signed rate of change of the velocity heading, rad/s (same EMA as _vel).
## A curled/whipped flick has a large |curl|; a straight one is ~0.
var _curl := 0.0
## Wind-up charge (px): live pull while adjusting, frozen once the flick starts.
var _charge := 0.0
var _latched := false
## Total finger travel (px) — a real dead zone (a wind-up-and-flick can end
## near where it started, so net travel would wrongly read as a tap).
var _path_len := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin(event.position)
		else:
			_end()
	elif event is InputEventScreenDrag and _tracking:
		_move(event.position)


func _begin(pos: Vector2) -> void:
	var view_h := get_viewport().get_visible_rect().size.y
	if pos.y < view_h * GRAB_ZONE_TOP_FRAC:
		return
	_tracking = true
	_press_pos = pos
	_last_pos = pos
	_press_usec = Time.get_ticks_usec()
	_last_usec = _press_usec
	_vel = Vector2.ZERO
	_curl = 0.0
	_charge = 0.0
	_latched = false
	_path_len = 0.0
	grab_pressed.emit()
	drag_moved.emit(pos)
	windup_changed.emit(0.0)


func _move(pos: Vector2) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_usec) / 1_000_000.0
	if dt <= 0.0:
		return
	var delta := pos - _last_pos
	var inst := delta / dt
	var alpha := 1.0 - exp(-dt / TAU_SMOOTH)
	var prev_vel := _vel
	_vel = _vel.lerp(inst, alpha)
	# Curl: how fast the heading is turning. Only meaningful once the finger is
	# actually moving, otherwise the heading of a near-zero vector is noise.
	if prev_vel.length() > MIN_HEADING_SPEED and _vel.length() > MIN_HEADING_SPEED:
		_curl = lerpf(_curl, prev_vel.angle_to(_vel) / dt, alpha)
	_path_len += (pos - _last_pos).length()
	_last_pos = pos
	_last_usec = now
	drag_moved.emit(pos)
	# Wind-up: +y is down. Only the vertical part of predominantly-vertical
	# motion counts: pull down → charge, ease up → discharge, sideways → nothing.
	# Once the upward speed crosses the latch threshold the throw has begun and
	# the charge freezes; slowing down again (aborted throw) resumes tracking.
	var view_h := get_viewport().get_visible_rect().size.y
	var up_sh := -_vel.y / view_h
	if up_sh >= FLICK_LATCH_SH:
		_latched = true
	else:
		_latched = false
		var heading := _vel if _vel.length() > MIN_HEADING_SPEED else delta
		if absf(heading.y) > absf(heading.x):
			_charge = maxf(0.0, _charge + delta.y)
	windup_changed.emit(_charge)
	flick_charging.emit(_vel.length() / view_h, _latched)


func _end() -> void:
	if not _tracking:
		return
	_tracking = false
	var now := Time.get_ticks_usec()
	# Drag events stop when the finger stops, so a pause before lift-off would
	# otherwise release with the last fast sample. Treat the idle gap as zero
	# velocity fed through the same EMA, so a deliberate hold means a soft shot.
	var idle := (now - _last_usec) / 1_000_000.0
	if idle > 0.0:
		var decay := 1.0 - exp(-idle / TAU_SMOOTH)
		_vel = _vel.lerp(Vector2.ZERO, decay)
		_curl = lerpf(_curl, 0.0, decay)
	var travel := _last_pos - _press_pos
	var sample := {
		"vel_x": _vel.x,
		"vel_y": _vel.y,
		"travel_x": travel.x,
		"travel_y": travel.y,
		"pos_x": _last_pos.x,   # release point (screen px) — aim-by-pointing origin
		"pos_y": _last_pos.y,
		"curl": _curl,          # rad/s heading turn rate — visual roll
		"pull_px": _charge,     # wind-up charge at the start of the throw — arc
		"path_px": _path_len,   # total travel — dead zone
		"duration_s": (now - _press_usec) / 1_000_000.0,
		"viewport_h": get_viewport().get_visible_rect().size.y,
	}
	flick_released.emit(sample)
