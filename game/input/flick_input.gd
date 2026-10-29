class_name FlickInput
extends Node
## Full-screen gesture capture: press in the lower grab zone to pick up, flick
## upward and release to shoot. Listens in _unhandled_input (not Control GUI) —
## robust regardless of scene structure, and UI Buttons above still consume
## their clicks first. Handles ONLY touch events: the project enables
## emulate_touch_from_mouse, so mouse input (real or injected) always arrives
## as touch too, and handling both would double-process every gesture.
##
## The release speed MEASURES THE FLICK (2026-10-25; docs/HOME.md → The
## flick). Drag events arrive about once per frame (the engine accumulates
## input), and a real flick is three to six of them. The old 40 ms EMA, read
## once at lift-off, ramped up from the pull-down's momentum and never
## caught a short flick, then decayed by the random delivery gap before the
## touch-up — the same gesture read 65–100 % of itself. Now:
##  • the speed is the finger's travel over the last WINDOW_S before the
##    latest drag (a finite difference over a short fixed window: no ramp,
##    no momentum from the pull), and the release takes the FASTEST such
##    window of the final PEAK_HOLD_S — a finger slows as it leaves the glass;
##  • a gap longer than REST_S between drags is a rest (the finger stopped):
##    the window restarts there (the first move after it cannot latch; the
##    charge still follows the finger), and a rest longer than HOLD_S right before lift-off is a
##    deliberate soft hold (the speed decays from the hold's start); shorter
##    gaps are delivery latency and change nothing;
##  • the wind-up latch decides on that same honest speed, with hysteresis,
##    and on latching gives the charge back what the turn's first frames
##    drained (`_charge_at_turn`), so the arc at release is the arc aimed.
## A 40 ms EMA survives only for the curl (visual roll) and as `ema_sh` in
## the sample, the old reading, for the calibration trace.

signal grab_pressed
## Finger position (band px) while holding — fired on the press and every
## drag event, so the held ball can follow the finger.
signal drag_moved(pos: Vector2)
## Wind-up charge (px): accumulated from finger motion that is predominantly
## VERTICAL — pulling down charges, easing back up discharges, sideways motion
## changes nothing (so a thumb arcing across the screen can't sneak in charge).
## Latched the moment the upward flick starts, so the throw doesn't drain it.
## Fired on the press (0) and every drag, for the arc preview.
signal windup_changed(pull_px: float)
## Live throw strength while the flick is under way: the window speed in
## screen-heights/s — the same quantity the release sample carries — and
## `latched` says the throw has actually begun (below that, the finger is
## still pulling back and the speed means nothing about power).
signal flick_charging(speed_sh: float, latched: bool)
signal flick_released(sample: Dictionary)

## The speed window (s): the finger's travel over this long before the latest drag.
const WINDOW_S := 0.05
## The release takes the fastest window seen this long before the last drag.
const PEAK_HOLD_S := 0.08
## A gap between drags longer than this is a rest (the finger stopped).
const REST_S := 0.05
## A rest right before lift-off longer than this is a deliberate soft hold.
const HOLD_S := 0.08
## The curl's EMA time constant (s), and the legacy reading's.
const TAU_SMOOTH := 0.04
## Presses above this fraction of the screen height are ignored (UI zone).
const GRAB_ZONE_TOP_FRAC := 0.45
## Below this speed (px/s) the heading is noise; curl isn't sampled.
const MIN_HEADING_SPEED := 60.0
## Upward speed (screen-heights/s) at which the wind-up charge latches: slower
## upward motion is "easing off the pull" and discharges; faster is the throw.
const FLICK_LATCH_SH := 0.5
## Once latched, the throw stays latched until the upward speed falls under
## this (or the finger moves down again): a wobble mid-flick is not a new pull.
const FLICK_UNLATCH_SH := 0.25

var _tracking := false
var _press_pos := Vector2.ZERO
var _press_usec := 0
var _last_pos := Vector2.ZERO
var _last_usec := 0
## The drag samples since the last rest, newest last: [[usec, pos], …].
var _trail: Array = []
## Every sample of the gesture, press first: [[usec, x, y], …] — the
## sample's `trace`, so a release can be replayed (tools/flick_trace.gd).
var _log: Array = []
## The window velocity (px/s) at the latest drag; zero right after a rest.
var _win_vel := Vector2.ZERO
## The upward-dominant window speeds (px/s) of the final stretch: [[usec, speed], …].
var _peaks: Array = []
## The legacy EMA (the old reading, for the trace) and the curl's.
var _ema := Vector2.ZERO
## Signed rate of change of the velocity heading, rad/s (EMA).
## A curled/whipped flick has a large |curl|; a straight one is ~0.
var _curl := 0.0
## Wind-up charge (px): live pull while adjusting, frozen once the flick starts.
var _charge := 0.0
## The charge when the finger last moved DOWN: what the latch restores.
var _charge_at_turn := 0.0
var _latched := false
## Total finger travel (px) — a real dead zone (a wind-up-and-flick can end
## near where it started, so net travel would wrongly read as a tap).
var _path_len := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin(UiLayout.from_screen(event.position))   # screen → the band (the HUD's space)
		else:
			_end()
	elif event is InputEventScreenDrag and _tracking:
		_move(UiLayout.from_screen(event.position))


func _begin(pos: Vector2) -> void:
	_begin_at(pos, Time.get_ticks_usec())


func _move(pos: Vector2) -> void:
	_move_at(pos, Time.get_ticks_usec())


func _end() -> void:
	_end_at(Time.get_ticks_usec())


func _begin_at(pos: Vector2, now: int) -> void:
	var view_h := UiLayout.DESIGN.y   # the design height: the feel is the same on every screen
	if pos.y < view_h * GRAB_ZONE_TOP_FRAC:
		return
	_tracking = true
	_press_pos = pos
	_last_pos = pos
	_press_usec = now
	_last_usec = now
	_trail = [[now, pos]]
	_log = [[now, pos.x, pos.y]]
	_win_vel = Vector2.ZERO
	_peaks = []
	_ema = Vector2.ZERO
	_curl = 0.0
	_charge = 0.0
	_charge_at_turn = 0.0
	_latched = false
	_path_len = 0.0
	grab_pressed.emit()
	drag_moved.emit(pos)
	windup_changed.emit(0.0)


func _move_at(pos: Vector2, now: int) -> void:
	if not _tracking:
		return
	var dt := (now - _last_usec) / 1_000_000.0
	if dt <= 0.0:
		return
	var delta := pos - _last_pos
	var rested := dt > REST_S
	if rested:
		_trail.clear()   # the finger stopped: the window starts again here
	_trail.push_back([now, pos])
	_log.push_back([now, pos.x, pos.y])
	while _trail.size() > 2 and (now - int(_trail[1][0])) / 1_000_000.0 > WINDOW_S:
		_trail.pop_front()
	_win_vel = _window_velocity(now)
	# The legacy EMA and the curl (visual), fed the instantaneous velocity.
	var inst := delta / dt
	var alpha := 1.0 - exp(-dt / TAU_SMOOTH)
	var prev_ema := _ema
	_ema = _ema.lerp(inst, alpha)
	if not rested and prev_ema.length() > MIN_HEADING_SPEED and _ema.length() > MIN_HEADING_SPEED:
		_curl = lerpf(_curl, prev_ema.angle_to(_ema) / dt, alpha)
	_path_len += delta.length()
	_last_pos = pos
	_last_usec = now
	drag_moved.emit(pos)
	# The fastest upward-dominant window of the final stretch.
	if -_win_vel.y > absf(_win_vel.x) and _win_vel.length() > 0.0:
		_peaks.push_back([now, _win_vel.length()])
	while not _peaks.is_empty() and (now - int(_peaks[0][0])) / 1_000_000.0 > PEAK_HOLD_S:
		_peaks.pop_front()
	# Wind-up: +y is down. Only the vertical part of predominantly-vertical
	# motion counts: pull down → charge, ease up → discharge, sideways → nothing.
	# The throw latches on the window speed and stays latched (hysteresis);
	# latching restores the charge the turn's first upward frames drained.
	var view_h := UiLayout.DESIGN.y
	var up_sh := -_win_vel.y / view_h
	if _latched:
		if up_sh < FLICK_UNLATCH_SH or delta.y > 0.0:
			_latched = false
	elif up_sh >= FLICK_LATCH_SH:
		_latched = true
		_charge = _charge_at_turn
	# The charge follows the finger's displacement whatever the timing: a slow
	# pull sends sparse events (gaps over REST_S) and must still charge. The
	# first upward frame after a hold may drain a little; the latch, a frame
	# later, gives it back.
	if not _latched:
		var heading := _win_vel if _win_vel.length() > MIN_HEADING_SPEED else delta
		if absf(heading.y) > absf(heading.x):
			_charge = maxf(0.0, _charge + delta.y)
		if delta.y > 0.0:
			_charge_at_turn = _charge   # still pulling: this is the charge a throw keeps
	windup_changed.emit(_charge)
	flick_charging.emit(_win_vel.length() / view_h, _latched)


## The finger's velocity over the trail's window: the newest sample against
## the oldest one still inside WINDOW_S (zero with a single sample, i.e.
## right after a rest — the flick's true start is unknowable then).
func _window_velocity(now: int) -> Vector2:
	if _trail.size() < 2:
		return Vector2.ZERO
	var oldest: Array = _trail[0]
	var newest: Array = _trail[_trail.size() - 1]
	var span := (int(newest[0]) - int(oldest[0])) / 1_000_000.0
	if span <= 0.0:
		return Vector2.ZERO
	return ((newest[1] as Vector2) - (oldest[1] as Vector2)) / span


func _end_at(now: int) -> void:
	if not _tracking:
		return
	_tracking = false
	var view_h := UiLayout.DESIGN.y
	var idle := (now - _last_usec) / 1_000_000.0
	# The release: the latest window's direction at the fastest window's speed
	# of the final stretch. A rest before lift-off longer than HOLD_S is a
	# deliberate soft hold, decayed from the hold's start; a shorter gap is
	# delivery latency and changes nothing.
	var peak := _win_vel.length()
	for p in _peaks:
		peak = maxf(peak, float(p[1]))
	var vel := _win_vel.normalized() * peak if _win_vel.length() > 0.0 else Vector2.ZERO
	var ema := _ema
	if idle > HOLD_S:
		var decay := 1.0 - exp(-(idle - HOLD_S) / TAU_SMOOTH)
		vel = vel.lerp(Vector2.ZERO, decay)
		_curl = lerpf(_curl, 0.0, decay)
	if idle > 0.0:
		ema = ema.lerp(Vector2.ZERO, 1.0 - exp(-idle / TAU_SMOOTH))   # the old reading, as it was
	var travel := _last_pos - _press_pos
	var sample := {
		"vel_x": vel.x,
		"vel_y": vel.y,
		"speed_sh": vel.length() / view_h,   # the honest release speed
		"peak_sh": peak / view_h,
		"ema_sh": ema.length() / view_h,     # the old reading (the calibration trace)
		"held_s": idle,
		"travel_x": travel.x,
		"travel_y": travel.y,
		"pos_x": _last_pos.x,   # release point (band px) — aim-by-pointing origin
		"pos_y": _last_pos.y,
		"curl": _curl,          # rad/s heading turn rate — visual roll
		"pull_px": _charge,     # wind-up charge at the start of the throw — arc
		"path_px": _path_len,   # total travel — dead zone
		"duration_s": (now - _press_usec) / 1_000_000.0,
		"viewport_h": view_h,   # the design height (the canvas may be taller)
		"lift_usec": now,
		"trace": _log,          # the whole gesture, for the replay tool
	}
	flick_released.emit(sample)
