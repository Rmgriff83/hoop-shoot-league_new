extends RefCounted
## Flick mapping properties, adapted from tests/aim.spec.ts for the new gesture.

const H := 1280.0  # reference viewport height


func _sample(vel_x: float, vel_y: float, travel_x: float, travel_y: float, dur := 0.15) -> Dictionary:
	return {
		"vel_x": vel_x, "vel_y": vel_y,
		"travel_x": travel_x, "travel_y": travel_y,
		"duration_s": dur, "viewport_h": H,
	}


func run(t) -> void:
	var tuning := FlickTuning.new()
	# This file exercises the LEGACY drag-length model (flick lab only), whose
	# band was fitted at these values. The shipped defaults are Ross's on-device
	# wind-up set (flick_tuning.gd), which the wind-up tests cover.
	tuning.flick_min_sh = 0.1
	tuning.flick_max_sh = 3.9
	tuning.dead_zone_px = 30.0
	var geo := SimGeometry.regulation()
	var anchor := FlickMap.v_ideal(geo)
	var v_min := FlickMap.V_MIN_FRAC * anchor
	var v_max := FlickMap.V_MAX_FRAC * anchor

	# The derived band reproduces the original tuned 7.0/11.0 at regulation.
	t.close(v_min, 7.0, 0.01, "regulation v_min ≈ 7.0")
	t.close(v_max, 11.0, 0.03, "regulation v_max ≈ 11.0")

	# power_curve: monotonic, spans [0,1], hits the control points.
	t.close(FlickMap.power_curve(0.0), 0.0, 1e-9, "curve(0)=0")
	t.close(FlickMap.power_curve(1.0), 1.0, 1e-9, "curve(1)=1")
	t.close(FlickMap.power_curve(0.20), 0.40, 1e-9, "curve P1")
	t.close(FlickMap.power_curve(0.75), 0.65, 1e-9, "curve P2")
	var prev := -1.0
	for i in 101:
		var v := FlickMap.power_curve(i / 100.0)
		t.ok(v >= prev, "curve monotonic at u=%.2f" % (i / 100.0))
		prev = v

	# The forgiving band: u∈[0.20, 0.75] (55% of input) maps to ~8.6–9.6 m/s
	# at regulation (band edges = v_min + span·curve(P)).
	var span := v_max - v_min
	t.close(v_min + span * FlickMap.power_curve(0.20), 8.6, 0.03, "band low ≈ 8.6")
	t.close(v_min + span * FlickMap.power_curve(0.75), 9.6, 0.03, "band high ≈ 9.6")

	# Cancels: dead zone, too short, sideways-dominant.
	t.eq(FlickMap.map_flick(_sample(0, -2000, 0, -20), tuning), {}, "dead zone cancels")
	t.eq(FlickMap.map_flick(_sample(0, -2000, 0, -300, 0.01), tuning), {}, "too-short cancels")
	t.eq(FlickMap.map_flick(_sample(2000, -100, 300, -100), tuning), {}, "sideways cancels")

	# A straight-up medium flick lands in the useful band, no lateral.
	var mid := FlickMap.map_flick(_sample(0, -1.8 * H, 0, -0.25 * H), tuning)
	t.ok(not mid.is_empty(), "medium flick fires")
	t.ok(mid["speed"] > 8.5 and mid["speed"] < 9.7, "medium flick in band (%.2f)" % mid["speed"])
	t.close(mid["vz"], 0.0, 1e-9, "straight flick has no vz")
	t.ok(mid["angle_deg"] > tuning.angle_low and mid["angle_deg"] < tuning.angle_high,
		"medium lift between angle bounds (%.1f)" % mid["angle_deg"])

	# Clamps: monster flick caps at v_max and angle_high; feather flick floors
	# at v_min — both bands anchored to the ideal speed at the flick's own arc.
	var monster := FlickMap.map_flick(_sample(0, -10.0 * H, 0, -0.9 * H), tuning)
	t.close(monster["angle_deg"], tuning.angle_high, 1e-9, "full travel caps angle")
	t.close(monster["speed"],
		FlickMap.V_MAX_FRAC * Ballistics.speed_for_angle(monster["angle_deg"]),
		1e-9, "monster flick caps at v_max for its arc")
	# Below flick_min_sh → u = 0 → v_min, whatever the tunable is set to.
	var feather := FlickMap.map_flick(_sample(0, -tuning.flick_min_sh * 0.5 * H, 0, -0.05 * H), tuning)
	t.close(feather["speed"],
		FlickMap.V_MIN_FRAC * Ballistics.speed_for_angle(feather["angle_deg"]),
		1e-9, "feather flick floors at v_min for its arc")
	t.close(feather["angle_deg"], tuning.angle_low + (tuning.angle_high - tuning.angle_low) * (0.05 / 0.45), 1e-6,
		"small travel ≈ low angle")

	# Lateral: right tilt → positive vz, left → negative, symmetric, clamped.
	var right := FlickMap.map_flick(_sample(400, -1.8 * H, 80, -0.3 * H), tuning)
	var left := FlickMap.map_flick(_sample(-400, -1.8 * H, -80, -0.3 * H), tuning)
	t.ok(right["vz"] > 0.0, "right tilt → +vz")
	t.ok(left["vz"] < 0.0, "left tilt → −vz")
	t.close(right["vz"], -left["vz"], 1e-9, "lateral symmetric")
	var hard_tilt := FlickMap.map_flick(_sample(2000, -2100, 250, -260), tuning)
	t.ok(absf(hard_tilt["vz"]) <= tuning.vz_max + 1e-9, "vz clamped")

	# Determinism: same sample twice → identical launch.
	var a := FlickMap.map_flick(_sample(120, -2.0 * H, 30, -0.3 * H), tuning)
	var b := FlickMap.map_flick(_sample(120, -2.0 * H, 30, -0.3 * H), tuning)
	t.eq(JSON.stringify(a), JSON.stringify(b), "flick mapping deterministic")
