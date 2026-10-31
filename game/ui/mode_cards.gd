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

const LEAGUE_H := 310.0
const PAIR_H := 110.0
const CHIP := 40.0
const CHIP_GAP := 8.0
const MAX_TROPHIES := 5
const TROPHY := 38.0
## The trophies' sparkles (the design's twinkle): each one's delay and spot in its cup.
const SPARKLE_DELAY := 0.55
const SPARKLE_AT := [Vector2(24, -2), Vector2(3, 8), Vector2(26, 13), Vector2(5, -5), Vector2(21, 3)]
const CREAM := RetroTheme.SCENE_TEXT
const HI := Color("#FFE45C")


# ---- the cards -------------------------------------------------------------------


## The LEAGUE card from an App.league_states() row (design "Home League
## Context v2", 2026-10-30): the season in gold over its top-left corner and
## the trophies (each with its sparkle) over its top-right; inside, your
## jersey, name and hometown, the three season numbers beside ENTER LEAGUE
## (an orange dot sweep across it) and the next game over a dashed rule.
## `you` = {name, town} (FaceOffPage.you_record() when empty). Sized
## LEAGUE_H + shadow.
static func league_card(state: Dictionary, you: Dictionary = {}) -> Button:
	var info := LeagueSummary.card(state)
	if you.is_empty():
		you = FaceOffPage.you_record()
	var b := ShadowCard.new(RetroTheme.c("orange"))
	b.name = "LeagueCard"
	b.custom_minimum_size = Vector2(0, LEAGUE_H + ShadowCard.OFFSET)
	if not state.is_empty() and not bool(state.get("unlocked", true)):
		b.disabled = true
	var margin := _margin(20, 22)
	b.add_child(margin)
	var col := VBoxContainer.new()
	col.name = "Text"
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	# Header: the jersey beside your name over your hometown.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lift := Control.new()
	lift.custom_minimum_size = Vector2(0, 20 - 14)   # the design's margin-top 20, less the column's gap
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lift)
	col.add_child(head)
	var jersey := PixelIcon.new("icon_jersey", Vector2(60, 60), 3.0)
	jersey.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(jersey)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(who)
	var nm := _label(str(you.get("name", "YOU")).to_upper(), 28, CREAM, true)
	nm.name = "PlayerName"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(nm)
	var town := _label(str(you.get("town", "")).to_upper(), 20, CREAM)
	town.name = "PlayerTown"
	town.clip_text = true
	town.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	town.visible = town.text != ""
	who.add_child(town)
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
		var st := stat(str(k["v"]), str(k["l"]), 34, 10, 18)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats.add_child(st)
	# A finished season narrows it to a centred chevron (the footer says START INSIDE).
	var done := bool(info.get("done", false))
	var enter := ShadowCard.new(CREAM)
	enter.name = "Enter"
	enter.clip_contents = true
	enter.custom_minimum_size = Vector2((104 if done else 176) + ShadowCard.OFFSET, 0)
	enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enter.disabled = b.disabled
	var shine := PreMatchPage.Shine.new(2.4, 200.0, 0.75, RetroTheme.c("orange"))
	shine.name = "Shine"
	UiLayout.full_rect(shine)
	shine.offset_right = -ShadowCard.OFFSET
	shine.offset_bottom = -ShadowCard.OFFSET
	enter.add_child(shine)
	var em := _margin(17, 16)
	enter.add_child(em)
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 10)
	er.alignment = BoxContainer.ALIGNMENT_CENTER if done else BoxContainer.ALIGNMENT_BEGIN
	er.mouse_filter = Control.MOUSE_FILTER_IGNORE
	em.add_child(er)
	if not done:
		var el := _label("ENTER\nLEAGUE", 18, CREAM, true)
		el.name = "EnterLabel"
		el.add_theme_constant_override("line_spacing", 8)
		el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		er.add_child(el)
	var ch := _label(">", 34, CREAM, true)
	ch.name = "Chevron"
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	er.add_child(ch)
	enter.custom_minimum_size.y = maxf(UiFont.snap(18) * 2 + 8, UiFont.snap(34)) + 34 + ShadowCard.OFFSET
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
	var nl := _label(str(info["next_left"]), 18, CREAM)
	nl.name = "NextLeft"
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.add_child(nl)
	var nr := _label(str(info["next_right"]), 18, CREAM)
	nr.name = "NextRight"
	nr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fr.add_child(nr)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 20 - 14)   # the footer's margin-bottom 20
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tail)
	# Overhangs: the season top-left, the trophies (and their sparkles) top-right.
	var season := _label(str(info["sub"]), 18, HI, true)
	season.name = "Season"
	season.position = Vector2(18, -30)
	b.add_child(season)
	var titles := int(info["titles"])
	if titles > 0:
		var tr := HBoxContainer.new()
		tr.name = "Trophies"
		tr.add_theme_constant_override("separation", 6)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := 0.0
		for i in mini(titles, MAX_TROPHIES):
			var cup := Control.new()
			cup.name = "Trophy%d" % i
			cup.custom_minimum_size = Vector2(TROPHY, TROPHY)
			cup.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cup.add_child(PixelIcon.new("icon_trophy", Vector2(TROPHY, TROPHY), 2.0))
			var sp := Sparkle.new(i * SPARKLE_DELAY)
			sp.name = "Sparkle"
			sp.position = SPARKLE_AT[i]
			cup.add_child(sp)
			tr.add_child(cup)
			w += TROPHY + (6.0 if i > 0 else 0.0)
		if titles > MAX_TROPHIES:
			var txt := "+%d" % (titles - MAX_TROPHIES)
			var more := _label(txt, 18, RetroTheme.c("gold"), true)
			more.name = "MoreTitles"
			more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tr.add_child(more)
			w += 6.0 + UiFont.display().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(18)).x + 2.0 * RetroTheme.OUTLINE
		tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		tr.offset_right = -(18 + ShadowCard.OFFSET)
		tr.offset_left = tr.offset_right - w
		tr.offset_top = -43
		tr.offset_bottom = tr.offset_top + TROPHY
		b.add_child(tr)
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
	var b := icon_card("icon_barbell", "PRACTICE", ("LOCKED · LEVEL %d" % lock_level) if lock_level > 0 else "NO CLOCK", RetroTheme.c("teal"))
	b.name = "PracticeCard"
	b.disabled = lock_level > 0
	return b


## A PAIR_H card (design 3a, 2026-10-30): the pixel icon in a 48 px box
## (the stopwatch at 40, the barbell at 48 with a 2 px shadow), the title in
## the display face and a bold sub-line.
static func icon_card(icon: String, title: String, sub: String, fill: Color) -> Button:
	var b := ShadowCard.new(fill)
	b.custom_minimum_size = Vector2(0, PAIR_H + ShadowCard.OFFSET)
	var margin := _margin(0, 24)
	b.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(48, 48)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var big := icon == "icon_barbell"
	var pic := PixelIcon.new(icon, Vector2(48, 48) if big else Vector2(40, 40), 2.0 if big else 0.0)
	pic.name = "Icon"
	box.add_child(pic)
	row.add_child(box)
	var col := VBoxContainer.new()
	col.name = "Text"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := _label(title, 18, CREAM, true)
	t.name = "Title"
	col.add_child(t)
	var s := _label(sub, 18, CREAM)
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
static func stat(v: String, l: String, size_ := 32, gap := 10, label_size := 16) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", gap)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(_label(v, size_, CREAM, true))
	cell.add_child(_label(l, label_size, CREAM))
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
	var face := CardFace.new(card, size_)
	face.name = "Face"
	holder.add_child(face)
	if button:
		# A textureless button over the face: the tap target, nothing drawn.
		var b := TextureButton.new()
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.size = size_
		b.focus_mode = Control.FOCUS_NONE
		holder.add_child(b)
		holder.set_meta("button", b)
	return holder


## An empty loadout slot: a dashed cream border over an ink ground (the
## design's 40 % on the loadout; the 40 px chip row's slot sits at 60 %), a
## "+" in the display face.
static func empty_slot(size_: Vector2, font := 16, border := 2.0, shadow := 0.0, ground := Dashed.GROUND) -> Control:
	var d := Dashed.new(size_, border, shadow, ground)
	var plus := _label("+", font, CREAM, true)
	UiLayout.full_rect(plus)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	d.add_child(plus)
	return d


## A 40 px loadout chip: the card's sprite loop on the card's own colour in
## an ink frame with a 3 px shadow; an empty slot is the dashed "+".
static func chip(card: Dictionary) -> Control:
	if card.is_empty():
		return empty_slot(Vector2(CHIP, CHIP), 16, 2.0, 3.0, 0.6)
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
	UiLayout.full_rect(m)
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
	const GROUND := 0.4
	var border := 2.0
	var shadow := 0.0
	var ground := GROUND   # the ink ground's alpha (design: 0.4 loadout slots, 0.6 chip slots)
	func _init(size_: Vector2, p_border := 2.0, p_shadow := 0.0, p_ground := GROUND) -> void:
		border = p_border
		shadow = p_shadow
		ground = p_ground
		custom_minimum_size = size_ + Vector2.ONE * shadow
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size - Vector2.ONE * shadow)
		if shadow > 0.0:
			draw_rect(Rect2(Vector2.ONE * shadow, box.size), RetroTheme.SCENE_OUTLINE)
		draw_rect(box, Color(RetroTheme.SCENE_OUTLINE, ground))
		var h := border / 2.0
		var pts := [Vector2(h, h), Vector2(box.size.x - h, h), Vector2(box.size.x - h, box.size.y - h), Vector2(h, box.size.y - h), Vector2(h, h)]
		for i in 4:
			draw_dashed_line(pts[i], pts[i + 1], RetroTheme.SCENE_TEXT, border, 8.0)


## A loadout chip (design "Card Icons" 9a): a 40 px ink frame (2 px border,
## 3 px ink shadow) filled with the card's `fx.chip_bg`, the card's sprite
## loop (`fx.chip` px, a sprite-only CardFace) centred in it.
class Chip extends Control:
	var card: Dictionary = {}
	var bg: Color = RetroTheme.SCENE_OUTLINE
	func _init(p_card: Dictionary) -> void:
		card = p_card
		custom_minimum_size = Vector2(ModeCards.CHIP + 3, ModeCards.CHIP + 3)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var fx: Dictionary = card["fx"] if card.get("fx", null) is Dictionary else {}
		if Color.html_is_valid(str(fx.get("chip_bg", ""))):
			bg = Color.html(str(fx["chip_bg"]))
		var cs: Array = fx["chip"] if fx.get("chip", null) is Array and fx["chip"].size() == 2 else [36, 36]
		var spr_size := Vector2(float(cs[0]), float(cs[1]))
		var spr := CardFace.new(card, spr_size, true)
		spr.name = "Sprite"
		spr.position = ((Vector2.ONE * ModeCards.CHIP - spr_size) * 0.5).floor()
		add_child(spr)
	func _draw() -> void:
		var box := Vector2.ONE * ModeCards.CHIP
		draw_rect(Rect2(Vector2(3, 3), box), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, box), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2(2, 2), box - Vector2(4, 4)), bg)


## A trophy's sparkle (the design's twinkle, 2026-10-30): a 10 px cream plus
## with a gold centre, hidden most of its 2.4 s loop, then popping in, turning
## and shrinking away in steps (CssEase.twinkle), `delay` s after the others.
class Sparkle extends Control:
	var delay := 0.0
	func _init(p_delay := 0.0) -> void:
		delay = p_delay
		size = Vector2(10, 10)
		pivot_offset = Vector2(5, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate.a = 0.0
	func _process(_dt: float) -> void:
		var v := CssEase.twinkle(Time.get_ticks_msec() / 1000.0 - delay)
		modulate.a = v.x
		scale = Vector2.ONE * v.y
		rotation_degrees = v.z
	func _draw() -> void:
		draw_rect(Rect2(4, 0, 2, 10), RetroTheme.SCENE_TEXT)
		draw_rect(Rect2(0, 4, 10, 2), RetroTheme.SCENE_TEXT)
		draw_rect(Rect2(3, 3, 4, 4), ModeCards.HI)
