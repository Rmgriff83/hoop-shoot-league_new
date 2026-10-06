extends RefCounted
## Court props the ball bounces off (SimGeometry.props, Colliders.prop_contact):
## the city's floor speaker and its tabletop scoreboard. Nothing else has
## any (golden fixtures); a prop hit is its own contact kind, never a bank.


func run(t) -> void:
	for pair in [["regulation", SimGeometry.regulation()], ["beach", SimGeometry.beach()]]:
		t.ok(not (pair[1] as SimGeometry).has_props(), "%s: no props" % pair[0])
	# The cage's front console (2026-10-04): past the release point, chest high,
	# full width; the held ball starts above it and a roll-out passes under it.
	var a := SimGeometry.arcade()
	t.eq(a.props.size(), 1, "the arcade: the front console")
	var con: Dictionary = a.props[0]
	t.ok(float(con["x0"]) > 0.0 and float(con["y1"]) < 1.85 - SimConstants.R_BALL and float(con["y0"]) > 2.0 * SimConstants.R_BALL, "in front of the release, under the held ball, above a rolling ball")
	t.ok(Colliders.prop_contact(SimVec3.new(0.5, 1.0 + 0.05, 0.0), a) != null, "a ball dropping onto its top is caught")
	t.ok(Colliders.prop_contact(SimVec3.new(0.5, SimConstants.R_BALL, 0.0), a) == null, "…and one rolling home underneath is not")
	var low := ShotSim.create_shot({"angle_deg": 10.0, "speed": 2.0, "rx": 0.0, "ry": 1.3, "rz": 0.0, "bx": 1.0, "bz": 0.0}, a)
	var kinds := []
	for i in int(1.5 / SimConstants.SIM_DT):
		if low.settled:
			break
		ShotSim.step_shot(low)
	for ev in low.events:
		kinds.push_back(ev["kind"])
	t.ok(kinds.has("prop"), "a dribbled flick bounces off the console (%s)" % str(kinds))
	var g := SimGeometry.city()
	t.eq(g.props.size(), 2, "the city: the speaker and the scoreboard")
	t.ok(g.with_pose(4.0, 0.2).props.size() == 2, "with_pose keeps them")
	# Contact geometry: on top of a speaker (normal up), against the scoreboard's face (normal -x), clear.
	var top := Colliders.prop_contact(SimVec3.new(4.55, 0.92 + 0.10, -1.75), g)
	t.ok(top != null and top.kind == "prop" and top.ny == 1.0 and absf(top.depth - (SimConstants.R_BALL - 0.10)) < 1e-9, "a ball resting on a speaker is pushed up")
	var face := Colliders.prop_contact(SimVec3.new(5.20 - 0.08, 0.3, 1.45), g)
	t.ok(face != null and face.nx == -1.0, "a ball at the scoreboard's face is pushed back toward the shooter")
	t.ok(Colliders.prop_contact(SimVec3.new(3.0, 0.3, 0.0), g) == null, "clear of them on the court")
	var corner := Colliders.prop_contact(SimVec3.new(4.78 + 0.05, 0.92 + 0.05, -1.75), g)
	t.ok(corner != null and corner.nx > 0.5 and corner.ny > 0.5, "an edge pushes diagonally")
	var inside := Colliders.prop_contact(SimVec3.new(4.40, 0.5, -1.75), g)
	t.ok(inside != null and inside.nx == -1.0 and inside.depth > SimConstants.R_BALL, "a centre caught inside leaves through the nearest face")
	# Dropped onto a speaker: the first hit is a prop hit, the ball bounces and stays above the top.
	var s := ShotSim.create_shot({"angle_deg": 0.0, "speed": 0.0, "rx": 4.55, "ry": 1.6, "rz": -1.75, "bx": 1.0, "bz": 0.0}, g)
	var min_y := INF
	var first := ""
	for i in int(1.5 / SimConstants.SIM_DT):
		if s.settled:
			break
		ShotSim.step_shot(s)
		if first == "" and not s.events.is_empty():
			first = str(s.events[0]["kind"])
		if s.pos.x > 4.32 and s.pos.x < 4.78 and absf(s.pos.z + 1.75) < 0.26:
			min_y = minf(min_y, s.pos.y)
	t.eq(first, "prop", "the first contact is the speaker")
	t.ok(min_y > 0.92 + SimConstants.R_BALL - 0.01, "never through its top (min y %.3f)" % min_y)
	# Thrown flat at the scoreboard: it comes back toward the shooter.
	var h := ShotSim.create_shot({"angle_deg": 0.0, "speed": 5.0, "rx": 3.5, "ry": 0.3, "rz": 1.45, "bx": 1.0, "bz": 0.0}, g)
	var hit := false
	for i in int(1.0 / SimConstants.SIM_DT):
		if h.settled:
			break
		ShotSim.step_shot(h)
		for ev in h.events:
			if ev["kind"] == "prop":
				hit = true
		if hit:
			break
	t.ok(hit and h.vel.x < 0.0, "it bounces back off the scoreboard (vx %.2f)" % h.vel.x)
	t.ok(h.pos.x < 5.20, "…and never passes its face")
	t.ok(ShotClassify.classify_shot(h)["type"] != ShotClassify.BANK, "a prop hit does not read as a bank")
	# Shots still drop.
	t.ok(ShotSim.simulate_shot(Ballistics.ideal_launch_for(52.0, g), false, g)["made"], "ideal city shot still drops")
