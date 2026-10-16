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
	t.ok(trees >= 30 and trees <= 50, "a few dozen trees (%d)" % trees)
	t.ok(models.has("aspen_tree_01") and models.has("pine_tree_01_a") and models.has("pine_tree_stump_01") and models.has("rock_01_large_mossy") and models.has("fallen_pine_tree_01"),
		"aspens, pines, a stump, the mossy rock and the fallen log")
	var leaning := false
	for r in rows:
		if str(r["model"]) == "aspen_tree_01" and absf(float(r["x"]) - 4.6) < 1e-6 and float(r.get("rx", 0.0)) > 0.0:
			leaning = true
	t.ok(leaning, "the tall aspen leans in over the board")
	# The dressing on the park arena, off-tree (the shaders compile headless).
	var arena := CosmeticLibrary.get_arena("park")
	t.ok(arena != null and arena.snow and arena.parked_cars.size() == 3, "the park ArenaSet asks for snow and three cars")
	if arena == null:
		return
	var scene: PackedScene = load(arena.model_path)
	t.ok(scene != null, "the park glb loads")
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	for n in ["Sky", "TreelineRing", "SnowLying", "Court", "Lawn", "ParkingLot", "Road", "NoticeBoard", "FarSnow", "PoleFooting"]:
		t.ok(inst.find_child(n, true, false) != null, "park glb has %s" % n)
	t.ok(inst.find_child("Pole", true, false) == null, "no arena pole: the park hoop brings its own")
	var fx := ParkFx.new()
	t.ok(fx.setup(inst, arena), "ParkFx dresses the park")
	t.eq(fx.instance_count(), rows.size(), "every layout row is instanced")
	t.ok(fx.draw_count() >= models.size() and fx.draw_count() <= models.size() * 3, "a draw per model surface (%d draws for %d models)" % [fx.draw_count(), models.size()])
	t.eq(fx.car_count(), 3, "three parked cars")
	t.eq(fx.snow_count(), 500, "five hundred flakes")
	t.ok(fx.has_sky() and fx.sky_resource() is Sky and (fx.sky_resource() as Sky).sky_material is ShaderMaterial, "the design's sky shader is a Sky resource for the court's Environment")
	t.ok(not (inst.find_child("Sky", true, false) as MeshInstance3D).visible, "the glb's dome is hidden under it")
	fx._process(0.5)
	t.close(float(((fx.sky_resource() as Sky).sky_material as ShaderMaterial).get_shader_parameter("cloud_time")), ParkFx.CLOUD_T0 + 0.5, 1e-6, "the clouds' clock is driven from script")
	var snow: MeshInstance3D = inst.find_child("Snowfall", true, false)
	t.ok(snow != null and snow.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_POINTS, "the snow is one points mesh")
	t.ok(snow != null and snow.custom_aabb.size.x > 100.0, "…never culled")
	var mmi: MultiMeshInstance3D = inst.find_child("pine_tree_01_a_0", true, false)
	t.ok(mmi != null and mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the pines cast shadows")
	var rock: MultiMeshInstance3D = inst.find_child("rock_01_large_mossy_0", true, false)
	t.ok(rock != null and rock.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the rock does not")
	var bare := ParkFx.new()
	t.ok(not bare.setup(Node3D.new(), CosmeticLibrary.get_arena("cage")), "the cage asks for none of it")
	bare.free()
	fx.free()
	inst.free()
	# Snow is visual only: the park geometry has no weather.
	t.ok(SimGeometry.park().props.size() == 1, "the sim knows one drift and no flakes")
