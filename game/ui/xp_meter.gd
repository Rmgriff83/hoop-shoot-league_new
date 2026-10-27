class_name XpMeter
extends Control
## The post-match XP meter (design "League Post-Match v2" 6b, 2026-10-25):
## the level line with the XP just earned beside it, over a 12 px bar that
## fills from where the player was to where they are once the ticket stream
## has landed (0.8 s, ease-out). A level up fills to the end and the line
## turns gold and pulses (and Sfx.level_up rings once, Ross 2026-10-26); at
## the cap the bar sits full. Driven by `step(dt)` (`_process` unless
## `manual`), so QA snaps are deterministic.

const FILL_S := 0.8
const BAR_H := 12.0
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


func _init(m: Dictionary, width: float) -> void:
	name = "XpMeter"
	_m = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(width, 16 + 12 + BAR_H + 4)
	size = custom_minimum_size
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	row.size = Vector2(width, 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_line = UiFont.label("", 16, CREAM, UiFont.display())
	RetroTheme.on_scene(_line)
	_line.name = "LevelText"
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_line)
	_gain = UiFont.label("+%d XP" % int(m.get("gained", 0)), 16, HI, UiFont.body_bold())
	RetroTheme.on_scene(_gain)
	_gain.add_theme_color_override("font_color", HI)
	_gain.name = "XpGain"
	_gain.visible = int(m.get("gained", 0)) > 0
	row.add_child(_gain)
	_bar = Control.new()
	_bar.name = "Bar"
	_bar.position = Vector2(0, 16 + 12)
	_bar.size = Vector2(width, BAR_H + 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	var track := ColorRect.new()
	track.color = Color(RetroTheme.SCENE_OUTLINE, 0.7)
	track.size = _bar.size
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(track)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.color = GOLD
	_fill.position = Vector2(2, 2)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_fill)
	var frame := Frame.new()
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
	if bool(_m.get("up", false)) and progress_at(_t) >= 1.0:
		if not _rang:
			_rang = true
			Sfx.level_up()
		_line.modulate.a = 0.775 + 0.225 * cos(TAU * (_t - _start - fill_s))   # the design's 1 s glow


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
	_fill.size = Vector2((_bar.size.x - 4.0) * clampf(xp / need, 0.0, 1.0), BAR_H)
	_line.text = HeatCopy.meter_text(_m, k)
	var gold := (bool(_m["up"]) and k >= 1.0)
	_line.add_theme_color_override("font_color", GOLD if gold else CREAM)


func text() -> String:
	return _line.text


func fill_frac() -> float:
	return _fill.size.x / maxf(_bar.size.x - 4.0, 1.0)


## The bar's 2 px cream border.
class Frame extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), RetroTheme.SCENE_TEXT, false, 2.0)
