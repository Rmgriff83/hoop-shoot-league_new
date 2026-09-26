extends RefCounted
## Gym rim (arcade geometry): the ring-to-board neck is part of the rim, the
## net only takes the ball once it is through the ring, and soft tube rubs are
## logged so rattle-ins classify as rolls. Regulation keeps the original
## behaviour byte-exact (golden fixtures).


func _ice_flag(t) -> void:
	var geo := SimGeometry.arcade()
	t.ok(not geo.ice, "presets start un-iced")
	var iced := geo.with_ice(true)
	t.ok(iced.ice and not geo.ice, "with_ice clones (source untouched)")
	t.close(iced.hoop_x, geo.hoop_x, 1e-12, "same pose")
	t.ok(iced.with_pose(3.1, 0.2).ice, "with_pose keeps the ice flag")
	t.ok(not iced.with_ice(false).ice, "with_ice(false) clears it")
	t.ok(not SimGeometry.regulation().ice, "regulation (golden) never iced")


func run(t) -> void:
	_ice_flag(t)
	_fields(t)
	_neck_kind(t)
	_neck_is_back_iron(t)
	_rattle_reality(t)
	_shelf_trap(t)


func _fields(t) -> void:
	var reg := SimGeometry.regulation()
	t.ok(not reg.neck_is_rim, "regulation: neck is backboard (original)")
	t.ok(reg.net_catch_depth == 0.0, "regulation: net catches at the plane (original)")
	t.ok(reg.rim_log_impact == 0.4, "regulation: rim log threshold 0.4 (original)")
	var arc := SimGeometry.arcade()
	t.ok(arc.neck_is_rim, "arcade: neck is rim")
	t.close(arc.net_catch_depth, SimConstants.R_BALL, 1e-12, "arcade: net catches a ball radius down")
	t.close(arc.rim_log_impact, SimGeometry.ARCADE_RIM_LOG_IMPACT, 1e-12, "arcade: soft rubs logged")
	var moved := arc.with_pose(3.1, 0.3)
	var kept: bool = (moved.neck_is_rim and moved.net_catch_depth == arc.net_catch_depth
		and moved.rim_log_impact == arc.rim_log_impact)
	t.ok(kept, "with_pose keeps the gym-rim fields")


func _neck_kind(t) -> void:
	# A ball resting on the neck ribbon, midway between ring back and board.
	for geo: SimGeometry in [SimGeometry.arcade(), SimGeometry.regulation()]:
		var mx: float = (geo.bracket_x0 + geo.bracket_x1) / 2.0
		var my: float = (geo.bracket_y0 + geo.bracket_y1) / 2.0
		var c := Colliders.bracket_contact(SimVec3.new(mx, my + SimConstants.R_BALL * 0.8, 0.0), geo)
		t.ok(c != null, "neck contact found")
		if c != null:
			var want := Colliders.KIND_RIM if geo.neck_is_rim else Colliders.KIND_BOARD
			t.eq(c.kind, want, "neck contact kind follows neck_is_rim (%s)" % want)


func _neck_is_back_iron(t) -> void:
	# Long arcade shots that land on the neck: they are BACK_RIM (rim event with a
	# back azimuth), never BOARD_MISS/BANK. Find some deterministically.
	var geo := SimGeometry.arcade(2.9)
	var back_rim := 0
	var neck_events := 0
	var board_off_face := 0
	# Measured 2026-09-12: 11 neck touches, 24 BACK_RIM of 297 rows.
	for a in range(44, 62, 2):
		var ideal: float = Ballistics.speed_for_angle(a, geo.hoop_x, geo.rise)
		for k in range(2, 13):
			for vz in [-0.3, 0.0, 0.3]:
				var out := ShotSim.simulate_shot({"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k), "vz": vz}, false, geo)
				var hit_neck := false
				for ev in out["events"]:
					if ev["kind"] == "rim" and ev["pos"]["x"] > geo.hoop_x + SimConstants.R_RIM + 0.005:
						hit_neck = true
				if hit_neck:
					neck_events += 1
				for ev in out["events"]:
					# Event pos is the ball centre: a face touch sits R_BALL off the
					# board; anything clearly nearer the ring would be the old ribbon.
					if ev["kind"] == "board" and ev["pos"]["x"] < geo.board_x - SimConstants.R_BALL - 0.02:
						board_off_face += 1
				if out["type"] == ShotClassify.BACK_RIM:
					back_rim += 1
	t.ok(neck_events >= 5, "long shots touch the neck as rim contacts (%d)" % neck_events)
	t.ok(back_rim >= 10, "long shots read as BACK_RIM (%d)" % back_rim)
	t.ok(board_off_face == 0, "no board event comes from the neck ribbon (%d)" % board_off_face)


func _rattle_reality(t) -> void:
	# Deterministic sweep around the ideal window. Measured 2026-09-12 on the
	# arcade rim: 5 SHOOTERS_ROLL, 34 BACK_RIM, 100 makes of 507 rows (the full
	# 1690-row sweep: 28 rolls / 112 back-rim, vs 2 / 30 with the neck as
	# backboard and the net grabbing at the plane).
	var geo := SimGeometry.arcade(2.9)
	var counts := {}
	var rows := 0
	var pen := 0.0
	var first := ""
	for a in range(40, 66, 2):
		var ideal: float = Ballistics.speed_for_angle(a, geo.hoop_x, geo.rise)
		for k in range(-6, 7):
			for vz in [-0.3, 0.0, 0.3]:
				var launch := {"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k), "vz": vz}
				var out := ShotSim.simulate_shot(launch, false, geo)
				rows += 1
				counts[out["type"]] = counts.get(out["type"], 0) + 1
				pen = maxf(pen, out["max_penetration"])
				if first == "":
					first = JSON.stringify(ShotSim.simulate_shot(launch, false, geo))
					t.eq(first, JSON.stringify(out), "gym rim sim is deterministic")
	t.ok(counts.get(ShotClassify.SHOOTERS_ROLL, 0) >= 2, "rattle-ins classify as rolls (%d)" % counts.get(ShotClassify.SHOOTERS_ROLL, 0))
	t.ok(counts.get(ShotClassify.BACK_RIM, 0) >= 15, "back-iron misses exist (%d)" % counts.get(ShotClassify.BACK_RIM, 0))
	var makes: int = (counts.get(ShotClassify.SWISH, 0) + counts.get(ShotClassify.MAKE, 0)
		+ counts.get(ShotClassify.BANK, 0) + counts.get(ShotClassify.SHOOTERS_ROLL, 0))
	t.ok(makes >= rows / 10, "the gym rim still lets shots in (%d/%d)" % [makes, rows])
	t.ok(pen < 0.02, "no deep penetration on the gym rim (%.4f)" % pen)


func _shelf_trap(t) -> void:
	# Port of test_shot_sim's bracket trap to the arcade gym rim: nothing may
	# rest on the shelf between ring and board.
	var geo := SimGeometry.arcade(2.9)
	var parked := 0
	for a in range(46, 62, 2):
		var ideal: float = Ballistics.speed_for_angle(a, geo.hoop_x, geo.rise)
		for k in range(2, 10):
			var s := ShotSim.create_shot({"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k)}, geo)
			while not s.settled and s.t < SimConstants.MAX_SHOT_TIME:
				ShotSim.step_shot(s)
			var on_shelf: bool = (s.t > 4.5 and s.pos.x > geo.hoop_x + SimConstants.R_RIM - 0.02
				and s.pos.x < geo.board_x + 0.01 and s.pos.y > geo.hoop_y - 0.2)
			if on_shelf:
				parked += 1
	t.eq(parked, 0, "no ball parks on the neck shelf")
	var drop := ShotSim.create_shot({"angle_deg": 0.0, "speed": 0.05, "rx": geo.bracket_x0 + 0.08, "ry": geo.hoop_y + 0.15, "rz": 0.0, "bx": 1.0, "bz": 0.0}, geo)
	while not drop.settled and drop.t < 3.0:
		ShotSim.step_shot(drop)
	t.ok(drop.settled or drop.resolved, "a ball dropped on the neck slides off and resolves")
