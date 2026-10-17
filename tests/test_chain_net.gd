extends RefCounted
## ChainNet: the city hoop's chain body — the rig, the interlocking link
## multimesh placed with slack sag, the junction rings, the S-hooks under
## the rim, and sync() moving it all with a NetSim.


func run(t) -> void:
	var root := Node3D.new()
	var chain := ChainNet.new()
	root.add_child(chain)
	var lay := NetSim.chain_layout()
	chain.build(lay)
	t.eq(chain.bone_count(), 73, "73 bones: NetRoot + 12 hooks + 60 junctions")
	var skel: Skeleton3D = chain.skeleton
	t.eq(skel.find_bone("Hook_11"), 12, "Hook_11 is bone 12")
	t.eq(skel.find_bone("Knot_4_11"), 72, "Knot_4_11 is the last bone")
	t.eq(chain.surface_count(), 2, "two skinned meshes (rings, hooks) beside the link multimesh")
	var links: Node = skel.get_node_or_null("Net_Links")
	t.ok(links is MultiMeshInstance3D, "Net_Links is a multimesh")
	t.ok(skel.get_node_or_null("Net_Rings") is MeshInstance3D and skel.get_node_or_null("Net_Hooks") is MeshInstance3D, "Net_Rings and Net_Hooks are skinned meshes")
	t.ok(chain.link_count() >= 400 and chain.link_count() <= 700, "hundreds of links (%d)" % chain.link_count())
	t.eq((links as MultiMeshInstance3D).multimesh.instance_count, chain.link_count(), "an instance per link")
	t.eq((links as MultiMeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the links cast no shadow (50k triangles nobody read)")
	# The one buffer write: 12 floats a link, the transform's rows (the engine's
	# multimesh layout: xx yx zx ox | xy yy zy oy | xz yz zz oz). Headless, the
	# dummy renderer returns no instance transforms, so the buffer itself is read.
	var buf: PackedFloat32Array = (links as MultiMeshInstance3D).multimesh.buffer
	t.eq(buf.size(), chain.link_count() * 12, "the buffer holds every link")
	var buf_ok := buf.size() == chain.link_count() * 12
	for i in [0, 7, chain.link_count() / 2, chain.link_count() - 1]:
		if not buf_ok:
			break
		var xf := chain.link_transform(int(i))
		var o: int = int(i) * 12
		var want := [xf.basis.x.x, xf.basis.y.x, xf.basis.z.x, xf.origin.x, xf.basis.x.y, xf.basis.y.y, xf.basis.z.y, xf.origin.y, xf.basis.x.z, xf.basis.y.z, xf.basis.z.z, xf.origin.z]
		for k in 12:
			if absf(buf[o + k] - float(want[k])) > 1e-5:
				buf_ok = false
	t.ok(buf_ok, "the buffer carries each link's transform rows where set_instance_transform put them")
	t.close(ChainNet.LINK_PITCH, 0.0228, 1e-9, "the pitch is the link's inner length: links interlock")
	# A diagonal run (~0.105 m) carries 5 links; a hook drop (0.025 m) one.
	var diag_n := 0
	var drop_n := 0
	for r in chain.run_count():
		var ends := chain.run_ends(r)
		if ends[0] < 12 or ends[1] < 12:
			drop_n = chain.run_links(r)
		elif diag_n == 0:
			diag_n = chain.run_links(r)
	t.ok(diag_n >= 4 and diag_n <= 6, "a diagonal run carries %d links" % diag_n)
	t.eq(drop_n, 1, "a hook drop carries one link")
	var inside := true
	var top := -INF
	for i in chain.link_count():
		var o := chain.link_transform(i).origin
		top = maxf(top, o.y)
		if Vector2(o.x, o.z).length() > 0.26 or o.y < -0.45:
			inside = false
	t.ok(inside, "every link sits on the net")
	t.ok(top < 0.0, "no link rises above the rim line (top %.3f)" % top)
	# Alternate links are turned 90°.
	var b0 := chain.link_transform(0).basis
	var b1 := chain.link_transform(1).basis
	t.ok(absf(b0.x.dot(b1.x)) < 1e-4 and b0.y.distance_to(b1.y) < 1e-4, "alternate links turn 90° about the run")
	# The S-hooks: skinned, weights sum to 1, nothing above the rim's centre line.
	var hooks_mi := skel.get_node("Net_Hooks") as MeshInstance3D
	var arrays: Array = hooks_mi.mesh.surface_get_arrays(0)
	var hv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var htop := -INF
	for v in hv:
		htop = maxf(htop, v.y)
	t.ok(htop < 0.0, "the S-hooks stay under the rim (top %.4f)" % htop)
	t.ok(htop > -(SimConstants.R_TUBE + 0.011 * 2), "…their top curl reaches the rim's NetHook loop")
	var weights_ok := w.size() == hv.size() * 4
	for v in hv.size():
		if absf(w[v * 4] + w[v * 4 + 1] + w[v * 4 + 2] + w[v * 4 + 3] - 1.0) > 1e-4:
			weights_ok = false
	t.ok(weights_ok and hooks_mi.skin != null, "the hooks are skinned, weights sum to 1")
	# Textures and steel.
	t.eq(chain.textures().size(), 2, "a link and a ring texture")
	t.ok(chain.textures()[0].get_width() == 16 and chain.textures()[0].get_height() == 16, "16×16 steel")
	var lmat: StandardMaterial3D = (links as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0)
	t.eq(lmat.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST, "nearest filtered")
	t.close(lmat.metallic, 0.35, 1e-6, "galvanised: metallic 0.35")
	t.ok(chain.tri_count() > 20000 and chain.tri_count() < 80000, "tens of thousands of tris (%d)" % chain.tri_count())

	# sync(): a pass moves the links; a slack run sags under its chord.
	var net := NetSim.new()
	root.add_child(net)
	net.configure(load("res://assets/hoops/chain/hoop_set.tres"))
	t.ok(net.setup_chain(chain), "a sim on the same layout")
	chain.sync(net)
	var before := PackedVector3Array()
	for i in chain.link_count():
		before.push_back(chain.link_transform(i).origin)
	var y := 0.4
	var vy := -4.6
	for i in 30:
		net.step(1.0 / 60.0, [{"pos": Vector3(0, y, 0), "vel": Vector3(0, vy, 0), "spin": 14.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}])
		vy -= 9.81 / 60.0
		y += vy / 60.0
	chain.sync(net)
	var moved := 0.0
	for i in chain.link_count():
		moved = maxf(moved, chain.link_transform(i).origin.distance_to(before[i]))
	t.ok(moved > 0.005, "the links follow the ball's pass (%.3f m)" % moved)
	var hook_rest := skel.get_bone_rest(skel.find_bone("Hook_4")).origin
	t.close(skel.get_bone_pose_position(skel.find_bone("Hook_4")).distance_to(hook_rest), 0.0, 1e-9, "the hook bones never move")
	# Slack sag: a run whose ends sit closer than its rest length hangs its
	# middle link below the chord's midpoint (the bottom ring lifted 3 cm
	# shortens every run into it); taut runs stay on the chord.
	var pos := PackedVector3Array()
	for i in net.particle_count():
		pos.push_back(net.rest_position(i))
	for b in lay["bottom"]:
		pos[int(b)] = pos[int(b)] + Vector3(0.0, 0.03, 0.0)
	chain._place_links_at(pos)
	var sagged := false
	var taut_ok := true
	var idx := 0
	for r in chain.run_count():
		var n := chain.run_links(r)
		var ends := chain.run_ends(r)
		var a := pos[ends[0]]
		var b := pos[ends[1]]
		var rest_len: float = net.spring(r)[2]
		var mid := chain.link_transform(idx + n / 2).origin
		var chord := a.lerp(b, (float(n / 2) + 0.5) / float(n))
		if a.distance_to(b) < rest_len - 0.01 and n >= 3:
			if mid.y < chord.y - 1e-4:
				sagged = true
		elif absf(a.distance_to(b) - rest_len) < 1e-6 and mid.distance_to(chord) > 1e-4:
			taut_ok = false
		idx += n
	t.ok(sagged, "a slack run sags under its chord")
	t.ok(taut_ok, "a taut run hangs straight")
	root.free()
