class_name RewardsPage
extends HomePage
## The rewards page (docs/BACKEND.md → Ranked → Stage B; design "Online
## Lobby" 37a's REWARDS view, 2026-10-30), over the lobby: `<` REWARDS; LOGIN
## DAYS (DAY n, how far the next card is, a ten-cell strip with a star on
## each card day ahead); WAITING FOR YOU (the grants with CLAIM, three in
## view, the rest scrolled); MILESTONES (the firsts and the win counts as
## chips, unlocked gold) and RANK (the next step, yours, and every step
## reached below it). No drop meter here since 37a (the post-match page
## still shows it). `build(data)` takes the /v1/rewards dict (tests feed
## tests/fixtures/rewards.json); the title reloads it after a claim. Copy
## from MatchCopy / MilestoneCopy. Nothing asks for more width than the
## frame: long words wrap.

signal claim(key: String)

const GOLD := RetroTheme.LIGHT["gold"]
const MUTED := Color("#D9D9D9")
const DIM := Color("#9A928C")
const INK := RetroTheme.SCENE_OUTLINE
const FADE := Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.92)
const ROW_H := 116.0
const WAIT_MAX_H := 388.0   # three rows in view
const DAY_CELLS := 10
const DAY_BAR_H := 46.0
const CHIP_H := 46.0
const CHIPS_MIN_H := 104.0
const LADDER_H := 290.0

var _data: Dictionary = {}
var _offline := false
var _claimed: Dictionary = {}   # key → true once tapped (until the reload)
var _wait_note: Label
var _login_days: Array = []     # the strip's ten days: {day, got, card}
var _ladder: Array = []         # [kind, name] from the top


func build(data: Dictionary) -> Control:
	_data = data.duplicate(true)
	_offline = false
	if root == null:
		_ready()
	else:
		_build()
	return root


func _ready() -> void:
	if root != null:
		return
	super()


func set_data(data: Dictionary) -> void:
	_data = data.duplicate(true)
	_offline = false
	_claimed.clear()
	_build()


func set_offline() -> void:
	if not _data.is_empty():
		return   # a cached page stays
	_offline = true
	_build()


func _row_gap() -> int:
	return 30


func _build() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_build_head()
	var col := VBoxContainer.new()
	col.name = "Col"
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 26)
	body.add_child(col)
	if _offline and _data.is_empty():
		var off := words(MatchCopy.rewards_offline(), 16)
		off.name = "Offline"
		col.add_child(off)
	elif _data.is_empty():
		# Nothing cached yet: the skeleton until /v1/rewards answers (39b).
		col.add_child(SkeletonList.new("LOADING REWARDS", RetroTheme.SCENE_TEXT, true))
	else:
		_build_logins(col)
		_build_pending(col)
		_build_milestones(col)
	body.add_child(_gap(4))


## `<` and REWARDS, as the lobby's head.
func _build_head() -> void:
	var h := HBoxContainer.new()
	h.name = "Head"
	h.add_theme_constant_override("separation", 20)
	body.add_child(h)
	var back := button("<", CREAM, 24, 56.0 - ShadowStyle.OFFSET)
	back.name = "Back"
	back.custom_minimum_size = Vector2(56 + ShadowStyle.OFFSET, 56 + ShadowStyle.OFFSET)
	back.pressed.connect(close)
	h.add_child(back)
	var t := words(MatchCopy.rewards_title(), 28, true)
	t.name = "Title"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)


## A section head: the words, a rule to the note, the note in grey.
func _section(col: VBoxContainer, title: String, note: String) -> VBoxContainer:
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 16)
	col.add_child(sec)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sec.add_child(h)
	var t := words(title, 20, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(t)
	var rule := ColorRect.new()
	rule.color = Color(CREAM, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(rule)
	var n := words(note, 19)
	n.name = "Note"
	n.add_theme_color_override("font_color", MUTED)
	h.add_child(n)
	return sec


# ---- LOGIN DAYS ----------------------------------------------------------------------------


func _build_logins(col: VBoxContainer) -> void:
	var days := int(_data.get("login_days", 0))
	var next_day := int(_data.get("next_login_card", OnlineDrops.next_login_card(days)))
	var sec := _section(col, MatchCopy.login_head(), MatchCopy.login_note(next_day))
	sec.name = "Logins"
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sec.add_child(line)
	var d := words(MatchCopy.login_day(days), 32, true)
	d.name = "LoginDay"
	d.add_theme_color_override("font_color", GOLD)
	line.add_child(d)
	var more := words(MatchCopy.login_more(days, next_day), 19)
	more.name = "LoginMore"
	more.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(more)
	_login_days = login_window(days, next_day, _card_days())
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sec.add_child(strip)
	var bar := DayBar.new()
	bar.name = "DayBar"
	bar.days = _login_days
	strip.add_child(bar)
	var nums := HBoxContainer.new()
	nums.name = "DayNumbers"
	nums.add_theme_constant_override("separation", 0)
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(nums)
	for e in _login_days:
		var n := words(str(e["day"]), 13, true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_color_override("font_color", GOLD if e["got"] or e["card"] else DIM)
		nums.add_child(n)
	# The numbers sit under the cells, not under the shadow.
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(ShadowStyle.OFFSET - 1.0, 0)
	nums.add_child(pad)


## The login schedule's card days (1, 3, 7, 10, 30…).
static func _card_days() -> Array:
	var out := []
	for entry in OnlineDrops.logins_cfg().get("schedule", []):
		if entry is Array and entry.size() >= 1:
			out.push_back(int(entry[0]))
	return out


## The strip's ten days, ending on the next card day (or the last ten days
## once every card is earned): {day, got, card} — card marks a card day ahead.
static func login_window(days: int, next_day: int, card_days: Array) -> Array:
	var last := next_day if next_day > 0 else maxi(days, DAY_CELLS)
	var first := maxi(1, last - DAY_CELLS + 1)
	var out := []
	for i in DAY_CELLS:
		var day := first + i
		out.push_back({"day": day, "got": day <= days, "card": day > days and card_days.has(day)})
	return out


## The ten cells: gold up to today, a star on a card day ahead, a white
## frame with a hard shadow.
class DayBar:
	extends Control
	const SHADOW := 4.0
	const EDGE := 3.0
	var days: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		custom_minimum_size = Vector2(0, DAY_BAR_H + SHADOW)

	func _draw() -> void:
		var w := size.x - SHADOW
		var h := DAY_BAR_H
		draw_rect(Rect2(w, SHADOW, SHADOW, h), INK)
		draw_rect(Rect2(SHADOW, h, w - SHADOW, SHADOW), INK)
		var face := Rect2(0, 0, w, h)
		draw_rect(face, Color(INK, 0.75))
		var inner := face.grow(-EDGE)
		var cw := inner.size.x / float(maxi(days.size(), 1))
		var star: Texture2D = load("res://assets/ui/icon_star.png")
		for i in days.size():
			var e: Dictionary = days[i]
			var cell := Rect2(inner.position.x + cw * i, inner.position.y, cw, inner.size.y)
			if e["got"]:
				draw_rect(cell, GOLD)
				draw_texture_rect(ShadowStyle.dot_tex(), cell, true, Color(INK, ShadowStyle.DOT_ALPHA))
			elif e["card"]:
				draw_rect(cell, Color(GOLD, 0.18))
				if star != null:
					draw_texture_rect(star, Rect2(cell.get_center() - Vector2(11, 11), Vector2(22, 22)), false)
			if i > 0:
				draw_rect(Rect2(cell.position.x - 1.0, cell.position.y, 2.0, cell.size.y), INK)
		draw_rect(face.grow(-EDGE * 0.5), CREAM, false, EDGE)


# ---- WAITING FOR YOU -----------------------------------------------------------------------


func _build_pending(col: VBoxContainer) -> void:
	var pending: Array = _data.get("pending", []) if _data.get("pending") is Array else []
	var sec := _section(col, MatchCopy.pending_head(), MatchCopy.pending_note(_left(pending)) if not pending.is_empty() else "")
	sec.name = "Waiting"
	_wait_note = sec.find_child("Note", true, false)
	if pending.is_empty():
		var none := words(MatchCopy.nothing_pending().replace(" · ", "\n"), 16)
		none.name = "NothingPending"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sec.add_child(none)
		return
	var list := VBoxContainer.new()
	list.name = "Pending"
	list.add_theme_constant_override("separation", 16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for g in pending:
		list.add_child(_grant_row(g if g is Dictionary else {}))
	var n := pending.size()
	var full := n * (ROW_H + ShadowStyle.OFFSET) + (n - 1) * 16.0
	sec.add_child(_faded_scroll("PendingScroll", list, minf(full, WAIT_MAX_H + ShadowStyle.OFFSET), 90.0))


func _left(pending: Array) -> int:
	var n := 0
	for g in pending:
		if g is Dictionary and not _claimed.get(str(g.get("key", "")), false):
			n += 1
	return n


## A grant: its card, the kind over its name, CLAIM (gold) → CLAIMED (dim).
func _grant_row(gd: Dictionary) -> Control:
	var key := str(gd.get("key", ""))
	var row := ShadowPanel.new(CREAM, 0.0, 0.24, 18.0)
	row.name = "Grant_" + key
	row.custom_minimum_size = Vector2(0, ROW_H + ShadowStyle.OFFSET)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var card := CardDefs.get_card(str(gd.get("card", "")))
	if not card.is_empty():
		var art := ModeCards.art(card, Vector2(66, 88), 4.0)
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(art)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 12)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(text)
	var kind := words(MilestoneCopy.kind_word(str(gd.get("kind", ""))), 18)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	kind.add_theme_color_override("font_color", MUTED)
	text.add_child(kind)
	var nm := words(MilestoneCopy.name(key), 20, true)
	nm.name = "Name"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = 1.0
	text.add_child(nm)
	var done := bool(_claimed.get(key, false))
	var b := button(MatchCopy.claim_word(done), MUTED if done else GOLD, 18, 72.0 - ShadowStyle.OFFSET)
	b.name = "Claim"
	b.custom_minimum_size = Vector2(150, 72)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = done
	row.modulate.a = 0.5 if done else 1.0
	b.pressed.connect(func() -> void:
		if _claimed.get(key, false):
			return
		_claimed[key] = true
		b.text = MatchCopy.claim_word(true)
		b.color = MUTED
		b.disabled = true
		b.queue_redraw()
		row.modulate.a = 0.5
		if is_instance_valid(_wait_note):
			_wait_note.text = MatchCopy.pending_note(_left(_data.get("pending", [])))
		claim.emit(key))
	h.add_child(b)
	return row


# ---- MILESTONES + RANK ---------------------------------------------------------------------


func _build_milestones(col: VBoxContainer) -> void:
	var unlocked: Array = _data.get("unlocked", []) if _data.get("unlocked") is Array else []
	var keys: Array = _data.get("all_milestones", []) if _data.get("all_milestones") is Array else []
	if keys.is_empty():
		keys = OnlineDrops.all_milestone_keys()
	var done := 0
	for k in keys:
		if unlocked.has(str(k)):
			done += 1
	var sec := _section(col, MatchCopy.milestones_head(), MatchCopy.milestones_note(done, keys.size()))
	sec.name = "MilestonesSection"
	sec.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var flow := HFlowContainer.new()
	flow.name = "Milestones"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var steps := []
	for k in keys:
		var key := str(k)
		if MilestoneCopy.is_step(key):
			steps.push_back(key)
		else:
			flow.add_child(_chip(key, unlocked.has(key)))
	var chips := _faded_scroll("MilestoneScroll", flow, CHIPS_MIN_H, 56.0)
	chips.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sec.add_child(chips)
	# RANK: the next step, yours, then every step reached below it.
	var head := words(MatchCopy.rank_head(), 19)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_color_override("font_color", MUTED)
	var rank := VBoxContainer.new()
	rank.add_theme_constant_override("separation", 10)
	rank.add_child(head)
	sec.add_child(rank)
	_ladder = ladder_rows(steps, unlocked)
	var rows := VBoxContainer.new()
	rows.name = "Ladder"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	for r in _ladder:
		rows.add_child(_ladder_row(r[0], r[1]))
	rows.add_child(_gap(20))
	rank.add_child(_faded_scroll("LadderScroll", rows, LADDER_H, 90.0))


## A milestone chip: `+ FIRST LOGIN` gold when unlocked, `- …` dim when not.
func _chip(key: String, on: bool) -> Control:
	var c := DotBox.new()
	c.name = "Milestone_" + key
	c.on = on
	c.edge = GOLD if on else Color(CREAM, 0.3)
	c.fill = Color(GOLD, 0.28) if on else Color(INK, 0.5)
	c.dots = on
	c.pad = Vector2(14, 0)
	c.custom_minimum_size = Vector2(0, CHIP_H)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	var colour := CREAM if on else DIM
	var mark := words("+" if on else "-", 14, true)
	mark.add_theme_color_override("font_color", colour)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(mark)
	var t := words(MilestoneCopy.name(key), 18)
	t.name = "Text"
	t.add_theme_color_override("font_color", colour)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	return c


## The ladder from the top: NEXT (the first step past yours), YOU (your
## highest step reached), then each step reached below it. Steps come in
## the server's order, lowest first (tier, then III, II, I).
static func ladder_rows(steps: Array, unlocked: Array) -> Array:
	var you := -1
	for i in steps.size():
		if unlocked.has(steps[i]):
			you = i
	var out := []
	if you + 1 < steps.size():
		out.push_back(["next", MilestoneCopy.step_name(steps[you + 1])])
	if you >= 0:
		out.push_back(["you", MilestoneCopy.step_name(steps[you])])
		for i in range(you - 1, -1, -1):
			if unlocked.has(steps[i]):
				out.push_back(["past", MilestoneCopy.step_name(steps[i])])
	return out


func _ladder_row(kind: String, name_: String) -> Control:
	var you := kind == "you"
	var next := kind == "next"
	var r := DotBox.new()
	r.name = "Step_" + kind if kind != "past" else "Step_" + name_.replace(" ", "_")
	r.edge = GOLD if you else (CREAM if next else Color(CREAM, 0.3))
	r.edge_w = 3.0 if you else 2.0
	r.dashed = next
	r.fill = Color(GOLD, 0.3) if you else Color(INK, 0.5 if next else 0.45)
	r.dots = you
	r.pad = Vector2(18, 0)
	r.custom_minimum_size = Vector2(0, 68.0 if you else (56.0 if next else 50.0))
	r.modulate.a = 1.0 if you or next else 0.85
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(h)
	var mark := words(">" if you else ("^" if next else "+"), 16, true)
	mark.custom_minimum_size.x = 28
	mark.add_theme_color_override("font_color", GOLD if not next else CREAM)
	h.add_child(mark)
	var nm := words(name_, 22 if you else (18 if next else 16), true)
	nm.name = "Name"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_color_override("font_color", GOLD if you else (CREAM if next else MUTED))
	h.add_child(nm)
	var tag := words(MatchCopy.ladder_tag(kind), 18)
	tag.add_theme_color_override("font_color", GOLD if you else (CREAM if next else MUTED))
	h.add_child(tag)
	for l in h.get_children():
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return r


# ---- pieces ---------------------------------------------------------------------------------


## A scroll with no bar over `content`, `h` tall, and a dark fade at its
## foot while there is more below.
func _faded_scroll(name_: String, content: Control, h: float, fade_h: float) -> Control:
	var wrap := Control.new()
	wrap.name = name_
	wrap.custom_minimum_size = Vector2(0, h)
	wrap.clip_contents = true
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	UiLayout.full_rect(scroll)
	wrap.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var g := Gradient.new()
	g.set_color(0, Color(FADE, 0.0))
	g.set_color(1, FADE)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var fade := TextureRect.new()
	fade.name = "Fade"
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -fade_h
	fade.offset_bottom = 0
	wrap.add_child(fade)
	var bar := scroll.get_v_scroll_bar()
	var sync := func() -> void:
		if is_instance_valid(fade):
			fade.visible = bar.value + bar.page < bar.max_value - 6.0
	bar.value_changed.connect(func(_v: float) -> void: sync.call())
	bar.changed.connect(sync)
	sync.call_deferred()
	return wrap


static func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A flat face without a shadow: the fill, the dots (gold faces), a solid or
## dashed edge, the child inset by `pad`.
class DotBox:
	extends Container
	var edge := Color.WHITE
	var edge_w := 2.0
	var fill := Color.TRANSPARENT
	var dots := false
	var dashed := false
	var on := false
	var pad := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _get_minimum_size() -> Vector2:
		var m := Vector2.ZERO
		for c in get_children():
			if c is Control and (c as Control).visible:
				m = m.max((c as Control).get_combined_minimum_size())
		return m + 2.0 * pad

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					fit_child_in_rect(c, Rect2(pad, size - 2.0 * pad))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, fill)
		if dots:
			draw_texture_rect(ShadowStyle.dot_tex(), r, true, Color(edge, ShadowStyle.DOT_ALPHA))
		var e := r.grow(-edge_w * 0.5)
		if dashed:
			var corners := [e.position, Vector2(e.end.x, e.position.y), e.end, Vector2(e.position.x, e.end.y)]
			for i in 4:
				draw_dashed_line(corners[i], corners[(i + 1) % 4], edge, edge_w, 6.0)
		else:
			draw_rect(e, edge, false, edge_w)


# ---- for tests and QA -----------------------------------------------------------------------


func pending_count() -> int:
	return Array(_data.get("pending", []) if _data.get("pending") is Array else []).size()


func login_days() -> Array:
	return _login_days


func ladder() -> Array:
	return _ladder


func login_text() -> String:
	var d := root.find_child("LoginDay", true, false) as Label
	var m := root.find_child("LoginMore", true, false) as Label
	return "%s · %s" % [d.text, m.text] if d != null and m != null else ""
