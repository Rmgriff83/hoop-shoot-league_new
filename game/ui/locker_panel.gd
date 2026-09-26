class_name LockerPanel
extends CanvasLayer
## The locker sheet (the top-left locker icon): the prize counter. Your
## ticket balance, then every ball and hoop — owned ones equip on tap, the
## one in use is tagged, unowned ones show their ticket price and buy on tap
## (disabled when short). Purchases go through App.try_buy (tickets), equips
## through App.select (which reloads the set's sounds). Same modal shape as
## SettingsPanel. docs/ECONOMY.md.

signal closed

const DIM := Color(0.02, 0.02, 0.05, 0.72)

var _list: VBoxContainer
var _balance: Label


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
	sheet.position = Vector2(-310, -480)
	sheet.size = Vector2(620, 960)
	sheet.add_theme_stylebox_override("panel", RetroTheme.face(RetroTheme.c("bg"), RetroTheme.RADIUS, 24.0))
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	sheet.add_child(vbox)

	var title := RetroTheme.display("LOCKER", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_balance = RetroTheme.caps("", 16, RetroTheme.c("muted"))
	_balance.name = "Balance"
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_balance)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "Items"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_fill()

	var close_btn := UiFont.flat_button("CLOSE", 24, RetroTheme.c("text"))
	close_btn.name = "Close"
	close_btn.custom_minimum_size = Vector2(0, 64)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


## Every set: owned → equip (tagged when in use); unowned → buy for tickets.
func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.free()
	_balance.text = "%s TICKETS" % RetroTheme.thousands(App.tickets())
	for kind in ["ball", "hoop"]:
		var head := RetroTheme.caps("BALLS" if kind == "ball" else "HOOPS", 16, RetroTheme.c("muted"))
		head.name = "Head_" + kind
		_list.add_child(head)
		var current: String = ""
		var live: CosmeticSet = App.ball_set if kind == "ball" else App.hoop_set
		var starter: CosmeticSet = CosmeticLibrary.starter_ball() if kind == "ball" else CosmeticLibrary.starter_hoop()
		if live != null:
			current = live.id
		elif starter != null:
			current = starter.id
		var sets: Array = CosmeticLibrary.balls() if kind == "ball" else CosmeticLibrary.hoops()
		for cs in sets:
			# The free starter is always yours, whatever the save says.
			var owned: bool = App.owns(kind, cs.id) or (starter != null and cs.id == starter.id)
			var in_use: bool = owned and cs.id == current
			var row := Button.new()
			row.name = "%s_%s" % ["Ball" if kind == "ball" else "Hoop", cs.id]
			var label := str(cs.display_name).to_upper()
			if in_use:
				label += "   -  IN USE"
			elif not owned:
				label += "   -  %s TICKETS" % RetroTheme.thousands(int(cs.price_coins))
			row.text = label
			row.custom_minimum_size = Vector2(0, 60)
			var fill := RetroTheme.c("gold") if in_use else (RetroTheme.c("panel") if owned else RetroTheme.c("bg"))
			RetroTheme.card_button(row, fill, RetroTheme.RADIUS, 12.0)
			row.add_theme_font_size_override("font_size", UiFont.snap(16))
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not owned and App.tickets() < int(cs.price_coins):
				row.disabled = true
			var id := str(cs.id)
			var k: String = kind
			var was_owned := owned
			row.pressed.connect(func() -> void:
				if was_owned:
					if App.select(k, id):
						_fill()
				elif App.try_buy(k, id):
					App.select(k, id)
					_fill()
			)
			_list.add_child(row)


## Row names, in order ("Ball_<id>" / "Hoop_<id>"), for tests.
func rows() -> Array:
	var out := []
	for c in _list.get_children():
		if c is Button:
			out.push_back(c.name)
	return out


func in_use_row(kind := "ball") -> String:
	var prefix := "Ball_" if kind == "ball" else "Hoop_"
	for c in _list.get_children():
		if c is Button and str(c.name).begins_with(prefix) and str(c.text).contains("IN USE"):
			return c.name
	return ""


func close() -> void:
	closed.emit()
	queue_free()
