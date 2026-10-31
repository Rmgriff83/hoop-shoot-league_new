class_name NewPlayerPage
extends HomePage
## NEW PLAYER (design "New Game Flow" 35a, 2026-10-17; docs/HOME.md → New
## player): the form a fresh install fills before its first court. Slides in
## from the right over the splash (the ENTER LEAGUE move). Pre-filled at
## random — a handle from HandleWords with its two-digit tag, a hometown from
## Towns — each field typed over or re-rolled with its die. Since 2026-10-30
## (35a on the 1560 phone) the fields sit on dashed lines inside one gold
## card — the jersey and HOMETOWN, then PLAYER NAME in big gold type with its
## #tag — over the splash's bare brick wall, under a line saying how. The name follows the settings rules
## (A–Z, 0–9, 3–24, no blocked word), the hometown cannot be empty; LET'S PLAY
## dims with a reason until both are good, then App.create_player lands on
## the Arcade Cage campaign home. Name and hometown stay editable in
## Settings → PLAYER.

const LEFT := 6.0            # design x 36 inside the frame at x 30
const WIDTH := 642.0         # 720 − 36 − 42
## The rows' tops inside the frame, which starts at the top safe area (108
## on the design's iPhone, so design y 130 / 236).
const HEAD_Y := 22.0
const INTRO_Y := 128.0
const INTRO_GAP := 22.0      # the intro's foot to the card (design 323 → 346)
const DIE_W := 60.0
const TOWN_H := 56.0
const NAME_H := 76.0
const RULE := Color(1, 1, 1, 0.55)
const BUTTER := Color("#FFE45C")
const BAD := Color("#FF8A6A")
const HINT := "YOU CAN CHANGE THESE LATER IN SETTINGS"
const INTRO := "NAME YOUR PLAYER AND PICK A HOMETOWN. TAP EITHER LINE TO TYPE YOUR OWN, OR ROLL THE DICE FOR A RANDOM ONE."

var rng: DetRng = DetRng.new(int(Time.get_ticks_usec() % 2147483647))
var tag := "00"
var _name_edit: TextEdit
var _tag_label: Label
var _town_edit: LineEdit
var _status: Label
var _play: ShadowCard
var _dice: Array[DieGlyph] = []
var _leaving := false


## The splash's brick wall shows through bare (no wash).
func wash_alpha() -> float:
	return 0.0


func _build() -> void:
	body.visible = false   # everything sits at the design's spots in the frame
	# Head: < and NEW PLAYER.
	var back := button("<", CREAM, 28, 72.0 - ShadowStyle.OFFSET)
	back.name = "Back"
	back.position = Vector2(LEFT, HEAD_Y)
	back.size = Vector2(72, 72) + Vector2.ONE * ShadowStyle.OFFSET
	back.pressed.connect(close)
	root.add_child(back)
	var head_ := words("NEW PLAYER", 28, true)
	head_.name = "Head"
	head_.position = Vector2(LEFT + 96, HEAD_Y)
	head_.size = Vector2(400, 72)
	head_.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(head_)
	var intro := words(INTRO, 20)
	intro.name = "Intro"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	intro.add_theme_constant_override("line_spacing", 8)
	# The intro and the form in one column, so the card follows however many
	# lines the intro takes.
	var page := VBoxContainer.new()
	page.name = "Page"
	page.position = Vector2(LEFT, INTRO_Y)
	page.size = Vector2(WIDTH, 0)
	page.add_theme_constant_override("separation", INTRO_GAP)
	root.add_child(page)
	page.add_child(intro)
	var form := VBoxContainer.new()
	form.name = "Form"
	form.add_theme_constant_override("separation", 30)
	page.add_child(form)
	# The gold card: the jersey and HOMETOWN, then PLAYER NAME with its tag —
	# how they'll read in the league, typed straight onto the card.
	var card := ShadowPanel.new(RetroTheme.LIGHT["gold"], 31.0, ShadowStyle.TINT, 26.0)
	card.name = "Card"
	form.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	card.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	col.add_child(top)
	var jersey := PixelIcon.new("icon_jersey", Vector2(96, 96), 4.0)
	jersey.name = "Jersey"
	jersey.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(jersey)
	var town_col := VBoxContainer.new()
	town_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	town_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	town_col.add_theme_constant_override("separation", 6)
	top.add_child(town_col)
	town_col.add_child(_label("TownHead", "HOMETOWN", 17))
	_town_edit = _line_edit("TownEdit", Towns.TOWN_MAX, "YOUR CITY")
	_town_edit.text_changed.connect(_on_town_typed)
	town_col.add_child(_field_row(_town_edit, TOWN_H, "RollTown", _roll_town))
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 8)
	col.add_child(name_col)
	var name_head := HBoxContainer.new()
	name_head.add_theme_constant_override("separation", 12)
	name_col.add_child(name_head)
	var nh := _label("NameHead", "PLAYER NAME", 19)
	nh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_head.add_child(nh)
	_tag_label = _label("Tag", "", 20)
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_head.add_child(_tag_label)
	_name_edit = _text_edit("NameEdit", "YOUR NAME")
	_name_edit.text_changed.connect(_on_name_typed)
	name_col.add_child(_field_row(_name_edit, NAME_H, "RollName", _roll_name))
	# The reason, or the reassurance.
	_status = words("", 18)
	_status.name = "Status"
	_status.custom_minimum_size = Vector2(WIDTH, 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	form.add_child(_status)
	# LET'S PLAY.
	_play = big_button("LET'S PLAY", "icon_neonball")
	_play.name = "Play"
	_play.custom_minimum_size = _play.size
	_play.pressed.connect(_lets_play)
	form.add_child(_play)
	_roll_all()


func _label(name_: String, text: String, size_: int) -> Label:
	var l := words(text, size_)
	l.name = name_
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


## A field on a dashed line with its die beside it.
func _field_row(edit: Control, h: float, die_name: String, on_roll: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var line := VBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_constant_override("separation", 0)
	row.add_child(line)
	edit.custom_minimum_size = Vector2(0, h - DashRule.H)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(edit)
	line.add_child(DashRule.new())
	var die := _die(die_name, on_roll)
	die.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(die)
	return row


func _line_edit(name_: String, max_len: int, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.name = name_
	e.max_length = max_len
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", UiFont.body_bold())
	e.add_theme_font_size_override("font_size", UiFont.snap(24))
	e.add_theme_color_override("font_color", CREAM)
	_field_look(e)
	return e


## The name: big gold display type that wraps onto a second line.
func _text_edit(name_: String, placeholder: String) -> TextEdit:
	var e := TextEdit.new()
	e.name = name_
	e.placeholder_text = placeholder
	e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	e.scroll_fit_content_height = true
	e.context_menu_enabled = false
	e.add_theme_font_override("font", UiFont.display())
	e.add_theme_font_size_override("font_size", UiFont.snap(34))
	e.add_theme_color_override("font_color", RetroTheme.LIGHT["gold"])
	e.add_theme_constant_override("line_spacing", 10)
	_field_look(e)
	return e


func _field_look(e: Control) -> void:
	e.add_theme_color_override("font_placeholder_color", Color("#A89E94"))
	e.add_theme_color_override("caret_color", BUTTER)
	e.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	e.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	for state in ["normal", "focus", "read_only"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		e.add_theme_stylebox_override(state, sb)


func _die(name_: String, on_roll: Callable) -> ShadowCard:
	var b := ShadowCard.new(CREAM)
	b.name = name_
	b.custom_minimum_size = Vector2(DIE_W, DIE_W) + Vector2.ONE * ShadowStyle.OFFSET
	var glyph := DieGlyph.new()
	glyph.name = "Die"
	glyph.scale = Vector2.ONE * (32.0 / DieGlyph.SIZE)
	glyph.position = Vector2.ONE * ((DIE_W - DieGlyph.SIZE) / 2.0)
	b.add_child(glyph)
	_dice.push_back(glyph)
	b.pressed.connect(on_roll)
	return b


## The field's dashed underline (3 px, white at 55 %).
class DashRule:
	extends Control
	const H := 3.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, 0, minf(9.0, size.x - x), H), RULE)
			x += 18.0


## The splash's big orange card button: the label left, a pixel icon right.
static func big_button(text: String, icon: String) -> ShadowCard:
	var b := ShadowCard.new(RetroTheme.c("orange"))
	b.size = Vector2(WIDTH, 140)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(row)
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
	row.add_child(icon_slot(icon))
	return b


## A big button's 48 px icon slot (the title's buttons share it). The neon
## ball (design 39a, 2026-10-30) draws 64 in it, its glow spilling 8 px each
## way, with no drop shadow (the glow is its own); other icons fill it with
## a 3 px ink drop.
static func icon_slot(icon: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(48, 48)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var neon := icon == "icon_neonball"
	var px := PixelIcon.new(icon, Vector2(64, 64) if neon else Vector2(48, 48), 0.0 if neon else 3.0)
	px.name = "Icon"
	px.position = Vector2(-8, -8) if neon else Vector2.ZERO
	box.add_child(px)
	return box


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


func _on_name_typed() -> void:
	var cleaned := clean_typing(_name_edit.text, HandleWords.NAME_MAX)
	if _name_edit.text != cleaned:
		var caret := _name_edit.get_caret_column()
		_name_edit.text = cleaned
		_name_edit.set_caret_column(mini(caret, cleaned.length()))
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
	_tag_label.text = RanksCopy.tag_text(tag)
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
