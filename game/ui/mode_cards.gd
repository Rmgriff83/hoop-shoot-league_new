class_name ModeCards
extends RefCounted
## The home page's mode cards (docs/HOME.md, design "Home League Context
## v2"): ShadowCards (see-through, the card's colour as a dithered offset
## shadow) with their own label stacks in cream + ink outline. The LEAGUE
## card is the big one — the league's name and titles (trophies overhanging
## its top-left, the equipped cards as chips top-right), three season
## numbers, an ENTER LEAGUE button and the next game over a dashed rule, all
## from LeagueSummary.card. TIME TRIAL / PRACTICE are the icon pair under it.
## Card art thumbnails (`art`, `empty_slot`, `chip`) are shared with the
## league in context and the home's floating layer.

const LEAGUE_H := 270.0
const PAIR_H := 94.0
const CHIP := 40.0
const CHIP_GAP := 8.0
const MAX_TROPHIES := 5
const CREAM := RetroTheme.SCENE_TEXT
const HI := Color("#FFCE8A")


# ---- the cards -------------------------------------------------------------------


## The LEAGUE card from an App.league_states() row; `slots` = the league's
## three loadout slots (ids or null) for the chips. Sized LEAGUE_H + shadow.
static func league_card(state: Dictionary, slots: Array = []) -> Button:
	var info := LeagueSummary.card(state)
	var b := ShadowCard.new(RetroTheme.c("orange"))
	b.name = "LeagueCard"
	b.custom_minimum_size = Vector2(0, LEAGUE_H + ShadowCard.OFFSET)
	if not state.is_empty() and not bool(state.get("unlocked", true)):
		b.disabled = true
	var margin := _margin(22, 22)
	b.add_child(margin)
	var col := VBoxContainer.new()
	col.name = "Text"
	col.add_theme_constant_override("separation", 18)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	# Header: NAME — 1 TITLE, then the season.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(top)
	var t := _label(str(info["top"]), 16, CREAM, true)
	t.name = "Title"
	top.add_child(t)
	var titles := int(info["titles"])
	if titles > 0:
		var dash := Dash.new()
		dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(dash)
		var tl := _label("%d TITLE%s" % [titles, "" if titles == 1 else "S"], 16, HI, true)
		tl.name = "Titles"
		top.add_child(tl)
	var sub := _label(str(info["sub"]), 20, CREAM)
	sub.name = "Sub"
	head.add_child(sub)
	# Middle: the three numbers and ENTER LEAGUE.
	var mid := HBoxContainer.new()
	mid.name = "Mid"
	mid.add_theme_constant_override("separation", 20)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mid)
	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", 36)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.alignment = BoxContainer.ALIGNMENT_BEGIN
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(stats)
	for k in info["stats"]:
		stats.add_child(stat(str(k["v"]), str(k["l"]), 32))
	# A finished season narrows it to a centred chevron (the footer says START INSIDE).
	var done := bool(info.get("done", false))
	var enter := ShadowCard.new(CREAM)
	enter.name = "Enter"
	enter.custom_minimum_size = Vector2((104 if done else 176) + ShadowCard.OFFSET, 0)
	enter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enter.disabled = b.disabled
	var em := _margin(0, 16)
	enter.add_child(em)
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 10)
	er.alignment = BoxContainer.ALIGNMENT_CENTER if done else BoxContainer.ALIGNMENT_BEGIN
	er.mouse_filter = Control.MOUSE_FILTER_IGNORE
	em.add_child(er)
	if not done:
		var el := _label("ENTER\nLEAGUE", 16, CREAM, true)
		el.name = "EnterLabel"
		el.add_theme_constant_override("line_spacing", 8)
		el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		er.add_child(el)
	var ch := _label(">", 32, CREAM, true)
	ch.name = "Chevron"
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	er.add_child(ch)
	mid.add_child(enter)
	b.set_meta("enter", enter)
	# Footer: the next game over a dashed rule.
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	foot.add_child(DashedRule.new())
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 16)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(fr)
	var nl := _label(str(info["next_left"]), 16, CREAM)
	nl.name = "NextLeft"
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.add_child(nl)
	var nr := _label(str(info["next_right"]), 16, CREAM)
	nr.name = "NextRight"
	nr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fr.add_child(nr)
	# Overhangs: trophies top-left, the loadout chips top-right.
	if titles > 0:
		var tr := HBoxContainer.new()
		tr.name = "Trophies"
		tr.position = Vector2(14, -35)
		tr.add_theme_constant_override("separation", 6)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in mini(titles, MAX_TROPHIES):
			tr.add_child(PixelIcon.new("icon_trophy", Vector2(30, 30), 2.0))
		if titles > MAX_TROPHIES:
			var more := _label("+%d" % (titles - MAX_TROPHIES), 16, RetroTheme.c("gold"), true)
			more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tr.add_child(more)
		b.add_child(tr)
	if not slots.is_empty():
		var chips := chip_row(slots, true)
		chips.name = "Chips"
		var w := slots.size() * CHIP + (slots.size() - 1) * CHIP_GAP
		chips.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		chips.offset_right = -(18 + ShadowCard.OFFSET)
		chips.offset_left = chips.offset_right - w
		chips.offset_top = -20
		chips.offset_bottom = chips.offset_top + CHIP
		b.add_child(chips)
	return b


## The ENTER LEAGUE button inside a league card (for wiring).
static func enter_button(card: Button) -> Button:
	return card.get_meta("enter") if card.has_meta("enter") else null


## `lock_level` > 0: the area is locked below that level — the card is
## disabled and its sub-line says so.
static func trial_card(best: int, lock_level := 0) -> Button:
	var sub := ("BEST %d" % best) if best > 0 else "NO RUNS YET"
	var b := icon_card("icon_stopwatch", "TIME TRIAL", ("LOCKED · LEVEL %d" % lock_level) if lock_level > 0 else sub, RetroTheme.c("gold"))
	b.name = "TrialCard"
	b.disabled = lock_level > 0
	return b


static func practice_card(lock_level := 0) -> Button:
	var b := icon_card("icon_jersey", "PRACTICE", ("LOCKED · LEVEL %d" % lock_level) if lock_level > 0 else "NO CLOCK", RetroTheme.c("teal"))
	b.name = "PracticeCard"
	b.disabled = lock_level > 0
	return b


## A PAIR_H card: the pixel icon (40 px in a 48 px box), the title in the
## display face and a small-caps sub-line.
static func icon_card(icon: String, title: String, sub: String, fill: Color) -> Button:
	var b := ShadowCard.new(fill)
	b.custom_minimum_size = Vector2(0, PAIR_H + ShadowCard.OFFSET)
	var margin := _margin(0, 20)
	b.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(48, 48)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(PixelIcon.new(icon, Vector2(40, 40)))
	row.add_child(box)
	var col := VBoxContainer.new()
	col.name = "Text"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := _label(title, 16, CREAM, true)
	t.name = "Title"
	col.add_child(t)
	var s := _label(sub, 16, CREAM)
	s.name = "Sub"
	s.visible = sub != ""
	col.add_child(s)
	return b


## A plain text card (START SEASON, ADVANCE): title (display), sub (caps), a chevron.
static func text_card(title: String, sub: String, fill: Color, title_size := 24, chevron := true) -> Button:
	var b := ShadowCard.new(fill)
	var margin := _margin(18, 22)
	b.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var col := VBoxContainer.new()
	col.name = "Text"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := _label(title, title_size, CREAM, true)
	t.name = "Title"
	col.add_child(t)
	var s := _label(sub, 16, CREAM)
	s.name = "Sub"
	s.visible = sub != ""
	col.add_child(s)
	if chevron:
		var ch := _label(">", 24, CREAM, true)
		ch.name = "Chevron"
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(ch)
	return b


static func sub_text(b: Button) -> String:
	var s: Label = b.find_child("Sub", true, false)
	return s.text if s != null else ""


## The one-line league status (LeagueSummary.line), kept here for its callers.
static func league_line(state: Dictionary) -> String:
	return LeagueSummary.line(state)


# ---- shared pieces ---------------------------------------------------------------


## A big number over its small-caps label.
static func stat(v: String, l: String, size_ := 32, gap := 10) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", gap)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(_label(v, size_, CREAM, true))
	cell.add_child(_label(l, 16, CREAM))
	return cell


## Card art at a size with a hard ink shadow; a TextureButton when `button`
## (meta "button"), else a TextureRect. Nearest-filtered.
static func art(card: Dictionary, size_: Vector2, shadow := 6.0, button := false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = size_ + Vector2.ONE * shadow
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sh := ColorRect.new()
	sh.color = RetroTheme.SCENE_OUTLINE
	sh.position = Vector2.ONE * shadow
	sh.size = size_
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sh)
	var path := str(card.get("art", "res://assets/textures/cards/card_back.png"))
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if button:
		var b := TextureButton.new()
		b.texture_normal = tex
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.size = size_
		b.focus_mode = Control.FOCUS_NONE
		holder.add_child(b)
		holder.set_meta("button", b)
	else:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.size = size_
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
	return holder


## An empty loadout slot: a dashed cream border over ink, a "+" in the display face.
static func empty_slot(size_: Vector2, font := 16, border := 2.0, shadow := 0.0) -> Control:
	var d := Dashed.new(size_, border, shadow)
	var plus := _label("+", font, CREAM, true)
	plus.set_anchors_preset(Control.PRESET_FULL_RECT)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	d.add_child(plus)
	return d


## A 40 px loadout chip: a crop of the card's art in an ink frame with a 3 px
## shadow; an empty slot is the dashed "+".
static func chip(card: Dictionary) -> Control:
	if card.is_empty():
		return empty_slot(Vector2(CHIP, CHIP), 16, 2.0, 3.0)
	return Chip.new(card)


## The three slots as chips in a row (`with_empty`: dashed "+" for an empty slot).
static func chip_row(slots: Array, with_empty := true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(CHIP_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in slots:
		var card := CardDefs.get_card(str(id)) if id != null else {}
		if card.is_empty() and not with_empty:
			continue
		row.add_child(chip(card))
	return row


static func _margin(v: int, h: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h + int(ShadowCard.OFFSET))
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v + int(ShadowCard.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


static func _label(text: String, size_: int, color: Color, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


## The short cream dash between the league's name and its titles (2 px ink shadow).
class Dash extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(14, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2(12, 3)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, Vector2(12, 3)), RetroTheme.SCENE_TEXT)


## A dashed cream rule (the card's footer, the playoff line).
class DashedRule extends Control:
	var thickness := 2.0
	func _init(p_thickness := 2.0) -> void:
		thickness = p_thickness
		custom_minimum_size = Vector2(0, p_thickness + 1)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_dashed_line(Vector2(0, thickness / 2.0), Vector2(size.x, thickness / 2.0), RetroTheme.SCENE_TEXT, thickness, 10.0)


## An empty slot's box: ink at 40 % with a dashed cream border, optional ink shadow.
class Dashed extends Control:
	var border := 2.0
	var shadow := 0.0
	func _init(size_: Vector2, p_border := 2.0, p_shadow := 0.0) -> void:
		border = p_border
		shadow = p_shadow
		custom_minimum_size = size_ + Vector2.ONE * shadow
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size - Vector2.ONE * shadow)
		if shadow > 0.0:
			draw_rect(Rect2(Vector2.ONE * shadow, box.size), RetroTheme.SCENE_OUTLINE)
		draw_rect(box, Color(RetroTheme.SCENE_OUTLINE, 0.4))
		var h := border / 2.0
		var pts := [Vector2(h, h), Vector2(box.size.x - h, h), Vector2(box.size.x - h, box.size.y - h), Vector2(h, box.size.y - h), Vector2(h, h)]
		for i in 4:
			draw_dashed_line(pts[i], pts[i + 1], RetroTheme.SCENE_TEXT, border, 8.0)


## A loadout chip: the card's art scaled to 48×64 and cropped to a 40 px ink
## frame (2 px border), with a 3 px ink shadow.
class Chip extends Control:
	var card: Dictionary = {}
	func _init(p_card: Dictionary) -> void:
		card = p_card
		custom_minimum_size = Vector2(ModeCards.CHIP + 3, ModeCards.CHIP + 3)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var clip := Control.new()
		clip.position = Vector2(2, 2)
		clip.size = Vector2(ModeCards.CHIP - 4, ModeCards.CHIP - 4)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(clip)
		var path := str(card.get("art", "res://assets/textures/cards/card_back.png"))
		var t := TextureRect.new()
		t.texture = load(path) if ResourceLoader.exists(path) else null
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.position = Vector2(-6, -6)
		t.size = Vector2(48, 64)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(t)
	func _draw() -> void:
		var box := Vector2.ONE * ModeCards.CHIP
		draw_rect(Rect2(Vector2(3, 3), box), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, box), RetroTheme.SCENE_OUTLINE)
