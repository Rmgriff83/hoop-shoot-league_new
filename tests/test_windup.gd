extends RefCounted
## Wind-up flick model: pull-back → arc, release speed → power, release tilt →
## sideways (dead band + gain) about the true line from the release origin.

const H := 1280.0


func _sample(vel_x: float, vel_y: float, pull_px: float, path_px := 400.0, duration := 0.3, curl := NAN) -> Dictionary:
	var s := {
		"vel_x": vel_x, "vel_y": vel_y, "pull_px": pull_px, "path_px": path_px,
		"travel_x": 0.0, "travel_y": -100.0, "pos_x": 360.0, "pos_y": 900.0,
		"duration_s": duration, "viewport_h": H,
	}
	if not is_nan(curl):
		s["curl"] = curl
	return s


## Release velocity tilted `deg` off vertical (positive = screen-right), speed sh/s.
func _tilted(deg: float, speed_sh: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(sin(a), -cos(a)) * (speed_sh * H)


func run(t) -> void:
	var geo := SimGeometry.arcade()
	var tuning := FlickTuning.new()
	var full_pull := tuning.pull_full_frac * H

	# 1. Arc from wind-up.
	t.close(FlickMap.windup_angle(0.0, H, tuning), tuning.angle_low, 1e-9, "no wind-up → angle_low")
	t.close(FlickMap.windup_angle(full_pull, H, tuning), tuning.angle_high, 1e-9, "full pull → angle_high")
	t.close(FlickMap.windup_angle(full_pull * 3.0, H, tuning), tuning.angle_high, 1e-9, "over-pull clamps")
	t.close(FlickMap.windup_angle(full_pull * 0.5, H, tuning),
		(tuning.angle_low + tuning.angle_high) / 2.0, 1e-9, "half pull → midpoint")
	t.close(FlickMap.windup_angle(-50.0, H, tuning), tuning.angle_low, 1e-9, "negative pull clamps to angle_low")

	# 2. Cancel rules.
	var up := _tilted(0.0, 1.5)
	t.eq(FlickMap.map_windup(_sample(up.x, up.y, 100.0, 10.0), tuning, geo), {}, "tap (tiny path) cancels")
	t.eq(FlickMap.map_windup(_sample(up.x, up.y, 100.0, 400.0, 0.01), tuning, geo), {}, "too-short cancels")
	var side := _tilted(70.0, 1.5)
	t.eq(FlickMap.map_windup(_sample(side.x, side.y, 100.0), tuning, geo), {}, "sideways release cancels")
	var down := Vector2(0.0, 1.5 * H)
	t.eq(FlickMap.map_windup(_sample(down.x, down.y, 100.0), tuning, geo), {}, "downward release cancels")
	var fizzle := _tilted(0.0, tuning.flick_min_sh * 0.2)
	t.eq(FlickMap.map_windup(_sample(fizzle.x, fizzle.y, 100.0), tuning, geo), {}, "no real flick after wind-up cancels")

	# 3. Arc is set by the pull, not by speed or release height.
	var origin := {"rx": 0.0, "ry": 1.6, "rz": 0.3}
	var slow := FlickMap.map_windup(_sample(up.x, up.y, full_pull * 0.5), tuning, geo, origin)
	var fast_v := _tilted(0.0, 2.8)
	var fast := FlickMap.map_windup(_sample(fast_v.x, fast_v.y, full_pull * 0.5), tuning, geo, origin)
	t.close(slow["angle_deg"], fast["angle_deg"], 1e-9, "same pull → same arc regardless of speed")
	t.close(slow["pull"], 0.5, 1e-9, "launch carries the pull fraction")
	t.ok(fast["speed"] > slow["speed"], "faster flick → more power")
	var none := FlickMap.map_windup(_sample(up.x, up.y, 0.0), tuning, geo, origin)
	t.close(none["angle_deg"], tuning.angle_low, 1e-9, "no wind-up → angle_low arc")

	# 4. Power band anchored at the REFERENCE arc for the real triangle: the pull
	#    never touches it; the hoop distance does (the anchor follows the hoop).
	var slant := sqrt(geo.hoop_x * geo.hoop_x + 0.3 * 0.3)
	var rise := geo.hoop_y - 1.6
	var anchor := Ballistics.speed_for_angle(FlickMap.ANCHOR_ANGLE_DEG, slant, rise)
	var monster_v := _tilted(0.0, 10.0)
	var monster := FlickMap.map_windup(_sample(monster_v.x, monster_v.y, full_pull), tuning, geo, origin)
	t.close(monster["speed"], FlickMap.V_MAX_FRAC * anchor, 1e-9, "monster flick caps at v_max of the reference-arc anchor")
	var feather_v := _tilted(0.0, tuning.flick_min_sh)
	var feather := FlickMap.map_windup(_sample(feather_v.x, feather_v.y, full_pull), tuning, geo, origin)
	t.close(feather["speed"], FlickMap.V_MIN_FRAC * anchor, 1e-9, "feather flick floors at v_min of the anchor")
	t.close(monster["dist"], slant, 1e-12, "launch carries the slant distance")
	t.close(monster["rz"], 0.3, 0.0, "launch carries the origin")
	var mid_v := _tilted(0.0, 2.2)
	var shallow := FlickMap.map_windup(_sample(mid_v.x, mid_v.y, full_pull * 0.2), tuning, geo, origin)
	var deep := FlickMap.map_windup(_sample(mid_v.x, mid_v.y, full_pull * 0.8), tuning, geo, origin)
	t.close(shallow["speed"], deep["speed"], 1e-12, "pull never changes power")
	t.ok(deep["angle_deg"] > shallow["angle_deg"] + 10.0, "pull changes only the arc")
	var near := FlickMap.map_windup(_sample(mid_v.x, mid_v.y, full_pull * 0.5), tuning, SimGeometry.arcade(2.4), origin)
	var far := FlickMap.map_windup(_sample(mid_v.x, mid_v.y, full_pull * 0.5), tuning, SimGeometry.arcade(3.4), origin)
	t.ok(far["speed"] > near["speed"] + 0.5, "the anchor follows the hoop: a far hoop maps the same flick to more speed")
	t.ok(far["dist"] > near["dist"] + 0.9, "and the launch carries the live distance")

	# 5. Sideways: straight release → true line; tilt → dead band + gain.
	var tx := geo.hoop_x / slant
	var tz := -0.3 / slant
	var straight := FlickMap.map_windup(_sample(up.x, up.y, 100.0), tuning, geo, origin)
	t.close(straight["bx"], tx, 1e-12, "straight release → true bearing x")
	t.close(straight["bz"], tz, 1e-12, "straight release → true bearing z")
	t.close(straight["vz"], 0.0, 0.0, "no additive vz in the wind-up model")
	var wob := _tilted(tuning.side_dead_deg * 0.5, 1.5)
	var wobble := FlickMap.map_windup(_sample(wob.x, wob.y, 100.0), tuning, geo, origin)
	t.close(wobble["bx"], tx, 1e-9, "wobble inside the dead band is ignored")
	var ten := _tilted(10.0, 1.5)
	var tilted := FlickMap.map_windup(_sample(ten.x, ten.y, 100.0), tuning, geo, origin)
	var expect := deg_to_rad((10.0 - tuning.side_dead_deg) * tuning.side_gain)
	var got := atan2(tx * tilted["bz"] - tz * tilted["bx"], tx * tilted["bx"] + tz * tilted["bz"])
	t.close(got, expect, 1e-6, "10° right tilt carries (10−dead)×gain toward +z (screen-right)")
	var neg := _tilted(-10.0, 1.5)
	var mirrored := FlickMap.map_windup(_sample(neg.x, neg.y, 100.0), tuning, geo, origin)
	var got_m := atan2(tx * mirrored["bz"] - tz * mirrored["bx"], tx * mirrored["bx"] + tz * mirrored["bz"])
	t.close(got_m, -expect, 1e-6, "left tilt mirrors")
	t.close(FlickMap.forgive_tilt(deg_to_rad(10.0), tuning), expect, 1e-12, "forgive_tilt formula")
	tuning.side_dead_deg = 0.0
	tuning.side_gain = 1.0
	t.close(FlickMap.forgive_tilt(0.3, tuning), 0.3, 1e-12, "dead 0 / gain 1 = full carry")
	tuning = FlickTuning.new()

	# 6. The launch drives the sim: bearing used as-is, and a centered flick at
	#    the flick speed whose absolute m/s equals the ideal for its arc drops in
	#    (the mapping is monotonic, so bisect the flick speed).
	var launched := ShotSim.create_shot(tilted, geo)
	t.close(launched.dir_x, tilted["bx"], 1e-12, "sim uses the launch bearing")
	var arc := FlickMap.windup_angle(full_pull * 0.6, H, tuning)
	var want := Ballistics.speed_for_angle(arc, slant, rise)
	var lo := tuning.flick_min_sh
	var hi := tuning.flick_max_sh
	t.ok(want > FlickMap.anchored_speed(slant, rise, lo, tuning) and want < FlickMap.anchored_speed(slant, rise, hi, tuning),
		"ideal for a mid arc lies inside the band")
	for i in 40:
		var mid := (lo + hi) / 2.0
		if FlickMap.anchored_speed(slant, rise, mid, tuning) < want:
			lo = mid
		else:
			hi = mid
	var ideal_v := _tilted(0.0, (lo + hi) / 2.0)
	var ideal := FlickMap.map_windup(_sample(ideal_v.x, ideal_v.y, full_pull * 0.6), tuning, geo, origin)
	t.close(ideal["speed"], want, 1e-6, "the right flick speed lands exactly on the ideal for its arc")
	t.ok(ShotSim.simulate_shot(ideal, false, geo)["made"], "centered ideal wind-up shot is made")

	# 7. Roll from curl, clamped; absent without curl. Explicit bx/bz normalize.
	var curled := FlickMap.map_windup(_sample(up.x, up.y, 100.0, 400.0, 0.3, 40.0), tuning, geo, origin)
	t.close(curled["roll"], minf((40.0 - tuning.roll_dead) * tuning.roll_gain, tuning.roll_max), 1e-9, "roll = (curl − dead) × gain, clamped to roll_max")
	var wobbly := FlickMap.map_windup(_sample(up.x, up.y, 100.0, 400.0, 0.3, tuning.roll_dead * 0.5), tuning, geo, origin)
	t.close(wobbly["roll"], 0.0, 1e-12, "curl inside roll_dead is ignored")
	var hooked_left := FlickMap.map_windup(_sample(up.x, up.y, 100.0, 400.0, 0.3, -40.0), tuning, geo, origin)
	t.close(hooked_left["roll"], -curled["roll"], 1e-9, "roll forgiveness is symmetric")
	# Backspin scales with launch speed (harder throw spins faster).
	t.close(straight["backspin"], tuning.backspin_per_mps * straight["speed"], 1e-9, "backspin = per_mps × speed")
	t.ok(fast["backspin"] > slow["backspin"], "faster flick → more backspin")
	t.close(ShotSim.create_shot(straight, geo).spin, straight["backspin"], 0.0, "sim takes the launch backspin")
	var whipped := FlickMap.map_windup(_sample(up.x, up.y, 100.0, 400.0, 0.3, 500.0), tuning, geo, origin)
	t.close(whipped["roll"], tuning.roll_max, 1e-9, "roll clamps")
	t.ok(not straight.has("roll"), "no curl → no roll key")
	var explicit := ShotSim.create_shot(
		{"angle_deg": 48.0, "speed": 6.0, "rx": 0.0, "ry": 1.6, "rz": 0.3, "bx": 2.0, "bz": 0.0}, geo)
	t.close(explicit.dir_x, 1.0, 1e-12, "explicit bearing normalized")
	t.close(explicit.dir_z, 0.0, 1e-12, "explicit bearing ignores the hoop axis")

	# 8. Without an origin the canonical release point is used, bearing +x.
	var canon := FlickMap.map_windup(_sample(up.x, up.y, 100.0), tuning, geo)
	t.close(canon["ry"], geo.release_h, 0.0, "no origin → canonical release height")
	t.close(canon["bx"], 1.0, 1e-12, "no origin → +x bearing")

	# 9. Tunables round-trip through dicts (persistence path).
	var d := tuning.to_dict()
	t.ok(d.has("angle_low") and d.has("pull_full_frac") and d.has("side_gain"), "to_dict has the wind-up fields")
	var other := FlickTuning.new()
	other.apply_dict({"angle_low": 44.0, "bogus": 1.0, "side_gain": "nope"})
	t.close(other.angle_low, 44.0, 0.0, "apply_dict sets known numeric fields")
	t.close(other.side_gain, tuning.side_gain, 0.0, "apply_dict ignores non-numeric values")
