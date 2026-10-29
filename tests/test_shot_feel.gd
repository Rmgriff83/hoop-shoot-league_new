extends RefCounted
## Shot feel (design 44a, Ross 2026-10-27): the wind-up reads on the held
## ball — it slides back along the camera ray toward you, rolls with the
## drag, and a cancelled grab eases back. Presentation only: Ross's sandbox
## numbers, verbatim, and the ball always under the finger.


func run(t) -> void:
	# Ross's values.
	t.eq([ShotFeel.PULL_FULL_PX, ShotFeel.PULL_DEPTH_M, ShotFeel.PULL_EXTRA_SCALE], [270.0, 0.32, 0.04], "full pull 270 px, 0.32 m toward you, +4 %")
	t.eq([ShotFeel.ROLL_WITH_DRAG, ShotFeel.HELD_SPIN_RPM, ShotFeel.SETTLE_S], [0.6, 0.0, 0.08], "roll 0.6, no held spin, settle 0.08 s")
	# The depth: ease out, clamped at the full pull.
	t.close(ShotFeel.depth(0.0), 0.0, 1e-9, "no pull, no depth")
	t.close(ShotFeel.depth(270.0), 0.32, 1e-9, "the full pull slides the ball 0.32 m toward you")
	t.close(ShotFeel.depth(135.0), 0.32 * 0.75, 1e-9, "ease out: half the pull is three quarters of the depth")
	t.close(ShotFeel.depth(600.0), 0.32, 1e-9, "past the full pull nothing more")
	t.close(ShotFeel.depth(-40.0), 0.0, 1e-9, "a negative pull is none")
	t.close(ShotFeel.scale(270.0), 1.04, 1e-9, "+4 % on top of perspective at full pull")
	t.close(ShotFeel.scale(0.0), 1.0, 1e-9, "true size at rest")
	# Under the finger: the same ray from the camera, shorter by the depth.
	var cam := Vector3(-1.35, 1.55, 0.0)
	var hand := Vector3(0.0, 1.1, 0.3)
	var p := ShotFeel.held_pos(cam, hand, 0.32)
	t.close((p - cam).normalized().dot((hand - cam).normalized()), 1.0, 1e-5, "the ball stays on the camera→hand ray")
	t.close((hand - cam).length() - (p - cam).length(), 0.32, 1e-5, "…exactly the depth nearer the camera")
	t.eq(ShotFeel.held_pos(cam, hand, 0.0), hand, "no depth: the hand point itself")
	t.ok((ShotFeel.held_pos(cam, cam + Vector3(0.1, 0, 0), 0.5) - cam).length() <= 1e-9, "never past the camera")
	# The roll: 0.6 × true rolling, top toward you on a pull down.
	t.close(ShotFeel.roll_delta(0.121), 0.6, 1e-9, "a pull of one radius rolls 0.6 rad")
	t.close(ShotFeel.roll_delta(-0.05), 0.0, 1e-12, "pushing up (the flick) adds no roll — only the pull turns it (Ross, 2026-10-28)")
	t.close(ShotFeel.roll_delta(0.05) + ShotFeel.roll_delta(-0.05), ShotFeel.roll_delta(0.05), 1e-12, "…so a pull then a flick leaves the pull's roll")
	# The settle: cubic out, 0 → 1 over SETTLE_S, monotonic.
	t.close(ShotFeel.settle(0.0), 0.0, 1e-9, "settle starts where it was")
	t.close(ShotFeel.settle(1.0), 1.0, 1e-9, "…and is home at SETTLE_S")
	t.close(ShotFeel.settle(0.5), 0.875, 1e-9, "cubic out: most of the way at half time")
	var last := -1.0
	var mono := true
	for i in 11:
		var v := ShotFeel.settle(i / 10.0)
		mono = mono and v >= last
		last = v
	t.ok(mono, "the settle never reverses")
	t.close(ShotFeel.held_spin_rad(1.0, 1.0), 0.0, 1e-12, "no idle spin while held (HELD_SPIN_RPM 0)")
	# The pool's pose: the roll rides the grab orientation, the scale is only the ball's.
	var pool := BallPool.new()
	pool._ready()
	pool.update_balls([], true, 0.016)   # a fresh pickup: a grab orientation
	var base := pool.held_basis()
	var roll := Basis(Vector3(0, 0, 1), 0.4)
	pool.set_held_pose(Vector3(0.2, 1.0, 0.0), roll, 1.04)
	t.close(pool.held_scale(), 1.04, 1e-6, "set_held_pose scales the held ball")
	t.ok(pool.held_basis().is_equal_approx(roll * base), "…the roll on top of the grab orientation")
	pool.set_held_position(Vector3.ZERO)
	t.close(pool.held_scale(), 1.0, 1e-6, "set_held_position is back at true size")
	t.ok(pool.held_basis().is_equal_approx(roll * base), "…keeping the roll")
	pool.free()
	# The release blend (Ross, 2026-10-28): a ball let go while drawn nearer
	# and larger starts its flight there and eases to the sim's pose over
	# RELEASE_S, instead of snapping back on frame one.
	t.close(ShotFeel.RELEASE_S, 0.16, 1e-12, "the release eases out over 0.16 s (0.08 was too quick for Ross)")
	var rp := BallPool.new()
	rp._ready()
	rp.update_balls([], true, 0.016)
	var shot := ShotSim.create_shot({"angle_deg": 50.0, "speed": 6.2, "rx": 0.0, "ry": 1.85, "rz": 0.0, "bx": 1.0, "bz": 0.0}, SimGeometry.arcade())
	var sim_at := Vector3(shot.pos.x, shot.pos.y, shot.pos.z)
	var drawn_at := sim_at + Vector3(-0.3, 0.0, 0.0)
	rp.set_held_pose(drawn_at, Basis.IDENTITY, 1.04)
	var flight: Array[BallState] = [shot]
	rp.update_balls(flight, false, 0.016)
	var fp: Dictionary = rp.flight_pose(0)
	var gap := (Vector3(fp["pos"]) - sim_at).length()
	t.ok(fp["blending"], "frame one of the flight is still blending")
	t.ok(gap > 0.1 and gap < 0.3, "…the ball is between the hand's pose and the sim's (%.3f m from the sim's)" % gap)
	t.ok((Vector3(fp["pos"]) - drawn_at).length() < (drawn_at - sim_at).length(), "…and on its way from where it was drawn")
	t.ok(float(fp["scale"]) > 1.0 and float(fp["scale"]) < 1.04, "…the extra size easing out too (%.3f)" % float(fp["scale"]))
	for _i in 12:
		rp.update_balls(flight, false, 0.016)
	fp = rp.flight_pose(0)
	t.ok(not fp["blending"], "after 0.2 s the blend is over")
	t.ok((Vector3(fp["pos"]) - sim_at).length() < 1e-5, "…the ball sits on the sim's point")
	t.close(float(fp["scale"]), 1.0, 1e-5, "…at true size")
	rp.free()
