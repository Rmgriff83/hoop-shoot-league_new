extends RefCounted
## The park's dressing (game/view/park_fx.gd): the PSX trees and litter
## instanced from the layout (one multimesh per model surface), the three
## parked cars with their snow caps, the falling snow as one points mesh
## under the shader, the sky shader on the dome — all seeded, none of it
## in the sim.


func run(t) -> void:
	var layout_path := "res://data/park_layout.json"
	t.ok(FileAccess.file_exists(layout_path), "the park layout ships")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	t.ok(doc is Dictionary and doc.has("rows"), "…and parses")
	if not (doc is Dictionary and doc.has("rows")):
		return
	var rows: Array = doc["rows"]
	var trees := 0
	var models := {}
	for r in rows:
		var m := str(r["model"])
		models[m] = true
		if m.find("tree_0") >= 0 and m.find("stump") < 0 and m.find("fallen") < 0:
			trees += 1
		t.ok(FileAccess.file_exists("res://assets/arena/park/trees/%s.glb" % m), "the layout's %s ships conformed" % m)
	t.ok(trees >= 25 and trees <= 50, "a few dozen trees (%d)" % trees)
	# The park running lighter: the six far aspens are the small model scaled to height.
	var big := 0
	var far_small := 0
	for r in rows:
		if str(r["model"]) == "aspen_tree_01":
			big += 1
			t.ok(float(r["x"]) < 29.0, "a big aspen stays only near the court (x %.1f)" % float(r["x"]))
		elif str(r["model"]) == "aspen_tree_02" and float(r["x"]) >= 29.0 and float(r.get("s", 1.0)) >= 1.6:
			far_small += 1
	t.eq(big, 5, "five big aspens near the court")
	t.eq(far_small, 5, "five far aspens are the small model scaled up to the big one's height (Ross deleted the sixth)")
	var moved_pine := false
	for r in rows:
		if str(r["model"]) == "pine_tree_01_b" and absf(float(r["x"]) - 24.36) < 0.01 and absf(float(r["z"]) - 2.58) < 0.01 and absf(float(r.get("y", 0.0))) < 1e-6:
			moved_pine = true
	t.ok(moved_pine, "the pine Ross dragged beside the lot's row stands there, on the ground")
	var behind_board := false
	for r in rows:
		if str(r["model"]).begins_with("aspen") and absf(float(r["x"]) - 25.4) < 0.3 and absf(float(r["z"]) - 0.9) < 0.3:
			behind_board = true
	t.ok(not behind_board, "the aspen that doubled up behind the backboard is gone")
	t.ok(models.has("aspen_tree_01") and models.has("pine_tree_01_a") and models.has("pine_tree_stump_01") and models.has("rock_01_large_mossy") and models.has("fallen_pine_tree_01"),
		"aspens, pines, a stump, the mossy rock and the fallen log")
	var leaning := false
	for r in rows:
		if str(r["model"]) == "aspen_tree_01" and absf(float(r["x"]) - 4.6) < 1e-6:
			leaning = true
	t.ok(not leaning, "the aspen that leaned in over the board is gone (it doubled up on the left from the key)")
	# The dressing on the park arena, off-tree (the shaders compile headless).
	var arena := CosmeticLibrary.get_arena("park")
	t.ok(arena != null and arena.snow and arena.parked_cars.size() == 1, "the park ArenaSet asks for snow and one parked car")
	if arena == null:
		return
	var scene: PackedScene = load(arena.model_path)
	t.ok(scene != null, "the park glb loads")
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	for n in ["Sky", "TreelineRing", "SnowLying", "Court", "Lawn", "ParkingLot", "Road", "NoticeBoard", "FarSnow", "PoleFooting", "SplitRailFence", "BayStripes", "FlipBoard", "ScoreboardFace", "ScoreboardHardware", "FlipCard0", "FlipCard3", "FlipPivot0", "FlipFront3", "FlipBack3", "Snowman"]:
		t.ok(inst.find_child(n, true, false) != null, "park glb has %s" % n)
	t.ok(inst.find_child("Pole", true, false) == null, "no arena pole: the park hoop brings its own")
	var fx := ParkFx.new()
	t.ok(fx.setup(inst, arena), "ParkFx dresses the park")
	t.eq(fx.instance_count(), rows.size(), "every layout row is instanced")
	t.ok(fx.draw_count() >= models.size() and fx.draw_count() <= models.size() * 6, "a draw per model surface and near/far split (%d draws for %d models)" % [fx.draw_count(), models.size()])
	t.ok(fx.shadow_caster_count() >= 2 and fx.shadow_caster_count() <= 5, "only the trees by the court cast shadows (%d)" % fx.shadow_caster_count())
	var split_ok := true
	for mmi in inst.find_children("*", "MultiMeshInstance3D", true, false):
		var n := String(mmi.name)
		if n.ends_with("_near") and mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			split_ok = false
		if n.ends_with("_far") and mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			split_ok = false
	t.ok(split_ok, "every near multimesh casts, every far one does not")
	t.eq(fx.car_count(), 1, "one parked car, in its striped bay")
	var fence: MeshInstance3D = inst.find_child("SplitRailFence", true, false)
	var fa: AABB = fence.get_aabb()
	t.ok(absf(fa.position.x + fa.size.x * 0.5 - SimGeometry.PARK_FENCE_X) < 0.08, "the fence stands on the sim's wall line (x %.2f)" % (fa.position.x + fa.size.x * 0.5))
	t.ok(fa.size.z > 11.5 and fa.size.y > 1.1 and fa.size.y < 1.4, "…the slab's width, rail height")
	var snowman: MeshInstance3D = inst.find_child("Snowman", true, false)
	var sc: Vector3 = snowman.get_aabb().get_center() if snowman != null else Vector3.ZERO
	t.ok(snowman != null and absf(sc.x - 11.4) < 0.5 and absf(sc.z + 3.2) < 0.5, "the snowman slumps on the lawn back-left (built in place: %s)" % str(sc))
	t.ok(snowman != null and snowman.mesh.get_surface_count() == 1 and (snowman.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0, "…one vertex-coloured surface")
	var hard: MeshInstance3D = inst.find_child("ScoreboardHardware", true, false)
	t.ok(hard != null and (hard.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0, "the board's stacks, rings and hooks: one vertex-coloured mesh")
	var sa: AABB = snowman.get_aabb() if snowman != null else AABB()
	t.ok(sa.size.y > 1.0 and sa.size.y < 1.6 and sa.size.x > 1.5, "…a slumped, hatted size (%.2f tall, %.2f wide)" % [sa.size.y, sa.size.x])
	t.eq(fx.snow_count(), 500, "five hundred flakes")
	t.ok(fx.has_sky() and fx.sky_resource() is Sky and (fx.sky_resource() as Sky).sky_material is ShaderMaterial, "the design's sky shader is a Sky resource for the court's Environment")
	t.ok(not (inst.find_child("Sky", true, false) as MeshInstance3D).visible, "the glb's dome is hidden under it")
	fx._process(0.5)
	t.close(float(((fx.sky_resource() as Sky).sky_material as ShaderMaterial).get_shader_parameter("cloud_time")), ParkFx.CLOUD_T0, 1e-6, "the clouds' phase is set once: no per-frame uniform write (that re-rendered the radiance every frame)")
	t.close(fx.clock(), ParkFx.CLOUD_T0 + 0.5, 1e-6, "…the drift rides the shader's TIME")
	t.ok((fx.sky_resource() as Sky).radiance_size == Sky.RADIANCE_SIZE_64, "a small radiance map (reflections only)")
	t.ok(FileAccess.get_file_as_string("res://game/court/park_sky.gdshader").contains("drift * (TIME + cloud_time)"), "the shader drifts on TIME")
	t.ok(float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0)) >= 86400.0, "TIME rolls over in days, not the hour")
	var snow: MeshInstance3D = inst.find_child("Snowfall", true, false)
	t.ok(snow != null and snow.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_POINTS, "the snow is one points mesh")
	t.ok(snow != null and snow.custom_aabb.size.x > 100.0, "…never culled")
	var mmi: MultiMeshInstance3D = inst.find_child("pine_tree_01_a_0_near", true, false)
	t.ok(mmi != null and mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the pine by the slab casts a shadow")
	var rock: MultiMeshInstance3D = inst.find_child("rock_01_large_mossy_0_far", true, false)
	t.ok(rock != null and rock.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the rock does not")
	var bare := ParkFx.new()
	t.ok(not bare.setup(Node3D.new(), CosmeticLibrary.get_arena("cage")), "the cage asks for none of it")
	bare.free()
	fx.free()
	inst.free()
	# Snow is visual only: the park geometry has no weather.
	t.ok(SimGeometry.park().props.size() == 1, "the sim knows one drift and no flakes")
