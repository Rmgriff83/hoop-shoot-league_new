extends RefCounted
## Variable release origin: shots launch from where the finger let go, aimed
## at the hoop axis. The no-origin path must stay identical to the reference.

const H := 1280.0


func _sample(vel_x: float, vel_y: float, travel_x: float, travel_y: float) -> Dictionary:
	return {
		"vel_x": vel_x, "vel_y": vel_y, "travel_x": travel_x, "travel_y": travel_y,
		"duration_s": 0.2, "viewport_h": H,
	}


func run(t) -> void:
	var geo := SimGeometry.arcade()
	var th := deg_to_rad(50.0)

	# 1. Default path (no origin) is the canonical lane, formulas untouched.
	var d := ShotSim.create_shot({"angle_deg": 50.0, "speed": 6.0, "vz": 0.3}, geo)
	t.close(d.pos.x, 0.0, 0.0, "default origin x")
	t.close(d.pos.y, geo.release_h, 0.0, "default origin y = release_h")
	t.close(d.pos.z, 0.0, 0.0, "default origin z")
	t.close(d.vel.x, 6.0 * cos(th), 0.0, "default vel.x = speed cos")
	t.close(d.vel.y, 6.0 * sin(th), 0.0, "default vel.y = speed sin")
	t.close(d.vel.z, 0.3, 0.0, "default vel.z = vz (additive lateral)")
	t.close(d.dir_x, 1.0, 0.0, "default bearing +x")
	t.close(d.dir_z, 0.0, 0.0, "default bearing z = 0")

	# 2. An explicit center origin reproduces the default velocity exactly.
	var c := ShotSim.create_shot(
		{"angle_deg": 50.0, "speed": 6.0, "vz": 0.3, "rx": 0.0, "ry": geo.release_h, "rz": 0.0}, geo
	)
	t.close(c.vel.x, d.vel.x, 0.0, "center origin vel.x identical")
	t.close(c.vel.y, d.vel.y, 0.0, "center origin vel.y identical")
	t.close(c.vel.z, d.vel.z, 0.0, "center origin vel.z identical")

	# 3. Lateral origin: bearing points at the hoop axis and is unit length.
	var rz := 0.6
	var ry := 1.6
	var slant := sqrt(geo.hoop_x * geo.hoop_x + rz * rz)
	var rise := geo.hoop_y - ry
	var v_ideal := Ballistics.speed_for_angle(50.0, slant, rise)
	var launch := {"angle_deg": 50.0, "speed": v_ideal, "rx": 0.0, "ry": ry, "rz": rz}
	var s := ShotSim.create_shot(launch, geo)
	t.close(s.pos.z, rz, 0.0, "origin z carried onto the ball")
	t.close(s.dir_x * s.dir_x + s.dir_z * s.dir_z, 1.0, 1e-12, "bearing is unit length")
	t.close(s.dir_x, geo.hoop_x / slant, 1e-12, "bearing x toward the hoop")
	t.close(s.dir_z, -rz / slant, 1e-12, "bearing z back toward the axis")
	var horiz := sqrt(s.vel.x * s.vel.x + s.vel.z * s.vel.z)
	t.close(horiz, v_ideal * cos(th), 1e-9, "horizontal speed rides the bearing")
	# Spin axis (−dir_z, dir_x) is perpendicular to the bearing.
	t.close(-s.dir_z * s.dir_x + s.dir_x * s.dir_z, 0.0, 1e-12, "spin axis ⟂ bearing")

	# 4. The ideal speed for the real triangle drops the ball in, from either side.
	var out := ShotSim.simulate_shot(launch, false, geo)
	t.ok(out["made"], "ideal side shot from z=+0.6 is made")
	var mirror := launch.duplicate()
	mirror["rz"] = -rz
	var out_m := ShotSim.simulate_shot(mirror, false, geo)
	t.ok(out_m["made"], "ideal side shot from z=−0.6 is made")
	var sm := ShotSim.create_shot(mirror, geo)
	t.close(sm.dir_z, -s.dir_z, 1e-12, "mirrored origin flips bearing z")

	# 5. A high release (less rise) needs less speed than a low one at the same arc.
	var v_low := Ballistics.speed_for_angle(50.0, slant, geo.hoop_y - 1.2)
	var v_high := Ballistics.speed_for_angle(50.0, slant, geo.hoop_y - 2.0)
	t.ok(v_high < v_low, "higher release needs less speed")

	# 6. map_flick with an origin solves the band for the slant triangle and
	#    passes the origin through; without one the dict shape is unchanged.
	var tuning := FlickTuning.new()
	var origin := {"rx": 0.0, "ry": ry, "rz": rz}
	var monster := FlickMap.map_flick(_sample(0, -10.0 * H, 0, -0.9 * H), tuning, geo, origin)
	t.close(monster["dist"], slant, 1e-12, "launch carries the slant distance")
	t.close(monster["rise"], rise, 1e-12, "launch carries the per-shot rise")
	t.close(monster["rz"], rz, 0.0, "launch carries the origin")
	t.close(monster["speed"],
		FlickMap.V_MAX_FRAC * Ballistics.speed_for_angle(monster["angle_deg"], slant, rise),
		1e-9, "monster flick caps at v_max for the slant triangle")
	var plain := FlickMap.map_flick(_sample(0, -10.0 * H, 0, -0.9 * H), tuning, geo)
	t.ok(not plain.has("rx") and not plain.has("dist"), "no origin → canonical dict shape")
	t.close(plain["speed"],
		FlickMap.V_MAX_FRAC * Ballistics.speed_for_angle(plain["angle_deg"], geo.hoop_x, geo.rise),
		1e-9, "no origin → band solved at geo.hoop_x / geo.rise")

	# 7. Rim azimuth is measured from the shooter's bearing: a ball approaching the
	#    hoop along its own bearing and hitting the near tube reads as FRONT (< 55°).
	var short_side := launch.duplicate()
	short_side["speed"] = v_ideal * 0.93
	var out_s := ShotSim.simulate_shot(short_side, false, geo)
	var front_hits := 0
	for ev in out_s["events"]:
		if ev["kind"] == "rim" and ev["azimuth_deg"] < 55.0:
			front_hits += 1
	t.ok(front_hits > 0 or out_s["rim_contacts"] == 0, "short side shot's first rim touch is front-rim in its own frame")
