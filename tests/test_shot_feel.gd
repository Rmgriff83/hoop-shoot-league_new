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
	t.ok(ShotFeel.roll_delta(-0.05) < 0.0, "pushing up rolls the other way")
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
