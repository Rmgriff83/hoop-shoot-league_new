extends RefCounted
## Online with clock skew (the real thing: one phone tips off ~2 s after the
## other). The leading heat reaches each buzzer first and must wait for the
## lagging side's report; a late tying shot from the lagging side arrives
## after the leader's replay clock has already finished. The leader must
## still go to the next overtime, and never hang.


func _cfg(extra := {}) -> Dictionary:
	var cfg := {"geo": SimGeometry.arcade(2.9), "seconds": 8.0, "ot_seconds": 5.0, "ball_return_s": 1.0,
		"ai": AiRatings.make(0.0, 0.0), "seed": 5, "remote": true}
	cfg.merge(extra, true)
	return cfg


func run(t) -> void:
	var dt := 1.0 / 60.0
	var lead := Heat.new(_cfg())   # the Mac: 2 s ahead
	var ots := 0
	var decided := false
	# Regulation: the leader's buzzer, then the laggard's report two seconds later (0-0).
	for i in 60 * 12:
		lead.tick(dt)
		for ev in lead.drain_events():
			if ev["kind"] == "ot_start":
				ots += 1
	t.eq(lead.player.phase, TimeTrial.PHASE_DONE, "the leader's regulation is over (countdown 3 + 8 s)")
	t.ok(not lead.done and ots == 0, "…and it waits on the laggard's report")
	for i in 60 * 2:
		lead.tick(dt)
	lead.remote_period_end(0, 0, Heat.totals_of(lead.ai))
	for i in 10:
		lead.tick(dt)
		for ev in lead.drain_events():
			if ev["kind"] == "ot_start":
				ots += 1
	t.eq(ots, 1, "0-0 → overtime 1")
	t.eq(lead.ot, 1, "period 1")
	# Through the OT break and the OT countdown and the whole OT period.
	for i in 60 * 12:
		lead.tick(dt)
		lead.drain_events()
	t.eq(lead.player.phase, TimeTrial.PHASE_DONE, "the leader's OT 1 is over")
	t.ok(not lead.done, "…waiting again")
	# The laggard's late tying shot lands on us after our replay clock is done:
	# the shot queues, their running score arrives, then their buzzer report.
	t.ok(not lead.remote_release({"angle_deg": 52.0, "speed": 7.0}), "a shot after our replay's buzzer waits")
	lead.remote_outcome(0)
	for i in 60 * 2:
		lead.tick(dt)
	lead.remote_period_end(1, 0, Heat.totals_of(lead.ai))
	for i in 10:
		lead.tick(dt)
		for ev in lead.drain_events():
			if ev["kind"] == "ot_start":
				ots += 1
	t.eq(ots, 2, "a tie at the end of OT 1 → overtime 2 on the leader")
	t.ok(not lead.done, "…not decided")
	for i in 60 * 7:
		lead.tick(dt)
		lead.drain_events()
	t.eq(lead.player.phase, TimeTrial.PHASE_RUNNING, "OT 2 is running after the break and countdown")
	t.eq(lead.ai.balls().size(), 0, "the stale queued shot never replays into the new period")
	# And a decision in OT 2 by their report alone.
	for i in 60 * 10:
		lead.tick(dt)
		lead.drain_events()
	t.eq(lead.player.phase, TimeTrial.PHASE_DONE, "the leader's OT 2 is over")
	lead.remote_period_end(2, 3, {"score": 3, "makes": 3, "attempts": 4, "swishes": 0, "bestStreak": 3, "bonus": 0, "iced": 0})
	lead.tick(dt)
	t.ok(lead.done, "their 3 decides OT 2")
	t.ok(not bool(lead.result()["won"]), "…against us")
	t.eq(int(lead.result()["ot"]), 2, "two overtimes on the record")
	# The laggard (the phone, 2 s behind): the leader's report is already in
	# when its own buzzer sounds, so the tie rolls `ot` on in the same tick as
	# the buzzer event — that event must still say which period it ended.
	var lag := Heat.new(_cfg())
	lag.remote_period_end(0, 0, Heat.totals_of(lag.ai))   # their regulation report, early
	var done_period := -1
	var lag_ots := 0
	for i in 60 * 13:
		lag.tick(dt)
		for ev in lag.drain_events():
			if ev["kind"] == "done" and ev.get("side", "") == Heat.PLAYER and done_period < 0:
				done_period = int(ev.get("period", -99))
			if ev["kind"] == "ot_start":
				lag_ots += 1
	t.eq(lag_ots, 1, "the laggard ties regulation and goes to OT 1")
	t.eq(done_period, 0, "…and its buzzer event names period 0, not the overtime it rolled into")
	# A report numbered one period ahead (the old bug on the wire) still decides us.
	var lenient := Heat.new(_cfg({"seconds": 4.0}))
	for i in 60 * 9:
		lenient.tick(dt)
		lenient.drain_events()
	t.eq(lenient.player.phase, TimeTrial.PHASE_DONE, "regulation over")
	lenient.remote_period_end(1, 2, {"score": 2, "makes": 2, "attempts": 2, "swishes": 0, "bestStreak": 2, "bonus": 0, "iced": 0})
	lenient.tick(dt)
	t.ok(lenient.done, "a report for a later period than ours still settles this one")
