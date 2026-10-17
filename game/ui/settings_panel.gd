class_name SettingsPanel
extends HomePage
## The settings page (the menu button, docs/HOME.md): a page over the area
## like the locker — the home UI slides out left, settings in from the
## right — with every row a dotted face: cream by default, gold when a
## toggle is on, orange for SAVE / CLAIM. The player settings (shot help,
## dark mode), the PLAYER section (your handle, editable; MOVE TO NEW
## PHONE's one-time code; ENTER CODE on the new one; the platform link row,
## hidden until a store backend exists; DELETE ACCOUNT, two taps —
## docs/BACKEND.md → Identity / Platform identity), the dev-only tuning toggle (debug builds — the phone build
## Ross deploys is one; a store build hides it), credits, and CLOSE.
## `closed` fires when it goes away; `dark_mode_changed` when the theme
## flips so the screen behind can rebuild (the page itself wears the scene
## colours on both palettes).

signal dark_mode_changed(on: bool)

const ROW_H := 68.0
const FIELD_BG := Color(34.0 / 255.0, 28.0 / 255.0, 24.0 / 255.0, 0.55)

var _shot_help: ShadowCard
var _dark: ShadowCard
var _tuning: ShadowCard
var _gates: ShadowCard
var _name_edit: LineEdit
var _town_edit: LineEdit
var _player_status: Label
var _move: ShadowCard
var _enter: ShadowCard
var _code_row: HBoxContainer
var _code_edit: LineEdit
var _list: VBoxContainer
var _link_row: ShadowCard
var _delete: ShadowCard
var _delete_armed_at := -1.0
## DELETE ACCOUNT needs a second tap within this many seconds.
const DELETE_ARM_S := 8.0


func _build() -> void:
	head("SETTINGS", false)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 16)
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(_list)

	_shot_help = _row("ShotHelp", _shot_help_label(), App.shot_help > 0)
	_shot_help.pressed.connect(func() -> void:
		App.cycle_shot_help()
		_shot_help.text = _shot_help_label()
		_tone(_shot_help, App.shot_help > 0)
	)
	_list.add_child(_shot_help)

	_dark = _row("DarkMode", _dark_label(), App.dark_mode)
	_dark.pressed.connect(func() -> void:
		App.set_dark_mode(not App.dark_mode)
		_dark.text = _dark_label()
		_tone(_dark, App.dark_mode)
		dark_mode_changed.emit(App.dark_mode)
	)
	_list.add_child(_dark)
	_list.add_child(_spacer(8))

	_build_player()
	_list.add_child(_spacer(8))

	if OS.is_debug_build():
		_tuning = _row("Tuning", _tuning_label(), App.tuning_mode)
		_tuning.pressed.connect(func() -> void:
			App.set_tuning_mode(not App.tuning_mode)
			_tuning.text = _tuning_label()
			_tone(_tuning, App.tuning_mode)
		)
		_list.add_child(_tuning)
		# LEVEL GATES (Ross, 2026-10-17): play with the areas and leagues locked
		# by level, the way a release build does — a new user's game.
		_gates = _row("Gates", _gates_label(), App.league_gating)
		_gates.pressed.connect(func() -> void:
			App.set_league_gating(not App.league_gating)
			_gates.text = _gates_label()
			_tone(_gates, App.league_gating)
		)
		_list.add_child(_gates)
		var dev := words("DEV BUILD ONLY", 16)
		dev.name = "DevLine"
		_list.add_child(dev)

	var credits := _row("Credits", "CREDITS", false)
	credits.pressed.connect(App.to_credits)
	_list.add_child(credits)
	close_button()


## PLAYER: the handle (edit + SAVE), its status and cloud lines, MOVE TO NEW
## PHONE, ENTER CODE (a code field + CLAIM).
func _build_player() -> void:
	var head_ := words("PLAYER", 16)
	head_.name = "PlayerHead"
	_list.add_child(head_)
	var acct := Net.account()
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 12)
	_list.add_child(name_row)
	_name_edit = _edit("NameEdit", str(acct.get("name", "")), HandleWords.NAME_MAX)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	var tag := words(str(acct.get("tag", "")), 16, true)
	tag.name = "Tag"
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(tag)
	var save := _action("SaveName", "SAVE")
	save.pressed.connect(_save_name)
	name_row.add_child(save)
	# HOMETOWN (design 35a): a synced setting, saved on the spot.
	var town_row := HBoxContainer.new()
	town_row.name = "TownRow"
	town_row.add_theme_constant_override("separation", 12)
	_list.add_child(town_row)
	_town_edit = _edit("TownEdit", App.hometown(), Towns.TOWN_MAX)
	_town_edit.placeholder_text = "HOMETOWN"
	_town_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	town_row.add_child(_town_edit)
	var save_town := _action("SaveTown", "SAVE")
	save_town.pressed.connect(_save_town)
	town_row.add_child(save_town)
	_player_status = words(_player_status_text(), 14)
	_player_status.name = "PlayerStatus"
	_list.add_child(_player_status)
	var cloud := words(Net.cloud_line(), 14)
	cloud.name = "CloudLine"
	_list.add_child(cloud)
	_move = _row("MoveToPhone", "MOVE TO NEW PHONE", false)
	_move.pressed.connect(_move_to_phone)
	_list.add_child(_move)
	_enter = _row("EnterCode", "ENTER CODE", false)
	_enter.pressed.connect(func() -> void:
		_code_row.visible = not _code_row.visible
		_tone(_enter, _code_row.visible)
	)
	_list.add_child(_enter)
	_code_row = HBoxContainer.new()
	_code_row.name = "CodeRow"
	_code_row.visible = false
	_code_row.add_theme_constant_override("separation", 12)
	_list.add_child(_code_row)
	_code_edit = _edit("CodeEdit", "", 9)
	_code_edit.placeholder_text = "8-LETTER CODE"
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.add_child(_code_edit)
	var claim := _action("Claim", "CLAIM")
	claim.pressed.connect(_claim_code)
	_code_row.add_child(claim)
	# The platform link (docs/BACKEND.md → Platform identity): hidden while
	# the backend is the null one (no Game Center / Play Games plugin yet).
	_link_row = _row("PlatformLink", _link_text(), Platform.is_linked())
	_link_row.visible = Platform.backend.is_available()
	_link_row.pressed.connect(_toggle_link)
	_list.add_child(_link_row)
	# Account deletion (Apple 5.1.1(v)): armed by one tap, done by a second.
	_delete = _row("DeleteAccount", "DELETE ACCOUNT", false)
	_delete.color = RetroTheme.LIGHT["orange"]
	_delete.pressed.connect(_delete_account)
	_list.add_child(_delete)


## A see-through field: a cream rule around a dark wash, bold cream words.
func _edit(name_: String, text: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.name = name_
	e.text = text
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, ROW_H)
	e.add_theme_font_override("font", UiFont.body_bold())
	e.add_theme_font_size_override("font_size", UiFont.snap(20))
	e.add_theme_color_override("font_color", CREAM)
	e.add_theme_color_override("font_placeholder_color", Color("#A89E94"))
	e.add_theme_color_override("caret_color", CREAM)
	e.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	e.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = FIELD_BG if state == "normal" else Color(FIELD_BG, 0.7)
		sb.border_color = CREAM
		sb.set_border_width_all(2)
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		e.add_theme_stylebox_override(state, sb)
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


func _save_town() -> void:
	var town := Towns.normalize(_town_edit.text)
	if not Towns.valid(town):
		_player_status.text = "PICK A HOMETOWN"
		return
	App.set_hometown(town)
	_town_edit.text = town
	_player_status.text = "SAVED · %s" % town


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
		_tone(_enter, false)
	else:
		_player_status.text = "CODE NOT FOUND OR EXPIRED"


func has_player() -> bool:
	return _name_edit != null


func _link_text() -> String:
	var label := Platform.backend.display_name()
	if label == "":
		label = Platform.backend.provider_id().to_upper()
	return ("LINKED · %s" % label) if Platform.is_linked() else ("LINK %s" % label)


## LINK: sign in (if needed) and link; LINKED: tap unlinks.
func _toggle_link() -> void:
	if Platform.is_linked():
		_link_row.text = "UNLINKING..."
		var ok: bool = await Platform.unlink()
		if not is_instance_valid(_link_row):
			return
		_link_row.text = _link_text() if ok else "NO SIGNAL · TRY AGAIN LATER"
		_tone(_link_row, Platform.is_linked())
		return
	if not Platform.backend.is_signed_in():
		Platform.backend.sign_in()
	_link_row.text = "LINKING..."
	await Platform.sync_link()
	if not is_instance_valid(_link_row):
		return
	_link_row.text = _link_text()
	_tone(_link_row, Platform.is_linked())


## First tap arms it (DELETE_ARM_S); the second deletes the server account,
## wipes this phone's save and goes back to the title as a fresh install.
func _delete_account() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _delete_armed_at < 0.0 or now - _delete_armed_at > DELETE_ARM_S:
		_delete_armed_at = now
		_delete.text = "TAP AGAIN TO DELETE EVERYTHING"
		return
	_delete_armed_at = -1.0
	_delete.text = "DELETING..."
	var ok: bool = await Net.delete_account()
	if not is_instance_valid(_delete):
		return
	if ok:
		_delete.text = "ACCOUNT DELETED"
		App.to_title()
	else:
		_delete.text = "NO SIGNAL · TRY AGAIN LATER"


func delete_armed() -> bool:
	return _delete_armed_at >= 0.0


## A full-width row: cream, or gold while its toggle is on.
func _row(name_: String, text: String, on: bool) -> ShadowCard:
	var b := button(text, CREAM, 16, ROW_H)
	b.name = name_
	_tone(b, on)
	return b


## An orange action beside a field (SAVE, CLAIM), 120 wide.
func _action(name_: String, text: String) -> ShadowCard:
	var b := button(text, RetroTheme.LIGHT["orange"], 16, ROW_H)
	b.name = name_
	b.custom_minimum_size.x = 120 + ShadowStyle.OFFSET
	return b


static func _tone(b: ShadowCard, on: bool) -> void:
	b.color = RetroTheme.LIGHT["gold"] if on else CREAM
	b.queue_redraw()


func has_tuning() -> bool:
	return _tuning != null


func has_dark_mode() -> bool:
	return _dark != null


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


func _gates_label() -> String:
	return "LEVEL GATES: ON" if App.league_gating else "LEVEL GATES: OFF"


func has_gates() -> bool:
	return _gates != null
