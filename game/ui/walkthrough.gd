class_name Walkthrough
extends CanvasLayer
## A spotlight tour over a live screen (design "First Time Walkthrough" 36a,
## 2026-10-17; docs/HOME.md → Walkthroughs). Everything is dimmed except the
## part being explained, which gets a gold outline with a soft pulse; the
## spotlight glides from spot to spot and the card flips above or below it
## so it never covers what it points at; taps underneath are blocked until
## the tour ends. The welcome and the last card are centred bookends with no
## spotlight. Steps come from Walkthroughs (data/walkthroughs.json); the
## hosting screen passes `resolve(target_id) -> Rect2` (design px) and
## listens for `closed(completed)`; SKIP and the last NEXT both mark the
## tour seen (App.mark_walkthrough_seen).

signal closed(completed: bool)

const DIM := Color(14.0 / 255.0, 11.0 / 255.0, 9.0 / 255.0, 0.82)
const GOLD := Color("#F0B84A")
const CREAM := RetroTheme.SCENE_TEXT
const CARD_X := 36.0
const CARD_W := 642.0
const CARD_PAD := 28.0
const GAP := 36.0              # between the spot and the card
const BOOKEND_TOP := 380.0
const SPOT_PAD := 12.0
const GLIDE_S := 0.4
const CARD_IN_S := 0.35
const PULSE_S := 1.4
const PULSE_PX := 18.0

var tour_id := ""
var steps: Array = []
var _resolve := Callable()
var _index := 0
var _root: Control
var _dim: Control
var _card: ShadowPanel
var _spot := Rect2()          # what is drawn (mid-glide)
var _target := Rect2()        # where the glide ends: the card is placed against this
var _has_spot := false
var _spot_tween: Tween
var _card_tween: Tween
var _pulse := 0.0
var _done := false


func _init() -> void:
	layer = 50


func start(p_tour: String, p_resolve: Callable) -> bool:
	tour_id = p_tour
	steps = Walkthroughs.tour(p_tour)
	_resolve = p_resolve
	if steps.is_empty():
		return false
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_dim = Control.new()
	_dim.name = "Dim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.draw.connect(_draw_dim)
	_root.add_child(_dim)
	_index = 0
	_show_step(true)
	return true


func _process(dt: float) -> void:
	if _dim == null or not _has_spot:
		return
	_pulse = fmod(_pulse + dt, PULSE_S)
	_dim.queue_redraw()


# ---- the spotlight ---------------------------------------------------------------------


## The dim in four rects around the spot (the cut-out), the gold outline and
## the pulse ring expanding and fading around it. No spot: the dim is whole.
func _draw_dim() -> void:
	var full := Rect2(Vector2.ZERO, _dim.size)
	if not _has_spot or _spot.size == Vector2.ZERO:
		_dim.draw_rect(full, DIM)
		return
	var s := _spot.intersection(full)
	_dim.draw_rect(Rect2(0, 0, full.size.x, s.position.y), DIM)
	_dim.draw_rect(Rect2(0, s.end.y, full.size.x, full.size.y - s.end.y), DIM)
	_dim.draw_rect(Rect2(0, s.position.y, s.position.x, s.size.y), DIM)
	_dim.draw_rect(Rect2(s.end.x, s.position.y, full.size.x - s.end.x, s.size.y), DIM)
	_dim.draw_rect(s, GOLD, false, 3.0)
	var k := _pulse / PULSE_S
	var ring := s.grow(k * PULSE_PX)
	_dim.draw_rect(ring, Color(GOLD, 0.9 * (1.0 - k)), false, 3.0)


func _set_spot(r: Rect2) -> void:
	_spot = r
	if _dim != null:
		_dim.queue_redraw()


func _glide_to(target: Rect2, instant: bool) -> void:
	if _spot_tween != null and _spot_tween.is_valid():
		_spot_tween.kill()
	if instant or not _has_spot or not is_inside_tree():
		_set_spot(target)
		return
	var from := _spot
	_spot_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_spot_tween.tween_method(func(t: float) -> void:
		_set_spot(Rect2(from.position.lerp(target.position, t), from.size.lerp(target.size, t))), 0.0, 1.0, GLIDE_S)


# ---- the steps -------------------------------------------------------------------------


func step_index() -> int:
	return _index


func step() -> Dictionary:
	return steps[_index] if _index >= 0 and _index < steps.size() else {}


func spot_rect() -> Rect2:
	return _target if _has_spot else Rect2()


func has_spot() -> bool:
	return _has_spot


## The card sits below a spot in the upper half, above one in the lower half.
func card_above() -> bool:
	return _has_spot and _target.get_center().y >= 640.0


func next() -> void:
	if _done:
		return
	if _index >= steps.size() - 1:
		_finish(true)
		return
	_index += 1
	_show_step(false)


func back() -> void:
	if _done or _index <= 0:
		return
	_index -= 1
	_show_step(false)


func skip() -> void:
	_finish(false)


func _finish(completed: bool) -> void:
	if _done:
		return
	_done = true
	App.mark_walkthrough_seen(tour_id)
	closed.emit(completed)
	queue_free()


func _show_step(first: bool) -> void:
	var st := step()
	var kind := str(st.get("kind", "plain"))
	var target := Rect2()
	if kind == "plain" and _resolve.is_valid():
		var r: Variant = _resolve.call(str(st["id"]))
		if r is Rect2:
			target = r
	var had := _has_spot
	_has_spot = target.size != Vector2.ZERO
	_target = target
	if _has_spot:
		_glide_to(target, first or not had)
	else:
		_set_spot(Rect2())
	if _dim != null:
		_dim.queue_redraw()
	_build_card(st, kind)


func _build_card(st: Dictionary, kind: String) -> void:
	if _card != null:
		# Out of the tree at once: a queued free would still answer find_child.
		if _card.get_parent() != null:
			_card.get_parent().remove_child(_card)
		_card.queue_free()
	_card = ShadowPanel.new(CREAM, CARD_PAD)
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_card)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 20)
	_card.add_child(col)
	var n := Walkthroughs.plain_count(steps)
	match kind:
		"welcome":
			var pre := _words("WELCOME TO", 20, true)
			pre.name = "Pre"
			pre.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			col.add_child(pre)
			col.add_child(_big_gold("Title", "HOOP SHOOT\nLEAGUE"))
		"end":
			col.add_child(_big_gold("Title", str(st.get("title", "THAT'S IT!"))))
		_:
			var row := HBoxContainer.new()
			row.name = "TitleRow"
			row.add_theme_constant_override("separation", 16)
			col.add_child(row)
			var title := _words(str(st.get("title", "")), 22, true)
			title.name = "Title"
			title.add_theme_color_override("font_color", GOLD)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			# No autowrap: in a box with no width yet it would wrap per glyph
			# and the card would grow to a column of letters' height.
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(title)
			var count := _words("%d / %d" % [_plain_index(), n], 16)
			count.name = "Count"
			count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(count)
	var body := _words(str(st.get("body", "")), 21)
	body.name = "Body"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(CARD_W - 2.0 * CARD_PAD - ShadowStyle.OFFSET, 0)
	col.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 22)
	col.add_child(buttons)
	var last := _index >= steps.size() - 1
	if not last:
		var skip_b := HomePage.button("SKIP", CREAM, 16, 68.0 - ShadowStyle.OFFSET)
		skip_b.name = "TourSkip"   # Tour*: the home has its own Prev / Next chevrons
		skip_b.custom_minimum_size = Vector2(150, 68)
		skip_b.pressed.connect(skip)
		buttons.add_child(skip_b)
	if _index > 0:
		var back_b := HomePage.button("<", CREAM, 24, 68.0 - ShadowStyle.OFFSET)
		back_b.name = "TourBack"
		back_b.custom_minimum_size = Vector2(68, 68)
		back_b.pressed.connect(back)
		buttons.add_child(back_b)
	var cta := str(st.get("cta", ""))
	var next_b := HomePage.button("", RetroTheme.c("orange"), 20, 68.0 - ShadowStyle.OFFSET)
	next_b.name = "TourNext"
	next_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_b.pressed.connect(next)
	var nrow := HBoxContainer.new()
	nrow.name = "Row"
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nrow.offset_left = 22.0
	nrow.offset_right = -(22.0 + ShadowStyle.OFFSET)
	nrow.offset_bottom = -ShadowStyle.OFFSET
	next_b.add_child(nrow)
	var nl := _words(cta if cta != "" else "NEXT", 20, true)
	nl.name = "Cta"
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nrow.add_child(nl)
	var arrow := _words(">", 24, true)
	arrow.name = "Arrow"
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nrow.add_child(arrow)
	buttons.add_child(next_b)
	# Place it: below a spot in the upper half, above one in the lower half,
	# the bookends at the design's resting spot; then rise and fade in.
	_card.size = Vector2(CARD_W, 0)
	_card.reset_size()
	var h := _card_height()
	var top := BOOKEND_TOP
	if _has_spot:
		top = (_target.end.y + GAP) if not card_above() else (_target.position.y - GAP - h)
	top = clampf(top, 20.0, 1280.0 - h - 20.0)
	_card.position = Vector2(CARD_X, top + 16.0)
	_card.modulate.a = 0.0
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	if is_inside_tree():
		_card_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_card_tween.tween_property(_card, "position:y", top, CARD_IN_S).set_delay(0.1)
		_card_tween.tween_property(_card, "modulate:a", 1.0, CARD_IN_S).set_delay(0.1)
	else:
		_card.position.y = top
		_card.modulate.a = 1.0


## The card's height from its contents (the layout runs the same frame off-tree).
func _card_height() -> float:
	var col: VBoxContainer = _card.get_node("Col")
	var h := 2.0 * CARD_PAD + ShadowStyle.OFFSET
	var items := 0
	for c in col.get_children():
		if c is Control:
			var mn: Vector2 = (c as Control).get_combined_minimum_size()
			var ch := mn.y
			if (c as Label) != null:
				var lab := c as Label
				var w := CARD_W - 2.0 * CARD_PAD - ShadowStyle.OFFSET
				ch = maxf(ch, lab.get_theme_font("font").get_multiline_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, w, lab.get_theme_font_size("font_size")).y)
			h += ch
			items += 1
	h += 20.0 * maxi(items - 1, 0)
	return h


func _plain_index() -> int:
	var k := 0
	for i in range(_index + 1):
		if str(steps[i].get("kind", "plain")) == "plain":
			k += 1
	return k


func card_top() -> float:
	return _card.position.y if _card != null else 0.0


static func _words(text: String, size_: int, display := false) -> Label:
	var l := HomePage.words(text, size_, display)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _big_gold(name_: String, text: String) -> Label:
	var l := RetroTheme.display(text, 40, GOLD)
	l.name = name_
	l.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	l.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RetroTheme.dithered(l, Vector2(6, 6))
	return l
