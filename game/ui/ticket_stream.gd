class_name TicketStream
extends Control
## The ticket stream (designs "Time Trial Results" 7a and "League Match End"
## 15a, 2026-10-24): a handful of ticket icons arc one after another from the
## score into the gold ticket box — one per two tickets, fifteen at most — and
## the box's count ticks up as each one lands, so a bigger haul means a longer
## stream. Pure `_draw` on a clock (`step(dt)`; `_process` drives it unless
## `manual`), like Confetti, so QA snaps are deterministic. The design's
## keyframes: a flyer appears big (×1.5) at its start with a tilt, is fully
## up by 12 %, passes a raised midpoint at 55 % (×1.1, counter-tilt), lands
## small (×0.55) and gone at 100 %, all on an ease-out curve.

signal count_changed(shown: int)

const MAX_FLYERS := 15
const PER_FLYER := 2
const DUR := 0.75
const GAP := 0.09
const ICON := Vector2(52, 33)   # the 22 × 14 ticket at the design's 52 px width
const SHADOW := Vector2(3, 3)

var manual := false
var max_flyers := MAX_FLYERS   # the cap (design 39b: 12)
var from := Vector2.ZERO
var to := Vector2.ZERO
var tickets := 0
var start := 0.0
## The scatter of the starts around `from` (x spread, y spread), the arc's lift
## and a sideways wobble at the midpoint (the match end's +30 / -30).
var spread := Vector2(140, 50)
var lift := 110.0
var wobble := 0.0
var _t := 0.0
var _playing := false
var _shown := 0
var _rang := false   # the shuffle sound, once per play, as the flyers launch


func _init() -> void:
	UiLayout.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## How many flyers `n` tickets send: one per two, fifteen at most, none for none.
static func count(n: int) -> int:
	return clampi(ceili(float(n) / float(PER_FLYER)), 0, MAX_FLYERS) if n > 0 else 0


## This stream's flyers for `n` tickets (its own cap).
func flyers_for(n: int) -> int:
	return clampi(ceili(float(n) / float(PER_FLYER)), 0, max_flyers) if n > 0 else 0


func play(p_from: Vector2, p_to: Vector2, p_tickets: int, p_start := 0.0) -> void:
	from = p_from
	to = p_to
	tickets = p_tickets
	start = p_start
	_t = 0.0
	_shown = 0
	_rang = false
	_playing = flyers_for(tickets) > 0
	visible = true
	queue_redraw()


func _process(dt: float) -> void:
	if not manual:
		step(dt)


func step(dt: float) -> void:
	if not _playing:
		return
	_t += dt
	if not _rang and _t >= start:
		_rang = true
		Sfx.ticket_shuffle()   # the tickets gained (Ross, 2026-10-26)
	var was := _shown
	_shown = shown_at(_t)
	if _shown != was:
		count_changed.emit(_shown)
	if done():
		_playing = false
	queue_redraw()


func clock() -> float:
	return _t


## Flyers landed by second `t`.
func landed_at(t: float) -> int:
	var n := flyers_for(tickets)
	if n == 0:
		return 0
	return clampi(int(floor((t - start - DUR) / GAP)) + 1, 0, n)


## The count the box reads at second `t`: the haul in proportion to the flyers down.
func shown_at(t: float) -> int:
	var n := flyers_for(tickets)
	if n == 0:
		return tickets
	return roundi(float(tickets) * float(landed_at(t)) / float(n))


func shown() -> int:
	return _shown


func landed() -> int:
	return landed_at(_t)


func done() -> bool:
	return _t >= start + float(flyers_for(tickets)) * GAP + DUR + 0.2


func playing() -> bool:
	return _playing


## Where flyer `i` starts (its scatter around `from`) and the raised midpoint.
func flyer_start(i: int) -> Vector2:
	return from + Vector2(float((i * 53) % int(spread.x)) - spread.x * 0.5, float((i * 37) % int(spread.y)) - spread.y * 0.5)


func flyer_mid(i: int) -> Vector2:
	var s := flyer_start(i) - to
	return to + Vector2(s.x * 0.45 + (wobble if i % 2 == 1 else -wobble), -lift - float(i % 4) * 22.0)


static func _ease(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return 1.0 - pow(1.0 - p, 3.0)


## Flyer `i` at second `t`: {pos, scale, rot, alpha}, or {} when it is not up.
func flyer_at(i: int, t: float) -> Dictionary:
	var t0 := start + float(i) * GAP
	if t < t0 or t > t0 + DUR:
		return {}
	var p := _ease((t - t0) / DUR)
	var s := flyer_start(i)
	var m := flyer_mid(i)
	var r0 := deg_to_rad(float(20 + i * 7) * (1.0 if i % 2 == 1 else -1.0))
	var rm := deg_to_rad(14.0 * (-1.0 if i % 2 == 1 else 1.0))
	var pos: Vector2
	var scale_: float
	var rot: float
	if p < 0.55:
		var k := p / 0.55
		pos = s.lerp(m, k)
		scale_ = lerpf(1.5, 1.1, k)
		rot = lerpf(r0, rm, k)
	else:
		var k := (p - 0.55) / 0.45
		pos = m.lerp(to, k)
		scale_ = lerpf(1.1, 0.55, k)
		rot = lerpf(rm, 0.0, k)
	var alpha := 1.0
	if p < 0.12:
		alpha = p / 0.12
	elif p > 0.92:
		alpha = 1.0 - (p - 0.92) / 0.08
	return {"pos": pos, "scale": scale_, "rot": rot, "alpha": alpha}


func _draw() -> void:
	if not _playing:
		return
	var tex := PixelIcon.tex("icon_ticket")
	if tex == null:
		return
	for i in flyers_for(tickets):
		var f := flyer_at(i, _t)
		if f.is_empty():
			continue
		var size_ := ICON * float(f["scale"])
		draw_set_transform(f["pos"], float(f["rot"]), Vector2.ONE)
		draw_texture_rect(tex, Rect2(-size_ * 0.5 + SHADOW, size_), false, Color(RetroTheme.SCENE_OUTLINE, float(f["alpha"])))
		draw_texture_rect(tex, Rect2(-size_ * 0.5, size_), false, Color(1, 1, 1, float(f["alpha"])))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Whether the shuffle has rung this play (tests).
func rang() -> bool:
	return _rang
