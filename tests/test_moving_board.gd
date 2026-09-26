extends RefCounted
## Moving-board difficulty phase: opt-in flag, phase timing, continuity,
## range, determinism, per-ball geometry freeze, and the base-anchored skill
## model (flick mapping must NOT track the live board).


func _tick_seconds(tt: TimeTrial, seconds: float) -> void:
	for i in ceili(seconds / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)


func run(t) -> void:
	_with_distance(t)
	_force_and_stop(t)
	_with_pose(t)
	_opt_in_and_timing(t)
	_range_and_determinism(t)
	_freeze_and_skill(t)
	_gameplay_reality(t)


func _with_distance(t) -> void:
	var g := SimGeometry.arcade().with_distance(3.1)
	t.close(g.hoop_x, 3.1, 1e-12, "with_distance sets hoop_x")
	t.close(g.hoop_y, 2.44, 1e-12, "rim height preserved")
	t.close(g.release_h, 1.85, 1e-12, "release preserved")
	t.close(g.board_half_w, 0.61, 1e-12, "board width preserved")
	t.close(g.board_x, 3.1 + SimConstants.BOARD_OFFSET, 1e-12, "board_x re-derived")
	t.close(g.bracket_x0, 3.1 + SimConstants.R_RIM - 0.01, 1e-12, "bracket re-derived")
	t.close(g.rise, 0.59, 1e-12, "rise unchanged (height-derived)")


func _with_pose(t) -> void:
	var g := SimGeometry.arcade().with_pose(3.1, 0.25)
	t.close(g.hoop_x, 3.1, 1e-12, "with_pose sets hoop_x")
	t.close(g.hoop_z, 0.25, 1e-12, "with_pose sets hoop_z")
	t.close(g.hoop_y, 2.44, 1e-12, "pose keeps rim height")
	t.close(g.release_h, 1.85, 1e-12, "pose keeps release")
	t.close(g.board_half_w, 0.61, 1e-12, "pose keeps board width")
	t.close(g.board_x, 3.1 + SimConstants.BOARD_OFFSET, 1e-12, "pose re-derives board_x")
	t.close(g.rim_e, SimGeometry.ARCADE_RIM_E, 1e-12, "pose keeps arcade rim materials")
	t.close(g.with_distance(3.0).hoop_z, 0.25, 1e-12, "with_distance keeps the lateral offset")
	t.ok(SimGeometry.regulation().hoop_z == 0.0, "regulation hoop_z is exactly 0")
	t.ok(SimGeometry.arcade().hoop_z == 0.0, "arcade hoop_z is exactly 0")


func _opt_in_and_timing(t) -> void:
	# Off by default: regulation trial keeps a stationary hoop forever.
	var plain := TimeTrial.new()
	_tick_seconds(plain, TimeTrial.COUNTDOWN_SECONDS + 40.0)
	t.ok(not plain.moving, "motion is opt-in (off by default)")
	t.close(plain.geo.hoop_x, SimConstants.HOOP_X, 1e-12, "regulation hoop never moves")
	t.ok(plain.geo.hoop_z == 0.0, "regulation hoop never slides sideways")

	# Opt-in arcade trial: fixed until 30 s left, then moving + one heat_up.
	var tt := TimeTrial.new(SimGeometry.arcade())
	tt.board_motion = true
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 29.9)
	t.ok(not tt.moving, "board fixed in the first half")
	t.close(tt.geo.hoop_x, 2.6, 1e-12, "distance still base before the phase")
	var heat_ups := 0
	for ev in tt.drain_events():
		if ev["kind"] == "heat_up":
			heat_ups += 1
	t.eq(heat_ups, 0, "no heat_up before 30s left")

	_tick_seconds(tt, 0.2)  # cross the threshold
	t.ok(tt.moving, "moving flips at 30s left")
	# Continuity: just after the transition the board is still ≈ base.
	t.ok(absf(tt.geo.hoop_x - 2.6) < 0.05, "no jump at transition (%.3f)" % tt.geo.hoop_x)
	t.ok(absf(tt.geo.hoop_z) < 0.15, "lateral continuous at transition, ≤0.63 m/s × 0.2 s (%.3f)" % tt.geo.hoop_z)
	for ev in tt.drain_events():
		if ev["kind"] == "heat_up":
			heat_ups += 1
	t.eq(heat_ups, 1, "heat_up fires exactly once")
	_tick_seconds(tt, 5.0)
	for ev in tt.drain_events():
		if ev["kind"] == "heat_up":
			heat_ups += 1
	t.eq(heat_ups, 1, "heat_up never repeats")


func _range_and_determinism(t) -> void:
	var a := TimeTrial.new(SimGeometry.arcade())
	a.board_motion = true
	var b := TimeTrial.new(SimGeometry.arcade())
	b.board_motion = true
	_tick_seconds(a, TimeTrial.COUNTDOWN_SECONDS + 30.0)
	_tick_seconds(b, TimeTrial.COUNTDOWN_SECONDS + 30.0)

	var lo := INF
	var hi := -INF
	var lo_z := INF
	var hi_z := -INF
	var edge := 0.0
	var identical := true
	# Sample the remaining 29+ s of the moving phase at 0.25 s.
	for i in 116:
		_tick_seconds(a, 0.25)
		_tick_seconds(b, 0.25)
		lo = minf(lo, a.geo.hoop_x)
		hi = maxf(hi, a.geo.hoop_x)
		lo_z = minf(lo_z, a.geo.hoop_z)
		hi_z = maxf(hi_z, a.geo.hoop_z)
		edge = maxf(edge, absf(a.geo.hoop_z) + a.geo.board_half_w)
		if a.geo.hoop_x != b.geo.hoop_x or a.geo.hoop_z != b.geo.hoop_z:
			identical = false
	t.ok(lo_z >= -TimeTrial.LATERAL_AMP - 1e-9 and hi_z <= TimeTrial.LATERAL_AMP + 1e-9,
		"lateral stays within ±%.1f (%.3f..%.3f)" % [TimeTrial.LATERAL_AMP, lo_z, hi_z])
	t.ok(hi_z > 0.35 and lo_z < -0.35, "both lateral extremes reached")
	t.ok(edge <= 1.05, "board edge stays inside the cage/frustum (%.3f)" % edge)
	t.ok(lo >= TimeTrial.BOARD_NEAR - 1e-9, "board never nearer than %.1f (%.3f)" % [TimeTrial.BOARD_NEAR, lo])
	t.ok(hi <= TimeTrial.BOARD_FAR + 1e-9, "board never farther than %.1f (%.3f)" % [TimeTrial.BOARD_FAR, hi])
	t.ok(lo < 2.45, "near extreme actually approached (%.3f)" % lo)
	t.ok(hi > 3.35, "far extreme actually approached (%.3f)" % hi)
	t.ok(identical, "board path is deterministic")


func _freeze_and_skill(t) -> void:
	var tt := TimeTrial.new(SimGeometry.arcade())
	tt.board_motion = true
	_tick_seconds(tt, TimeTrial.COUNTDOWN_SECONDS + 33.0)  # 3 s into motion
	tt.pickup()
	var launch_dist := tt.geo.hoop_x
	tt.release(Ballistics.ideal_launch_for(55.0, tt.geo))
	var ball := tt.balls()[0]
	_tick_seconds(tt, 1.0)
	t.ok(tt.geo.hoop_x != launch_dist, "live board kept moving meanwhile")
	t.ok(ball.geo == tt.geo, "in-flight ball collides with the LIVE hoop, not a frozen one")

	# Leading the hoop: aim at where it will be when the ball lands and it goes in.
	var lead_makes := 0
	var frozen_misses := 0
	for k in 6:
		var tl := TimeTrial.new(SimGeometry.arcade(2.9))
		tl.board_motion = true
		_tick_seconds(tl, TimeTrial.COUNTDOWN_SECONDS + 31.0 + 1.3 * k)
		var now := tl.geo
		var ideal := Ballistics.ideal_launch_for(52.0, now)
		var ft: float = Ballistics.flight_time(52.0, ideal["speed"], now.hoop_x)
		var lead := tl.geo_in(ft)
		var slant := sqrt(lead.hoop_x * lead.hoop_x + lead.hoop_z * lead.hoop_z)
		var v := Ballistics.speed_for_angle(52.0, slant, lead.rise)
		var launch := {"angle_deg": 52.0, "speed": v, "rx": 0.0, "ry": lead.release_h, "rz": 0.0,
			"bx": lead.hoop_x / slant, "bz": lead.hoop_z / slant}
		tl.pickup()
		tl.release(launch)
		_tick_seconds(tl, 3.0)
		if tl.makes == 1:
			lead_makes += 1
		# The same shot judged against the frozen release pose would have been a
		# plain make; judged live it can miss — that asymmetry is the old bug.
		var frozen := ShotSim.simulate_shot(launch, false, lead)
		if not frozen["made"]:
			frozen_misses += 1
	t.ok(lead_makes >= 4, "shots that lead the hoop go in against the live rim (%d/6)" % lead_makes)
	t.eq(frozen_misses, 0, "the led launches are dead-centre for their target pose")
	var a := TimeTrial.new(SimGeometry.arcade(2.9))
	a.board_motion = true
	_tick_seconds(a, TimeTrial.COUNTDOWN_SECONDS + 35.0)
	t.ok(a.pose_at(5.0).hoop_x == a.pose_at(5.0).hoop_x and a.geo_in(0.0).hoop_z == a.geo.hoop_z, "geo_in(0) is the current pose")

	# Mapping is a pure function of the geo it is handed (the screen hands it
	# the LIVE hoop pose): the same flick aimed at a slid hoop solves for the
	# slant distance and bears toward the offset.
	var tuning := FlickTuning.new()
	var sample := {
		"vel_x": 0.0, "vel_y": -2300.0, "travel_x": 0.0, "travel_y": -380.0,
		"duration_s": 0.15, "viewport_h": 1280.0,
	}
	var near := FlickMap.map_flick(sample, tuning, SimGeometry.arcade())
	var again := FlickMap.map_flick(sample, tuning, SimGeometry.arcade())
	t.eq(JSON.stringify(near), JSON.stringify(again), "same sample + same geo → identical launch")
	var slid := SimGeometry.arcade(2.9).with_pose(3.3, 0.35)
	var wsample := {
		"vel_x": 0.0, "vel_y": -2300.0, "travel_x": 0.0, "travel_y": -380.0, "pos_x": 360.0, "pos_y": 900.0,
		"curl": 0.0, "pull_px": 200.0, "path_px": 600.0, "duration_s": 0.3, "viewport_h": 1280.0,
	}
	var origin := {"rx": 0.0, "ry": 1.6, "rz": 0.0}
	var live := FlickMap.map_windup(wsample, tuning, slid, origin)
	t.ok(not live.is_empty(), "wind-up maps against the slid hoop")
	if not live.is_empty():
		t.close(live["dist"], sqrt(3.3 * 3.3 + 0.35 * 0.35), 1e-9, "dist is the slant to the live hoop")
		t.ok(live["bz"] > 0.0 and absf(live["bz"] - 0.35 / sqrt(3.3 * 3.3 + 0.35 * 0.35)) < 1e-9,
			"bearing points at the slid hoop")


func _gameplay_reality(t) -> void:
	# The mechanic is real: an ideal-for-2.6 launch misses a 3.4 board; the
	# harder ideal-for-3.4 launch makes it.
	var far := SimGeometry.arcade(3.4)
	var lazy := ShotSim.simulate_shot(Ballistics.ideal_launch_for(52.0, SimGeometry.arcade()), false, far)
	t.ok(not lazy["made"], "base-power flick falls short of the far board (got %s)" % lazy["type"])
	var honest := ShotSim.simulate_shot(Ballistics.ideal_launch_for(52.0, far), false, far)
	t.ok(honest["made"], "distance-matched power makes at the far board")

	# Lateral is real too: the same straight shot makes at z 0 and misses when
	# the hoop has slid 0.4 m sideways; aiming at the slid hoop makes again.
	var base := SimGeometry.arcade(2.9)
	var straight := Ballistics.ideal_launch_for(52.0, base)
	t.ok(ShotSim.simulate_shot(straight, false, base.with_pose(2.9, 0.0))["made"], "straight shot makes at z 0")
	t.ok(not ShotSim.simulate_shot(straight, false, base.with_pose(2.9, 0.4))["made"], "straight shot misses the slid hoop")
	var slid := base.with_pose(2.9, 0.4)
	var slant := sqrt(2.9 * 2.9 + 0.4 * 0.4)
	var aimed := {
		"angle_deg": 52.0, "speed": Ballistics.speed_for_angle(52.0, slant, base.rise),
		"rx": 0.0, "ry": base.release_h, "rz": 0.0, "bx": 2.9 / slant, "bz": 0.4 / slant,
	}
	t.ok(ShotSim.simulate_shot(aimed, false, slid)["made"], "shot aimed at the slid hoop makes")


func _force_and_stop(t) -> void:
	# Practice "30 s mode": force the moving phase with a full clock, then park it.
	var tt := TimeTrial.new(SimGeometry.arcade(2.9))
	tt.endless = true
	tt.board_motion = true
	tt.force_motion = true
	_tick_seconds(tt, 4.0)
	t.ok(tt.moving, "force_motion starts the figure-8 in endless practice")
	t.ok(tt.geo.hoop_x != 2.9 or tt.geo.hoop_z != 0.0, "hoop has moved off the base pose")
	t.close(tt.time_left, 60.0, 1e-9, "the practice clock still does not run")
	tt.stop_motion()
	t.ok(not tt.moving and not tt.board_motion, "stop_motion ends the phase")
	t.ok(tt.geo == tt.base_geo, "stop_motion parks the hoop at the base pose")
	_tick_seconds(tt, 1.0)
	t.ok(not tt.moving and tt.geo == tt.base_geo, "…and it stays parked")

