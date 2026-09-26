class_name FlickMap
extends RefCounted
## Pure gesture → LaunchParams mapping (headless, float64, no nodes).
##
## The game uses the WIND-UP model (map_windup): hold to pick up, pull DOWN to
## wind up, flick UP to throw.
##   arc   ← pull-back distance (deepest point below the press), a deliberate
##           choice made before the throw, so it never tangles with thumb speed
##   power ← release velocity (screen-heights/sec through the power curve)
##   side  ← release-velocity tilt off vertical, dead-banded and gain-scaled,
##           applied to the true line from the release origin to the hoop axis
##
## map_flick is the legacy drag-length model, kept for the flick lab and tests.
## Samples are Dictionaries of floats in screen px (+y = down).

## Speed limits derive from the ideal make speed at the CURRENT geometry, so
## the mapping stays fair when the arcade board moves in depth. The fractions
## reproduce the original's tuned 7.0/11.0 band at regulation geometry
## (v_ideal(52°) = 9.03 → 7.00 / 11.02): those numbers were these fractions
## all along.
const ANCHOR_ANGLE_DEG := 52.0
const V_MIN_FRAC := 0.775
const V_MAX_FRAC := 1.22

## Piecewise-linear saturating power curve — exact control points from the
## original: the useful 8.6–9.6 m/s band occupies the middle 55% of input.
const P1_U := 0.20
const P1_V := 0.40
const P2_U := 0.75
const P2_V := 0.65

const MIN_DURATION_S := 0.03
## Wind-up: a release slower than this fraction of flick_min_sh is a fizzle
## (finger lifted without a throw), not a shot.
const WINDUP_MIN_SPEED_FRAC := 0.5


static func power_curve(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	if u <= P1_U:
		return u * (P1_V / P1_U)
	if u <= P2_U:
		return P1_V + (u - P1_U) * ((P2_V - P1_V) / (P2_U - P1_U))
	return P2_V + (u - P2_U) * ((1.0 - P2_V) / (1.0 - P2_U))


## Wind-up arc: pull-back (px) as a fraction of pull_full_frac × viewport
## height, lerped from angle_low (no wind-up) to angle_high (full pull).
static func windup_angle(pull_px: float, viewport_h: float, tuning: FlickTuning) -> float:
	var full := tuning.pull_full_frac * viewport_h
	var pull := clampf(pull_px / full, 0.0, 1.0) if full > 0.0 else 0.0
	return lerpf(tuning.angle_low, tuning.angle_high, pull)


## The make-band anchor speed for a geometry: the ideal dead-center speed at
## the anchor angle. Exposed for tests and the tuning overlay.
static func v_ideal(geo: SimGeometry) -> float:
	return Ballistics.speed_for_angle(ANCHOR_ANGLE_DEG, geo.hoop_x, geo.rise)


## Shot triangle from the release origin to the hoop axis:
## [dist (horizontal), rise, true-bearing x, true-bearing z]. Without an origin:
## the canonical lane (geo.hoop_x, geo.rise, +x).
static func _triangle(geo: SimGeometry, origin: Dictionary) -> Array:
	if origin.has("rx") and origin.has("ry") and origin.has("rz"):
		var dx: float = geo.hoop_x - origin["rx"]
		var dz: float = geo.hoop_z - origin["rz"]
		var dist := sqrt(dx * dx + dz * dz)
		var rise: float = geo.hoop_y - origin["ry"]
		if dist > 1e-9:
			return [dist, rise, dx / dist, dz / dist]
		return [dist, rise, 1.0, 0.0]
	return [geo.hoop_x, geo.rise, 1.0, 0.0]


## Wind-up power: the band is anchored at the ideal speed for a FIXED reference
## arc (ANCHOR_ANGLE_DEG) at the live distance/rise, then scaled by flick speed
## through the power curve. So the pull (arc) never touches power — a steep arc
## needs a visibly harder flick, a flat one a softer flick — while the anchor
## still follows the hoop's distance so the moving sweep stays fair.
static func anchored_speed(dist: float, rise: float, speed_sh: float, tuning: FlickTuning) -> float:
	var u := clampf(
		(speed_sh - tuning.flick_min_sh) / (tuning.flick_max_sh - tuning.flick_min_sh), 0.0, 1.0
	)
	var anchor := Ballistics.speed_for_angle(ANCHOR_ANGLE_DEG, dist, rise)
	var v_min := V_MIN_FRAC * anchor
	var v_max := V_MAX_FRAC * anchor
	return v_min + (v_max - v_min) * power_curve(u)


## Legacy band (map_flick / flick lab): anchored to the ideal speed AT THIS ARC
## for the real triangle, so a mid-band flick is near ideal for whatever arc.
static func _band_speed(angle_deg: float, dist: float, rise: float, speed_sh: float, tuning: FlickTuning) -> float:
	var u := clampf(
		(speed_sh - tuning.flick_min_sh) / (tuning.flick_max_sh - tuning.flick_min_sh), 0.0, 1.0
	)
	var anchor := Ballistics.speed_for_angle(angle_deg, dist, rise)
	if is_nan(anchor):
		anchor = Ballistics.speed_for_angle(ANCHOR_ANGLE_DEG, dist, rise)
	var v_min := V_MIN_FRAC * anchor
	var v_max := V_MAX_FRAC * anchor
	return v_min + (v_max - v_min) * power_curve(u)


## Sideways forgiveness: a signed tilt (rad) off the true line loses the dead
## band and is scaled by side_gain. Dead 0 / gain 1 = full physical carry.
static func forgive_tilt(tilt: float, tuning: FlickTuning) -> float:
	var dead := deg_to_rad(tuning.side_dead_deg)
	return signf(tilt) * maxf(0.0, absf(tilt) - dead) * tuning.side_gain


## Rotate a horizontal bearing about +y by ang (rad). +ang turns +x toward +z,
## which is screen-right for the time-trial camera.
static func rotate_bearing(tx: float, tz: float, ang: float) -> Array:
	var c := cos(ang)
	var s := sin(ang)
	return [tx * c - tz * s, tx * s + tz * c]


## WIND-UP model. sample keys: vel_x, vel_y (release velocity), pull_px (deepest
## pull-back below the press), path_px (total finger travel), duration_s,
## viewport_h, curl (optional). origin {"rx","ry","rz"} = the hand's sim-space
## point at release; without it the canonical point is used. Returns {} when
## the gesture cancels (tap, too short, sideways/downward release, no flick).
static func map_windup(sample: Dictionary, tuning: FlickTuning, geo: SimGeometry = null, origin: Dictionary = {}) -> Dictionary:
	if geo == null:
		geo = SimGeometry.regulation()
	var vel_x: float = sample["vel_x"]
	var vel_y: float = sample["vel_y"]
	var viewport_h: float = sample["viewport_h"]
	var path: float = sample.get("path_px", sqrt(
		sample.get("travel_x", 0.0) ** 2 + sample.get("travel_y", 0.0) ** 2))
	if path < tuning.dead_zone_px:
		return {}
	if sample["duration_s"] < MIN_DURATION_S:
		return {}
	# The throw itself must be upward-dominant (+y is down in screen space).
	if -vel_y < absf(vel_x):
		return {}
	var speed_sh := sqrt(vel_x * vel_x + vel_y * vel_y) / viewport_h
	if speed_sh < tuning.flick_min_sh * WINDUP_MIN_SPEED_FRAC:
		return {}

	# Arc ← wind-up. Power ← release speed on a band anchored at the reference
	# arc for the live triangle (the pull never touches it). Side ← release tilt.
	var pull_px: float = sample.get("pull_px", 0.0)
	var angle_deg := windup_angle(pull_px, viewport_h, tuning)
	var tri := _triangle(geo, origin)
	var speed := anchored_speed(tri[0], tri[1], speed_sh, tuning)
	var tilt := atan2(vel_x, -vel_y)
	var b := rotate_bearing(tri[2], tri[3], forgive_tilt(tilt, tuning))

	var launch := {
		"angle_deg": angle_deg,
		"speed": speed,
		"vz": 0.0,
		"rx": origin.get("rx", 0.0),
		"ry": origin.get("ry", geo.release_h),
		"rz": origin.get("rz", 0.0),
		"dist": tri[0],
		"rise": tri[1],
		"bx": b[0],
		"bz": b[1],
		"pull": clampf(pull_px / maxf(tuning.pull_full_frac * viewport_h, 1e-9), 0.0, 1.0),
		"backspin": tuning.backspin_per_mps * speed,
	}
	if sample.has("curl"):
		launch["roll"] = forgive_roll(sample["curl"], tuning)
	return launch


## Visual roll from gesture curl with the same forgiveness shape as sideways aim.
static func forgive_roll(curl: float, tuning: FlickTuning) -> float:
	var kept := signf(curl) * maxf(0.0, absf(curl) - tuning.roll_dead) * tuning.roll_gain
	return clampf(kept, -tuning.roll_max, tuning.roll_max)


## LEGACY drag-length model (flick lab, tests): arc ← upward travel length,
## power ← release speed, lateral ← gain-damped tilt as additive vz.
## origin (optional) solves the band for the real triangle and passes through.
static func map_flick(sample: Dictionary, tuning: FlickTuning, geo: SimGeometry = null, origin: Dictionary = {}) -> Dictionary:
	if geo == null:
		geo = SimGeometry.regulation()
	var has_origin := origin.has("rx") and origin.has("ry") and origin.has("rz")
	var tri := _triangle(geo, origin)
	var dist: float = tri[0]
	var rise: float = tri[1]
	var travel_x: float = sample["travel_x"]
	var travel_y: float = sample["travel_y"]
	var travel := sqrt(travel_x * travel_x + travel_y * travel_y)
	if travel < tuning.dead_zone_px:
		return {}
	if sample["duration_s"] < MIN_DURATION_S:
		return {}
	# Upward must dominate (+y is down in screen space).
	if -travel_y < absf(travel_x):
		return {}

	var vel_x: float = sample["vel_x"]
	var vel_y: float = sample["vel_y"]
	var viewport_h: float = sample["viewport_h"]
	var speed_sh := sqrt(vel_x * vel_x + vel_y * vel_y) / viewport_h

	# Arc ← upward travel length.
	var lift := clampf(-travel_y / (tuning.travel_full_frac * viewport_h), 0.0, 1.0)
	var angle_deg := lerpf(tuning.angle_low, tuning.angle_high, lift)
	var speed := _band_speed(angle_deg, dist, rise, speed_sh, tuning)

	# Lateral ← gain-damped flick tilt off vertical.
	var azimuth := atan2(vel_x, -vel_y)
	var vz := clampf(speed * sin(azimuth * tuning.az_gain), -tuning.vz_max, tuning.vz_max)

	var launch := {"angle_deg": angle_deg, "speed": speed, "vz": vz}
	if has_origin:
		launch["rx"] = origin["rx"]
		launch["ry"] = origin["ry"]
		launch["rz"] = origin["rz"]
		launch["dist"] = dist
		launch["rise"] = rise
	if sample.has("curl"):
		launch["roll"] = clampf(sample["curl"] * tuning.roll_gain, -tuning.roll_max, tuning.roll_max)
	return launch
