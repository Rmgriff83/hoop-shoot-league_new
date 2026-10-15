extends RefCounted
## JackNet (docs/BLENDER_101.md §30): figure-8 links in stretched hexagons —
## the layout with its shared vertical runs, the rig, the links, the long
## S-hooks under the rim, no rings; a swish moves it and it settles.


func run(t) -> void:
	var rim_r: float = SimConstants.R_RIM
	var tube_r: float = SimConstants.R_TUBE
	var lay := JackNet.layout(rim_r, tube_r)
	var knots: PackedVector3Array = lay["knots"]
	var hooks: PackedVector3Array = lay["hooks"]
	t.eq(knots.size(), 132, "jack: 72 knots + 60 joins")
	t.eq(hooks.size(), 12, "jack: 12 hooks")
	t.eq((lay["springs"] as Array).size(), 192, "jack: 12 drops + 60 shared runs + 120 diagonals")
	t.eq((lay["knot_names"] as PackedStringArray).size(), 132, "jack: a name per knot")
	t.eq(str((lay["knot_names"] as PackedStringArray)[12]), "Join_0_0", "jack: the joins follow their row's knots")
	t.eq((lay["bottom"] as Array).size(), 12, "jack: a 12-knot bottom")
	var hook_y := -(tube_r + JackNet.J_HOOK_DROP)
	var hooks_ok := true
	for h in hooks:
		if absf(h.y - hook_y) > 1e-6 or absf(Vector2(h.x, h.z).length() - rim_r) > 1e-6:
			hooks_ok = false
	t.ok(hooks_ok, "jack: the hook bones hang on the rim's radius %.3f under its centre line" % -hook_y)
	# The shared run: Knot_0_0 sits 30 mm above Join_0_0 on the same column.
	var k00 := knots[0]
	var j00 := knots[12]
	t.close(k00.y - j00.y, JackNet.SEG, 1e-6, "jack: a 30 mm shared vertical run at each junction")
	t.close(Vector2(k00.x, k00.z).distance_to(Vector2(j00.x, j00.z)), 0.0, 1e-9, "jack: …straight down")
	t.close(knots[(12 + 12) * 5].y, -NetSim.NET_LEN, 1e-6, "jack: the bottom row at −0.42")
	t.ok(knots[0].y < hook_y, "jack: the top knots hang under the hooks")

	var root := Node3D.new()
	var jack := JackNet.new()
	root.add_child(jack)
	jack.build(lay)
	t.eq(jack.bone_count(), 145, "145 bones: NetRoot + 12 hooks + 132")
	var skel: Skeleton3D = jack.skeleton
	t.eq(skel.find_bone("Join_4_11"), 132, "Join_4_11 is the last bone")
	t.ok(skel.find_bone("Knot_5_0") > 0, "the bottom row is named Knot_5_*")
	t.eq(jack.surface_count(), 1, "no rings: the hooks are the only skinned mesh")
	t.ok(skel.get_node_or_null("Net_Rings") == null, "jack: no junction rings")
	t.ok(skel.get_node_or_null("Net_Links") is MultiMeshInstance3D, "jack: the link multimesh")
	t.ok(jack.link_count() >= 500 and jack.link_count() <= 750, "hundreds of thin links (%d)" % jack.link_count())
	t.close(jack._pitch(), 0.0165, 1e-9, "jack: 16.5 mm pitch")
	var lm: ArrayMesh = (skel.get_node("Net_Links") as MultiMeshInstance3D).multimesh.mesh
	t.eq(ChainNet._link_tris(lm), 96, "a figure-8 link is 96 tris")
	var hooks_mi := skel.get_node("Net_Hooks") as MeshInstance3D
	var top := -INF
	for v in hooks_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		top = maxf(top, v.y)
	t.ok(top < 0.0, "the long S-hooks stay under the rim (top %.4f)" % top)
	t.ok(top > -(tube_r + 0.011 * 2), "…reaching the rim's NetHook loop")
	var ltop := -INF
	for i in jack.link_count():
		ltop = maxf(ltop, jack.link_transform(i).origin.y)
	t.ok(ltop < 0.0, "no link above the rim line")

	var net := NetSim.new()
	root.add_child(net)
	net.configure(load("res://assets/hoops/chain/hoop_set.tres"))
	t.ok(net.setup_layout(jack, lay, "chain"), "the sim takes the jack layout")
	t.eq(net.particle_count(), 144, "144 particles")
	jack.sync(net)
	var before := PackedVector3Array()
	for i in jack.link_count():
		before.push_back(jack.link_transform(i).origin)
	var y := 0.4
	var vy := -4.6
	for i in 30:
		net.step(1.0 / 60.0, [{"pos": Vector3(0, y, 0), "vel": Vector3(0, vy, 0), "spin": 14.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}])
		vy -= 9.81 / 60.0
		y += vy / 60.0
	jack.sync(net)
	var moved := 0.0
	for i in jack.link_count():
		moved = maxf(moved, jack.link_transform(i).origin.distance_to(before[i]))
	t.ok(moved > 0.005, "a swish moves the links (%.3f m)" % moved)
	var slept := 0
	while net.is_awake() and slept < 900:
		net.step(1.0 / 60.0, [])
		slept += 1
	t.ok(not net.is_awake(), "and it settles back to sleep (%d frames)" % slept)
	root.free()
