class_name PreMatchPage
extends FaceOffPage
## The pre-match pick (docs/BACKEND.md → Ranked, 2026-10-19): between PLAYER
## FOUND and the tip-off, over the lobby. Your card and theirs (handle, town
## · level, the ladder badge), the CARD CAP line — both loadouts stop at the
## lower of the two levels — the LOADOUT strip (a spare above the cap is
## dimmed with its level and refuses the tap), a timer bar and READY. The
## page sends its current pick as it changes (`picked`, provisional) and
## `readied(slots)` on READY; at zero it readies itself with what it has, as
## the room starts then anyway. Built to be reused before SOLO league heats
## (a later task): `build` takes a plain info dict, not a room.

signal picked(slots: Array)
signal readied(slots: Array)
signal cancelled

const BAR_H := 14.0

var bucket := Net.ONLINE_BUCKET
var cap := 1
var seconds := 20.0
var _info: Dictionary = {}
var _left := 20.0
var _ready_sent := false
var _you_card: ShadowPanel
var _opp_card: ShadowPanel
var _strip: VBoxContainer
var _ready_btn: ShadowCard
var _timer_label: Label
var _bar: Control
var _fill: ColorRect


## `info` is the room's `matched` ({peer, levels, tiers, cap, seconds, side})
## — or anything with `peer` and `cap`.
func build(info: Dictionary, p_bucket := "") -> Control:
	_info = info.duplicate(true)
	if p_bucket != "":
		bucket = p_bucket
	cap = maxi(1, int(info.get("cap", App.level())))
	seconds = float(info.get("seconds", RankedRules.prematch_cfg().get("seconds", 20)))
	_left = seconds
	_ready_sent = false
	if root == null:
		_ready()
	else:
		_build()
	return root


func _ready() -> void:
	if root != null:
		return
	super()


func _row_gap() -> int:
	return 22


func _build() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var title := words(MatchCopy.prematch_title(), 28, true)
	title.name = "Title"
	body.add_child(title)
	# The face-off: YOU, VS, the opponent (gold).
	_you_card = _face_card("YouCard", CREAM, MatchCopy.you_label())
	body.add_child(_you_card)
	_fill_lines(_you_card, you_record())
	body.add_child(_vs_row())
	_opp_card = _face_card("OppCard", GOLD, MatchCopy.opp_label())
	body.add_child(_opp_card)
	_fill_lines(_opp_card, opponent_record())
	# The cap.
	var cap_l := words(MatchCopy.cap_line(cap), 16, true)
	cap_l.name = "CapLine"
	cap_l.add_theme_color_override("font_color", GOLD)
	body.add_child(cap_l)
	# The loadout.
	_strip = VBoxContainer.new()
	_strip.name = "Cards"
	_strip.add_theme_constant_override("separation", 12)
	_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_strip)
	refresh_cards()
	# The timer bar and READY.
	var timer_row := HBoxContainer.new()
	timer_row.name = "TimerRow"
	timer_row.add_theme_constant_override("separation", 16)
	body.add_child(timer_row)
	_timer_label = words(MatchCopy.timer_line(_left), 16, true)
	_timer_label.name = "TimerLine"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_timer_label.custom_minimum_size.x = 190
	timer_row.add_child(_timer_label)
	_bar = Control.new()
	_bar.name = "TimerBar"
	_bar.custom_minimum_size = Vector2(0, BAR_H)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_row.add_child(_bar)
	var track := ColorRect.new()
	track.name = "Track"
	track.color = Color(RetroTheme.SCENE_OUTLINE, 0.55)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(track)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.color = GOLD
	_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_fill.anchor_right = 1.0
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_fill)
	_ready_btn = button(MatchCopy.ready_word(false), ORANGE, 24, 84.0 - ShadowStyle.OFFSET)
	_ready_btn.name = "Ready"
	_ready_btn.custom_minimum_size = Vector2(0, 84 + ShadowStyle.OFFSET)
	_ready_btn.pressed.connect(press_ready)
	body.add_child(_ready_btn)
	var back := button("BACK OUT", CREAM, 18, 60.0 - ShadowStyle.OFFSET)
	back.name = "Cancel"
	back.custom_minimum_size = Vector2(0, 60 + ShadowStyle.OFFSET)
	back.pressed.connect(func() -> void:
		cancelled.emit()
		slide_out(false, true))
	body.add_child(back)
	picked.emit(slots())   # the provisional pick: a timeout starts with it


## The opponent's card record from `matched`: the peer plus their tier.
func opponent_record() -> Dictionary:
	var peer: Dictionary = _info.get("peer", {}) if _info.get("peer") is Dictionary else {}
	var rec := peer.duplicate(true)
	var side := str(_info.get("side", "a"))
	var theirs := "b" if side == "a" else "a"
	var tiers: Dictionary = _info.get("tiers", {}) if _info.get("tiers") is Dictionary else {}
	if tiers.get(theirs) is Dictionary and not rec.has("rank"):
		var t: Dictionary = tiers[theirs]
		rec["rank"] = {"tier": str(t.get("tier", "rookie")), "division": int(t.get("division", 3)), "games": int(t.get("games", 1)),
			"wins": int(t.get("wins", 0)), "losses": int(t.get("losses", 0)), "position": int(t.get("position", 0))}
	var levels: Dictionary = _info.get("levels", {}) if _info.get("levels") is Dictionary else {}
	if levels.has(theirs):
		rec["level"] = int(levels[theirs])
	return rec


## Rebuild the strip from the bucket's cache (a tap, Net.cards_changed).
func refresh_cards() -> void:
	if _strip == null:
		return
	build_loadout_strip(_strip, bucket, cap, func() -> void:
		refresh_cards()
		picked.emit(slots()))


## The three slots as the room wants them (id or null).
func slots() -> Array:
	return App.loadout_slots(bucket)


func press_ready() -> void:
	if _ready_sent:
		return
	_ready_sent = true
	_ready_btn.text = MatchCopy.ready_word(true)
	_ready_btn.color = GOLD
	_ready_btn.queue_redraw()
	readied.emit(slots())


func is_ready() -> bool:
	return _ready_sent


func seconds_left() -> float:
	return _left


## The clock: _process drives it; tests call it. At zero the page readies
## itself with what it has.
func advance(dt: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(0.0, _left - dt)
	if _timer_label != null:
		_timer_label.text = MatchCopy.timer_line(_left)
	if _fill != null:
		_fill.anchor_right = clampf(_left / maxf(seconds, 0.01), 0.0, 1.0)
	if _left <= 0.0 and not _ready_sent:
		press_ready()


func _process(dt: float) -> void:
	advance(dt)


func cap_text() -> String:
	return (body.get_node("CapLine") as Label).text


func opp_name() -> String:
	return (_opp_card.find_child("Name", true, false) as Label).text


func opp_online_text() -> String:
	return (_opp_card.find_child("Online", true, false) as Label).text
