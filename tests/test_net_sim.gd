extends RefCounted
## NetSim: a Verlet cord lattice built from a tapered open cylinder (the hoop
## net), pinned at the top ring, pushed and dragged by a ball. Deterministic.


func _make_net() -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = SimConstants.R_RIM
	cyl.bottom_radius = 0.10
	cyl.height = 0.42
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 12
	cyl.rings = 4
	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cyl.get_mesh_arrays())
	mi.mesh = am
	return mi


func _ball(pos: Vector3, vel: Vector3, spin := 0.0) -> Dictionary:
	return {"pos": pos, "vel": vel, "spin": spin, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}


## Drop a ball straight through the net centre; returns the net after it's gone.
func _run_drop(net: NetSim, spin: float, seconds := 1.2) -> void:
	var dt := 1.0 / 60.0
	var y := 0.35
	var vy := -3.0
	var t := 0.0
	while t < seconds:
		var balls: Array = []
		if y > -0.9:
			balls.push_back(_ball(Vector3(0, y, 0), Vector3(0, vy, 0), spin))
		net.step(dt, balls)
		vy -= 9.81 * dt
		y += vy * dt
		t += dt


func run(t) -> void:
	var root := Node3D.new()
	var mi := _make_net()
	root.add_child(mi)
	var net := NetSim.new()
	root.add_child(net)
	t.ok(net.setup(mi), "setup accepts a cylinder net")
	t.ok(net.particle_count() >= 60 and net.particle_count() <= 80,
		"particles = unique vertices (%d)" % net.particle_count())
	t.ok(mi.mesh is ArrayMesh and mi.mesh.get_surface_count() == 1, "mesh replaced by a dynamic ArrayMesh")

	# 1. No ball: the net stays asleep and at rest.
	for i in 30:
		net.step(1.0 / 60.0, [])
	t.ok(not net.is_awake(), "stays asleep with no ball")
	t.close(net.max_displacement(), 0.0, 1e-9, "at rest with no ball")

	# 2. A ball passing through wakes it, deforms it, and it settles afterwards.
	var peak := 0.0
	var dt := 1.0 / 60.0
	var y := 0.35
	var vy := -3.0
	for i in 40:
		net.step(dt, [_ball(Vector3(0, y, 0), Vector3(0, vy, 0))])
		vy -= 9.81 * dt
		y += vy * dt
		peak = maxf(peak, net.max_displacement())
	t.ok(net.is_awake(), "ball wakes the net")
	t.ok(peak > 0.03, "ball deforms the net (peak %.3f m)" % peak)
	# Pinned top ring never moves.
	var top_moved := 0.0
	for i in net.particle_count():
		if net.rest_position(i).y > 0.2:
			top_moved = maxf(top_moved, net.particle_position(i).distance_to(net.rest_position(i)))
	t.close(top_moved, 0.0, 1e-9, "top ring stays pinned to the rim")
	for i in 240:
		net.step(dt, [])
	t.ok(net.max_displacement() < 0.02, "net settles after the ball (%.4f m)" % net.max_displacement())

	# 3. Deterministic: same ball path twice → identical particle positions.
	var a := NetSim.new()
	var b := NetSim.new()
	var ma := _make_net()
	var mb := _make_net()
	root.add_child(ma)
	root.add_child(mb)
	root.add_child(a)
	root.add_child(b)
	a.setup(ma)
	b.setup(mb)
	_run_drop(a, 15.0, 0.5)
	_run_drop(b, 15.0, 0.5)
	var same := true
	for i in a.particle_count():
		if a.particle_position(i) != b.particle_position(i):
			same = false
	t.ok(same, "identical inputs give identical nets")

	# 4. Backspin grabs cords: with spin, the front-bottom cords end up dragged
	#    differently from a no-spin pass at the same instant.
	var c := NetSim.new()
	var mc := _make_net()
	root.add_child(mc)
	root.add_child(c)
	c.setup(mc)
	_run_drop(c, 0.0, 0.25)
	_run_drop(a, 15.0, 0.0)  # (no-op, keeps API symmetric)
	var d := NetSim.new()
	var md := _make_net()
	root.add_child(md)
	root.add_child(d)
	d.setup(md)
	_run_drop(d, 15.0, 0.25)
	var diff := 0.0
	for i in c.particle_count():
		diff = maxf(diff, c.particle_position(i).distance_to(d.particle_position(i)))
	t.ok(diff > 0.005, "spin changes how the cords are dragged (%.4f m)" % diff)

	# 5. Chain rendering (the city hoop): the surface hides, links line every
	#    spring between rings, they sit inside the net and follow a pass.
	var e := NetSim.new()
	var me := _make_net()
	root.add_child(me)
	root.add_child(e)
	e.setup(me)
	e.set_chain(true)
	var chain: Node = root.find_child("Chain", true, false)
	t.ok(chain is MultiMeshInstance3D and not me.visible, "chain: a link multimesh replaces the cord surface")
	t.ok(e.chain_link_count() > 100, "hundreds of links (%d)" % e.chain_link_count())
	var inside := true
	for i in e.chain_link_count():
		var o := e.chain_instance_transform(i).origin
		if absf(o.x) > 0.3 or absf(o.z) > 0.3 or o.y > 0.3 or o.y < -0.5:   # the test cylinder is centred at the origin
			inside = false
	t.ok(inside, "every link sits on the net")
	var before := PackedVector3Array()
	for i in e.chain_link_count():
		before.push_back(e.chain_instance_transform(i).origin)
	_run_drop(e, 0.0, 0.25)
	var moved := 0.0
	for i in e.chain_link_count():
		moved = maxf(moved, e.chain_instance_transform(i).origin.distance_to(before[i]))
	t.ok(moved > 0.005, "the links follow the ball's pass (%.4f m)" % moved)
	e.set_chain(false)
	t.ok(me.visible and e.chain_link_count() == 0, "chain off: the surface is back")

	root.free()
