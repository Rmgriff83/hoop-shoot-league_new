class_name SettingsPanel
extends HomePage
## The settings page (the menu button, docs/HOME.md; design "Settings v2"
## 42a, 2026-10-25): a see-through full page over the area like Ranks and
## the lobby — the home slides out left, settings in from the right — with
## `<` SETTINGS (the back square is CLOSE now) and one scrolling list, a
## fade at its foot until the end is in view:
##  • GAME, one panel: SHOT HELP (OFF / NUMBERS / NUMBERS + ARC), AI
##    DIFFICULTY (EASY / NORMAL / HARD) and HUD SIDE (LEFT / RIGHT) as
##    pickers showing every choice, the active one gold. (DARK MODE is gone: the game is dark everywhere, 2026-10-26.)
##  • PLAYER (the cloud line on the right): a gold card — how you appear in
##    leagues and online — whose pencil opens NAME (with your tag) and
##    HOMETOWN, the card following as you type; SAVE checks both and closes,
##    CLOSE drops the changes. The messages sit under it. The platform link
##    row waits, hidden, for a store backend (docs/BACKEND.md).
##  • DEV (debug builds only): TUNING and LEVEL GATES as switches.
##  • MORE: CREDITS.
##  • DANGER ZONE, last: MOVE TO NEW PHONE (the one-time code on the row),
##    ENTER CODE (the code field and CLAIM) and DELETE ACCOUNT in orange —
##    the first tap arms it (DELETE_ARM_S), the second deletes.
## `closed` fires when it goes away.


const GOLD := Color("#F0B84A")
const MUTED := Color("#E6D9B8")
const BAD := Color("#FF8A6A")
const ORANGE := Color("#E8703A")
const PAGE_WASH := Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.6)
const FIELD_BG := Color(34.0 / 255.0, 28.0 / 255.0, 24.0 / 255.0, 0.55)
const FADE_C := Color(27.0 / 255.0, 22.0 / 255.0, 19.0 / 255.0, 0.95)
const OPTION_H := 56.0
const NAV_H := 76.0
const FIELD_H := 64.0
const FADE_H := 120.0
const SHOT_SUBS := ["NO AIM HELP", "POWER + ANGLE", "POWER + ANGLE + PATH"]
## DELETE ACCOUNT needs a second tap within this many seconds.
const DELETE_ARM_S := 8.0

var _pickers: Dictionary = {}     # name → {value: ShadowCard}
var _shot_sub: Label
var _tuning_switch: PixelSwitch
var _gates_switch: PixelSwitch
var _card_name: Label
var _card_tag: Label
var _card_town: Label
var _edit_btn: ShadowCard
var _edit_box: ShadowPanel
var _name_edit: LineEdit
var _town_edit: LineEdit
var _msg: Label
var _move: ShadowCard
var _enter: ShadowCard
var _code_row: HBoxContainer
var _code_edit: LineEdit
var _link_row: ShadowCard
var _delete: ShadowCard
var _delete_armed_at := -1.0
var _scroll: ScrollContainer
var _list: VBoxContainer
var _fade: TextureRect


func _row_gap() -> int:
	return 36


func _build() -> void:
	wash.color = PAGE_WASH
	# < SETTINGS
	var head_ := HBoxContainer.new()
	head_.name = "Head"
	head_.add_theme_constant_override("separation", 20)
	head_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(head_)
	var back := button("<", CREAM, 24, 56.0 - ShadowStyle.OFFSET)
	back.name = "Back"
	back.custom_minimum_size = Vector2(56 + ShadowStyle.OFFSET, 56 + ShadowStyle.OFFSET)
	back.pressed.connect(close)
	head_.add_child(back)
	var title := words("SETTINGS", 28, true)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head_.add_child(title)
	# The list.
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	body.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_bottom", 60)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 20)
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(_list)
	_build_game()
	_list.add_child(_spacer(8))
	_build_player()
	if OS.is_debug_build():
		_list.add_child(_spacer(8))
		_build_dev()
	_list.add_child(_spacer(8))
	_list.add_child(_section("MORE"))
	var credits := _nav_row("Credits", "CREDITS", "", CREAM)
	credits.pressed.connect(App.to_credits)
	_list.add_child(credits)
	_list.add_child(_spacer(8))
	_build_danger()
	# The fade at the list's foot.
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
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_fade.offset_top = -FADE_H
	_fade.offset_left = -FRAME_POS.x
	_fade.offset_right = FRAME_POS.x + 6.0
	root.add_child(_fade)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _check_end())
	_scroll.get_v_scroll_bar().changed.connect(_check_end)


# ---- GAME -----------------------------------------------------------------------------


func _build_game() -> void:
	_list.add_child(_section("GAME"))
	var panel := ShadowPanel.new(CREAM, 22.0, 0.14, 22.0)
	panel.name = "GamePanel"
	_list.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(col)
	var shot_opts := []
	for i in App.SHOT_HELP_LABELS.size():
		shot_opts.push_back([i, str(App.SHOT_HELP_LABELS[i])])
	var shot := _picker("ShotHelp", "SHOT HELP", str(SHOT_SUBS[App.shot_help]), shot_opts, App.shot_help, func(v: Variant) -> void:
		App.set_shot_help(int(v))
		_shot_sub.text = str(SHOT_SUBS[App.shot_help]))
	_shot_sub = shot.get_node("Head/Sub")
	col.add_child(shot)
	col.add_child(_rule())
	# AI DIFFICULTY (Ross, 2026-10-19): every AI the player faces, on every court.
	var ai_opts := []
	for lv in AiDifficulty.LEVELS:
		ai_opts.push_back([lv, AiDifficulty.label(lv)])
	col.add_child(_picker("Difficulty", "AI DIFFICULTY", "EVERY AI, EVERY COURT", ai_opts, App.ai_difficulty, func(v: Variant) -> void:
		App.set_ai_difficulty(str(v))))
	col.add_child(_rule())
	# HUD SIDE (Ross, 2026-10-24): the match toasts and the music note.
	col.add_child(_picker("HudSide", "HUD SIDE", "TOASTS + MUSIC NOTE", [["left", "LEFT"], ["right", "RIGHT"]], App.hud_side, func(v: Variant) -> void:
		App.set_hud_side(str(v))))


## TITLE ........ sub, then every choice in a row (the active one gold).
func _picker(name_: String, title: String, sub: String, options: Array, current: Variant, on_pick: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = name_
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_title_row(title, sub))
	var row := HBoxContainer.new()
	row.name = "Options"
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(row)
	var cards := {}
	for o in options:
		var value: Variant = o[0]
		var b := ShadowCard.new(CREAM)
		b.name = "%s_%s" % [name_, str(value)]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, OPTION_H + ShadowStyle.OFFSET)
		var l := words(str(o[1]), 13, true)
		l.name = "Text"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("line_spacing", 4)
		UiLayout.full_rect(l)
		l.offset_right = -ShadowStyle.OFFSET - 4.0
		l.offset_left = 4.0
		l.offset_bottom = -ShadowStyle.OFFSET
		b.add_child(l)
		b.pressed.connect(func() -> void:
			on_pick.call(value)
			_pick(name_, value))
		row.add_child(b)
		cards[value] = b
	_pickers[name_] = cards
	_pick(name_, current)
	return box


func _pick(name_: String, value: Variant) -> void:
	var cards: Dictionary = _pickers.get(name_, {})
	for v in cards:
		var b: ShadowCard = cards[v]
		var on: bool = str(v) == str(value)
		b.color = GOLD if on else CREAM
		b.tint = 0.28 if on else 0.18
		b.queue_redraw()


## Which choice a picker shows in gold (tests, QA).
func picked(name_: String) -> String:
	var cards: Dictionary = _pickers.get(name_, {})
	for v in cards:
		if (cards[v] as ShadowCard).color == GOLD:
			return str(v)
	return ""


## A row with its words on the left and a PixelSwitch on the right; the whole row takes the tap.
func _switch_row(name_: String, title: String, sub: String, on: bool) -> Button:
	var b := Button.new()
	b.name = name_
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS   # a drag that starts here scrolls the list
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, PixelSwitch.SIZE.y + 4.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(row)
	b.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := words(title, 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(t)
	var s := words(sub, 14)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.add_theme_color_override("font_color", MUTED)
	col.add_child(s)
	var sw := PixelSwitch.new(on)
	sw.name = "Switch"
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 10.0 + 18.0 + 14.0 * (2.0 if sub.length() > 30 else 1.0) + 8.0)
	return b


# ---- PLAYER ---------------------------------------------------------------------------


func _build_player() -> void:
	_list.add_child(_section("PLAYER", Net.cloud_line()))
	var acct := Net.account()
	var card := ShadowPanel.new(GOLD, 0.0, ShadowStyle.TINT, 22.0)
	card.name = "PlayerCard"
	card.custom_minimum_size = Vector2(0, 120 + ShadowStyle.OFFSET)
	_list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(row)
	var jersey := PixelIcon.new("icon_jersey", Vector2(64, 64), 4.0)
	jersey.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(jersey)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_theme_constant_override("separation", 14)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(who)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(top)
	_card_name = words("", 20, true)
	_card_name.name = "CardName"
	_card_name.add_theme_color_override("font_color", GOLD)
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_card_name.clip_text = true
	_card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_card_name)
	_card_tag = words(MatchCopy.card_tag(acct), 16)
	_card_tag.name = "CardTag"
	_card_tag.add_theme_color_override("font_color", MUTED)
	_card_tag.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(_card_tag)
	_card_town = words("", 16)
	_card_town.name = "CardTown"
	_card_town.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	who.add_child(_card_town)
	_edit_btn = ShadowCard.new(CREAM)
	_edit_btn.name = "Edit"
	_edit_btn.custom_minimum_size = Vector2.ONE * (56 + ShadowStyle.OFFSET)
	_edit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pencil := PixelIcon.new("icon_edit", Vector2(32, 32), 2.0)
	pencil.position = Vector2(12, 12)
	_edit_btn.add_child(pencil)
	_edit_btn.pressed.connect(func() -> void:
		if _edit_box.visible:
			_close_edit()
		else:
			_open_edit())
	row.add_child(_edit_btn)
	# NAME (with the tag) and HOMETOWN, SAVE / CLOSE.
	_edit_box = ShadowPanel.new(CREAM, 22.0, 0.14, 22.0)
	_edit_box.name = "EditBox"
	_edit_box.visible = false
	_list.add_child(_edit_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	_edit_box.add_child(col)
	_name_edit = _edit("NameEdit", str(acct.get("name", "")), HandleWords.NAME_MAX)
	_name_edit.placeholder_text = "YOUR NAME"
	col.add_child(_field_group("NAME", _name_edit, MatchCopy.card_tag(acct), CREAM))
	_town_edit = _edit("TownEdit", App.hometown(), Towns.TOWN_MAX)
	_town_edit.placeholder_text = "HOMETOWN"
	col.add_child(_field_group("HOMETOWN", _town_edit, "", CREAM))
	for e in [_name_edit, _town_edit]:
		(e as LineEdit).text_changed.connect(func(raw: String) -> void:
			_tidy(e, raw)
			_refresh_card())
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	btns.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(btns)
	var save := button("SAVE", ORANGE, 16, FIELD_H)
	save.name = "Save"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_save_player)
	btns.add_child(save)
	var close_b := button("CLOSE", CREAM, 16, FIELD_H)
	close_b.name = "CloseEdit"
	close_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_b.pressed.connect(_close_edit)
	btns.add_child(close_b)
	_msg = words("", 15)
	_msg.name = "PlayerStatus"
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.visible = false
	_list.add_child(_msg)
	# The platform link (docs/BACKEND.md → Platform identity): hidden while
	# the backend is the null one (no Game Center / Play Games plugin yet).
	_link_row = _nav_row("PlatformLink", _link_text(), "", GOLD if Platform.is_linked() else CREAM)
	_link_row.visible = Platform.backend.is_available()
	_link_row.pressed.connect(_toggle_link)
	_list.add_child(_link_row)
	_refresh_card()


## LABEL over a see-through field (and the tag at its right end).
func _field_group(label: String, e: LineEdit, tag: String, edge: Color) -> VBoxContainer:
	var g := VBoxContainer.new()
	g.name = e.name.trim_suffix("Edit") + "Group"
	g.add_theme_constant_override("separation", 10)
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := words(label, 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_color_override("font_color", MUTED)
	g.add_child(l)
	g.add_child(_field(e, tag, edge))
	return g


## A dark well with a 2 px edge around a flat LineEdit (and optional words after it).
func _field(e: LineEdit, tag: String, edge: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = e.name + "Box"
	var sb := StyleBoxFlat.new()
	sb.bg_color = FIELD_BG
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(0, FIELD_H)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(h)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(e)
	if tag != "":
		var t := words(tag, 16)
		t.name = "FieldTag"
		t.add_theme_color_override("font_color", Color("#A89E94"))
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(t)
	return box


## A flat field: bold cream words, outlined, the caret gold.
func _edit(name_: String, text: String, max_len: int, display := false) -> LineEdit:
	var e := LineEdit.new()
	e.name = name_
	e.text = text
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, FIELD_H - 4.0)
	e.add_theme_font_override("font", UiFont.display() if display else UiFont.body_bold())
	e.add_theme_font_size_override("font_size", UiFont.snap(20 if display else 22))
	e.add_theme_color_override("font_color", CREAM)
	e.add_theme_color_override("font_placeholder_color", Color("#A89E94"))
	e.add_theme_color_override("caret_color", GOLD)
	e.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	e.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "focus", "read_only"]:
		e.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return e


## Capitals, letters, digits and single spaces as you type (the caret kept).
static func _tidy(e: LineEdit, raw: String) -> void:
	var re := RegEx.create_from_string("[^A-Z0-9 ]")
	var cleaned := re.sub(raw.to_upper(), "", true).replace("  ", " ").lstrip(" ").left(e.max_length)
	if cleaned != e.text:
		var caret := e.caret_column
		e.text = cleaned
		e.caret_column = mini(caret, cleaned.length())


## The card: the fields while editing, the saved name and town otherwise.
func _refresh_card() -> void:
	var acct := Net.account()
	var name_ := (_name_edit.text if _edit_box.visible else str(acct.get("name", ""))).strip_edges()
	var town := (_town_edit.text if _edit_box.visible else App.hometown()).strip_edges()
	_card_name.text = name_ if name_ != "" else "YOUR NAME"
	_card_town.text = town.to_upper() if town != "" else "HOMETOWN"
	_card_tag.text = MatchCopy.card_tag(acct)
	var f := UiFont.display()
	var w := f.get_string_size(_card_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(20)).x + 2.0 * RetroTheme.OUTLINE
	var tag_w := UiFont.body_bold().get_string_size(_card_tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(16)).x
	_card_name.custom_minimum_size.x = minf(w, maxf(100.0, FRAME_SIZE.x - 2.0 * PAD - 44.0 - 64.0 - 40.0 - 61.0 - tag_w - 12.0))


func _open_edit() -> void:
	_edit_box.visible = true
	_name_edit.text = str(Net.account().get("name", ""))
	_town_edit.text = App.hometown()
	_say("")
	_tone(_edit_btn, true)
	_refresh_card()


func _close_edit() -> void:
	_edit_box.visible = false
	_name_edit.text = str(Net.account().get("name", ""))
	_town_edit.text = App.hometown()
	_say("")
	_tone(_edit_btn, false)
	_refresh_card()


func edit_open() -> bool:
	return _edit_box != null and _edit_box.visible


func card_text() -> String:
	return "%s %s · %s" % [_card_name.text, _card_tag.text, _card_town.text]


## SAVE: the name (renamed on the server when it changed) and the hometown,
## both checked first; closes on success.
func _save_player() -> void:
	var name_ := HandleWords.normalize(_name_edit.text)
	if not HandleWords.valid(name_):
		_say("NAME NOT ALLOWED · A-Z, 0-9, 3-24", false)
		return
	var town := Towns.normalize(_town_edit.text)
	if not Towns.valid(town):
		_say("PICK A HOMETOWN", false)
		return
	if name_ != str(Net.account().get("name", "")):
		var save_b := _edit_box.find_child("Save", true, false) as ShadowCard
		_say("")
		_button_spin(save_b, true)
		var ok: bool = await Net.rename(name_)
		if not is_instance_valid(_msg):
			return
		_button_spin(save_b, false)
		if not ok:
			_say("NO SIGNAL · TRY AGAIN LATER", false)
			return
	App.set_hometown(town)
	_close_edit()
	_say("SAVED · %s · %s" % [Net.handle(), town])


func _say(text: String, ok := true) -> void:
	_msg.text = text
	_msg.visible = text != ""
	_msg.add_theme_color_override("font_color", CREAM if ok else BAD)


func message() -> String:
	return _msg.text if _msg != null else ""


func has_player() -> bool:
	return _name_edit != null


func _link_text() -> String:
	var label := Platform.backend.display_name()
	if label == "":
		label = Platform.backend.provider_id().to_upper()
	return ("LINKED · %s" % label) if Platform.is_linked() else ("LINK %s" % label)


## LINK: sign in (if needed) and link; LINKED: tap unlinks.
func _toggle_link() -> void:
	var top := _link_row.find_child("Top", true, false) as Label
	if Platform.is_linked():
		_spin(top, true)
		var ok: bool = await Platform.unlink()
		if not is_instance_valid(_link_row):
			return
		_spin(top, false)
		top.text = _link_text() if ok else "NO SIGNAL · TRY AGAIN LATER"
		_tone(_link_row, Platform.is_linked())
		return
	if not Platform.backend.is_signed_in():
		Platform.backend.sign_in()
	_spin(top, true)
	await Platform.sync_link()
	if not is_instance_valid(_link_row):
		return
	_spin(top, false)
	top.text = _link_text()
	_tone(_link_row, Platform.is_linked())


# ---- DEV ------------------------------------------------------------------------------


func _build_dev() -> void:
	_list.add_child(_section("DEV", "DEV BUILD ONLY"))
	var panel := ShadowPanel.new(CREAM, 22.0, 0.14, 22.0)
	panel.name = "DevPanel"
	_list.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(col)
	var tuning := _switch_row("Tuning", "TUNING", "THE IN-GAME TUNING PANEL", App.tuning_mode)
	_tuning_switch = tuning.find_child("Switch", true, false)
	tuning.pressed.connect(func() -> void:
		App.set_tuning_mode(not App.tuning_mode)
		_tuning_switch.set_on(App.tuning_mode))
	col.add_child(tuning)
	col.add_child(_rule())
	# LEVEL GATES (Ross, 2026-10-17): the areas and leagues locked by level,
	# the way a release build does — a new user's game.
	var gates := _switch_row("Gates", "LEVEL GATES", "LOCK AREAS + LEAGUES BY LEVEL, LIKE A RELEASE BUILD", App.league_gating)
	_gates_switch = gates.find_child("Switch", true, false)
	gates.pressed.connect(func() -> void:
		App.set_league_gating(not App.league_gating)
		_gates_switch.set_on(App.league_gating))
	col.add_child(gates)


func has_tuning() -> bool:
	return _tuning_switch != null


func has_gates() -> bool:
	return _gates_switch != null


func has_difficulty() -> bool:
	return _pickers.has("Difficulty")


func has_hud_side() -> bool:
	return _pickers.has("HudSide")


## A switch's state as drawn (tests, QA).
func switch_on(name_: String) -> bool:
	var row := _list.find_child(name_, true, false)
	var sw := row.find_child("Switch", true, false) as PixelSwitch if row != null else null
	return sw != null and sw.on


# ---- DANGER ZONE ----------------------------------------------------------------------


func _build_danger() -> void:
	_list.add_child(_section("DANGER ZONE", "ACCOUNT + DEVICE", true))
	_move = _nav_row("MoveToPhone", "MOVE TO NEW PHONE", "GET A ONE-TIME CODE FOR YOUR NEW PHONE", CREAM)
	_move.pressed.connect(_move_to_phone)
	_list.add_child(_move)
	_enter = _nav_row("EnterCode", "ENTER CODE", "MOVING FROM ANOTHER PHONE?", CREAM)
	_enter.pressed.connect(func() -> void:
		_code_row.visible = not _code_row.visible
		_set_sub(_enter, "TYPE THE CODE FROM YOUR OLD PHONE" if _code_row.visible else "MOVING FROM ANOTHER PHONE?", MUTED))
	_list.add_child(_enter)
	_code_row = HBoxContainer.new()
	_code_row.name = "CodeRow"
	_code_row.visible = false
	_code_row.add_theme_constant_override("separation", 14)
	_code_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_list.add_child(_code_row)
	_code_edit = _edit("CodeEdit", "", 9, true)
	_code_edit.placeholder_text = "8-LETTER CODE"
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.text_changed.connect(func(raw: String) -> void:
		var re := RegEx.create_from_string("[^A-Z0-9]")
		var cleaned := re.sub(raw.to_upper(), "", true).left(8)
		if cleaned != _code_edit.text:
			var caret := _code_edit.caret_column
			_code_edit.text = cleaned
			_code_edit.caret_column = mini(caret, cleaned.length()))
	_code_row.add_child(_field(_code_edit, "", GOLD))
	var claim := button("CLAIM", ORANGE, 14, FIELD_H)
	claim.name = "Claim"
	claim.custom_minimum_size.x = 112 + ShadowStyle.OFFSET
	claim.pressed.connect(_claim_code)
	_code_row.add_child(claim)
	# Account deletion (Apple 5.1.1(v)): armed by one tap, done by a second.
	_delete = _nav_row("DeleteAccount", "DELETE ACCOUNT", "TWO TAPS · REMOVES YOUR ONLINE ACCOUNT", ORANGE, false)
	_delete.pressed.connect(_delete_account)
	_list.add_child(_delete)


func _move_to_phone() -> void:
	_spin(_move.find_child("Sub", true, false) as Label, true)
	var r: Dictionary = await Net.transfer_code()
	if not is_instance_valid(_move):
		return
	_spin(_move.find_child("Sub", true, false) as Label, false)
	if r.is_empty():
		_set_sub(_move, "NO SIGNAL · TRY AGAIN LATER", BAD)
		return
	var code := str(r.get("code", ""))
	_set_sub(_move, "CODE %s %s · 15 MIN" % [code.substr(0, 4), code.substr(4)], GOLD)


func _claim_code() -> void:
	var code := _code_edit.text.strip_edges().replace(" ", "").to_upper()
	if code.length() != 8:
		_set_sub(_enter, "A CODE IS 8 LETTERS", BAD)
		return
	_spin(_enter.find_child("Sub", true, false) as Label, true)
	var ok: bool = await Net.claim_transfer(code)
	if not is_instance_valid(_enter):
		return
	_spin(_enter.find_child("Sub", true, false) as Label, false)
	if ok:
		_code_row.visible = false
		_code_edit.text = ""
		_set_sub(_enter, "MOVING FROM ANOTHER PHONE?", MUTED)
		_close_edit()   # the card shows the claimed account
		_say("WELCOME BACK · %s" % Net.handle())
	else:
		_set_sub(_enter, "CODE NOT FOUND OR EXPIRED", BAD)


## First tap arms it (DELETE_ARM_S); the second deletes the server account,
## wipes this phone's save and goes back to the title as a fresh install.
func _delete_account() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var top := _delete.find_child("Top", true, false) as Label
	if _delete_armed_at < 0.0 or now - _delete_armed_at > DELETE_ARM_S:
		_delete_armed_at = now
		top.text = "TAP AGAIN TO DELETE EVERYTHING"
		_set_sub(_delete, "YOUR ACCOUNT AND THIS PHONE'S SAVE · CAN'T BE UNDONE", CREAM)
		_delete.tint = 0.5
		_delete.queue_redraw()
		return
	_delete_armed_at = -1.0
	_spin(top, true)
	var ok: bool = await Net.delete_account()
	if not is_instance_valid(_delete):
		return
	_spin(top, false)
	if ok:
		top.text = "ACCOUNT DELETED"
		App.to_title()
	else:
		top.text = "NO SIGNAL · TRY AGAIN LATER"


func delete_armed() -> bool:
	return _delete_armed_at >= 0.0


func _process(_dt: float) -> void:
	# The arm runs out: DELETE ACCOUNT goes back to its first face.
	if _delete_armed_at >= 0.0 and Time.get_ticks_msec() / 1000.0 - _delete_armed_at > DELETE_ARM_S:
		_delete_armed_at = -1.0
		(_delete.find_child("Top", true, false) as Label).text = "DELETE ACCOUNT"
		_set_sub(_delete, "TWO TAPS · REMOVES YOUR ONLINE ACCOUNT", CREAM)
		_delete.tint = ShadowStyle.TINT
		_delete.queue_redraw()


# ---- the pieces -----------------------------------------------------------------------


## GAME ———————— note: a section head (DANGER ZONE in red over an orange rule).
func _section(title: String, note := "", danger := false) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = title.capitalize().replace(" ", "") + "Head"
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := words(title, 16, true)
	if danger:
		t.add_theme_color_override("font_color", BAD)
	h.add_child(t)
	var rule := ColorRect.new()
	rule.color = Color(ORANGE, 0.55) if danger else Color(CREAM, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(rule)
	if note != "":
		var n := words(note, 14)
		n.name = "Note"
		n.add_theme_color_override("font_color", MUTED)
		h.add_child(n)
	return h


## TITLE ........ sub, over a picker.
func _title_row(title: String, sub: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Head"
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := words(title, 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(t)
	var s := words(sub, 14)
	s.name = "Sub"
	s.add_theme_color_override("font_color", MUTED)
	h.add_child(s)
	return h


## A full-width row: TITLE over its sub-line, `>` on the right.
func _nav_row(name_: String, title: String, sub: String, colour: Color, chevron := true) -> ShadowCard:
	var b := ShadowCard.new(colour)
	b.name = name_
	b.custom_minimum_size = Vector2(0, NAV_H + ShadowStyle.OFFSET)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(h)
	h.offset_left = 22.0
	h.offset_right = -22.0 - ShadowStyle.OFFSET
	h.offset_bottom = -ShadowStyle.OFFSET
	b.add_child(h)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var t := words(title, 16, true)
	t.name = "Top"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(t)
	var s := words(sub, 14)
	s.name = "Sub"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	s.add_theme_color_override("font_color", MUTED if colour != ORANGE else CREAM)
	s.visible = sub != ""
	col.add_child(s)
	if chevron:
		var c := words(">", 22, true)
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.size_flags_vertical = Control.SIZE_FILL
		h.add_child(c)
	return b


func _set_sub(row: ShadowCard, text: String, colour: Color) -> void:
	var s := row.find_child("Sub", true, false) as Label
	s.text = text
	s.visible = text != ""
	s.add_theme_color_override("font_color", colour)


## A row's sub-line (tests, QA).
func row_sub(name_: String) -> String:
	var row := _list.find_child(name_, true, false)
	var s := row.find_child("Sub", true, false) as Label if row != null else null
	return s.text if s != null else ""


## A spinner in a label's place while something is on its way (no
## …ING words since 2026-10-25): the words stay laid out but unseen, so the
## row keeps its size.
func _spin(l: Label, on: bool) -> void:
	if l == null:
		return
	var sp := l.get_node_or_null("Spin") as PixelSpinner
	if on:
		l.visible = true
		l.self_modulate.a = 0.0
		if sp == null:
			sp = PixelSpinner.new(20.0)
			sp.name = "Spin"
			l.add_child(sp)
		sp.position = Vector2(0.0, maxf(0.0, (l.size.y - 20.0) * 0.5))
	else:
		l.self_modulate.a = 1.0
		if sp != null:
			sp.queue_free()


## The same on a button with its own words (SAVE): the spinner in the face's middle.
func _button_spin(b: ShadowCard, on: bool) -> void:
	if b == null:
		return
	var box := b.get_node_or_null("Spin")
	if on:
		b.set_meta("spin_text", b.text)
		b.text = ""
		b.disabled = true
		if box == null:
			var c := CenterContainer.new()
			c.name = "Spin"
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UiLayout.full_rect(c)   # inside the button: fills it, no bleed
			c.offset_right = -ShadowStyle.OFFSET
			c.offset_bottom = -ShadowStyle.OFFSET
			c.add_child(PixelSpinner.new(ButtonBusy.spinner_px(b.size.y if b.size.y > 0.0 else b.custom_minimum_size.y)))
			b.add_child(c)
	else:
		b.text = str(b.get_meta("spin_text", b.text))
		b.disabled = false
		if box != null:
			box.queue_free()


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(CREAM, 0.25)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _tone(b: ShadowCard, on: bool) -> void:
	b.color = GOLD if on else CREAM
	b.tint = 0.35 if on else ShadowStyle.TINT
	b.queue_redraw()


static func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _check_end() -> void:
	if _scroll == null or _fade == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_fade.visible = bar.value + bar.page < bar.max_value - 4.0


func fade_shown() -> bool:
	return _fade != null and _fade.visible
