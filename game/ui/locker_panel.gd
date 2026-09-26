class_name LockerPanel
extends CanvasLayer
## The locker sheet (the top-left locker icon): set your ball from the skins
## you own. One row per owned BallSet, the one in use tagged; tapping a row
## selects it through App.select (which reloads the ball's sounds). More
## sections later. Same modal shape as SettingsPanel.

signal closed

const DIM := Color(0.02, 0.02, 0.05, 0.72)

var _list: VBoxContainer


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
	sheet.position = Vector2(-300, -380)
	sheet.size = Vector2(600, 760)
	sheet.add_theme_stylebox_override("panel", RetroTheme.face(RetroTheme.c("bg"), RetroTheme.RADIUS, 28.0))
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	sheet.add_child(vbox)

	var title := RetroTheme.display("LOCKER", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var caps := RetroTheme.caps("BALL", 16, RetroTheme.c("muted"))
	caps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(caps)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "Balls"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_fill()

	var close_btn := UiFont.flat_button("CLOSE", 24, RetroTheme.c("text"))
	close_btn.name = "Close"
	close_btn.custom_minimum_size = Vector2(0, 64)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


## The owned balls, the current one tagged.
func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.free()
	var starter := CosmeticLibrary.starter_ball()
	var current: String = App.ball_set.id if App.ball_set != null else (starter.id if starter != null else "")
	for b in CosmeticLibrary.balls():
		# The free starter is always yours, whatever the save says.
		if not App.owns("ball", b.id) and not (starter != null and b.id == starter.id):
			continue
		var in_use: bool = b.id == current
		var row := Button.new()
		row.name = "Ball_" + str(b.id)
		row.text = str(b.display_name).to_upper() + ("   -  IN USE" if in_use else "")
		row.custom_minimum_size = Vector2(0, 64)
		RetroTheme.card_button(row, RetroTheme.c("gold") if in_use else RetroTheme.c("panel"), RetroTheme.RADIUS, 12.0)
		row.add_theme_font_size_override("font_size", UiFont.snap(16))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id := str(b.id)
		row.pressed.connect(func() -> void:
			if App.select("ball", id):
				_fill()
		)
		_list.add_child(row)


## Row names, in order ("Ball_<id>"), for tests.
func rows() -> Array:
	var out := []
	for c in _list.get_children():
		out.push_back(c.name)
	return out


func in_use_row() -> String:
	for c in _list.get_children():
		if str(c.text).contains("IN USE"):
			return c.name
	return ""


func close() -> void:
	closed.emit()
	queue_free()
