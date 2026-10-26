extends RefCounted
## Port of tests/timeTrial.spec.ts.

var SWISH_LAUNCH := Ballistics.ideal_launch(52.0)
var BRICK_LAUNCH := {"angle_deg": 45.0, "speed": 7.2}  # clean airball


func _tick_seconds(tt: TimeTrial, seconds: float) -> void:
	var steps := ceili(seconds / SimConstants.SIM_DT)
	for i in steps:
		tt.tick(SimConstants.SIM_DT)


func _has_kind(events: Array[Dictionary], kind: String) -> bool:
	for e in events:
		if e["kind"] == kind:
			return true
	return false


func run(t) -> void:
	run_endless(t)
	_countdown_gates(t)
	_scoring_and_streaks(t)
	_streak_tiers(t)
	_card_fire(t)
	_card_magnet(t)
	_cold_streak(t)
	_rapid_fire(t)
	_buzzer_beater(t)
	_slow_shooter(t)
	_holding_at_buzzer(t)
	_start_period(t)


func _countdown_gates(t) -> void:
	var tt := TimeTrial.new()
	t.ok(not tt.pickup(), "pickup blocked during countdown")
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "running after countdown")
	t.ok(_has_kind(tt.drain_events(), "go"), "GO event fired")
	t.ok(tt.pickup(), "pickup allowed when running")
	t.ok(not tt.pickup(), "second pickup blocked while holding")


func _scoring_and_streaks(t) -> void:
	var tt := TimeTrial.new()
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	for i in 3:
		t.ok(tt.pickup(), "pickup %d" % i)
		t.ok(tt.release(SWISH_LAUNCH), "release %d" % i)
		_tick_seconds(tt, 3.0)
	tt.pickup()
	tt.release(BRICK_LAUNCH)
	_tick_seconds(tt, 3.0)
	t.eq(tt.attempts, 4, "attempts")
	t.eq(tt.makes, 3, "makes")
	t.eq(tt.swishes, 3, "swishes")
	t.eq(tt.score, 6, "score")
	t.eq(tt.best_streak, 3, "best streak")
	t.eq(tt.streak, 0, "brick broke the streak")
	t.eq(tt.score, 2 * tt.swishes + (tt.makes - tt.swishes), "totals coherent below the tiers")
	t.eq(tt.bonus_points, 0, "no streak bonus under 6 straight")


func _streak_tiers(t) -> void:
	# 11 swishes in a row: 2 2 2 2 2 | 3 3 | 4 4 4 | 5 = 33, bonus 11.
	var tt := TimeTrial.new()
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	var seen_points: Array[int] = []
	var seen_streaks: Array[int] = []
	for i in 11:
		t.ok(tt.pickup(), "tier pickup %d" % i)
		t.ok(tt.release(SWISH_LAUNCH), "tier release %d" % i)
		_tick_seconds(tt, 3.0)
		for ev in tt.drain_events():
			if ev["kind"] == "outcome":
				seen_points.push_back(int(ev["outcome"]["points"]))
				seen_streaks.push_back(int(ev["outcome"]["streak"]))
				t.eq(int(ev["outcome"]["base_points"]), 2, "swish base stays 2")
	t.eq(seen_points, [2, 2, 2, 2, 2, 3, 3, 4, 4, 4, 5], "points per make climb with the streak")
	t.eq(seen_streaks, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], "outcome carries the streak after the make")
	t.eq(tt.score, 33, "tiered total")
	t.eq(tt.bonus_points, 11, "bonus above the plain rule")
	t.eq(tt.swishes, 11, "swish counter keyed on type, not points")
	t.eq(tt.best_streak, 11, "best streak")
	tt.pickup()
	tt.release(BRICK_LAUNCH)
	_tick_seconds(tt, 3.0)
	var broke := -1
	for ev in tt.drain_events():
		if ev["kind"] == "outcome":
			broke = int(ev["outcome"].get("streak_broken", -1))
	t.eq(broke, 11, "miss reports the streak it broke")
	t.eq(tt.streak, 0, "miss resets the streak")
	t.eq(tt.score, 33, "miss scores nothing")


## A fire card lights the rim from FIRE_AT for a window; makes stack tiers,
## the clock or a miss puts it out and resets the streak.
func _card_fire(t) -> void:
	var tt := TimeTrial.new()
	t.ok(not tt.light_rim(7.0), "no card fire during the countdown")
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	tt.drain_events()
	t.ok(tt.light_rim(7.0), "card lights the rim")
	t.ok(tt.fire_card, "card fire on")
	t.eq(tt.streak, StreakRules.FIRE_AT, "streak jumps to FIRE_AT")
	t.close(tt.fire_left(), 7.0, 0.01, "seven seconds on the card")
	t.ok(_has_kind(tt.drain_events(), "fire_on"), "fire_on event")
	t.ok(not tt.light_rim(7.0), "no second card while burning")
	var pts := []
	for i in 3:
		t.ok(tt.pickup() and tt.release(SWISH_LAUNCH), "card-fire shot %d" % i)
		_tick_seconds(tt, 1.6)
		for ev in tt.drain_events():
			if ev["kind"] == "outcome":
				pts.push_back(int(ev["outcome"]["points"]))
	t.eq(pts, [3, 3, 4], "swishes pay the hot tiers (2+1, 2+1, 3+1)")
	t.eq(tt.streak, 8, "streak stacked to 8")
	t.ok(tt.fire_card and tt.fire_left() > 0.0, "still burning inside the window (%.2f s left)" % tt.fire_left())
	_tick_seconds(tt, 3.0)
	t.ok(not tt.fire_card, "window closed")
	t.eq(tt.streak, 3, "the card's loan is withdrawn; the three makes stay a (cold) streak")
	t.eq(tt.fire_left(), 0.0, "no time left")
	var offs := []
	for ev in tt.drain_events():
		if ev["kind"] == "fire_off":
			offs.push_back(ev["reason"])
	t.eq(offs, ["time"], "fire_off by time")
	t.ok(tt.pickup() and tt.release(SWISH_LAUNCH), "plain shot after")
	_tick_seconds(tt, 1.6)
	for ev in tt.drain_events():
		if ev["kind"] == "outcome":
			t.eq(int(ev["outcome"]["points"]), 2, "back to plain swish points")
	# A miss puts it out at once.
	var tt2 := TimeTrial.new()
	_tick_seconds(tt2, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.ok(tt2.light_rim(7.0), "second trial lit")
	t.ok(tt2.pickup() and tt2.release(BRICK_LAUNCH), "brick under card fire")
	_tick_seconds(tt2, 3.0)
	t.ok(not tt2.fire_card, "miss put the card fire out")
	t.eq(tt2.streak, 0, "streak reset by the miss")
	var reasons := []
	for ev in tt2.drain_events():
		if ev["kind"] == "fire_off":
			reasons.push_back(ev["reason"])
	t.eq(reasons, ["miss"], "fire_off by miss")
	# Refused while already lit, and while iced; ice puts a card fire out.
	var tt3 := TimeTrial.new()
	_tick_seconds(tt3, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	tt3.streak = 6
	t.ok(not tt3.light_rim(7.0), "no card on a rim that is already on fire")
	tt3.streak = 0
	t.ok(tt3.freeze_rim("card"), "ice it")
	t.ok(not tt3.light_rim(7.0), "no fire card on an iced rim")
	var tt4 := TimeTrial.new()
	_tick_seconds(tt4, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.ok(tt4.light_rim(7.0), "lit")
	tt4.freeze_rim("card")
	t.ok(not tt4.fire_card and tt4.streak == 0, "ice puts the card fire out")
	# A ball in the air when the window closes still lands hot.
	var tt5 := TimeTrial.new()
	_tick_seconds(tt5, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.ok(tt5.light_rim(0.5), "half-second card")
	t.ok(tt5.pickup() and tt5.release(SWISH_LAUNCH), "release inside the window")
	_tick_seconds(tt5, 3.0)
	var hot_pts := -1
	for ev in tt5.drain_events():
		if ev["kind"] == "outcome":
			hot_pts = int(ev["outcome"]["points"])
	t.eq(hot_pts, 3, "the in-flight shot still paid the hot tier")
	t.ok(not tt5.fire_card and tt5.streak == 1, "then the window closed; the one make under it stays a streak")
	# A ball shot BEFORE the card, missing after it lit, does not put it out (Ross, 2026-10-25).
	var tt6 := TimeTrial.new()
	_tick_seconds(tt6, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	for i in 2:
		tt6.pickup()
		tt6.release(SWISH_LAUNCH)
		_tick_seconds(tt6, 1.6)
	t.eq(tt6.streak, 2, "a streak of two before the card")
	tt6.drain_events()
	t.ok(tt6.pickup() and tt6.release(BRICK_LAUNCH), "a brick in the air…")
	t.ok(tt6.light_rim(7.0), "…and the fire card played before it lands")
	_tick_seconds(tt6, 1.6)
	var stale := {}
	var stale_offs := []
	for ev in tt6.drain_events():
		if ev["kind"] == "outcome":
			stale = ev["outcome"]
		elif ev["kind"] == "fire_off":
			stale_offs.push_back(ev["reason"])
	t.ok(not bool(stale.get("made", true)) and bool(stale.get("fire_kept", false)), "the brick lands a miss, the card's fire kept")
	t.eq(int(stale.get("streak_broken", -1)), 2, "…it breaks the streak the card found")
	t.ok(tt6.fire_card and stale_offs.is_empty() and tt6.streak == StreakRules.FIRE_AT, "the rim burns on at FIRE_AT")
	t.eq(tt6.miss_streak, 1, "…the miss still counts toward the cold streak")
	tt6.pickup()
	tt6.release(SWISH_LAUNCH)
	_tick_seconds(tt6, 1.6)
	t.eq(tt6.streak, StreakRules.FIRE_AT + 1, "a make under the card stacks")
	_tick_seconds(tt6, 6.0)
	t.ok(not tt6.fire_card and tt6.streak == 1, "the window closes: the make under it stays a streak of one")
	# …while a miss shot under the card still puts it out (tt2 above).


## Overtime period: the arena resets (balls gone, hoop home, no board slide or
## shuffle), the score and streak carry, and play opens on a countdown.
func _start_period(t) -> void:
	var tt := TimeTrial.new()
	tt.board_motion = true
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	_tick_seconds(tt, TimeTrial.TIME_TRIAL_SECONDS - 1.5)
	t.ok(tt.moving, "board sliding late in regulation")
	t.ok(tt.pickup() and tt.release(BRICK_LAUNCH), "airball just before the buzzer")
	_tick_seconds(tt, 1.7)
	t.eq(tt.phase, TimeTrial.PHASE_DONE, "regulation done (the airball resolved on the floor)")
	t.ok(tt.balls().size() > 0, "the ball is still bouncing at the end")
	tt.streak = 4
	tt.score = 7
	var streak0 := tt.streak
	var score0 := tt.score
	tt.drain_events()
	tt.start_period(20.0, true)
	t.ok(tt.overtime, "flagged overtime")
	t.eq(tt.phase, TimeTrial.PHASE_COUNTDOWN, "OT opens on the countdown")
	t.eq(tt.balls().size(), 0, "arena cleared for OT")
	t.eq(tt.streak, streak0, "streak carries into OT")
	t.eq(tt.score, score0, "score carries into OT")
	t.ok(not tt.moving, "board parked for OT")
	t.close(tt.geo.hoop_x, tt.base_geo.hoop_x, 1e-9, "hoop back at home depth")
	t.close(tt.geo.hoop_z, tt.base_geo.hoop_z, 1e-9, "hoop back at home lateral")
	t.ok(not tt.pickup(), "no pickup during the OT countdown")
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	var evs := tt.drain_events()
	t.ok(_has_kind(evs, "go"), "GO after the OT countdown")
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "OT running")
	t.ok(tt.pickup(), "pickup allowed once OT runs")
	tt.drop()
	_tick_seconds(tt, 15.0)
	t.ok(not tt.moving, "no board slide in overtime")
	t.ok(not _has_kind(tt.drain_events(), "heat_up"), "no heat_up in overtime")


func _kinds(events: Array) -> Array:
	var out := []
	for ev in events:
		out.push_back(ev["kind"])
	return out


func _bricks(tt: TimeTrial, n: int) -> void:
	for i in n:
		tt.pickup()
		tt.release(BRICK_LAUNCH)
		_tick_seconds(tt, 3.0)


## A launch that goes in off the iron (MAKE / BANK / SHOOTERS_ROLL) on a
## fresh trial — deterministic scan around the ideal arc.
func _rattled_make_launch() -> Dictionary:
	for angle in [52.0, 48.0, 56.0, 45.0, 60.0]:
		var ideal := Ballistics.ideal_launch(angle)
		for k in [1.02, 0.98, 1.04, 0.96, 1.06, 0.94, 1.08, 0.92, 1.1, 0.9]:
			var launch := {"angle_deg": angle, "speed": ideal["speed"] * k}
			var out := ShotSim.simulate_shot(launch)
			if out["made"] and out["type"] != ShotClassify.SWISH:
				return launch
	return {}


func _cold_streak(t) -> void:
	var tt := TimeTrial.new()
	tt.endless = true   # four freezes of COLD_AT bricks outrun the 60 s clock
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	tt.drain_events()
	# COLD_AT bricks → iced over, announced once.
	for i in StreakRules.COLD_AT:
		tt.pickup()
		tt.release(BRICK_LAUNCH)
		_tick_seconds(tt, 3.0)
		var evs := tt.drain_events()
		var last := i == StreakRules.COLD_AT - 1
		t.eq(tt.iced, last, "iced only after miss %d (%d)" % [StreakRules.COLD_AT, i + 1])
		t.eq(_kinds(evs).has("ice_on"), last, "ice_on event on the last miss only (%d)" % (i + 1))
	t.eq(tt.miss_streak, StreakRules.COLD_AT, "miss streak")
	t.eq(tt.times_iced, 1, "times iced")
	t.ok(tt.geo.ice, "live geometry carries the ice")
	# A swish while iced passes through, scores normally and breaks the ice.
	var score0 := tt.score
	tt.pickup()
	tt.release(SWISH_LAUNCH)
	_tick_seconds(tt, 3.0)
	var evs_sw := tt.drain_events()
	var out_sw := {}
	var broke_sw := ""
	for ev in evs_sw:
		if ev["kind"] == "outcome":
			out_sw = ev["outcome"]
		elif ev["kind"] == "ice_break":
			broke_sw = ev["by"]
	t.eq(out_sw.get("type", ""), ShotClassify.SWISH, "swish through the ice is a swish")
	t.eq(int(out_sw.get("points", 0)), 2, "swish through the ice pays 2")
	t.eq(out_sw.get("ice_broken", ""), "swish", "outcome tagged ice_broken by swish")
	t.eq(tt.score, score0 + 2, "score counts the swish")
	t.eq(tt.streak, 1, "streak starts from the swish")
	t.eq(broke_sw, "swish", "ice broke by swish")
	t.ok(not tt.iced and not tt.geo.ice, "ice gone after the swish")
	t.eq(tt.miss_streak, 0, "miss streak reset")
	# Re-ice; a rattled-in make is caught, held, popped, and scores nothing.
	var rattled := _rattled_make_launch()
	t.ok(not rattled.is_empty(), "found a rattled-in make launch")
	_bricks(tt, StreakRules.COLD_AT)
	tt.drain_events()
	t.ok(tt.iced, "iced again")
	t.eq(tt.times_iced, 2, "times iced counts")
	var score1 := tt.score
	var makes1 := tt.makes
	tt.pickup()
	tt.release(rattled)
	var ball: BallState = tt.balls()[0]
	var caught_at := -1.0
	var lowest := INF
	var was_above := false
	for i in ceili(5.0 / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)
		was_above = was_above or ball.pos.y > tt.geo.hoop_y
		if was_above and not ball.ice_popped:
			lowest = minf(lowest, ball.pos.y)   # the descent onto the rim, before the pop
		if ball.ice_caught and caught_at < 0.0:
			caught_at = ball.t
			t.ok(tt.iced, "still iced at the catch")
	var evs2 := tt.drain_events()
	var kinds2 := _kinds(evs2)
	var outcome := {}
	var broke_by := ""
	for ev in evs2:
		if ev["kind"] == "outcome":
			outcome = ev["outcome"]
		elif ev["kind"] == "ice_break":
			broke_by = ev["by"]
	t.ok(caught_at > 0.0, "the ice caught the rattled ball")
	t.ok(kinds2.has("ice_caught"), "ice_caught event (%s)" % str(kinds2))
	t.ok(lowest > tt.geo.hoop_y - 0.05, "the ball never dropped through the rim (lowest %.2f vs rim %.2f)" % [lowest, tt.geo.hoop_y])
	t.ok(ball.ice_popped, "popped back out")
	t.ok(ball.settled and ball.pos.y < 0.3, "popped ball ends on the floor (y %.2f)" % ball.pos.y)
	t.ok(ball.pos.x < tt.geo.hoop_x - 0.5, "popped toward the shooter (x %.2f)" % ball.pos.x)
	t.eq(outcome.get("type", ""), ShotClassify.ICE_CAUGHT, "outcome type ICE_CAUGHT")
	t.ok(not outcome.get("made", true), "not a make")
	t.ok(outcome.get("iced_out", false), "flagged iced_out")
	t.eq(int(outcome.get("points", -1)), 0, "caught make pays nothing")
	t.eq(tt.score, score1, "score unchanged")
	t.eq(tt.makes, makes1, "not counted as a make")
	t.eq(tt.streak, 0, "streak stays at 0")
	t.eq(broke_by, "make", "ice broke by the make (pop)")
	t.ok(not tt.iced and not tt.geo.ice, "ice gone")
	t.eq(tt.miss_streak, 0, "miss streak reset")
	# Re-ice, then three rim hits break it (hook driven).
	_bricks(tt, StreakRules.COLD_AT)
	tt.drain_events()
	t.ok(tt.iced, "iced a third time")
	t.eq(tt.times_iced, 3, "times iced counts")
	tt._ice_rim_hit()
	tt._ice_rim_hit()
	var kinds := _kinds(tt.drain_events())
	t.eq(kinds.count("ice_crack"), 2, "two cracks (%s)" % str(kinds))
	t.ok(tt.iced, "still iced after two hits")
	tt._ice_rim_hit()
	kinds = _kinds(tt.drain_events())
	t.ok(kinds.has("ice_break"), "third hit breaks the ice")
	t.ok(not tt.iced, "ice gone after three hits")
	t.eq(tt.ice_hits, 0, "hits reset")
	# Sim-driven: a shot that clips the rim while iced counts its rim contacts.
	_bricks(tt, StreakRules.COLD_AT)
	tt.drain_events()
	t.ok(tt.iced, "iced a fourth time")
	var found := false
	for k in [0.97, 0.98, 0.99, 1.01, 1.02, 1.03, 0.96, 1.04, 0.95, 1.05]:
		var probe := TimeTrial.new()
		_tick_seconds(probe, TimeTrial.COUNTDOWN_SECONDS + 0.05)
		probe.pickup()
		probe.release({"angle_deg": SWISH_LAUNCH["angle_deg"], "speed": SWISH_LAUNCH["speed"] * k})
		_tick_seconds(probe, 3.0)
		var rim_hits := 0
		var made := false
		for ev in probe.drain_events():
			if ev["kind"] == "contact" and ev["contact"]["kind"] == "rim":
				rim_hits += 1
			elif ev["kind"] == "outcome":
				made = ev["outcome"]["made"]
		if rim_hits > 0 and rim_hits < 3 and not made:
			found = true
			var hits0 := tt.ice_hits
			tt.pickup()
			tt.release({"angle_deg": SWISH_LAUNCH["angle_deg"], "speed": SWISH_LAUNCH["speed"] * k})
			_tick_seconds(tt, 3.0)
			tt.drain_events()
			t.eq(tt.ice_hits, hits0 + rim_hits, "rim contacts in flight chip the ice (%d)" % rim_hits)
			break
	t.ok(found, "found a rim-clipping miss for the sim-driven check")


func _rapid_fire(t) -> void:
	var tt := TimeTrial.new()
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	for i in 3:
		t.ok(tt.pickup(), "rapid pickup %d" % i)
		t.ok(tt.release(SWISH_LAUNCH), "rapid release %d" % i)
		_tick_seconds(tt, 0.3)
	t.ok(tt.balls().size() >= 2, "genuinely overlapping flights (%d)" % tt.balls().size())
	_tick_seconds(tt, 4.0)
	t.eq(tt.makes, 3, "all three rapid shots score")
	t.eq(tt.score, 6, "rapid fire score")


func _buzzer_beater(t) -> void:
	var tt := TimeTrial.new()
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	_tick_seconds(tt, TimeTrial.TIME_TRIAL_SECONDS - 0.4)
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "still running with 0.4s left")
	t.ok(tt.pickup(), "pickup before buzzer")
	t.ok(tt.release(SWISH_LAUNCH), "release before buzzer")
	_tick_seconds(tt, 0.6)
	t.eq(tt.phase, TimeTrial.PHASE_FINISHING, "finishing while ball is up")
	t.ok(not tt.pickup(), "no pickups after buzzer")
	_tick_seconds(tt, 4.0)
	t.eq(tt.phase, TimeTrial.PHASE_DONE, "done after last ball lands")
	t.eq(tt.score, 2, "buzzer beater counts")
	t.eq(tt.makes, 1, "buzzer beater is a make")


func _slow_shooter(t) -> void:
	var tt := TimeTrial.new()
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + TimeTrial.TIME_TRIAL_SECONDS + 0.1)
	t.eq(tt.phase, TimeTrial.PHASE_DONE, "empty hands buzzer → done immediately")
	t.eq(tt.attempts, 0, "no attempts")
	t.eq(tt.score, 0, "no score")


func _holding_at_buzzer(t) -> void:
	var tt := TimeTrial.new()
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	_tick_seconds(tt, TimeTrial.TIME_TRIAL_SECONDS - 0.2)
	tt.pickup()
	_tick_seconds(tt, 0.4)
	t.ok(not tt.release(SWISH_LAUNCH), "holding at buzzer loses the ball")
	t.eq(tt.attempts, 0, "no free release")
	t.eq(tt.phase, TimeTrial.PHASE_DONE, "done")


func run_endless(t) -> void:
	var tt := TimeTrial.new(SimGeometry.arcade(2.9))
	tt.endless = true
	tt.tick(0.1)
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "endless skips the countdown")
	var saw_go := false
	for ev in tt.drain_events():
		if ev["kind"] == "go":
			saw_go = true
	t.ok(saw_go, "endless still emits go once")
	var before := tt.time_left
	for i in 700:
		tt.tick(0.1)   # 70 s of play, longer than a whole trial
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "endless never finishes")
	t.close(tt.time_left, before, 0.0, "endless clock does not run down")
	var buzzed := false
	for ev in tt.drain_events():
		if ev["kind"] == "buzzer":
			buzzed = true
	t.ok(not buzzed, "endless never buzzes")
	t.ok(tt.pickup(), "can still pick up in endless")
	t.ok(tt.release({"angle_deg": 48.0, "speed": 6.0}), "can still shoot in endless")
	t.eq(tt.attempts, 1, "attempts count in endless")



## The magnet card (docs/CARDS.md): a timed self window on the city rim, and
## the streak rules under it (Ross, 2026-10-23): makes never build the
## streak, a real miss still breaks it, the counter you had is kept.
func _card_magnet(t) -> void:
	var g := SimGeometry.city()
	var tt := TimeTrial.new(g)
	t.ok(not tt.magnetize_rim(6.0, 0.35), "no magnet during the countdown")
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	tt.drain_events()
	t.ok(tt.magnetize_rim(6.0, 0.35), "the card magnetises the rim")
	t.ok(tt.magnet_card and tt.geo.magnet and tt.geo.magnet_pull_m == 0.35, "magnet on, on the live geometry, with the threshold")
	t.close(tt.magnet_left(), 6.0, 0.01, "six seconds on the card")
	t.ok(_has_kind(tt.drain_events(), "magnet_on"), "magnet_on event")
	t.ok(not tt.magnetize_rim(6.0), "no second card while it hangs")
	# A miss does not end it (nothing to "break": it is a make-rate window).
	var airball := Ballistics.ideal_launch_for(52.0, g)
	airball["speed"] = airball["speed"] * 0.8
	t.ok(tt.pickup() and tt.release(airball), "brick under the magnet")
	_tick_seconds(tt, 2.5)
	t.ok(tt.magnet_card, "a miss leaves the magnet on")
	for ev in tt.drain_events():
		if ev["kind"] == "outcome":
			t.ok(not ev["outcome"]["made"] and not ev["outcome"].get("magnet", false), "an airball is not pulled in")
	_tick_seconds(tt, 4.0)
	t.ok(not tt.magnet_card and not tt.geo.magnet, "window closed on the clock")
	t.eq(tt.magnet_left(), 0.0, "no time left")
	var offs := []
	for ev in tt.drain_events():
		if ev["kind"] == "magnet_off":
			offs.push_back(ev["reason"])
	t.eq(offs, ["time"], "magnet_off by time")
	# Ice ends it.
	var tt2 := TimeTrial.new(g)
	_tick_seconds(tt2, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.ok(tt2.magnetize_rim(6.0), "second trial magnetised")
	t.ok(tt2.freeze_rim(), "then iced")
	t.ok(tt2.iced and not tt2.magnet_card and tt2.geo.ice and not tt2.geo.magnet, "the ice wins")
	var reasons := []
	for ev in tt2.drain_events():
		if ev["kind"] == "magnet_off":
			reasons.push_back(ev["reason"])
	t.eq(reasons, ["ice"], "magnet_off by ice")
	t.ok(not tt2.magnetize_rim(6.0), "no magnet on an iced rim")
	# The last ball of the window still counts: a ball in the air at the
	# deadline keeps the magnet until it lands.
	var tt3 := TimeTrial.new(g)
	_tick_seconds(tt3, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.ok(tt3.magnetize_rim(0.5), "a half-second window")
	t.ok(tt3.pickup() and tt3.release(Ballistics.ideal_launch_for(52.0, g)), "shot on release")
	_tick_seconds(tt3, 0.6)
	t.ok(tt3.magnet_card, "still on with a ball in the air past the deadline")
	_tick_seconds(tt3, 2.5)
	t.ok(not tt3.magnet_card, "closed once it landed")
	_magnet_streak(t, g)


## The sweep finds launches by what they do on the plain city rim.
func _find_launch(g: SimGeometry, want: String) -> Dictionary:
	for a in range(48, 57, 2):
		var ideal: float = Ballistics.speed_for_angle(a, g.hoop_x, g.rise)
		for k in range(-8, 9):
			var launch := {"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k)}
			var p := ShotSim.run_shot(launch, false, g)
			var reach := ShotSim.first_reach(p)
			var type := str(ShotClassify.classify_shot(p)["type"])
			match want:
				"swish":
					if type == ShotClassify.SWISH:
						return launch
				"near":
					if not p.made and float(reach["t"]) >= 0.0 and float(reach["hd"]) <= 0.35:
						return launch
				"wide":
					if not p.made and (float(reach["t"]) < 0.0 or float(reach["hd"]) > 0.35):
						return launch
	return {}


func _shoot(tt: TimeTrial, launch: Dictionary) -> Dictionary:
	tt.pickup()
	tt.release(launch)
	_tick_seconds(tt, 2.6)
	for ev in tt.drain_events():
		if ev["kind"] == "outcome":
			return ev["outcome"]
	return {}


## The streak under the magnet: frozen against building, paid at the tier
## you had, broken by a real miss, kept once the window closes.
func _magnet_streak(t, g: SimGeometry) -> void:
	var swish := _find_launch(g, "swish")
	var near := _find_launch(g, "near")
	var wide := _find_launch(g, "wide")
	t.ok(not swish.is_empty() and not near.is_empty() and not wide.is_empty(), "the sweep found a swish, a near miss and a wide miss")
	var tt := TimeTrial.new(g)
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	_shoot(tt, swish)
	_shoot(tt, swish)
	t.eq(tt.streak, 2, "two makes: streak 2")
	t.ok(tt.magnetize_rim(30.0, 0.35), "play the magnet at streak 2")
	tt.drain_events()
	var o1 := _shoot(tt, swish)
	t.ok(bool(o1["made"]) and o1["type"] == ShotClassify.SWISH and not o1["magnet"], "a swish under the magnet still swishes")
	t.ok(bool(o1.get("streak_frozen", false)), "…flagged as a frozen-streak make")
	t.eq(int(o1["points"]), StreakRules.points_for(2, true), "…paid at the streak you had (2)")
	t.eq(tt.streak, 2, "the streak did not build")
	var o2 := _shoot(tt, near)
	t.ok(bool(o2["made"]) and o2["magnet"] and int(o2["points"]) == StreakRules.points_for(2, false) and o2["type"] != ShotClassify.SWISH, "a near miss is zapped in, never a swish, paid at the frozen tier")
	t.eq(tt.streak, 2, "still 2 after the zap")
	_shoot(tt, swish)
	t.eq(tt.streak, 2, "still 2 after a third make")
	t.eq(tt.makes, 5, "the makes still count as makes")
	var before_best := tt.best_streak
	# A real miss under the magnet breaks it.
	var o3 := _shoot(tt, wide)
	t.ok(not bool(o3["made"]) and not o3["magnet"], "a wide miss is a miss under the magnet")
	t.eq(tt.streak, 0, "…and it breaks the streak")
	t.eq(int(o3["streak_broken"]), 2, "the broken streak was the frozen 2")
	t.eq(tt.best_streak, before_best, "best streak untouched by the window")
	# Keep what you had once the window closes.
	var tt2 := TimeTrial.new(g)
	_tick_seconds(tt2, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	_shoot(tt2, swish)
	_shoot(tt2, swish)
	t.ok(tt2.magnetize_rim(1.0, 0.35), "a short magnet at streak 2")
	_shoot(tt2, swish)
	_tick_seconds(tt2, 1.5)
	t.ok(not tt2.magnet_card, "the window closed")
	t.eq(tt2.streak, 2, "the streak you had before the card is kept")
	var o4 := _shoot(tt2, swish)
	t.ok(not o4.has("streak_frozen"), "a make after the window is a normal make")
	t.eq(tt2.streak, 3, "…and builds again")
	# Fire then magnet: the lent streak stays where it is.
	var tt3 := TimeTrial.new(g)
	_tick_seconds(tt3, TimeTrial.COUNTDOWN_SECONDS + 0.05)
	t.ok(tt3.light_rim(30.0), "fire lit")
	t.eq(tt3.streak, StreakRules.FIRE_AT, "the fire lends FIRE_AT")
	t.ok(tt3.magnetize_rim(30.0, 0.35), "then the magnet")
	var o5 := _shoot(tt3, swish)
	t.eq(int(o5["points"]), StreakRules.points_for(StreakRules.FIRE_AT, true), "a make pays at the fire's tier")
	t.eq(tt3.streak, StreakRules.FIRE_AT, "…but the streak does not climb under the magnet")
	t.ok(tt3.fire_card and tt3.magnet_card, "both cards stay on")
