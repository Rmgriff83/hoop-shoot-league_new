extends RefCounted
## Heat online (docs/BACKEND.md → Phase 3): the AI side driven by another
## phone's messages. A seeded bot heat is the "other phone": its launches
## replay through a remote heat to the identical score (the same float64
## sim), its reported score and totals are what the remote heat shows and
## settles on, shots before the period runs queue, a tie goes to OT on both,
## and a dropped peer is a void early or a forfeit late.


func _cfg(extra := {}) -> Dictionary:
	var cfg := {"geo": SimGeometry.arcade(2.9), "seconds": 20.0, "ot_seconds": 6.0, "ball_return_s": 1.0,
		"ai": AiRatings.make(0.65, 0.5), "seed": 11, "calib_key": "arcade"}
	cfg.merge(extra, true)
	return cfg


## Run the bot heat and the remote heat in lockstep, relaying the bot's AI
## side as the wire would: shot on release, outcome after it lands, the
## period report at its buzzer. Returns [src, dst].
func _relay(seed: int, max_s := 60.0) -> Array:
	var src := Heat.new(_cfg({"seed": seed}))
	var dst := Heat.new(_cfg({"seed": seed, "remote": true}))
	var dt := 1.0 / 60.0
	var t := 0.0
	var reported := 0
	var was_done := false
	var n := 0
	while t < max_s and not (src.done and dst.done):
		src.tick(dt)
		for ev in src.drain_events():
			if ev.get("side", "") != Heat.AI:
				continue
			if ev["kind"] == "release":
				n += 1
				var wire := MatchProtocol.parse(MatchProtocol.encode(MatchProtocol.shot(n, ev["launch"])))
				dst.remote_release(wire["launch"])
			elif ev["kind"] == "outcome":
				dst.remote_outcome(src.ai.score)
		# Their buzzer: the report names the period that just ended (the bot
		# heat may already have rolled into OT within the same tick).
		var is_done := src.ai.phase == TimeTrial.PHASE_DONE
		if is_done and not was_done:
			dst.remote_period_end(reported, src.ai.score, Heat.totals_of(src.ai))
			reported += 1
		was_done = is_done
		dst.tick(dt)
		dst.drain_events()
		t += dt
	return [src, dst]


func run(t) -> void:
	# No bot on the remote side; the board reads the other phone's count.
	var r := Heat.new(_cfg({"remote": true}))
	t.ok(r.remote, "remote flag")
	t.eq(r.score(Heat.AI), 0, "their score starts at 0")
	r.remote_outcome(3)
	t.eq(r.score(Heat.AI), 3, "their reported score is the board")
	t.eq(r.ai.score, 0, "…not the replay's")
	# A shot before their clock runs here is queued, then flies.
	t.ok(not r.remote_release({"angle_deg": 50.0, "speed": 7.0}), "a shot in the countdown waits")
	for i in 60 * 4:
		r.tick(1.0 / 60.0)
	t.eq(r.ai.balls().size(), 1, "…and is in flight once the period runs")
	t.eq(r.remote_shots, 1, "counted")
	# The replay never refuses for the ball-return wait.
	t.ok(r.remote_release({"angle_deg": 50.0, "speed": 7.0}), "a second shot right away goes")
	t.eq(r.ai.balls().size(), 2, "two in the air")
	# The spot follows the launch origin.
	r.set_spots([{"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 0.0, "y": 0.0, "z": 1.5}], true)
	var moved := false
	r.remote_release({"angle_deg": 50.0, "speed": 7.0, "rx": 0.1, "ry": 1.8, "rz": 1.4})
	for ev in r.drain_events():
		if ev["kind"] == "ai_spot" and int(ev["index"]) == 1:
			moved = true
	t.ok(moved, "a shot from the second spot moves their frame there")
	# Lockstep relay: the replay lands where the bot's did.
	var pair := _relay(11)
	var src: Heat = pair[0]
	var dst: Heat = pair[1]
	t.ok(src.done and dst.done, "both heats end")
	t.ok(src.ai.attempts > 3, "the bot shot (%d)" % src.ai.attempts)
	t.eq(dst.ai.attempts, src.ai.attempts, "every shot replayed")
	t.eq(dst.ai.score, src.ai.score, "the replay scores exactly what the bot did")
	t.ok(not dst.desync(), "no desync")
	var res := dst.result()
	t.ok(bool(res.get("online", false)), "an online result")
	t.eq(int(res["ai_score"]), src.ai.score, "their score settled from their report")
	t.eq(int(res["sides"]["ai"]["swishes"]), src.ai.swishes, "their totals are theirs")
	t.eq(bool(res["won"]), 0 > src.ai.score, "won by the two authoritative scores")
	t.eq(int(res["ot"]), src.ot, "the same number of periods")
	# A tie goes to overtime on both: a bot that never scores vs our idle side.
	var tie_src := Heat.new(_cfg({"seed": 3, "ai": AiRatings.make(0.0, 0.0), "seconds": 5.0, "ot_seconds": 3.0}))
	var tie_dst := Heat.new(_cfg({"seed": 3, "remote": true, "seconds": 5.0, "ot_seconds": 3.0}))
	var ots := 0
	var reported := 0
	var was_done := false
	for i in 60 * 10:
		tie_src.tick(1.0 / 60.0)
		tie_src.drain_events()
		var is_done := tie_src.ai.phase == TimeTrial.PHASE_DONE
		if is_done and not was_done:
			tie_dst.remote_period_end(reported, tie_src.ai.score, Heat.totals_of(tie_src.ai))
			reported += 1
		was_done = is_done
		tie_dst.tick(1.0 / 60.0)
		for ev in tie_dst.drain_events():
			if ev["kind"] == "ot_start":
				ots += 1
		if ots >= 1:
			break
	t.ok(ots >= 1, "0–0 at the buzzer → overtime on the remote heat too")
	# Without their report the remote heat waits.
	var wait := Heat.new(_cfg({"remote": true, "seconds": 4.0}))
	for i in 60 * 12:
		wait.tick(1.0 / 60.0)
		wait.drain_events()
	t.ok(not wait.done and wait.player.phase == TimeTrial.PHASE_DONE, "our period is over, theirs unreported: not decided yet")
	wait.remote_period_end(0, 2, {"score": 2, "makes": 2, "swishes": 0, "attempts": 3, "bestStreak": 2, "bonus": 0, "iced": 0})
	wait.tick(1.0 / 60.0)
	t.ok(wait.done, "their report decides it")
	t.eq(int(wait.result()["sides"]["ai"]["attempts"]), 3, "with their totals")
	t.ok(not bool(wait.result()["won"]), "0–2: lost")
	# Forfeits.
	var early := Heat.new(_cfg({"remote": true}))
	for i in 60 * 6:
		early.tick(1.0 / 60.0)
	early.remote_forfeit(30.0)
	t.ok(early.done and early.forfeit_reason() == "void", "they left in the first seconds: void")
	t.ok(not bool(early.result()["won"]), "…no win")
	var late := Heat.new(_cfg({"remote": true, "seconds": 60.0}))
	for i in 60 * 40:
		late.tick(1.0 / 60.0)
	late.remote_forfeit(30.0)
	t.eq(late.forfeit_reason(), "forfeit", "they left after 30 s: a forfeit")
	t.ok(bool(late.result()["won"]), "…a win")
	t.eq(str(late.result()["reason"]), "forfeit", "the result says why")
