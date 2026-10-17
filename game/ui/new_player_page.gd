class_name NewPlayerPage
extends HomePage
## NEW PLAYER (design "New Game Flow" 35a, 2026-10-17; docs/HOME.md → New
## player): the form a fresh install fills before its first court. Slides in
## from the right over the splash (the ENTER LEAGUE move). Pre-filled at
## random — a handle from HandleWords with its two-digit tag, a hometown from
## Towns — each field typed over or re-rolled with its die; the gold card on
## top previews name over hometown. The name follows the settings rules
## (A–Z, 0–9, 3–24, no blocked word), the hometown cannot be empty; LET'S PLAY
## dims with a reason until both are good, then App.create_player lands on
## the Arcade Cage campaign home. Name and hometown stay editable in
## Settings → PLAYER.

const LEFT := 6.0            # design x 36 inside the frame at x 30
const WIDTH := 642.0         # 720 − 36 − 42
const FIELD_H := 76.0
const DIE_W := 76.0
const BAD := Color("#FF8A6A")
const FIELD_BG := Color(34.0 / 255.0, 28.0 / 255.0, 24.0 / 255.0, 0.55)
const HINT := "YOU CAN CHANGE THESE LATER IN SETTINGS"

var rng: DetRng = DetRng.new(int(Time.get_ticks_usec() % 2147483647))
var tag := "00"
var _name_edit: LineEdit
var _tag_label: Label
var _town_edit: LineEdit
var _preview_name: Label
var _preview_town: Label
var _status: Label
var _play: ShadowCard
var _dice: Array[DieGlyph] = []
var _leaving := false


func _build() -> void:
	body.visible = false   # everything sits at the design's absolute spots
	# Head: < and NEW PLAYER.
	var back := button("<", CREAM, 28, 72.0 - ShadowStyle.OFFSET)
	back.name = "Back"
	back.position = Vector2(LEFT, 24)
	back.size = Vector2(72, 72)
	back.pressed.connect(close)
	root.add_child(back)
	var head_ := words("NEW PLAYER", 28, true)
	head_.name = "Head"
	head_.position = Vector2(LEFT + 96, 24)
	head_.size = Vector2(400, 72)
	head_.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(head_)
	# The preview card: how they'll read in the league, name over hometown.
	var card := ShadowPanel.new(RetroTheme.LIGHT["gold"], 0.0)
	card.name = "PreviewCard"
	card.position = Vector2(LEFT, 140)
	card.size = Vector2(WIDTH, 196)
	root.add_child(card)
	# A plain host inside the panel (a container would stretch its children).
	var lay := Control.new()
	lay.name = "Layout"
	lay.set_anchors_preset(Control.PRESET_FULL_RECT)
	lay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lay)
	var jersey := PixelIcon.new("icon_jersey", Vector2(96, 96), 4.0)
	jersey.name = "Jersey"
	jersey.position = Vector2(28, (196 - ShadowStyle.OFFSET - 96) / 2.0)
	lay.add_child(jersey)
	_preview_name = words("", 30, true)
	_preview_name.name = "PreviewName"
	_preview_name.position = Vector2(150, 30)
	_preview_name.size = Vector2(WIDTH - 150 - 28, 80)
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_name.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_name.add_theme_color_override("font_color", RetroTheme.LIGHT["gold"])
	lay.add_child(_preview_name)
	_preview_town = words("", 20)
	_preview_town.name = "PreviewTown"
	_preview_town.position = Vector2(150, 118)
	_preview_town.size = Vector2(WIDTH - 150 - 28, 40)
	_preview_town.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_town.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lay.add_child(_preview_town)
	# PLAYER NAME: the field with its tag, and a die.
	_label_at("NameHead", "PLAYER NAME", 390)
	var name_box := _field_box("NameBox", 428)
	_name_edit = _edit("NameEdit", HandleWords.NAME_MAX, "YOUR NAME")
	_name_edit.text_changed.connect(_on_name_typed)
	name_box.add_child(_name_edit)
	_tag_label = words("", 18)
	_tag_label.name = "Tag"
	_tag_label.add_theme_color_override("font_color", Color("#A89E94"))
	_tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_box.add_child(_tag_label)
	root.add_child(_die("RollName", 428, _roll_name))
	# HOMETOWN.
	_label_at("TownHead", "HOMETOWN", 590)
	var town_box := _field_box("TownBox", 628)
	_town_edit = _edit("TownEdit", Towns.TOWN_MAX, "YOUR CITY")
	_town_edit.text_changed.connect(_on_town_typed)
	town_box.add_child(_town_edit)
	root.add_child(_die("RollTown", 628, _roll_town))
	# The reason, or the reassurance.
	_status = words("", 18)
	_status.name = "Status"
	_status.position = Vector2(LEFT, 830)
	_status.size = Vector2(WIDTH, 30)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_status)
	# LET'S PLAY.
	_play = big_button("LET'S PLAY", "icon_ball")
	_play.name = "Play"
	_play.position = Vector2(LEFT, 1060)
	_play.pressed.connect(_lets_play)
	root.add_child(_play)
	_roll_all()


func _label_at(name_: String, text: String, top: float) -> void:
	var l := words(text, 16)
	l.name = name_
	l.position = Vector2(LEFT, top)
	l.size = Vector2(WIDTH, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(l)


## The dark field box the design draws: a cream rule around a dark wash.
func _field_box(name_: String, top: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = name_
	box.position = Vector2(LEFT, top)
	box.size = Vector2(WIDTH - DIE_W - 18, FIELD_H)
	box.add_theme_constant_override("separation", 12)
	var bg := Panel.new()
	bg.name = "Bg"
	var sb := StyleBoxFlat.new()
	sb.bg_color = FIELD_BG
	sb.border_color = CREAM
	sb.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", sb)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.show_behind_parent = true
	box.add_child(bg)
	root.add_child(box)
	return box


func _edit(name_: String, max_len: int, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.name = name_
	e.max_length = max_len
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, FIELD_H)
	e.add_theme_font_override("font", UiFont.body_bold())
	e.add_theme_font_size_override("font_size", UiFont.snap(26))
	e.add_theme_color_override("font_color", CREAM)
	e.add_theme_color_override("font_placeholder_color", Color("#A89E94"))
	e.add_theme_color_override("caret_color", RetroTheme.LIGHT["gold"])
	e.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	e.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "focus"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 18.0
		sb.content_margin_right = 12.0
		e.add_theme_stylebox_override(state, sb)
	return e


func _die(name_: String, top: float, on_roll: Callable) -> ShadowCard:
	var b := ShadowCard.new(CREAM)
	b.name = name_
	b.position = Vector2(LEFT + WIDTH - DIE_W, top)
	b.size = Vector2(DIE_W, FIELD_H)
	var glyph := DieGlyph.new()
	glyph.name = "Die"
	glyph.position = Vector2((DIE_W - ShadowStyle.OFFSET - DieGlyph.SIZE) / 2.0, (FIELD_H - ShadowStyle.OFFSET - DieGlyph.SIZE) / 2.0)
	b.add_child(glyph)
	_dice.push_back(glyph)
	b.pressed.connect(on_roll)
	return b


## The splash's big orange card button: the label left, a pixel icon right.
static func big_button(text: String, icon: String) -> ShadowCard:
	var b := ShadowCard.new(RetroTheme.c("orange"))
	b.size = Vector2(WIDTH, 140)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 32.0
	row.offset_right = -(32.0 + ShadowCard.OFFSET)
	row.offset_bottom = -ShadowCard.OFFSET
	b.add_child(row)
	var l := Label.new()
	l.name = "Label"
	l.text = text
	l.add_theme_font_override("font", UiFont.display())
	l.add_theme_font_size_override("font_size", 32)
	RetroTheme.on_scene(l)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(48, 48)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(PixelIcon.new(icon, Vector2(48, 48), 3.0))
	row.add_child(box)
	return b


# ---- the values ----------------------------------------------------------------------


func _roll_all() -> void:
	var h := HandleWords.generate(rng)
	tag = str(h["tag"])
	_name_edit.text = str(h["name"])
	_town_edit.text = Towns.pick(rng)
	_refresh()


func _roll_name() -> void:
	_name_edit.text = str(HandleWords.generate(rng)["name"])
	_spin()
	_refresh()


func _roll_town() -> void:
	_town_edit.text = Towns.pick(rng, _town_edit.text)
	_spin()
	_refresh()


func _spin() -> void:
	for d in _dice:
		d.spin()


## Typing is tidied in place (upper-case, the allowed characters, single
## spaces) with the caret kept; a trailing space stays so words can follow.
static func clean_typing(raw: String, max_len: int) -> String:
	var re := RegEx.create_from_string("[^A-Z0-9 ]")
	var s := re.sub(raw.to_upper(), "", true)
	while s.contains("  "):
		s = s.replace("  ", " ")
	if s.begins_with(" "):
		s = s.substr(1)
	return s.left(max_len)


func _on_name_typed(raw: String) -> void:
	_retype(_name_edit, clean_typing(raw, HandleWords.NAME_MAX))
	_refresh()


func _on_town_typed(raw: String) -> void:
	_retype(_town_edit, clean_typing(raw, Towns.TOWN_MAX))
	_refresh()


static func _retype(e: LineEdit, cleaned: String) -> void:
	if e.text == cleaned:
		return
	var caret := e.caret_column
	e.text = cleaned
	e.caret_column = mini(caret, cleaned.length())


func name_value() -> String:
	return HandleWords.normalize(_name_edit.text)


func town_value() -> String:
	return Towns.normalize(_town_edit.text)


## "" when the name passes; else the reason, in the design's words.
func name_problem() -> String:
	var n := name_value()
	if n.length() < HandleWords.NAME_MIN:
		return "NAME NEEDS 3 OR MORE LETTERS"
	if not HandleWords.valid(n):
		return "NAME NOT ALLOWED"
	return ""


func problem() -> String:
	var p := name_problem()
	if p != "":
		return p
	if not Towns.valid(town_value()):
		return "PICK A HOMETOWN"
	return ""


func is_valid() -> bool:
	return problem() == ""


func values() -> Dictionary:
	return {"name": name_value(), "tag": tag, "town": town_value()}


func _refresh() -> void:
	_tag_label.text = tag
	_preview_name.text = name_value() if name_value() != "" else "YOUR NAME"
	_preview_town.text = town_value() if town_value() != "" else "HOMETOWN"
	var p := problem()
	_status.text = HINT if p == "" else p
	_status.add_theme_color_override("font_color", CREAM if p == "" else BAD)
	_play.disabled = p != ""
	_play.modulate.a = 1.0 if p == "" else 0.45


func _lets_play() -> void:
	if _leaving or not is_valid():
		return
	_leaving = true
	var v := values()
	slide_out(true, false)
	App.create_player(str(v["name"]), str(v["tag"]), str(v["town"]))
