class_name SettingsPanel
extends CanvasLayer
## The menu's settings sheet: a dimmed modal in the RetroTheme with the
## player settings (shot help, dark mode), the dev-only tuning toggle (debug
## builds — the phone build Ross deploys is one; a store build hides it),
## credits, and close. `closed` fires when it goes away; `dark_mode_changed`
## when the theme flips so the screen behind can rebuild.

signal closed
signal dark_mode_changed(on: bool)

const DIM := Color(0.02, 0.02, 0.05, 0.72)

var _shot_help: Button
var _dark: Button
var _tuning: Button


func _init() -> void:
	layer = 30


func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			close()
	)
	add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.position = Vector2(-300, -300)
	sheet.size = Vector2(600, 600)
	sheet.add_theme_stylebox_override("panel", RetroTheme.face(RetroTheme.c("bg"), RetroTheme.RADIUS, 28.0))
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	sheet.add_child(vbox)

	var title := RetroTheme.display("SETTINGS", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(_spacer(6))

	_shot_help = _row("ShotHelp", _shot_help_label(), RetroTheme.c("gold"))
	_shot_help.pressed.connect(func() -> void:
		App.cycle_shot_help()
		_shot_help.text = _shot_help_label()
	)
	vbox.add_child(_shot_help)

	_dark = _row("DarkMode", _dark_label(), RetroTheme.c("teal"))
	_dark.pressed.connect(func() -> void:
		App.set_dark_mode(not App.dark_mode)
		_dark.text = _dark_label()
		dark_mode_changed.emit(App.dark_mode)
		_restyle()
	)
	vbox.add_child(_dark)

	if OS.is_debug_build():
		_tuning = _row("Tuning", _tuning_label(), RetroTheme.c("panel"))
		_tuning.pressed.connect(func() -> void:
			App.set_tuning_mode(not App.tuning_mode)
			_tuning.text = _tuning_label()
		)
		vbox.add_child(_tuning)
		var dev := RetroTheme.caps("DEV BUILD ONLY", 16, RetroTheme.c("muted"))
		dev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(dev)

	var credits := _row("Credits", "CREDITS", RetroTheme.c("panel"))
	credits.pressed.connect(App.to_credits)
	vbox.add_child(credits)
	vbox.add_child(_spacer(6))
	var close_btn := UiFont.flat_button("CLOSE", 24, RetroTheme.c("text"))
	close_btn.name = "Close"
	close_btn.custom_minimum_size = Vector2(0, 64)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


func _row(name_: String, text: String, fill: Color) -> Button:
	var b := Button.new()
	b.name = name_
	b.text = text
	b.custom_minimum_size = Vector2(0, 68)
	RetroTheme.card_button(b, fill, RetroTheme.RADIUS, 12.0)
	b.add_theme_font_size_override("font_size", UiFont.snap(16))
	return b


## The theme flipped under us: rebuild the sheet in the new palette.
func _restyle() -> void:
	for c in get_children():
		c.queue_free()
	_ready()


func has_tuning() -> bool:
	return _tuning != null


func has_dark_mode() -> bool:
	return _dark != null


func close() -> void:
	closed.emit()
	queue_free()


static func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _shot_help_label() -> String:
	return "SHOT HELP: %s" % App.SHOT_HELP_LABELS[App.shot_help]


func _dark_label() -> String:
	return "DARK MODE: ON" if App.dark_mode else "DARK MODE: OFF"


func _tuning_label() -> String:
	return "TUNING: ON" if App.tuning_mode else "TUNING: OFF"
