extends RefCounted
## NetSim: a Verlet cord lattice built from a tapered open cylinder (the hoop
## net), pinned at the top ring, pushed and dragged by a ball. Deterministic.
## Three structures: the mesh-fed lattice (the primitive fallback) under the
## 2026-10-03 snap-model knobs, the cotton net (the nylon hoops) under the
## 2026-10-14 defaults, and the chain net (the city) under its hoop set.

## The mesh net's knobs (the snap model the mesh sections were written for;
## the class defaults are the cotton net's now).
const MESH_KNOBS := {"rest_spring": 90.0, "rest_pull": 0.003, "tail_mass": 1.6, "kick_speed": 1.6, "ball_friction": 0.55}


func _mesh_sim() -> NetSim:
	var n := NetSim.new()
	n.apply_overrides(MESH_KNOBS)
	return n


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
	_cotton(t)
	_chain(t)
	var root := Node3D.new()
	var mi := _make_net()
	root.add_child(mi)
	var net := _mesh_sim()
	root.add_child(net)
	t.ok(net.setup(mi), "setup accepts a cylinder net")
	t.ok(net.particle_count() >= 60 and net.particle_count() <= 100,
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
	# The snap-back: after the ball is gone some free cord rises ABOVE its rest
	# (the spring memory carries momentum through rest), the net never jumps
	# while it settles, and it is still within 3 s.
	var overshoot := 0.0
	var sleep_jump := -1.0
	var last := PackedVector3Array()
	for i in net.particle_count():
		last.push_back(net.particle_position(i))
	for i in 180:
		var was_awake := net.is_awake()
		net.step(dt, [])
		var jump := 0.0
		for k in net.particle_count():
			var pp := net.particle_position(k)
			if net.rest_position(k).y < 0.2:
				overshoot = maxf(overshoot, pp.y - net.rest_position(k).y)
			jump = maxf(jump, pp.distance_to(last[k]))
			last[k] = pp
		if was_awake and not net.is_awake():
			sleep_jump = jump   # the frame it fell asleep: eased home, no snap
	t.ok(overshoot > 0.004, "the cords whip back above rest after the ball (%.4f m)" % overshoot)
	t.ok(sleep_jump >= 0.0 and sleep_jump < 0.004, "falling asleep is eased, not a teleport (jump %.4f m)" % sleep_jump)
	t.ok(net.max_displacement() < 0.02, "net settles after the ball (%.4f m)" % net.max_displacement())
	# Normals follow the cords: present, unit length, one per vertex.
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	t.eq(nrm.size(), (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "a normal per vertex")
	var unit := true
	for v in nrm:
		if absf(v.length() - 1.0) > 1e-4:
			unit = false
	t.ok(unit, "normals are unit length")
	# The swish kick moves the cords under the entry point at once.
	for i in 240:
		net.step(dt, [])
	var rest_disp := net.max_displacement()
	net.kick(mi.transform * Vector3(0, 0.21, 0), Vector3(0, -5.0, 0))
	net.step(dt, [])
	t.ok(net.is_awake() and net.max_displacement() > rest_disp + 0.008, "a kick shoves the cords (%.4f m)" % net.max_displacement())

	# 3. Deterministic: same ball path twice → identical particle positions.
	var a := _mesh_sim()
	var b := _mesh_sim()
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
	var c := _mesh_sim()
	var mc := _make_net()
	root.add_child(mc)
	root.add_child(c)
	c.setup(mc)
	_run_drop(c, 0.0, 0.25)
	_run_drop(a, 15.0, 0.0)  # (no-op, keeps API symmetric)
	var d := _mesh_sim()
	var md := _make_net()
	root.add_child(md)
	root.add_child(d)
	d.setup(md)
	_run_drop(d, 15.0, 0.25)
	var diff := 0.0
	for i in c.particle_count():
		diff = maxf(diff, c.particle_position(i).distance_to(d.particle_position(i)))
	t.ok(diff > 0.005, "spin changes how the cords are dragged (%.4f m)" % diff)

	root.free()
	# The tuning strip's knobs: by name, with a re-settle, and overrides on top.
	var kn := _mesh_sim()
	var mi2 := _make_net()
	var root2 := Node3D.new()
	root2.add_child(mi2)
	root2.add_child(kn)
	kn.setup(mi2)
	t.eq(kn.knobs().keys(), NetSim.KNOBS, "every knob reads back by name")
	kn.set_knob("rest_spring", 150.0)
	t.close(kn.rest_spring, 150.0, 0.0, "a knob sets")
	kn.set_knob("nope", 1.0)
	kn.apply_overrides({"damping": 0.99, "tail_mass": 2.0, "junk": 5})
	t.close(kn.damping, 0.99, 0.0, "overrides apply by name")
	t.close(kn.tail_mass, 2.0, 0.0, "…every known knob")
	t.ok(not kn.is_awake() and kn.max_displacement() < 1e-9, "re-settled at rest after a knob change")
	root2.free()


## The cotton net (docs/BLENDER_101.md §28): the layout, the particles, a
## swish through it under the 2026-10-14 defaults.
func _cotton(t) -> void:
	var rim_r: float = SimConstants.R_RIM
	var tube_r: float = SimConstants.R_TUBE
	var lay := NetSim.cotton_layout(rim_r, tube_r)
	var knots: PackedVector3Array = lay["knots"]
	var hooks: PackedVector3Array = lay["hooks"]
	t.eq(knots.size(), 84, "cotton: 7 rings × 12 knots")
	t.eq(hooks.size(), 12, "cotton: 12 hooks")
	t.eq((lay["springs"] as Array).size(), 156, "cotton: 144 diagonals + 12 loops")
	t.eq((lay["cords"] as Array).size(), 12, "cotton: twelve cords")
	t.eq((lay["bottom"] as Array).size(), 12, "cotton: a 12-knot bottom ring")
	# Hooks hide under the rim tube: below its centre line, inside its
	# underside, just outside the ring's radius; nothing rises above the rim.
	var hooks_hidden := true
	for h in hooks:
		var r := Vector2(h.x, h.z).length()
		if h.y >= 0.0 or h.y < -tube_r or absf(r - (rim_r + NetSim.HOOK_OUT)) > 1e-6:
			hooks_hidden = false
	t.ok(hooks_hidden, "cotton: every hook sits under the rim tube (y %.4f)" % hooks[0].y)
	var top := -INF
	for k in knots:
		top = maxf(top, k.y)
	t.ok(top <= -tube_r - NetSim.COTTON_TOP_GAP + 1e-6, "cotton: the top knots hang under the tube (%.3f)" % top)
	# Ring radii: the rim at the top, 0.10 at the bottom, turned half a step per ring.
	t.close(Vector2(knots[0].x, knots[0].z).length(), rim_r, 1e-6, "cotton: ring 0 at the rim's radius")
	t.close(Vector2(knots[72].x, knots[72].z).length(), NetSim.COTTON_BOTTOM_R, 1e-6, "cotton: the bottom ring at 0.10")
	t.close(knots[72].y, -NetSim.COTTON_LEN, 1e-6, "cotton: 0.42 m long")
	t.close(atan2(knots[12].z, knots[12].x), TAU / 24.0, 1e-6, "cotton: ring 1 turned half a step")
	# Cord i: left diagonal through Knot_k_((i−k) mod 12), right through Knot_k_i, over Hook_i.
	var c3: Dictionary = lay["cords"][3]
	t.eq(int(c3["left"][2]), 12 + 2 * 12 + 1, "cotton: cord 3's left diagonal passes Knot_2_1")
	t.eq(int(c3["right"][2]), 12 + 2 * 12 + 3, "cotton: …and its right diagonal Knot_2_3")
	t.eq(int(c3["hook"]), 3, "cotton: …over Hook_3")
	t.eq(int(c3["k0"]), 12 + 3, "cotton: …through Knot_0_3")

	var root := Node3D.new()
	var space := Node3D.new()
	root.add_child(space)
	var net := NetSim.new()
	root.add_child(net)
	t.ok(net.setup_cotton(space, rim_r, tube_r), "cotton: setup needs no mesh")
	t.eq(net.structure, "cotton", "cotton: structure tag")
	t.eq(net.particle_count(), 96, "cotton: 96 particles")
	var pinned := 0
	for i in net.particle_count():
		if net.is_pinned(i):
			pinned += 1
	t.eq(pinned, 12, "cotton: the 12 hooks are pinned")
	t.ok(net.rest_position(12 + 72).y < knots[72].y, "cotton: the rest pose settled under gravity (%.4f < %.4f)" % [net.rest_position(84).y, knots[72].y])
	for i in 30:
		net.step(1.0 / 60.0, [])
	t.ok(not net.is_awake() and net.max_displacement() < 1e-9, "cotton: asleep at rest")

	# A swish: the net flares, the hooks never move, and with no rest spring
	# gravity and the cords alone bring it back.
	var dt := 1.0 / 60.0
	var y := 0.42
	var vy := -4.6
	var peak := 0.0
	var bottom_spread := 0.0
	for i in 50:
		net.step(dt, [_ball(Vector3(0.0, y, 0.0), Vector3(0.0, vy, 0.0), 18.0)])
		vy -= 9.81 * dt
		y += vy * dt
		peak = maxf(peak, net.max_displacement())
		var pb := net.particle_position(84)
		bottom_spread = maxf(bottom_spread, Vector2(pb.x, pb.z).length() - Vector2(net.rest_position(84).x, net.rest_position(84).z).length())
	t.ok(net.is_awake(), "cotton: the ball wakes the net")
	t.ok(peak > 0.03, "cotton: the ball spreads the cords (peak %.3f m)" % peak)
	t.ok(bottom_spread > 0.01, "cotton: the bottom ring flares outward (%.3f m)" % bottom_spread)
	var hook_moved := 0.0
	for i in 12:
		hook_moved = maxf(hook_moved, net.particle_position(i).distance_to(net.rest_position(i)))
	t.close(hook_moved, 0.0, 1e-9, "cotton: the hooks stay on the rim")
	for i in 240:
		net.step(dt, [])
	t.ok(net.max_displacement() < 0.02, "cotton: back at rest within 4 s with no rest spring (%.4f m)" % net.max_displacement())
	for i in 240:
		net.step(dt, [])
	var rest_disp := net.max_displacement()
	net.kick(space.transform * Vector3(0.0, 0.0, 0.0), Vector3(0.0, -5.0, 0.0))
	net.step(dt, [])
	t.ok(net.is_awake() and net.max_displacement() > rest_disp + 0.008, "cotton: the kick shoves the cords (%.4f m)" % net.max_displacement())

	# Deterministic, and spin still tells (friction 0.09).
	var a := NetSim.new()
	var b := NetSim.new()
	var c := NetSim.new()
	for n in [a, b, c]:
		var sp := Node3D.new()
		root.add_child(sp)
		root.add_child(n)
		n.setup_cotton(sp, rim_r, tube_r)
	_run_drop(a, 15.0, 0.4)
	_run_drop(b, 15.0, 0.4)
	_run_drop(c, 0.0, 0.4)
	var same := true
	var diff := 0.0
	for i in a.particle_count():
		if a.particle_position(i) != b.particle_position(i):
			same = false
		diff = maxf(diff, a.particle_position(i).distance_to(c.particle_position(i)))
	t.ok(same, "cotton: identical inputs give identical nets")
	t.ok(diff > 1e-3, "cotton: spin changes how the cords are dragged (%.4f m)" % diff)
	# Knobs re-settle the cotton net too (the NET page's RESET refreshes the tail weight).
	var soft := HoopSet.new()
	soft.net_tail_mass = 2.0
	net.configure(soft)
	t.ok(not net.is_awake() and net.max_displacement() < 1e-9, "cotton: configure re-settles at rest")
	t.ok(net.rest_position(84).y < net.rest_position(12 + 60).y, "cotton: the bottom ring hangs lowest after a heavier tail")
	t.ok(net.cords().size() == 12, "cotton: the cords read back")
	root.free()


## The chain net (docs/BLENDER_101.md §29): 5 rings, S-hooks on the rim's
## NetHook loops, under the chain hoop set's feel.
func _chain(t) -> void:
	var rim_r: float = SimConstants.R_RIM
	var tube_r: float = SimConstants.R_TUBE
	var lay := NetSim.chain_layout(rim_r, tube_r)
	var knots: PackedVector3Array = lay["knots"]
	var hooks: PackedVector3Array = lay["hooks"]
	t.eq(knots.size(), 60, "chain: 5 rings × 12 junctions")
	t.eq(hooks.size(), 12, "chain: 12 S-hooks")
	t.eq((lay["springs"] as Array).size(), 108, "chain: 96 diagonal runs + 12 hook drops")
	t.eq((lay["cords"] as Array).size(), 12, "chain: twelve chains")
	t.eq((lay["bottom"] as Array).size(), 12, "chain: a 12-ring bottom")
	t.eq(int(lay["rows"]), 4, "chain: four rows")
	var hook_y := -(tube_r + NetSim.CHAIN_HOOK_DROP)
	var hooks_ok := true
	for h in hooks:
		if absf(h.y - hook_y) > 1e-6 or absf(Vector2(h.x, h.z).length() - rim_r) > 1e-6:
			hooks_ok = false
	t.ok(hooks_ok, "chain: the hook bones hang on the rim's radius %.3f under its centre line" % -hook_y)
	t.ok(hook_y < -(tube_r + 0.011 * 2 - 0.002) and hook_y > -0.42, "chain: …below the rim's NetHook loop")
	t.close(knots[0].y, hook_y - NetSim.CHAIN_HOOK_HH, 1e-6, "chain: ring 0 one link under the hooks")
	t.close(Vector2(knots[0].x, knots[0].z).length(), rim_r, 1e-6, "chain: ring 0 at the rim's radius")
	t.close(knots[48].y, -NetSim.NET_LEN, 1e-6, "chain: 0.42 m long")
	t.close(Vector2(knots[48].x, knots[48].z).length(), NetSim.NET_BOTTOM_R, 1e-6, "chain: the bottom ring at 0.10")
	var c3: Dictionary = lay["cords"][3]
	t.eq(int(c3["left"][2]), 12 + 2 * 12 + 1, "chain: chain 3's left diagonal passes Knot_2_1")
	t.eq(int(c3["hook"]), 3, "chain: …over Hook_3")

	var set: HoopSet = load("res://assets/hoops/chain/hoop_set.tres")
	var root := Node3D.new()
	var space := Node3D.new()
	root.add_child(space)
	var net := NetSim.new()
	root.add_child(net)
	net.configure(set)
	t.ok(net.setup_chain(space, rim_r, tube_r), "chain: setup needs no mesh")
	t.eq(net.structure, "chain", "chain: structure tag")
	t.eq(net.particle_count(), 72, "chain: 72 particles")
	t.eq(net.spring_count(), 108, "chain: 108 springs")
	var pinned := 0
	for i in net.particle_count():
		if net.is_pinned(i):
			pinned += 1
	t.eq(pinned, 12, "chain: the 12 hooks are pinned")
	t.ok(net.rest_position(12 + 48).y < knots[48].y, "chain: the rest pose settled under gravity")
	for i in 30:
		net.step(1.0 / 60.0, [])
	t.ok(not net.is_awake() and net.max_displacement() < 1e-9, "chain: asleep at rest")

	var dt := 1.0 / 60.0
	var y := 0.42
	var vy := -4.6
	var peak := 0.0
	var spread := 0.0
	for i in 50:
		net.step(dt, [_ball(Vector3(0.0, y, 0.0), Vector3(0.0, vy, 0.0), 14.0)])
		vy -= 9.81 * dt
		y += vy * dt
		peak = maxf(peak, net.max_displacement())
		var pb := net.particle_position(60)
		spread = maxf(spread, Vector2(pb.x, pb.z).length() - Vector2(net.rest_position(60).x, net.rest_position(60).z).length())
	t.ok(net.is_awake(), "chain: the ball wakes the net")
	t.ok(peak > 0.03, "chain: the ball spreads the chains (peak %.3f m)" % peak)
	t.ok(spread > 0.01, "chain: the bottom ring flares outward (%.3f m)" % spread)
	var hook_moved := 0.0
	for i in 12:
		hook_moved = maxf(hook_moved, net.particle_position(i).distance_to(net.rest_position(i)))
	t.close(hook_moved, 0.0, 1e-9, "chain: the hooks stay on the rim")
	for i in 240:
		net.step(dt, [])
	t.ok(net.max_displacement() < 0.02, "chain: the rest spring brings it back within 4 s (%.4f m)" % net.max_displacement())
	var slept := 0
	while net.is_awake() and slept < 900:
		net.step(dt, [])
		slept += 1
	t.ok(not net.is_awake(), "chain: asleep again within %d frames" % slept)
	net.kick(space.transform * Vector3(0.0, 0.0, 0.0), Vector3(0.0, -5.0, 0.0))
	net.step(dt, [])
	t.ok(net.is_awake() and net.max_displacement() > 0.002, "chain: the kick (0.6 m/s) shoves the chains (%.4f m)" % net.max_displacement())

	var a := NetSim.new()
	var b := NetSim.new()
	var c := NetSim.new()
	for n in [a, b, c]:
		var sp := Node3D.new()
		root.add_child(sp)
		root.add_child(n)
		n.configure(set)
		n.setup_chain(sp, rim_r, tube_r)
	_run_drop(a, 15.0, 0.4)
	_run_drop(b, 15.0, 0.4)
	_run_drop(c, 0.0, 0.4)
	var same := true
	var diff := 0.0
	for i in a.particle_count():
		if a.particle_position(i) != b.particle_position(i):
			same = false
		diff = maxf(diff, a.particle_position(i).distance_to(c.particle_position(i)))
	t.ok(same, "chain: identical inputs give identical nets")
	t.ok(diff > 1e-3, "chain: spin changes how the chains are dragged (%.4f m)" % diff)
	root.free()
