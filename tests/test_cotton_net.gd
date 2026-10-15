extends RefCounted
## CottonNet: the nylon net's skinned body — the rig, the three meshes, the
## textures, and sync() moving the knot bones with a NetSim.


func run(t) -> void:
	var root := Node3D.new()
	var cotton := CottonNet.new()
	root.add_child(cotton)
	var lay := NetSim.cotton_layout()
	cotton.build(lay)
	t.eq(cotton.bone_count(), 97, "97 bones: NetRoot + 12 hooks + 84 knots")
	var skel: Skeleton3D = cotton.skeleton
	t.eq(skel.find_bone("Hook_0"), 1, "Hook_0 is bone 1")
	t.eq(skel.find_bone("Hook_11"), 12, "Hook_11 is bone 12")
	t.eq(skel.find_bone("Knot_0_0"), 13, "Knot_0_0 follows the hooks")
	t.eq(skel.find_bone("Knot_6_11"), 96, "Knot_6_11 is the last bone")
	t.eq(cotton.surface_count(), 3, "three skinned meshes")
	t.ok(cotton.tri_count() >= 5000 and cotton.tri_count() <= 9000, "about 7K tris (%d)" % cotton.tri_count())
	var names: Array = []
	var weights_ok := true
	var bones_ok := true
	var n_verts := 0
	for child in skel.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		names.push_back(String(mi.name))
		t.ok(mi.skin != null, "%s carries the skin" % mi.name)
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var b: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var nv: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		n_verts += nv
		if w.size() != nv * 4 or b.size() != nv * 4:
			weights_ok = false
			continue
		for v in nv:
			var sum := w[v * 4] + w[v * 4 + 1] + w[v * 4 + 2] + w[v * 4 + 3]
			if absf(sum - 1.0) > 1e-4:   # the mesh stores weights 16-bit
				weights_ok = false
			for j in 4:
				if b[v * 4 + j] < 0 or b[v * 4 + j] >= 97:
					bones_ok = false
	names.sort()
	t.eq(names, ["Net_Cords", "Net_Knots", "Net_Tails"], "the design's three parts")
	t.ok(weights_ok, "every vertex carries 4 weights summing to 1 (%d vertices)" % n_verts)
	t.ok(bones_ok, "every bone index is a rig bone")
	t.eq(n_verts, cotton.tri_count() * 3, "flat shaded: a vertex per triangle corner")
	# Textures: the 16×16 pixel twist, nearest filtered.
	var texs: Array = cotton.textures()
	t.eq(texs.size(), 2, "a cord and a knot texture")
	t.ok(texs[0].get_width() == 16 and texs[0].get_height() == 16, "16×16 twist")
	var mat: StandardMaterial3D = (skel.get_node("Net_Cords") as MeshInstance3D).mesh.surface_get_material(0)
	t.eq(mat.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST, "nearest filtered")
	t.close(mat.roughness, 1.0, 0.0, "rough cotton")
	# The hook loops: no cord vertex rises above the rim's centre line.
	var top := -INF
	var cords_arrays: Array = (skel.get_node("Net_Cords") as MeshInstance3D).mesh.surface_get_arrays(0)
	for v in cords_arrays[Mesh.ARRAY_VERTEX]:
		top = maxf(top, v.y)
	t.ok(top < 0.0, "no loop shows above the rim line (top %.4f)" % top)

	# sync(): a swish moves the bottom knots' bones, never the hooks.
	var net := NetSim.new()
	root.add_child(net)
	t.ok(net.setup_cotton(cotton), "a sim on the same layout")
	cotton.sync(net)
	var rest6 := skel.get_bone_pose_position(skel.find_bone("Knot_6_0"))
	t.close(rest6.distance_to(net.rest_position(12 + 72)), 0.0, 1e-6, "at rest the bones sit on the settled particles")
	var y := 0.4
	var vy := -4.6
	for i in 30:
		net.step(1.0 / 60.0, [{"pos": Vector3(0, y, 0), "vel": Vector3(0, vy, 0), "spin": 15.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}])
		vy -= 9.81 / 60.0
		y += vy / 60.0
	cotton.sync(net)
	var moved := skel.get_bone_pose_position(skel.find_bone("Knot_6_0")).distance_to(rest6)
	t.ok(moved > 0.01, "sync moves the bottom knot bones (%.3f m)" % moved)
	var hook_rest := skel.get_bone_rest(skel.find_bone("Hook_4")).origin
	t.close(skel.get_bone_pose_position(skel.find_bone("Hook_4")).distance_to(hook_rest), 0.0, 1e-9, "the hook bones never move")
	t.eq(cotton.bone_of_particle(0), 1, "particle 0 drives Hook_0")
	t.eq(cotton.bone_of_particle(12), 13, "particle 12 drives Knot_0_0")
	root.free()
