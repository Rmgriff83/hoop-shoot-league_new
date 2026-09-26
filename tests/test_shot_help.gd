extends RefCounted
## Shot help's two numbers. This is the one piece of the readout that can
## silently lie to the player, so it is pinned against the real ballistics
## rather than against itself.


func run(t) -> void:
	var geo := SimGeometry.arcade()
	var tuning := FlickTuning.new()
	var origin := Vector3(0.0, 1.6, 0.3)
	var dx := geo.hoop_x - origin.x
	var dz := geo.hoop_z - origin.z
	var dist := sqrt(dx * dx + dz * dz)
	var rise := geo.hoop_y - origin.y

	# 1. The load-bearing invariant: speed_for_angle() is BY DEFINITION the
	#    speed that puts the ball on the rim axis, so the percentage the player
	#    sees at that speed must be exactly 100. If this drifts, the gauge lies.
	#
	#    It holds for every arc that ARRIVES DESCENDING, which is every arc that
	#    can actually score — the sim only counts a downward crossing of the
	#    ring. Flatter arcs are covered separately in section 3.
	for angle in [40.0, 45.0, 52.0, 60.0, 68.0, 71.0]:
		var ideal := Ballistics.speed_for_angle(angle, dist, rise)
		t.ok(not is_nan(ideal), "arc %d is reachable geometry" % int(angle))
		t.close(AimReadout.reach_pct(angle, ideal, dist, rise), 100.0, 1e-6,
			"ideal speed at %d° reads 100%%" % int(angle))
	for d in [2.2, 2.6, 3.4, 7.24]:
		var ideal2 := Ballistics.speed_for_angle(52.0, d, rise)
		t.close(AimReadout.reach_pct(52.0, ideal2, d, rise), 100.0, 1e-6,
			"ideal reads 100%% at distance %.2f" % d)

	# 2. Monotonic and correctly signed: harder is longer, softer is shorter.
	var mid := Ballistics.speed_for_angle(52.0, dist, rise)
	t.ok(AimReadout.reach_pct(52.0, mid * 1.05, dist, rise) > 100.0, "over-hit reads long")
	t.ok(AimReadout.reach_pct(52.0, mid * 0.95, dist, rise) < 100.0, "under-hit reads short")
	var a := AimReadout.reach_pct(52.0, mid * 0.90, dist, rise)
	var b := AimReadout.reach_pct(52.0, mid * 0.98, dist, rise)
	t.ok(a < b, "percentage rises with speed")

	# 3. Flat arcs. Two regimes, and the number has to stay sane across both.
	#
	#    (a) Flat but still cresting the rim: at 32° the ideal speed puts the
	#        ball at the ring while it is STILL RISING — its apex is rim height
	#        almost exactly. It would sail on and come down well past the hoop,
	#        so reading LONG is correct, not a bug. (32° also needs 7.66 m/s
	#        against a 6.90 ceiling, so it is unreachable anyway — see 4.)
	var cresting := AimReadout.reach_pct(32.0, Ballistics.speed_for_angle(32.0, dist, rise), dist, rise)
	t.ok(cresting > 100.0, "a shot arriving on the way up reads long (got %.1f)" % cresting)

	#    (b) Too flat to reach rim height at all: no crossing exists, so the
	#        apex is used instead. Must stay finite and honestly short rather
	#        than blowing up on a negative discriminant.
	var flat := AimReadout.reach_pct(19.0, 4.5, dist, rise)
	t.ok(not is_nan(flat) and flat > 0.0 and flat < 100.0,
		"a shot that never reaches rim height reads short, not NaN (got %.1f)" % flat)

	#    ...and the two branches JOIN, rather than stepping. At the speed whose
	#    apex lands exactly on rim height the discriminant is zero, so both
	#    formulas reduce to the same apex time.
	#
	#    Note this join is continuous but NOT smooth: sqrt(disc) has an infinite
	#    derivative at zero, so the reading moves fast either side of it. That
	#    is real physics, not a glitch — a shot grazing the rim height is
	#    genuinely on a knife edge — so test the value AT the join and the
	#    ordering around it, never a tight epsilon across it.
	var g: float = SimConstants.G
	var th := deg_to_rad(45.0)
	var graze := sqrt(2.0 * g * rise) / sin(th)   # apex lands exactly on rim height
	var apex_pct := (graze * cos(th)) * (graze * sin(th) / g) / dist * 100.0
	t.close(AimReadout.reach_pct(45.0, graze, dist, rise), apex_pct, 0.5,
		"at the join both branches give the apex reading")
	var prev := -1.0
	for k in 9:
		var v := graze * (0.99 + 0.0025 * float(k))
		var got := AimReadout.reach_pct(45.0, v, dist, rise)
		t.ok(got > prev, "reading rises with speed across the join (%.4f → %.2f%%)" % [v, got])
		prev = got

	# 4. The red threshold is the real power ceiling, not a hardcoded angle.
	#    Below ~30° at arcade geometry nothing scores at any flick strength.
	var anchor := Ballistics.speed_for_angle(FlickMap.ANCHOR_ANGLE_DEG, dist, rise)
	var ceiling: float = FlickMap.V_MAX_FRAC * anchor
	t.ok(Ballistics.speed_for_angle(19.0, dist, rise) > ceiling,
		"the minimum arc is unreachable at full power")
	t.ok(Ballistics.speed_for_angle(52.0, dist, rise) <= ceiling,
		"the anchor arc is comfortably reachable")
	# The floor never binds: the cheapest arc still needs more than the weakest
	# flick delivers, so only the ceiling can make a shot impossible.
	t.ok(Ballistics.speed_for_angle(52.0, dist, rise) > FlickMap.V_MIN_FRAC * anchor,
		"the power floor never rules an arc out")

	# 5. The setting has three steps, and it used to be a bool. An existing save
	#    must not silently reset to off when it grows the middle step.
	var AppScript := load("res://game/autoload/app.gd")
	t.eq(AppScript.shot_help_from_saved(true), AppScript.SHOT_HELP_FULL,
		"a legacy true reads as the full treatment")
	t.eq(AppScript.shot_help_from_saved(false), AppScript.SHOT_HELP_OFF,
		"a legacy false reads as off")
	t.eq(AppScript.shot_help_from_saved(1), AppScript.SHOT_HELP_NUMBERS, "1 is numbers only")
	t.eq(AppScript.shot_help_from_saved(2), AppScript.SHOT_HELP_FULL, "2 is numbers + arc")
	t.eq(AppScript.shot_help_from_saved(7), AppScript.SHOT_HELP_FULL, "out of range clamps up")
	t.eq(AppScript.shot_help_from_saved(-3), AppScript.SHOT_HELP_OFF, "out of range clamps down")
	t.eq(AppScript.shot_help_from_saved("nonsense"), AppScript.SHOT_HELP_OFF, "junk reads as off")
	t.eq(AppScript.SHOT_HELP_LABELS.size(), 3, "every mode has a label")
