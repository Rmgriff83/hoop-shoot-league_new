extends Node3D
## League post-match (design "League Post-Match", docs/HOME.md → Results):
## the heat's numbers over the LIVE court you just played on (the area's
## home pan under a half scrim), in the home's retro style. Top to bottom:
## `ARCADE LEAGUE · SEASON 2 · DAY 4`, the result big with the dithered
## shadow (YOU WIN in gold), the score with an OT chip when it went there,
## `VS NAME · "NICKNAME"`; the box score on a see-through panel with a YOU
## chip and the opponent's chip in their colour, the better number in gold;
## the rewards card (the tickets) beside the card drop; CONTINUE SEASON
## back to the home with the league open, and HOME. A heat outside a league
## (test-only) gets the header QUICK HEAT and only HOME. Copy from HeatCopy
## (pure); the heat from App.last_heat, the doc from App.league_doc.

const MARGIN := 36.0
const RIGHT := 720.0 - 42.0
const SCRIM_ALPHA := 0.5
## The layout (design "League Post-Match v2" 6b, 2026-10-25, 720 × 1280).
const HEAD_POS := Vector2(36, 48)
const SCORE_POS := Vector2(48, 192)
const SCORE_W := 390.0
const TICKETS_RECT := Rect2(720.0 - 42.0 - 240.0, 204.0, 240.0, 124.0)
const METER_Y := 372.0
const BOX_Y := 442.0
const BOX_W := 642.0
const BOX_HEAD_H := 54.0
const COL_W := 140.0
const ROW_H := 56.0          # a box score row
const ROW_H_BRIGHT := 50.0   # …when bright spots follow the rows
const BRIGHT_H := 32.0       # a bright-spot line
const DROP_GAP := 30.0
const DROP_H := 140.0
const ONLINE_CARD_H := 140.0 # the online rewards row (the meter sits under it)
const METER_H := 40.0        # the meter bar + line under the online rewards row
const BUTTONS_Y := 1124.0
const BUTTON_H := 120.0
const BUTTON_GAP := 26
const HOME_W := 170.0
const CONT_H := BUTTON_H     # REMATCH? / SHOOT AROUND? share the foot
const STREAM_START := 0.45
const HI := Color("#FFE45C")
const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")

var _t := 0.0
var _spec: Dictionary = {}
var _box: TicketBox
var _stream: TicketStream
var _meter: XpMeter
var _score_label: Label
var _court: CourtGeometry
var _cam: Camera3D


func _ready() -> void:
	var heat: Dictionary = App.last_heat
	_build_court(str(heat.get("location", "cage")), str(heat.get("mode", "heat")))
	var ui := CanvasLayer.new()
	ui.name = "Ui"
	ui.layer = 10
	add_child(ui)
	var league := HeatCopy.league_of(heat)
	var lid := str(league.get("id", ""))
	ui.add_child(build_chrome(heat, App.league_doc(lid) if lid != "" else {}, LeagueData.league(lid) if lid != "" else {}))
	_start_fx.call_deferred()


func _process(dt: float) -> void:
	_t += dt
	if _court != null:
		var p := TitlePan.pose(_spec, _t)
		_cam.position = p["pos"]
		_cam.look_at(p["look"])
		_court.step_rim(dt)


# ---- the court behind (the home page's recipe) -----------------------------------


func _build_court(location: String, mode: String) -> void:
	var arena := CosmeticLibrary.get_arena(location)
	if arena == null:
		arena = CosmeticLibrary.starter_arena()
	if not App.MODES.has(mode):
		mode = "heat"
	_cam = Camera3D.new()
	_cam.name = "Camera"
	add_child(_cam)
	_court = CourtGeometry.new()
	_court.name = "Court"
	_court.geo = App.geo_for_mode(mode)
	_court.arena_set = arena
	_court.hoop_set = App.hoop_for_mode(mode)
	_court.net_set = App.net_for_mode(mode)
	add_child(_court)
	_court.led.set_text("HOOP SHOOT", _court.led.accent_color)
	_spec = TitlePan.spec_of(arena)
	UiLayout.frame_camera(_cam, float(_spec["fov"]))
	var p := TitlePan.pose(_spec, 0.0)
	_cam.position = p["pos"]
	_cam.look_at(p["look"])


# ---- the chrome ------------------------------------------------------------------


## Everything over the court, as one Control (also built off-tree by tests).
func build_chrome(heat: Dictionary, doc: Dictionary, cfg: Dictionary) -> Control:
	var chrome := Control.new()
	chrome.name = "Chrome"
	UiLayout.full_rect(chrome)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(RetroTheme.SCENE_OUTLINE, SCRIM_ALPHA)
	UiLayout.full_screen_fill(scrim)   # past the band to the screen's edges
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(scrim)
	var in_league := not HeatCopy.league_of(heat).is_empty()
	var online := bool(heat.get("online", false))

	# The head: ★ SEASON 2 · DAY 4 over the league's name, dithered.
	var head := _vbox(16)
	head.name = "Head"
	head.position = HEAD_POS
	head.size = Vector2(720 - 2 * MARGIN, 0)
	chrome.add_child(head)
	var krow := _hbox(12)
	krow.name = "KickerRow"
	var star := PixelIcon.new("icon_star", Vector2(22, 22), 0.0)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	krow.add_child(star)
	var kicker := _text(HeatCopy.kicker(heat, doc), 18)
	kicker.name = "Kicker"
	krow.add_child(kicker)
	krow.visible = kicker.text != ""
	head.add_child(krow)
	var title := _text(HeatCopy.title(heat), 36, CREAM, true)
	title.name = "Title"
	RetroTheme.dithered(title)
	head.add_child(title)

	# The score block, left: the result, the score (+ OT), the opponent.
	var sb := _vbox(18)
	sb.name = "ScoreBlock"
	sb.position = SCORE_POS
	sb.size = Vector2(SCORE_W, 0)
	chrome.add_child(sb)
	var res := HeatCopy.result(heat)
	var rl := _text(str(res["text"]), int(res["size"]), GOLD if bool(res["gold"]) else CREAM, true)
	rl.name = "Result"
	RetroTheme.dithered(rl)
	sb.add_child(rl)
	var score_row := _hbox(14)
	score_row.name = "ScoreRow"
	sb.add_child(score_row)
	_score_label = _text(HeatCopy.score_line(heat), 60, CREAM, true)
	_score_label.name = "ScoreLine"
	RetroTheme.dithered(_score_label)
	score_row.add_child(_score_label)
	if HeatCopy.ot(heat):
		var chip := ShadowPanel.new(GOLD, 0.0, 0.40, 12.0)
		chip.name = "OT"
		chip.custom_minimum_size = Vector2(0, 40 + ShadowStyle.OFFSET)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ot := _text("OT", 16, CREAM, true)
		ot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(ot)
		score_row.add_child(chip)
	var vs := _text(HeatCopy.vs_line(heat), 18)
	vs.name = "Vs"
	vs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vs.custom_minimum_size = Vector2(SCORE_W, 0)
	sb.add_child(vs)
	if online:
		# The rank line (docs/BACKEND.md → Ranked): the rating change and the
		# badge once the room's decision lands; nothing for a casual match.
		var rank_l := _text(MatchCopy.rank_delta_line(heat), 18, GOLD, true)
		rank_l.name = "RankLine"
		rank_l.visible = rank_l.text != ""
		App.online_settled.connect(func(st: Dictionary) -> void:
			if is_instance_valid(rank_l):
				rank_l.text = MatchCopy.rank_delta_line(st)
				rank_l.visible = rank_l.text != ""
		, CONNECT_ONE_SHOT)
		sb.add_child(rank_l)

	# The tickets box, right, and the stream into it (TicketBox / TicketStream,
	# as the time-trial results page); the XP meter under both.
	if in_league:
		var ck := HeatCopy.rewards(heat)
		var tk := int(heat.get("tickets", 0))
		_box = TicketBox.new(TICKETS_RECT.size.y, 64.0, 30, 14, 20.0, 18.0, 64.0, 0.0, TICKETS_RECT.size.x)
		_box.position = TICKETS_RECT.position
		_box.set_count(tk)
		_box.set_sub(str(ck.get("sub", "TICKETS")))
		chrome.add_child(_box)
		var m := HeatCopy.level_meter(heat, App.xp())
		if not m.is_empty():
			_meter = XpMeter.new(m, BOX_W)
			_meter.position = Vector2(MARGIN, METER_Y)
			chrome.add_child(_meter)

	# The box score.
	var bright := HeatCopy.bright_lines(heat)
	var row_h := ROW_H_BRIGHT if not bright.is_empty() else ROW_H
	var box := ShadowPanel.new(CREAM, 12.0, 0.24, 26.0)
	box.name = "Box"
	box.position = Vector2(MARGIN, BOX_Y)
	var box_h := box_height(bright.size())
	box.size = Vector2(BOX_W + ShadowStyle.OFFSET, box_h + ShadowStyle.OFFSET)
	chrome.add_child(box)
	var bcol := _vbox(0)
	box.add_child(bcol)
	var bh := _hbox(0)
	bh.custom_minimum_size = Vector2(0, BOX_HEAD_H)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bh.add_child(spacer)
	var oc := HeatCopy.opponent_chip(heat)
	for spec in [["YOU", RetroTheme.c("orange"), 0.40, "YouChip"], [str(oc["text"]), oc["color"], 0.50, "ThemChip"]]:
		var cell := _hbox(0)
		cell.custom_minimum_size = Vector2(COL_W, 0)
		cell.alignment = BoxContainer.ALIGNMENT_END
		var chip := ShadowPanel.new(spec[1], 0.0, float(spec[2]), 12.0)
		chip.name = str(spec[3])
		chip.custom_minimum_size = Vector2(0, 38 + ShadowStyle.OFFSET)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var l := _text(str(spec[0]), 16, CREAM, true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(l)
		cell.add_child(chip)
		bh.add_child(cell)
	bcol.add_child(bh)
	for r in HeatCopy.box(heat):
		bcol.add_child(_box_row(r, row_h))
	# The bright spots of a loss (docs/CARDS.md § Drops), in gold under the rows.
	for line in bright:
		var bl := _text(str(line), 17, GOLD)
		bl.name = "Bright"
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bl.custom_minimum_size = Vector2(0, BRIGHT_H)
		bcol.add_child(bl)
	var below := BOX_Y + box_h + DROP_GAP

	# A card drop gets its own teal row under the box, the live card in it.
	if in_league:
		var card := HeatCopy.drop(heat)
		if not card.is_empty():
			var dp := ShadowPanel.new(RetroTheme.c("teal"), 0.0, 0.32, 24.0)
			dp.name = "Drop"
			dp.position = Vector2(MARGIN, below)
			dp.size = Vector2(BOX_W + ShadowStyle.OFFSET, DROP_H + ShadowStyle.OFFSET)
			var dr := _hbox(22)
			var art := ModeCards.art(card, Vector2(78, 104), 5.0)
			art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dr.add_child(art)
			var dc := _vbox(14)
			dc.alignment = BoxContainer.ALIGNMENT_CENTER
			dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cap_l := _text(HeatCopy.drop_caption(heat), 16)
			cap_l.name = "DropCaption"
			cap_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dc.add_child(cap_l)
			var nm := _text(str(card.get("name", "")).to_upper(), 22, CREAM, true)
			nm.name = "DropName"
			nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nm.add_theme_constant_override("line_spacing", 6)
			dc.add_child(nm)
			dr.add_child(dc)
			var plus := _text("+1 CARD", 16, HI)
			plus.name = "DropPlus"
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dr.add_child(plus)
			dp.add_child(dr)
			chrome.add_child(dp)

	# The foot: CONTINUE SEASON beside HOME (a league), REMATCH? / SHOOT
	# AROUND? beside HOME (an open online room), HOME alone otherwise.
	var foot := _hbox(BUTTON_GAP - int(ShadowStyle.OFFSET))
	foot.name = "Buttons"
	foot.position = Vector2(MARGIN, BUTTONS_Y)
	foot.size = Vector2(BOX_W + ShadowStyle.OFFSET, BUTTON_H + ShadowStyle.OFFSET)
	foot.alignment = BoxContainer.ALIGNMENT_END
	chrome.add_child(foot)
	if in_league:
		var cont := ShadowCard.new(RetroTheme.c("orange"))
		cont.name = "ContinueSeason"
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cont.custom_minimum_size = Vector2(0, BUTTON_H + ShadowStyle.OFFSET)
		var cm := _margin(0, 24)
		cont.add_child(cm)
		var crow := _hbox(16)
		cm.add_child(crow)
		var ccol := _vbox(14)
		ccol.alignment = BoxContainer.ALIGNMENT_CENTER
		ccol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ccol.add_child(_text("CONTINUE SEASON", 22, CREAM, true))
		var sub := _text(HeatCopy.continue_sub(doc, cfg), 15)
		sub.name = "ContinueSub"
		ccol.add_child(sub)
		crow.add_child(ccol)
		var ch := _text(">", 30, CREAM, true)
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crow.add_child(ch)
		cont.pressed.connect(App.to_league_hub)
		foot.add_child(cont)
	if online:
		# Stage B (docs/BACKEND.md → Ranked → Stage B): the tickets beside the
		# spoils / the granted card and the meter under them, between the box
		# and the foot; REMATCH? (and SHOOT AROUND?) in the foot. Filled now and
		# again when the room's decision lands.
		var rewards_box := Control.new()
		rewards_box.name = "OnlineRewards"
		rewards_box.position = Vector2(MARGIN, below)
		rewards_box.size = Vector2(BOX_W + ShadowStyle.OFFSET, ONLINE_CARD_H + ShadowStyle.OFFSET + METER_H)
		rewards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chrome.add_child(rewards_box)
		_fill_online_rewards(rewards_box, heat)
		var bottom := _hbox(BUTTON_GAP - int(ShadowStyle.OFFSET))
		bottom.name = "OnlineBottom"
		bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(bottom)
		_fill_online_bottom(bottom)
		App.online_settled.connect(func(_s: Dictionary) -> void:
			if is_instance_valid(rewards_box):
				_fill_online_rewards(rewards_box, App.last_heat)
			if is_instance_valid(bottom):
				_fill_online_bottom(bottom)
		, CONNECT_ONE_SHOT)
	var home := ShadowCard.new(CREAM)
	home.name = "Home"
	home.custom_minimum_size = Vector2(HOME_W + ShadowStyle.OFFSET, BUTTON_H + ShadowStyle.OFFSET)
	home.text = "HOME"
	home.add_theme_font_override("font", UiFont.display())
	home.add_theme_font_size_override("font_size", UiFont.snap(20))
	RetroTheme.on_scene(home)
	home.pressed.connect(App.to_title)
	foot.add_child(home)

	_stream = TicketStream.new()
	_stream.name = "Stream"
	_stream.tickets = int(heat.get("tickets", 0)) if in_league else 0
	chrome.add_child(_stream)
	return chrome


## The box score's height for `bright` bright-spot lines (the design's
## 12 + 54 + 6 rows + the lines + 16 + the borders).
static func box_height(bright: int) -> float:
	var rows := HeatCopy.ROWS.size()
	return 12.0 + BOX_HEAD_H + rows * (ROW_H_BRIGHT if bright > 0 else ROW_H) + bright * BRIGHT_H + 16.0 + 4.0


## The arrival (deferred: the layout must have settled): the tickets stream
## from the score into the box and count up, then the XP meter fills.
func _start_fx() -> void:
	var fill_at := STREAM_START
	if _box != null and _stream != null and _stream.tickets > 0:
		_box.set_count(0)
		var from := _score_label.get_global_rect().get_center() if _score_label != null else Vector2(160, 300)
		_stream.count_changed.connect(func(n: int) -> void:
			_box.set_count(n)
			_box.bump()
		)
		_stream.play(from, _box.icon_center(), _stream.tickets, STREAM_START)
		fill_at = STREAM_START + float(TicketStream.count(_stream.tickets)) * TicketStream.GAP + TicketStream.DUR
	if _meter != null:
		_meter.play(fill_at)


## The online rewards row (MatchCopy.spoils_panel / HeatCopy.rewards): the
## tickets, then what the decision did with cards; the meter line under.
func _fill_online_rewards(box: Control, heat: Dictionary) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.free()
	var ck := HeatCopy.rewards(heat)
	var sp := MatchCopy.spoils_panel(heat)
	var row := _hbox(26 - int(ShadowStyle.OFFSET))
	row.name = "Cards"
	row.position = Vector2.ZERO
	row.size = Vector2(box.size.x, ONLINE_CARD_H + ShadowStyle.OFFSET)
	box.add_child(row)
	# Two panels split the row evenly whatever their words measure; one alone takes it all.
	var half := (box.size.x - ShadowStyle.OFFSET - 21.0) / 2.0 if (not ck.is_empty() and not sp.is_empty()) else 0.0
	if not ck.is_empty():
		var rewards := ShadowPanel.new(GOLD, 0.0, 0.32, 22.0)
		rewards.name = "Rewards"
		rewards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rewards.custom_minimum_size = Vector2(half, ONLINE_CARD_H + ShadowStyle.OFFSET)
		var cr := _hbox(18)
		cr.alignment = BoxContainer.ALIGNMENT_BEGIN
		var ticket := PixelIcon.new("icon_ticket", Vector2(48, 32), 3.0)
		ticket.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cr.add_child(ticket)
		var cc := _vbox(12)
		cc.alignment = BoxContainer.ALIGNMENT_CENTER
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var big := _text(str(ck.get("big", "+0")), 32, CREAM, true)
		big.name = "RewardsBig"
		cc.add_child(big)
		var sub_l := _text(str(ck.get("sub", "")))
		sub_l.name = "RewardsSub"
		cc.add_child(sub_l)
		var close := MatchCopy.close_loss_line(heat)
		if close != "":
			var cl := _text(close, 14, GOLD, true)
			cl.name = "CloseLine"
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cl.custom_minimum_size = Vector2(maxf(half - 120.0, 160.0), 0)
			cc.add_child(cl)
		cr.add_child(cc)
		rewards.add_child(cr)
		row.add_child(rewards)
	if not sp.is_empty():
		var lost := bool(sp.get("lost", false))
		var dp := ShadowPanel.new(CREAM if lost else RetroTheme.c("teal"), 0.0, 0.32, 20.0)
		dp.name = "Spoils"
		dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dp.custom_minimum_size = Vector2(half, ONLINE_CARD_H + ShadowStyle.OFFSET)
		dp.clip_contents = true
		var dr := _hbox(18)
		var card := CardDefs.get_card(str(sp.get("card", "")))
		if not card.is_empty():
			var art := ModeCards.art(card, Vector2(84, 112), 4.0)
			art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if lost:
				art.modulate = Color(1, 1, 1, 0.55)
			dr.add_child(art)
		var dc := _vbox(12)
		dc.alignment = BoxContainer.ALIGNMENT_CENTER
		dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_l := _text(str(sp.get("caption", "")), 14, CREAM, true)
		cap_l.name = "SpoilsCaption"
		cap_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A wrapping label measured before its width is known reports a tower
		# of lines; a floor on its width keeps the row from growing to fit it.
		cap_l.custom_minimum_size = Vector2(170, 0)
		dc.add_child(cap_l)
		dr.add_child(dc)
		dp.add_child(dr)
		row.add_child(dp)
	row.visible = row.get_child_count() > 0
	# Filled in-tree (the decision landing after the page): the row keeps its height.
	row.set_deferred("size", Vector2(box.size.x, ONLINE_CARD_H + ShadowStyle.OFFSET))
	var ml := MatchCopy.meter_line(heat)
	if ml != "":
		var bar := Control.new()
		bar.name = "MeterBar"
		bar.position = Vector2(0, ONLINE_CARD_H + ShadowStyle.OFFSET + 4)
		bar.size = Vector2(box.size.x - ShadowStyle.OFFSET, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track := ColorRect.new()
		track.color = Color(RetroTheme.SCENE_OUTLINE, 0.55)
		UiLayout.full_rect(track)
		bar.add_child(track)
		var fill := ColorRect.new()
		fill.name = "MeterFill"
		fill.color = GOLD
		fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		fill.anchor_right = MatchCopy.meter_frac(heat)
		bar.add_child(fill)
		box.add_child(bar)
		var l := _text(ml, 14, GOLD, true)
		l.name = "MeterLine"
		l.position = Vector2(0, ONLINE_CARD_H + ShadowStyle.OFFSET + 14)
		l.size = Vector2(box.size.x, 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)


## The row at the foot while the room is open: REMATCH?, and beside it
## SHOOT AROUND? after a losing stretch (App.shoot_around_offered).
func _fill_online_bottom(bottom: HBoxContainer) -> void:
	for c in bottom.get_children():
		bottom.remove_child(c)
		c.free()
	if App.room == null:
		return
	bottom.add_child(_rematch_card())
	if App.shoot_around_offered():
		var sa := ShadowCard.new(RetroTheme.c("teal"))
		sa.name = "ShootAround"
		sa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sa.custom_minimum_size = Vector2(0, CONT_H + ShadowStyle.OFFSET)
		var sm := _margin(0, 20)
		sa.add_child(sm)
		var col := _vbox(14)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(_text(MatchCopy.shoot_around_title(), 20, CREAM, true))
		var sub := _text(MatchCopy.shoot_around_sub(int(OnlineDrops.shoot_around_cfg().get("bonus", 0))), 14)
		sub.name = "ShootAroundSub"
		col.add_child(sub)
		sm.add_child(col)
		sa.pressed.connect(App.start_shoot_around)
		bottom.add_child(sa)


## REMATCH? (docs/BACKEND.md → Phase 3, Rematch): only here, only while the
## room is still open. Orange to ask, gold when they asked (tap to accept),
## teal once both have, cream and dead when they left. Restyles on
## App.rematch_changed. Sized by the row that holds it.
func _rematch_card() -> Control:
	var card := ShadowCard.new(RetroTheme.c("orange"))
	card.name = "Rematch"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, CONT_H + ShadowStyle.OFFSET)
	var cm := _margin(0, 24)
	card.add_child(cm)
	var row := _hbox(16)
	cm.add_child(row)
	var col := _vbox(14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _text("", 24, CREAM, true)
	title.name = "RematchTitle"
	col.add_child(title)
	var sub := _text("")
	sub.name = "RematchSub"
	col.add_child(sub)
	row.add_child(col)
	var ch := _text(">", 32, CREAM, true)
	ch.name = "RematchChevron"
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ch)
	var style := func(state: String) -> void:
		if not is_instance_valid(card):
			return
		title.text = MatchCopy.rematch_title(state)
		sub.text = MatchCopy.rematch_sub(state)
		card.disabled = not MatchCopy.rematch_active(state)
		ch.visible = MatchCopy.rematch_active(state)
		match state:
			"wanted": card.color = RetroTheme.c("gold")
			"both": card.color = RetroTheme.c("teal")
			"gone": card.color = CREAM
			_: card.color = RetroTheme.c("orange")
		card.queue_redraw()
	style.call(App.rematch_state)
	App.rematch_changed.connect(style)
	card.tree_exited.connect(func() -> void:
		if App.rematch_changed.is_connected(style):
			App.rematch_changed.disconnect(style)
	)
	card.pressed.connect(App.offer_rematch)
	return card


## A box row: the label, then you / them in 150-px columns, the better in gold.
func _box_row(r: Dictionary, h := ROW_H) -> Control:
	var row := _hbox(0)
	row.name = "Row_" + str(r["l"]).replace(" ", "_")
	row.custom_minimum_size = Vector2(0, h)
	var l := _text(str(r["l"]), 19)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	for spec in [[str(r["a"]), r["hi"] == "a"], [str(r["b"]), r["hi"] == "b"]]:
		var c := _text(spec[0], 20, GOLD if bool(spec[1]) else CREAM, true)
		c.custom_minimum_size = Vector2(COL_W, 0)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(c)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, h)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := RowRule.new()
	wrap.add_child(rule)
	UiLayout.full_rect(row)
	wrap.add_child(row)
	return wrap


## The dashed rule along a box row's top (cream at 35 %, 2 px).
class RowRule extends Control:
	func _init() -> void:
		set_anchors_preset(Control.PRESET_TOP_WIDE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_dashed_line(Vector2(0, 1), Vector2(size.x, 1), Color(RetroTheme.SCENE_TEXT, 0.35), 2.0, 8.0)


# ---- helpers ---------------------------------------------------------------------


func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _margin(v: int, h: int) -> MarginContainer:
	var m := MarginContainer.new()
	UiLayout.full_rect(m)
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v + int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m
