class_name MatchLobbyPage
extends FaceOffPage
## The 1v1 lobby (design "Online Lobby" 37a, 2026-10-17; docs/HOME.md → 1v1,
## docs/BACKEND.md → Phase 3) with the locker treatment: a HomePage over the
## area — the home slides out left, this slides in from the right, every
## face see-through and dotted. `<` ONLINE · 1V1; the COURT picker (ANY and
## the four courts, locked ones dimmed with a lock; the row itself dimmed
## while only the cage is open); RANKED (2026-10-19: one global rated queue,
## any court both own — the picker does not constrain it), QUICK MATCH,
## CREATE CODE, ENTER CODE + GO. The loadout moved to the pre-match page
## (PreMatchPage). The waits: FINDING A PLAYER… / the big gold
## code and WAITING… with CANCEL; PLAYER FOUND; a failure with BACK. The
## quick wait and PLAYER FOUND are a face-off (2026-10-18): your card, VS,
## and theirs — a pulsing "?" beside a reel of names while searching, then
## the gold card popping in, VS slamming down and the court sliding in. The
## page owns no network: it emits `ranked`, `quick(area)`, `create(area)`,
## `join(area, code)` and `cancel`; App drives it through show_waiting /
## show_found / show_failed.

signal ranked
## The REWARDS row (Stage B): the title opens the rewards page.
signal rewards
signal quick(area: String)
signal create(area: String)
signal join(area: String, code: String)
signal cancel

const BTN_H := 112.0
const COURT_H := 60.0
const FIELD_BG := Color(34.0 / 255.0, 28.0 / 255.0, 24.0 / 255.0, 0.55)
const BAD := Color("#FF8A6A")
const DOTS_S := 0.45
const REEL_S := 0.11       # a new face on the reel
const REEL_IN_S := 0.1     # …sliding down 36 px into place
const REEL_H := 110.0
const PULSE_S := 0.45      # the "?" and the "..." blink (1 ↔ 0.35)
const POP_S := 0.45        # the found card: 0.85 → 1.04 → 1
const VS_S := 0.3          # VS from 1.6× in three steps
const COURT_AT := 0.35     # the court line, after the pop…
const COURT_S := 0.3       # …sliding in

var area_choice := "any"
var _menu: VBoxContainer
var _wait: VBoxContainer
var _courts: Dictionary = {}
var _court_note: Label
var _quick_sub: Label
var _rewards_sub: Label
var _code_edit: LineEdit
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
var _vs: VBoxContainer
var _you_card: ShadowPanel
var _vs_word: Label
var _opp_search: ShadowPanel
var _opp_found: ShadowPanel
var _court_line: Control
var _court_row: HBoxContainer
var _court_label: Label
var _qbox: Control
var _qdots: Label
var _reel_entry: VBoxContainer
var _reel_rng := DetRng.new()
var _reel_t := 0.0
var _pulse_t := 0.0
var _found_t := -1.0       # < 0: no found timeline running
var _found_area := ""


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
	_menu.add_child(_big_button("Ranked", "RANKED", MatchCopy.ranked_sub(), GOLD, func() -> void: ranked.emit()))
	# Stage B (docs/BACKEND.md → Ranked → Stage B): the rewards page, with
	# what waits for a CLAIM on its sub-line.
	_menu.add_child(_big_button("Rewards", "REWARDS", MatchCopy.rewards_sub(Net.pending_rewards), CREAM, func() -> void: rewards.emit()))
	_rewards_sub = _menu.get_node("Rewards/Col/Sub")
	_style_rewards_sub(Net.pending_rewards)
	var on_badge := func(n: int) -> void:
		if is_instance_valid(_rewards_sub):
			_rewards_sub.text = MatchCopy.rewards_sub(n)
			_style_rewards_sub(n)
	Net.rewards_badge.connect(on_badge)
	_menu.tree_exited.connect(func() -> void:
		if Net.rewards_badge.is_connected(on_badge):
			Net.rewards_badge.disconnect(on_badge))
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
	var push := Control.new()
	push.name = "Push"
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(push)
	# The waits.
	_wait = VBoxContainer.new()
	_wait.name = "Wait"
	_wait.visible = false
	_wait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wait.alignment = BoxContainer.ALIGNMENT_CENTER
	_wait.add_theme_constant_override("separation", 30)
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
	_build_face_off()
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
	_wait.add_child(_spacer_v(70))
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


## A pending count turns the REWARDS sub gold.
func _style_rewards_sub(n: int) -> void:
	if is_instance_valid(_rewards_sub):
		_rewards_sub.add_theme_color_override("font_color", GOLD if n > 0 else CREAM)


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


# ---- the face-off (design 37a, 2026-10-18) -----------------------------------------------


## YOU · VS · the opponent (the "?" and the reel while searching, the gold
## card once found), and the court line under it.
func _build_face_off() -> void:
	_vs = VBoxContainer.new()
	_vs.name = "Vs"
	_vs.visible = false
	_vs.add_theme_constant_override("separation", 22)
	_vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait.add_child(_vs)
	_you_card = _face_card("YouCard", CREAM, MatchCopy.you_label())
	_vs.add_child(_you_card)
	# VS between two rules.
	var row := _vs_row()
	_vs.add_child(row)
	_vs_word = row.get_node("VsWord")
	# Searching: the "?" and the reel.
	_opp_search = ShadowPanel.new(CREAM, 0.0, ShadowStyle.TINT, 24.0)
	_opp_search.name = "OppSearch"
	_opp_search.custom_minimum_size = Vector2(0, FACE_H + ShadowStyle.OFFSET)
	_vs.add_child(_opp_search)
	var srow := _face_row()
	_opp_search.add_child(srow)
	_qbox = ModeCards.empty_slot(Vector2.ONE * FACE_ICON, 28, 3.0)
	_qbox.name = "Ask"
	_qbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(_qbox.get_child(0) as Label).text = "?"
	srow.add_child(_qbox)
	var reel := Control.new()
	reel.name = "Reel"
	reel.clip_contents = true
	reel.custom_minimum_size = Vector2(0, REEL_H)
	reel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(reel)
	_reel_entry = _face_lines(CREAM, CREAM, CREAM)
	_reel_entry.name = "ReelEntry"
	_reel_entry.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_reel_entry.offset_top = 12.0
	reel.add_child(_reel_entry)
	_qdots = _corner(srow, "...", CREAM)
	_qdots.name = "SearchDots"
	# Found: the gold card.
	_opp_found = _face_card("OppFound", GOLD, MatchCopy.opp_label())
	_vs.add_child(_opp_found)
	# The court, sliding in under the found card.
	_court_line = Control.new()
	_court_line.name = "CourtLine"
	_court_line.custom_minimum_size = Vector2(0, 30)
	_court_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vs.add_child(_court_line)
	_court_row = HBoxContainer.new()
	_court_row.name = "Row"
	_court_row.add_theme_constant_override("separation", 12)
	_court_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_court_line.add_child(_court_row)
	var star := PixelIcon.new("icon_star", Vector2(18, 18))
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_court_row.add_child(star)
	_court_label = words("", 18)
	_court_label.name = "Court"
	_court_row.add_child(_court_label)


## YOU: the account's handle, the hometown, the level, the rank.
func _fill_you() -> void:
	_fill_lines(_you_card, you_record())


func _next_reel_face() -> void:
	var e := MatchCopy.reel_entry(_reel_rng)
	_set_name(_reel_entry.find_child("Name", true, false) as Label, str(e["name"]))
	(_reel_entry.find_child("Tag", true, false) as Label).text = ""
	(_reel_entry.find_child("Place", true, false) as Label).text = str(e["place"])
	(_reel_entry.find_child("Online", true, false) as Label).text = str(e["online"])
	_reel_t = 0.0


## The court under the found card (an any-court host learns it at the tip-off).
func set_found_court(area: String) -> void:
	_found_area = area
	if _court_label != null:
		_court_label.text = MatchCopy.found_court(area)


## The face-off clock: the reel and the blinks while searching, the pop,
## the VS slam and the court line once found. _process drives it; the tests
## call it directly.
func advance(dt: float) -> void:
	if _vs == null or not _vs.visible:
		return
	_pulse_t += dt
	var blink := 1.0 if fmod(_pulse_t, 2.0 * PULSE_S) < PULSE_S else 0.35
	if _opp_search.visible:
		_qbox.modulate.a = blink
		_qdots.modulate.a = blink
		_reel_t += dt
		if _reel_t >= REEL_S:
			_next_reel_face()
		var p := clampf(_reel_t / REEL_IN_S, 0.0, 1.0)
		_reel_entry.offset_top = 12.0 - 36.0 * (1.0 - p)
		_reel_entry.offset_bottom = _reel_entry.offset_top + _reel_entry.get_combined_minimum_size().y
		_reel_entry.modulate.a = 0.7 * p
	if _found_t >= 0.0:
		_found_t += dt
		# The card: 0.85 → 1.04 by 60 %, then home; in by 60 %.
		var p := clampf(_found_t / POP_S, 0.0, 1.0)
		var k := 0.85 + 0.19 * _ease_out(p / 0.6) if p < 0.6 else 1.04 - 0.04 * _ease_out((p - 0.6) / 0.4)
		_opp_found.pivot_offset = _opp_found.size * 0.5
		_opp_found.scale = Vector2.ONE * k
		_opp_found.modulate.a = clampf(p / 0.6, 0.0, 1.0)
		# VS: 1.6 → 1 in three steps.
		var step := mini(3, int(floor(_found_t / VS_S * 3.0)))
		_vs_word.pivot_offset = _vs_word.size * 0.5
		_vs_word.scale = Vector2.ONE * (1.6 - 0.6 * step / 3.0)
		# The court line slides down into place.
		var c := clampf((_found_t - COURT_AT) / COURT_S, 0.0, 1.0)
		var w := _court_row.get_combined_minimum_size()
		_court_row.size = w
		_court_row.position = Vector2((_court_line.size.x - w.x) * 0.5, -36.0 * (1.0 - _ease_out(c)))
		_court_line.modulate.a = c


static func _ease_out(p: float) -> float:
	var q := 1.0 - clampf(p, 0.0, 1.0)
	return 1.0 - q * q * q


func reel_name() -> String:
	return (_reel_entry.find_child("Name", true, false) as Label).text


func opp_name() -> String:
	return (_opp_found.find_child("Name", true, false) as Label).text


func vs_scale() -> float:
	return _vs_word.scale.x


func found_popped() -> bool:
	return _found_t >= POP_S and is_equal_approx(_opp_found.scale.x, 1.0) and _opp_found.modulate.a > 0.99


func court_text() -> String:
	return _court_label.text


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
	_found_t = -1.0


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
	var kind := "code" if how in ["create", "join"] else how
	_base_big = MatchCopy.waiting_big(kind)
	_base_status = MatchCopy.waiting_line(kind)
	_big.add_theme_font_size_override("font_size", UiFont.snap(24))
	_big.add_theme_color_override("font_color", CREAM)
	_dots = 0
	_apply_dots()
	# The quick wait is the face-off with the reel; the code wait is the code.
	_found_t = -1.0
	_vs.visible = how in ["quick", "ranked"]
	if _vs.visible:
		_fill_you()
		_opp_search.visible = true
		_opp_found.visible = false
		_court_line.visible = false
		_vs_word.scale = Vector2.ONE
		_reel_rng.reseed(Time.get_ticks_usec())
		_next_reel_face()
		advance(0.0)


## PLAYER FOUND: the gold card pops in where the reel was (a joiner comes
## straight here). `peer` may carry `area` (the court) and `town`.
func show_found(peer: Dictionary) -> void:
	_state = "found"
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = false
	_code_block.visible = false
	_base_big = MatchCopy.found_big()
	_base_status = MatchCopy.found_line()
	_big.add_theme_font_size_override("font_size", UiFont.snap(32))
	_big.add_theme_color_override("font_color", GOLD)
	_dots = 0
	_apply_dots()
	_vs.visible = true
	_fill_you()
	_fill_lines(_opp_found, peer)
	_opp_search.visible = false
	_opp_found.visible = true
	_court_line.visible = true
	set_found_court(str(peer.get("area", _found_area if _found_area != "" else area_choice)))
	_found_t = 0.0
	advance(0.0)


func show_failed(reason: String) -> void:
	_state = "failed"
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = true
	_cancel.text = "BACK"
	_code_block.visible = false
	_vs.visible = false
	_found_t = -1.0
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
	advance(dt)
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

