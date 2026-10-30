class_name XpMeter
extends Control
## The post-match XP meter (design "League Post-Match v2" 6b, 2026-10-25):
## the level line with the XP just earned beside it, over a 12 px bar that
## fills from where the player was to where they are once the ticket stream
## has landed (0.8 s, ease-out). A level up fills to the end and the line
## turns gold and pulses (and Sfx.level_up rings once, Ross 2026-10-26); at
## the cap the bar sits full. While it fills it ticks (Sfx.xp_tick every
## TICK_S, the pitch climbing with the bar; Ross 2026-10-30). `big` is the
## 2026-10-30 post-match size: a 22 px line, an 18 px gain, a 24 px bar in a
## 3 px frame with a 4 px ink drop. Driven by `step(dt)` (`_process` unless
## `manual`), so QA snaps are deterministic.

const FILL_S := 0.8
const BAR_H := 12.0
const BIG_BAR_H := 24.0
const TICK_S := 0.07
const GOLD := Color("#F0B84A")
const HI := Color("#FFE45C")
const CREAM := RetroTheme.SCENE_TEXT

var manual := false
var fill_s := FILL_S   # the fill time (design 39b: 1.1 s)
var _m: Dictionary = {}
var _start := 0.0
var _t := 0.0
var _line: Label
var _gain: Label
var _fill: ColorRect
var _bar: Control
var _rang := false   # the level-up sound, once
var _bar_h := BAR_H
var _edge := 2.0
var _next_tick := 0.0
var _ticks := 0


func _init(m: Dictionary, width: float, big := false) -> void:
	name = "XpMeter"
	_m = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_px := 22 if big else 16
	var gap := 16.0 if big else 12.0
	_bar_h = BIG_BAR_H if big else BAR_H
	_edge = 3.0 if big else 2.0
	var line_h := float(line_px) + (6.0 if big else 0.0)
	custom_minimum_size = Vector2(width, line_h + gap + _bar_h + 2.0 * _edge + (4.0 if big else 0.0))
	size = custom_minimum_size
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	row.size = Vector2(width, line_h)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_line = UiFont.label("", line_px, CREAM, UiFont.display())
	RetroTheme.on_scene(_line)
	_line.name = "LevelText"
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_line)
	_gain = UiFont.label("+%d XP" % int(m.get("gained", 0)), 18 if big else 16, HI, UiFont.body_bold())
	RetroTheme.on_scene(_gain)
	_gain.add_theme_color_override("font_color", HI)
	_gain.name = "XpGain"
	_gain.visible = int(m.get("gained", 0)) > 0
	row.add_child(_gain)
	_bar = Control.new()
	_bar.name = "Bar"
	_bar.position = Vector2(0, line_h + gap)
	_bar.size = Vector2(width, _bar_h + 2.0 * _edge)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	if big:
		var drop := ColorRect.new()
		drop.name = "Drop"
		drop.color = RetroTheme.SCENE_OUTLINE
		drop.position = Vector2(4, 4)
		drop.size = _bar.size
		drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.add_child(drop)
	var track := ColorRect.new()
	track.color = Color(RetroTheme.SCENE_OUTLINE, 0.7)
	track.size = _bar.size
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(track)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.color = GOLD
	_fill.position = Vector2(_edge, _edge)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_fill)
	var frame := Frame.new(_edge)
	frame.size = _bar.size
	_bar.add_child(frame)
	_apply(0.0)


## Start filling at second `start` of the meter's own clock.
func play(start: float) -> void:
	_start = start
	_t = 0.0
	_apply(0.0)


func _process(dt: float) -> void:
	if not manual:
		step(dt)


func step(dt: float) -> void:
	_t += dt
	_apply(progress_at(_t))
	# The climb ticks, its pitch rising with the bar (none at the cap, none
	# for a match that earned nothing).
	var raw := (_t - _start) / fill_s
	if raw > 0.0 and raw < 1.0 and int(_m.get("gained", 0)) > 0 and not bool(_m.get("cap", false)) and _t >= _next_tick:
		_next_tick = _t + TICK_S
		_ticks += 1
		Sfx.xp_tick(1.0 + 0.5 * progress_at(_t))
	if bool(_m.get("up", false)) and progress_at(_t) >= 1.0:
		if not _rang:
			_rang = true
			Sfx.level_up()
		_line.modulate.a = 0.775 + 0.225 * cos(TAU * (_t - _start - fill_s))   # the design's 1 s glow


## How many climb ticks have sounded (tests).
func ticks() -> int:
	return _ticks


## Whether the level-up sound has rung (tests, QA).
func rang() -> bool:
	return _rang


## The fill fraction at second `t` (ease-out cubic after the start).
func progress_at(t: float) -> float:
	var k := clampf((t - _start) / fill_s, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


func _apply(k: float) -> void:
	if _m.is_empty():
		return
	var need := maxf(float(_m["need"]), 1.0)
	var xp := lerpf(float(_m["from"]), float(_m["to"]), k)
	if bool(_m["cap"]):
		xp = need
	_fill.size = Vector2((_bar.size.x - 2.0 * _edge) * clampf(xp / need, 0.0, 1.0), _bar_h)
	_line.text = HeatCopy.meter_text(_m, k)
	var gold := (bool(_m["up"]) and k >= 1.0)
	_line.add_theme_color_override("font_color", GOLD if gold else CREAM)


func text() -> String:
	return _line.text


func fill_frac() -> float:
	return _fill.size.x / maxf(_bar.size.x - 2.0 * _edge, 1.0)


## The bar's cream border (2 px, or 3 on the big meter).
class Frame extends Control:
	var w := 2.0

	func _init(p_w := 2.0) -> void:
		w = p_w
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ONE * w * 0.5, size - Vector2.ONE * w), RetroTheme.SCENE_TEXT, false, w)
