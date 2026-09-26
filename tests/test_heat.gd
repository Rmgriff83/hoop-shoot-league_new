extends RefCounted
## Heat: head-to-head time trial with a ball-return wait, AI driver, overtime,
## result totals and seed replay.


func _tick(h: Heat, seconds: float) -> void:
	var steps := ceili(seconds / SimConstants.SIM_DT)
	for i in steps:
		h.tick(SimConstants.SIM_DT)


func _drain_kinds(h: Heat) -> Array:
	var out := []
	for ev in h.drain_events():
		out.push_back([ev["side"] if ev.has("side") else "", ev["kind"]])
	return out


func run(t) -> void:
	var geo := SimGeometry.arcade()
	var h := Heat.new({"geo": geo, "seconds": 20.0, "ot_seconds": 5.0, "ball_return_s": 1.5,
		"ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 11, "calib_key": "arcade"})
	_tick(h, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.eq(h.phase(), TimeTrial.PHASE_RUNNING, "running after the countdown")
	# Ball-return wait: refuse the second pickup until 1.5 s after the release.
	var swish := Ballistics.ideal_launch_for(52.0, geo)
	t.ok(h.pickup(), "first pickup")
	t.ok(h.release(swish), "release")
	t.ok(not h.pickup(), "pickup refused right after a release")
	t.ok(h.ball_wait() > 1.3 and h.ball_wait() <= 1.5 + 1e-9, "wait ≈ 1.5 s (%.2f)" % h.ball_wait())
	_tick(h, 1.0)
	t.ok(not h.pickup(), "still refused at 1.0 s")
	_tick(h, 0.6)
	t.close(h.ball_wait(), 0.0, 1e-9, "wait over")
	t.ok(h.pickup(), "pickup allowed after the wait")
	h.drop()
	# Let the heat run out; the AI shoots on its own rhythm.
	_tick(h, 25.0)
	var kinds := _drain_kinds(h)
	var ai_releases := kinds.filter(func(k): return k[0] == "ai" and k[1] == "release").size()
	var player_outcomes := kinds.filter(func(k): return k[0] == "player" and k[1] == "outcome").size()
	t.ok(ai_releases >= 5 and ai_releases <= 9, "AI released on a human rhythm in 20 s at 1.5 s return (%d)" % ai_releases)
	t.eq(player_outcomes, 1, "the player's one shot resolved")
	t.ok(h.done or h.ot > 0, "heat decided or in overtime")
	# A shorter ball-return wait speeds the AI up; it reloads while its last ball flies.
	var hq := Heat.new({"geo": geo, "seconds": 20.0, "ot_seconds": 5.0, "ball_return_s": 1.0,
		"ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 11, "calib_key": "arcade"})
	_tick(hq, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	var overlap := false
	var last_release := -10.0
	var gaps := []
	for i in int(20.0 / SimConstants.SIM_DT):
		hq.tick(SimConstants.SIM_DT)
		for ev in hq.drain_events():
			if ev.get("side", "") == "ai" and ev["kind"] == "release":
				if last_release > 0.0:
					gaps.push_back(hq.ai.t - last_release)
				last_release = hq.ai.t
		if hq.ai.holding and not hq.ai.balls().is_empty():
			overlap = true
	t.ok(gaps.size() > ai_releases, "1.0 s return → more AI shots than 1.5 s (%d vs %d)" % [gaps.size() + 1, ai_releases])
	var mean_gap := 0.0
	for g in gaps:
		mean_gap += float(g)
	mean_gap /= maxf(gaps.size(), 1.0)
	t.close(mean_gap, AiCadence.cycle_s(hq.ai_ratings, 1.0), 0.35, "AI release spacing ≈ cycle (%.2f vs %.2f)" % [mean_gap, AiCadence.cycle_s(hq.ai_ratings, 1.0)])
	t.ok(overlap, "the AI holds its next ball while the last one is still in the air")
	if h.done:
		var r := h.result()
		t.eq(r["player_score"], h.player.score, "result carries the player score")
		t.eq(r["ai_score"], h.ai.score, "result carries the ai score")
		t.eq(r["won"], h.player.score > h.ai.score, "won flag")
		t.eq(int(r["sides"]["ai"]["attempts"]), h.ai.attempts, "ai totals")
	# Overtime: force a tie at the buzzer with a sharpshooter vs nobody.
	var h2 := Heat.new({"geo": geo, "seconds": 6.0, "ot_seconds": 4.0, "ball_return_s": 1.5,
		"ai": AiRatings.make(0.05, 0.1, 6.0), "seed": 3, "calib_key": "arcade"})
	_tick(h2, TimeTrial.COUNTDOWN_SECONDS + 8.0)
	# Both at 0 (AI 5 % shooter with a slow pace, player idle) → tie → OT break.
	var saw_ot := false
	for ev in h2.drain_events():
		if ev["kind"] == "ot_start":
			saw_ot = true
	if h2.ai.score == 0:
		t.ok(saw_ot and h2.ot >= 1, "scoreless heat goes to overtime")
		t.eq(h2.player.phase, TimeTrial.PHASE_DONE, "the OT break holds play")
		t.ok(not h2.pickup(), "no pickup during the OT break")
		_tick(h2, Heat.OT_BREAK_S + TimeTrial.COUNTDOWN_SECONDS + 0.1)
		var saw_period := false
		var saw_go := 0
		for ev in h2.drain_events():
			if ev["kind"] == "ot_period":
				saw_period = true
			elif ev["kind"] == "go":
				saw_go += 1
		t.ok(saw_period, "OT period opened after the break")
		t.eq(saw_go, 2, "both sides tipped off OT after the countdown")
		t.eq(h2.player.phase, TimeTrial.PHASE_RUNNING, "OT period running")
		t.close(h2.player.seconds, 4.0, 1e-9, "OT period is 4 s here")
		# Player scores in OT, then the period ends decided.
		h2.pickup()
		h2.release(swish)
		_tick(h2, 8.0)
		t.ok(h2.done, "decided after OT")
		t.ok(h2.result()["won"], "player won in OT")
		t.eq(int(h2.result()["ot"]), h2.ot, "result records OT count")
	# Seed replay: two heats with the same seed and no player input match exactly.
	var a := Heat.new({"geo": geo, "seconds": 12.0, "ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 77, "calib_key": "arcade"})
	var b := Heat.new({"geo": geo, "seconds": 12.0, "ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 77, "calib_key": "arcade"})
	_tick(a, 16.0)
	_tick(b, 16.0)
	t.eq(a.ai.score, b.ai.score, "same seed → same AI score")
	t.eq(a.ai.attempts, b.ai.attempts, "same seed → same AI attempts")
	# freeze_rim (card hook): the AI side can be iced from outside.
	var h3 := Heat.new({"geo": geo, "seconds": 30.0, "ai": AiRatings.make(0.9, 0.9, 2.0), "seed": 5, "calib_key": "arcade"})
	_tick(h3, TimeTrial.COUNTDOWN_SECONDS + 0.1)
	t.ok(h3.ai.freeze_rim("card"), "ai rim frozen by a card")
	t.ok(not h3.ai.freeze_rim("card"), "cannot double-freeze")
	t.ok(h3.ai.geo.ice, "ai geometry iced")
	h3.tick(SimConstants.SIM_DT)   # side events are relayed on tick
	var reason := ""
	for ev in h3.drain_events():
		if ev["kind"] == "ice_on":
			reason = str(ev.get("reason", ""))
	t.eq(reason, "card", "ice_on carries the card reason")
	# Last 30 s: with board_motion both sides' hoops slide (the arcade's mechanic).
	var h4 := Heat.new({"geo": geo, "seconds": 40.0, "ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 2, "calib_key": "arcade", "board_motion": true})
	_tick(h4, TimeTrial.COUNTDOWN_SECONDS + 5.0)
	t.ok(not h4.player.moving and not h4.ai.moving, "still before the last 30 s")
	_tick(h4, 8.0)
	t.ok(h4.player.moving and h4.ai.moving, "both boards moving inside the last 30 s")
	var heat_ups := 0
	for ev in h4.drain_events():
		if ev["kind"] == "heat_up":
			heat_ups += 1
	t.eq(heat_ups, 2, "a heat_up event per side")
	t.ok(absf(h4.ai.geo.hoop_x - geo.hoop_x) > 0.01 or absf(h4.ai.geo.hoop_z - geo.hoop_z) > 0.01, "AI hoop has left its base pose")
	t.ok(h4.ai.geo_in(0.9).hoop_x != h4.ai.geo.hoop_x or h4.ai.geo_in(0.9).hoop_z != h4.ai.geo.hoop_z, "AI aims with a lead")
	# Beach: the AI walks to another spot at the 30/20/10 s marks and shoots from there.
	var beach := SimGeometry.beach()
	var spots := [{"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 1.039, "y": 0.0, "z": -2.45}, {"x": 1.039, "y": 0.0, "z": 2.45},
		{"x": 2.9, "y": 0.0, "z": -4.0}, {"x": 2.9, "y": 0.0, "z": 4.0}]
	var h5 := Heat.new({"geo": beach, "seconds": 40.0, "ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 12, "calib_key": "beach",
		"spots": spots, "spot_shuffle": true})
	_tick(h5, TimeTrial.COUNTDOWN_SECONDS + 5.0)
	t.eq(h5.ai_spot_index, 0, "AI starts on the key")
	_tick(h5, 30.0)
	var moves := []
	var off_spot_release := false
	for ev in h5.drain_events():
		if ev["kind"] == "ai_spot":
			moves.push_back(int(ev["index"]))
		elif ev["kind"] == "release" and ev.get("side", "") == "ai":
			var l: Dictionary = ev["launch"]
			if l.has("rx") and (absf(float(l["rx"])) > 0.01 or absf(float(l["rz"])) > 0.01):
				off_spot_release = true
	t.eq(moves.size(), 3, "three AI spot moves in the last 30 s (%s)" % str(moves))
	t.ok(h5.ai_spot_index != 0 or moves.size() == 3, "AI ended off the key or moved three times")
	t.ok(off_spot_release, "AI released from a side spot")
	var h6 := Heat.new({"geo": beach, "seconds": 40.0, "ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 12, "calib_key": "beach",
		"spots": spots, "spot_shuffle": true})
	_tick(h6, TimeTrial.COUNTDOWN_SECONDS + 35.0)
	t.eq(h6.ai_spot_index, h5.ai_spot_index, "spot walk replays from the seed")
	# Beach overtime: both back at the key, no shuffle in the extra period.
	var h7 := Heat.new({"geo": beach, "seconds": 40.0, "ot_seconds": 6.0, "ai": AiRatings.make(0.0, 0.0, 6.0), "seed": 12,
		"calib_key": "beach", "spots": spots, "spot_shuffle": true})
	_tick(h7, TimeTrial.COUNTDOWN_SECONDS + 42.0)
	var reg_moves := 0
	var saw_ot7 := false
	for ev in h7.drain_events():
		if ev["kind"] == "ai_spot":
			reg_moves += 1
		elif ev["kind"] == "ot_start":
			saw_ot7 = true
	if h7.ai.score == 0:
		t.eq(reg_moves, 3, "three regulation moves before the tie")
		t.ok(saw_ot7, "beach heat tied into OT")
		_tick(h7, Heat.OT_BREAK_S + 0.1)
		var back_to_key := false
		for ev in h7.drain_events():
			if ev["kind"] == "ai_spot" and int(ev["index"]) == 0:
				back_to_key = true
		t.ok(back_to_key, "AI sent back to the key for OT")
		t.eq(h7.ai_spot_index, 0, "AI at the key")
		t.ok(h7.ai.overtime and h7.player.overtime, "both sides in overtime")
		_tick(h7, TimeTrial.COUNTDOWN_SECONDS + 6.5)
		var ot_moves := 0
		for ev in h7.drain_events():
			if ev["kind"] == "ai_spot" and int(ev["index"]) != 0:
				ot_moves += 1   # (index 0 = the reset before a further OT)
		t.eq(ot_moves, 0, "no spot shuffle in overtime")
	# A bot on the player side (the card lab): both sides shoot, the heat
	# decides itself, and the seed replays it.
	var lab := Heat.new({"geo": geo, "seconds": 20.0, "ot_seconds": 5.0, "ball_return_s": 1.0,
		"ai": AiRatings.make(0.6, 0.6, 3.0), "player_bot": AiRatings.make(0.6, 0.6, 3.0), "seed": 21, "calib_key": "arcade"})
	_tick(lab, 60.0)
	t.ok(lab.done, "bot-vs-bot heat runs to a decision")
	t.ok(lab.player.attempts >= 5 and lab.ai.attempts >= 5, "both bots shot (%d vs %d)" % [lab.player.attempts, lab.ai.attempts])
	var lab2 := Heat.new({"geo": geo, "seconds": 20.0, "ot_seconds": 5.0, "ball_return_s": 1.0,
		"ai": AiRatings.make(0.6, 0.6, 3.0), "player_bot": AiRatings.make(0.6, 0.6, 3.0), "seed": 21, "calib_key": "arcade"})
	_tick(lab2, 60.0)
	t.eq([lab2.player.score, lab2.ai.score], [lab.player.score, lab.ai.score], "bot-vs-bot replays from the seed")
	# Without a bot the player side stays idle, as it always has.
	var idle := Heat.new({"geo": geo, "seconds": 8.0, "ai": AiRatings.make(0.6, 0.6, 3.0), "seed": 21, "calib_key": "arcade"})
	_tick(idle, 12.0)
	t.eq(idle.player.attempts, 0, "no bot → the player side does not shoot on its own")
