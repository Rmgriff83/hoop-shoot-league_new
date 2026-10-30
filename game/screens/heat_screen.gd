extends "res://game/screens/time_trial_screen.gd"
## A league heat: the time-trial screen driving a Heat (two TimeTrials on one
## clock). The player's side is the main court exactly as in a trial; the
## opponent's side renders in a picture-in-picture court (its own world) in
## the top-right corner, with a minimize control. The HUD shows both scores
## and the ball-return wait; overtime periods roll on until decided.

const PIP_SIZE := Vector2i(216, 384)
## League heats use a smaller window (the dashboard's stats carry the story).
const PIP_SIZE_LEAGUE := Vector2i(168, 298)
## The opponent's window (design "League Match HUD"): under the top row at
## the right margin, framed in their shooter colour with a dithered shadow.
## The window's top (4a, 2026-10-30: 256 on the design's iPhone, under the
## 120-tall score box).
const PIP_Y := 157.0
const PIP_FRAME := 3.0
const AI_SFX_GAIN_DB := -9.0
## Card tray: three slots on the left edge, inside the UI zone (above the flick
## input's grab line at 45 % of the height) so a tap never becomes a shot.
const TRAY_POS := Vector2(36, 440)
const TRAY_CARD := Vector2(84, 112)

var heat: Heat
var _heat_cfg: Dictionary = {}
var _pip_layer: CanvasLayer
var _pip: SubViewportContainer
var _pip_vp: SubViewport
var _pip_min_btn: Button
var _pip_chip: Button
var _pip_chip_label: Label
var _pip_frame: PipFrame
var _pip_chrome: Control
var _opp_chips: HBoxContainer
var _opp_hand_n := -1
var _opp_color := LeagueContext.PINE
var _opp_short := "OPP"
var _ai_court: CourtGeometry
var _ai_pool: BallPool
var _ai_cam: Camera3D
var _ai_tier_shown := 1
var _ai_applied_geo: SimGeometry
## The league's standings / bracket cloth in the arena (league heats only).
var _banner: LeagueBanner
## Where the PiP sits: below the spot picker row on courts that have one.
var _pip_pos := Vector2(720 - 36 - 216 - PIP_FRAME, PIP_Y + PIP_FRAME)
var _pip_size := PIP_SIZE
## The opponent's window draws at half rate (docs/PERFORMANCE.md rule 9):
## every other frame its viewport is armed for one draw and its ball, rim,
## net and magnet step with the two frames' dt together. The sim (heat.tick)
## runs every frame as always.
const PIP_EVERY := 2
var _pip_tick := 0
var _pip_dt := 0.0
## The kit the PiP wears (docs/LOCKER.md → The kit): online, the other
## phone's resolved ball/net (and hoop in the cage); solo, the court's stock
## pair. Null sets fall back inside CosmeticLibrary.resolve_kit.
var _pip_kit: Dictionary = {}
var _tray: Array[TrayCard] = []
var _tray_ids: Array = []
var _empties: Array[Control] = []


func _make_rules() -> void:
	_heat_cfg = App.next_heat
	var ratings := AiRatings.from_dict(_heat_cfg.get("ai", {}))
	heat = Heat.new({
		"geo": base_geo,
		"seconds": float(_heat_cfg.get("seconds", Heat.DEFAULT_SECONDS)),
		"ot_seconds": float(_heat_cfg.get("ot_seconds", Heat.DEFAULT_OT_SECONDS)),
		"ball_return_s": float(_heat_cfg.get("ball_return_s", Heat.DEFAULT_BALL_RETURN_S)),
		"ai": ratings,
		"err_mult": float(_heat_cfg.get("err_mult", 1.0)),
		"seed": int(_heat_cfg.get("seed", 1)),
		"calib_key": str(_heat_cfg.get("calib_key", _mode.get("calib_key", "regulation"))),
		"player_cards": Array(_heat_cfg.get("player_cards", [])),
		"ai_cards": Array(_heat_cfg.get("ai_cards", [])),
		"board_motion": bool(_mode.get("board_motion", false)),
		"remote": bool(_heat_cfg.get("remote", false)),
		"player_bot": _heat_cfg.get("player_bot", null),   # QA only (--qa-perf): a bot on our side
	})
	trial = heat.player
	if heat.remote:
		_wire_online()


func _after_ready() -> void:
	var chip := HeatCopy.opponent_chip({"opponent": _heat_cfg.get("opponent", {})})
	_opp_color = chip["color"]
	_opp_short = str(chip["text"])
	_hud.set_heat(true, _opp_short, _opp_color)
	_lock_pause_online()
	var list := []
	for sp in _spots:
		var pos: Vector3 = sp["pos"]
		list.push_back({"x": float(pos.x), "y": float(pos.y), "z": float(pos.z)})
	heat.set_spots(list, _shuffle_enabled)
	if _heat_cfg.get("league", null) != null or heat.remote:
		lock_spot_picker()
	_build_pip()
	_build_tray()
	_build_toast()
	_build_league_banner()
	if _heat_cfg.get("prematch") is Dictionary:
		_open_prematch(Dictionary(_heat_cfg["prematch"]))


# ---- the pre-match pick (design "Pre Match" 37a, 2026-10-25) ---------------------------------
# The page opens over the loaded match — the camera on the hoop, the HUD
# behind it — and holds the rules (no clock, no countdown chip) until its
# count ends in GO; then the match's own 3-2-1 runs. A league heat takes the
# loadout picked here; an online one is re-made from the room's `start`
# (the seed, both hands, their kit), which lands while both are ready.

var _prematch: PreMatchPage
var _held := false


func _match_held() -> bool:
	return _held


func _defer_tutorial() -> bool:
	return _held


func _open_prematch(info: Dictionary) -> void:
	_held = true
	# The match's own UI (the HUD, the card tray, the opponent window, the
	# buttons) stays hidden until GO (Ross, 2026-10-26).
	_set_chrome_visible(false)
	var league := bool(info.get("league", false))
	_prematch = PreMatchPage.new()
	_prematch.name = "PreMatch"
	_prematch.build(info, str(info.get("bucket", "cage")) if league else Net.ONLINE_BUCKET)
	_prematch.go.connect(_prematch_go)
	if not league:
		_prematch.picked.connect(func(slots: Array) -> void: App.send_loadout(slots, false))
		_prematch.readied.connect(func(slots: Array) -> void: App.send_loadout(slots, true))
		_prematch.unreadied.connect(func(slots: Array) -> void: App.send_loadout(slots, false))
		var on_cards := func() -> void:
			if is_instance_valid(_prematch):
				_prematch.refresh_cards()
		Net.cards_changed.connect(on_cards)
		_prematch.tree_exited.connect(func() -> void:
			if Net.cards_changed.is_connected(on_cards):
				Net.cards_changed.disconnect(on_cards))
	add_child(_prematch)
	_prematch.fade_in()
	# Anything the room said while the scene was loading.
	for m in App.take_prematch_inbox():
		prematch_message(str(m[0]), m[1])


## The room's word for the page (App routes it here while it is up).
func prematch_message(kind: String, msg: Variant) -> void:
	match kind:
		"peer_loadout":
			if is_instance_valid(_prematch) and msg is Dictionary:
				_prematch.set_peer_loadout(Array(Dictionary(msg).get("slots", [])), bool(Dictionary(msg).get("ready", false)))
		"start":
			if msg is Dictionary:
				_restage(App.stage_online_start(Dictionary(msg)))
				if is_instance_valid(_prematch):
					_prematch.start_countdown(float(Dictionary(msg).get("countdown_s", 5)))
		"failed":
			# They left, the room expired, the socket died: back home.
			App.to_title()


func prematch_open() -> bool:
	return is_instance_valid(_prematch) and _held


func prematch_page() -> PreMatchPage:
	return _prematch if is_instance_valid(_prematch) else null


## GO: the loadout into the match (a league's, as picked; online the room's
## start already re-made it), the page fades, the match's countdown runs.
func _prematch_go() -> void:
	if _heat_cfg.get("league", null) != null:
		var bucket := _bucket()
		var hand: Array = App.loadout_hand(bucket)
		_heat_cfg["player_cards"] = hand.duplicate()
		_heat_cfg["player_slots"] = App.loadout_slots(bucket).duplicate()
		App.next_heat["player_cards"] = _heat_cfg["player_cards"]
		App.next_heat["player_slots"] = _heat_cfg["player_slots"]
		heat.hands[Heat.PLAYER] = hand.duplicate()
		_rebuild_tray()
	_held = false
	if is_instance_valid(_prematch):
		_prematch.fade_out_free()
	_prematch = null
	_set_chrome_visible(true)   # the match's UI comes up with its 3-2-1
	_maybe_tutorial()


## The online match as the room started it: the rules made again from the
## real config (the seed, both hands, their kit), and every piece that reads
## them rebuilt — the tray, the opponent window — behind the page.
func _restage(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	_heat_cfg = cfg
	_make_rules()
	trial.endless = false
	trial.board_motion = _mode["board_motion"]
	var list := []
	for sp in _spots:
		var pos: Vector3 = sp["pos"]
		list.push_back({"x": float(pos.x), "y": float(pos.y), "z": float(pos.z)})
	heat.set_spots(list, _shuffle_enabled)
	var chip := HeatCopy.opponent_chip({"opponent": _heat_cfg.get("opponent", {})})
	_opp_color = chip["color"]
	_opp_short = str(chip["text"])
	_hud.set_heat(true, _opp_short, _opp_color)
	_lock_pause_online()
	_rebuild_tray()
	if _pip_layer != null:
		_pip_layer.free()
		_pip_layer = null
	_ai_applied_geo = null
	_opp_hand_n = -1
	_build_pip()
	if _held:
		_set_chrome_visible(false)   # the rebuilt tray and window stay hidden behind the page


func _rebuild_tray() -> void:
	var layer := get_node_or_null("CardUi")
	if layer != null:
		remove_child(layer)
		layer.free()
	_tray.clear()
	_tray_ids = []
	_empties.clear()
	_fire_slot = -1
	_magnet_slot = -1
	_dealt_slot = -1
	_build_tray()


func _ai_id() -> String:
	return str(_heat_cfg.get("opponent", {}).get("id", ""))


# ---- online (docs/BACKEND.md → Phase 3) ------------------------------------------------------

var _online: Node = null
var _shot_n := 0
var _period_sent := -1
var _pending_card: Dictionary = {}


## Online the match never stops for one side (design 4a, 2026-10-30): the
## pause is dimmed with an orange slash and does nothing — the other phone's
## clock runs on.
func _lock_pause_online() -> void:
	if _pause_button != null:
		_pause_button.disabled = heat.remote


func pause_game() -> void:
	if heat != null and heat.remote:
		return
	super()


## The room client App opened: their messages drive heat's remote side; our
## releases, outcomes and buzzers go out as MatchProtocol messages.
func _wire_online() -> void:
	_online = App.room
	if _online == null:
		return
	if not _online.message.is_connected(_on_online_message):   # a restaged heat wires once
		_online.message.connect(_on_online_message)
		_online.closed.connect(_on_online_closed)
		if _online.has_signal("dropped"):   # a MatchClient; the QA fake peer has no line to lose
			_online.dropped.connect(_on_online_dropped)
			_online.restored.connect(_on_online_restored)


func _on_online_message(msg: Dictionary) -> void:
	if heat == null or not heat.remote:
		return
	match str(msg["t"]):
		MatchProtocol.SHOT:
			heat.remote_release(Dictionary(msg["launch"]))
		MatchProtocol.OUTCOME:
			heat.remote_outcome(int(msg["score"]))
			_hud.set_opponent_score(heat.score(Heat.AI))
		MatchProtocol.PERIOD_END:
			heat.remote_period_end(int(msg["period"]), int(msg["score"]), Dictionary(msg.get("totals", {})))
		MatchProtocol.CARD:
			heat.remote_card(str(msg["id"]))   # their play; the card_played event shows it
		MatchProtocol.CARD_OK:
			if not _pending_card.is_empty() and str(_pending_card["id"]) == str(msg["id"]):
				var slot := int(_pending_card["slot"])
				_pending_card = {}
				_deploy(slot, str(msg["id"]), true)   # receipted: the ledger has spent it
		MatchProtocol.ERROR:
			if str(msg.get("code", "")) == "card" and not _pending_card.is_empty():
				var slot := int(_pending_card["slot"])
				var id := str(_pending_card["id"])
				_pending_card = {}
				_restore_slot(slot, id)
				_court.info.flash("CARD REFUSED", 2, _court.info.accent_color)
		MatchProtocol.SETTLED:
			App.settled_online(msg)   # App hears it too; settled_online runs once
		MatchProtocol.PEER_LEFT:
			# Gone before their buzzer: a forfeit. Gone after reporting: they
			# are simply finished, and our own buzzer decides it.
			if not heat.done and not heat.remote_reported():
				_court.info.marquee("THEY LEFT", 24.0, _court.info.accent_color)
				heat.remote_forfeit()
		MatchProtocol.EXPIRED:
			# The room timed the match out (idle, or too long): it records a void.
			if not heat.done:
				_court.info.marquee("ROOM CLOSED", 24.0, _court.info.accent_color)
				heat.remote_lost()


## Our own line died and MatchClient could not get it back: the match ends
## here as a VOID — never a win on our own say-so (Ross, 2026-10-27: a phone
## that dropped while behind 15–30 was told it had won). The room decides
## what the match became; a forfeit in OUR favour only ever comes as its
## peer_left.
func _on_online_closed(_reason: String) -> void:
	_online = null
	if heat != null and heat.remote and not heat.done:
		_court.info.marquee("CONNECTION LOST", 24.0, _court.info.accent_color)
		heat.remote_lost()


## The line dropped mid-match; the client is opening the room again.
func _on_online_dropped() -> void:
	if heat != null and heat.remote and not heat.done:
		_court.info.marquee("RECONNECTING", 24.0, _court.info.accent_color)


func _on_online_restored() -> void:
	if heat != null and heat.remote and not heat.done:
		_court.info.flash("BACK ON", 2, _court.info.accent_color)


## Our buzzer went and the heat still has not decided REPORT_WAIT_S later —
## their report never reached us, or our replay of their last ball never
## scored: Heat.remote_timeout decides on the reports or voids it, so nobody
## stays on a court they cannot leave (Ross, 2026-10-27: the winner of a
## quick-match rematch stuck at the hoop). The room's peer_left (a forfeit
## win, after its 20 s grace) beats this wait when they really dropped.
const REPORT_WAIT_S := 30.0
var _report_wait := 0.0


func _watch_report(dt: float) -> void:
	if heat == null or not heat.remote or heat.done or heat.player.phase != TimeTrial.PHASE_DONE:
		_report_wait = 0.0
		return
	_report_wait += dt
	if _report_wait >= REPORT_WAIT_S:
		_report_wait = 0.0
		if not heat.remote_reported():
			_court.info.marquee("NO REPLY", 24.0, _court.info.accent_color)
		heat.remote_timeout()


func _online_send(msg: Dictionary) -> void:
	if _online != null and _online.has_method("send"):
		_online.send(msg)


## Our side's events, as the wire sees them.
func _online_player_event(ev: Dictionary) -> void:
	match ev["kind"]:
		"release":
			_shot_n += 1
			_online_send(MatchProtocol.shot(_shot_n, ev["launch"]))
		"outcome":
			_online_send(MatchProtocol.outcome(_shot_n, heat.player.score))
		"done":
			# The period the buzzer belonged to (stamped by Heat.tick; heat.ot may
			# already have rolled on when their report beat our buzzer).
			var period := int(ev.get("period", heat.ot))
			if _period_sent != period:
				_period_sent = period
				_online_send(MatchProtocol.period_end(period, heat.player.score, Heat.totals_of(heat.player)))


func online() -> bool:
	return heat != null and heat.remote


func _build_league_banner() -> void:
	if _heat_cfg.get("league", null) == null or _arena_set == null or _arena_set.league_banner_kind == "":
		return
	_banner = LeagueBanner.new()
	_banner.name = "LeagueBanner"
	_court.add_child(_banner)
	_banner.set_layout(_arena_set.league_banner_pos, _arena_set.league_banner_size,
		_arena_set.league_banner_yaw_deg, _arena_set.league_banner_lit)
	_banner.set_style(_arena_set.league_banner_style)
	if _arena_set.league_banner_kind == "label":
		_banner.show_label(_arena_set.league_banner_label)
		return
	var cfg := App.league_cfg(str(_heat_cfg["league"]["id"]))
	var doc := App.league_doc(str(_heat_cfg["league"]["id"]))
	if cfg.is_empty() or doc.is_empty():
		_banner.show_label(_arena_set.league_banner_label)
		return
	var season: Dictionary = doc["season"]
	var ids := LeagueData.team_ids(cfg)
	var names := {Campaign.PLAYER: "You"}
	for id in ids:
		if id != Campaign.PLAYER:
			names[id] = LeagueData.shooter(str(id)).get("name", id)
	if season["phase"] == Season.PHASE_REGULAR:
		var table := Standings.table(ids, season["schedule"], int(season["seed"]))
		var clinches := Standings.compute_clinches(ids, season["schedule"], int(season.get("playoffTeams", 4)))
		_banner.show_standings(str(cfg.get("name", "")), table, clinches, names, Campaign.PLAYER, int(season.get("playoffTeams", 4)))
	else:
		_banner.show_bracket(str(cfg.get("name", "")), season["series"], names, str(season.get("championId", "")), Season.days(season))


## The player's equipped cards, stacked up the left edge (slot 0 at the
## bottom) and centred on the tray column. A played card leaves the tray and
## the rest slide to re-centre; a burning fire card stays, lit, counting its
## window down, and leaves when the fire goes out. A card whose effect can't
## land yet (the opponent's rim is already iced, or their clock hasn't
## started) dims with a WAIT tag.
const TRAY_PITCH := TRAY_CARD.y + 8
## Vertical centre of the three-slot column (slot 0 at TRAY_POS, slot 2 two pitches up).
const TRAY_CENTRE_Y := TRAY_POS.y + TRAY_CARD.y * 0.5 - TRAY_PITCH
## The slot whose fire card is burning (its tag counts the window down).
var _fire_slot := -1
var _magnet_slot := -1
## The slot a card was just dealt from, and where it sat (the deal starts there).
var _dealt_slot := -1
var _dealt_from := Rect2(TRAY_POS, TRAY_CARD)
var _tray_tween: Tween


## A tray slot (design "League Match HUD"): the card's art on a TextureButton
## over a dithered ink shadow — pressing drops it onto the shadow — with a
## chip across its middle for WAIT (ink, the card dimmed) or the fire
## window's seconds (orange).
class TrayCard extends Control:
	var face: CardFace
	var button: TextureButton
	var tag: PanelContainer
	var tag_row: HBoxContainer
	var tag_glyph: PixelIcon
	var tag_label: Label
	var _sb: StyleBoxFlat
	var _pressed := false

	func _init(card: Dictionary, card_size: Vector2) -> void:
		size = card_size + Vector2.ONE * ShadowStyle.OFFSET
		custom_minimum_size = size
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		face = CardFace.new(card, card_size)
		face.name = "Art"
		add_child(face)
		# A textureless button over the face: the tap target, nothing drawn.
		button = TextureButton.new()
		button.name = "Button"
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		button.size = card_size
		button.focus_mode = Control.FOCUS_NONE
		button.button_down.connect(_press.bind(true))
		button.button_up.connect(_press.bind(false))
		add_child(button)
		tag = PanelContainer.new()
		tag.name = "Tag"
		_sb = StyleBoxFlat.new()
		_sb.set_border_width_all(2)
		_sb.set_content_margin_all(0)
		tag.add_theme_stylebox_override("panel", _sb)
		tag.position = Vector2(-6, 42)
		tag.size = Vector2(card_size.x + 12, 28)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.visible = false
		tag_row = HBoxContainer.new()
		tag_row.alignment = BoxContainer.ALIGNMENT_CENTER
		tag_row.add_theme_constant_override("separation", 6)
		tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(tag_row)
		# The fire window's flame glyph (design 8d: 14 px before `5S`).
		tag_glyph = PixelIcon.new("cards/glyph_fire", Vector2(14, 14))
		tag_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag_glyph.visible = false
		tag_row.add_child(tag_glyph)
		tag_label = RetroTheme.on_scene(UiFont.label("", 16, RetroTheme.SCENE_TEXT)) as Label
		tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag_row.add_child(tag_label)
		add_child(tag)

	func _press(down: bool) -> void:
		_pressed = down
		button.position = Vector2(4, 4) if down else Vector2.ZERO
		face.position = button.position
		tag.position = Vector2(-6 + (4 if down else 0), 42 + (4 if down else 0))
		queue_redraw()

	## "wait" (WAIT, dimmed), "fire" / "magnet" (the seconds left, with the
	## card's glyph) or "" (ready).
	func set_state(kind: String, text: String) -> void:
		tag.visible = kind != ""
		tag_label.text = text
		tag_glyph.visible = kind == "fire" or kind == "magnet"
		if kind == "magnet":
			tag_glyph.icon_name = "cards/glyph_magnet"
			tag_glyph.queue_redraw()
			_sb.bg_color = Color(Color("#4A1410"), 0.9)
			_sb.border_color = Color("#D0443A")
			face.modulate = Color.WHITE
		elif kind == "fire":
			tag_glyph.icon_name = "cards/glyph_fire"
			tag_glyph.queue_redraw()
		if kind == "wait":
			_sb.bg_color = Color(RetroTheme.SCENE_OUTLINE, 0.9)
			_sb.border_color = RetroTheme.SCENE_TEXT
			face.modulate = Color(1, 1, 1, 0.7)
		elif kind == "fire":
			_sb.bg_color = Color(RetroTheme.LIGHT["orange"], 0.95)
			_sb.border_color = RetroTheme.LIGHT["orange"]
			face.modulate = Color.WHITE
		else:
			face.modulate = Color.WHITE

	func _draw() -> void:
		if _pressed:
			return
		var w := size.x - ShadowStyle.OFFSET
		var h := size.y - ShadowStyle.OFFSET
		var sh := Color(RetroTheme.SCENE_OUTLINE, ShadowStyle.SHADOW_ALPHA)
		var tex := ShadowStyle.dither_tex()
		draw_texture_rect(tex, Rect2(Vector2(w, ShadowStyle.OFFSET), Vector2(ShadowStyle.OFFSET, h)), true, sh)
		draw_texture_rect(tex, Rect2(Vector2(ShadowStyle.OFFSET, h), Vector2(w - ShadowStyle.OFFSET, ShadowStyle.OFFSET)), true, sh)


func _build_tray() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CardUi"
	layer.layer = 11
	UiLayout.anchor_layer(layer)   # pinned to the real screen with the HUD (UiLayout.hud_y)
	add_child(layer)
	var slots: Array = _heat_cfg.get("player_slots", [])
	if slots.is_empty():
		# No slot layout in the config (older callers): lay the hand out in order.
		slots = [null, null, null]
		var hand: Array = heat.hands[Heat.PLAYER]
		for i in mini(hand.size(), CardDefs.SLOTS):
			slots[i] = hand[i]
	_tray_ids = []
	for i in CardDefs.SLOTS:
		var id := "" if i >= slots.size() or slots[i] == null else str(slots[i])
		_tray_ids.push_back(id)
		var card := CardDefs.get_card(id) if id != "" else {}
		var tc := TrayCard.new(card, TRAY_CARD)
		tc.name = "Card%d" % i
		tc.visible = id != ""
		tc.button.pressed.connect(_on_card_tapped.bind(i))
		layer.add_child(tc)
		_tray.push_back(tc)
	# Dashed empty slots (design 4a): one per slot without a card, stacked
	# above the cards; a played card leaves one behind.
	for i in CardDefs.SLOTS:
		var e := ModeCards.Dashed.new(TRAY_CARD, 2.0, 0.0)
		e.name = "Empty%d" % i
		e.visible = false
		layer.add_child(e)
		_empties.push_back(e)
	_layout_tray(false)


## Slots that still hold a card, lowest slot first.
func _tray_shown() -> Array[int]:
	var out: Array[int] = []
	for i in _tray.size():
		if _tray[i].visible:
			out.push_back(i)
	return out


## The tray column's slot positions, lowest slot first: the full stack of
## `slots` cards centred on TRAY_CENTRE_Y (the design's slotTop), cards in
## the first `n_cards` slots and dashed empties above them.
static func tray_layout(slots: int, centre_y := TRAY_CENTRE_Y, card_h := TRAY_CARD.y, pitch := TRAY_PITCH, x := TRAY_POS.x) -> Array:
	var total := slots * card_h + (slots - 1) * (pitch - card_h)
	var top := centre_y - total * 0.5
	var out := []
	for k in slots:
		out.push_back(Vector2(x, top + (slots - 1 - k) * pitch))
	return out


## Stack the remaining cards from the bottom slot up (slide when animate) and
## park a dashed empty in every slot above them.
func _layout_tray(animate: bool) -> void:
	var shown := _tray_shown()
	var n := shown.size()
	var spots := tray_layout(CardDefs.SLOTS, UiLayout.hud_y(TRAY_CENTRE_Y))
	if _tray_tween != null:
		_tray_tween.kill()
	_tray_tween = create_tween().set_parallel(true) if animate else null
	for k in n:
		var i: int = shown[k]
		var pos: Vector2 = spots[k]
		if animate:
			_tray_tween.tween_property(_tray[i], "position", pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_tray[i].position = pos
	for k in _empties.size():
		var slot := n + k
		_empties[k].visible = slot < CardDefs.SLOTS
		if slot < CardDefs.SLOTS:
			_empties[k].position = spots[slot]


## Positions of the cards still in the tray, lowest slot first (for probes).
func tray_positions() -> Array:
	var out := []
	for i in _tray_shown():
		out.push_back(_tray[i].position)
	return out


## Take a card out of the tray and re-centre the rest.
func _remove_from_tray(i: int) -> void:
	if i < 0 or i >= _tray.size() or not _tray[i].visible:
		return
	_tray[i].visible = false
	_layout_tray(true)


## Slot states for tests/probes: "empty", "ready", "wait" or "used" per slot.
func tray_states() -> Array:
	var out := []
	for i in _tray.size():
		if _tray_ids[i] == "":
			out.push_back("empty")
		elif _tray_ids[i] == "used":
			if i == _fire_slot and heat.player.fire_card:
				out.push_back("fire")
			elif i == _magnet_slot and heat.player.magnet_card:
				out.push_back("magnet")
			else:
				out.push_back("used")
		elif not Progression.can_use(App.level(), CardDefs.get_card(_tray_ids[i])):
			out.push_back("locked")
		elif heat.can_play(Heat.PLAYER, _tray_ids[i]):
			out.push_back("ready")
		else:
			out.push_back("wait")
	return out


func _on_card_tapped(i: int) -> void:
	if i >= _tray_ids.size():
		return
	var id: String = _tray_ids[i]
	if id == "" or id == "used" or not heat.can_play(Heat.PLAYER, id):
		return
	if not Progression.can_use(App.level(), CardDefs.get_card(id)):
		return   # owned early: playable once the level is reached (docs/PROGRESSION.md)
	# One-time use: the slot leaves the loadout first; a card the save no longer
	# holds (played from another device, say) is not deployed.
	if not App.consume_slot(i, id, _bucket()):
		_tray_ids[i] = "used"
		return
	if heat.remote:
		# Online the room owns the ledger: the card goes out, the slot waits
		# for the receipt (card_ok → deploy; error → the slot comes back).
		_pending_card = {"slot": i, "id": id}
		_tray_ids[i] = "used"
		_tray[i].set_state("wait", "...")
		_online_send(MatchProtocol.card(id))
		return
	_deploy(i, id)


## The card leaves the tray and takes effect (or comes back if the effect
## refused). `receipted` (online, after the room's card_ok): the ledger has
## already spent the copy, so a refusal here never puts it back — the slot
## stays used and the LED says so (Ross, 2026-10-26: a played card must
## never return to the player who played it).
func _deploy(i: int, id: String, receipted := false) -> void:
	_dealt_slot = i
	_dealt_from = Rect2(_tray[i].position, TRAY_CARD)
	if heat.play_card(Heat.PLAYER, id):
		_tray_ids[i] = "used"
		var kind := str(CardDefs.get_card(id).get("effect", {}).get("kind", ""))
		if kind == "fire":
			_fire_slot = i   # stays in the tray while it burns
		elif kind == "magnet":
			_magnet_slot = i   # stays in the tray while it hangs over the rim
		else:
			_remove_from_tray(i)
	elif receipted:
		_tray_ids[i] = "used"
		_remove_from_tray(i)
		_court.info.flash("CARD SPENT", 2, _court.info.accent_color)
		print("HeatScreen: %s refused after the room's receipt: spent, not restored" % id)
	else:
		_restore_slot(i, id)


## The copy back in its slot (the effect refused, or the room did).
func _restore_slot(i: int, id: String) -> void:
	print("HeatScreen: restoring %s to slot %d of the %s bucket" % [id, i, _bucket()])
	var d := App.cards_doc()
	var b := CardDefs.league_doc(d, _bucket())
	CardDefs.add(b, id)
	CardDefs.equip(b, i, id)
	SaveService.put_cards(d)
	_tray_ids[i] = id
	_tray[i].set_state("", "")


## Whose cards these are: the league's bucket, or `online` for a room.
## The pause menu's words for a match: the league (or ONLINE / RANKED), the
## overtime, the time left, the score; quitting a league match leaves it
## unplayed, quitting online forfeits it.
func _pause_info() -> Dictionary:
	var parts := []
	var kind := "league"
	var league = _heat_cfg.get("league")
	if heat.remote:
		kind = "online"
		parts.push_back("RANKED" if bool(_heat_cfg.get("ranked", false)) else "ONLINE")
	elif league is Dictionary and not (league as Dictionary).is_empty():
		var lid := str(league.get("id", ""))
		parts.push_back(str(App.league_cfg(lid).get("name", "LEAGUE")).to_upper() if lid != "" else "LEAGUE")
	else:
		parts.push_back("MATCH")
	var opp_first := str(Dictionary(_heat_cfg.get("opponent", {})).get("name", "")).to_upper()
	if opp_first.find(" ") > 0:
		opp_first = opp_first.substr(0, opp_first.find(" "))
	var game := str(league.get("game", "")) if league is Dictionary else ""
	return {"context": HudCopy.pause_context_match(str(parts[0]), game, opp_first, heat.ot),
		"stats": HudCopy.pause_stats_match(heat.player.score, heat.score(Heat.AI), opp_first, heat.player.time_left),
		"quit_note": HudCopy.pause_quit_note(kind)}


func _bucket() -> String:
	return str(_heat_cfg.get("bucket", App.current_league if App.current_league != "" else "cage"))


func _refresh_tray() -> void:
	var states := tray_states()
	for i in _tray.size():
		var st: String = states[i]
		match st:
			"fire":
				_tray[i].set_state("fire", "%dS" % ceili(heat.player.fire_left()))
			"magnet":
				_tray[i].set_state("magnet", "%dS" % ceili(heat.player.magnet_left()))
			"used":
				_remove_from_tray(i)   # a fire card whose window just closed
			"wait":
				_tray[i].set_state("wait", "WAIT")
			"locked":
				_tray[i].set_state("wait", "LVL %d" % Progression.card_level(CardDefs.get_card(_tray_ids[i])))
			_:
				_tray[i].set_state("", "")


## Overtime break (design "League Match HUD"): a dim over the court, the tie,
## OVERTIME big with the dithered shadow, the period's note — while the heat
## holds (Heat.OT_BREAK_S), before the countdown. Touches pass through
## (nothing is pickable during the break), so the pause button still works.


## A centred label over the court (the PiP chrome, the deal caption).
func _ot_text(text: String, size_: int, color := RetroTheme.SCENE_TEXT, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## The overtime break (design 4a): the gold OVERTIME · 20S toast with the
## stopwatch, up for the break — no dim, no TIED line (the boards marquee it).
func _show_ot_break(n: int) -> void:
	var copy := HudCopy.ot_toast(n, int(round(heat.ot_seconds)))
	_hud.toast(str(copy["title"]), str(copy["sub"]), "icon_stopwatch", Hud.GOLD)
	Sfx.score_pop(true)


func _hide_ot_break() -> void:
	_hud.hide_toast()


func ot_break_shown() -> bool:
	return _hud.toast_shown()


## Card play "deal": the card slides out of its tray slot, grows to the middle
## of the screen over a dithered ink shadow, then flies to whoever it acts
## on — your own hoop for a self card, the opponent's window (or its
## minimized chip) for a card played against them. The opponent's plays run
## the same path from the window. The caption is the HUD's card toast
## (design 4a, 2026-10-24): the card's thumb, DEEP FREEZE over PLAYED ON
## OLLIE, the target badge — blue for your plays, orange for theirs.
const DEAL_BIG := Vector2(168, 224)
const DEAL_SMALL := Vector2(26, 34)
const DEAL_CENTRE := Vector2(360, 502)
const DEAL_OUT_S := 0.35
const DEAL_HOLD_S := 0.55
const DEAL_FLY_S := 0.4

var _deal: DealCard
var _deal_tween: Tween


## The dealt card: its animated face over a dithered ink shadow that follows the fly.
class DealCard extends Control:
	var face: CardFace

	func _init() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		face = CardFace.new({}, Vector2.ZERO)
		face.name = "Art"
		UiLayout.full_rect(face)
		add_child(face)

	func _draw() -> void:
		var o := ShadowStyle.OFFSET * clampf(size.x / DEAL_BIG.x, 0.3, 1.0)
		var sh := Color(RetroTheme.SCENE_OUTLINE, ShadowStyle.SHADOW_ALPHA)
		var tex := ShadowStyle.dither_tex()
		draw_texture_rect(tex, Rect2(Vector2(size.x, o), Vector2(o, size.y)), true, sh)
		draw_texture_rect(tex, Rect2(Vector2(o, size.y), Vector2(size.x - o, o)), true, sh)


func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ToastUi"
	layer.layer = 12
	UiLayout.anchor_layer(layer)   # the deal flies between anchored layers: screen px
	add_child(layer)
	_deal = DealCard.new()
	_deal.name = "Deal"
	_deal.visible = false
	layer.add_child(_deal)


## LED line for the side that did NOT play a card: `against_me` when the card
## hit that side ("ICED BY CARD"), else the other shooter boosted themselves
## ("OPP HEAT CHECK").
static func _card_marquee(card_id: String, against_me: bool) -> String:
	var card := CardDefs.get_card(card_id)
	var kind := str(card.get("effect", {}).get("kind", ""))
	if against_me:
		return "ICED BY CARD" if kind == "ice" else "%s BY CARD" % str(card.get("name", card_id)).to_upper()
	return "OPP %s" % str(card.get("name", card_id)).to_upper()


## Screen point of the player's hoop (where their card on you flies to) — raw
## screen px: the deal layer is anchored.
func _hoop_point() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _court == null or not _court.rim_pivot.is_inside_tree():
		return UiLayout.to_screen(Vector2(360, 560))
	return cam.unproject_position(_court.rim_pivot.global_position)


## Screen point of the opponent's window (the PiP, or its chip when minimized).
func _pip_point() -> Vector2:
	if _pip != null and _pip.visible:
		return _pip_pos + Vector2(_pip_size) * 0.5
	if _pip_chip != null:
		return _pip_chip.position + _pip_chip.size * 0.5
	return UiLayout.hud_pos(Vector2(640, 100))


func _show_card_play(card_id: String, by_ai: bool, target: String) -> void:
	var card := CardDefs.get_card(card_id)
	var cname: String = str(card.get("name", card_id))
	var on_you := target == Heat.PLAYER
	var from: Rect2 = Rect2(_pip_point() - DEAL_SMALL * 0.5, DEAL_SMALL) if by_ai else _dealt_from
	# Every card YOU play ends in the opponent's window — the self cards too
	# (Ross, 2026-10-30: never into your own view of the hoop); theirs still
	# fly to whom they target.
	var to: Vector2 = _hoop_point() if by_ai and on_you else _pip_point()
	var copy := HudCopy.deal_toast(cname, on_you, _opp_short)
	_hud.card_toast(str(copy["title"]), str(copy["sub"]), card, str(copy["target"]), RetroTheme.LIGHT["orange"] if by_ai else LeagueContext.BLUE)
	_deal_card(card, from, to)


func _deal_card(card: Dictionary, from: Rect2, to: Vector2) -> void:
	if _deal_tween != null:
		_deal_tween.kill()
	_deal.face.set_card(card)
	_deal.position = from.position
	_deal.size = from.size
	_deal.modulate = Color.WHITE
	_deal.visible = true
	Sfx.score_pop(true)
	_deal_tween = create_tween()
	_deal_tween.set_parallel(true)
	# Out of the slot and up to size in the middle.
	_deal_tween.tween_property(_deal, "position", UiLayout.to_screen(DEAL_CENTRE) - DEAL_BIG * 0.5, DEAL_OUT_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_deal_tween.tween_property(_deal, "size", DEAL_BIG, DEAL_OUT_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Hold, then fly to the target while shrinking and fading.
	_deal_tween.chain().tween_interval(DEAL_HOLD_S)
	_deal_tween.chain().tween_property(_deal, "position", to - DEAL_SMALL * 0.5, DEAL_FLY_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_deal_tween.tween_property(_deal, "size", DEAL_SMALL, DEAL_FLY_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_deal_tween.tween_property(_deal, "modulate:a", 0.0, DEAL_FLY_S * 0.6).set_delay(DEAL_FLY_S * 0.4)
	_deal_tween.chain().tween_callback(_hide_deal)


func _hide_deal() -> void:
	_deal.visible = false


## Where the deal is right now (for probes): null when idle.
func deal_rect() -> Variant:
	if _deal == null or not _deal.visible:
		return null
	return Rect2(_deal.position, _deal.size)


## The opponent's window (design "League Match HUD"): their court in its own
## 3D world, rendered small in a frame of their shooter colour with a
## dithered shadow, OPP at its top-left, a minimize button top-right and
## their loadout hanging off the bottom as chips. Minimized it is a chip in
## their colour with their score and a restore glyph.
func _build_pip() -> void:
	_pip_layer = CanvasLayer.new()
	_pip_layer.name = "PipUi"
	_pip_layer.layer = 11
	UiLayout.anchor_layer(_pip_layer)
	add_child(_pip_layer)

	if _heat_cfg.get("league", null) != null:
		_pip_size = PIP_SIZE_LEAGUE
	var frame_size := Vector2(_pip_size) + Vector2.ONE * 2.0 * PIP_FRAME
	var frame_pos := Vector2(720 - 36 - frame_size.x, UiLayout.hud_y(PIP_Y))
	if _spots.size() > 1 and _picker_free:
		frame_pos += Vector2(0, 56)   # clear of the picker row when it is shown
	_pip_pos = frame_pos + Vector2.ONE * PIP_FRAME
	_pip_frame = PipFrame.new(_opp_color)
	_pip_frame.name = "PipFrame"
	_pip_frame.position = frame_pos
	_pip_frame.size = frame_size + Vector2.ONE * ShadowStyle.OFFSET
	_pip_layer.add_child(_pip_frame)
	_pip = SubViewportContainer.new()
	_pip.name = "Pip"
	_pip.position = _pip_pos
	_pip.size = Vector2(_pip_size)
	_pip.stretch = true
	_pip.mouse_filter = Control.MOUSE_FILTER_STOP
	_pip_layer.add_child(_pip)
	_pip_vp = SubViewport.new()
	_pip_vp.name = "PipViewport"
	_pip_vp.size = _pip_size
	_pip_vp.own_world_3d = true
	_pip_vp.render_target_update_mode = SubViewport.UPDATE_ONCE   # then every other frame (_process)
	_pip_vp.transparent_bg = false
	_pip.add_child(_pip_vp)

	_ai_court = CourtGeometry.new()
	_ai_court.name = "OpponentCourt"
	_ai_court.profile = CourtGeometry.Profile.PIP   # no shadows, frozen area fx (docs/PERFORMANCE.md rule 9)
	Sfx.rim_rigidity = base_geo.rim_rigidity()
	_ai_court.geo = base_geo
	_ai_court.arena_set = _arena_set
	_pip_kit = pip_kit(_heat_cfg, _hoop_set, str(App.mode_config(App.next_mode).get("hoop", "")) != "")
	_ai_court.hoop_set = _pip_kit["hoop"] if _pip_kit["hoop"] != null else _hoop_set
	_ai_court.net_set = _pip_kit["net"]
	_ai_court.pop_scale = 2.4   # the PiP is a third the width: the pops stay readable
	_pip_vp.add_child(_ai_court)
	_ai_court.info.set_text(_mode["led_text"], _ai_court.info.accent_color)

	_ai_cam = Camera3D.new()
	_ai_cam.name = "OpponentCamera"
	_ai_cam.fov = _arena_set.camera_fov if _arena_set != null else 60.0
	_pip_vp.add_child(_ai_cam)
	_ai_pool = BallPool.new()
	_ai_pool.name = "OpponentBalls"
	_ai_pool.ball_set = _pip_kit["ball"]
	_pip_vp.add_child(_ai_pool)
	_place_ai_frame(_spots[0]["pos"])

	# Over the window: OPP, the minimize button, the opponent's loadout chips.
	_pip_chrome = Control.new()
	_pip_chrome.name = "PipChrome"
	_pip_chrome.position = frame_pos
	_pip_chrome.size = frame_size
	_pip_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip_layer.add_child(_pip_chrome)
	var opp_l := _ot_text("OPP", 16)
	opp_l.position = Vector2(10, 12)
	_pip_chrome.add_child(opp_l)
	_pip_min_btn = ShadowCard.new(RetroTheme.SCENE_TEXT)
	_pip_min_btn.name = "PipMin"
	_pip_min_btn.text = "-"
	_pip_min_btn.add_theme_font_override("font", UiFont.display())
	_pip_min_btn.add_theme_font_size_override("font_size", UiFont.snap(16))
	RetroTheme.on_scene(_pip_min_btn)
	_pip_min_btn.position = Vector2(frame_size.x - 8 - 40 - ShadowStyle.OFFSET, 6)
	_pip_min_btn.size = Vector2(40 + ShadowStyle.OFFSET, 40 + ShadowStyle.OFFSET)
	_pip_min_btn.pressed.connect(_set_pip_minimized.bind(true))
	_pip_chrome.add_child(_pip_min_btn)
	_opp_chips = HBoxContainer.new()
	_opp_chips.name = "OppChips"
	_opp_chips.position = Vector2(10, frame_size.y - 20)
	_opp_chips.add_theme_constant_override("separation", int(ModeCards.CHIP_GAP))
	_opp_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip_chrome.add_child(_opp_chips)
	_refresh_opp_chips()
	# The minimized chip.
	_pip_chip = ShadowCard.new(_opp_color)
	_pip_chip.name = "PipChip"
	_pip_chip.tint = 0.42
	_pip_chip.position = Vector2(720 - 36 - 180 - ShadowStyle.OFFSET, frame_pos.y)
	_pip_chip.size = Vector2(180 + ShadowStyle.OFFSET, 50 + ShadowStyle.OFFSET)
	_pip_chip.visible = false
	_pip_chip.pressed.connect(_set_pip_minimized.bind(false))
	var cm := MarginContainer.new()
	UiLayout.full_rect(cm)
	cm.add_theme_constant_override("margin_left", 14)
	cm.add_theme_constant_override("margin_right", 14 + int(ShadowStyle.OFFSET))
	cm.add_theme_constant_override("margin_bottom", int(ShadowStyle.OFFSET))
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip_chip.add_child(cm)
	var crow := HBoxContainer.new()
	crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cm.add_child(crow)
	_pip_chip_label = _ot_text("OPP 0", 16)
	_pip_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pip_chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pip_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crow.add_child(_pip_chip_label)
	var glyph := RestoreGlyph.new()
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(glyph)
	_pip_layer.add_child(_pip_chip)


## The window's frame: a 3 px border in the opponent's colour over the
## viewport's edge, with the dithered shadow strip past it.
class PipFrame extends Control:
	var color := Color.WHITE
	func _init(p_color: Color) -> void:
		color = p_color
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var box := size - Vector2.ONE * ShadowStyle.OFFSET
		var sh := Color(color, ShadowStyle.SHADOW_ALPHA)
		var tex := ShadowStyle.dither_tex()
		draw_texture_rect(tex, Rect2(Vector2(box.x, ShadowStyle.OFFSET), Vector2(ShadowStyle.OFFSET, box.y)), true, sh)
		draw_texture_rect(tex, Rect2(Vector2(ShadowStyle.OFFSET, box.y), Vector2(box.x - ShadowStyle.OFFSET, ShadowStyle.OFFSET)), true, sh)
		draw_rect(Rect2(Vector2.ZERO, box), Color("#171311"))
		draw_rect(Rect2(Vector2.ZERO, box), color, false, PIP_FRAME)


## The minimized chip's restore glyph: a 16×14 box with a 3 px cream border and an ink shadow.
class RestoreGlyph extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(18, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2(16, 14)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, Vector2(16, 14)), RetroTheme.SCENE_TEXT, false, 3.0)


## The opponent's loadout as chips under their window (rebuilt when it changes).
func _refresh_opp_chips() -> void:
	var hand: Array = heat.hands[Heat.AI]
	if hand.size() == _opp_hand_n:
		return
	_opp_hand_n = hand.size()
	for c in _opp_chips.get_children():
		_opp_chips.remove_child(c)
		c.free()
	var shown := 0
	for id in hand:
		var card := CardDefs.get_card(str(id))
		if not card.is_empty():
			_opp_chips.add_child(ModeCards.chip(card))
			shown += 1
	# Dashed empties for the opponent's unused slots (design 4a).
	for k in maxi(0, CardDefs.SLOTS - shown):
		var e := ModeCards.Dashed.new(Vector2.ONE * ModeCards.CHIP, 2.0, 3.0)
		e.name = "OppEmpty%d" % k
		_opp_chips.add_child(e)


## The opponent's frame: camera behind their spot, ball rest pose, board facing them.
func _place_ai_frame(spot: Vector3) -> void:
	var hoop := Vector3(base_geo.hoop_x, 0.0, base_geo.hoop_z)
	var fwd := hoop - spot
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 1e-6 else Vector3.RIGHT
	_ai_cam.position = spot - fwd * 1.35 + Vector3(0.0, 1.55, 0.0)
	var look_h: float = _arena_set.camera_look_height if _arena_set != null else 2.2
	_ai_cam.look_at(Vector3(base_geo.hoop_x, look_h, base_geo.hoop_z))
	_ai_pool.rest_pos = spot + Vector3(0.0, 1.25, 0.0)
	_ai_pool.set_held_position(_ai_pool.rest_pos)
	_ai_court.face_scoreboard(spot)


func _set_pip_minimized(min_: bool) -> void:
	_pip.visible = not min_
	_pip_frame.visible = not min_
	_pip_chrome.visible = not min_
	_pip_chip.visible = min_
	# A hidden viewport still renders unless told otherwise, and its court's
	# nodes (the LED, the rim fx) still process: both stop while it is away.
	# The sim is the heat's; the window's ball, rim and net catch up on restore.
	_pip_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if min_ else SubViewport.UPDATE_ONCE
	_ai_court.process_mode = Node.PROCESS_MODE_DISABLED if min_ else Node.PROCESS_MODE_INHERIT
	_pip_dt = 0.0


## What the opponent's window wears: online, the other phone's kit off the
## wire resolved against our catalog (unknown ids → the court's stock pair,
## the court's own hoop); solo, the court's stock pair — a league shooter
## may name a `kit` in data/shooters.json one day (none does yet). The
## player's own pause-menu swaps never reach it.
static func pip_kit(cfg: Dictionary, court_hoop: HoopSet, hoop_fixed: bool) -> Dictionary:
	var kind := NetSet.kind_of_hoop(court_hoop) if court_hoop != null else "cotton"
	var kit: Dictionary = {}
	if bool(cfg.get("online", false)):
		kit = MatchProtocol.clean_kit(cfg.get("their_kit", {}))
	elif cfg.get("league", null) != null:
		var shooter: Dictionary = LeagueData.shooter(str(Dictionary(cfg.get("opponent", {})).get("id", "")))
		kit = MatchProtocol.clean_kit(shooter.get("kit", {}))
	var out := CosmeticLibrary.resolve_kit(kit, kind)
	if hoop_fixed:
		out["hoop"] = null   # the court fixes its hoop everywhere but the cage
	return out


func pip_minimized() -> bool:
	return _pip_chip != null and _pip_chip.visible


func _step_rules(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	heat.tick(dt)
	last_sim_ms = (Time.get_ticks_usec() - t0) / 1000.0
	for ev in heat.drain_events():
		if ev.get("side", "") == Heat.AI:
			_handle_ai_event(ev)
		else:
			if heat.remote and ev.get("side", "") == Heat.PLAYER:
				_online_player_event(ev)
			_handle_event(ev)


func _handle_event(ev: Dictionary) -> void:
	match ev["kind"]:
		"done":
			return  # the heat decides when it is over (overtime may follow)
		"go":
			# GO is the league's orange toast (design 4a), not the solo banner;
			# an OT tip-off keeps the carried score on the board.
			_court.arcade_chase()
			Sfx.countdown_go()
			_hud.go_toast()
			_court.info.set_text("")
			_court.show_score(heat.player.score if heat.ot > 0 else 0)
			_court.info.flash("GO!", 2, _court.info.accent_color)
		"ot_start":
			_hud.set_ot(int(ev["n"]))
			_show_ot_break(int(ev["n"]))
			_court.info.marquee("OVERTIME", 24.0, _court.info.accent_color)
			_ai_court.info.marquee("OVERTIME", 24.0, _ai_court.info.accent_color)
		"ot_period":
			_hide_ot_break()
			super(ev)
		"heat_done":
			_finish()
		"ball_ready":
			pass  # the HUD polls the wait each frame
		"card_played":
			if ev.get("ok", false):
				_show_card_play(str(ev["card"]), false, str(ev.get("target", Heat.AI)))
				# The opponent's board announces what was played on, or against, them.
				_ai_court.info.marquee(_card_marquee(str(ev["card"]), str(ev.get("target", Heat.AI)) == Heat.AI), 24.0, _ai_court.info.accent_color)
		_:
			super(ev)


## The opponent's events drive the picture-in-picture court (no HUD text,
## sounds ducked).
func _handle_ai_event(ev: Dictionary) -> void:
	var prev_gain := Sfx.gain_db
	Sfx.gain_db = AI_SFX_GAIN_DB
	match ev["kind"]:
		"go":
			_ai_court.arcade_chase()
			if heat.ot > 0:
				_ai_court.show_score(heat.score(Heat.AI))
			else:
				_ai_court.info.set_text("")
				_ai_court.show_score(0)
		"contact":
			var c: Dictionary = ev["contact"]
			if c["kind"] == "enter":
				Sfx.make_as(Sfx.sound_kind(_ai_court.net_kind()))   # the opponent's own net, not the one the player hung
				_ai_court.net_kick(Vector3(c["pos"]["x"], c["pos"]["y"], c["pos"]["z"]), Vector3(0.0, -float(c.get("speed", 5.0)), 0.0))
			elif c["kind"] == "rim":
				_ai_court.rim_react(c["speed"])
			elif c["kind"] == "floor":
				# Ground only, for the same reason as the player's court.
				_ai_pool.squash_at(
					Vector3(c["pos"]["x"], c["pos"]["y"], c["pos"]["z"]),
					Vector3(c["normal"]["x"], c["normal"]["y"], c["normal"]["z"]),
					c["speed"])
		"outcome":
			_on_ai_outcome(ev["outcome"])
		"ice_on":
			_ai_court.set_ice(true)
			_ai_court.info.marquee("ICED OVER", 24.0, _ai_court.info.accent_color)
		"ice_caught":
			_ai_court.ice_grab()
		"ice_crack":
			_ai_court.ice_crack(int(ev["left"]))
		"ice_break":
			_ai_court.set_ice(false, str(ev["by"]))
			_ai_court.info.marquee("ICE BROKEN", 24.0, _ai_court.info.accent_color)
		"buzzer":
			_ai_court.arcade_chase_stop()
			_ai_court.info.set_text("TIME")
		"heat_up":
			_ai_court.info.marquee("HEATING UP", 24.0, _ai_court.info.accent_color)
			_ai_court.flare_lights()
		"ai_spot":
			var sp: Dictionary = ev["spot"]
			_place_ai_frame(Vector3(float(sp["x"]), float(sp["y"]), float(sp["z"])))
			if int(ev["index"]) < _spots.size():
				_ai_court.info.flash(str(_spots[int(ev["index"])]["name"]), 2, _ai_court.info.accent_color)
		"fire_on":
			_ai_tier_shown = 1
			_ai_court.set_fire(true, StreakRules.FIRE_AT)
			_ai_court.info.marquee("ON FIRE", 24.0, _ai_court.info.accent_color)
		"fire_off":
			_ai_tier_shown = 1
			_ai_court.show_score(heat.score(Heat.AI))
			if _ai_court.fire_lit():
				_ai_court.set_fire(false)
				_ai_court.info.marquee("BURNED OUT" if str(ev.get("reason", "")) == "time" else "COOLED OFF", 24.0, _ai_court.info.accent_color)
		"magnet_on":
			_ai_court.set_magnet(true)
			_ai_court.info.marquee("MAGNET", 24.0, _ai_court.info.accent_color)
		"magnet_off":
			_ai_court.set_magnet(false, str(ev.get("reason", "")) == "ice")
			_ai_court.show_score(heat.score(Heat.AI))
			_ai_court.info.marquee("MAGNET SPENT" if str(ev.get("reason", "")) == "time" else "MAGNET ICED", 24.0, _ai_court.info.accent_color)
		"card_played":
			if ev.get("ok", false):
				Sfx.gain_db = prev_gain
				_show_card_play(str(ev["card"]), true, str(ev.get("target", Heat.PLAYER)))
				# Your board announces the opponent's play, whether it hit you or helped them.
				_court.info.marquee(_card_marquee(str(ev["card"]), str(ev.get("target", Heat.AI)) == Heat.PLAYER), 24.0, _court.info.accent_color)
		_:
			pass
	Sfx.gain_db = prev_gain


func _on_ai_outcome(outcome: Dictionary) -> void:
	var streak: int = outcome.get("streak", heat.ai.streak)
	if outcome.get("iced_out", false):
		return
	if outcome["made"]:
		var tier := StreakRules.base_points(streak)
		var lit := StreakRules.is_lit(streak)
		_hud.set_opponent_score(heat.score(Heat.AI))
		_ai_court.show_score(heat.score(Heat.AI), tier)
		_ai_court.rim_nudge()
		_ai_court.play_make()
		# Their scoring pop in the PiP (design 5a: every mode).
		_ai_court.rim_pop_from(HudCopy.rim_pop(str(outcome["type"]), int(outcome["points"]), false))
		if lit and streak == StreakRules.FIRE_AT:
			_ai_court.rim_pop_from(HudCopy.fire_pop())
			_ai_court.info.marquee("ON FIRE", 24.0, _ai_court.info.accent_color)
		elif lit and tier > _ai_tier_shown:
			_ai_court.info.marquee("%d PTS A BASKET" % tier, 24.0, _ai_court.info.accent_color)
		if lit:
			_ai_tier_shown = tier
			_ai_court.set_fire(true, streak)
	else:
		_ai_tier_shown = 1
		if _ai_court.fire_lit():
			_ai_court.set_fire(false)
			_ai_court.info.marquee("COOLED OFF", 24.0, _ai_court.info.accent_color)


func _process(dt: float) -> void:
	super(dt)
	# The city scoreboards: VISITOR is the other side, PER the period (OT 2+),
	# and the opponent's own clock in the PiP. After super: the heat's period
	# outranks the base trial's regulation/overtime pair.
	_court.set_visitor(heat.score(Heat.AI))
	_court.set_period(heat.ot + 1)
	if _ai_court != null:
		_ai_court.set_visitor(heat.player.score)
		_ai_court.set_period(heat.ot + 1)
		_ai_court.set_clock(heat.ai.time_left)
	# Opponent view sync (their board slides too in the last 30 s).
	if heat.ai.geo != _ai_applied_geo:
		_ai_applied_geo = heat.ai.geo
		_ai_court.apply_geometry(heat.ai.geo)
	# The window at half rate: its ball, rim, net and magnet step with the
	# frames' dt together, then one draw is armed. Nothing while minimized.
	_pip_dt += dt
	_pip_tick += 1
	if not pip_minimized() and _pip_tick % PIP_EVERY == 0:
		_ai_pool.update_balls(heat.balls(Heat.AI), heat.ai.holding, _pip_dt)
		_ai_court.magnet_follow(CourtGeometry.magnet_target(heat.balls(Heat.AI)))
		_ai_court.step_rim(_pip_dt)
		_ai_court.step_net(_pip_dt, heat.balls(Heat.AI))
		_pip_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_pip_dt = 0.0
	if heat.ai.phase == TimeTrial.PHASE_RUNNING:
		_ai_court.led.band_flash(_ai_court.led.band_flash_color, LedBoard.band_hz_for(heat.ai.time_left))
	_pip_chip_label.text = "OPP %d" % heat.score(Heat.AI)
	_refresh_opp_chips()
	_refresh_tray()
	_hud.set_ball_wait(heat.ball_wait() if heat.player.phase == TimeTrial.PHASE_RUNNING and not heat.player.holding else 0.0)
	_hud.set_side_tags(heat.player.streak, heat.player.iced, heat.ai.streak, heat.ai.iced)
	_watch_report(dt)


func _finish() -> void:
	if _finished_handed_off:
		return
	_finished_handed_off = true
	_court.set_fire(false)
	_court.set_ice(false)
	_ai_court.set_fire(false)
	_ai_court.set_ice(false)
	var result := heat.result()
	# Online the room stays open through the result page: the payout
	# (`settled`) still has to land, and our last report has to go out.
	# The match-end page (docs/HOME.md → Results): settle the heat at the
	# buzzer and play the moment; a tap goes on to the post-match page. A
	# heat outside a league skips straight there.
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		var heat_doc := App.settle_heat(result)
		if heat_doc.get("league", null) == null:
			get_tree().create_timer(0.8).timeout.connect(App.to_heat_result)
			return
		var overlay := MatchEndOverlay.new()
		overlay.name = "MatchEnd"
		overlay.build(MatchEndCopy.state(heat_doc))
		overlay.continued.connect(_after_match_end)
		add_child(overlay)
	)


## After the match-end page: the Area Unlock page when this match's XP
## reached an area's level (docs/HOME.md → Area unlock), else the post-match
## page. GO THERE lands on that area's home; LATER goes on to the post-match
## page. Either way the page is seen once.
func _after_match_end() -> void:
	var area := App.take_pending_unlock()
	if area == "":
		App.to_heat_result()
		return
	var page := AreaUnlockPage.new()
	page.name = "AreaUnlock"
	page.build(AreaUnlockCopy.state(area, App.level()))
	page.go_there.connect(func(id: String) -> void:
		App.mark_unlock_seen(id)
		App.home_card = maxi(0, AreaArchiveCopy.index_of(id))
		App.show_archive = false
		App.to_title())
	page.later.connect(func() -> void:
		App.mark_unlock_seen(area)
		App.to_heat_result())
	add_child(page)


## The pause menu's swaps are ours alone: the opponent's window wears its
## own kit (pip_kit) — their cosmetics online, the court's stock pair solo.
