class_name SettingsPanel
extends CanvasLayer
## The menu's settings sheet: a dimmed modal in the RetroTheme with the
## player settings (shot help, dark mode), the PLAYER section (your handle,
## editable; MOVE TO NEW PHONE's one-time code; ENTER CODE on the new one —
## docs/BACKEND.md → Identity), the dev-only tuning toggle (debug builds —
## the phone build Ross deploys is one; a store build hides it), credits,
## and close. `closed` fires when it goes away; `dark_mode_changed` when the
## theme flips so the screen behind can rebuild.

signal closed
signal dark_mode_changed(on: bool)

const DIM := Color(0.02, 0.02, 0.05, 0.72)
const SHEET := Vector2(600, 910)

var _shot_help: Button
var _dark: Button
var _tuning: Button
var _name_edit: LineEdit
var _player_status: Label
var _move: Button
var _code_row: HBoxContainer
var _code_edit: LineEdit


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
	sheet.position = -SHEET / 2.0
	sheet.size = SHEET
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

	_build_player(vbox)

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


## PLAYER: the handle (edit + SAVE), its status line, MOVE TO NEW PHONE,
## ENTER CODE (a code field + CLAIM).
func _build_player(vbox: VBoxContainer) -> void:
	var head := RetroTheme.caps("PLAYER", 16, RetroTheme.c("muted"))
	head.name = "PlayerHead"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(head)
	var acct := Net.account()
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 12)
	vbox.add_child(name_row)
	_name_edit = _edit("NameEdit", str(acct.get("name", "")), HandleWords.NAME_MAX)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	var tag := RetroTheme.display(str(acct.get("tag", "")), 16, RetroTheme.c("muted"))
	tag.name = "Tag"
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(tag)
	var save := _row("SaveName", "SAVE", RetroTheme.c("gold"))
	save.custom_minimum_size = Vector2(120, 68)
	save.pressed.connect(_save_name)
	name_row.add_child(save)
	_player_status = RetroTheme.caps(_player_status_text(), 14, RetroTheme.c("muted"))
	_player_status.name = "PlayerStatus"
	_player_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_player_status)
	var cloud := RetroTheme.caps(Net.cloud_line(), 14, RetroTheme.c("muted"))
	cloud.name = "CloudLine"
	cloud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cloud)
	_move = _row("MoveToPhone", "MOVE TO NEW PHONE", RetroTheme.c("teal"))
	_move.pressed.connect(_move_to_phone)
	vbox.add_child(_move)
	var enter := _row("EnterCode", "ENTER CODE", RetroTheme.c("panel"))
	enter.pressed.connect(func() -> void: _code_row.visible = not _code_row.visible)
	vbox.add_child(enter)
	_code_row = HBoxContainer.new()
	_code_row.name = "CodeRow"
	_code_row.visible = false
	_code_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_code_row)
	_code_edit = _edit("CodeEdit", "", 9)
	_code_edit.placeholder_text = "8-LETTER CODE"
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.add_child(_code_edit)
	var claim := _row("Claim", "CLAIM", RetroTheme.c("gold"))
	claim.custom_minimum_size = Vector2(120, 68)
	claim.pressed.connect(_claim_code)
	_code_row.add_child(claim)


func _edit(name_: String, text: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.name = name_
	e.text = text
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 68)
	e.add_theme_font_override("font", UiFont.body_bold())
	e.add_theme_font_size_override("font_size", UiFont.snap(20))
	e.add_theme_color_override("font_color", RetroTheme.c("text"))
	e.add_theme_color_override("font_placeholder_color", RetroTheme.c("muted"))
	e.add_theme_color_override("caret_color", RetroTheme.c("text"))
	e.add_theme_stylebox_override("normal", RetroTheme.flat(RetroTheme.c("panel"), RetroTheme.RADIUS, 16.0))
	e.add_theme_stylebox_override("focus", RetroTheme.flat(RetroTheme.c("panel").lightened(0.05), RetroTheme.RADIUS, 16.0))
	return e


func _player_status_text() -> String:
	if not Net.enabled:
		return "OFFLINE · %s" % Net.handle()
	return Net.handle() if Net.registered() else "NOT SIGNED UP YET · %s" % Net.handle()


func _save_name() -> void:
	var name := HandleWords.normalize(_name_edit.text)
	if not HandleWords.valid(name):
		_player_status.text = "NAME NOT ALLOWED · A-Z, 0-9, 3-24"
		return
	_player_status.text = "SAVING..."
	var ok: bool = await Net.rename(name)
	if not is_instance_valid(_player_status):
		return
	_player_status.text = "SAVED · %s" % Net.handle() if ok else "NO SIGNAL · TRY AGAIN LATER"
	_name_edit.text = str(Net.account().get("name", name))


func _move_to_phone() -> void:
	_move.text = "ASKING..."
	var r: Dictionary = await Net.transfer_code()
	if not is_instance_valid(_move):
		return
	if r.is_empty():
		_move.text = "NO SIGNAL · TRY AGAIN LATER"
		return
	var code := str(r.get("code", ""))
	_move.text = "CODE %s %s · 15 MIN" % [code.substr(0, 4), code.substr(4)]


func _claim_code() -> void:
	var code := _code_edit.text.strip_edges().replace(" ", "").to_upper()
	if code.length() != 8:
		_player_status.text = "A CODE IS 8 LETTERS"
		return
	_player_status.text = "CLAIMING..."
	var ok: bool = await Net.claim_transfer(code)
	if not is_instance_valid(_player_status):
		return
	if ok:
		_player_status.text = "WELCOME BACK · %s" % Net.handle()
		_name_edit.text = str(Net.account().get("name", ""))
		_code_row.visible = false
	else:
		_player_status.text = "CODE NOT FOUND OR EXPIRED"


func has_player() -> bool:
	return _name_edit != null


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
