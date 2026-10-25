extends RefCounted
## TatteredNet (docs/BLENDER_101.md §32, design 26d): the cotton net aged —
## three hooks torn off, twelve pieces snapped, loose strands on free bones.


func run(t) -> void:
	var rim_r: float = SimConstants.R_RIM
	var tube_r: float = SimConstants.R_TUBE
	var lay := TatteredNet.layout(rim_r, tube_r)
	var cotton := NetSim.cotton_layout(rim_r, tube_r)
	var knots: PackedVector3Array = lay["knots"]
	var ck: PackedVector3Array = cotton["knots"]
	var tails: Array = lay["tails"]
	t.eq(tails.size(), 27, "27 loose strands")
	var kinds := {}
	for tl in tails:
		kinds[str(tl["kind"])] = int(kinds.get(str(tl["kind"]), 0)) + 1
	t.eq(kinds, {"snap": 12, "rim": 4, "bottom": 11}, "twelve snapped ends, four strands left on the rim, a ragged bottom")
	t.eq(knots.size(), 84 + 27, "84 knots + the strands")
	t.eq((lay["hooks"] as PackedVector3Array).size(), 12, "the twelve hook particles stay (pinned, three of them bare)")
	t.eq((lay["springs"] as Array).size(), 156 - 12 - 3 + 27, "156 pieces − 12 snapped − 3 torn loops + 27 strands")
	t.eq((lay["bottom"] as Array).size(), 12 + 27, "the bottom ring and every strand hang heavy")
	t.eq(Array(lay["broken_hooks"]), [3, 4, 9], "hooks 3, 4 and 9 tore off")
	t.eq((lay["broken"] as Dictionary).size(), 12, "twelve snapped pieces")
	var names: PackedStringArray = lay["knot_names"]
	t.eq(names.size(), knots.size(), "a name per particle")
	t.eq(str(names[84]), "Tail_0", "the strands follow the knots")
	# The torn hooks have no loop spring; a snapped piece has no spring.
	var pairs := {}
	for sp in lay["springs"]:
		pairs[Vector2i(mini(int(sp[0]), int(sp[1])), maxi(int(sp[0]), int(sp[1])))] = true
	var cords: Array = lay["cords"]
	for h in [3, 4, 9]:
		var k0 := int(cords[h]["k0"])
		t.ok(not pairs.has(Vector2i(mini(k0, h), maxi(k0, h))), "hook %d: no loop spring" % h)
	t.ok(pairs.has(Vector2i(mini(int(cords[0]["k0"]), 0), maxi(int(cords[0]["k0"]), 0))), "hook 0 still holds its loop")
	var left2: Array = cords[2]["right"]
	t.ok(not pairs.has(Vector2i(mini(int(left2[3]), int(left2[4])), maxi(int(left2[3]), int(left2[4])))), "piece 2R3 is snapped (no spring)")
	# The sag: the flank around hooks 3–4 hangs lower than cotton and pulls in; the far side barely.
	var d3 := ck[3].y - knots[3].y
	var d9 := ck[9].y - knots[9].y
	var d0 := ck[0].y - knots[0].y
	t.ok(d3 > 0.06 and d3 < 0.09, "ring 0 under the torn pair sags ~8 cm (%.3f)" % d3)
	t.ok(d9 > 0.03 and d9 < d3, "…the lone torn hook less (%.3f)" % d9)
	t.ok(d0 < 0.005, "…the sound side hardly at all (%.3f)" % d0)
	var r3 := Vector2(knots[3].x, knots[3].z).length()
	var rc3 := Vector2(ck[3].x, ck[3].z).length()
	t.ok(r3 < rc3 * 0.9, "the sagging flank pulls inward (%.3f of the cotton radius)" % (r3 / rc3))
	var strands_ok := true
	for tl in tails:
		var kp: Vector3 = (lay["hooks"] as PackedVector3Array)[int(tl["knot"])] if int(tl["knot"]) < 12 else knots[int(tl["knot"]) - 12]
		var tp := knots[int(tl["tail"]) - 12]
		var len := float(tl["len"])
		if len < 0.02 - 1e-9 or len > 0.26 + 1e-9 or absf((kp.y - tp.y) - len) > 1e-6:
			strands_ok = false
	t.ok(strands_ok, "every strand hangs 2–26 cm straight under its knot or hook")

	var root := Node3D.new()
	var net_body := TatteredNet.new()
	root.add_child(net_body)
	net_body.build(lay)
	t.eq(net_body.bone_count(), 1 + 12 + 84 + 27, "NetRoot + 12 hooks + 84 knots + 27 strands")
	var skel: Skeleton3D = net_body.skeleton
	t.eq(skel.find_bone("Tail_26"), 123, "Tail_26 is the last bone")
	t.eq(net_body.surface_count(), 3, "cords, knots, tails")
	t.ok(net_body.tri_count() >= 6000 and net_body.tri_count() <= 12000, "about as many tris as the cotton net (%d)" % net_body.tri_count())
	var cotton_body := CottonNet.new()
	root.add_child(cotton_body)
	cotton_body.build(cotton)
	t.ok(net_body.tri_count() < cotton_body.tri_count() + 27 * 6 * 10 and net_body.tri_count() > cotton_body.tri_count() - 15 * 60, "fewer cord pieces, more strands than the cotton (%d vs %d)" % [net_body.tri_count(), cotton_body.tri_count()])
	var cords_mi := skel.get_node("Net_Cords") as MeshInstance3D
	var mat: StandardMaterial3D = cords_mi.mesh.surface_get_material(0)
	t.ok(not mat.vertex_color_use_as_albedo and not mat.emission_enabled, "grimy grey-cream from the texture alone: no tint, no glow")
	t.ok(net_body.textures()[0].get_width() == 16 and mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "a 16×16 twist, nearest")
	var tex_img := net_body.textures()[0].get_image()
	var base := tex_img.get_pixel(3, 0)
	t.ok(base.r > 0.7 and base.r < 0.9 and base.b < base.r, "the cord is a grey-cream, darker than fresh cotton (%s)" % base.to_html(false))
	var top := -INF
	for v in cords_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		top = maxf(top, (v as Vector3).y)
	t.ok(top < 0.0, "no loop shows above the rim line (top %.4f)" % top)
	var tails_mi := skel.get_node("Net_Tails") as MeshInstance3D
	var tw: PackedFloat32Array = tails_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]
	var blended := false
	for i in tw.size() / 4:
		if tw[i * 4] > 0.01 and tw[i * 4 + 1] > 0.01:
			blended = true
	t.ok(blended, "the strands blend from their knot bone to their tail bone")

	var net := NetSim.new()
	root.add_child(net)
	t.ok(net.setup_layout(net_body, lay, "cotton"), "the sim takes the tattered layout")
	t.eq(net.particle_count(), 12 + 84 + 27, "123 particles")
	net_body.sync(net)
	# A snapped end inside the lattice swings with the net; a strand left on
	# the rim hangs from a pinned hook outside the ball's reach and stays put.
	var rim_strand := skel.find_bone("Tail_0")
	var rim_left := skel.find_bone("Tail_12")
	var tail_rest := skel.get_bone_pose_position(rim_strand)
	var rim_rest := skel.get_bone_pose_position(rim_left)
	var y := 0.42
	var vy := -4.6
	for i in 40:
		net.step(1.0 / 60.0, [{"pos": Vector3(0, y, 0), "vel": Vector3(0, vy, 0), "spin": 18.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}])
		vy -= 9.81 / 60.0
		y += vy / 60.0
	net_body.sync(net)
	var moved := skel.get_bone_pose_position(rim_strand).distance_to(tail_rest)
	t.ok(moved > 0.005, "a swish swings the snapped ends (%.3f m)" % moved)
	t.ok(skel.get_bone_pose_position(rim_left).distance_to(rim_rest) < 0.01, "…and leaves the strand on the rim hanging")
	var slept := 0
	while net.is_awake() and slept < 900:
		net.step(1.0 / 60.0, [])
		slept += 1
	t.ok(not net.is_awake(), "and it settles back to sleep (%d frames)" % slept)
	var again := TatteredNet.layout(rim_r, tube_r)
	t.ok((again["knots"] as PackedVector3Array) == knots, "the wear is seeded: the same net every build")
	t.ok(NetBodies.has_style("tattered") and NetBodies.kind_of("tattered") == "cotton" and NetBodies.for_style("tattered") is TatteredNet, "registered as a cotton style")
	root.free()
