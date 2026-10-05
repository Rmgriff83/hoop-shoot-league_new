class_name Toast
extends Control
## The league HUD's toast chip (design "League Match HUD" 4a, 2026-10-04):
## a dark chip — `#1B1815` at 85 % under the colour's dot pattern, a 2 px
## edge in the colour, the dithered checker shadow — centred on the screen
## at a given y. Two shapes: `big` (the countdown: an optional small line
## over a 48 px display title, min width 240) and `small` (a 64 px row: an
## optional 28 px pixel icon, the title at 20 px, an optional 16 px sub).
## `show_stay()` slides it in from 24 px above with a fade and holds;
## `show_once(seconds)` does the same, holds and fades out. Everything is
## drawn, so the chip reads the same over any court.

const FILL := Color("#1B1815", 0.85)
const SLIDE_PX := 24.0
const SLIDE_S := 0.35
const FADE_OUT_S := 0.4
const BIG_MIN_W := 240.0
const BIG_PAD := Vector4(20.0, 36.0, 22.0, 36.0)   # top, right, bottom, left
const SMALL_H := 64.0
const SMALL_PAD_X := 22.0

var color := RetroTheme.SCENE_TEXT
var _box: BoxContainer
var _title: Label
var _pre: Label
var _sub: Label
var _icon: PixelIcon
var _big := false
var _tween: Tween
var _top := 0.0


func _init(p_color: Color, top: float) -> void:
	color = p_color
	_top = top
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = top
	visible = false


## The countdown shape: `pre` (20 px display, may be "") over `title` (48 px
## display). Called every frame of a countdown, so a chip already in this
## shape just swaps its text.
func set_big(pre: String, title: String) -> void:
	if _box != null and _big and (_pre != null) == (pre != ""):
		if _pre != null:
			_pre.text = pre
		_title.text = title
		_title.add_theme_color_override("font_color", color)
		_fit()
		return
	_rebuild(true)
	if pre != "":
		_pre = _label(pre, 20, true)
		_pre.name = "Pre"
		_box.add_child(_pre)
	_title = _label(title, 48, true)
	_title.name = "Title"
	_title.add_theme_color_override("font_color", color)
	_box.add_child(_title)
	_fit()


## The notice shape: an optional icon, the title (20 px display, in the colour), an optional sub.
func set_small(title: String, sub := "", icon_name := "") -> void:
	_rebuild(false)
	if icon_name != "":
		_icon = PixelIcon.new(icon_name, Vector2(28, 28))
		_icon.name = "Icon"
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_box.add_child(_icon)
	_title = _label(title, 20, true)
	_title.name = "Title"
	_title.add_theme_color_override("font_color", color)
	_box.add_child(_title)
	if sub != "":
		_sub = _label(sub, 16, false)
		_sub.name = "Sub"
		_box.add_child(_sub)
	_fit()


func _rebuild(big: bool) -> void:
	if _box != null:
		remove_child(_box)
		_box.free()
	_title = null
	_pre = null
	_sub = null
	_icon = null
	_big = big
	_box = VBoxContainer.new() if big else HBoxContainer.new()
	_box.name = "Row"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 18 if big else 14)
	if big:
		(_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	if big:
		_box.offset_left = BIG_PAD.w
		_box.offset_top = BIG_PAD.x
		_box.offset_right = -BIG_PAD.y - ShadowStyle.OFFSET
		_box.offset_bottom = -BIG_PAD.z - ShadowStyle.OFFSET
	else:
		_box.offset_left = SMALL_PAD_X
		_box.offset_right = -SMALL_PAD_X - ShadowStyle.OFFSET
		_box.offset_bottom = -ShadowStyle.OFFSET
	add_child(_box)
	# Fonts settle a frame late: refit whenever the row's minimum size moves.
	_box.minimum_size_changed.connect(_fit)


func _fit() -> void:
	var big := _big
	var inner := _box.get_combined_minimum_size()
	var w: float
	var h: float
	if big:
		w = maxf(BIG_MIN_W, inner.x + BIG_PAD.y + BIG_PAD.w)
		h = inner.y + BIG_PAD.x + BIG_PAD.z
	else:
		# The labels' ink outline draws past their boxes: room for it both sides.
		w = inner.x + 2.0 * SMALL_PAD_X + 2.0 * RetroTheme.OUTLINE
		h = SMALL_H
	var full := Vector2(w, h) + Vector2.ONE * ShadowStyle.OFFSET
	custom_minimum_size = full
	offset_left = -w / 2.0
	offset_right = w / 2.0 + ShadowStyle.OFFSET
	offset_bottom = offset_top + full.y
	size = full
	queue_redraw()


func _label(text: String, size_: int, display: bool) -> Label:
	var l := UiFont.label(text, size_, RetroTheme.SCENE_TEXT, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _draw() -> void:
	ShadowStyle.draw_ex(self, size, color, FILL, Color(color, ShadowStyle.DOT_ALPHA), Color(color, ShadowStyle.SHADOW_ALPHA), false, false, false)


func _kill() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


## Slide in from above with a fade, then hold until hidden.
func show_stay() -> void:
	_kill()
	visible = true
	modulate.a = 0.0
	var h := size.y   # read first: moving offset_top alone stretches the box
	offset_top = _top - SLIDE_PX
	offset_bottom = offset_top + h
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "offset_top", _top, SLIDE_S)
	_tween.tween_property(self, "offset_bottom", _top + h, SLIDE_S)
	_tween.tween_property(self, "modulate:a", 1.0, SLIDE_S)


## Slide in, hold `seconds`, fade out.
func show_once(seconds := 2.6) -> void:
	show_stay()
	_tween.chain().tween_interval(maxf(0.0, seconds - SLIDE_S - FADE_OUT_S))
	_tween.chain().tween_property(self, "modulate:a", 0.0, FADE_OUT_S)
	_tween.chain().tween_callback(hide_now)


func hide_now() -> void:
	_kill()
	visible = false


func title_text() -> String:
	return _title.text if _title != null else ""


func pre_text() -> String:
	return _pre.text if _pre != null else ""


func sub_text() -> String:
	return _sub.text if _sub != null else ""


func has_icon() -> bool:
	return _icon != null
