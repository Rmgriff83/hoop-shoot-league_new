extends RefCounted
## Ball squash: the ball dents along the surface it actually hit, by an amount
## set by how hard it hit.
##
## What this replaces: the old squash wrote `mi.scale` AFTER `mi.basis`, and
## Godot's set_scale rebuilds the transform as R * diag(scale) — so the flatten
## ran along the ball's LOCAL Y, an axis tumbling with backspin, roll and a
## random grab orientation. The dent pointed nowhere in particular. Hence the
## central test here: deform the ball while it is spinning hard and prove the
## flattened axis is still the world-space contact normal.
##
## The extent of the deformed ball along a world direction `u` is |B^T u| (the
## ellipsoid you get by transforming a unit sphere by B). Because the squash
## matrix S is symmetric and the rotation R is orthonormal, B*B^T = S*S — so
## that extent is rotation-invariant, which is exactly the property under test.


func run(t) -> void:
	_pure_math(t)
	_survives_bad_input(t)
	_through_the_pool(t)


## Extent of the deformed unit sphere along world direction `u`.
static func _extent(b: Basis, u: Vector3) -> float:
	return (b.transposed() * u).length()


func _pure_math(t) -> void:
	var s := 0.12
	var normals: Array[Vector3] = [
		Vector3.UP, Vector3.RIGHT, Vector3.BACK, Vector3(1, 1, -1).normalized()]
	for n in normals:
		var d := BallPool._squash_basis(n, s)
		t.close(_extent(d, n), 1.0 - s, 1e-6, "flattens %.2v by exactly the squash amount" % n)
		# Any direction perpendicular to the normal bulges by half.
		var perp := n.cross(Vector3(0.3, 0.7, -0.6)).normalized()
		t.close(_extent(d, perp), 1.0 + s * 0.5, 1e-6, "bulges across %.2v" % n)
	t.eq(BallPool._squash_basis(Vector3.UP, 0.0), Basis.IDENTITY, "no squash is the identity")


func _survives_bad_input(t) -> void:
	var pool := BallPool.new()
	pool._ready()
	# A zero normal comes out of Colliders.rim_contact's d < 1e-9 guard.
	# Normalising it would put NaN in the basis and the ball would disappear.
	pool.squash_at(Vector3.ZERO, Vector3.ZERO, 9.0)
	var n: Vector3 = pool._squash_n[0]
	t.ok(not (is_nan(n.x) or is_nan(n.y) or is_nan(n.z)), "a zero normal is ignored, not normalised")
	t.close(pool._squash[0].velocity, 0.0, 1e-12, "and it does not kick the spring")


## The real path: a live ball, a contact, and the transform the pool writes.
func _through_the_pool(t) -> void:
	var pool := BallPool.new()
	pool._ready()
	var geo := SimGeometry.arcade()
	var shot := ShotSim.create_shot({
		"angle_deg": 50.0, "speed": 6.2, "rx": 0.0, "ry": 1.85,
		"rz": 0.0, "bx": 1.0, "bz": 0.0,
	}, geo)
	var balls: Array[BallState] = [shot]
	pool.update_balls(balls, false, 1.0 / 60.0)
	var here := Vector3(shot.pos.x, shot.pos.y, shot.pos.z)

	# Spin it hard: this is what the old code got wrong.
	pool._angle_by_ball[shot] = 7.3
	pool._roll_by_ball[shot] = 2.1

	# A wall hit from the side — the normal is world +X.
	pool.squash_at(here, Vector3.RIGHT, BallPool.IMPACT_REF)
	pool.update_balls(balls, false, 1.0 / 60.0)
	var b: Basis = pool._pool[0].basis
	var ex := _extent(b, Vector3.RIGHT)
	var ey := _extent(b, Vector3.UP)
	t.ok(ex < 0.995, "a side hit flattens WORLD x even while the ball spins (%.4f)" % ex)
	t.ok(ey > 1.002, "and bulges world y (%.4f)" % ey)
	t.ok(ey > ex, "the dent axis is the contact normal, not the ball's own axis")

	# The contact face stays on the surface rather than shrinking away from it.
	var sq := 1.0 - ex
	var drift: Vector3 = pool._pool[0].position - here
	t.close(drift.x, -SimConstants.R_BALL * sq, 1e-5, "the ball is pushed into the surface it dented")

	# Hardest possible hit is still capped.
	for i in 6:
		pool.squash_at(pool._pool[0].position, Vector3.RIGHT, 10_000.0)
		pool.update_balls(balls, false, 1.0 / 60.0)
	var peak := 1.0 - _extent(pool._pool[0].basis, Vector3.RIGHT)
	t.ok(peak <= BallPool.MAX_SQUASH + 1e-6,
		"no impact exceeds MAX_SQUASH (%.4f <= %.2f)" % [peak, BallPool.MAX_SQUASH])

	# A graze is much softer than a slam.
	var soft := BallPool.new()
	soft._ready()
	var soft_balls: Array[BallState] = [shot]
	soft.update_balls(soft_balls, false, 1.0 / 60.0)
	soft.squash_at(Vector3(shot.pos.x, shot.pos.y, shot.pos.z), Vector3.UP, 0.5)
	soft.update_balls(soft_balls, false, 1.0 / 60.0)
	var graze := 1.0 - _extent(soft._pool[0].basis, Vector3.UP)
	t.ok(graze < BallPool.MAX_SQUASH * 0.25,
		"a 0.5 m/s graze barely deforms (%.4f vs %.2f max)" % [graze, BallPool.MAX_SQUASH])

	# It recovers: back to a clean sphere at rest.
	for i in 120:
		pool.update_balls(balls, false, 1.0 / 60.0)
	t.close(_extent(pool._pool[0].basis, Vector3.RIGHT), 1.0, 1e-3, "the dent relaxes out")
	t.close((pool._pool[0].position - here).length(), 0.0, 1e-4, "and the ball returns to the sim's position")

	# Slot handover must not leave the next ball wearing this one's dent.
	var empty: Array[BallState] = []
	pool.update_balls(empty, false, 1.0 / 60.0)
	t.eq(pool._squash_n[0], Vector3.UP, "a freed slot forgets its contact normal")
