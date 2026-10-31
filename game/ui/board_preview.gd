class_name BoardPreview
extends Control
## The time-trial board on the home (design "Home League Context v2" 3a,
## 2026-10-30): an ink panel mid-court — TIME TRIAL · ALL TIME over a rule,
## a window three rows tall onto the area's top fifteen (rank, name, points;
## dashed rules; a fade at its foot while more rows wait below) and YOUR row
## pinned under it in gold on orange. A drag scrolls the window; a tap opens
## the board popup (BoardSheet). Slides off left and fades while the league
## is open (the title drives that from _apply_area). `max_h`: the room it
## has (HomeLayout board_max_h) — a short screen shows fewer rows.

signal pressed

const WIDTH := 434.0
const PAD_TOP := 16.0
const PAD_H := 20.0
const PAD_BOTTOM := 10.0
const HEAD_H := 40.0
const ROW_H := 44.0
const ROWS_SHOWN := 3
const TOP := 15
const FADE_H := 44.0
const YOU := Color("#FFE45C")
const CREAM := RetroTheme.SCENE_TEXT
const MUTED := RetroTheme.SCENE_MUTED
const INK := RetroTheme.SCENE_OUTLINE
const PANEL := Color("#14100E")
const TAP_PX := 18.0

var _panel: ShadowPanel
var _scroll: ScrollContainer
var _list: VBoxContainer
var _you: Control
var _fade: TextureRect
var _shown := ROWS_SHOWN
var _press_at := Vector2.INF
var _dragged := false


func _init() -> void:
	name = "BoardPreview"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = ShadowPanel.new(PANEL, 0.0, 0.82, 0.0)
	_panel.name = "Panel"
	_panel.color = INK
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", int(PAD_H))
	pad.add_theme_constant_override("margin_right", int(PAD_H))
	pad.add_theme_constant_override("margin_top", int(PAD_TOP))
	pad.add_theme_constant_override("margin_bottom", int(PAD_BOTTOM))
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pad)
	pad.add_child(col)
	# TIME TRIAL · ALL TIME over a cream rule.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.custom_minimum_size = Vector2(0, HEAD_H - 12.0)
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var watch := PixelIcon.new("icon_stopwatch", Vector2(24, 24))
	watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(watch)
	var title := _text("TIME TRIAL", 18, CREAM, true)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var period := _text("ALL TIME", 16, MUTED)
	period.name = "Period"
	head.add_child(period)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = CREAM
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	# The window onto the top fifteen.
	var win := Control.new()
	win.name = "Window"
	win.clip_contents = true
	win.custom_minimum_size = Vector2(0, ROW_H * ROWS_SHOWN)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(win)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	UiLayout.full_rect(_scroll)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS   # a tap reaches the board; a drag scrolls
	_scroll.scroll_started.connect(func() -> void: _dragged = true)
	win.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_list)
	_fade = TextureRect.new()
	_fade.name = "Fade"
	var grad := Gradient.new()
	grad.set_color(0, Color(PANEL, 0.0))
	grad.set_color(1, Color(PANEL, 0.95))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	_fade.texture = gt
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_fade.offset_top = -FADE_H
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	win.add_child(_fade)
	_you = Control.new()
	_you.name = "YouSlot"
	_you.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_you)
	_relayout()


## The room the board has on this screen: rows come off the window to fit.
func set_max_height(h: float) -> void:
	var fixed := PAD_TOP + HEAD_H + 2.0 + ROW_H + PAD_BOTTOM + ShadowStyle.OFFSET
	_shown = clampi(int(floorf((h - fixed) / ROW_H)), 1, ROWS_SHOWN)
	(_scroll.get_parent() as Control).custom_minimum_size.y = ROW_H * _shown
	_relayout()


func rows_shown() -> int:
	return _shown


## Rows as RanksCopy makes them ({rank "#n", name, score, me}); the first TOP
## in the window, then YOUR row (from `me` or the list) pinned underneath.
func set_rows(rows: Array, me: Dictionary = {}) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for c in _you.get_children():
		_you.remove_child(c)
		c.queue_free()
	var you := {}
	var n := 0
	for r in rows:
		if bool(r.get("me", false)) and you.is_empty():
			you = r
		if n < TOP:
			var row := _row(str(r["rank"]).trim_prefix("#"), str(r["name"]), str(r["score"]), false, n > 0)
			_list.add_child(row)
			n += 1
	if you.is_empty() and not me.is_empty():
		you = {"rank": "#%d" % int(me.get("rank", 0)), "name": "YOU", "score": str(int(me.get("score", 0))), "me": true}
	if n == 0:
		var empty := _text("NO RUNS YET · BE FIRST", 16, MUTED)
		empty.name = "Empty"
		empty.custom_minimum_size = Vector2(0, ROW_H)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(empty)
	if not you.is_empty():
		var yr := _row(str(you["rank"]).trim_prefix("#"), "YOU", str(you["score"]), true, true)
		yr.position = Vector2(-PAD_H, 0)
		yr.size = Vector2(WIDTH - ShadowStyle.OFFSET, ROW_H)
		_you.add_child(yr)
	_you.custom_minimum_size = Vector2(0, ROW_H if not you.is_empty() else 0.0)
	_scroll.scroll_vertical = 0
	_relayout()


## Rows in the window (YOU's pinned row counted when there is one).
func row_count() -> int:
	var n := 0
	for c in _list.get_children():
		if c.name.begins_with("Row"):
			n += 1
	return n + _you.get_child_count()


func has_you() -> bool:
	return _you.get_child_count() > 0


func fade_shown() -> bool:
	return _fade.visible


func _process(_dt: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	var more := bar.max_value - bar.page - _scroll.scroll_vertical > 2.0
	if more != _fade.visible:
		_fade.visible = more


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			_press_at = mb.position
			_dragged = false
		elif _press_at != Vector2.INF:
			var tap := not _dragged and mb.position.distance_to(_press_at) < TAP_PX
			_press_at = Vector2.INF
			if tap:
				pressed.emit()
			accept_event()


func _relayout() -> void:
	_panel.size = Vector2(WIDTH, 0)
	_panel.reset_size()
	_panel.size.x = WIDTH
	size = _panel.get_combined_minimum_size()
	size.x = WIDTH
	custom_minimum_size = size


func _row(rank: String, who: String, pts: String, mine: bool, rule: bool) -> Control:
	var wrap := RowBox.new(Color(CREAM, 0.6 if mine else 0.18) if rule else Color.TRANSPARENT, Color(RetroTheme.c("orange"), 0.35) if mine else Color.TRANSPARENT)
	wrap.name = "Row" + rank if not mine else "RowYou"
	wrap.custom_minimum_size = Vector2(0, ROW_H)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(h)
	if mine:
		h.offset_left = PAD_H
		h.offset_right = -PAD_H
	wrap.add_child(h)
	var col := YOU if mine else CREAM
	var n := _text(rank, 16, col, true)
	n.name = "Rank"
	n.custom_minimum_size = Vector2(56, 0)
	h.add_child(n)
	var w := _text(who, 20, col)
	w.name = "Name"
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.clip_text = true
	w.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(w)
	var p := _text(pts, 20, col, true)
	p.name = "Pts"
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(p)
	for l in [n, w, p]:
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return wrap


func _text(text: String, size_: int, color: Color, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


## A row's ground: an optional fill and a dashed rule along its top.
class RowBox extends Control:
	var rule := Color.TRANSPARENT
	var fill := Color.TRANSPARENT
	func _init(p_rule: Color, p_fill: Color) -> void:
		rule = p_rule
		fill = p_fill
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		if fill.a > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), fill)
		if rule.a > 0.0:
			draw_dashed_line(Vector2(0, 1), Vector2(size.x, 1), rule, 2.0, 8.0)
