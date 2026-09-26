extends RefCounted
## Shooting spots: the sim launches from anywhere on the court toward the fixed
## hoop, the cull rule respects the release origin, arenas declare spots, and
## the ground scoreboard's yaw math points at the shooter.


func run(t) -> void:
	# Every spot sits on the key's arc: the same distance from the hoop as the key.
	var beach_geo := SimGeometry.beach()
	var beach_spots: Array = CosmeticLibrary.get_arena("beach").spots()
	var key_d := 0.0
	for sp in beach_spots:
		var pos: Vector3 = sp["pos"]
		var d := Vector2(beach_geo.hoop_x - pos.x, beach_geo.hoop_z - pos.z).length()
		if sp["name"] == "KEY":
			key_d = d
	for sp in beach_spots:
		if sp["name"] != "KEY":
			var pos: Vector3 = sp["pos"]
			var d := Vector2(beach_geo.hoop_x - pos.x, beach_geo.hoop_z - pos.z).length()
			t.close(d, key_d, 0.01, "%s is the key's distance from the hoop (%.2f vs %.2f)" % [sp["name"], d, key_d])
	_cull(t)
	_beach_spots_make(t)
	_arena_spots(t)
	_yaw(t)


static func _aimed(geo: SimGeometry, spot: Vector3, angle := 52.0, scale := 1.0) -> Dictionary:
	var dx := geo.hoop_x - spot.x
	var dz := geo.hoop_z - spot.z
	var slant := sqrt(dx * dx + dz * dz)
	var rise := geo.hoop_y - geo.release_h
	return {"angle_deg": angle, "speed": Ballistics.speed_for_angle(angle, slant, rise) * scale,
		"rx": spot.x, "ry": geo.release_h, "rz": spot.z, "bx": dx / slant, "bz": dz / slant}


func _cull(t) -> void:
	var geo := SimGeometry.beach()
	var s := ShotSim.create_shot(_aimed(geo, Vector3(2.9, 0.0, -4.0)), geo)
	for i in int(0.5 / SimConstants.SIM_DT):
		ShotSim.step_shot(s)
	t.ok(not s.settled and s.t > 0.45, "a baseline release 4 m off the hoop's z is not culled at launch (t=%.2f)" % s.t)
	t.ok(ShotSim.simulate_shot(_aimed(geo, Vector3(2.9, 0.0, -4.0)), false, geo)["made"], "ideal baseline shot is made")


func _beach_spots_make(t) -> void:
	var geo := SimGeometry.beach()
	var arena := CosmeticLibrary.get_arena("beach")
	if arena == null:
		t.ok(false, "beach arena missing")
		return
	for sp in arena.spots():
		var pos: Vector3 = sp["pos"]
		var out := ShotSim.simulate_shot(_aimed(geo, pos), false, geo)
		t.ok(out["made"], "ideal 52° from %s (%.2f, %.2f) is made (%s)" % [sp["name"], pos.x, pos.z, out["type"]])
		var short := ShotSim.simulate_shot(_aimed(geo, pos, 52.0, 0.93), false, geo)
		t.ok(not short["made"], "7 %% short from %s misses" % sp["name"])


func _arena_spots(t) -> void:
	var plain := ArenaSet.new()
	t.eq(plain.spots().size(), 1, "an arena with no spots has one default spot")
	t.ok(plain.spots()[0]["pos"] == Vector3.ZERO, "the default spot is the origin")
	var beach := CosmeticLibrary.get_arena("beach")
	if beach != null:
		var sp := beach.spots()
		t.eq(sp.size(), 5, "beach has five spots")
		t.eq(sp[0]["name"], "KEY", "beach default spot is the key")
		t.ok(sp[0]["pos"] == Vector3.ZERO, "key spot is the origin")
		t.ok(sp[3]["pos"].z < -3.0 and sp[4]["pos"].z > 3.0, "baseline spots are out wide")
	var cage := CosmeticLibrary.get_arena("cage")
	if cage != null:
		t.eq(cage.spots().size(), 1, "cage has only the default spot")


func _yaw(t) -> void:
	var board := Vector3(4.0, 0.0, -0.46)
	t.close(CourtGeometry.yaw_toward(board, Vector3(0.0, 0.0, -0.46)), 0.0, 1e-9, "shooter straight ahead → yaw 0")
	t.close(CourtGeometry.yaw_toward(board, Vector3(4.0, 0.0, 5.0)), PI / 2.0, 1e-9, "shooter to the east → +90°")
	t.close(CourtGeometry.yaw_toward(board, Vector3(4.0, 0.0, -6.0)), -PI / 2.0, 1e-9, "shooter to the west → −90°")
