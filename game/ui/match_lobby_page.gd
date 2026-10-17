class_name MatchLobbyPage
extends HomePage
## The 1v1 lobby (design "Online Lobby" 37a, 2026-10-17; docs/HOME.md → 1v1,
## docs/BACKEND.md → Phase 3) with the locker treatment: a HomePage over the
## area — the home slides out left, this slides in from the right, every
## face see-through and dotted. `<` ONLINE · 1V1; the COURT picker (ANY and
## the four courts, locked ones dimmed with a lock; the row itself dimmed
## while only the cage is open); QUICK MATCH, CREATE CODE, ENTER CODE + GO;
## then, at the foot, the LOADOUT (three slots, tap to remove) and YOUR
## CARDS (spares, tap to add). The waits: FINDING A PLAYER… / the big gold
## code and WAITING… with CANCEL; PLAYER FOUND; a failure with BACK. The
## page owns no network: it emits `quick(area)`, `create(area)`,
## `join(area, code)` and `cancel`; App drives it through show_waiting /
## show_found / show_failed.

signal quick(area: String)
signal create(area: String)
signal join(area: String, code: String)
signal cancel

const BTN_H := 112.0
const COURT_H := 60.0
const FIELD_BG := Color(34.0 / 255.0, 28.0 / 255.0, 24.0 / 255.0, 0.55)
const BAD := Color("#FF8A6A")
const GOLD := RetroTheme.LIGHT["gold"]
const SLOT := Vector2(84, 112)
const SPARE := Vector2(66, 88)
const DOTS_S := 0.45

var area_choice := "any"
var _menu: VBoxContainer
var _wait: VBoxContainer
var _courts: Dictionary = {}
var _court_note: Label
var _quick_sub: Label
var _code_edit: LineEdit
var _loadout: VBoxContainer
var _code_block: VBoxContainer
var _code_label: Label
var _big: Label
var _status: Label
var _cancel: ShadowCard
var _state := "menu"
var _how := ""
var _base_big := ""
var _base_status := ""
var _dots := 0
var _dot_t := 0.0


## Build for an area (the court picked at open: it or ANY when several are open).
func build(area: String) -> Control:
	var owned := _owned()
	area_choice = "any" if owned.size() > 1 else "cage"
	if owned.size() > 1 and owned.has(area):
		area_choice = area
	if root == null:
		_ready()   # off-tree (tests): build now; entering the tree later will not build again
	else:
		_build()
	return root


func _ready() -> void:
	if root != null:
		return
	super()


func _row_gap() -> int:
	return 24


func _build() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	# Head: < and ONLINE · 1V1.
	var head_ := HBoxContainer.new()
	head_.name = "Head"
	head_.add_theme_constant_override("separation", 20)
	body.add_child(head_)
	var back := button("<", CREAM, 24, 56.0 - ShadowStyle.OFFSET)
	back.name = "Back"
	back.custom_minimum_size = Vector2(56 + ShadowStyle.OFFSET, 56 + ShadowStyle.OFFSET)
	back.pressed.connect(_back)
	head_.add_child(back)
	var title := words(MatchCopy.title(), 28, true)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_.add_child(title)
	# The menu.
	_menu = VBoxContainer.new()
	_menu.name = "Menu"
	_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu.add_theme_constant_override("separation", 16)
	body.add_child(_menu)
	_build_courts()
	_menu.add_child(_big_button("Quick", "QUICK MATCH", MatchCopy.quick_sub(area_choice), RetroTheme.c("orange"), func() -> void: quick.emit(area_choice)))
	_quick_sub = _menu.get_node("Quick/Col/Sub")
	_menu.add_child(_big_button("Create", "CREATE CODE", MatchCopy.code_sub(), RetroTheme.c("teal"), func() -> void: create.emit(area_choice)))
	var join_row := HBoxContainer.new()
	join_row.name = "JoinRow"
	join_row.add_theme_constant_override("separation", 18)
	_menu.add_child(join_row)
	var box := PanelContainer.new()
	box.name = "CodeBox"
	var sb := StyleBoxFlat.new()
	sb.bg_color = FIELD_BG
	sb.border_color = CREAM
	sb.set_border_width_all(2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(0, BTN_H)
	join_row.add_child(box)
	_code_edit = LineEdit.new()
	_code_edit.name = "CodeEdit"
	_code_edit.placeholder_text = "ENTER CODE"
	_code_edit.max_length = 5
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_override("font", UiFont.display())
	_code_edit.add_theme_font_size_override("font_size", UiFont.snap(24))
	_code_edit.add_theme_color_override("font_color", CREAM)
	_code_edit.add_theme_color_override("font_placeholder_color", Color("#A89E94"))
	_code_edit.add_theme_color_override("caret_color", GOLD)
	_code_edit.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	_code_edit.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "focus"]:
		_code_edit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_code_edit.text_changed.connect(func(raw: String) -> void:
		var re := RegEx.create_from_string("[^A-Z0-9]")
		var cleaned := re.sub(raw.to_upper(), "", true).left(5)
		if cleaned != _code_edit.text:
			var caret := _code_edit.caret_column
			_code_edit.text = cleaned
			_code_edit.caret_column = mini(caret, cleaned.length())
	)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _go())
	box.add_child(_code_edit)
	var go := button("GO", GOLD, 24, BTN_H - ShadowStyle.OFFSET)
	go.name = "Go"
	go.custom_minimum_size = Vector2(160 + ShadowStyle.OFFSET, BTN_H + ShadowStyle.OFFSET)
	go.pressed.connect(_go)
	join_row.add_child(go)
	var sub := words(MatchCopy.join_sub(), 16)
	sub.name = "JoinSub"
	_menu.add_child(sub)
	# The cards, at the foot.
	var push := Control.new()
	push.name = "Push"
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(push)
	_loadout = VBoxContainer.new()
	_loadout.name = "Cards"
	_loadout.add_theme_constant_override("separation", 12)
	_menu.add_child(_loadout)
	refresh_cards()
	# The waits.
	_wait = VBoxContainer.new()
	_wait.name = "Wait"
	_wait.visible = false
	_wait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wait.alignment = BoxContainer.ALIGNMENT_CENTER
	_wait.add_theme_constant_override("separation", 36)
	body.add_child(_wait)
	_code_block = VBoxContainer.new()
	_code_block.name = "CodeBlock"
	_code_block.visible = false
	_code_block.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_block.add_theme_constant_override("separation", 20)
	_wait.add_child(_code_block)
	var cap := words(MatchCopy.code_caption(), 18)
	cap.name = "CodeCaption"
	_code_block.add_child(cap)
	_code_label = RetroTheme.display("", 72, GOLD)
	_code_label.name = "Code"
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	_code_label.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	_code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RetroTheme.dithered(_code_label, Vector2(7, 7))
	_code_block.add_child(_code_label)
	_big = words("", 24, true)
	_big.name = "Big"
	_big.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wait.add_child(_big)
	_status = words("", 18)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wait.add_child(_status)
	var cancel_row := CenterContainer.new()
	cancel_row.name = "CancelRow"
	_wait.add_child(cancel_row)
	_cancel = button("CANCEL", CREAM, 20, 76.0 - ShadowStyle.OFFSET)
	_cancel.name = "Cancel"
	_cancel.custom_minimum_size = Vector2(360 + ShadowStyle.OFFSET, 76 + ShadowStyle.OFFSET)
	_cancel.pressed.connect(func() -> void:
		cancel.emit()
		show_menu())
	cancel_row.add_child(_cancel)
	_wait.add_child(_spacer_v(120))
	show_menu()


## COURT: ANY and the four courts in a row of five; the chosen one gold.
func _build_courts() -> void:
	var section := VBoxContainer.new()
	section.name = "CourtSection"
	section.add_theme_constant_override("separation", 10)
	_menu.add_child(section)
	var head_ := HBoxContainer.new()
	head_.name = "CourtHead"
	head_.add_theme_constant_override("separation", 12)
	section.add_child(head_)
	var l := words("COURT", 16)
	l.name = "CourtLabel"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_.add_child(l)
	var owned := _owned()
	_court_note = words(MatchCopy.court_note(owned.size()), 16)
	_court_note.name = "CourtNote"
	_court_note.add_theme_color_override("font_color", RetroTheme.SCENE_MUTED)
	head_.add_child(_court_note)
	var row := HBoxContainer.new()
	row.name = "Courts"
	row.add_theme_constant_override("separation", 14)
	section.add_child(row)
	var only := owned.size() < 2
	_courts = {}
	for a in MatchCopy.AREAS:
		var ok: bool = a == "any" or owned.has(a)
		var b := ShadowCard.new(GOLD if a == area_choice else CREAM)
		b.name = "Court_" + a
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, COURT_H + ShadowStyle.OFFSET)
		var inner := HBoxContainer.new()
		inner.name = "Inner"
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_theme_constant_override("separation", 8)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_right = -ShadowStyle.OFFSET
		inner.offset_bottom = -ShadowStyle.OFFSET
		b.add_child(inner)
		if not ok:
			var lock := PixelIcon.new("icon_lock", Vector2(14, 14))
			lock.name = "Lock"
			lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			inner.add_child(lock)
		var w := words(MatchCopy.court_name(a), 13, true)
		w.name = "Name"
		w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inner.add_child(w)
		b.disabled = not ok or only
		b.modulate.a = 0.38 if not ok else (0.45 if only else 1.0)
		b.pressed.connect(func() -> void: set_area(a))
		row.add_child(b)
		_courts[a] = b


func set_area(a: String) -> void:
	if not _courts.has(a):
		return
	area_choice = a
	for id in _courts:
		var b: ShadowCard = _courts[id]
		b.color = GOLD if id == a else CREAM
		b.queue_redraw()
	if _quick_sub != null:
		_quick_sub.text = MatchCopy.quick_sub(a)


func _owned() -> Array:
	var out := []
	for a in ["cage", "beach", "park", "city"]:
		if App.area_unlocked(a):
			out.push_back(a)
	return out


func _big_button(name_: String, text: String, sub: String, fill: Color, on_press: Callable) -> ShadowCard:
	var b := ShadowCard.new(fill)
	b.name = name_
	b.custom_minimum_size = Vector2(0, BTN_H + ShadowStyle.OFFSET)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_right = -ShadowStyle.OFFSET
	col.offset_bottom = -ShadowStyle.OFFSET
	b.add_child(col)
	var l := words(text, 24, true)
	l.name = "Text"
	col.add_child(l)
	var s := words(sub, 16)
	s.name = "Sub"
	col.add_child(s)
	b.pressed.connect(on_press)
	return b


# ---- the cards: LOADOUT (tap to remove) and YOUR CARDS (tap to add) --------------------


## Rebuild from the online bucket's cache (Net.cards_changed, a tap).
func refresh_cards() -> void:
	if _loadout == null:
		return
	for c in _loadout.get_children():
		_loadout.remove_child(c)
		c.queue_free()
	var cd := App.cards_bucket(Net.ONLINE_BUCKET)
	var slots: Array = App.loadout_slots(Net.ONLINE_BUCKET)
	var inv: Dictionary = cd.get("inventory", {})
	# The LOADOUT panel.
	var panel := ShadowPanel.new(GOLD, 12.0, 0.18, 18.0)
	panel.name = "Loadout"
	_loadout.add_child(panel)
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
				App.unequip_card(slot_i, Net.ONLINE_BUCKET)
				refresh_cards())
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
	_loadout.add_child(yours)
	var yh := HBoxContainer.new()
	yh.add_theme_constant_override("separation", 12)
	yours.add_child(yh)
	var yt := words("YOUR CARDS", 16, true)
	yt.name = "YoursTitle"
	yt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	yt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yh.add_child(yt)
	var rule := ColorRect.new()   # the design's underline, drawn under the words
	rule.name = "YoursRule"
	rule.color = CREAM
	rule.custom_minimum_size = Vector2(0, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var free_slots := 0
	for s in slots:
		if s == null:
			free_slots += 1
	for id in inv:
		if int(inv[id]) <= 0:
			continue
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var holder := ModeCards.art(card, SPARE, 6.0, true)
		holder.name = "Spare_" + str(id)
		var cid := str(id)
		(holder.get_meta("button") as TextureButton).pressed.connect(func() -> void:
			if not App.can_equip(cid):
				return
			for slot in CardDefs.SLOTS:
				if App.loadout_slots(Net.ONLINE_BUCKET)[slot] == null:
					App.equip_card(slot, cid, Net.ONLINE_BUCKET)
					break
			refresh_cards())
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
	_loadout.add_child(_spacer_v(18))   # breathing room over the frame's foot


## The old name, kept for the title and QA.
func refresh_strip() -> void:
	refresh_cards()


# ---- the states ------------------------------------------------------------------------


func _go() -> void:
	var code := _code_edit.text.strip_edges().replace(" ", "").to_upper()
	if code.length() != 5:
		show_failed("not_found")
		return
	join.emit(area_choice, code)


func show_menu() -> void:
	_state = "menu"
	_how = ""
	_menu.visible = true
	_wait.visible = false


## Waiting: FINDING A PLAYER… or the code to pass on and WAITING….
func show_waiting(how: String, code := "") -> void:
	_state = "waiting"
	_how = how
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = true
	_cancel.text = "CANCEL"
	_code_block.visible = code != ""
	_code_label.text = code.to_upper()
	_base_big = MatchCopy.waiting_big("quick" if how == "quick" else "code")
	_base_status = MatchCopy.waiting_line("quick" if how == "quick" else "code")
	_big.add_theme_font_size_override("font_size", UiFont.snap(24))
	_big.add_theme_color_override("font_color", CREAM)
	_dots = 0
	_apply_dots()


func show_found(peer: Dictionary) -> void:
	_state = "found"
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = false
	_code_block.visible = false
	_base_big = MatchCopy.found_big()
	_base_status = MatchCopy.found_line(peer)
	_big.add_theme_font_size_override("font_size", UiFont.snap(32))
	_big.add_theme_color_override("font_color", GOLD)
	_dots = 0
	_apply_dots()


func show_failed(reason: String) -> void:
	_state = "failed"
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = true
	_cancel.text = "BACK"
	_code_block.visible = false
	_base_big = MatchCopy.failed_big(reason)
	_base_status = MatchCopy.failed_line(reason)
	_big.add_theme_font_size_override("font_size", UiFont.snap(32))
	_big.add_theme_color_override("font_color", BAD)
	_big.text = _base_big
	_status.text = _base_status


## The live dots on FINDING A PLAYER… and STARTING… (none on a failure).
func _process(dt: float) -> void:
	if _state != "waiting" and _state != "found":
		return
	_dot_t += dt
	if _dot_t >= DOTS_S:
		_dot_t -= DOTS_S
		_dots = (_dots + 1) % 4
		_apply_dots()


func _apply_dots() -> void:
	var d := ".".repeat(_dots)
	if _state == "waiting":
		_big.text = _base_big + d
		_status.text = _base_status
	elif _state == "found":
		_big.text = _base_big
		_status.text = _base_status + d


func state() -> String:
	return _state


func big_text() -> String:
	return _big.text


func status_text() -> String:
	return _status.text


func code_text() -> String:
	return _code_label.text


## `<`: back to the menu from a wait, else close.
func _back() -> void:
	if _state != "menu":
		cancel.emit()
		show_menu()
		return
	close()


func close() -> void:
	cancel.emit()
	slide_out(false, true)


static func _spacer_v(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
