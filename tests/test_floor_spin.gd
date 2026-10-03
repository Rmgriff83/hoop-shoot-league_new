extends RefCounted
## Ground friction torques the ball, it does not just slow it down.
##
## resolve_contact already computed the slip at the contact patch and bled the
## ball's PATH with it (v -= mu * r), but `spin` only ever decayed — so a ball
## landed with backspin and kept spinning the way it was thrown, all the way to
## rest. Real friction drives a landing ball toward rolling.
##
## Scoped to the FLOOR on purpose: a shot is already `resolved` the moment
## floor_hits > 0, so nothing here can move an outcome, and every other surface
## stays byte-identical. The golden grid confirms it (100 % agreement).


func run(t) -> void:
	_drives_toward_rolling(t)
	_other_surfaces_unchanged(t)
	_deterministic(t)


## Rolling means the contact point is stationary: w = -v_t / R.
static func _rolling_spin(s: BallState) -> float:
	var v_t: float = s.vel.x * s.dir_x + s.vel.z * s.dir_z
	return -v_t / SimConstants.R_BALL


## The arcade feel on a flat deck: the cage's ball-return ramp (which this
## shot would land on the crease of) has its own test, tests/test_ramp.gd.
static func _flat_arcade() -> SimGeometry:
	var geo := SimGeometry.arcade()
	geo.ramp_h = 0.0
	return geo


func _drives_toward_rolling(t) -> void:
	var geo := _flat_arcade()
	var s := ShotSim.create_shot({
		"angle_deg": 44.0, "speed": 5.4, "rx": 0.0, "ry": 1.85,
		"rz": 0.0, "bx": 1.0, "bz": 0.0,
	}, geo)
	t.ok(s.spin > 0.0, "the shot launches with backspin (%.1f rad/s)" % s.spin)
	var hits := 0
	var first_before := 0.0
	var first_after := 0.0
	while not s.settled and s.t < SimConstants.MAX_SHOT_TIME:
		var before := s.spin
		var n := s.floor_hits
		ShotSim.step_shot(s)
		if s.floor_hits > n:
			hits += 1
			# Every bounce must move spin TOWARD rolling, never away.
			var target := _rolling_spin(s)
			var gap_before := absf(target - before)
			var gap_after := absf(target - s.spin)
			t.ok(gap_after <= gap_before + 1e-9,
				"floor hit %d moves spin toward rolling (gap %.1f -> %.1f)" % [hits, gap_before, gap_after])
			if hits == 1:
				first_before = before
				first_after = s.spin
	t.ok(hits >= 2, "the shot bounced on the floor (%d hits)" % hits)
	# The headline behaviour: a backspinning ball grips and reverses its spin.
	t.ok(first_before > 0.0 and first_after < 0.0,
		"backspin flips through zero on the first bounce (%+.1f -> %+.1f)" % [first_before, first_after])


## Rim and board must be untouched — they only decay spin, as before.
func _other_surfaces_unchanged(t) -> void:
	var geo := _flat_arcade()
	for kind in [Colliders.KIND_RIM, Colliders.KIND_BOARD]:
		var s := ShotSim.create_shot({
			"angle_deg": 50.0, "speed": 6.0, "rx": 0.0, "ry": 1.85,
			"rz": 0.0, "bx": 1.0, "bz": 0.0,
		}, geo)
		s.spin = 20.0
		s.vel = SimVec3.new(3.0, -2.0, 0.0)
		var c := Colliders.Contact.new(kind, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0)
		Colliders.resolve_contact(s, c)
		# Pure decay keeps the sign and never overshoots toward rolling.
		t.ok(s.spin > 0.0 and s.spin < 20.0,
			"%s only decays spin (20.0 -> %.1f)" % [kind, s.spin])


func _deterministic(t) -> void:
	var launch := {"angle_deg": 44.0, "speed": 5.4, "rx": 0.0, "ry": 1.85,
		"rz": 0.0, "bx": 1.0, "bz": 0.0}
	var a := ShotSim.simulate_shot(launch, false, _flat_arcade())
	var b := ShotSim.simulate_shot(launch, false, _flat_arcade())
	t.eq(JSON.stringify(a), JSON.stringify(b), "floor spin stays deterministic")
