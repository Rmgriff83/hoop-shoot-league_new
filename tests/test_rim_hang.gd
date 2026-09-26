extends RefCounted
## A ball that drops softly into the ring must be allowed to finish the drop.
##
## The dead-ball safety net in ShotSim kills any ball resting off the floor
## after half a second. Net drag bleeds a soft entry below its 0.4 m/s trip
## wire while the ball is still threading the ring, so the rule used to fire
## MID-DROP: the ball vanished in mid-air and was scored a miss even though it
## was on its way through. Found from a live report — "it disappears when it
## was about to fall into the hoop".
##
## Measured before the fix: of 2583 swept shots, four died to that rule, all
## four on the rim, and given more time NONE stalled — two fell in, two fell
## out, needing at most 0.85 s more. The rule was not protecting against
## anything; it was stealing makes.


func run(t) -> void:
	_soft_drop_finishes(t)
	_sweep_has_no_midair_kills(t)
	_wedges_still_die(t)


## The exact shot from the report: a 49° arc that enters slow and hangs.
func _soft_drop_finishes(t) -> void:
	var geo := SimGeometry.arcade()
	var s := ShotSim.create_shot({
		"angle_deg": 49.0, "speed": 5.72,
		"rx": 0.0, "ry": 1.85, "rz": 0.0, "bx": 1.0, "bz": 0.0,
	}, geo)
	while not s.settled and s.t < SimConstants.MAX_SHOT_TIME:
		ShotSim.step_shot(s)
	t.ok(s.ever_entered, "the 49° soft drop enters the ring")
	t.ok(s.made, "a ball that enters the ring and keeps dropping is a MAKE, not a vanishing miss")
	t.eq(ShotClassify.classify_shot(s)["made"], true, "and it classifies as made")


## Nothing may be deleted while it is inside the cylinder heading down — that
## is the mid-air disappearance, whatever the launch.
func _sweep_has_no_midair_kills(t) -> void:
	var geo := SimGeometry.arcade()
	var rise: float = geo.hoop_y - 1.85
	var killed := 0
	var worst := ""
	for ai in 41:
		var angle: float = 34.0 + ai * 0.85
		var ideal: float = Ballistics.speed_for_angle(angle, geo.hoop_x, rise)
		if is_nan(ideal):
			continue
		for si in 25:
			var speed: float = ideal * (0.94 + si * 0.005)
			var s := ShotSim.create_shot({
				"angle_deg": angle, "speed": speed,
				"rx": 0.0, "ry": 1.85, "rz": 0.0, "bx": 1.0, "bz": 0.0,
			}, geo)
			while not s.settled and s.t < SimConstants.MAX_SHOT_TIME:
				var in_cyl := s.in_cylinder
				var falling: bool = s.vel.y <= 0.0
				ShotSim.step_shot(s)
				if s.settled and s.slow_time > 0.5 and in_cyl and falling and not s.made:
					killed += 1
					worst = "%.1f° v=%.2f at y=%+.3f below the rim" % [angle, speed, s.pos.y - geo.hoop_y]
					break
	t.eq(killed, 0, "no shot is deleted mid-drop inside the ring (%s)" % worst)


## The exemption must not save a genuinely wedged ball: the gap behind the rim
## is never inside the cylinder, so the half-second rule still applies there.
func _wedges_still_die(t) -> void:
	var s := ShotSim.create_shot({"angle_deg": 50.0, "speed": Ballistics.speed_for_angle(50.0)})
	s.pos = SimVec3.new(7.55, 3.2, 0.0)
	s.vel = SimVec3.new(0.05, 0.0, 0.0)
	var t0 := s.t
	for i in 1200:
		if s.settled:
			break
		ShotSim.step_shot(s)
	t.ok(s.settled and s.t - t0 < 3.0, "a ball dropped in the rim-board gap still dies promptly (%.2f s)" % (s.t - t0))
