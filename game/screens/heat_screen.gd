extends "res://game/screens/time_trial_screen.gd"
## A league heat: the time-trial screen driving a Heat (two TimeTrials on one
## clock). The player's side is the main court exactly as in a trial; the
## opponent's side renders in a picture-in-picture court (its own world) in
## the top-right corner, with a minimize control. The HUD shows both scores
## and the ball-return wait; overtime periods roll on until decided.

const PIP_SIZE := Vector2i(216, 384)
## League heats use a smaller window (the dashboard's stats carry the story).
const PIP_SIZE_LEAGUE := Vector2i(168, 298)
const PIP_POS := Vector2(720 - 216 - 12, 84)
const AI_SFX_GAIN_DB := -9.0
## Card tray: three slots on the left edge, inside the UI zone (above the flick
## input's grab line at 45 % of the height) so a tap never becomes a shot.
const TRAY_POS := Vector2(16, 440)
const TRAY_CARD := Vector2(84, 112)

var heat: Heat
var _heat_cfg: Dictionary = {}
var _pip_layer: CanvasLayer
var _pip: SubViewportContainer
var _pip_vp: SubViewport
var _pip_min_btn: Button
var _pip_chip: Button
var _ai_court: CourtGeometry
var _ai_pool: BallPool
var _ai_cam: Camera3D
var _ai_tier_shown := 1
var _ai_applied_geo: SimGeometry
## The league's standings / bracket cloth in the arena (league heats only).
var _banner: LeagueBanner
## Where the PiP sits: below the spot picker row on courts that have one.
var _pip_pos := PIP_POS
var _pip_size := PIP_SIZE
var _tray: Array[TextureButton] = []
var _tray_ids: Array = []


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
	})
	trial = heat.player


func _after_ready() -> void:
	_hud.set_heat(true)
	var list := []
	for sp in _spots:
		var pos: Vector3 = sp["pos"]
		list.push_back({"x": float(pos.x), "y": float(pos.y), "z": float(pos.z)})
	heat.set_spots(list, _shuffle_enabled)
	if _heat_cfg.get("league", null) != null:
		lock_spot_picker()
	_build_pip()
	_build_tray()
	_build_toast()
	_build_ot_break()
	_build_league_banner()
	_refresh_ticker()


## The cage's back-wall ribbon. League content during a league heat, attract
## copy otherwise — the ribbon is part of the room, not part of the match.
func _refresh_ticker() -> void:
	if _heat_cfg.get("league", null) == null:
		_court.set_ticker(TickerText.arcade_items(_best_score()))
		return
	var id := str(_heat_cfg["league"]["id"])
	_court.set_ticker(TickerText.league_items(
		App.league_cfg(id), App.league_doc(id), heat.player.score, heat.ai.score, _ai_id()))


func _ai_id() -> String:
	return str(_heat_cfg.get("opponent", {}).get("id", ""))


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
var _tray_tags: Array[Label] = []
## The slot whose fire card is burning (its tag counts the window down).
var _fire_slot := -1
## The slot a card was just dealt from, and where it sat (the deal starts there).
var _dealt_slot := -1
var _dealt_from := Rect2(TRAY_POS, TRAY_CARD)
var _tray_tween: Tween


func _build_tray() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CardUi"
	layer.layer = 11
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
		var b := TextureButton.new()
		b.name = "Card%d" % i
		b.texture_normal = load(str(card.get("art", "res://assets/textures/cards/card_back.png")))
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.custom_minimum_size = TRAY_CARD
		b.size = TRAY_CARD
		b.focus_mode = Control.FOCUS_NONE
		b.visible = id != ""
		b.pressed.connect(_on_card_tapped.bind(i))
		layer.add_child(b)
		_tray.push_back(b)
		var tag := Label.new()
		tag.name = "Tag%d" % i
		tag.size = Vector2(TRAY_CARD.x, 28)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 18)
		tag.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
		tag.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.14))
		tag.add_theme_constant_override("outline_size", 6)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.visible = false
		layer.add_child(tag)
		_tray_tags.push_back(tag)
	_layout_tray(false)


## Slots that still hold a card, lowest slot first.
func _tray_shown() -> Array[int]:
	var out: Array[int] = []
	for i in _tray.size():
		if _tray[i].visible:
			out.push_back(i)
	return out


## Stack the remaining cards centred on the tray column (slide when animate).
func _layout_tray(animate: bool) -> void:
	var shown := _tray_shown()
	var n := shown.size()
	if n == 0:
		return
	var total := n * TRAY_CARD.y + (n - 1) * (TRAY_PITCH - TRAY_CARD.y)
	var top := TRAY_CENTRE_Y - total * 0.5
	if _tray_tween != null:
		_tray_tween.kill()
	_tray_tween = create_tween().set_parallel(true) if animate else null
	for k in n:
		var i: int = shown[k]
		var pos := Vector2(TRAY_POS.x, top + (n - 1 - k) * TRAY_PITCH)
		var tag_pos := pos + Vector2(0, TRAY_CARD.y * 0.5 - 14)
		if animate:
			_tray_tween.tween_property(_tray[i], "position", pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tray_tween.tween_property(_tray_tags[i], "position", tag_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_tray[i].position = pos
			_tray_tags[i].position = tag_pos


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
	_tray_tags[i].visible = false
	_layout_tray(true)


## Slot states for tests/probes: "empty", "ready", "wait" or "used" per slot.
func tray_states() -> Array:
	var out := []
	for i in _tray.size():
		if _tray_ids[i] == "":
			out.push_back("empty")
		elif _tray_ids[i] == "used":
			out.push_back("fire" if i == _fire_slot and heat.player.fire_card else "used")
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
	# One-time use: the slot leaves the loadout first; a card the save no longer
	# holds (played from another device, say) is not deployed.
	if not App.consume_slot(i, id):
		_tray_ids[i] = "used"
		return
	_dealt_slot = i
	_dealt_from = Rect2(_tray[i].position, _tray[i].size)
	if heat.play_card(Heat.PLAYER, id):
		_tray_ids[i] = "used"
		if str(CardDefs.get_card(id).get("effect", {}).get("kind", "")) == "fire":
			_fire_slot = i   # stays in the tray while it burns
		else:
			_remove_from_tray(i)
	else:
		# The effect refused after all: put the copy back in its slot.
		var d := App.cards_doc()
		var b := CardDefs.league_doc(d, App.current_league if App.current_league != "" else "cage")
		CardDefs.add(b, id)
		CardDefs.equip(b, i, id)
		SaveService.put_cards(d)


func _refresh_tray() -> void:
	var states := tray_states()
	for i in _tray.size():
		var st: String = states[i]
		match st:
			"fire":
				_tray[i].modulate = Color.WHITE
				_tray_tags[i].text = "🔥 %ds" % ceili(heat.player.fire_left())
				_tray_tags[i].visible = true
			"used":
				_remove_from_tray(i)   # a fire card whose window just closed
			"wait":
				_tray[i].modulate = Color(0.75, 0.75, 0.8, 0.9)
				_tray_tags[i].text = "WAIT"
				_tray_tags[i].visible = true
			"ready":
				_tray[i].modulate = Color.WHITE
				_tray_tags[i].visible = false
			_:
				_tray_tags[i].visible = false


## Overtime break: a dimmed card over the court announcing the tie and the
## extra period while the heat holds (Heat.OT_BREAK_S), before the countdown.
## Touches pass through (nothing is pickable during the break), so the pause
## button still works.
var _ot_layer: CanvasLayer
var _ot_title: Label
var _ot_sub: Label
var _ot_note: Label


func _build_ot_break() -> void:
	_ot_layer = CanvasLayer.new()
	_ot_layer.name = "OtBreakUi"
	_ot_layer.layer = 25
	_ot_layer.visible = false
	add_child(_ot_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.1, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ot_layer.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-280, -150)
	vb.size = Vector2(560, 300)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ot_layer.add_child(vb)
	_ot_sub = Label.new()
	_ot_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ot_sub.add_theme_font_size_override("font_size", 30)
	_ot_sub.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vb.add_child(_ot_sub)
	_ot_title = Label.new()
	_ot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ot_title.add_theme_font_size_override("font_size", 64)
	_ot_title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3))
	_ot_title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	_ot_title.add_theme_constant_override("outline_size", 10)
	vb.add_child(_ot_title)
	_ot_note = Label.new()
	_ot_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ot_note.add_theme_font_size_override("font_size", 24)
	_ot_note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vb.add_child(_ot_note)


func _show_ot_break(n: int) -> void:
	if _ot_layer == null:
		return
	_ot_sub.text = "TIED  %d – %d" % [heat.player.score, heat.ai.score]
	_ot_title.text = "OVERTIME" if n == 1 else "OVERTIME %d" % n
	var secs := int(round(heat.ot_seconds))
	_ot_note.text = ("%d seconds · both shooters back to the key" % secs) if _spots.size() > 1 else ("%d seconds" % secs)
	_ot_layer.visible = true
	Sfx.score_pop(true)


func _hide_ot_break() -> void:
	if _ot_layer != null:
		_ot_layer.visible = false


func ot_break_shown() -> bool:
	return _ot_layer != null and _ot_layer.visible


## Card play "deal": the card slides out of its tray slot, grows to the middle
## of the screen with a caption, then flies to whoever it acts on — your own
## hoop for a self card, the opponent's PiP (or its minimized chip) for a card
## played against them. The opponent's plays run the same path from the PiP.
const DEAL_BIG := Vector2(168, 224)
const DEAL_SMALL := Vector2(26, 34)
const DEAL_CENTRE := Vector2(360, 470)
const DEAL_OUT_S := 0.35
const DEAL_HOLD_S := 0.55
const DEAL_FLY_S := 0.4

var _deal: TextureRect
var _deal_label: Label
var _deal_tween: Tween


func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ToastUi"
	layer.layer = 12
	add_child(layer)
	_deal = TextureRect.new()
	_deal.name = "Deal"
	_deal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_deal.stretch_mode = TextureRect.STRETCH_SCALE
	_deal.visible = false
	_deal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_deal)
	_deal_label = Label.new()
	_deal_label.name = "DealText"
	_deal_label.position = DEAL_CENTRE + Vector2(-200, DEAL_BIG.y * 0.5 + 10)
	_deal_label.size = Vector2(400, 70)
	_deal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deal_label.add_theme_font_size_override("font_size", 26)
	_deal_label.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2))
	_deal_label.add_theme_constant_override("outline_size", 8)
	_deal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deal_label.visible = false
	_deal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_deal_label)


## LED line for the side that did NOT play a card: `against_me` when the card
## hit that side ("ICED BY CARD"), else the other shooter boosted themselves
## ("OPP HEAT CHECK").
static func _card_marquee(card_id: String, against_me: bool) -> String:
	var card := CardDefs.get_card(card_id)
	var kind := str(card.get("effect", {}).get("kind", ""))
	if against_me:
		return "ICED BY CARD" if kind == "ice" else "%s BY CARD" % str(card.get("name", card_id)).to_upper()
	return "OPP %s" % str(card.get("name", card_id)).to_upper()


## Screen point of the player's hoop (where a self card flies to).
func _hoop_point() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _court == null or not _court.rim_pivot.is_inside_tree():
		return Vector2(360, 560)
	return cam.unproject_position(_court.rim_pivot.global_position)


## Screen point of the opponent's window (the PiP, or its chip when minimized).
func _pip_point() -> Vector2:
	if _pip != null and _pip.visible:
		return _pip_pos + Vector2(_pip_size) * 0.5
	if _pip_chip != null:
		return _pip_chip.position + _pip_chip.size * 0.5
	return Vector2(640, 100)


func _show_card_play(card_id: String, by_ai: bool, target: String) -> void:
	var card := CardDefs.get_card(card_id)
	var art: Texture2D = load(str(card.get("art", "res://assets/textures/cards/card_back.png")))
	var opp: String = str(_heat_cfg.get("opponent", {}).get("name", "OPPONENT")).to_upper()
	var cname: String = str(card.get("name", card_id)).to_upper()
	var from: Rect2
	var to: Vector2
	var caption: String
	var colour: Color
	if by_ai:
		from = Rect2(_pip_point() - DEAL_SMALL * 0.5, DEAL_SMALL)
		if target == Heat.PLAYER:
			to = _hoop_point()
			caption = "%s plays %s on YOU!" % [opp, cname]
			colour = Color(1.0, 0.6, 0.5)
		else:
			to = _pip_point()
			caption = "%s plays %s" % [opp, cname]
			colour = Color(1.0, 0.8, 0.5)
	else:
		from = _dealt_from
		if target == Heat.PLAYER:
			to = _hoop_point()
			caption = "%s → YOU" % cname
			colour = Color(1.0, 0.85, 0.5)
		else:
			to = _pip_point()
			caption = "%s → %s" % [cname, opp]
			colour = Color(0.72, 0.88, 1.0)
	_deal_card(art, from, to, caption, colour)


func _deal_card(art: Texture2D, from: Rect2, to: Vector2, caption: String, colour: Color) -> void:
	if _deal_tween != null:
		_deal_tween.kill()
	_deal.texture = art
	_deal.position = from.position
	_deal.size = from.size
	_deal.modulate = Color.WHITE
	_deal.visible = true
	_deal_label.text = caption
	_deal_label.add_theme_color_override("font_color", colour)
	_deal_label.modulate.a = 0.0
	_deal_label.visible = true
	Sfx.score_pop(true)
	_deal_tween = create_tween()
	_deal_tween.set_parallel(true)
	# Out of the slot and up to size in the middle (caption fades in under it).
	_deal_tween.tween_property(_deal, "position", DEAL_CENTRE - DEAL_BIG * 0.5, DEAL_OUT_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_deal_tween.tween_property(_deal, "size", DEAL_BIG, DEAL_OUT_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_deal_tween.tween_property(_deal_label, "modulate:a", 1.0, 0.2).set_delay(0.15)
	# Hold, then fly to the target while shrinking and fading.
	_deal_tween.chain().tween_interval(DEAL_HOLD_S)
	_deal_tween.chain().tween_property(_deal, "position", to - DEAL_SMALL * 0.5, DEAL_FLY_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_deal_tween.tween_property(_deal, "size", DEAL_SMALL, DEAL_FLY_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_deal_tween.tween_property(_deal, "modulate:a", 0.0, DEAL_FLY_S * 0.6).set_delay(DEAL_FLY_S * 0.4)
	_deal_tween.tween_property(_deal_label, "modulate:a", 0.0, 0.25)
	_deal_tween.chain().tween_callback(func() -> void:
		_deal.visible = false
		_deal_label.visible = false)


## Where the deal is right now (for probes): null when idle.
func deal_rect() -> Variant:
	if _deal == null or not _deal.visible:
		return null
	return Rect2(_deal.position, _deal.size)


## The opponent's court in its own 3D world, rendered small.
func _build_pip() -> void:
	_pip_layer = CanvasLayer.new()
	_pip_layer.name = "PipUi"
	_pip_layer.layer = 11
	add_child(_pip_layer)

	if _heat_cfg.get("league", null) != null:
		_pip_size = PIP_SIZE_LEAGUE
	_pip_pos = Vector2(720 - _pip_size.x - 12, PIP_POS.y)
	if _spots.size() > 1 and _picker_free:
		_pip_pos += Vector2(0, 56)   # clear of the picker row when it is shown
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
	_pip_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pip_vp.transparent_bg = false
	_pip.add_child(_pip_vp)

	_ai_court = CourtGeometry.new()
	_ai_court.name = "OpponentCourt"
	Sfx.rim_rigidity = base_geo.rim_rigidity()
	_ai_court.geo = base_geo
	_ai_court.arena_set = _arena_set
	_ai_court.hoop_set = _hoop_set
	_pip_vp.add_child(_ai_court)
	_ai_court.led.set_text(_mode["led_text"], _ai_court.led.accent_color)

	_ai_cam = Camera3D.new()
	_ai_cam.name = "OpponentCamera"
	_ai_cam.fov = _arena_set.camera_fov if _arena_set != null else 60.0
	_pip_vp.add_child(_ai_cam)
	_ai_pool = BallPool.new()
	_ai_pool.name = "OpponentBalls"
	_ai_pool.ball_set = App.ball_set
	_pip_vp.add_child(_ai_pool)
	_place_ai_frame(_spots[0]["pos"])

	# Frame + minimize control, and the chip that replaces the window.
	var frame := ReferenceRect.new()
	frame.editor_only = false
	frame.border_color = Color(0.85, 0.9, 1.0, 0.7)
	frame.border_width = 2.0
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip.add_child(frame)
	_pip_min_btn = Button.new()
	_pip_min_btn.text = "–"
	_pip_min_btn.add_theme_font_size_override("font_size", 22)
	_pip_min_btn.position = Vector2(_pip_pos.x + _pip_size.x - 44, _pip_pos.y + 4)
	_pip_min_btn.custom_minimum_size = Vector2(40, 40)
	_pip_min_btn.focus_mode = Control.FOCUS_NONE
	_pip_min_btn.pressed.connect(_set_pip_minimized.bind(true))
	_pip_layer.add_child(_pip_min_btn)
	_pip_chip = Button.new()
	_pip_chip.text = "OPP 0  ▢"
	_pip_chip.add_theme_font_size_override("font_size", 20)
	_pip_chip.position = Vector2(720 - 150 - 12, _pip_pos.y)
	_pip_chip.custom_minimum_size = Vector2(150, 44)
	_pip_chip.focus_mode = Control.FOCUS_NONE
	_pip_chip.visible = false
	_pip_chip.pressed.connect(_set_pip_minimized.bind(false))
	_pip_layer.add_child(_pip_chip)


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
	_pip_min_btn.visible = not min_
	_pip_chip.visible = min_
	# A hidden viewport still renders unless told otherwise.
	_pip_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if min_ else SubViewport.UPDATE_ALWAYS


func pip_minimized() -> bool:
	return _pip_chip != null and _pip_chip.visible


func _step_rules(dt: float) -> void:
	heat.tick(dt)
	for ev in heat.drain_events():
		if ev.get("side", "") == Heat.AI:
			_handle_ai_event(ev)
		else:
			_handle_event(ev)


func _handle_event(ev: Dictionary) -> void:
	match ev["kind"]:
		"done":
			return  # the heat decides when it is over (overtime may follow)
		"go":
			if heat.ot > 0:
				# OT tip-off: keep the carried score on the board, flash GO.
				_hud.banner("GO! 🏀", Color(0.4, 0.9, 0.55))
				_court.led.show_score(heat.player.score)
				_court.led.flash("GO!", 2, _court.led.accent_color)
			else:
				super(ev)
		"ot_start":
			_hud.set_ot(int(ev["n"]))
			_show_ot_break(int(ev["n"]))
			_court.led.marquee("OVERTIME", 24.0, _court.led.accent_color)
			_ai_court.led.marquee("OVERTIME", 24.0, _ai_court.led.accent_color)
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
				_ai_court.led.marquee(_card_marquee(str(ev["card"]), str(ev.get("target", Heat.AI)) == Heat.AI), 24.0, _ai_court.led.accent_color)
		_:
			super(ev)


## The opponent's events drive the picture-in-picture court (no HUD text,
## sounds ducked).
func _handle_ai_event(ev: Dictionary) -> void:
	var prev_gain := Sfx.gain_db
	Sfx.gain_db = AI_SFX_GAIN_DB
	match ev["kind"]:
		"go":
			if heat.ot > 0:
				_ai_court.led.show_score(heat.ai.score)
			else:
				_ai_court.led.set_text("")
				_ai_court.led.show_score(0)
		"contact":
			var c: Dictionary = ev["contact"]
			if c["kind"] == "enter":
				Sfx.make()
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
			_ai_court.led.marquee("ICED OVER", 24.0, _ai_court.led.accent_color)
		"ice_caught":
			_ai_court.ice_grab()
		"ice_crack":
			_ai_court.ice_crack(int(ev["left"]))
		"ice_break":
			_ai_court.set_ice(false, str(ev["by"]))
			_ai_court.led.marquee("ICE BROKEN", 24.0, _ai_court.led.accent_color)
		"buzzer":
			_ai_court.led.set_text("TIME")
		"heat_up":
			_ai_court.led.marquee("HEATING UP", 24.0, _ai_court.led.accent_color)
			_ai_court.flare_lights()
		"ai_spot":
			var sp: Dictionary = ev["spot"]
			_place_ai_frame(Vector3(float(sp["x"]), float(sp["y"]), float(sp["z"])))
			if int(ev["index"]) < _spots.size():
				_ai_court.led.flash(str(_spots[int(ev["index"])]["name"]), 2, _ai_court.led.accent_color)
		"fire_on":
			_ai_tier_shown = 1
			_ai_court.set_fire(true, StreakRules.FIRE_AT)
			_ai_court.led.marquee("ON FIRE", 24.0, _ai_court.led.accent_color)
		"fire_off":
			_ai_tier_shown = 1
			_ai_court.led.show_score(heat.ai.score)
			if _ai_court.fire_lit():
				_ai_court.set_fire(false)
				_ai_court.led.marquee("BURNED OUT" if str(ev.get("reason", "")) == "time" else "COOLED OFF", 24.0, _ai_court.led.accent_color)
		"card_played":
			if ev.get("ok", false):
				Sfx.gain_db = prev_gain
				_show_card_play(str(ev["card"]), true, str(ev.get("target", Heat.PLAYER)))
				# Your board announces the opponent's play, whether it hit you or helped them.
				_court.led.marquee(_card_marquee(str(ev["card"]), str(ev.get("target", Heat.AI)) == Heat.PLAYER), 24.0, _court.led.accent_color)
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
		_hud.set_opponent_score(heat.ai.score)
		_refresh_ticker()
		_ai_court.led.show_score(heat.ai.score, tier)
		_ai_court.rim_nudge()
		_ai_court.play_make()
		if lit and streak == StreakRules.FIRE_AT:
			_ai_court.led.marquee("ON FIRE", 24.0, _ai_court.led.accent_color)
		elif lit and tier > _ai_tier_shown:
			_ai_court.led.marquee("%d PTS A BASKET" % tier, 24.0, _ai_court.led.accent_color)
		if lit:
			_ai_tier_shown = tier
			_ai_court.set_fire(true, streak)
	else:
		_ai_tier_shown = 1
		if _ai_court.fire_lit():
			_ai_court.set_fire(false)
			_ai_court.led.marquee("COOLED OFF", 24.0, _ai_court.led.accent_color)


func _process(dt: float) -> void:
	super(dt)
	# Opponent view sync (their board slides too in the last 30 s).
	if heat.ai.geo != _ai_applied_geo:
		_ai_applied_geo = heat.ai.geo
		_ai_court.apply_geometry(heat.ai.geo)
	_ai_pool.update_balls(heat.balls(Heat.AI), heat.ai.holding, dt)
	_ai_court.step_rim(dt)
	_ai_court.step_net(dt, heat.balls(Heat.AI))
	if heat.ai.phase == TimeTrial.PHASE_RUNNING:
		_ai_court.led.band_flash(_ai_court.led.band_flash_color, LedBoard.band_hz_for(heat.ai.time_left))
	_pip_chip.text = "OPP %d  ▢" % heat.ai.score
	_refresh_tray()
	_hud.set_ball_wait(heat.ball_wait() if heat.player.phase == TimeTrial.PHASE_RUNNING and not heat.player.holding else 0.0)


func _finish() -> void:
	if _finished_handed_off:
		return
	_finished_handed_off = true
	_court.set_fire(false)
	_court.set_ice(false)
	_ai_court.set_fire(false)
	_ai_court.set_ice(false)
	var result := heat.result()
	get_tree().create_timer(1.4).timeout.connect(func() -> void: App.finish_heat(result))
