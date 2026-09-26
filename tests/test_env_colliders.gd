extends RefCounted
## Environment colliders: the arcade cage's mesh walls and roof, the beach's
## fence enclosure and in-ground pole. Regulation has none (golden fixtures).


func run(t) -> void:
	_regulation_has_none(t)
	_cage_walls(t)
	_beach_fence_and_pole(t)
	_with_pose_keeps(t)


func _fly(geo: SimGeometry, launch: Dictionary, seconds: float) -> BallState:
	var s := ShotSim.create_shot(launch, geo)
	for i in int(seconds / SimConstants.SIM_DT):
		if s.settled:
			break
		ShotSim.step_shot(s)
	return s


func _kinds(s: BallState) -> Array:
	var out := []
	for ev in s.events:
		out.push_back(ev["kind"])
	return out


func _regulation_has_none(t) -> void:
	var g := SimGeometry.regulation()
	t.ok(not g.has_walls() and g.pole_r == 0.0, "regulation: no walls, no pole")
	t.ok(Colliders.wall_contact(SimVec3.new(50.0, 1.0, 50.0), g) == null, "no wall contact anywhere")
	t.ok(Colliders.pole_contact(SimVec3.new(g.board_x + 0.3, 1.0, 0.0), g) == null, "no pole contact")


func _cage_walls(t) -> void:
	var g := SimGeometry.arcade(2.9)
	t.ok(g.has_walls() and g.wall_z_max == 1.26 and g.wall_y_max == 3.9, "arcade geometry carries the cage")
	# A hard sideways throw: hits the side mesh, stays inside, keeps playing.
	var s := _fly(g, {"angle_deg": 20.0, "speed": 7.0, "rx": 0.0, "ry": 1.6, "rz": 0.0, "bx": 0.3, "bz": 0.954}, 2.0)
	t.ok(_kinds(s).has("wall"), "sideways throw hits the cage wall (%s)" % str(_kinds(s)))
	var max_z := 0.0
	var s2 := ShotSim.create_shot({"angle_deg": 20.0, "speed": 7.0, "rx": 0.0, "ry": 1.6, "rz": 0.0, "bx": 0.3, "bz": 0.954}, g)
	for i in int(2.0 / SimConstants.SIM_DT):
		if s2.settled:
			break
		ShotSim.step_shot(s2)
		max_z = maxf(max_z, absf(s2.pos.z))
	t.ok(max_z <= 1.26 - SimConstants.R_BALL + 0.02, "ball never leaves the cage sideways (max |z| %.3f)" % max_z)
	# A moon ball meets the mesh roof.
	var s3 := _fly(g, {"angle_deg": 80.0, "speed": 8.0}, 2.5)
	t.ok(_kinds(s3).has("wall"), "a moon ball hits the cage roof (%s)" % str(_kinds(s3)))
	# An ordinary make still goes in.
	t.ok(ShotSim.simulate_shot(Ballistics.ideal_launch_for(52.0, g), false, g)["made"], "ideal shot still swishes in the cage")


func _beach_fence_and_pole(t) -> void:
	var g := SimGeometry.beach()
	t.ok(g.has_walls() and g.wall_x_max == 5.7 and g.wall_y_max == INF, "beach: fence, no roof")
	t.ok(g.pole_r > 0.0, "beach has a pole")
	# A low line drive under the board hits the pole and comes back.
	var s := _fly(g, {"angle_deg": 0.0, "speed": 6.0, "rx": 2.5, "ry": 1.0, "rz": 0.0, "bx": 1.0, "bz": 0.0}, 1.5)
	t.ok(_kinds(s).has("pole"), "low drive under the board hits the pole (%s)" % str(_kinds(s)))
	t.ok(s.pos.x < g.board_x + g.pole_off, "…and is on the court side of it afterwards")
	# A long brick from the key hits the back fence instead of vanishing.
	var s2 := _fly(g, {"angle_deg": 30.0, "speed": 9.5}, 3.0)
	t.ok(_kinds(s2).has("wall") or _kinds(s2).has("board"), "a long brick meets the fence or board (%s)" % str(_kinds(s2)))
	var over := ShotSim.create_shot({"angle_deg": 30.0, "speed": 9.5}, g)
	var max_x := 0.0
	for i in int(3.0 / SimConstants.SIM_DT):
		if over.settled:
			break
		ShotSim.step_shot(over)
		max_x = maxf(max_x, over.pos.x)
	t.ok(max_x <= 5.7 - SimConstants.R_BALL + 0.02, "ball never passes the back fence (max x %.3f)" % max_x)
	# Determinism with the new colliders.
	var a := ShotSim.simulate_shot({"angle_deg": 30.0, "speed": 9.5}, false, g)
	var b := ShotSim.simulate_shot({"angle_deg": 30.0, "speed": 9.5}, false, g)
	t.eq(JSON.stringify(a), JSON.stringify(b), "enclosure sim is deterministic")


func _with_pose_keeps(t) -> void:
	var g := SimGeometry.beach().with_pose(3.6, 0.2)
	t.ok(g.has_walls() and g.pole_r == 0.06 and g.wall_x_min == -11.2, "with_pose copies the enclosure and pole")
	var c := SimGeometry.arcade(2.9).with_pose(3.3, 0.3)
	t.ok(c.wall_y_max == 3.9, "with_pose copies the cage roof")
