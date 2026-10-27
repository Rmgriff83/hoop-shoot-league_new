class_name LoadingScreen
extends CanvasLayer
## The full loading screen (design "Loading States" 39a, 2026-10-25): the
## destination's art faintly behind, a bouncing pixel ball, LOADING… with
## where you're going in gold and a line under it, a progress bar with what
## is loading and the percentage, and a tip that changes every few seconds.
## Fades in over 0.25 s; `finish()` fades it out over the new scene. Owned by
## SceneLoader (a child of the App autoload), so it outlives the scene change.
## Driven by `step(dt)` (`_process` unless `manual`) for deterministic snaps.

signal gone

const FADE_IN_S := 0.25
const FADE_OUT_S := 0.3
const BOUNCE_S := 0.9
const BOUNCE_H := 120.0
const SPIN_S := 1.8
const GOLD := Color("#F0B84A")
const CREAM := RetroTheme.SCENE_TEXT
const BALL_PX := 112.0
const BALL_FLOOR := 538.0      # the ball's bottom at rest (the design's column ends at 560)

var manual := false
var _d: Dictionary = {}
var _t := 0.0
var _progress := 0.0
var _shown := 0.0
var _fade_out := -1.0
var _root: Control
var _ball: TextureRect
var _shadow: ColorRect
var _dots: Label
var _stage: Label
var _pct: Label
var _fill: ColorRect
var _bar_w := 0.0
var _tip: Label
var _tip_i := -1


## `d` from LoadingCopy.dest(); `art` the destination's 720×1280 picture (or "").
func _init(d: Dictionary, art := "") -> void:
	layer = 100
	name = "LoadingScreen"
	_d = d
	_root = Control.new()
	_root.name = "Root"
	UiLayout.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under it takes a tap
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color("#1B1815")
	UiLayout.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	if art != "" and ResourceLoader.exists(art):
		var pic := TextureRect.new()
		pic.name = "Art"
		pic.texture = load(art)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.modulate.a = 0.32
		UiLayout.full_rect(pic)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(pic)
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.45)
	UiLayout.full_rect(veil)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)
	# The bouncing ball and its shadow.
	_shadow = ColorRect.new()
	_shadow.name = "BallShadow"
	_shadow.color = Color(0, 0, 0, 0.6)
	_shadow.size = Vector2(110, 16)
	_shadow.pivot_offset = _shadow.size * 0.5
	_shadow.position = Vector2(360 - 55, BALL_FLOOR + 6)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shadow)
	_ball = TextureRect.new()
	_ball.name = "Ball"
	_ball.texture = PixelIcon.tex("icon_ball")
	_ball.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ball.stretch_mode = TextureRect.STRETCH_SCALE
	_ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ball.size = Vector2(BALL_PX, BALL_PX)
	_ball.pivot_offset = Vector2(BALL_PX * 0.5, BALL_PX * 0.5)   # spins about its centre
	_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ball)
	# LOADING… · the destination · the line under it.
	var col := VBoxContainer.new()
	col.name = "Words"
	col.position = Vector2(36, 610)
	col.size = Vector2(642, 0)
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_dots = _text("LOADING", 28, CREAM, true)
	_dots.name = "Loading"
	col.add_child(_dots)
	var dest := _text(str(d.get("dest", "")), 36, GOLD, true)
	dest.name = "Dest"
	dest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dest.add_theme_constant_override("line_spacing", 9)
	col.add_child(dest)
	var sub := _text(str(d.get("sub", "")), 18, CREAM)
	sub.name = "DestSub"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.visible = sub.text != ""
	col.add_child(sub)
	# The progress: what is loading, the percentage, the bar.
	var prog := VBoxContainer.new()
	prog.name = "Progress"
	prog.position = Vector2(72, 900)
	prog.size = Vector2(720 - 72 - 78, 0)
	prog.add_theme_constant_override("separation", 14)
	prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(prog)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog.add_child(row)
	_stage = _text("", 16, CREAM)
	_stage.name = "Stage"
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_stage)
	_pct = _text("0%", 16, CREAM)
	_pct.name = "Pct"
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_pct)
	var bar := Control.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(0, 20)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog.add_child(bar)
	_bar_w = prog.size.x
	var track := ColorRect.new()
	track.color = Color(RetroTheme.SCENE_OUTLINE, 0.7)
	track.size = Vector2(_bar_w, 20)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(track)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.color = GOLD
	_fill.position = Vector2(2, 2)
	_fill.size = Vector2(0, 16)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_fill)
	var frame := XpMeter.Frame.new()
	frame.size = Vector2(_bar_w, 20)
	bar.add_child(frame)
	# The tip.
	var tipbox := ShadowPanel.new(CREAM, 20.0, 0.24, 24.0)
	tipbox.name = "TipBox"
	tipbox.position = Vector2(36, 1080)
	tipbox.size = Vector2(642 + ShadowStyle.OFFSET, 110 + ShadowStyle.OFFSET)
	tipbox.custom_minimum_size = tipbox.size
	_root.add_child(tipbox)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 20)
	trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tipbox.add_child(trow)
	var tl := _text("TIP", 16, GOLD, true)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	trow.add_child(tl)
	_tip = _text("", 19, CREAM)
	_tip.name = "Tip"
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip.add_theme_constant_override("line_spacing", 7)
	trow.add_child(_tip)
	_apply()


## The load's progress (0 … 1).
func set_progress(p: float) -> void:
	_progress = clampf(maxf(p, _progress), 0.0, 1.0)


func progress() -> float:
	return _progress


## Seconds the screen has been up.
func shown_for() -> float:
	return _shown


## Fade out over the new scene, then free.
func finish() -> void:
	set_progress(1.0)
	if _fade_out < 0.0:
		_fade_out = 0.0


func _process(dt: float) -> void:
	if not manual:
		step(dt)


func step(dt: float) -> void:
	_t += dt
	_shown += dt
	if _fade_out >= 0.0:
		_fade_out += dt
		_root.modulate.a = clampf(1.0 - _fade_out / FADE_OUT_S, 0.0, 1.0)
		if _fade_out >= FADE_OUT_S:
			gone.emit()
			queue_free()
			return
	else:
		_root.modulate.a = clampf(_t / FADE_IN_S, 0.0, 1.0)
	_apply()


func _apply() -> void:
	var pct := roundi(_progress * 100.0)
	_pct.text = "%d%%" % pct
	_stage.text = LoadingCopy.stage_for(_d.get("stages", []), pct) + "..."
	_fill.size.x = (_bar_w - 4.0) * _progress
	_dots.text = "LOADING" + LoadingCopy.dots(_t)
	var ti := int(floor(_t / LoadingCopy.TIP_S))
	if ti != _tip_i:
		_tip_i = ti
		_tip.text = LoadingCopy.tip_at(_t, int(_d.get("tip_skip", 0)))
	var since := fposmod(_t, LoadingCopy.TIP_S)
	var k := clampf(since / 0.35, 0.0, 1.0)
	_tip.modulate.a = k   # each tip fades in (the design's tipIn)
	# The bounce: up 120 px and back every 0.9 s, squashed at the floor, the
	# shadow shrinking and fading as the ball rises; the ball turns in 45° steps.
	var p := fposmod(_t, BOUNCE_S) / BOUNCE_S
	var h := sin(PI * p)
	var squash := 0.0
	if p < 0.16:
		squash = 1.0 - p / 0.16
	elif p > 0.84:
		squash = (p - 0.84) / 0.16
	_ball.scale = Vector2(1.0 + 0.18 * squash, 1.0 - 0.18 * squash)
	# Scaled about its centre, the squashed ball keeps its bottom on the floor.
	_ball.position = Vector2(360.0 - BALL_PX * 0.5, BALL_FLOOR - BALL_PX - BOUNCE_H * h + BALL_PX * 0.5 * (1.0 - _ball.scale.y))
	_ball.rotation = deg_to_rad(45.0 * floor(fposmod(_t, SPIN_S) / SPIN_S * 8.0))
	_shadow.scale = Vector2(1.0 - 0.5 * h, 1.0)
	_shadow.modulate.a = (0.55 - 0.30 * h) / 0.6


func _text(s: String, size_: int, color: Color, display := false) -> Label:
	var l := UiFont.label(s, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
