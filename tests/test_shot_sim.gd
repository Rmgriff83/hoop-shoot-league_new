extends RefCounted
## Port of tests/shotSim.spec.ts. fast-check properties become deterministic grids.


func run(t) -> void:
	_emergent_swish(t)
	_bracket_trap(t)
	_determinism(t)
	_no_tunneling_grids(t)


func _emergent_swish(t) -> void:
	# Ideal high-arc shots (52°, 55°) swish: 2 points, zero rim contact.
	for angle in [52.0, 55.0]:
		var out := ShotSim.simulate_shot(Ballistics.ideal_launch(angle))
		t.ok(out["made"], "%d° should drop" % int(angle))
		t.eq(out["type"], ShotClassify.SWISH, "%d° should be clean" % int(angle))
		t.eq(out["points"], 2, "%d° scores 2" % int(angle))
		t.ok(out["entry_angle_deg"] > 43.0, "%d° entry > 43°" % int(angle))

	# A flat 42° rope arrives at ~32° and cannot swish — rim contact is physics, not script.
	var flat := ShotSim.simulate_shot(Ballistics.ideal_launch(42.0))
	t.ok(flat["rim_contacts"] > 0, "42° has rim contact")
	t.ok(flat["type"] != ShotClassify.SWISH, "42° is not a swish")

	# Short shot clips the front rim and kicks back toward the shooter.
	var v45 := Ballistics.speed_for_angle(45.0)
	var short := ShotSim.simulate_shot({"angle_deg": 45.0, "speed": v45 * 0.965})
	t.ok(not short["made"], "short 45° misses")
	t.ok(short["type"] in [ShotClassify.FRONT_RIM, ShotClassify.IN_AND_OUT, ShotClassify.AIRBALL],
		"short 45° miss family (got %s)" % short["type"])
	if short["type"] == ShotClassify.FRONT_RIM:
		for ev in short["events"]:
			if ev["kind"] == Colliders.KIND_RIM:
				t.ok(ev["normal"]["x"] < 0.4, "front rim kicks back or up")
				break

	# Long shot catches back rim or banks.
	var v48 := Ballistics.speed_for_angle(48.0)
	var long := ShotSim.simulate_shot({"angle_deg": 48.0, "speed": v48 * 1.04})
	t.ok(long["made"] == false or long["type"] == ShotClassify.BANK or long["rim_contacts"] > 0,
		"long 48° hits something")
	if not long["made"]:
		t.ok(long["type"] in [ShotClassify.BACK_RIM, ShotClassify.BOARD_MISS, ShotClassify.IN_AND_OUT],
			"long 48° miss family (got %s)" % long["type"])

	# Lateral error produces side-rim results.
	var v50 := Ballistics.speed_for_angle(50.0)
	var side := ShotSim.simulate_shot({"angle_deg": 50.0, "speed": v50, "vz": 0.18})
	t.ok(side["rim_contacts"] > 0, "vz=0.18 clips the rim")
	for ev in side["events"]:
		if ev["kind"] == Colliders.KIND_RIM:
			t.ok(absf(ev["pos"]["z"]) > 0.05, "first rim contact off-axis |z|>0.05")
			break

	# Way-off shots are airballs.
	var air := ShotSim.simulate_shot({"angle_deg": 45.0, "speed": 7.2})
	t.eq(air["type"], ShotClassify.AIRBALL, "45°/7.2 is an airball")
	t.eq(air["points"], 0, "airball scores 0")


func _bracket_trap(t) -> void:
	# Long square back-rim misses never come to rest behind the rim.
	for angle in [46.0, 48.0, 50.0, 52.0, 55.0]:
		var v := Ballistics.speed_for_angle(angle)
		for over in [1.03, 1.04, 1.05, 1.06, 1.07]:
			for vz in [0.0, 0.08, 0.16]:
				var out := ShotSim.simulate_shot({"angle_deg": angle, "speed": v * over, "vz": vz})
				var events: Array = out["events"]
				if events.is_empty():
					continue
				var last: Dictionary = events[events.size() - 1]
				var rest: Dictionary = last["pos"]
				var in_trap: bool = rest["x"] > 7.44 and rest["x"] < 7.63 and rest["y"] > 2.85
				t.ok(not (in_trap and out["flight_time"] > 0.0 and last["t"] > 4.5),
					"%d° ×%.2f vz=%.2f rested in the rim–board gap" % [int(angle), over, vz])

	# A ball dropped into the gap region resolves fast and never parks behind the rim.
	var s := ShotSim.create_shot({"angle_deg": 50.0, "speed": Ballistics.speed_for_angle(50.0)})
	s.pos = SimVec3.new(7.55, 3.2, 0.0)
	s.vel = SimVec3.new(0.05, 0.0, 0.0)
	var t0 := s.t
	for i in 1200:
		if s.settled:
			break
		ShotSim.step_shot(s)
	t.ok(s.settled, "gap drop settles")
	t.ok(s.t - t0 < 3.0, "gap drop sheds promptly (%.2f s)" % (s.t - t0))
	var parked: bool = s.pos.x > 7.44 and s.pos.x < 7.63 and s.pos.y > 2.85
	t.ok(not parked, "gap drop never parks behind the rim")
	t.ok(ShotClassify.classify_shot(s)["type"] is String, "classify terminates on synthetic state")


func _determinism(t) -> void:
	var launch := {"angle_deg": 47.3, "speed": 9.11, "vz": 0.05}
	var a := ShotSim.simulate_shot(launch)
	var b := ShotSim.simulate_shot(launch)
	t.eq(JSON.stringify(a), JSON.stringify(b), "same launch → byte-identical outcome")


func _no_tunneling_grids(t) -> void:
	# Penetration never exceeds 2 cm across plausible launches (deterministic grid ≈ 315 combos).
	for ai in range(30, 71, 5):
		for si in [7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0]:
			for vz in [-0.6, 0.0, 0.6]:
				var out := ShotSim.simulate_shot({"angle_deg": float(ai), "speed": si, "vz": vz}, true)
				t.ok(out["max_penetration"] < 0.02,
					"penetration %.4f at %d°/%.1f/vz=%.1f" % [out["max_penetration"], ai, si, vz])

	# Every simulated shot terminates with a coherent classified outcome (edge grid).
	for ai in [20.0, 30.0, 50.0, 70.0, 78.0]:
		for si in [6.0, 8.0, 10.0, 12.0]:
			for vz in [-1.0, 0.0, 1.0]:
				var out := ShotSim.simulate_shot({"angle_deg": ai, "speed": si, "vz": vz}, true)
				t.ok(out["type"] is String, "classified at %d°/%.0f/%.0f" % [int(ai), si, vz])
				if out["made"]:
					t.ok(out["points"] >= 1, "made scores ≥1")
				else:
					t.eq(out["points"], 0, "miss scores 0")
