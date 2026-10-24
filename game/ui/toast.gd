class_name Toast
extends Control
## A toast chip (designs "League Match HUD" 4a / "Solo Modes HUD" 5a): a dark
## chip — `#1B1815` at 85 % under the colour's dot pattern, a 2 px edge in the
## colour, the dithered checker shadow. Two placements:
##
## `Mode.SIDE` (the match HUDs, 2026-10-24): the chip hangs off the screen's
## left or right edge (36 px in, App.hud_side) with its centre a third of the
## way up (y 853), slides in from off-screen with an 8 px overshoot, holds,
## and slides back out. Shapes: `big` (the countdown: STARTS IN over a 56 px
## digit that pops on every tick, GO centred; min width 260, 150 tall),
## `small` (72 tall, min width 300: a 32 px icon beside the 20 px title over
## the 16 px sub) and `card` (100 tall: a 54×72 card thumb with its fx loop
## and the target badge at the corner, beside the title and sub).
##
## `Mode.CENTER` (the title screen's WELCOME): centred at a given y, 64 tall,
## slides in from 24 px above with a fade (`show_stay`) and fades out
## (`show_once`). Everything is drawn, so the chip reads the same over any
## court.

enum Mode { CENTER, SIDE }

const FILL := Color("#1B1815", 0.85)
# Centre mode.
const SLIDE_PX := 24.0
const SLIDE_S := 0.35
const FADE_OUT_S := 0.4
const BIG_MIN_W := 240.0
const BIG_PAD := Vector4(20.0, 36.0, 22.0, 36.0)   # top, right, bottom, left
const SMALL_H := 64.0
const SMALL_PAD_X := 22.0
# Side mode (design 4a / 5a `_toast`).
const SIDE_MARGIN := 36.0
const SIDE_PAD_X := 26.0
const SIDE_GAP := 16.0
const SIDE_SMALL_H := 72.0
const SIDE_CARD_H := 100.0
const SIDE_BIG_H := 150.0
const SIDE_SMALL_MIN_W := 300.0
const SIDE_BIG_MIN_W := 260.0
const SIDE_ICON := 32.0
const THUMB := Vector2(54, 72)
const THUMB_SHADOW := 4.0
const BADGE := 33.0
const BADGE_AT := Vector2(-10, -10)
const OVERSHOOT := 8.0
const SLIDE_IN_S := 0.34
const SLIDE_SETTLE_S := 0.06
const SLIDE_OUT_S := 0.45
const POP_SCALE := 1.45
const POP_S := 0.3

var color := RetroTheme.SCENE_TEXT
var mode := Mode.CENTER
var side := "left"
var _box: BoxContainer
var _title: Label
var _pre: Label
var _sub: Label
var _icon: PixelIcon
var _thumb: Control
var _badge: PixelIcon
var _big := false
var _card := false
var _tween: Tween
var _pop: Tween
var _top := 0.0
var _staying := false
var _sliding := false
## Side mode: the chip's left offset (tweened; moving it moves the right one with it).
var x_pos := 0.0:
	set(v):
		x_pos = v
		offset_left = v
		offset_right = v + size.x


func _init(p_color: Color, top: float, p_mode := Mode.CENTER, p_side := "left") -> void:
	color = p_color
	_top = top
	mode = p_mode
	side = "right" if p_side == "right" else "left"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mode == Mode.CENTER:
		anchor_left = 0.5
		anchor_right = 0.5
		grow_horizontal = Control.GROW_DIRECTION_BOTH
	else:
		var a := 1.0 if side == "right" else 0.0
		anchor_left = a
		anchor_right = a
		grow_horizontal = Control.GROW_DIRECTION_BEGIN if side == "right" else Control.GROW_DIRECTION_END
	offset_top = top
	visible = false


## The countdown shape: `pre` (STARTS IN, may be "") over `title` (the digit
## or GO). Called every frame of a countdown, so a chip already in this shape
## just swaps its text — and, from the side, pops the digit on each change.
func set_big(pre: String, title: String) -> void:
	if _box != null and _big and (_pre != null) == (pre != ""):
		if _pre != null:
			_pre.text = pre
		var changed := _title.text != title
		_title.text = title
		_title.add_theme_color_override("font_color", color)
		_fit()
		if changed:
			_pop_title()
		return
	_rebuild(true)
	var side_mode := mode == Mode.SIDE
	if pre != "":
		_pre = _label(pre, 18 if side_mode else 20, side_mode)
		_pre.name = "Pre"
		_box.add_child(_pre)
	_title = _label(title, 56 if side_mode else 48, true)
	_title.name = "Title"
	_title.add_theme_color_override("font_color", color)
	_box.add_child(_title)
	if side_mode:
		# Counting: STARTS IN and the digit flush left; GO alone sits centred.
		(_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
		var left := pre != ""
		_pre_align(_pre, left)
		_pre_align(_title, left)
	_fit()
	if side_mode:
		_pop_title()


## The notice shape: an optional icon, the title (20 px display, in the
## colour), an optional sub (16 px bold) — from the side the sub sits under
## the title beside the icon; centred, the parts run in a row with an
## optional `pre` word. A chip already in this shape with the same parts just
## swaps its text.
func set_small(title: String, sub := "", icon_name := "", pre := "") -> void:
	if _box != null and not _big and not _card and (_pre != null) == (pre != "") and (_sub != null) == (sub != "") and (_icon != null) == (icon_name != ""):
		if _pre != null:
			_pre.text = pre
		_title.text = title
		_title.add_theme_color_override("font_color", color)
		if _sub != null:
			_sub.text = sub
		_fit()
		queue_redraw()
		return
	_rebuild(false)
	if mode == Mode.SIDE:
		if icon_name != "":
			_icon = PixelIcon.new(icon_name, Vector2(SIDE_ICON, SIDE_ICON))
			_icon.name = "Icon"
			_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_box.add_child(_icon)
		var col := _column()
		_box.add_child(col)
		if pre != "":
			_pre = _label(pre, 16, false)
			_pre.name = "Pre"
			col.add_child(_pre)
		_title = _label(title, 20, true)
		_title.name = "Title"
		_title.add_theme_color_override("font_color", color)
		col.add_child(_title)
		if sub != "":
			_sub = _label(sub, 16, false)
			_sub.name = "Sub"
			col.add_child(_sub)
		_fit()
		return
	if pre != "":
		_pre = _label(pre, 16, false)
		_pre.name = "Pre"
		_box.add_child(_pre)
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


## A card played (design 4a, side mode): the card's 54×72 thumb with its fx
## loop over a 4 px ink shadow, the target badge (`self` / `opp`) hanging off
## the chip's corner, the title (the card's name) over the sub (PLAYED ON …).
func set_card(title: String, sub: String, card: Dictionary, target: String) -> void:
	_rebuild(false)
	_card = true
	_thumb = CardThumb.new(card)
	_thumb.name = "Thumb"
	_thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_box.add_child(_thumb)
	var col := _column()
	_box.add_child(col)
	_title = _label(title, 20, true)
	_title.name = "Title"
	_title.add_theme_color_override("font_color", color)
	col.add_child(_title)
	if sub != "":
		_sub = _label(sub, 16, false)
		_sub.name = "Sub"
		col.add_child(_sub)
	_badge = PixelIcon.new("cards/badge_self_b" if target == "self" else "cards/badge_opp_a", Vector2(BADGE, BADGE))
	_badge.name = "Badge"
	_badge.position = BADGE_AT
	add_child(_badge)
	_fit()


## The card thumb: the face at 54×72 over a hard ink shadow.
class CardThumb extends Control:
	var face: CardFace

	func _init(card: Dictionary) -> void:
		custom_minimum_size = THUMB + Vector2.ONE * THUMB_SHADOW
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		face = CardFace.new(card, THUMB)
		face.name = "Face"
		add_child(face)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ONE * THUMB_SHADOW, THUMB), RetroTheme.SCENE_OUTLINE)


func _column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Lines"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return col


static func _pre_align(l: Label, left: bool) -> void:
	if l == null:
		return
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_FILL if left else Control.SIZE_SHRINK_CENTER


func _rebuild(big: bool) -> void:
	if _box != null:
		remove_child(_box)
		_box.free()
	if _badge != null:
		remove_child(_badge)
		_badge.free()
		_badge = null
	_title = null
	_pre = null
	_sub = null
	_icon = null
	_thumb = null
	_big = big
	_card = false
	_box = VBoxContainer.new() if big else HBoxContainer.new()
	_box.name = "Row"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mode == Mode.SIDE:
		_box.add_theme_constant_override("separation", int(SIDE_GAP))
	else:
		_box.add_theme_constant_override("separation", 18 if big else 14)
	if big:
		(_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	if mode == Mode.SIDE:
		_box.offset_left = SIDE_PAD_X
		_box.offset_right = -SIDE_PAD_X - ShadowStyle.OFFSET
		_box.offset_bottom = -ShadowStyle.OFFSET
	elif big:
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
	var inner := _box.get_combined_minimum_size()
	var w: float
	var h: float
	if mode == Mode.SIDE:
		# The labels' ink outline draws past their boxes: room for it both sides.
		var need := inner.x + 2.0 * SIDE_PAD_X + 2.0 * RetroTheme.OUTLINE
		w = maxf(SIDE_BIG_MIN_W if _big else SIDE_SMALL_MIN_W, need)
		h = SIDE_BIG_H if _big else (SIDE_CARD_H if _card else SIDE_SMALL_H)
		var full := Vector2(w, h) + Vector2.ONE * ShadowStyle.OFFSET
		custom_minimum_size = full
		size = full
		offset_top = _top - h / 2.0
		offset_bottom = offset_top + full.y
		if not _sliding:
			x_pos = _home_x()
		else:
			x_pos = x_pos   # re-apply the right offset for the new width
		queue_redraw()
		return
	if _big:
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


## Side mode: the chip's resting left offset — 36 in from its edge.
func _home_x() -> float:
	return -SIDE_MARGIN - size.x if side == "right" else SIDE_MARGIN


## Side mode: fully off its edge.
func _off_x() -> float:
	return SIDE_MARGIN if side == "right" else -size.x - SIDE_MARGIN


## The overshoot past home, towards the screen's middle.
func _over_x() -> float:
	return _home_x() + (-OVERSHOOT if side == "right" else OVERSHOOT)


func _label(text: String, size_: int, display: bool) -> Label:
	var l := UiFont.label(text, size_, RetroTheme.SCENE_TEXT, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The countdown digit's pop (design `cdPop`: 1.45 → 1 over 0.3 s), from the
## left edge while counting, the middle for GO.
func _pop_title() -> void:
	if _title == null or mode != Mode.SIDE:
		return
	if _pop != null:
		_pop.kill()
	var m := _title.get_minimum_size()
	_title.pivot_offset = Vector2(0.0 if _pre != null else m.x / 2.0, m.y / 2.0)
	_title.scale = Vector2.ONE * POP_SCALE
	_pop = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_title, "scale", Vector2.ONE, POP_S)


func _draw() -> void:
	ShadowStyle.draw_ex(self, size, color, FILL, Color(color, ShadowStyle.DOT_ALPHA), Color(color, ShadowStyle.SHADOW_ALPHA), false, false, false)


func _kill() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_sliding = false


## Up with no fade-out scheduled (show_stay, not show_once)?
func staying() -> bool:
	return visible and _staying


## Slide in (from above with a fade when centred; from the edge with an
## overshoot from the side), then hold until hidden.
func show_stay() -> void:
	_kill()
	_staying = true
	visible = true
	if mode == Mode.SIDE:
		modulate.a = 1.0
		_sliding = true
		x_pos = _off_x()
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "x_pos", _over_x(), SLIDE_IN_S)
		_tween.tween_property(self, "x_pos", _home_x(), SLIDE_SETTLE_S)
		_tween.tween_callback(func() -> void: _sliding = false)
		return
	modulate.a = 0.0
	var h := size.y   # read first: moving offset_top alone stretches the box
	offset_top = _top - SLIDE_PX
	offset_bottom = offset_top + h
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "offset_top", _top, SLIDE_S)
	_tween.tween_property(self, "offset_bottom", _top + h, SLIDE_S)
	_tween.tween_property(self, "modulate:a", 1.0, SLIDE_S)


## Slide in, hold `seconds` in all, then leave (slide out from the side, fade centred).
func show_once(seconds := 2.8) -> void:
	show_stay()
	_staying = false
	if mode == Mode.SIDE:
		_tween.tween_interval(maxf(0.0, seconds - SLIDE_IN_S - SLIDE_SETTLE_S - SLIDE_OUT_S))
		_tween.tween_callback(func() -> void: _sliding = true)
		_tween.tween_property(self, "x_pos", _off_x(), SLIDE_OUT_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_callback(hide_now)
		return
	_tween.chain().tween_interval(maxf(0.0, seconds - SLIDE_S - FADE_OUT_S))
	_tween.chain().tween_property(self, "modulate:a", 0.0, FADE_OUT_S)
	_tween.chain().tween_callback(hide_now)


func hide_now() -> void:
	_kill()
	_staying = false
	visible = false


func title_text() -> String:
	return _title.text if _title != null else ""


func pre_text() -> String:
	return _pre.text if _pre != null else ""


func sub_text() -> String:
	return _sub.text if _sub != null else ""


func has_icon() -> bool:
	return _icon != null


func has_thumb() -> bool:
	return _thumb != null


## The target badge's icon name ("" when the chip carries none).
func badge_name() -> String:
	return _badge.icon_name if _badge != null else ""


## Side mode: the chip's resting left offset (tests).
func home_x() -> float:
	return _home_x()
