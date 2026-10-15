extends RefCounted
## RwbNet (docs/BLENDER_101.md §31): the knitted build in red, white and
## blue bands, factory-even, with short blue stubs on swinging Tail bones.


func run(t) -> void:
	var rim_r: float = SimConstants.R_RIM
	var tube_r: float = SimConstants.R_TUBE
	var lay := RwbNet.layout(rim_r, tube_r)
	var cotton := NetSim.cotton_layout(rim_r, tube_r)
	var knots: PackedVector3Array = lay["knots"]
	var ck: PackedVector3Array = cotton["knots"]
	t.eq(knots.size(), 96, "rwb: 84 knots + 12 tails")
	t.eq((lay["springs"] as Array).size(), 168, "rwb: 156 cord pieces + 12 stub springs")
	var even := true
	for p in range(12, 84):
		var rw := Vector2(knots[p].x, knots[p].z).length()
		var rc := Vector2(ck[p].x, ck[p].z).length()
		if absf(rw / rc - 1.0) > 0.012 or absf(knots[p].y - ck[p].y) > 0.0025:
			even = false
	t.ok(even, "rwb: factory-even (within 1.2 % and 2.5 mm of the cotton layout)")
	var stubs := true
	for tl in lay["tails"]:
		var len: float = float(tl["len"])
		if len < 0.016 - 1e-9 or len > 0.024 + 1e-9:
			stubs = false
	t.ok(stubs, "rwb: 16–24 mm stubs")
	t.eq(RwbNet.band(0), Color.html(RwbNet.RED), "row 0 is red")
	t.eq(RwbNet.band(2), Color.html(RwbNet.WHITE), "row 2 is white")
	t.eq(RwbNet.band(5), Color.html(RwbNet.BLUE), "row 5 is blue")

	var root := Node3D.new()
	var rwb := RwbNet.new()
	root.add_child(rwb)
	rwb.build(lay)
	t.eq(rwb.bone_count(), 109, "109 bones")
	t.eq(rwb.surface_count(), 3, "cords, knots, tails")
	var skel: Skeleton3D = rwb.skeleton
	var seen := {}
	for part in ["Net_Cords", "Net_Knots", "Net_Tails"]:
		var arr: Array = (skel.get_node(part) as MeshInstance3D).mesh.surface_get_arrays(0)
		t.ok(arr[Mesh.ARRAY_COLOR] != null, "%s carries vertex colours" % part)
		if arr[Mesh.ARRAY_COLOR] != null:
			for c in arr[Mesh.ARRAY_COLOR]:
				seen[(c as Color).to_html(false)] = true
	t.eq(seen.size(), 3, "three colours in all (%d)" % seen.size())
	# The bands: the top knots red, the middle white, the bottom blue (8-bit on the mesh).
	var karr: Array = (skel.get_node("Net_Knots") as MeshInstance3D).mesh.surface_get_arrays(0)
	var kc: PackedColorArray = karr[Mesh.ARRAY_COLOR]
	var per_knot := 24   # 8 faces × 3 vertices
	var near := func(a: Color, b: Color) -> bool:
		return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
	t.ok(near.call(kc[0], Color.html(RwbNet.RED)), "Knot_0_0 is red")
	t.ok(near.call(kc[per_knot * 12 * 2], Color.html(RwbNet.WHITE)), "Knot_2_0 is white")
	t.ok(near.call(kc[per_knot * 12 * 6], Color.html(RwbNet.BLUE)), "Knot_6_0 is blue")
	var tarr: Array = (skel.get_node("Net_Tails") as MeshInstance3D).mesh.surface_get_arrays(0)
	t.ok(near.call((tarr[Mesh.ARRAY_COLOR] as PackedColorArray)[0], Color.html(RwbNet.BLUE)), "the stubs are blue")
	var top := -INF
	for v in (skel.get_node("Net_Cords") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		top = maxf(top, (v as Vector3).y)
	t.ok(top < 0.0, "no loop shows above the rim line")

	var net := NetSim.new()
	root.add_child(net)
	t.ok(net.setup_layout(rwb, lay, "cotton"), "the sim takes the layout")
	rwb.sync(net)
	var y := 0.42
	var vy := -4.6
	for i in 40:
		net.step(1.0 / 60.0, [{"pos": Vector3(0, y, 0), "vel": Vector3(0, vy, 0), "spin": 18.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}])
		vy -= 9.81 / 60.0
		y += vy / 60.0
	rwb.sync(net)
	var slept := 0
	while net.is_awake() and slept < 900:
		net.step(1.0 / 60.0, [])
		slept += 1
	t.ok(not net.is_awake(), "a swish settles back to sleep (%d frames)" % slept)
	root.free()
