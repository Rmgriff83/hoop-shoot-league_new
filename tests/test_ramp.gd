extends RefCounted
## The arcade cage's ball-return ramp (SimGeometry.arcade ramp_*; the Ramp
## quad in tools/blender/build_cage.py): a miss that drops behind the rim
## lands on the slope, bounces and rolls back down to the deck, where it
## rolls out and comes to rest. Every other geometry keeps the flat floor
## and the original drop-on-third-hit rules (golden fixtures).


func run(t) -> void:
	_only_the_arcade(t)
	_the_plane(t)
	_rolls_down(t)
	_deck_roll_out(t)
	_the_lip(t)
	_short_miss_unchanged_elsewhere(t)


func _only_the_arcade(t) -> void:
	for pair in [["regulation", SimGeometry.regulation()], ["beach", SimGeometry.beach()], ["city", SimGeometry.city()]]:
		var g: SimGeometry = pair[1]
		t.ok(not g.has_ramp() and g.deck_roll_decel == 0.0 and g.floor_log_impact == 0.0, "%s: flat floor, no deck roll, every floor hit logged" % pair[0])
		var c := Colliders.floor_contact(SimVec3.new(4.0, 0.1, 0.0), g)
		t.ok(c != null and c.ny == 1.0 and c.nx == 0.0 and absf(c.depth - (SimConstants.R_BALL - 0.1)) < 1e-12, "%s: the flat floor at x 4" % pair[0])
	var bare := Colliders.floor_contact(SimVec3.new(4.0, 0.1, 0.0))
	t.ok(bare != null and bare.ny == 1.0, "no geometry: the flat floor")
	var a := SimGeometry.arcade()
	t.ok(a.has_ramp() and a.ramp_x0 == 3.5 and a.ramp_x1 == 4.4 and a.ramp_h == 0.9, "the arcade carries the ramp (3.5 → 4.4, 0.9 m)")
	t.close(a.floor_height(3.95), 0.45, 1e-9, "the slope is halfway up at its middle")
	t.close(a.floor_height(2.0), 0.0, 1e-9, "the deck is flat")
	var moved := a.with_pose(3.2, 0.3)
	t.ok(moved.has_ramp() and moved.deck_roll_decel == a.deck_roll_decel and moved.floor_log_impact == a.floor_log_impact, "with_pose keeps the ramp")


func _the_plane(t) -> void:
	var g := SimGeometry.arcade()
	# A ball centre 0.1 m above the slope's surface at x 4.0 (surface 0.5):
	# perpendicular gap 0.1·cos 45° = 0.0707 → depth R − 0.0707.
	var c := Colliders.floor_contact(SimVec3.new(4.0, 0.6, 0.0), g)
	t.ok(c != null and c.kind == Colliders.KIND_FLOOR, "the ramp is floor material")
	t.ok(c.nx < -0.7 and c.ny > 0.7, "its normal leans toward the shooter (%.2f, %.2f)" % [c.nx, c.ny])
	t.close(c.depth, SimConstants.R_BALL - 0.1 * cos(PI / 4.0), 1e-9, "depth from the inclined plane")
	t.ok(Colliders.floor_contact(SimVec3.new(4.0, 0.75, 0.0), g) == null, "clear of the slope: no contact")
	var deck := Colliders.floor_contact(SimVec3.new(3.0, 0.1, 0.0), g)
	t.ok(deck != null and deck.ny == 1.0 and deck.nx == 0.0, "in front of the crease the deck is flat")
	t.ok(Colliders.floor_contact(SimVec3.new(3.0, 0.3, 0.0), g) == null, "…and the plane below it is ignored")


## Dropped from rest above the slope: the first hit is a ramp hit, the ball
## comes down to the deck, and it settles there (not on the slope) at rest.
func _rolls_down(t) -> void:
	var g := SimGeometry.arcade()
	var s := ShotSim.create_shot({"angle_deg": 0.0, "speed": 0.0, "rx": 4.0, "ry": 1.4, "rz": 0.0, "bx": 1.0, "bz": 0.0}, g)
	var min_x := INF
	var left_ramp_at := -1.0
	for i in int(SimConstants.MAX_SHOT_TIME / SimConstants.SIM_DT) + 1:
		if s.settled:
			break
		ShotSim.step_shot(s)
		min_x = minf(min_x, s.pos.x)
		if left_ramp_at < 0.0 and s.pos.x < g.ramp_x0:
			left_ramp_at = s.t
	t.ok(s.settled, "the ball settles")
	t.ok(s.t < SimConstants.MAX_SHOT_TIME - 0.5, "…by coming to rest, not the time cap (%.2f s)" % s.t)
	var first: Dictionary = s.events[0] if not s.events.is_empty() else {}
	t.ok(not first.is_empty() and first["kind"] == "floor" and float(first["normal"]["x"]) < -0.5, "the first hit is on the slope")
	t.ok(left_ramp_at > 0.0 and left_ramp_at < 2.5, "it rolls off the ramp onto the deck (%.2f s)" % left_ramp_at)
	t.ok(s.pos.x < g.ramp_x0 - 0.3, "…and rests on the deck (x %.2f)" % s.pos.x)
	t.ok(s.vel.length() < 0.6, "…slower than the rest speed")
	t.ok(s.resolved and s.floor_hits > 0, "a ramp hit resolves the shot (a miss)")
	t.ok(s.events.size() < 40, "soft rubs while rolling are not events (%d logged)" % s.events.size())
	t.ok(s.max_penetration < 0.02, "never through the slope (max %.4f)" % s.max_penetration)
	# A padded channel: the slope bounces softer than the deck.
	t.ok(g.ramp_e < SimConstants.E_FLOOR, "the slope is padded (e %.2f < %.2f)" % [g.ramp_e, SimConstants.E_FLOOR])
	var c := Colliders.Contact.new(Colliders.KIND_FLOOR, 0.0, -0.7071, 0.7071, 0.0, 4.0, 0.5, 0.0)
	t.ok(Colliders.is_ramp(c) and not Colliders.is_ramp(Colliders.Contact.new(Colliders.KIND_FLOOR, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0)), "a leaning floor normal is the ramp")


## The tray lip at the shooter's feet stops a roll-out.
func _the_lip(t) -> void:
	var g := SimGeometry.arcade()
	t.ok(g.lip_x == -0.4 and g.lip_h == 0.45, "the arcade carries the lip (x −0.4, 0.45 tall)")
	t.ok(Colliders.lip_contact(SimVec3.new(0.0, 0.2, 0.0), SimGeometry.regulation()) == null, "regulation has none")
	var face := Colliders.lip_contact(SimVec3.new(-0.3, 0.2, 0.0), g)
	t.ok(face != null and face.kind == Colliders.KIND_WALL and face.nx == 1.0 and absf(face.depth - 0.021) < 1e-9, "a ball against its face is pushed back (+x)")
	var top := Colliders.lip_contact(SimVec3.new(-0.43, 0.55, 0.0), g)
	t.ok(top != null and top.ny == 1.0, "a ball on its top edge is pushed up")
	t.ok(Colliders.lip_contact(SimVec3.new(0.5, 0.2, 0.0), g) == null, "clear of it on the deck")
	# A slow roll toward the shooter stops at the lip and rests in front of it.
	var s := ShotSim.create_shot({"angle_deg": 0.0, "speed": 1.5, "rx": 1.0, "ry": SimConstants.R_BALL + 0.001, "rz": 0.0, "bx": -1.0, "bz": 0.0}, g)
	var min_x := INF
	for i in int(SimConstants.MAX_SHOT_TIME / SimConstants.SIM_DT) + 1:
		if s.settled:
			break
		ShotSim.step_shot(s)
		min_x = minf(min_x, s.pos.x)
	t.ok(s.settled and min_x > g.lip_x + SimConstants.R_BALL - 0.01, "never through the lip (min x %.3f)" % min_x)
	t.ok(s.pos.x < 1.0, "…it rolled toward the tray (x %.2f)" % s.pos.x)


## A ball rolling on the deck slows down and stops short of the ramp.
func _deck_roll_out(t) -> void:
	var g := SimGeometry.arcade()
	var s := ShotSim.create_shot({"angle_deg": 0.0, "speed": 2.0, "rx": 1.5, "ry": SimConstants.R_BALL + 0.001, "rz": 0.0, "bx": 1.0, "bz": 0.0}, g)
	for i in int(SimConstants.MAX_SHOT_TIME / SimConstants.SIM_DT) + 1:
		if s.settled:
			break
		ShotSim.step_shot(s)
	t.ok(s.settled and s.t < 3.0, "a 2 m/s roll rests within 3 s (%.2f s)" % s.t)
	t.ok(s.pos.x > 1.5 and s.pos.x < g.ramp_x0, "…about a metre on, before the ramp (x %.2f)" % s.pos.x)
	# The same roll on a flat regulation floor: dropped on the third hit, as always.
	var r := ShotSim.create_shot({"angle_deg": 0.0, "speed": 2.0, "rx": 1.5, "ry": SimConstants.R_BALL + 0.001, "rz": 0.0, "bx": 1.0, "bz": 0.0}, SimGeometry.regulation())
	for i in 2000:
		if r.settled:
			break
		ShotSim.step_shot(r)
	t.ok(r.settled and r.floor_hits >= 3, "regulation: dropped on the third floor hit (%d)" % r.floor_hits)


func _short_miss_unchanged_elsewhere(t) -> void:
	# An ideal arcade shot still swishes with the ramp in play.
	var g := SimGeometry.arcade()
	t.ok(ShotSim.simulate_shot(Ballistics.ideal_launch_for(52.0, g), false, g)["made"], "ideal shot still drops")
	# A beach brick behaves as before: three floor hits and gone.
	var b := SimGeometry.beach()
	var s := ShotSim.create_shot({"angle_deg": 40.0, "speed": 4.0, "rx": 0.0, "ry": 1.85, "rz": 0.0, "bx": 1.0, "bz": 0.0}, b)
	for i in 2000:
		if s.settled:
			break
		ShotSim.step_shot(s)
	t.ok(s.settled and (s.floor_hits >= 3 or s.vel.length() < 0.6), "beach brick settles by the old rules")
