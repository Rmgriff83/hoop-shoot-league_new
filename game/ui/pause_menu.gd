class_name PauseMenu
extends CanvasLayer
## The pause menu every mode shares (design "Solo Modes HUD"): a dim that
## swallows touches, PAUSED, RESUME, the SHOT HELP row (taps cycle
## App.shot_help; the views read it every frame), the BALL row (taps cycle
## the owned balls — the equip is global), the NET row (taps cycle the owned
## nets of this court's kind — the equip is this court's, docs/LOCKER.md →
## NETS) and QUIT TO TITLE. Keeps processing while the tree is paused so its
## buttons work. `resumed`, `quit`, `ball_changed` and `net_changed` are the
## screen's to wire (the screen swaps the live pool / court).

signal resumed
signal quit
signal ball_changed(id: String)
signal net_changed(id: String)

const DIM := Color("#1B1815", 0.78)
const CREAM := RetroTheme.SCENE_TEXT
const HI := Color("#FFCE8A")

var _help_value: Label
var _ball_value: Label
var _net_value: Label
var _ball_chevron: Label
var _net_chevron: Label
var _area := "cage"
var _net_kind := "cotton"


func _init() -> void:
	name = "PauseUi"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	UiLayout.full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # no flicks through the menu
	add_child(dim)
	var col := VBoxContainer.new()
	col.name = "Menu"
	col.position = Vector2(140, 400)
	col.size = Vector2(720 - 280, 0)
	col.add_theme_constant_override("separation", 24)
	add_child(col)
	var title := _text("PAUSED", 56, RetroTheme.LIGHT["gold"], true)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetroTheme.dithered(title)
	col.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var resume := ShadowCard.new(RetroTheme.c("orange"))
	resume.name = "Resume"
	resume.custom_minimum_size = Vector2(0, 96 + ShadowStyle.OFFSET)
	var rm := _margin(0, 22)
	resume.add_child(rm)
	var rr := HBoxContainer.new()
	rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rm.add_child(rr)
	var rl := _text("RESUME", 32, CREAM, true)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rr.add_child(rl)
	var rc := _text(">", 24, CREAM, true)
	rc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rr.add_child(rc)
	resume.pressed.connect(func() -> void: resumed.emit())
	col.add_child(resume)
	var help: Array = _value_row("ShotHelp", "SHOT HELP")
	_help_value = help[1]
	_help_value.text = HudCopy.shot_help_value(App.shot_help)
	(help[0] as ShadowCard).pressed.connect(func() -> void:
		App.cycle_shot_help()
		_help_value.text = HudCopy.shot_help_value(App.shot_help)
	)
	col.add_child(help[0])
	var ball: Array = _value_row("Ball", "BALL")
	_ball_value = ball[1]
	_ball_chevron = ball[2]
	(ball[0] as ShadowCard).pressed.connect(_cycle_ball)
	col.add_child(ball[0])
	var net: Array = _value_row("Net", "NET")
	_net_value = net[1]
	_net_chevron = net[2]
	(net[0] as ShadowCard).pressed.connect(_cycle_net)
	col.add_child(net[0])
	var q := ShadowCard.new(CREAM)
	q.name = "Quit"
	q.custom_minimum_size = Vector2(0, 60 + ShadowStyle.OFFSET)
	q.text = "QUIT TO TITLE"
	q.add_theme_font_override("font", UiFont.display())
	q.add_theme_font_size_override("font_size", UiFont.snap(16))
	RetroTheme.on_scene(q)
	q.pressed.connect(func() -> void: quit.emit())
	col.add_child(q)


func open() -> void:
	_area = str(App.mode_config(App.next_mode).get("location", "cage"))
	_net_kind = App.net_kind_for_mode(App.next_mode)
	_refresh_values()
	visible = true


func close() -> void:
	visible = false


func shot_help_text() -> String:
	return _help_value.text if _help_value != null else ""


func ball_text() -> String:
	return _ball_value.text if _ball_value != null else ""


func net_text() -> String:
	return _net_value.text if _net_value != null else ""


## A cream row with a label on the left and a value (+ chevron) on the right:
## [card, value label, chevron label].
func _value_row(name_: String, label: String) -> Array:
	var card := ShadowCard.new(CREAM)
	card.name = name_
	card.custom_minimum_size = Vector2(0, 60 + ShadowStyle.OFFSET)
	var m := _margin(0, 20)
	card.add_child(m)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	m.add_child(row)
	var l := _text(label, 16, CREAM, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var value := _text("", 16, HI)
	value.name = name_ + "Value"
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var chevron := _text(">", 16, HI, true)
	chevron.name = name_ + "Chevron"
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)
	return [card, value, chevron]


## The owned balls, in library order.
func _ball_ids() -> Array:
	var out: Array = []
	for b in CosmeticLibrary.balls():
		if App.owns("ball", b.id):
			out.push_back(b.id)
	return out


## The owned nets, in library order (any kind hangs on any court).
func _net_ids() -> Array:
	var out: Array = []
	for n in CosmeticLibrary.nets():
		if App.owns("net", n.id):
			out.push_back(n.id)
	return out


func _refresh_values() -> void:
	if _help_value != null:
		_help_value.text = HudCopy.shot_help_value(App.shot_help)
	if _ball_value != null:
		_ball_value.text = str(App.ball_set.display_name).to_upper() if App.ball_set != null else ""
		_set_choice(_ball_value, _ball_chevron, _ball_ids().size() > 1)
	if _net_value != null:
		var ns := App.net_set_for(_area)
		_net_value.text = str(ns.display_name).to_upper() if ns != null else ""
		_set_choice(_net_value, _net_chevron, _net_ids().size() > 1)


## One option: the value reads muted and the chevron goes.
func _set_choice(value: Label, chevron: Label, more: bool) -> void:
	value.add_theme_color_override("font_color", HI if more else CREAM)
	chevron.visible = more


static func _next(ids: Array, current: String) -> String:
	if ids.is_empty():
		return ""
	var i := ids.find(current)
	return str(ids[(i + 1) % ids.size()])


func _cycle_ball() -> void:
	var ids := _ball_ids()
	if ids.size() <= 1:
		return
	var id := _next(ids, App.ball_set.id if App.ball_set != null else "")
	if App.select("ball", id):
		_refresh_values()
		ball_changed.emit(id)


func _cycle_net() -> void:
	var ids := _net_ids()
	if ids.size() <= 1:
		return
	var cur := App.net_set_for(_area)
	var id := _next(ids, cur.id if cur != null else "")
	if App.select_net(_area, id):
		_refresh_values()
		net_changed.emit(id)


func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


func _margin(v: int, h: int) -> MarginContainer:
	var m := MarginContainer.new()
	UiLayout.full_rect(m)
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v + int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m
