extends RefCounted
## LadderNet (docs/BLENDER_101.md §30): straight drops tied by three slack
## hoop chains — the layout, the rig, rings at the crossings only, the hoop
## chains drooping between drops at rest, a swish that settles.


func run(t) -> void:
	var rim_r: float = SimConstants.R_RIM
	var tube_r: float = SimConstants.R_TUBE
	var lay := LadderNet.layout(rim_r, tube_r)
	var knots: PackedVector3Array = lay["knots"]
	var hooks: PackedVector3Array = lay["hooks"]
	t.eq(knots.size(), 60, "ladder: 5 rows × 12")
	t.eq(hooks.size(), 12, "ladder: 12 hooks")
	t.eq((lay["springs"] as Array).size(), 96, "ladder: 12 drops to the hooks + 48 drop runs + 36 hoop runs")
	t.eq((lay["hoop_springs"] as Array).size(), 36, "ladder: three hoop chains")
	var hook_y := -(tube_r + NetSim.CHAIN_HOOK_DROP)
	t.close(hooks[0].y, hook_y, 1e-6, "ladder: hooks under the rim as the chain's")
	t.close(knots[0].y, hook_y - NetSim.CHAIN_HOOK_HH, 1e-6, "ladder: row 0 one link under the hooks")
	t.close(knots[48].y, -NetSim.NET_LEN, 1e-6, "ladder: the tails end at −0.42")
	t.close(atan2(knots[12].z, knots[12].x), 0.0, 1e-9, "ladder: the drops are straight (no half-step turn)")
	t.ok(Vector2(knots[36].x, knots[36].z).length() < Vector2(knots[12].x, knots[12].z).length(), "ladder: the hoops taper inward")
	var springs: Array = lay["springs"]
	var hoop: Array = springs[int(lay["hoop_springs"][0])]
	var a := knots[int(hoop[0]) - 12]
	var b := knots[int(hoop[1]) - 12]
	t.close(float(hoop[2]) / a.distance_to(b), 1.04, 1e-6, "ladder: a hoop run carries 4 % slack")

	var root := Node3D.new()
	var ladder := LadderNet.new()
	root.add_child(ladder)
	ladder.build(lay)
	t.eq(ladder.bone_count(), 73, "73 bones")
	var skel: Skeleton3D = ladder.skeleton
	t.eq(ladder.surface_count(), 2, "rings and hooks")
	t.ok(ladder.link_count() >= 250 and ladder.link_count() <= 450, "hundreds of links (%d)" % ladder.link_count())
	t.eq(ladder._ring_particles(lay).size(), 36, "rings at the 36 crossings only")
	var rings_mi := skel.get_node("Net_Rings") as MeshInstance3D
	var ring_top := -INF
	var ring_bottom := INF
	for v in rings_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		ring_top = maxf(ring_top, v.y)
		ring_bottom = minf(ring_bottom, v.y)
	t.ok(ring_top < knots[12].y + 0.02 and ring_bottom > knots[36].y - 0.02, "the rings sit between rows 1 and 3")
	var hooks_mi := skel.get_node("Net_Hooks") as MeshInstance3D
	var top := -INF
	for v in hooks_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		top = maxf(top, v.y)
	t.ok(top < 0.0, "the S-hooks stay under the rim (top %.4f)" % top)
	var lmat: StandardMaterial3D = (skel.get_node("Net_Links") as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0)
	t.close(lmat.roughness, 0.78, 1e-6, "worn steel: rough")
	t.close(lmat.metallic, 0.25, 1e-6, "…and dull")
	# The hoop chains droop between drops at rest: the middle link of a hoop
	# run hangs below its chord.
	var sagged := true
	var idx := 0
	for r in ladder.run_count():
		var n := ladder.run_links(r)
		if (lay["hoop_springs"] as Array).has(r) and n >= 3:
			var ends := ladder.run_ends(r)
			var pa := knots[ends[0] - 12]
			var pb := knots[ends[1] - 12]
			var mid := ladder.link_transform(idx + n / 2).origin
			if mid.y >= pa.lerp(pb, (float(n / 2) + 0.5) / float(n)).y - 1e-4:
				sagged = false
		idx += n
	t.ok(sagged, "the hoop chains droop between the drops")

	var net := NetSim.new()
	root.add_child(net)
	net.configure(load("res://assets/hoops/chain/hoop_set.tres"))
	t.ok(net.setup_layout(ladder, lay, "chain"), "the sim takes the ladder layout")
	t.eq(net.particle_count(), 72, "72 particles")
	ladder.sync(net)
	var before := PackedVector3Array()
	for i in ladder.link_count():
		before.push_back(ladder.link_transform(i).origin)
	var y := 0.4
	var vy := -4.6
	for i in 30:
		net.step(1.0 / 60.0, [{"pos": Vector3(0, y, 0), "vel": Vector3(0, vy, 0), "spin": 14.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}])
		vy -= 9.81 / 60.0
		y += vy / 60.0
	ladder.sync(net)
	var moved := 0.0
	for i in ladder.link_count():
		moved = maxf(moved, ladder.link_transform(i).origin.distance_to(before[i]))
	t.ok(moved > 0.005, "a swish moves the links (%.3f m)" % moved)
	var slept := 0
	while net.is_awake() and slept < 900:
		net.step(1.0 / 60.0, [])
		slept += 1
	t.ok(not net.is_awake(), "and it settles back to sleep (%d frames)" % slept)
	root.free()
