class_name BoardSheet
extends Control
## The time-trial board popup (design "Home League Context v2" 3a,
## 2026-10-30), opened by a tap on the home's board. The home's chrome fades
## out under a 45 % ink cover (the design draws the bare court there, 0.2 s);
## the cream panel slides in from 80 px right (0.3 s on the snap curve):
## the stopwatch, TIME TRIAL over `ARCADE CAGE · 60 S`, X; ONLINE / YOURS
## (the active one gold); the rows (rank, name, points; your row on
## orange); ONLINE pins YOUR row under the list. CLOSE slides in 0.05 s
## later at the foot. The cover, X and CLOSE close it (`closed`). Built in
## screen coordinates on the home's anchored layer.

signal closed

const LEFT := 36.0
const RIGHT := 42.0
const BOTTOM := 194.0     # the panel ends this far above the screen's bottom
const CLOSE_H := 92.0
const CLOSE_BOTTOM := 72.0
const ROW_H := 64.0
const YOU_H := 68.0
const COVER := 0.45
const COVER_S := 0.2
const CLOSE_DELAY := 0.05
const ORANGE_ROW := Color(0.91, 0.44, 0.23, 0.35)
const CREAM := RetroTheme.SCENE_TEXT
const MUTED := RetroTheme.SCENE_MUTED

var area := "cage"
var _tab := "ONLINE"
var _online: Array = []
var _me: Dictionary = {}
var _yours: Array = []
var _cover: ColorRect
var _panel: ShadowPanel
var _close: ShadowCard
var _tabs: HBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _you_slot: Control
var _t := 0.0


func _init() -> void:
	name = "BoardSheet"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Build for `area`: `online` = RanksCopy.rows of the server's ALL TIME board
## ([] when there is none), `me` its `me` entry, `runs` the device's own runs
## (SaveService.top_scores docs: score, swishes, playedAt).
func setup(p_area: String, online: Array, me: Dictionary, runs: Array) -> void:
	area = p_area
	_online = online
	_me = me
	_yours = runs
	UiLayout.screen_fill(self)
	var h := UiLayout.screen_height()
	_cover = ColorRect.new()
	_cover.name = "Cover"
	_cover.color = Color(RetroTheme.SCENE_OUTLINE, 0.0)
	UiLayout.full_rect(_cover)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and not (ev as InputEventMouseButton).pressed:
			close()
	)
	add_child(_cover)
	var top := UiLayout.header_top(120.0, 2.0)
	_panel = ShadowPanel.new(CREAM, 0.0, 0.28, 0.0)
	_panel.name = "Panel"
	_panel.position = Vector2(LEFT, top)
	_panel.size = Vector2(720.0 - LEFT - RIGHT, h - BOTTOM - top)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_bottom", 22)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pad)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 20)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)
	# The head: the stopwatch, TIME TRIAL over the court and the clock, X.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var watch := PixelIcon.new("icon_stopwatch", Vector2(44, 44))
	watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(watch)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 10)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(words)
	words.add_child(_text("TIME TRIAL", 28, CREAM, true))
	var arena := CosmeticLibrary.get_arena(area)
	var sub := _text("%s · %d S" % [(str(arena.display_name) if arena != null else area).to_upper(), int(TimeTrial.TIME_TRIAL_SECONDS)], 22, CREAM)
	sub.name = "Sub"
	words.add_child(sub)
	var x := HomePage.button("X", CREAM, 24, 64.0)
	x.name = "CloseX"
	x.custom_minimum_size = Vector2(64, 64) + Vector2.ONE * ShadowStyle.OFFSET
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.pressed.connect(close)
	head.add_child(x)
	# ONLINE / YOURS.
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 16 - int(ShadowStyle.OFFSET))
	_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tabs)
	# The rows, and YOUR row pinned under them.
	var win := Control.new()
	win.name = "Window"
	win.size_flags_vertical = Control.SIZE_EXPAND_FILL
	win.clip_contents = true
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(win)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	UiLayout.full_rect(_scroll)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	win.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_list)
	_you_slot = Control.new()
	_you_slot.name = "YouSlot"
	_you_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_you_slot)
	# CLOSE at the foot.
	_close = HomePage.button("CLOSE", CREAM, 26, CLOSE_H)
	_close.name = "Close"
	_close.position = Vector2(LEFT, h - CLOSE_BOTTOM - CLOSE_H)
	_close.size = Vector2(720.0 - LEFT - RIGHT, CLOSE_H) + Vector2.ONE * ShadowStyle.OFFSET
	_close.pressed.connect(close)
	add_child(_close)
	_fill()
	_step(0.0)


func tab() -> String:
	return _tab


func show_tab(t: String) -> void:
	if t == _tab:
		return
	_tab = t
	_fill()


## The rows on view: [[rank, who, pts, mine], …].
func rows() -> Array:
	var out := []
	for r in _list.get_children():
		if r.has_meta("row"):
			out.push_back(r.get_meta("row"))
	return out


func you_row() -> Array:
	return _you_slot.get_child(0).get_meta("row") if _you_slot.get_child_count() > 0 else []


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _process(dt: float) -> void:
	_t += dt
	_step(_t)


## The entrance: the cover fades in (lbFade), the panel and CLOSE slide in (lbIn).
func _step(t: float) -> void:
	_cover.color.a = COVER * CssEase.bezier(CssEase.EASE_OUT, clampf(t / COVER_S, 0.0, 1.0))
	var p := CssEase.lb_in(t)
	_panel.position.x = LEFT + p.x
	_panel.modulate.a = p.y
	var c := CssEase.lb_in(maxf(t - CLOSE_DELAY, 0.0))
	_close.position.x = LEFT + c.x
	_close.modulate.a = c.y


func _fill() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for spec in [["ONLINE", "ONLINE"], ["YOURS", "YOURS"]]:
		var on: bool = _tab == str(spec[0])
		var b := HomePage.button(str(spec[1]), RetroTheme.c("gold") if on else CREAM, 20, 60.0)
		b.name = "Tab_" + str(spec[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = spec[0]
		b.pressed.connect(func() -> void: show_tab(key))
		_tabs.add_child(b)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for c in _you_slot.get_children():
		_you_slot.remove_child(c)
		c.queue_free()
	_you_slot.custom_minimum_size = Vector2.ZERO
	var list: Array = []
	if _tab == "ONLINE":
		for r in _online:
			list.push_back([str(r["rank"]).trim_prefix("#"), str(r["name"]), str(r["score"]), bool(r.get("me", false))])
	else:
		list = BoardSheet.your_rows(_yours, Time.get_unix_time_from_system())
	if list.is_empty():
		var empty := _text("NO ONLINE BOARD YET" if _tab == "ONLINE" else "NO RUNS HERE YET", 22, MUTED)
		empty.name = "Empty"
		empty.custom_minimum_size = Vector2(0, ROW_H)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(empty)
	for i in list.size():
		_list.add_child(_row(list[i], ROW_H, i > 0, Color(CREAM, 0.3)))
	if _tab == "ONLINE":
		var you := {}
		for r in _online:
			if bool(r.get("me", false)):
				you = r
		var rank := int(str(you.get("rank", "#0")).trim_prefix("#")) if not you.is_empty() else int(_me.get("rank", 0))
		var score := str(you.get("score", "")) if not you.is_empty() else str(int(_me.get("score", 0)))
		if rank > 0:
			var yr := _row([str(rank), "YOU", score, true], YOU_H, true, CREAM)
			yr.name = "YouRow"
			yr.position = Vector2(-10, 0)
			yr.size = Vector2(720.0 - LEFT - RIGHT - 48.0 + 20.0, YOU_H)
			_you_slot.add_child(yr)
			_you_slot.custom_minimum_size = Vector2(0, YOU_H)
	_scroll.scroll_vertical = 0


## The device's own runs as rows (pure): best first, `TODAY · 7 SW`,
## `YESTERDAY · 5 SW` or `OCT 14 · 4 SW` from `playedAt` (ms), the best on orange.
static func your_rows(runs: Array, now_s: float) -> Array:
	var out := []
	for i in runs.size():
		var d: Dictionary = runs[i]
		out.push_back([str(i + 1), "%s · %d SW" % [day_label(float(d.get("playedAt", 0)) / 1000.0, now_s), int(d.get("swishes", 0))], str(int(d.get("score", 0))), i == 0])
	return out


## TODAY / YESTERDAY / `OCT 14` for a unix time, against `now_s` (local days).
static func day_label(at_s: float, now_s: float) -> String:
	var bias := float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	var day := floori((at_s + bias) / 86400.0)
	var today := floori((now_s + bias) / 86400.0)
	if day == today:
		return "TODAY"
	if day == today - 1:
		return "YESTERDAY"
	var dt := Time.get_datetime_dict_from_unix_time(int(at_s + bias))
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	return "%s %d" % [months[clampi(int(dt["month"]) - 1, 0, 11)], int(dt["day"])]


func _row(r: Array, h: float, rule: bool, rule_color: Color) -> Control:
	var mine := bool(r[3])
	var wrap := BoardPreview.RowBox.new(rule_color if rule else Color.TRANSPARENT, ORANGE_ROW if mine else Color.TRANSPARENT)
	wrap.name = "Row" + str(r[0])
	wrap.set_meta("row", r)
	wrap.custom_minimum_size = Vector2(0, h)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	UiLayout.full_rect(row)
	row.offset_left = 10
	row.offset_right = -10
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)
	var n := _text(str(r[0]), 22, CREAM, true)
	n.name = "Rank"
	n.custom_minimum_size = Vector2(64, 0)
	row.add_child(n)
	var w := _text(str(r[1]), 26, CREAM)
	w.name = "Name"
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.clip_text = true
	w.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(w)
	var p := _text(str(r[2]), 24, CREAM, true)
	p.name = "Pts"
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(p)
	for l in [n, w, p]:
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return wrap


func _text(text: String, size_: int, color: Color, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l
