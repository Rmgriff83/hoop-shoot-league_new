extends RefCounted
## Lateral hoop pose (hoop_z): every collider and the in-cylinder test are
## relative to the rim axis, so a hoop that has slid sideways on the cage
## rails scores and bounces exactly like a centred one, just displaced.


func run(t) -> void:
	var geo := SimGeometry.arcade().with_pose(2.6, 0.4)
	var z := geo.hoop_z

	# Rim: the tube is where the axis is, not at z 0.
	var on_rim := SimVec3.new(geo.hoop_x + SimConstants.R_RIM, geo.hoop_y, z)
	var c := Colliders.rim_contact(on_rim, geo)
	t.ok(c != null, "rim contact at the slid rim")
	if c != null:
		t.close(c.qz, z, 1e-9, "rim contact point sits on the slid axis")
	t.ok(Colliders.rim_contact(SimVec3.new(geo.hoop_x + SimConstants.R_RIM, geo.hoop_y, 0.0), geo) == null,
		"nothing left at the old rim position")

	# Board: the face rectangle follows the axis.
	var cy := (geo.board_bottom + geo.board_top) / 2.0
	var face := Colliders.board_contact(SimVec3.new(geo.board_x - SimConstants.R_BALL + 0.01, cy, z + 0.6), geo)
	t.ok(face != null and face.nx < -0.99, "face contact inside the slid rectangle")
	t.ok(Colliders.board_contact(SimVec3.new(geo.board_x - SimConstants.R_BALL + 0.01, cy, -0.5), geo) == null,
		"old rectangle edge is now empty air")
	var side := Colliders.board_contact(SimVec3.new(geo.board_x + 0.025, cy, z + geo.board_half_w + 0.05), geo)
	t.ok(side != null and side.nz > 0.5, "side-edge normal points outward from the slid board")

	# Bracket clamp centred on the axis.
	var br := Colliders.bracket_contact(SimVec3.new((geo.bracket_x0 + geo.bracket_x1) / 2.0, geo.bracket_y0 + 0.05, z + 0.3), geo)
	t.ok(br != null, "bracket contact near the slid bracket")
	if br != null:
		t.close(br.qz, z + SimConstants.BRACKET_HALF_W, 1e-9, "bracket clamp centred on hoop_z")

	# A side release aimed at the slid axis makes, and rim azimuths stay sane.
	var rz := -0.6
	var dz := z - rz
	var slant := sqrt(geo.hoop_x * geo.hoop_x + dz * dz)
	var launch := {
		"angle_deg": 52.0, "speed": Ballistics.speed_for_angle(52.0, slant, geo.rise),
		"rx": 0.0, "ry": geo.release_h, "rz": rz, "bx": geo.hoop_x / slant, "bz": dz / slant,
	}
	var out := ShotSim.simulate_shot(launch, false, geo)
	t.ok(out["made"], "side release aimed at the slid hoop makes (%s)" % out["type"])
	var again := ShotSim.simulate_shot(launch, false, geo)
	t.eq(JSON.stringify(out), JSON.stringify(again), "lateral sim is deterministic")
	# Rim events measured from the shot's own bearing: never > 180.
	var s := ShotSim.create_shot(launch, geo)
	while not s.resolved:
		ShotSim.step_shot(s)
	for ev in s.events:
		if ev.has("azimuth_deg"):
			t.ok(ev["azimuth_deg"] >= 0.0 and ev["azimuth_deg"] <= 180.0, "azimuth in range")
