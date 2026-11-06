extends RefCounted
## The trailer director's staged steps (docs/TRAILER.md → Shot files): each
## `stage_<verb>(step)` puts a real page or match on screen through the same
## entry points the QA passes use — a league heat with its PiP, the league's
## tabs, a match-end page, a season wrap-up, the online lobby, face-off, heat
## and result against QaFakePeer, the boards, the locker and PEGGY. Nothing
## here draws anything of its own. It runs on the trailer's own save
## (`--save-dir=trailer_save`), so what it grants or equips never reaches a
## real one.

const FIXTURES := "res://tools/trailer/fixtures/"

var d: Node   # the director


func _init(director: Node) -> void:
	d = director


func _scene() -> Node:
	return d.get_tree().current_scene


func _fixture(file: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + file))
	if parsed is Dictionary:
		return parsed
	d.call("_problem", "no fixture %s" % file)
	return {}


func _wait_for(test: Callable, timeout := 25.0) -> bool:
	var waited := 0.0
	while waited < timeout:
		if test.call():
			return true
		await d.get_tree().process_frame
		waited += 1.0 / 60.0
	return false


# ---- the league ----------------------------------------------------------------------


## {area, hand: [id × ≤3] (armed), spare: [ids] (owned, not armed), ready}
## → the league's next heat, held on the pre-match page (or past it).
func stage_league_heat(step: Dictionary) -> void:
	var area := str(step.get("area", "cage"))
	if not App.enter_league(area):
		d.call("_problem", "the %s league is not open on the trailer save" % area)
		return
	var hand: Array = step.get("hand", [])
	for i in mini(hand.size(), 3):
		if str(hand[i]) != "":
			App.add_card(str(hand[i]), 1, area)
			App.equip_card(i, str(hand[i]), area)
	for id in step.get("spare", []):
		App.add_card(str(id), 1, area)
	App.start_league_heat()
	var ok: bool = await _wait_for(func() -> bool:
		var sc := _scene()
		return sc != null and "heat" in sc and sc.has_method("prematch_open") and bool(sc.call("prematch_open")))
	if not ok:
		d.call("_problem", "the pre-match page never opened")
		return
	await d.call("_sleep", 0.6)
	if bool(step.get("ready", true)):
		await stage_ready(step)


## READY on the pre-match page, through the countdown, to a live ball.
func stage_ready(step: Dictionary) -> void:
	var sc := _scene()
	var page: PreMatchPage = sc.call("prematch_page") if sc != null and sc.has_method("prematch_page") else null
	if page == null:
		d.call("_problem", "READY with no pre-match page")
		return
	page.press_ready()
	await _wait_for(func() -> bool: return not bool(_scene().call("prematch_open")), 20.0)
	sc = _scene()
	if "_rng" in sc:
		(sc.get("_rng") as RandomNumberGenerator).seed = int(step.get("seed", 7))
	d.call("_attach_trail", sc)
	await d.call("_until", "running", 20.0)


## {card, slot, s}: on the pre-match page, drag an owned card up into a
## loadout slot with real pointer input, as a finger does (drag-to-arm).
func stage_drag_card(step: Dictionary) -> void:
	var sc := _scene()
	var page: PreMatchPage = sc.call("prematch_page") if sc != null and sc.has_method("prematch_page") else null
	if page == null:
		d.call("_problem", "a card drag with no pre-match page")
		return
	var cid := str(step.get("card", "ice"))
	var btn: Control = null
	var holder: Control = null
	for n in page.find_children("*", "TextureButton", true, false):
		for c in (n as Control).gui_input.get_connections():
			var bound: Array = (c["callable"] as Callable).get_bound_arguments()
			if bound.size() >= 2 and str(bound[0]) == cid:
				btn = n
				holder = bound[1]
	var slot: Control = page.find_child("Slot%d" % int(step.get("slot", 0)), true, false)
	var stage: Control = page.get("_stage")
	if btn == null or slot == null or stage == null:
		d.call("_problem", "no owned '%s' card or slot to drag to" % cid)
		return
	# The page reads the pointer's real position, which injected events do not
	# move; so its own drag is driven directly along a finger's path: the same
	# ghost, hover highlight and arm as a real drag.
	var inv := stage.get_global_transform().affine_inverse()
	var from: Vector2 = inv * btn.get_global_rect().get_center()
	var to: Vector2 = inv * slot.get_global_rect().get_center()
	page.set("_drag", {"id": cid, "from": from, "moved": false, "holder": holder, "held": 0.0})
	await d.call("_sleep", 0.08)
	page.call("_start_ghost")
	var frames := maxi(8, int(float(step.get("s", 0.55)) * 60.0))
	var slot_i := int(step.get("slot", 0))
	var slot_size: Vector2 = page.get("YOU_SLOT")
	for i in frames:
		var k := float(i + 1) / float(frames)
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		var at := from.lerp(to, e) + Vector2(sin(k * PI) * 14.0, 0.0)   # a finger's arc, not a ruler's line
		var ghost: Control = page.get("_ghost")
		if ghost != null:
			ghost.position = at - Vector2(slot_size.x / 2.0, slot_size.y * 0.62)
		# Over the slot for the last stretch: the page's own hover look (it reads
		# the real pointer for this, so the state is set as _move_ghost sets it).
		var over := k >= 0.7
		if over != (int(page.get("_hover")) == slot_i):
			page.set("_hover", slot_i if over else -1)
			var highlights: Array = page.get("_highlights")
			var nodes: Array = page.get("_you_slot_nodes")
			for j in highlights.size():
				(highlights[j] as Control).visible = over and j == slot_i
				(nodes[j] as Control).scale = Vector2.ONE * (1.08 if over and j == slot_i else 1.0)
			if ghost != null:
				ghost.rotation_degrees = 0.0 if over else -6.0
				ghost.scale = Vector2(0.95, 0.95) if over else Vector2(1.05, 1.05)
		await d.get_tree().process_frame
	await d.call("_sleep", 0.12)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	page.call("_input", up)
	await d.call("_sleep", 0.1)


## {slot, id}: play a card from the tray (dealt in if the level kept it out).
func stage_card(step: Dictionary) -> void:
	var sc := _scene()
	if sc == null or not ("heat" in sc):
		d.call("_problem", "a card with no heat")
		return
	var heat: Heat = sc.get("heat")
	var id := str(step.get("id", "ice"))
	if not heat.hands[Heat.PLAYER].has(id):
		heat.hands[Heat.PLAYER].push_back(id)
	sc.call("_deploy", int(step.get("slot", 0)), id)


## {area, tab}: the league open over the home, on a tab.
func stage_league_page(step: Dictionary) -> void:
	var area := str(step.get("area", "cage"))
	await d.driver.call("_pick_area", area)
	var ts := _scene()
	if not App.enter_league(area) or ts == null or not ts.has_method("_open_league"):
		d.call("_problem", "the %s league page is not reachable" % area)
		return
	if not bool(ts.call("is_league_open")):
		ts.call("_open_league", bool(step.get("instant", false)))
	await d.call("_sleep", 0.6)
	await stage_league_tab(step)


func stage_league_tab(step: Dictionary) -> void:
	var lc: LeagueContext = _scene().find_child("League", true, false)
	if lc != null and step.has("tab"):
		lc.show_tab(str(step["tab"]), bool(step.get("instant", false)))
		await d.call("_sleep", 0.4)


## {case}: the match-end page (design 15a / 39a–b) over whatever shows:
## win, loss, series, advance, eliminated, final_game, runner_up, champion.
func stage_match_end(step: Dictionary) -> void:
	var heat: Dictionary = d.driver.call("match_end_heat", str(step.get("case", "champion")))
	if heat.is_empty():
		d.call("_problem", "no match-end case '%s'" % str(step.get("case", "")))
		return
	# The XP the page counts up (as the season pass stages it).
	heat["xp"] = {"gained": 180, "title_gained": 120, "level_before": App.level(), "level_after": App.level(), "capped": false, "title": bool(heat.get("league_end", {}).get("series_won", false))}
	heat["xp_now"] = App.xp()
	var o := MatchEndOverlay.new()
	o.name = "MatchEnd"
	o.build(MatchEndCopy.state(heat))
	d.add_child(o)


## The splash: the ball drops, the neon HOOP SHOOT LEAGUE flickers on (the end card).
func stage_splash(_step: Dictionary) -> void:
	d.get_tree().change_scene_to_file("res://game/screens/splash_screen.tscn")
	await d.call("_sleep", 0.05)
	# The logo alone: the menu and the social icons stay out of the end card.
	var sc := _scene()
	if sc == null:
		return
	var hide: Array = []
	if sc.get("_buttons") is Array:
		hide.append_array(sc.get("_buttons"))
	if sc.get("_social") != null:
		hide.push_back(sc.get("_social"))
	for n in hide:
		var c := n as CanvasItem
		if c != null:
			c.visible = false
			c.visibility_changed.connect(func() -> void:
				if c.visible:
					c.visible = false)


## {variant: champs | out}: a season played through on a fixed seed, its
## wrap-up page over the league home (design 39c / 39e).
func stage_season_wrap(step: Dictionary) -> void:
	var cfg := LeagueData.league("cage")
	var doc: Dictionary = d.driver.call("_qa_done_doc", cfg, int(step.get("seed", 7)), str(step.get("variant", "champs")) == "champs")
	App.save_league_doc(doc, "cage")
	App.enter_league("cage")
	var ts := _scene()
	if not bool(ts.call("is_league_open")):
		ts.call("_open_league", true)
		await d.call("_sleep", 0.5)
	ts.call("_open_season_wrap")


# ---- solo: results and the boards ----------------------------------------------------


## {area, score, best}: the time-trial results page for a run.
func stage_results(step: Dictionary) -> void:
	var area := str(step.get("area", "cage"))
	var run := {"score": int(step.get("score", 31)), "makes": 19, "attempts": 27, "swishes": 8, "bestStreak": 7, "bonus": 6, "iced": 0, "location": area}
	App.next_mode = str(Dictionary(App.AREA_MODES["trial"]).get(area, "trial"))
	App.last_run = SaveService.put_score(run)
	App.last_run["tickets"] = int(step.get("tickets", 34))
	App.last_run_was_best = bool(step.get("best", true))
	d.get_tree().change_scene_to_file(App.RESULTS_SCENE)
	await d.call("_sleep", 0.3)


## {fixture, period}: the ranks page with invented rows (THIS WEEK by default).
func stage_board(step: Dictionary) -> void:
	var ts := _scene()
	if ts == null or not ts.has_method("_open_ranks"):
		d.call("_problem", "the ranks page is not reachable from here")
		return
	ts.call("_open_ranks")
	await d.call("_sleep", 0.6)
	await stage_board_rows(step)


## {fixture, me: {rank, score}}: (re)fill the open ranks page — a second
## call with a better rank is the climb.
func stage_board_rows(step: Dictionary) -> void:
	var page: RanksPage = d.get_tree().root.find_child("RanksPage", true, false)
	if page == null:
		d.call("_problem", "no ranks page")
		return
	var data := _fixture(str(step.get("fixture", "week_board.json")))
	if step.get("me") is Dictionary:
		var acct: Dictionary = Net.account()
		data = board_with_me(data, int(step["me"].get("rank", 9)), int(step["me"].get("score", 30)), str(acct.get("name", "YOU")), str(acct.get("tag", "")))
	var period := str(step.get("period", "week"))
	var area := str(step.get("area", page.area()))
	if page.area() != area or page.period() != period:
		page.select(area, period)   # the page asks for it; with no network it falls back to the device board…
		await d.call("_sleep", 0.3)
	page.set_board(area, period, data)   # …and the staged rows take its place


## The fixture's rows with YOU placed at `rank` with `score`: the rows below
## shift down a place (pure; the test pins it).
static func board_with_me(data: Dictionary, rank: int, score: int, me_name: String, me_tag := "") -> Dictionary:
	var out := data.duplicate(true)
	var rows: Array = out.get("rows", []).filter(func(r: Dictionary) -> bool: return not bool(r.get("me", false)))
	rank = clampi(rank, 1, rows.size() + 1)
	rows.insert(rank - 1, {"rank": rank, "name": me_name, "tag": me_tag, "score": score, "me": true})
	for i in rows.size():
		rows[i]["rank"] = i + 1
	out["rows"] = rows
	out["me"] = {"rank": rank, "score": score}
	return out


# ---- online, against QaFakePeer -------------------------------------------------------


## {rank: {...}, ladder: fixture}: the online lobby, your rank card and the top fifteen.
func stage_lobby(step: Dictionary) -> void:
	await d.driver.call("_click_named", "Online")
	await d.call("_sleep", 0.5)
	var lobby: MatchLobbyPage = d.get_tree().root.find_child("MatchLobby", true, false)
	if lobby == null:
		d.call("_problem", "the lobby did not open")
		return
	lobby.set_loading(false)
	var ladder := _fixture(str(step.get("ladder", "ranked_ladder.json")))
	if step.get("rank") is Dictionary:
		lobby.set_rank(step["rank"])
	elif ladder.get("me") is Dictionary:
		lobby.set_rank(ladder["me"])
	lobby.set_top(ladder)


## The reel spinning for an opponent (the names are generated, never real).
func stage_finding(_step: Dictionary) -> void:
	var lobby: MatchLobbyPage = d.get_tree().root.find_child("MatchLobby", true, false)
	if lobby != null:
		lobby.show_waiting("quick")


## The face-off card: YOU / VS / the fake peer.
func stage_found(step: Dictionary) -> void:
	var lobby: MatchLobbyPage = d.get_tree().root.find_child("MatchLobby", true, false)
	if lobby == null:
		return
	var peer := QaFakePeer.new()
	var who: Dictionary = peer.peer.duplicate(true)
	peer.free()
	who["area"] = str(step.get("area", "beach"))
	lobby.show_found(who)


## {area, seconds, hands: {a, b}, their_kit: {ball, net}, ranked, tiers}: a
## staged online heat against the fake peer; the PiP wears `their_kit`.
func stage_online_heat(step: Dictionary) -> void:
	var lobby: MatchLobbyPage = d.get_tree().root.find_child("MatchLobby", true, false)
	if lobby != null:
		lobby.close()
		await d.call("_sleep", 0.4)
	var kit: Dictionary = step.get("their_kit", {})
	var start := {"t": "start", "seed": int(step.get("seed", 4242)), "area": str(step.get("area", "beach")),
		"seconds": float(step.get("seconds", 30.0)), "ot_seconds": 6.0, "ball_return_s": 1.0,
		"hands": step.get("hands", {"a": ["fire7", "", "ice"], "b": ["", "", ""]}), "levels": {"a": App.level(), "b": 9},
		"ranked": bool(step.get("ranked", true)), "cap": 1,
		"tiers": step.get("tiers", {"a": {"tier": "pro", "division": 2}, "b": {"tier": "pro", "division": 1}}),
		"kits": {"a": null, "b": MatchProtocol.kit(str(kit.get("ball", "galaxy")), str(kit.get("net", "rwb")))}}
	var fake := QaFakePeer.new()
	fake.name = "Match"
	App.add_child(fake)
	App.room = fake
	App.match_how = "ranked" if bool(start["ranked"]) else "quick"
	fake.message.connect(func(m: Dictionary) -> void:
		if str(m.get("t", "")) == MatchProtocol.SETTLED:
			App.settled_online(m))
	var cfg := MatchProtocol.heat_cfg(start, fake.peer, "a")
	App.start_heat(str(cfg["mode"]), cfg)
	await _wait_for(func() -> bool: return _scene() != null and _scene().get("heat") != null)
	var sc := _scene()
	fake.stage(start, App.geo_for_mode(str(cfg["mode"])), (sc.get("heat") as Heat).spots, true)
	d.call("_attach_trail", sc)
	await d.call("_until", "running", 20.0)


## {won}: the online result page with the room's decision: rating, tier, SPOILS.
func stage_online_result(step: Dictionary) -> void:
	var won := bool(step.get("won", true))
	var peer := QaFakePeer.new()
	peer.name = "Match"
	App.add_child(peer)
	App.room = peer
	App.match_how = "ranked"
	App.online_settle = {}
	App.last_heat = {"won": won, "player_score": int(step.get("you", 44)), "ai_score": int(step.get("them", 39)), "ot": 0,
		"opponent": peer.peer, "mode": "heat", "location": str(step.get("area", "beach")), "league": null, "card_drop": "",
		"online": true, "ranked": true,
		"sides": {"player": {"makes": 19, "attempts": 28, "swishes": 8, "bestStreak": 7, "bonus": 7, "iced": 0},
			"ai": {"makes": 17, "attempts": 29, "swishes": 5, "bestStreak": 5, "bonus": 5, "iced": 0}},
		"pulse": GamePulse.from_keyframes([0, 15, 30, 45, 60, 75, 90], [0, 6, 12, 19, 27, 35, int(step.get("you", 44))], [0, 7, 13, 18, 25, 33, int(step.get("them", 39))])}
	d.get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await d.call("_sleep", 0.6)
	# The fake's decision, with the rank the trailer's player really has (PRO II → PRO I).
	var settle: Dictionary = peer.settle_message(won)
	var mine: Dictionary = Net.me_rank
	settle["rank"] = {"tier": str(mine.get("tier", "pro")), "division": maxi(1, int(mine.get("division", 2)) - (1 if won else 0)),
		"games": int(mine.get("games", 0)) + 1, "wins": int(mine.get("wins", 0)) + (1 if won else 0), "losses": int(mine.get("losses", 0)) + (0 if won else 1)}
	settle["peak"] = {"tier": settle["rank"]["tier"], "division": settle["rank"]["division"]}
	settle["milestones"] = []
	App.settled_online(settle)


# ---- the locker and PEGGY -------------------------------------------------------------


## {tab}: the locker over the home.
func stage_locker(step: Dictionary) -> void:
	var ts := _scene()
	if ts == null or not ts.has_method("_open_locker"):
		d.call("_problem", "the locker is not reachable from here")
		return
	if ts.call("locker") == null:
		ts.call("_open_locker")
		await d.call("_sleep", 0.6)
	if step.has("tab"):
		(ts.call("locker") as LockerPanel).show_tab(str(step["tab"]))
	if step.has("view"):
		(ts.call("locker") as LockerPanel).show_view(str(step["view"]))


## {ball} or {net}: a tap on a tile, as a finger would.
func stage_locker_tap(step: Dictionary) -> void:
	var locker: LockerPanel = _scene().call("locker")
	if locker == null:
		return
	if step.has("ball"):
		locker.tap_ball(str(step["ball"]))
	elif step.has("net"):
		locker.tap_net(str(step["net"]))


## PEGGY from the locker.
func stage_peggy(_step: Dictionary) -> void:
	var ts := _scene()
	if ts.call("locker") == null:
		await stage_locker({})
	(ts.call("locker") as LockerPanel).peggy_requested.emit()
	await d.call("_sleep", 1.0)


## {want: legend | epic}: a real drop that lands on a plate of that rarity.
## The aim is found by running the board's own sim for this drop's seed;
## then PLAY, the crane travels there, DROP.
func stage_peggy_drop(step: Dictionary) -> void:
	var page: PeggyPage = _scene().call("peggy")
	if page == null:
		d.call("_problem", "a PEGGY drop with no PEGGY page")
		return
	var want := str(step.get("want", "legend"))
	var aim := aim_for(want, App.peggy_slots(), DetRng.new(App.peggy_seed(App.drop_count())).fork("drop").state)
	if is_nan(aim):
		d.call("_problem", "no aim lands on a %s plate this drop" % want)
		return
	if App.tickets() < PeggyPrizes.DROP_COST and App.peggy_free_plays() <= 0:
		App.grant_tickets(PeggyPrizes.DROP_COST)
		page._refresh_machine()
	page._on_play()
	await d.call("_sleep", PeggyMachine.FEED_S + 0.3)
	var m := page.machine()
	var from := m.aim()
	var travel := maxf(0.5, absf(aim - from) / 3.0)
	var t := 0.0
	while t < travel:
		await d.get_tree().process_frame
		t += 1.0 / 60.0
		m.set_aim(lerpf(from, aim, smoothstep(0.0, 1.0, t / travel)))
	m.set_aim(aim)
	await d.call("_sleep", float(step.get("hold", 0.35)))
	m.press()


## The aim (board units) whose drop lands on a `rarity` plate that holds a
## prize, for this drop's seed; NAN when no aim does. Pure.
static func aim_for(rarity: String, plates: Array, seed_value: int) -> float:
	var best := NAN
	var steps := 240
	for i in steps + 1:
		# From the centre outwards: the shortest crane travel that works.
		var k := (i + 1) / 2 * (1 if i % 2 == 0 else -1)
		var aim := PeggyBoard.AIM_MAX * 2.0 * float(k) / float(steps)
		if absf(aim) > PeggyBoard.AIM_MAX:
			continue
		var slot := int(PeggyBoard.simulate(aim, seed_value)["slot"])
		if slot >= 0 and slot < plates.size() and str(plates[slot].get("rarity", "")) == rarity and str(plates[slot].get("id", "")) != "":
			best = aim
			break
	return best
