class_name PreMatchPage
extends FaceOffPage
## The pre-match page (design "Pre Match" 37a, 2026-10-23; docs/HOME.md →
## Pre-match pick): full screen before every match — a league heat and an
## online match alike — between PLAYER FOUND and the tip-off countdown. Card
## arming lives here; the league CARDS tab is the shop only.
##
## Top: who you face (name, town or league, three stats — league: RECORD ·
## SEED · AVG PTS; online: RANK · RATING · RECORD), THEIR LOADOUT filling live
## as they pick (the AI in a league, the other phone online), their chip
## flipping to READY. Middle: VS, or MATCH STARTS IN and the count once both
## are ready. Bottom: you — the same card, YOUR LOADOUT (three slots; tap a
## card to take it back), YOUR CARDS · HOLD + DRAG TO A SLOT (press and hold
## a card, drag it onto an open slot: open slots outline gold while you drag,
## the one under the card fills gold with ARM; let go to arm it, drop
## anywhere else and it snaps back; a plain tap arms it into the first open
## slot). READY locks the loadout; tap again to unlock while the other side
## is still deciding. Both ready → the count (data: prematch.countdown_s),
## then `go`: the match loads and its own 3-2-1 runs. A spare above the cap
## wears its level and refuses. The room's deadline (`seconds`) still
## readies the page silently at zero, so both phones agree.
##
## `build(info, bucket)` takes the room's `matched` (+ `side`) or a league
## info dict from App.league_pre_match_info (`league: true`, `league_stats`,
## `ai_hand`, `countdown_s`). Signals: `picked(slots)` on every change,
## `readied(slots)` / `unreadied(slots)` on READY, `go` at the count's end,
## `cancelled` on the back button.

signal picked(slots: Array)
signal readied(slots: Array)
signal unreadied(slots: Array)
signal go
signal cancelled

const HITCH_S := 0.25   # the most one frame may take off a clock
const PANEL_X := 6.0
const PANEL_W := 642.0
const OPP_TAB_Y := 163.0
const OPP_Y := 180.0
const OPP_H := 236.0
const VS_Y := 436.0
const VS_H := 110.0
const YOU_TAB_Y := 557.0
const YOU_Y := 574.0
const YOU_H := 440.0
const READY_Y := 1104.0
const READY_H := 116.0
const BACK_Y := 96.0
const OPP_SLOT := Vector2(66, 88)
const OWNED := Vector2(60, 80)
const DRAG_START_PX := 10.0
const SLOT_HIT_MARGIN := 14.0
const AI_PICK_TIMES := [1.0, 1.9, 2.7]
const AI_READY_AT := 3.6

var bucket := Net.ONLINE_BUCKET
var cap := 1
var seconds := 20.0
var _info: Dictionary = {}
var _left := 20.0
var _ready_sent := false
var _opp_slots: Array = ["", "", ""]
var _opp_ready := false
var _opp_name := "THEM"
var _counting := false
var _count_left := 0.0
var _count_total := 10.0
var _count_shown := -1
var _went := false
var _t := 0.0
# Nodes.
var _opp_slot_nodes: Array = []
var _opp_status: Label
var _opp_ready_chip: Control
var _vs_word: Label
var _vs_block: VBoxContainer
var _count_label: Label
var _you_slots: HBoxContainer
var _you_slot_nodes: Array = []
var _highlights: Array = []
var _load_count: Label
var _owned_row: HBoxContainer
var _owned_block: VBoxContainer
var _you_ready_chip: Control
var _ready_btn: ShadowCard
var _ready_top: Label
var _ready_sub: Label
var _ready_mark: Label
var _cap_label: Label
var _opp_name_l: Label
var _opp_town_l: Label
# The drag.
var _drag: Dictionary = {}
var _ghost: Control
var _hover := -1


## `info` is the room's `matched` ({peer, levels, tiers, stats, cap, seconds,
## countdown_s, side}) — or a league dict with `peer`, `cap`, `league: true`.
func build(info: Dictionary, p_bucket := "") -> Control:
	_info = info.duplicate(true)
	if p_bucket != "":
		bucket = p_bucket
	cap = maxi(1, int(info.get("cap", App.level())))
	seconds = float(info.get("seconds", RankedRules.prematch_cfg().get("seconds", 20)))
	_count_total = float(info.get("countdown_s", RankedRules.prematch_cfg().get("countdown_s", 10)))
	_left = seconds
	_ready_sent = false
	_opp_slots = ["", "", ""]
	_opp_ready = false
	_counting = false
	_went = false
	_t = 0.0
	var peer: Dictionary = info.get("peer", {}) if info.get("peer") is Dictionary else {}
	_opp_name = str(peer.get("name", "THEM"))
	if root == null:
		_ready()
	else:
		_build()
	return root


func _ready() -> void:
	if root != null:
		return
	super()


func is_league() -> bool:
	return bool(_info.get("league", false))


# ---- the build ---------------------------------------------------------------------------

func _build() -> void:
	for c in root.get_children():
		if c != body:
			root.remove_child(c)
			c.queue_free()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	body.visible = false
	_you_slot_nodes.clear()
	_opp_slot_nodes.clear()
	_highlights.clear()
	# BACK OUT, small, top-left.
	var back := button("<", CREAM, 24, 56.0 - ShadowStyle.OFFSET)
	back.name = "Cancel"
	back.position = Vector2(PANEL_X, BACK_Y)
	back.size = Vector2(56 + ShadowStyle.OFFSET, 56 + ShadowStyle.OFFSET)
	back.pressed.connect(func() -> void:
		cancelled.emit()
		slide_out(false, true))
	root.add_child(back)
	_build_opponent()
	_build_vs()
	_build_you()
	_build_ready()
	_refresh_ready()
	picked.emit(slots())   # the provisional pick: a timeout starts with it


## A tab word sitting on a panel's top edge.
func _tab(text: String, colour: Color, y: float) -> Control:
	var p := PanelContainer.new()
	p.name = text.capitalize().replace(" ", "") + "Tab"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2A2420")
	sb.border_color = colour
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(PANEL_X + 22, y)
	p.z_index = 2
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := words(text, 16, true)
	l.add_theme_color_override("font_color", colour)
	p.add_child(l)
	root.add_child(p)
	return p


## A panel's content column with the design's padding (36 under the tab, 22 sides and bottom).
func _panel(name_: String, colour: Color, y: float, h: float, tint: float) -> VBoxContainer:
	var panel := ShadowPanel.new(colour, 0.0, tint, 0.0)
	panel.name = name_
	panel.position = Vector2(PANEL_X, y)
	panel.size = Vector2(PANEL_W + ShadowStyle.OFFSET, h + ShadowStyle.OFFSET)
	root.add_child(panel)
	var m := MarginContainer.new()
	UiLayout.full_rect(m)
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_right", 22 + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_top", 36)
	m.add_theme_constant_override("margin_bottom", 22 + int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(m)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 18)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(col)
	return col


## Name + town on the left, three stats on the right.
func _who_row(name_: String, town: String, stats: Array, gold: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Who"
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 60)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := words(name_, 22, true)
	nm.name = "Name"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if gold:
		nm.add_theme_color_override("font_color", GOLD)
	left.add_child(nm)
	var tw := words(town, 16)
	tw.name = "Town"
	tw.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(tw)
	row.add_child(left)
	var right := HBoxContainer.new()
	right.name = "Stats"
	right.add_theme_constant_override("separation", 14)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for st in stats:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 10)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := words(str(st[0]), 16, true)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.name = "Stat_" + str(st[1]).replace(" ", "_")
		c.add_child(v)
		var l := words(str(st[1]), 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.add_child(l)
		right.add_child(c)
	row.add_child(right)
	return row


func _opp_record() -> Dictionary:
	return _info.get("peer", {}) if _info.get("peer") is Dictionary else {}


func _side() -> String:
	return str(_info.get("side", "a"))


func _theirs() -> String:
	return "b" if _side() == "a" else "a"


func _opp_stats() -> Array:
	if is_league():
		return Array(Dictionary(_info.get("league_stats", {})).get("opp", []))
	var stats: Dictionary = _info.get("stats", {}) if _info.get("stats") is Dictionary else {}
	var tiers: Dictionary = _info.get("tiers", {}) if _info.get("tiers") is Dictionary else {}
	return MatchCopy.online_stats(Dictionary(stats.get(_theirs(), {})), Dictionary(tiers.get(_theirs(), {})))


func _you_stats() -> Array:
	if is_league():
		return Array(Dictionary(_info.get("league_stats", {})).get("you", []))
	var stats: Dictionary = _info.get("stats", {}) if _info.get("stats") is Dictionary else {}
	var tiers: Dictionary = _info.get("tiers", {}) if _info.get("tiers") is Dictionary else {}
	var mine: Dictionary = Dictionary(stats.get(_side(), {}))
	if mine.is_empty() and not Net.me_rank.is_empty():
		mine = {"cons": Net.me_rank.get("cons", 0), "games": Net.me_rank.get("games", 0), "wins": Net.me_rank.get("wins", 0),
			"losses": Net.me_rank.get("losses", 0), "position": Net.me_rank.get("position", 0)}
	return MatchCopy.online_stats(mine, Dictionary(tiers.get(_side(), Net.me_rank)))


func _build_opponent() -> void:
	_tab(MatchCopy.prematch_tab_opp(), CREAM, OPP_TAB_Y)
	var col := _panel("OppPanel", CREAM, OPP_Y, OPP_H, 0.16)
	var rec := _opp_record()
	# Online the tag rides the town line (`SALT HARBOR · #07`) so the name keeps its room.
	var town := str(rec.get("place_text", "")) if is_league() else str(rec.get("town", "")).to_upper()
	var tag := MatchCopy.card_tag(rec) if not is_league() and str(rec.get("tag", "")) != "" else ""
	if tag != "":
		town = (town + " · " + tag) if town != "" else tag
	var who := _who_row(_opp_name, town, _opp_stats(), false)
	_opp_name_l = who.find_child("Name", true, false)
	_opp_town_l = who.find_child("Town", true, false)
	col.add_child(who)
	var row := HBoxContainer.new()
	row.name = "TheirLoadout"
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := words(MatchCopy.their_loadout(), 16)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.custom_minimum_size = Vector2(150, 0)
	row.add_child(lab)
	var slots_row := HBoxContainer.new()
	slots_row.name = "OppSlots"
	slots_row.add_theme_constant_override("separation", 16)
	slots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in CardDefs.SLOTS:
		var holder := Control.new()
		holder.name = "OppSlot%d" % i
		holder.custom_minimum_size = OPP_SLOT + Vector2.ONE * 4
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slots_row.add_child(holder)
		_opp_slot_nodes.push_back(holder)
	row.add_child(slots_row)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(push)
	_opp_ready_chip = _ready_chip()
	_opp_ready_chip.name = "OppReady"
	_opp_ready_chip.visible = false
	row.add_child(_opp_ready_chip)
	_opp_status = words(MatchCopy.opp_status(true), 16)
	_opp_status.name = "OppStatus"
	_opp_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_opp_status)
	col.add_child(row)
	_refresh_opp_slots()


## The gold READY chip (theirs and yours).
func _ready_chip() -> Control:
	var chip_ := ShadowPanel.new(GOLD, 0.0, 0.40, 14.0)
	chip_.custom_minimum_size = Vector2(0, 44 + ShadowStyle.OFFSET)
	chip_.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := words(MatchCopy.ready_word(false), 16, true)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_.add_child(l)
	return chip_


func _build_vs() -> void:
	var block := Control.new()
	block.name = "VsBlock"
	block.position = Vector2(0, VS_Y)
	block.size = Vector2(FRAME_SIZE.x, VS_H)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(block)
	var row := HBoxContainer.new()
	UiLayout.full_rect(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(row)
	var left := Rule.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	_vs_word = RetroTheme.display(MatchCopy.vs_word(), 40, GOLD)
	_vs_word.name = "VsWord"
	_vs_word.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	_vs_word.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	_vs_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vs_word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	RetroTheme.dithered(_vs_word, Vector2(5, 5))
	row.add_child(_vs_word)
	_vs_block = VBoxContainer.new()
	_vs_block.name = "Count"
	_vs_block.alignment = BoxContainer.ALIGNMENT_CENTER
	_vs_block.add_theme_constant_override("separation", 12)
	_vs_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vs_block.visible = false
	var si := words(MatchCopy.starts_in(), 16)
	si.name = "StartsIn"
	_vs_block.add_child(si)
	_count_label = RetroTheme.display("10", 64, GOLD)
	_count_label.name = "CountNumber"
	_count_label.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	_count_label.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.pivot_offset = Vector2(60, 40)
	_vs_block.add_child(_count_label)
	row.add_child(_vs_block)
	var right := Rule.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)


func _build_you() -> void:
	_tab(MatchCopy.prematch_tab_you(), GOLD, YOU_TAB_Y)
	var col := _panel("YouPanel", GOLD, YOU_Y, YOU_H, 0.20)
	var me := you_record()
	if _info.get("you") is Dictionary:
		me.merge(_info["you"], true)
	var who := _who_row(str(me.get("name", "YOU")), str(me.get("town", "")).to_upper(), _you_stats(), true)
	col.add_child(who)
	_cap_label = words(MatchCopy.cap_line(cap, is_league()), 14)
	_cap_label.name = "CapLine"
	_cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cap_label.add_theme_color_override("font_color", GOLD)
	col.add_child(_cap_label)
	# YOUR LOADOUT · n OF 3 · the slots · your READY chip.
	var row := HBoxContainer.new()
	row.name = "YourLoadout"
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var labcol := VBoxContainer.new()
	labcol.add_theme_constant_override("separation", 10)
	labcol.custom_minimum_size = Vector2(150, 0)
	labcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := words(MatchCopy.your_loadout(), 16)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	labcol.add_child(lab)
	_load_count = words(MatchCopy.load_count(0), 15)
	_load_count.name = "LoadoutLine"
	_load_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_load_count.add_theme_color_override("font_color", Color("#FFCE8A"))
	labcol.add_child(_load_count)
	row.add_child(labcol)
	_you_slots = HBoxContainer.new()
	_you_slots.name = "Slots"
	_you_slots.add_theme_constant_override("separation", 16)
	_you_slots.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_you_slots)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(push)
	_you_ready_chip = _ready_chip()
	_you_ready_chip.name = "YouReady"
	_you_ready_chip.visible = false
	row.add_child(_you_ready_chip)
	col.add_child(row)
	# YOUR CARDS · HOLD + DRAG TO A SLOT.
	_owned_block = VBoxContainer.new()
	_owned_block.name = "Yours"
	_owned_block.add_theme_constant_override("separation", 12)
	_owned_block.mouse_filter = Control.MOUSE_FILTER_PASS
	var yt := words(MatchCopy.your_cards_hint(), 16)
	yt.name = "YoursTitle"
	yt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_owned_block.add_child(yt)
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.color = Color(CREAM, 0.6)
	UiLayout.full_rect(line)
	rule.add_child(line)
	_owned_block.add_child(rule)
	_owned_row = HBoxContainer.new()
	_owned_row.name = "Spares"
	_owned_row.add_theme_constant_override("separation", 22)
	_owned_row.custom_minimum_size = Vector2(0, OWNED.y + 16)
	_owned_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_owned_block.add_child(_owned_row)
	col.add_child(_owned_block)
	refresh_cards()


func _build_ready() -> void:
	_ready_btn = ShadowCard.new(ORANGE)
	_ready_btn.name = "Ready"
	_ready_btn.position = Vector2(PANEL_X, READY_Y)
	_ready_btn.size = Vector2(PANEL_W + ShadowStyle.OFFSET, READY_H + ShadowStyle.OFFSET)
	root.add_child(_ready_btn)
	var m := MarginContainer.new()
	UiLayout.full_rect(m)
	m.add_theme_constant_override("margin_left", 30)
	m.add_theme_constant_override("margin_right", 30 + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_bottom", int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_btn.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_top = words("", 30, true)
	_ready_top.name = "ReadyTop"
	_ready_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_ready_top)
	_ready_sub = words("", 16)
	_ready_sub.name = "ReadySub"
	_ready_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ready_sub.clip_text = true
	_ready_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_ready_sub)
	row.add_child(col)
	_ready_mark = words(">", 30, true)
	_ready_mark.name = "ReadyMark"
	_ready_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ready_mark)
	_ready_btn.pressed.connect(press_ready)


# ---- the cards ------------------------------------------------------------------------------

## The three slots and YOUR CARDS from the bucket's cache (a change, Net.cards_changed).
func refresh_cards() -> void:
	if _you_slots == null:
		return
	for c in _you_slots.get_children():
		_you_slots.remove_child(c)
		c.queue_free()
	for c in _owned_row.get_children():
		_owned_row.remove_child(c)
		c.queue_free()
	_you_slot_nodes.clear()
	_highlights.clear()
	var cd := App.cards_bucket(bucket)
	var slots_: Array = App.loadout_slots(bucket)
	var inv: Dictionary = cd.get("inventory", {})
	var locked := _ready_sent
	var set_count := 0
	for i in CardDefs.SLOTS:
		var id: Variant = slots_[i] if i < slots_.size() else null
		var holder: Control
		if id != null:
			set_count += 1
			var card := CardDefs.get_card(str(id))
			holder = ModeCards.art(card, SLOT, 6.0, true)
			var slot_i := i
			(holder.get_meta("button") as TextureButton).pressed.connect(func() -> void:
				if _ready_sent or _counting:
					return
				App.unequip_card(slot_i, bucket)
				refresh_cards()
				picked.emit(slots()))
		else:
			holder = ModeCards.empty_slot(SLOT, 28, 2.0)
		holder.name = "Slot%d" % i
		# The drag's highlight: a gold frame with ARM, shown over the slot under the card.
		var hl := PanelContainer.new()
		hl.name = "Arm%d" % i
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(GOLD, 0.35)
		sb.border_color = GOLD
		sb.set_border_width_all(3)
		hl.add_theme_stylebox_override("panel", sb)
		hl.position = Vector2.ZERO
		hl.size = SLOT
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hl.visible = false
		var arm := words(MatchCopy.arm_word(), 14, true)
		arm.add_theme_color_override("font_color", GOLD)
		arm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hl.add_child(arm)
		holder.add_child(hl)
		_highlights.push_back(hl)
		_you_slots.add_child(holder)
		_you_slot_nodes.push_back(holder)
	_load_count.text = MatchCopy.load_count(set_count)
	# YOUR CARDS: every owned id (the cache's inventory is the spares), ×n, dimmed when none left or over the cap.
	var ids: Array = inv.keys()
	ids.sort()
	for id in ids:
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var left := int(inv[id])
		var holder := ModeCards.art(card, OWNED, 4.0, true)
		holder.name = "Spare_" + str(id)
		var cid := str(id)
		var allowed := left > 0 and App.can_equip(cid) and (cap < 0 or Progression.card_level(card) <= cap)
		if left <= 0:
			holder.modulate = Color(1, 1, 1, 0.35)
		elif not allowed:
			holder.modulate = Color(1, 1, 1, 0.45)
			var lock := PanelContainer.new()
			lock.name = "Lock_" + cid
			var lsb := StyleBoxFlat.new()
			lsb.bg_color = RetroTheme.SCENE_OUTLINE
			lsb.set_content_margin_all(4)
			lsb.content_margin_left = 6
			lsb.content_margin_right = 6
			lock.add_theme_stylebox_override("panel", lsb)
			lock.position = Vector2(2, OWNED.y - 24)
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock.add_child(UiFont.label("LVL %d" % Progression.card_level(card), 14, CREAM))
			holder.add_child(lock)
		var n := words("×%d" % left, 14, true)
		n.name = "Left"
		n.position = Vector2(OWNED.x - 16, OWNED.y - 10)
		n.z_index = 1
		holder.add_child(n)
		var btn := holder.get_meta("button") as TextureButton
		btn.gui_input.connect(_on_owned_input.bind(cid, holder, allowed))
		btn.pressed.connect(func() -> void:
			# A plain tap (no drag happened) arms it into the first open slot.
			if not _drag.is_empty() and bool(_drag.get("moved", false)):
				return
			_end_drag(false)
			_arm_first(cid, allowed))
		_owned_row.add_child(holder)
	_owned_block.modulate = Color(1, 1, 1, 0.45 if locked else 1.0)
	_refresh_ready()


func _arm_first(cid: String, allowed: bool) -> void:
	if not allowed or _ready_sent or _counting:
		return
	for slot in CardDefs.SLOTS:
		if App.loadout_slots(bucket)[slot] == null:
			if App.equip_card(slot, cid, bucket):
				refresh_cards()
				picked.emit(slots())
			return


## Press on an owned card starts a drag; the page's _input follows it.
func _on_owned_input(event: InputEvent, cid: String, holder: Control, allowed: bool) -> void:
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
	if not pressed or _ready_sent or _counting or not allowed:
		return
	_drag = {"id": cid, "from": root.get_local_mouse_position(), "moved": false, "holder": holder}


func _input(event: InputEvent) -> void:
	if _drag.is_empty() or root == null:
		return
	var motion: bool = event is InputEventMouseMotion or event is InputEventScreenDrag
	var release: bool = false
	if event is InputEventMouseButton:
		release = event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	elif event is InputEventScreenTouch:
		release = not event.pressed
	if motion:
		var at := root.get_local_mouse_position()
		if not bool(_drag["moved"]) and at.distance_to(_drag["from"]) >= DRAG_START_PX:
			_drag["moved"] = true
			_start_ghost()
		if bool(_drag["moved"]):
			_move_ghost(at)
	elif release and bool(_drag.get("moved", false)):
		var over := _hover
		var cid := str(_drag["id"])
		_end_drag(true)
		if over >= 0 and App.loadout_slots(bucket)[over] == null and App.equip_card(over, cid, bucket):
			refresh_cards()
			picked.emit(slots())
		get_viewport().set_input_as_handled()


func _start_ghost() -> void:
	var card := CardDefs.get_card(str(_drag["id"]))
	_ghost = ModeCards.art(card, SLOT, 8.0)
	_ghost.name = "Ghost"
	_ghost.z_index = 5
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.pivot_offset = SLOT / 2.0
	_ghost.rotation_degrees = -6.0
	_ghost.scale = Vector2(1.05, 1.05)
	root.add_child(_ghost)
	(_drag["holder"] as Control).modulate = Color(1, 1, 1, 0.5)
	_set_drag_frames(true)


func _move_ghost(at: Vector2) -> void:
	if _ghost == null:
		return
	_ghost.position = at - Vector2(SLOT.x / 2.0, SLOT.y * 0.62)
	var hover := -1
	var gp := root.get_global_mouse_position()
	for i in _you_slot_nodes.size():
		if App.loadout_slots(bucket)[i] != null:
			continue
		var h: Control = _you_slot_nodes[i]
		if Rect2(h.global_position, SLOT).grow(SLOT_HIT_MARGIN).has_point(gp):
			hover = i
	if hover != _hover:
		_hover = hover
		for i in _highlights.size():
			(_highlights[i] as Control).visible = i == hover
		_ghost.rotation_degrees = 0.0 if hover >= 0 else -6.0
		_ghost.scale = Vector2(0.95, 0.95) if hover >= 0 else Vector2(1.05, 1.05)


func _end_drag(_dropped: bool) -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if not _drag.is_empty() and is_instance_valid(_drag.get("holder")):
		(_drag["holder"] as Control).modulate = Color(1, 1, 1, 1.0)
	_drag = {}
	_hover = -1
	for hl in _highlights:
		if is_instance_valid(hl):
			(hl as Control).visible = false
	_set_drag_frames(false)


## While a card is in the air every open slot outlines gold.
func _set_drag_frames(on: bool) -> void:
	for i in _you_slot_nodes.size():
		if not is_instance_valid(_you_slot_nodes[i]) or App.loadout_slots(bucket)[i] != null:
			continue
		(_you_slot_nodes[i] as Control).modulate = Color(1.0, 0.85, 0.5) if on else Color.WHITE


## The three slots as the room wants them (id or null).
func slots() -> Array:
	return App.loadout_slots(bucket)


# ---- their side -------------------------------------------------------------------------------

## The other phone's validated pick as it stands (online, the room's peer_loadout).
func set_peer_loadout(p_slots: Array, ready: bool) -> void:
	var out := []
	for i in CardDefs.SLOTS:
		var s: Variant = p_slots[i] if i < p_slots.size() else ""
		out.push_back(str(s) if s != null else "")
	_opp_slots = out
	_opp_ready = ready
	_refresh_opp_slots()
	_refresh_ready()
	_maybe_count()


func _refresh_opp_slots() -> void:
	for i in _opp_slot_nodes.size():
		var holder: Control = _opp_slot_nodes[i]
		var id := str(_opp_slots[i]) if i < _opp_slots.size() else ""
		var had := str(holder.get_meta("id", "\u0001"))
		if had == id and holder.get_child_count() > 0:
			continue
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		holder.set_meta("id", id)
		var card := CardDefs.get_card(id) if id != "" else {}
		if card.is_empty():
			var e := ModeCards.empty_slot(OPP_SLOT, 20, 2.0)
			e.name = "Empty"
			e.modulate = Color(1, 1, 1, 0.6)
			holder.add_child(e)
		else:
			var art := ModeCards.art(card, OPP_SLOT, 4.0)
			art.name = "Card"
			art.pivot_offset = OPP_SLOT / 2.0
			holder.add_child(art)
			if is_inside_tree():
				# The drop: from above, a touch large, settling.
				art.position = Vector2(0, -18)
				art.scale = Vector2(1.15, 1.15)
				art.modulate.a = 0.0
				var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(art, "position", Vector2.ZERO, 0.3)
				tw.tween_property(art, "scale", Vector2.ONE, 0.3)
				tw.tween_property(art, "modulate:a", 1.0, 0.2)
	if _opp_ready_chip != null:
		_opp_ready_chip.visible = _opp_ready
		_opp_status.visible = not _opp_ready
		_opp_status.text = MatchCopy.opp_status(_opp_picking())


func _opp_picking() -> bool:
	if is_league():
		var hand: Array = _info.get("ai_hand", []) if _info.get("ai_hand") is Array else []
		return _opp_filled() < mini(hand.size(), CardDefs.SLOTS)
	return _opp_filled() == 0


func _opp_filled() -> int:
	var n := 0
	for s in _opp_slots:
		if str(s) != "":
			n += 1
	return n


func opp_slots() -> Array:
	return _opp_slots.duplicate()


func opp_ready() -> bool:
	return _opp_ready


# ---- READY and the count --------------------------------------------------------------------

func press_ready() -> void:
	if _counting or _went:
		return
	if _ready_sent:
		# Unlock while the other side is still deciding.
		if _opp_ready:
			return
		_ready_sent = false
		refresh_cards()
		unreadied.emit(slots())
		return
	_ready_sent = true
	_end_drag(false)
	refresh_cards()
	readied.emit(slots())
	_maybe_count()


func is_ready() -> bool:
	return _ready_sent


func seconds_left() -> float:
	return _left


## Both ready: a league counts on its own; online the room's `start` brings
## the count (start_countdown) — until it lands the button says READY.
func _maybe_count() -> void:
	if is_league() and _ready_sent and _opp_ready and not _counting:
		start_countdown(_count_total)


## The count to the tip-off (the room's `start.countdown_s` online).
func start_countdown(secs: float) -> void:
	if _counting or _went:
		return
	_counting = true
	_count_total = maxf(secs, 0.0)
	_count_left = _count_total
	_count_shown = -1
	_ready_sent = true
	_opp_ready = true
	_refresh_opp_slots()
	refresh_cards()
	_vs_word.visible = false
	_vs_block.visible = true
	_refresh_count()


func counting() -> bool:
	return _counting


func count_left() -> int:
	return ceili(_count_left)


func went() -> bool:
	return _went


func _refresh_count() -> void:
	var n := ceili(_count_left)
	if n != _count_shown:
		_count_shown = n
		_count_label.text = str(n) if n > 0 else MatchCopy.go_word()
		if is_inside_tree():
			_count_label.scale = Vector2(1.6, 1.6)
			_count_label.modulate.a = 0.0
			var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(_count_label, "scale", Vector2.ONE, 0.25)
			tw.tween_property(_count_label, "modulate:a", 1.0, 0.12)
	_refresh_ready()


func _refresh_ready() -> void:
	if _ready_btn == null:
		return
	var state := "pick"
	if _went:
		state = "go"
	elif _counting:
		state = "count"
	elif _ready_sent:
		state = "ready"
	var set_count := 0
	for s in slots():
		if s != null:
			set_count += 1
	var rb := MatchCopy.ready_button(state, set_count, _opp_name, ceili(_count_left))
	_ready_top.text = str(rb["top"])
	_ready_sub.text = str(rb["sub"])
	_ready_mark.text = str(rb["mark"])
	_ready_mark.visible = str(rb["mark"]) != ""
	_ready_btn.color = GOLD if bool(rb["gold"]) else ORANGE
	_ready_btn.disabled = _went or _counting
	_ready_btn.queue_redraw()
	if _you_ready_chip != null:
		_you_ready_chip.visible = _ready_sent


## The clocks: _process drives them; tests call it. The room's deadline
## readies the page silently at zero; the count ends in `go`.
func advance(dt: float) -> void:
	_t += dt
	if not _ready_sent and _left > 0.0:
		_left = maxf(0.0, _left - dt)
		if _left <= 0.0:
			press_ready()
	if is_league() and not _opp_ready:
		# The AI picks its cards one by one, then readies (design 37a's cadence).
		var hand: Array = _info.get("ai_hand", []) if _info.get("ai_hand") is Array else []
		var changed := false
		for i in mini(hand.size(), CardDefs.SLOTS):
			var at := float(AI_PICK_TIMES[i]) if i < AI_PICK_TIMES.size() else AI_READY_AT - 0.5
			if _t >= at and str(_opp_slots[i]) == "":
				_opp_slots[i] = str(hand[i])
				changed = true
		if _t >= AI_READY_AT:
			_opp_ready = true
			changed = true
		if changed:
			_refresh_opp_slots()
			_refresh_ready()
			_maybe_count()
	if _counting and not _went:
		_count_left = maxf(0.0, _count_left - dt)
		_refresh_count()
		if _count_left <= 0.0:
			_went = true
			_refresh_ready()
			go.emit()
	# Their status blinks while they decide.
	if _opp_status != null and _opp_status.visible:
		_opp_status.modulate.a = 0.55 if int(floor(_t * 2.0)) % 2 == 1 else 1.0


func _process(dt: float) -> void:
	advance(minf(dt, HITCH_S))


# ---- for tests and QA --------------------------------------------------------------------------

func cap_text() -> String:
	return _cap_label.text


func opp_name() -> String:
	return _opp_name_l.text


func opp_town_text() -> String:
	return _opp_town_l.text


## Their i-th stat's value, e.g. `#142` online or `6-2` in a league.
func opp_stat(i: int) -> String:
	var stats := _opp_stats()
	return str(stats[i][0]) if i < stats.size() else ""


func you_stat(i: int) -> String:
	var stats := _you_stats()
	return str(stats[i][0]) if i < stats.size() else ""


func ready_top() -> String:
	return _ready_top.text


func ready_sub() -> String:
	return _ready_sub.text
