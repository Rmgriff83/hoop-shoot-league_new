extends RefCounted
## Home screen cards (docs/HOME.md): the pan loops and stays inside the cage
## while keeping the hoop ahead of the camera, every arena carries a title
## pose, and every card's modes still resolve through App.AREA_MODES. The
## chrome itself is tests/test_home_ui.gd.


func run(t) -> void:
	_pan(t)
	_poses(t)
	_routing(t)


func _pan(t) -> void:
	var cage := CosmeticLibrary.get_arena("cage")
	var spec := TitlePan.spec_of(cage)
	var period := float(spec["period_s"])
	var p0 := TitlePan.pose(spec, 0.0)
	var pT := TitlePan.pose(spec, period)
	t.ok(p0["pos"].distance_to(pT["pos"]) < 0.02, "the truck loops after one period (%.3f m apart)" % p0["pos"].distance_to(pT["pos"]))
	t.eq(p0["look"], cage.title_look_at, "look target is the arena's")
	var far := 0.0
	for i in 57:
		var tt := period * i / 56.0
		var p := TitlePan.pose(spec, tt)
		var pos: Vector3 = p["pos"]
		# Inside the cage (x −1.8…4.4, z ±1.26) and above the ramp.
		t.ok(pos.x > -1.8 and pos.x < 4.4 and absf(pos.z) < 1.26 and pos.y > 1.2 and pos.y < 3.8,
			"pose at %.1f s inside the cage (%s)" % [tt, str(pos)]) if i % 8 == 0 else null
		if not (pos.x > -1.8 and pos.x < 4.4 and absf(pos.z) < 1.26 and pos.y > 1.2 and pos.y < 3.8):
			t.ok(false, "pose at %.1f s left the cage (%s)" % [tt, str(pos)])
		# The hoop stays well ahead of the lens: looking "forward" the whole time.
		var fwd: Vector3 = (p["look"] - pos).normalized()
		t.ok(fwd.x > 0.8, "camera faces the hoop at %.1f s (fwd.x %.2f)" % [tt, fwd.x]) if i % 8 == 0 else null
		far = maxf(far, pos.distance_to(TitlePan.pose(spec, tt + 1.0 / 60.0)["pos"]) * 60.0)
	t.ok(far < 0.35, "the pan never moves faster than 0.35 m/s (%.2f)" % far)
	# The bob is not a metronome on the truck.
	t.ok(absf(TitlePan.BOB_RATIO - 0.5) > 0.05 and absf(TitlePan.BOB_RATIO - 1.0) > 0.05, "bob period differs from the truck's")


func _poses(t) -> void:
	for id in ["cage", "beach", "city"]:
		var a := CosmeticLibrary.get_arena(id)
		t.ok(a != null, "%s arena resolves" % id)
		if a == null:
			continue
		t.ok(a.title_fov > 30.0 and a.title_fov < 90.0, "%s title fov sane (%.0f)" % [id, a.title_fov])
		t.ok(a.title_period_s >= 10.0, "%s pan is slow (%.0f s)" % [id, a.title_period_s])
		t.ok(a.title_drift.length() < 1.5, "%s drift is gentle (%.2f m)" % [id, a.title_drift.length()])
		t.ok(a.title_look_at.x > a.title_cam_pos.x, "%s camera looks toward the hoop side" % id)
	var beach := CosmeticLibrary.get_arena("beach")
	t.ok(beach.title_cam_pos != CosmeticLibrary.get_arena("cage").title_cam_pos, "the beach has its own pose")


func _routing(t) -> void:
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		return
	for card in ["cage", "beach", "city"]:
		for mode in ["trial", "practice"]:
			var id: String = app.AREA_MODES[mode][card]
			t.eq(app.mode_config(id)["location"], card, "%s/%s resolves to a %s mode" % [card, mode, card])
		t.ok(not LeagueData.league(card).is_empty(), "%s has a league" % card)
	t.eq(int(app.home_card), 0, "home card starts on the first page")
