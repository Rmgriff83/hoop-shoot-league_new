extends RefCounted
## Beach practice: the street-hoop geometry (8 ft rim, regulation board, the
## arcade's feel, 17.5 % farther, static), the mode table, and an endless
## trial on it.


func run(t) -> void:
	_geometry(t)
	_shots(t)
	_modes(t)
	_endless_trial(t)


func _geometry(t) -> void:
	var g := SimGeometry.beach()
	t.close(g.hoop_x, 2.9 * 1.175, 1e-12, "beach hoop is 17.5 %% farther than the arcade base (%.4f)" % g.hoop_x)
	t.close(g.hoop_y, 2.44, 1e-12, "beach rim stays 8 ft")
	t.close(g.release_h, 1.85, 1e-12, "beach release is the arcade's")
	t.close(g.board_half_w, 0.915, 1e-12, "regulation board width")
	t.close(g.board_top - g.board_bottom, 1.05, 1e-12, "regulation board height")
	t.close(g.board_bottom, 2.29, 1e-12, "board bottom 0.15 m below the rim")
	t.ok(g.hoop_z == 0.0, "beach hoop is centred")
	var a := SimGeometry.arcade()
	# The beach ring is deliberately the bouncier one — the ONLY rim field it
	# does not share with the cage. Everything the player sees and hears of that
	# rim is derived from it (see test_rim_feel.gd).
	t.close(g.rim_e, SimGeometry.BEACH_RIM_E, 1e-12, "beach rim uses its own restitution")
	t.ok(g.rim_e > a.rim_e, "beach iron is livelier than the cage's (%.3f > %.3f)" % [g.rim_e, a.rim_e])
	t.ok(g.rim_mu == a.rim_mu and g.rim_spin_decay == a.rim_spin_decay, "beach grip and spin decay still match the cage")
	t.close(g.with_pose(3.6, 0.2).rim_e, SimGeometry.BEACH_RIM_E, 1e-12, "a moved board keeps the beach rim's bounce")
	t.ok(g.neck_is_rim == a.neck_is_rim and g.net_catch_depth == a.net_catch_depth and g.rim_log_impact == a.rim_log_impact, "beach gym-rim fields = arcade")
	var moved := g.with_pose(3.6, 0.2)
	t.ok(moved.board_half_w == 0.915 and moved.neck_is_rim, "with_pose keeps board dims and feel")
	t.close(a.board_half_w, 0.61, 1e-12, "arcade board width unchanged by the refactor")
	t.close(a.board_top - a.board_bottom, 0.76, 1e-12, "arcade board height unchanged by the refactor")


func _shots(t) -> void:
	var g := SimGeometry.beach()
	for ang in [52.0, 55.0]:
		var launch := Ballistics.ideal_launch_for(ang, g)
		var out := ShotSim.simulate_shot(launch, false, g)
		t.ok(out["made"], "ideal %.0f° shot is made on the beach hoop (%s)" % [ang, out["type"]])
		var short := launch.duplicate()
		short["speed"] = launch["speed"] * 0.94
		t.ok(not ShotSim.simulate_shot(short, false, g)["made"], "6 %% short misses at %.0f°" % ang)
	var pen := 0.0
	var first := ""
	for a in range(40, 66, 5):
		var ideal: float = Ballistics.speed_for_angle(a, g.hoop_x, g.rise)
		for k in range(-4, 5, 2):
			var launch := {"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k)}
			var out := ShotSim.simulate_shot(launch, false, g)
			pen = maxf(pen, out["max_penetration"])
			if first == "":
				first = JSON.stringify(out)
				t.eq(first, JSON.stringify(ShotSim.simulate_shot(launch, false, g)), "beach sim is deterministic")
	t.ok(pen < 0.02, "no deep penetration on the beach hoop (%.4f)" % pen)


func _modes(t) -> void:
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		t.ok(true, "(App autoload absent — mode table checks skipped)")
		return
	for id in ["trial", "practice", "beach", "trial_beach"]:
		t.ok(app.MODES.has(id), "mode table has %s" % id)
	var tb: Dictionary = app.mode_config("trial_beach")
	t.ok(not tb["endless"] and not tb["board_motion"] and tb["location"] == "beach" and tb["arena"] == "beach",
		"beach time trial: timed, static hoop, beach leaderboard")
	t.eq(app.AREA_MODES["trial"]["beach"], "trial_beach", "trial × beach → trial_beach")
	t.eq(app.AREA_MODES["practice"]["cage"], "practice", "practice × cage → practice")
	t.ok(not app.AREA_MODES.has("heat"), "quick heats are off the area table (heats are league games)")
	t.ok(app.MODES.has("heat") and app.MODES.has("heat_beach"), "the heat modes stay for league games and tests")
	var b: Dictionary = app.mode_config("beach")
	t.eq(b["arena"], "beach", "beach mode uses the beach arena")
	t.eq(b["hoop"], "street", "beach mode mandates the street hoop")
	t.eq(b["geo"], "beach", "beach mode uses beach geometry")
	t.close(float(b["dist"]), 2.9 * 1.175, 1e-12, "beach mode distance")
	t.ok(b["endless"] and not b["board_motion"], "beach mode is endless and static")
	t.eq(b["hud_label"], "BEACH", "beach HUD label")
	t.close(app.geo_for_mode("beach").board_half_w, 0.915, 1e-12, "geo_for_mode(beach) is the regulation board")
	t.close(app.geo_for_mode("trial").hoop_x, 2.9, 1e-12, "geo_for_mode(trial) is the arcade base")
	t.close(app.geo_for_mode("trial").board_half_w, 0.61, 1e-12, "geo_for_mode(trial) is the junior board")
	t.eq(app.mode_config("nope"), app.MODES["trial"], "unknown mode falls back to trial")
	var street = app.hoop_for_mode("beach")
	t.ok(street != null and street.id == "street", "beach mode resolves the street hoop regardless of ownership")


func _endless_trial(t) -> void:
	var tt := TimeTrial.new(SimGeometry.beach())
	tt.endless = true
	for i in int(3.0 / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "beach trial runs")
	t.ok(not tt.moving, "beach hoop never moves")
	t.ok(tt.pickup(), "pickup on the beach")
	t.ok(tt.release(Ballistics.ideal_launch_for(55.0, tt.geo)), "release on the beach")
	for i in int(2.5 / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)
	t.eq(tt.makes, 1, "ideal beach shot scores")
	t.close(tt.geo.hoop_x, 2.9 * 1.175, 1e-12, "beach hoop stayed put")
