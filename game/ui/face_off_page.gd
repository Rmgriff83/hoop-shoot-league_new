class_name FaceOffPage
extends HomePage
## The pieces the 1v1 pages share (docs/HOME.md → 1v1): the face-off card
## (jersey, name + #tag, town · level, the online line, a corner word), the
## VS rule, and the LOADOUT strip (three slots to tap out, YOUR CARDS to tap
## in) — built by the lobby's face-off (MatchLobbyPage) and the pre-match
## pick (PreMatchPage, 2026-10-19) alike. No network, no state of its own.

const FACE_H := 156.0
const FACE_ICON := 72.0
const FACE_SUB := Color("#E6D9B8")
const NAME_MAX_W := 380.0
const GOLD := RetroTheme.LIGHT["gold"]
const ORANGE := RetroTheme.LIGHT["orange"]
const SLOT := Vector2(84, 112)
const SPARE := Vector2(66, 88)


## A face-off card: the jersey, the three lines, the corner word.
func _face_card(name_: String, edge: Color, corner: String) -> ShadowPanel:
	var card := ShadowPanel.new(edge, 0.0, ShadowStyle.TINT, 24.0)
	card.name = name_
	card.custom_minimum_size = Vector2(0, FACE_H + ShadowStyle.OFFSET)
	var row := _face_row()
	card.add_child(row)
	var icon := PixelIcon.new("icon_jersey", Vector2.ONE * FACE_ICON, 4.0)
	icon.name = "Jersey"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var lines := _face_lines(GOLD if edge == GOLD else CREAM, CREAM if edge == GOLD else FACE_SUB, GOLD)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lines)
	_corner(row, corner, GOLD if edge == GOLD else CREAM)
	return card


func _face_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## Name (+ #tag), the town and level, the online line.
func _face_lines(name_colour: Color, tag_colour: Color, online_colour: Color) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var who := words("", 22, true)
	who.name = "Name"
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	who.add_theme_color_override("font_color", name_colour)
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(who)
	var tag := words("", 18)
	tag.name = "Tag"
	tag.add_theme_color_override("font_color", tag_colour)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(tag)
	var place := words("", 18)
	place.name = "Place"
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(place)
	var online := words("", 18)
	online.name = "Online"
	online.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	online.add_theme_color_override("font_color", online_colour)
	col.add_child(online)
	return col


## The corner word (YOU / OPP / the searching "..."), 20 px down from the top.
func _corner(row: HBoxContainer, text: String, colour: Color) -> Label:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_vertical = Control.SIZE_FILL
	col.add_child(_spacer_v(20))
	var l := words(text, 14, true)
	l.name = "Corner"
	l.add_theme_color_override("font_color", colour)
	col.add_child(l)
	row.add_child(col)
	return l


## `place_text` / `online_text` on the record override the copy (a league
## opponent has a league and a record, not a town and a ladder badge).
static func _fill_lines(lines: Control, rec: Dictionary) -> void:
	_set_name(lines.find_child("Name", true, false) as Label, str(rec.get("name", "THEM")))
	(lines.find_child("Tag", true, false) as Label).text = MatchCopy.card_tag(rec)
	(lines.find_child("Place", true, false) as Label).text = str(rec.get("place_text", MatchCopy.card_place(rec)))
	(lines.find_child("Online", true, false) as Label).text = str(rec.get("online_text", MatchCopy.card_online(rec)))


## The handle at its own width (the tag follows it), cut with an ellipsis
## past NAME_MAX_W — a clipped label alone would shrink to nothing in a row.
static func _set_name(l: Label, text: String) -> void:
	l.text = text
	var w := UiFont.display().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(22)).x + 2.0 * RetroTheme.OUTLINE
	l.custom_minimum_size.x = minf(w, NAME_MAX_W)


## YOU: the account's handle, the hometown, the level, the rank the server
## last told us (Net.me_rank).
static func you_record() -> Dictionary:
	var a: Dictionary = Net.account()
	var rec := {"name": str(a.get("name", "YOU")), "tag": str(a.get("tag", "")), "town": App.hometown(), "level": App.level()}
	var rank: Dictionary = Net.me_rank
	if not rank.is_empty():
		rec["rank"] = rank
	return rec


## A VS row: two rules with the word between.
func _vs_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "VsRow"
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(Rule.new())
	var word := RetroTheme.display(MatchCopy.vs_word(), 36, ORANGE)
	word.name = "VsWord"
	word.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	word.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RetroTheme.dithered(word, Vector2(5, 5))
	row.add_child(word)
	row.add_child(Rule.new())
	return row


# ---- the cards: LOADOUT (tap to remove) and YOUR CARDS (tap to add) --------------------


## Build the strip into `into` from a bucket's cache: the LOADOUT panel and
## YOUR CARDS. `cap` is the card cap of the match being set up (a spare above
## it, or above the level, is dimmed with its level and refuses the tap);
## -1 means no cap beyond the level. `on_change` runs after a tap moved a card.
func build_loadout_strip(into: Control, bucket: String, cap: int, on_change: Callable) -> void:
	for c in into.get_children():
		into.remove_child(c)
		c.queue_free()
	var cd := App.cards_bucket(bucket)
	var slots: Array = App.loadout_slots(bucket)
	var inv: Dictionary = cd.get("inventory", {})
	# The LOADOUT panel.
	var panel := ShadowPanel.new(GOLD, 12.0, 0.18, 18.0)
	panel.name = "Loadout"
	into.add_child(panel)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var head_ := HBoxContainer.new()
	head_.add_theme_constant_override("separation", 12)
	col.add_child(head_)
	var t := words("LOADOUT", 16, true)
	t.name = "LoadoutTitle"
	t.add_theme_color_override("font_color", GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_.add_child(t)
	var set_count := 0
	for s in slots:
		if s != null:
			set_count += 1
	var line := words(MatchCopy.loadout_line(set_count), 16)
	line.name = "LoadoutLine"
	head_.add_child(line)
	var row := HBoxContainer.new()
	row.name = "Slots"
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_child(row)
	var names := VBoxContainer.new()
	names.name = "SlotNames"
	names.add_theme_constant_override("separation", 12)
	names.size_flags_vertical = Control.SIZE_SHRINK_END
	for i in CardDefs.SLOTS:
		var id: Variant = slots[i] if i < slots.size() else null
		if id != null:
			var card := CardDefs.get_card(str(id))
			var holder := ModeCards.art(card, SLOT, 6.0, true)
			holder.name = "Slot%d" % i
			var slot_i := i
			(holder.get_meta("button") as TextureButton).pressed.connect(func() -> void:
				App.unequip_card(slot_i, bucket)
				on_change.call())
			row.add_child(holder)
			var n := words(str(card.get("name", id)).to_upper(), 16)
			n.name = "SlotName%d" % i
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			names.add_child(n)
		else:
			var empty := ModeCards.empty_slot(SLOT, 24, 3.0)
			empty.name = "Slot%d" % i
			row.add_child(empty)
			var n := words(MatchCopy.slot_empty(i), 16)
			n.name = "SlotName%d" % i
			n.add_theme_color_override("font_color", RetroTheme.SCENE_MUTED)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			names.add_child(n)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	row.add_child(names)
	# YOUR CARDS: the spares.
	var yours := VBoxContainer.new()
	yours.name = "Yours"
	yours.add_theme_constant_override("separation", 14)
	into.add_child(yours)
	var yh := HBoxContainer.new()
	yh.add_theme_constant_override("separation", 12)
	yours.add_child(yh)
	var yt := words("YOUR CARDS", 16, true)
	yt.name = "YoursTitle"
	yt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	yt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yh.add_child(yt)
	var spares_n := 0
	for id in inv:
		if int(inv[id]) > 0:
			spares_n += 1
	var yc := words(MatchCopy.spares_caption(spares_n > 0), 16)
	yc.name = "YoursCaption"
	yh.add_child(yc)
	var spares := HBoxContainer.new()
	spares.name = "Spares"
	spares.add_theme_constant_override("separation", 22)
	spares.custom_minimum_size = Vector2(0, SPARE.y + 6)
	yours.add_child(spares)
	for id in inv:
		if int(inv[id]) <= 0:
			continue
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var holder := ModeCards.art(card, SPARE, 6.0, true)
		holder.name = "Spare_" + str(id)
		var cid := str(id)
		var allowed := App.can_equip(cid) and (cap < 0 or Progression.card_level(card) <= cap)
		if not allowed:
			# Above the cap (or the level): dimmed, its level on it, no tap.
			holder.modulate = Color(1, 1, 1, 0.45)
			var lock := PanelContainer.new()
			lock.name = "Lock_" + cid
			var lsb := StyleBoxFlat.new()
			lsb.bg_color = RetroTheme.SCENE_OUTLINE
			lsb.set_content_margin_all(4)
			lsb.content_margin_left = 6
			lsb.content_margin_right = 6
			lock.add_theme_stylebox_override("panel", lsb)
			lock.position = Vector2(4, SPARE.y - 26)
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock.add_child(UiFont.label("LVL %d" % Progression.card_level(card), 14, CREAM))
			holder.add_child(lock)
		(holder.get_meta("button") as TextureButton).pressed.connect(func() -> void:
			if not allowed:
				return
			for slot in CardDefs.SLOTS:
				if App.loadout_slots(bucket)[slot] == null:
					App.equip_card(slot, cid, bucket)
					break
			on_change.call())
		var badge := PanelContainer.new()
		badge.name = "Count"
		var sb := StyleBoxFlat.new()
		sb.bg_color = RetroTheme.SCENE_OUTLINE
		sb.set_content_margin_all(6)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		badge.add_theme_stylebox_override("panel", sb)
		badge.position = Vector2(SPARE.x - 10, -10)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(UiFont.label("×%d" % int(inv[id]), 16, CREAM))
		holder.add_child(badge)
		spares.add_child(holder)


static func _spacer_v(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A 3 px cream rule with a 2 px ink shadow, either side of VS.
class Rule extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 5)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2(size.x, 3)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 3)), RetroTheme.SCENE_TEXT)
