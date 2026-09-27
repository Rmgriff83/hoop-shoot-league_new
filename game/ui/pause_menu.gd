class_name PauseMenu
extends CanvasLayer
## The pause menu every mode shares (design "Solo Modes HUD"): a dim that
## swallows touches, PAUSED, RESUME, the SHOT HELP row (taps cycle
## App.shot_help; the views read it every frame) and QUIT TO TITLE. Keeps
## processing while the tree is paused so its buttons work. `resumed` and
## `quit` are the screen's to wire.

signal resumed
signal quit

const DIM := Color("#1B1815", 0.78)
const CREAM := RetroTheme.SCENE_TEXT
const HI := Color("#FFCE8A")

var _help_value: Label


func _init() -> void:
	name = "PauseUi"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	var help := ShadowCard.new(CREAM)
	help.name = "ShotHelp"
	help.custom_minimum_size = Vector2(0, 60 + ShadowStyle.OFFSET)
	var hm := _margin(0, 20)
	help.add_child(hm)
	var hr := HBoxContainer.new()
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_child(hr)
	var hl := _text("SHOT HELP", 16, CREAM, true)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hr.add_child(hl)
	_help_value = _text(HudCopy.shot_help_value(App.shot_help), 16, HI)
	_help_value.name = "ShotHelpValue"
	_help_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hr.add_child(_help_value)
	help.pressed.connect(func() -> void:
		App.cycle_shot_help()
		_help_value.text = HudCopy.shot_help_value(App.shot_help)
	)
	col.add_child(help)
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
	if _help_value != null:
		_help_value.text = HudCopy.shot_help_value(App.shot_help)
	visible = true


func close() -> void:
	visible = false


func shot_help_text() -> String:
	return _help_value.text if _help_value != null else ""


func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


func _margin(v: int, h: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v + int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m
