extends RefCounted
## WoolNet (docs/BLENDER_101.md §31): the cotton structure hand-tied, in
## coloured knitted yarn, with long tails that swing on their own bones.


func run(t) -> void:
	var rim_r: float = SimConstants.R_RIM
	var tube_r: float = SimConstants.R_TUBE
	var lay := WoolNet.layout(rim_r, tube_r)
	var cotton := NetSim.cotton_layout(rim_r, tube_r)
	var knots: PackedVector3Array = lay["knots"]
	var ck: PackedVector3Array = cotton["knots"]
	t.eq(knots.size(), 96, "wool: 84 knots + 12 tails")
	t.eq((lay["hooks"] as PackedVector3Array).size(), 12, "wool: 12 hooks")
	t.eq((lay["springs"] as Array).size(), 168, "wool: 156 cord pieces + 12 tail springs")
	t.eq((lay["bottom"] as Array).size(), 24, "wool: the bottom ring and the tails hang heavy")
	var names: PackedStringArray = lay["knot_names"]
	t.eq(names.size(), 96, "wool: a name per particle")
	t.eq(str(names[84]), "Tail_0", "wool: the tails follow the knots")
	var same_top := true
	for i in 12:
		if knots[i] != ck[i]:
			same_top = false
	t.ok(same_top, "wool: ring 0 is not jittered (the loops stay under the rim)")
	var jittered := false
	var bounded := true
	for p in range(12, 84):
		var d := knots[p] - ck[p]
		if d.length() > 1e-6:
			jittered = true
		var rw := Vector2(knots[p].x, knots[p].z).length()
		var rc := Vector2(ck[p].x, ck[p].z).length()
		if absf(rw / rc - 1.0) > 0.04 or absf(knots[p].y - ck[p].y) > 0.007:
			bounded = false
	t.ok(jittered, "wool: the lower rings are hand-tied (jittered)")
	t.ok(bounded, "wool: …within 4 % of radius and 7 mm of height")
	var tails_ok := true
	for tl in lay["tails"]:
		var kp := knots[int(tl["knot"]) - 12]
		var tp := knots[int(tl["tail"]) - 12]
		var len: float = float(tl["len"])
		if len < 0.04 - 1e-9 or len > 0.12 + 1e-9 or absf((kp.y - tp.y) - len) > 1e-6:
			tails_ok = false
	t.ok(tails_ok, "wool: every tail hangs 40–120 mm under its knot")

	var root := Node3D.new()
	var wool := WoolNet.new()
	root.add_child(wool)
	wool.build(lay)
	t.eq(wool.bone_count(), 109, "109 bones: NetRoot + 12 hooks + 84 knots + 12 tails")
	var skel: Skeleton3D = wool.skeleton
	t.eq(skel.find_bone("Tail_11"), 108, "Tail_11 is the last bone")
	t.eq(wool.surface_count(), 3, "cords, knots, tails")
	t.ok(wool.tri_count() >= 6000 and wool.tri_count() <= 12000, "about as many tris as the cotton net (%d)" % wool.tri_count())
	var cords_mi := skel.get_node("Net_Cords") as MeshInstance3D
	var arrays: Array = cords_mi.mesh.surface_get_arrays(0)
	t.ok(arrays[Mesh.ARRAY_COLOR] != null, "the cords carry vertex colours")
	var seen := {}
	if arrays[Mesh.ARRAY_COLOR] != null:
		for c in arrays[Mesh.ARRAY_COLOR]:
			seen[(c as Color).to_html(false)] = true
	t.eq(seen.size(), 12, "twelve yarns (%d colours)" % seen.size())
	var mat: StandardMaterial3D = cords_mi.mesh.surface_get_material(0)
	t.ok(mat.vertex_color_use_as_albedo, "the yarn tints the knit")
	t.ok(wool.textures()[0].get_width() == 16 and mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "a 16×16 knit, nearest")
	var top := -INF
	for v in arrays[Mesh.ARRAY_VERTEX]:
		top = maxf(top, (v as Vector3).y)
	t.ok(top < 0.0, "no loop shows above the rim line (top %.4f)" % top)
	var tails_mi := skel.get_node("Net_Tails") as MeshInstance3D
	var tw: PackedFloat32Array = tails_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]
	var blended := false
	for i in tw.size() / 4:
		if tw[i * 4] > 0.01 and tw[i * 4 + 1] > 0.01:
			blended = true
	t.ok(blended, "the tails blend from the knot bone to the tail bone")

	var net := NetSim.new()
	root.add_child(net)
	t.ok(net.setup_layout(wool, lay, "cotton"), "the sim takes the wool layout")
	t.eq(net.particle_count(), 108, "108 particles")
	wool.sync(net)
	var tail_rest := skel.get_bone_pose_position(skel.find_bone("Tail_3"))
	var y := 0.42
	var vy := -4.6
	for i in 40:
		net.step(1.0 / 60.0, [{"pos": Vector3(0, y, 0), "vel": Vector3(0, vy, 0), "spin": 18.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}])
		vy -= 9.81 / 60.0
		y += vy / 60.0
	wool.sync(net)
	var moved := skel.get_bone_pose_position(skel.find_bone("Tail_3")).distance_to(tail_rest)
	t.ok(moved > 0.01, "a swish swings the tails (%.3f m)" % moved)
	var slept := 0
	while net.is_awake() and slept < 900:
		net.step(1.0 / 60.0, [])
		slept += 1
	t.ok(not net.is_awake(), "and it settles back to sleep (%d frames)" % slept)
	var again := WoolNet.layout(rim_r, tube_r)
	t.ok((again["knots"] as PackedVector3Array) == knots, "the hand-tying is seeded: the same net every build")
	root.free()
