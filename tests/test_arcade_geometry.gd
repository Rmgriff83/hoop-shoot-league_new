extends RefCounted
## Arcade pop-a-shot geometry (SimGeometry.arcade): analytic table, emergent
## outcomes at close range, no-tunneling, determinism, the moving-board seam,
## and the distance-derived flick band.


func run(t) -> void:
	var geo := SimGeometry.arcade()
	t.ok(geo.hoop_z == 0.0, "arcade base hoop_z is exactly 0")

	# Geometry wiring.
	t.close(geo.hoop_x, 2.6, 1e-9, "arcade distance 2.6")
	t.close(geo.hoop_y, 2.44, 1e-9, "arcade rim 8ft")
	t.close(geo.rise, 0.59, 1e-9, "arcade rise")
	t.close(geo.board_half_w, 0.61, 1e-9, "junior board half width")
	t.close(geo.board_top - geo.board_bottom, 0.76, 1e-9, "junior board height")

	# Analytic launch table at (2.6 m, rise 0.59) — hand-computed ground truth.
	t.close(Ballistics.speed_for_angle(45.0, 2.6, 0.59), 5.744, 0.01, "arcade 45°")
	t.close(Ballistics.speed_for_angle(50.0, 2.6, 0.59), 5.656, 0.01, "arcade 50°")
	t.close(Ballistics.speed_for_angle(55.0, 2.6, 0.59), 5.681, 0.01, "arcade 55°")
	t.close(Ballistics.speed_for_angle(60.0, 2.6, 0.59), 5.822, 0.01, "arcade 60°")
	# The flat-band gift survives at arcade scale.
	for a in range(44, 63):
		var v := Ballistics.speed_for_angle(float(a), 2.6, 0.59)
		t.ok(v > 5.6 and v < 5.95, "arcade flat band at %d° (%.3f)" % [a, v])

	# Emergent outcomes at arcade range.
	for angle in [52.0, 55.0, 58.0]:
		var out := ShotSim.simulate_shot(Ballistics.ideal_launch_for(angle, geo), false, geo)
		t.ok(out["made"], "arcade ideal %d° drops" % int(angle))
		t.eq(out["type"], ShotClassify.SWISH, "arcade ideal %d° swishes" % int(angle))
		t.eq(out["points"], 2, "arcade swish boost intact at %d°" % int(angle))

	var v52: float = Ballistics.ideal_launch_for(52.0, geo)["speed"]
	var short := ShotSim.simulate_shot({"angle_deg": 52.0, "speed": v52 * 0.94}, false, geo)
	t.ok(not short["made"], "short arcade shot misses")
	t.ok(short["type"] in [ShotClassify.FRONT_RIM, ShotClassify.IN_AND_OUT, ShotClassify.AIRBALL],
		"short arcade miss family (got %s)" % short["type"])

	var long := ShotSim.simulate_shot({"angle_deg": 52.0, "speed": v52 * 1.06}, false, geo)
	if not long["made"]:
		t.ok(long["type"] in [ShotClassify.BACK_RIM, ShotClassify.BOARD_MISS, ShotClassify.IN_AND_OUT],
			"long arcade miss family (got %s)" % long["type"])
	else:
		t.ok(long["rim_contacts"] > 0 or long["board_contacts"] > 0, "long arcade make touched something")

	# Small lateral error may still roll in (κ-graze forgiveness, by design),
	# but a big tilt can never swish — it drifts wider than the rim radius.
	var side := ShotSim.simulate_shot({"angle_deg": 52.0, "speed": v52, "vz": 0.35}, false, geo)
	t.ok(side["type"] != ShotClassify.SWISH, "big lateral error cannot swish (got %s)" % side["type"])

	# No tunneling across the arcade launch space (168-combo grid).
	for ai in range(35, 71, 5):
		for si in [4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5]:
			for vz in [-0.5, 0.0, 0.5]:
				var out := ShotSim.simulate_shot({"angle_deg": float(ai), "speed": si, "vz": vz}, true, geo)
				t.ok(out["max_penetration"] < 0.02,
					"arcade penetration %.4f at %d°/%.1f/vz=%.1f" % [out["max_penetration"], ai, si, vz])

	# Determinism at arcade geometry.
	var launch := {"angle_deg": 53.7, "speed": 5.71, "vz": 0.04}
	t.eq(
		JSON.stringify(ShotSim.simulate_shot(launch, false, geo)),
		JSON.stringify(ShotSim.simulate_shot(launch, false, geo)),
		"arcade sim deterministic"
	)

	# Moving-board seam: same launch, different distance → different result.
	var near_ideal := Ballistics.ideal_launch_for(52.0, geo)
	var at_near := ShotSim.simulate_shot(near_ideal, false, SimGeometry.arcade(2.6))
	var at_far := ShotSim.simulate_shot(near_ideal, false, SimGeometry.arcade(3.2))
	t.ok(at_near["made"], "ideal at 2.6 makes")
	t.ok(not at_far["made"], "same launch at 3.2 falls short")

	# TimeTrial carries geometry into its shots.
	var trial := TimeTrial.new(geo)
	for i in ceili(TimeTrial.COUNTDOWN_SECONDS / SimConstants.SIM_DT) + 20:
		trial.tick(SimConstants.SIM_DT)
	trial.pickup()
	trial.release(Ballistics.ideal_launch_for(55.0, geo))
	for i in ceili(2.0 / SimConstants.SIM_DT):
		trial.tick(SimConstants.SIM_DT)
	t.eq(trial.score, 2, "arcade trial swish scores 2")

	# Flick band derives from distance.
	var anchor := FlickMap.v_ideal(geo)
	t.close(anchor, 5.653, 0.01, "arcade anchor speed")
	t.close(FlickMap.V_MIN_FRAC * anchor, 4.381, 0.01, "arcade band floor")
	t.close(FlickMap.V_MAX_FRAC * anchor, 6.896, 0.01, "arcade band ceiling")
	var tuning := FlickTuning.new()
	var sample := {
		"vel_x": 0.0, "vel_y": -1.8 * 1280.0, "travel_x": 0.0, "travel_y": -0.3 * 1280.0,
		"duration_s": 0.15, "viewport_h": 1280.0,
	}
	var mapped := FlickMap.map_flick(sample, tuning, geo)
	t.ok(mapped["speed"] > 4.38 and mapped["speed"] < 6.9, "arcade flick maps into band (%.2f)" % mapped["speed"])
