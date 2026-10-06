class_name RanksPage
extends CanvasLayer
## The Ranks page (docs/HOME.md → Ranks): the global time-trial boards per
## area. A sheet in the RetroTheme with `<` RANKS and your handle, the three
## area tabs (a locked area's tab is greyed with the level that opens it),
## THIS WEEK / ALL TIME, a status line, the top 50 as rows (the first three
## ranks in gold, your own row on orange), and your line pinned under the
## list. The page owns no network: it emits `request(area, period)` and is
## fed by set_board / set_offline (the title wires it to Net; tests and QA
## feed it a fixture).

signal closed
signal request(area: String, period: String)

const PAD := Vector2(28, 44)
const TAB_SIZE := Vector2(200, 56)
const CHIP_SIZE := Vector2(176, 44)
const ROW_H := 60.0
const ME_H := 64.0
const SLIDE_S := 0.22

var _root: Control
var _tabs: Dictionary = {}
var _locked: Dictionary = {}
var _chips: Dictionary = {}
var _status: Label
var _list: VBoxContainer
var _me: Label
var _area := "cage"
var _period := "week"
var _rows := 0


func _init() -> void:
	layer = 30


func build(tabs: Array, handle: String) -> Control:
	_tabs.clear()
	_chips.clear()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "RanksRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = RetroTheme.c("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	# < RANKS                                    BRICK BARON 42
	var head := HBoxContainer.new()
	head.name = "Head"
	head.position = PAD
	head.size = Vector2(720 - PAD.x * 2, 56)
	head.add_theme_constant_override("separation", 20)
	_root.add_child(head)
	var back := Button.new()
	back.name = "Back"
	back.text = "<"
	back.custom_minimum_size = Vector2(56 + ShadowStyle.OFFSET, 56 + ShadowStyle.OFFSET)
	RetroTheme.card_button(back, RetroTheme.c("panel"), RetroTheme.RADIUS, 0.0)
	back.add_theme_font_size_override("font_size", UiFont.snap(24))
	back.add_theme_color_override("font_color", RetroTheme.c("text"))
	back.add_theme_color_override("font_pressed_color", RetroTheme.c("text"))
	back.add_theme_color_override("font_hover_color", RetroTheme.c("text"))
	back.pressed.connect(close)
	head.add_child(back)
	var title := RetroTheme.display("RANKS", 32)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var who := RetroTheme.caps(handle, 16, RetroTheme.c("muted"))
	who.name = "Handle"
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(who)
	# The area tabs.
	var tab_row := HBoxContainer.new()
	tab_row.name = "Tabs"
	tab_row.position = Vector2(PAD.x, PAD.y + 56 + 24)
	tab_row.size = Vector2(720 - PAD.x * 2, TAB_SIZE.y + ShadowStyle.OFFSET)
	tab_row.add_theme_constant_override("separation", 16)
	_root.add_child(tab_row)
	for tb in tabs:
		var area := str(tb["area"])
		var locked := bool(tb.get("locked", false))
		var text := str(tb["text"]) if not locked else "%s · %s" % [str(tb["text"]), str(tb["lock_text"])]
		var b := _card("Tab_" + area, TAB_SIZE, text, 16 if not locked else 12)
		b.disabled = locked
		b.pressed.connect(func() -> void: select(area, _period))
		tab_row.add_child(b)
		_tabs[area] = b
		_locked[area] = locked
	# THIS WEEK / ALL TIME + the status line.
	var chip_row := HBoxContainer.new()
	chip_row.name = "Chips"
	chip_row.position = Vector2(PAD.x, tab_row.position.y + TAB_SIZE.y + ShadowStyle.OFFSET + 20)
	chip_row.size = Vector2(720 - PAD.x * 2, CHIP_SIZE.y + ShadowStyle.OFFSET)
	chip_row.add_theme_constant_override("separation", 12)
	_root.add_child(chip_row)
	for p in RanksCopy.PERIODS:
		var period := str(p)
		var c := _card("Period" + period.capitalize(), CHIP_SIZE, RanksCopy.period_name(period), 12)
		c.pressed.connect(func() -> void: select(_area, period))
		chip_row.add_child(c)
		_chips[period] = c
	# The status line, on its own row so the long ones never clip.
	_status = RetroTheme.caps(RanksCopy.loading_status(), 14, RetroTheme.c("muted"))
	_status.name = "Status"
	_status.position = Vector2(PAD.x, chip_row.position.y + CHIP_SIZE.y + ShadowStyle.OFFSET + 14)
	_status.size = Vector2(720 - PAD.x * 2, 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	_root.add_child(_status)
	# The rows.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = Vector2(PAD.x, _status.position.y + 24 + 14)
	scroll.size = Vector2(720 - PAD.x * 2, 1280 - scroll.position.y - ME_H - PAD.x - 20)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	# YOU · #12 · 31, pinned.
	var me_box := PanelContainer.new()
	me_box.name = "MeBox"
	me_box.position = Vector2(PAD.x, 1280 - PAD.x - ME_H)
	me_box.size = Vector2(720 - PAD.x * 2, ME_H)
	me_box.add_theme_stylebox_override("panel", RetroTheme.flat(RetroTheme.c("ink"), RetroTheme.RADIUS, 16.0))
	_root.add_child(me_box)
	_me = RetroTheme.display("", 16, RetroTheme.c("bg"))
	_me.name = "MeLine"
	_me.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_me.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	me_box.add_child(_me)
	_restyle()
	return _root


## Show an area + period: the tabs restyle, the list clears to LOADING and
## `request` asks for the data. A locked area is ignored.
func select(area: String, period: String) -> void:
	if bool(_locked.get(area, false)) or not _tabs.has(area):
		return
	_area = area
	_period = period if RanksCopy.PERIODS.has(period) else "week"
	_restyle()
	_clear()
	_status.text = RanksCopy.loading_status()
	_me.text = ""
	request.emit(_area, _period)


## A server board for (area, period); anything for another view is stale and dropped.
func set_board(area: String, period: String, data: Dictionary) -> void:
	if area != _area or period != _period:
		return
	_clear()
	var rows := RanksCopy.rows(data)
	for r in rows:
		_list.add_child(_row(r))
	_rows = rows.size()
	_status.text = RanksCopy.status(_period, _rows)
	_me.text = RanksCopy.me_line(data)


## No server: the device's own board for the area instead.
func set_offline(area: String, period: String, local_top: Array) -> void:
	if area != _area or period != _period:
		return
	_clear()
	var rows := RanksCopy.local_rows(local_top)
	for r in rows:
		_list.add_child(_row(r))
	_rows = rows.size()
	_status.text = RanksCopy.offline_status()
	_me.text = RanksCopy.local_me_line(local_top)


func area() -> String:
	return _area


func period() -> String:
	return _period


func status_text() -> String:
	return _status.text


func me_text() -> String:
	return _me.text


func row_count() -> int:
	return _rows


func tab(area_: String) -> Button:
	return _tabs.get(area_, null)


func close() -> void:
	closed.emit()
	queue_free()


## Slide the sheet in from the right (the title opens it this way).
func slide_in() -> void:
	if _root == null:
		return
	_root.position.x = 720.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_root, "position:x", 0.0, SLIDE_S)


func _clear() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows = 0


## The active tab / chip wears the solid ink face with text in the page's
## colour; the rest stay see-through with ink text.
func _restyle() -> void:
	for area in _tabs:
		_style(_tabs[area], area == _area)
	for period in _chips:
		_style(_chips[period], period == _period)


## A tab / chip: a ShadowCard with its words in a child Label (a Button's own
## text draws under the card face; a child draws over it).
func _card(name_: String, size_: Vector2, text: String, font_size: int) -> ShadowCard:
	var b := ShadowCard.new(RetroTheme.c("ink"))
	b.name = name_
	b.custom_minimum_size = size_ + Vector2.ONE * ShadowStyle.OFFSET
	var l := RetroTheme.display(text, font_size, RetroTheme.c("text"))
	l.name = "Text"
	l.position = Vector2.ZERO
	l.size = size_
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	return b


func _style(b: ShadowCard, active: bool) -> void:
	var ink := RetroTheme.c("ink")
	if active:
		b.fill = ink
		b.dot = ink
		b.shadow = Color(RetroTheme.c("orange"), ShadowStyle.SHADOW_ALPHA)
	else:
		b.fill = Color.TRANSPARENT
		b.dot = Color.TRANSPARENT
		b.shadow = Color.TRANSPARENT
	var fg := RetroTheme.c("bg") if active else RetroTheme.c("text")
	if b.disabled:
		fg = RetroTheme.c("muted")
	var l := b.get_node_or_null("Text") as Label
	if l != null:
		l.add_theme_color_override("font_color", fg)
	b.queue_redraw()


## One board row: #n · NAME · score, gold for the top three, orange for you.
func _row(r: Dictionary) -> Control:
	var me := bool(r.get("me", false))
	var box := PanelContainer.new()
	box.name = "Row" + str(r["rank"]).trim_prefix("#")
	box.custom_minimum_size = Vector2(0, ROW_H)
	box.add_theme_stylebox_override("panel", RetroTheme.flat(RetroTheme.c("orange") if me else RetroTheme.c("panel"), RetroTheme.RADIUS, 14.0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	box.add_child(h)
	var n := int(str(r["rank"]).trim_prefix("#"))
	var text_c := RetroTheme.c("card_text") if me else RetroTheme.c("text")
	var rank := RetroTheme.display(str(r["rank"]), 16, RetroTheme.c("gold") if n <= RanksCopy.TOP_COLOURS and not me else text_c)
	rank.name = "Rank"
	rank.custom_minimum_size = Vector2(80, 0)
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rank)
	var name_l := RetroTheme.caps(str(r["name"]), 20, text_c)
	name_l.name = "Name"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name_l)
	var score := RetroTheme.display(str(r["score"]), 20, text_c)
	score.name = "Score"
	score.custom_minimum_size = Vector2(96, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(score)
	return box
