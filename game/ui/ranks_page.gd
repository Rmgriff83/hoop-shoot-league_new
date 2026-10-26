class_name RanksPage
extends CanvasLayer
## The Ranks page (docs/HOME.md → Ranks; design "Ranks" 41a, 2026-10-25):
## the global time-trial boards per area and, on RANKED, the 1v1 ladder. A
## see-through full page over the area in the online lobby's style (the home
## slides out left as it slides in): the `<` back square and RANKS; your gold
## player card (jersey, handle and #tag, hometown; on the right your rank on
## the board in view and your best, or your badge and record on RANKED, or
## NO RUN HERE YET); BOARD with how many courts are open over the five-court
## grid (CAGE · BEACH · PARK · CITY · RANKED, the active one gold, a locked
## court dim with the level that opens it); ALL TIME / THIS WEEK (hidden on
## RANKED) with the status line on the right; then the top 50 in one
## see-through panel with dashed rules — the top three ranks gold, your row
## on orange — sliding in after LOADING… and its spinner, a fade at the foot
## until the end is in view. The page owns no network: it emits
## `request(area, period)` (`ranked`, `all` for the ladder) and is fed by
## set_board / set_offline (the title wires it to Net; tests and QA feed it
## a fixture).

signal closed
signal request(area: String, period: String)

const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")
const MUTED := Color("#E6D9B8")
const ME_BG := Color(232.0 / 255.0, 112.0 / 255.0, 58.0 / 255.0, 0.4)
const WASH := Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.58)
const FADE_C := Color(27.0 / 255.0, 22.0 / 255.0, 19.0 / 255.0, 0.95)
const LEFT := 36.0
const RIGHT := 42.0
## The design's rows, measured from the head's top (44 at 1280).
const HEAD_Y := 44.0
const CARD_DY := 84.0
const CARD_H := 132.0
const BOARD_DY := 252.0
const PERIOD_DY := 376.0
const PANEL_DY := 456.0
const BOTTOM := 44.0
const BACK_PX := 56.0
const TAB_H := 64.0
const TAB_GAP := 14.0
const PERIOD_SIZE := Vector2(150, 48)
const ROW_H := 62.0
const RANK_W := 76.0
const FADE_H := 110.0
const PAD_X := 22.0
## The row's width inside the panel's padding.
const ROW_W := 720.0 - LEFT - RIGHT - 4.0 - 2.0 * (PAD_X - 2.0)
const ROW_IN_S := 0.25
const ROW_STAGGER_S := 0.03
const SLIDE_S := 0.3

var _root: Control
var _tabs: Dictionary = {}
var _locked: Dictionary = {}
var _chips: Dictionary = {}
var _status: Label
var _chip_row: HBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _fade: TextureRect
var _me_rank: Label
var _me_sub: Label
var _you_name: Label
var _you_tag: Label
var _area := "cage"
var _period := "all"
var _rows := 0


func _init() -> void:
	layer = 30
	UiLayout.anchor_layer(self)   # screen coordinates: the page runs the real screen


## `you` = {name, tag, town} (the account's handle and the hometown).
func build(tabs: Array, you: Dictionary) -> Control:
	_tabs.clear()
	_chips.clear()
	_locked.clear()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "RanksRoot"
	UiLayout.screen_fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var wash := ColorRect.new()
	wash.name = "Wash"
	wash.color = WASH
	UiLayout.full_rect(wash)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)
	var top := UiLayout.header_top(HEAD_Y)
	var w := 720.0 - LEFT - RIGHT
	# < RANKS
	var head := HBoxContainer.new()
	head.name = "Head"
	head.position = Vector2(LEFT, top)
	head.size = Vector2(w, BACK_PX + ShadowStyle.OFFSET)
	head.add_theme_constant_override("separation", 20)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(head)
	var back := HomePage.button("<", CREAM, 24, BACK_PX)
	back.name = "Back"
	back.custom_minimum_size.x = BACK_PX + ShadowStyle.OFFSET
	back.pressed.connect(close)
	head.add_child(back)
	var title := _display("RANKS", 28)
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_FILL
	head.add_child(title)
	_build_card(top, w, you)
	# BOARD ............ n OF 4 COURTS OPEN, then the grid.
	var board := HBoxContainer.new()
	board.name = "Board"
	board.position = Vector2(LEFT, top + BOARD_DY)
	board.size = Vector2(w, 16)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(board)
	board.add_child(_words("BOARD", 16))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(gap)
	var note := _words(RanksCopy.board_note(tabs), 16, MUTED)
	note.name = "BoardNote"
	board.add_child(note)
	var tab_row := HBoxContainer.new()
	tab_row.name = "Tabs"
	tab_row.position = Vector2(LEFT, top + BOARD_DY + 30.0)
	tab_row.size = Vector2(w, TAB_H + ShadowStyle.OFFSET)
	tab_row.add_theme_constant_override("separation", int(TAB_GAP))
	tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tab_row)
	var face_w := (w - 6.0 - TAB_GAP * (tabs.size() - 1)) / maxi(tabs.size(), 1) - ShadowStyle.OFFSET
	for tb in tabs:
		var area := str(tb["area"])
		var locked := bool(tb.get("locked", false))
		var b := _card("Tab_" + area, Vector2(face_w, TAB_H))
		var col := VBoxContainer.new()
		col.name = "Words"
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 8)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.position = Vector2.ZERO
		col.size = Vector2(face_w, TAB_H)
		b.add_child(col)
		var l := _display(str(tb["text"]), 13)
		l.name = "Text"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		if locked:
			var lk := _words(str(tb["lock_text"]), 12)
			lk.name = "Lock"
			lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(lk)
			b.disabled = true
			b.modulate.a = 0.38
		b.pressed.connect(func() -> void: select(area, "all"))
		tab_row.add_child(b)
		_tabs[area] = b
		_locked[area] = locked
	# ALL TIME / THIS WEEK ............ the status line.
	_chip_row = HBoxContainer.new()
	_chip_row.name = "Chips"
	_chip_row.position = Vector2(LEFT, top + PERIOD_DY)
	_chip_row.size = Vector2(w, 52)
	_chip_row.add_theme_constant_override("separation", 14)
	_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chip_row)
	for p in RanksCopy.PERIODS:
		var period := str(p)
		var c := _card("Period" + period.capitalize(), PERIOD_SIZE)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var l := _display(RanksCopy.period_name(period), 12)
		l.name = "Text"
		l.position = Vector2.ZERO
		l.size = PERIOD_SIZE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.add_child(l)
		c.pressed.connect(func() -> void: select(_area, period))
		_chip_row.add_child(c)
		_chips[period] = c
	_status = _words(RanksCopy.loading_status(), 15, MUTED)
	_status.name = "Status"
	_status.position = Vector2(LEFT, top + PERIOD_DY)
	_status.size = Vector2(w, 52)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_status)
	_build_list(top, w)
	_restyle()
	return _root


## Your card: the jersey, the handle and #tag over the hometown; your rank
## and line on the right (set by set_board / set_offline).
func _build_card(top: float, w: float, you: Dictionary) -> void:
	var card := ShadowPanel.new(GOLD, 0.0, ShadowStyle.TINT, 24.0)
	card.name = "YouCard"
	card.position = Vector2(LEFT, top + CARD_DY)
	card.size = Vector2(w + ShadowStyle.OFFSET, CARD_H + ShadowStyle.OFFSET)
	card.custom_minimum_size = card.size
	_root.add_child(card)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 22)
	crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(crow)
	var jersey := PixelIcon.new("icon_jersey", Vector2(64, 64), 4.0)
	jersey.name = "Jersey"
	jersey.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(jersey)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_theme_constant_override("separation", 14)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crow.add_child(who)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(name_row)
	_you_name = _display(str(you.get("name", "YOU")), 20)
	_you_name.name = "YouName"
	_you_name.clip_text = true
	_you_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(_you_name)
	_you_tag = _words(RanksCopy.tag_text(str(you.get("tag", ""))), 16, MUTED)
	_you_tag.name = "YouTag"
	_you_tag.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(_you_tag)
	var town := _words(str(you.get("town", "")).to_upper(), 16)
	town.name = "YouTown"
	town.visible = town.text != ""
	who.add_child(town)
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crow.add_child(right)
	_me_rank = _display("-", 28, GOLD)
	_me_rank.name = "MeRank"
	_me_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_me_rank)
	_me_sub = _words("", 16)
	_me_sub.name = "MeSub"
	_me_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_me_sub)
	_fit_name()


## The list panel to the screen's foot, its scroll, and the fade.
func _build_list(top: float, w: float) -> void:
	var panel_top := top + PANEL_DY
	var panel_h := UiLayout.screen_height() - BOTTOM - panel_top
	var panel := ShadowPanel.new(CREAM, 0.0, 0.14)
	panel.name = "Panel"
	panel.position = Vector2(LEFT, panel_top)
	panel.size = Vector2(w + ShadowStyle.OFFSET, panel_h + ShadowStyle.OFFSET)
	panel.custom_minimum_size = panel.size
	_root.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.position = Vector2(LEFT + 2.0, panel_top + 2.0)
	_scroll.size = Vector2(w - 4.0, panel_h - 4.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_root.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", int(PAD_X) - 2)
	pad.add_theme_constant_override("margin_right", int(PAD_X) - 2)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 28)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(_list)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _check_end())
	_scroll.get_v_scroll_bar().changed.connect(_check_end)
	var grad := Gradient.new()
	grad.set_color(0, Color(FADE_C, 0.0))
	grad.set_color(1, FADE_C)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	_fade = TextureRect.new()
	_fade.name = "Fade"
	_fade.texture = gt
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.stretch_mode = TextureRect.STRETCH_SCALE
	_fade.position = Vector2(LEFT + 2.0, panel_top + panel_h - 2.0 - FADE_H)
	_fade.size = Vector2(w - 4.0, FADE_H)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	_root.add_child(_fade)


## Show an area + period: the tabs restyle, the list clears to LOADING and
## `request` asks for the data. A locked area is ignored.
func select(area: String, period: String) -> void:
	if bool(_locked.get(area, false)) or not _tabs.has(area):
		return
	_area = area
	_period = period if RanksCopy.PERIODS.has(period) else "all"
	if _area == RanksCopy.RANKED:
		_period = "all"   # one ladder, no periods
	if _chip_row != null:
		_chip_row.visible = _area != RanksCopy.RANKED
	_restyle()
	_clear()
	_status.text = ""
	_list.add_child(_loading_row())
	_set_me({"rank": "-", "sub": ""})
	_scroll.scroll_vertical = 0
	_fade.visible = false
	request.emit(_area, _period)


## A server board for (area, period); anything for another view is stale and dropped.
func set_board(area: String, period: String, data: Dictionary) -> void:
	if area != _area or period != _period:
		return
	var ladder := area == RanksCopy.RANKED
	_fill(RanksCopy.ranked_rows(data) if ladder else RanksCopy.rows(data), ladder)
	_status.text = RanksCopy.ranked_status(_rows) if ladder else RanksCopy.status(_period, _rows)
	_set_me(RanksCopy.ranked_me_card(data) if ladder else RanksCopy.me_card(data))


## No signal: the device's own board for the area instead (the ladder has none).
func set_offline(area: String, period: String, local_top: Array) -> void:
	if area != _area or period != _period:
		return
	if area == RanksCopy.RANKED:
		_fill([], true)
		_status.text = RanksCopy.ranked_offline_status()
		_set_me(RanksCopy.ranked_me_card({}))
		return
	_fill(RanksCopy.local_rows(local_top), false)
	_status.text = RanksCopy.offline_status()
	_set_me(RanksCopy.local_me_card(local_top))


func area() -> String:
	return _area


func period() -> String:
	return _period


func status_text() -> String:
	return _status.text


## The player card's rank and line: `#7 · 29 PTS · BEST`.
func me_text() -> String:
	return "%s · %s" % [_me_rank.text, _me_sub.text] if _me_sub.text != "" else _me_rank.text


func row_count() -> int:
	return _rows


## Whether LOADING… is up (a board is on its way).
func loading() -> bool:
	return _list != null and _list.get_node_or_null("Loading") != null


## Whether the fade at the list's foot shows (more below).
func fade_shown() -> bool:
	return _fade != null and _fade.visible


func tab(area_: String) -> Button:
	return _tabs.get(area_, null)


func close() -> void:
	closed.emit()
	queue_free()


## Slide the page in from the right (the title opens it this way).
func slide_in() -> void:
	if _root == null:
		return
	_root.position.x = 1.1 * 720.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_root, "position:x", 0.0, SLIDE_S)


func _clear() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows = 0


func _fill(rows: Array, ladder: bool) -> void:
	_clear()
	for i in rows.size():
		var row := _row(rows[i], i, ladder)
		_list.add_child(row)
		_slide_row(row, i)
	_rows = rows.size()
	_check_end.call_deferred()


func _set_me(c: Dictionary) -> void:
	_me_rank.text = str(c.get("rank", "-"))
	_me_sub.text = str(c.get("sub", ""))
	_fit_name()


## Your handle takes what the jersey, the tag and your rank and line leave
## (an ellipsis past that), so the right column never runs off the card.
func _fit_name() -> void:
	if _you_name == null:
		return
	var inner := 720.0 - LEFT - RIGHT - 2.0 * 24.0 - ShadowStyle.OFFSET
	var right := maxf(_text_w(_me_rank), _text_w(_me_sub))
	var room := inner - 64.0 - 2.0 * 22.0 - right - 12.0 - _text_w(_you_tag)
	_you_name.custom_minimum_size.x = minf(_text_w(_you_name), maxf(room, 60.0))


func _check_end() -> void:
	if _scroll == null or _fade == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_fade.visible = _rows > 0 and bar.value + bar.page < bar.max_value - 4.0


## The active tab / period wears gold; the rest cream.
func _restyle() -> void:
	for area in _tabs:
		_style(_tabs[area], area == _area)
	for period in _chips:
		_style(_chips[period], period == _period)


func _card(name_: String, face: Vector2) -> ShadowCard:
	var b := ShadowCard.new(CREAM)
	b.name = name_
	b.custom_minimum_size = face + Vector2.ONE * ShadowStyle.OFFSET
	return b


func _style(b: ShadowCard, active: bool) -> void:
	b.color = GOLD if active else CREAM
	b.queue_redraw()


## LOADING… with the spinner, while a board is on its way.
func _loading_row() -> Control:
	var h := HBoxContainer.new()
	h.name = "Loading"
	h.custom_minimum_size = Vector2(0, 72)
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spin := PixelSpinner.new(28.0)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(spin)
	var l := _display(RanksCopy.loading_status(), 16)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	h.add_child(l)
	return h


## One board row: #n · NAME #tag · score, gold for the top three, orange for
## you, a dashed rule over every row but the first.
func _row(r: Dictionary, i: int, ladder: bool) -> Control:
	var me := bool(r.get("me", false))
	var box := RowBox.new()
	box.name = "Row" + str(r["rank"]).trim_prefix("#")
	box.custom_minimum_size = Vector2(0, ROW_H)
	box.rule = i > 0
	box.me = me
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.name = "Inner"
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.position = Vector2.ZERO
	h.size = Vector2(ROW_W, ROW_H)
	box.add_child(h)
	var n := int(str(r["rank"]).trim_prefix("#"))
	var rank := _display(str(r["rank"]), 18, GOLD if n <= RanksCopy.TOP_COLOURS and not me else CREAM)
	rank.name = "Rank"
	rank.custom_minimum_size = Vector2(RANK_W, 0)
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank.size_flags_vertical = Control.SIZE_FILL
	h.add_child(rank)
	var name_l := _words(str(r["name"]), 19)
	name_l.name = "Name"
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.size_flags_vertical = Control.SIZE_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	h.add_child(name_l)
	var tag := _words(str(r.get("tag", "")), 14, MUTED)
	tag.name = "Tag"
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.size_flags_vertical = Control.SIZE_FILL
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tag)
	var score := _display(str(r["score"]), 13 if ladder else 20)
	score.name = "Score"
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score.size_flags_vertical = Control.SIZE_FILL
	h.add_child(score)
	# The name takes its own width, up to what the rank, the tag and the score
	# leave (an ellipsis past that; a clipped label alone would shrink to nothing).
	var room := ROW_W - RANK_W - 3.0 * 14.0 - _text_w(tag) - _text_w(score)
	name_l.custom_minimum_size.x = minf(_text_w(name_l), maxf(room, 80.0))
	return box


## The rows slide in from the right and fade up, a beat apart (the first ten).
func _slide_row(row: Control, i: int) -> void:
	if not row.is_inside_tree():
		return
	var inner := row.get_node("Inner") as Control
	inner.modulate.a = 0.0
	inner.position.x = 24.0
	var tw := row.create_tween().set_parallel(true)
	var d := minf(i, 10) * ROW_STAGGER_S
	tw.tween_property(inner, "modulate:a", 1.0, ROW_IN_S).set_delay(d).set_ease(Tween.EASE_OUT)
	tw.tween_property(inner, "position:x", 0.0, ROW_IN_S).set_delay(d).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _text_w(l: Label) -> float:
	if l.text == "":
		return 0.0
	var f := l.get_theme_font("font")
	if f == null:
		return 200.0
	return f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x + 8.0


func _words(text: String, size_: int, color := CREAM) -> Label:
	var l := RetroTheme.caps(text, size_, color)
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _display(text: String, size_: int, color := CREAM) -> Label:
	var l := RetroTheme.display(text, size_, color)
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A row's own drawing: the dashed rule over it and your orange band, which
## runs 12 px past the text on both sides.
class RowBox extends Control:
	var rule := false
	var me := false

	func _draw() -> void:
		if me:
			draw_rect(Rect2(-12.0, 0.0, size.x + 24.0, size.y), ME_BG)
		if rule:
			var x := -12.0
			while x < size.x + 12.0:
				draw_rect(Rect2(x, 0.0, minf(8.0, size.x + 12.0 - x), 2.0), Color(CREAM, 0.3))
				x += 14.0
