class_name RewardsPage
extends HomePage
## The rewards page (docs/BACKEND.md → Ranked → Stage B), over the lobby:
## the drop meter with its odds, the grants waiting for a CLAIM (login days,
## a welcome-back card, milestones), the login-day count, and every
## milestone — unlocked gold, the rest dim. `build(data)` takes the
## /v1/rewards dict (tests feed tests/fixtures/rewards.json); the title
## reloads it after a claim. Copy from MatchCopy / MilestoneCopy.
## Every line wraps (a label's text is otherwise the page's minimum width,
## and the frame would grow past the screen — Ross saw the EPIC odds push
## the whole page right, 2026-10-28); the meter line breaks on purpose,
## METER 14/22 over the odds, once it is wider than the frame.

signal claim(key: String)

const GOLD := RetroTheme.LIGHT["gold"]
const ROW_H := 96.0

var _data: Dictionary = {}
var _offline := false
var _claimed: Dictionary = {}   # key → true once tapped (until the reload)


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
	return 18


func _build() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	head(MatchCopy.rewards_title())
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	if _offline and _data.is_empty():
		var off := words(MatchCopy.rewards_offline(), 16)
		off.name = "Offline"
		col.add_child(off)
	elif _data.is_empty():
		# Nothing cached yet: the skeleton until /v1/rewards answers (39b).
		col.add_child(SkeletonList.new("LOADING REWARDS", RetroTheme.SCENE_TEXT, true))
	else:
		_build_meter(col)
		_build_pending(col)
		_build_logins(col)
		_build_milestones(col)
	close_button()


func _build_meter(col: VBoxContainer) -> void:
	col.add_child(chip(MatchCopy.meter_head()))
	var m: Dictionary = _data.get("meter", {}) if _data.get("meter") is Dictionary else {}
	var size_ := int(m.get("size", OnlineDrops.meter_size()))
	var progress := int(m.get("progress", 0))
	var bar := Control.new()
	bar.name = "MeterBar"
	bar.custom_minimum_size = Vector2(0, 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := ColorRect.new()
	track.color = Color(RetroTheme.SCENE_OUTLINE, 0.55)
	UiLayout.full_rect(track)
	bar.add_child(track)
	var fill := ColorRect.new()
	fill.name = "MeterFill"
	fill.color = GOLD
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(float(progress) / maxf(float(size_), 1.0), 0.0, 1.0)
	bar.add_child(fill)
	col.add_child(bar)
	var text := MatchCopy.meter_line({"meter": {"after": progress, "size": size_, "odds": m.get("odds", OnlineDrops.odds_for(str(_data.get("tier", "rookie")), App.level()))}})
	var line := words(_two_lines(text, 16), 16, true)
	line.name = "MeterLine"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_color_override("font_color", GOLD)
	col.add_child(line)
	var cap := words(MatchCopy.meter_caption(), 14)
	cap.name = "MeterCaption"
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(cap)


func _build_pending(col: VBoxContainer) -> void:
	col.add_child(chip(MatchCopy.pending_head()))
	var pending: Array = _data.get("pending", []) if _data.get("pending") is Array else []
	if pending.is_empty():
		var none := words(_two_lines(MatchCopy.nothing_pending(), 14, false), 14)
		none.name = "NothingPending"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(none)
		return
	var list := VBoxContainer.new()
	list.name = "Pending"
	list.add_theme_constant_override("separation", 12)
	col.add_child(list)
	for g in pending:
		var gd: Dictionary = g if g is Dictionary else {}
		var key := str(gd.get("key", ""))
		var row := ShadowPanel.new(CREAM, 0.0, 0.24, 16.0)
		row.name = "Grant_" + key
		row.custom_minimum_size = Vector2(0, ROW_H + ShadowStyle.OFFSET)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		UiLayout.full_rect(h)
		h.offset_right = -ShadowStyle.OFFSET
		h.offset_bottom = -ShadowStyle.OFFSET
		row.add_child(h)
		var card := CardDefs.get_card(str(gd.get("card", "")))
		if not card.is_empty():
			var art := ModeCards.art(card, Vector2(54, 72), 3.0)
			art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(art)
		var text := VBoxContainer.new()
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 8)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kind := words(MilestoneCopy.kind_word(str(gd.get("kind", ""))), 14)
		kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(kind)
		var nm := words(MilestoneCopy.name(key), 16, true)
		nm.name = "Name"
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(nm)
		h.add_child(text)
		var done := bool(_claimed.get(key, false))
		var b := button(MatchCopy.claim_word(done), GOLD if not done else CREAM, 16, 56.0 - ShadowStyle.OFFSET)
		b.name = "Claim"
		b.custom_minimum_size = Vector2(150, 56 + ShadowStyle.OFFSET)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = done
		b.pressed.connect(func() -> void:
			if _claimed.get(key, false):
				return
			_claimed[key] = true
			b.text = MatchCopy.claim_word(true)
			b.color = CREAM
			b.disabled = true
			b.queue_redraw()
			claim.emit(key))
		h.add_child(b)
		list.add_child(row)


func _build_logins(col: VBoxContainer) -> void:
	var days := int(_data.get("login_days", 0))
	var next_day := int(_data.get("next_login_card", OnlineDrops.next_login_card(days)))
	var l := words(_two_lines(MatchCopy.login_line(days, next_day), 16), 16, true)
	l.name = "LoginLine"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)


func _build_milestones(col: VBoxContainer) -> void:
	col.add_child(chip(MatchCopy.milestones_head()))
	var unlocked: Array = _data.get("unlocked", []) if _data.get("unlocked") is Array else []
	var keys: Array = _data.get("all_milestones", []) if _data.get("all_milestones") is Array else []
	if keys.is_empty():
		keys = OnlineDrops.all_milestone_keys()
	var grid := GridContainer.new()
	grid.name = "Milestones"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	for k in keys:
		var key := str(k)
		var on := unlocked.has(key)
		var l := words(("+ " if on else "- ") + MilestoneCopy.name(key), 14, false)
		l.name = "Milestone_" + key
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", GOLD if on else CREAM)
		if not on:
			l.modulate = Color(1, 1, 1, 0.5)
		grid.add_child(l)


## A line wider than the frame's inside breaks at its first " · " (METER
## 14/22 over the odds, LOGIN DAYS · 5 over the next card, NOTHING WAITING
## over the hint) instead of wrapping wherever the width falls.
func _two_lines(text: String, size_: int, display := true) -> String:
	var f := UiFont.display() if display else UiFont.body_bold()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(size_)).x + 2.0 * RetroTheme.OUTLINE
	var i := text.find(" · ")
	if i < 0 or w <= FRAME_SIZE.x - 2.0 * PAD:
		return text
	return text.substr(0, i) + "\n" + text.substr(i + 3)


func pending_count() -> int:
	return Array(_data.get("pending", []) if _data.get("pending") is Array else []).size()


func meter_text() -> String:
	var l := root.find_child("MeterLine", true, false) as Label
	return l.text if l != null else ""
