class_name ChainNet
extends NetRig
## The city hoop's steel chain net (2026-10-14, docs/BLENDER_101.md §29):
## Ross's design model (27a) built in Godot. Twelve continuous chains on the
## knotted-net rig — a bone per junction ring (60, driven by NetSim) and a
## pinned bone per S-hook (12, hanging from the rim's NetHook loops). The
## links are ONE oval wire link in a MultiMesh, placed along every chain run
## from its two bones each frame the net moves: straight when the run is
## taut, a shallow sag when it goes slack, every other link turned 90° the
## way a real chain hangs, and interlocking (the pitch is the link's inner
## length). The junction rings and the S-hooks are skinned, rigid on their
## bones. Galvanised steel pixel textures.

const LINK_LEN := 0.034
const LINK_W := 0.017
const LINK_WIRE := 0.0028
const LINK_PITCH := LINK_LEN - 4.0 * LINK_WIRE   # 22.8 mm: each link's end passes through the next
const RING_R := 0.0085
const RING_WIRE := 0.0032
const LINK_COLORS := ["#A9AFB6", "#6E747C", "#E4E8EC", "#8C6A4E"]
const RING_COLORS := ["#8E949C", "#5C6168", "#CDD2D8", "#7A5A40"]

var links: MultiMeshInstance3D
var _run_a := PackedInt32Array()
var _run_b := PackedInt32Array()
var _run_len := PackedFloat32Array()
var _run_n := PackedInt32Array()
var _link_xf: Array[Transform3D] = []     # the placed links (a CPU copy: tests, headless)
var _placed_rest := Vector3(INF, INF, INF)   # the bottom knot's rest when last placed


## Build the rig, the link multimesh, the rings and the S-hooks from
## NetSim.chain_layout().
func build(layout: Dictionary) -> void:
	build_rig(layout)
	var knots: PackedVector3Array = layout["knots"]
	var n_hooks: int = (layout["hooks"] as PackedVector3Array).size()
	var link_mat := _material(steel_texture(LINK_COLORS), 0.5, 0.35)
	var ring_mat := _material(steel_texture(RING_COLORS), 0.5, 0.35)

	# Net_Links: n interlocking links per spring, from its rest length.
	_run_a = PackedInt32Array()
	_run_b = PackedInt32Array()
	_run_len = PackedFloat32Array()
	_run_n = PackedInt32Array()
	var total := 0
	for s in layout["springs"]:
		var n := maxi(1, roundi(float(s[2]) / LINK_PITCH))
		_run_a.push_back(int(s[0]))
		_run_b.push_back(int(s[1]))
		_run_len.push_back(float(s[2]))
		_run_n.push_back(n)
		total += n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link_mesh(link_mat)
	mm.instance_count = total
	links = MultiMeshInstance3D.new()
	links.name = "Net_Links"
	links.multimesh = mm
	links.extra_cull_margin = 0.5
	skeleton.add_child(links)
	_link_xf.resize(total)
	_tris += total * 80
	_place_links_at(_rest)

	# Net_Rings: a junction ring at every crossing, standing in the net's
	# surface (its plane holds the tangent and up), rigid on its bone.
	var rings := _MeshBuilder.new()
	for p in knots.size():
		var pos := knots[p]
		var f := _frame(pos)
		var f_tan: Vector3 = f["tan"]
		var pts: Array[Vector3] = []
		for s in 10:
			var a := float(s) / 10.0 * TAU
			pts.push_back(pos + f_tan * (RING_R * cos(a)) + Vector3(0.0, RING_R * sin(a), 0.0))
		var bone := _bone_of_particle[n_hooks + p]
		_tube(rings, pts, RING_WIRE, 1.0, bone, bone, 4, true)
	_add_surface("Net_Rings", rings, ring_mat)

	# Net_Hooks: twelve S-hooks. The top curl wraps the rim's NetHook loop
	# (inward of the bone), the lower curl carries the chain's top link.
	var hooks := _MeshBuilder.new()
	for i in n_hooks:
		var p := _rest[i]
		var f := _frame(p)
		var f_out: Vector3 = f["out"]
		var pts: Array[Vector3] = []
		for s in 9:
			var a := PI * float(s) / 8.0
			pts.push_back(p + f_out * (-0.007 + 0.007 * cos(a)) + Vector3(0.0, 0.010 + 0.007 * sin(a), 0.0))
		for s in range(1, 9):
			var a := PI * float(s) / 8.0
			pts.push_back(p + f_out * (0.006 - 0.006 * cos(a)) + Vector3(0.0, 0.010 - 0.006 * sin(a) - 0.009 * float(s) / 8.0, 0.0))
		var bone := _bone_of_particle[i]
		_tube(hooks, pts, LINK_WIRE * 1.1, 2.0, bone, bone, 4)
	_add_surface("Net_Hooks", hooks, ring_mat)


## Move the bones, and re-place the links whenever the net is awake or its
## rest pose changed (a knob change re-settles it).
func sync(sim: NetSim) -> void:
	super(sim)
	if links == null:
		return
	var bottom_rest := sim.rest_position(sim.particle_count() - 1)
	if sim.is_awake() or bottom_rest != _placed_rest:
		var pos := PackedVector3Array()
		pos.resize(sim.particle_count())
		for i in sim.particle_count():
			pos[i] = sim.particle_position(i)
		_place_links_at(pos)
		_placed_rest = bottom_rest


func link_count() -> int:
	return _link_xf.size()


func link_transform(i: int) -> Transform3D:
	return _link_xf[i] if i < _link_xf.size() else Transform3D()


## Links per run and the runs' endpoints, for the tests.
func run_count() -> int:
	return _run_a.size()


func run_links(i: int) -> int:
	return _run_n[i]


func run_ends(i: int) -> PackedInt32Array:
	return PackedInt32Array([_run_a[i], _run_b[i]])


## Place every link along its run: straight when the run is taut, a shallow
## catenary when it is slack (sag = half the length the run has to spare),
## y along the run, the flat plane turned 90° on every other link.
func _place_links_at(pos: PackedVector3Array) -> void:
	var mm := links.multimesh
	var idx := 0
	for r in _run_a.size():
		var a := pos[_run_a[r]]
		var b := pos[_run_b[r]]
		var d := b - a
		var dist := d.length()
		var rest_len := _run_len[r]
		var sag := 0.5 * sqrt(maxf(0.0, rest_len * rest_len - dist * dist))
		var n := _run_n[r]
		for k in n:
			var t := (float(k) + 0.5) / float(n)
			var p := a + d * t
			p.y -= sag * 4.0 * t * (1.0 - t)
			var y := d
			y.y -= sag * 4.0 * (1.0 - 2.0 * t)
			y = y.normalized() if y.length_squared() > 1e-12 else Vector3.DOWN
			var ref := Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)
			var x := y.cross(ref).normalized()
			var z := x.cross(y).normalized()
			var basis := Basis(x, y, z) if k % 2 == 0 else Basis(z, y, -x)
			_link_xf[idx] = Transform3D(basis, p)
			mm.set_instance_transform(idx, _link_xf[idx])
			idx += 1


## One link: an oval ring of wire (LINK_LEN × LINK_W, wire LINK_WIRE), its
## long axis along +y, its flat plane x-y; u runs round the oval, v round
## the wire. 80 tris.
static func link_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around := 10
	var tube := 4
	var half_l := LINK_LEN * 0.5 - LINK_W * 0.5
	var ring_r := LINK_W * 0.5 - LINK_WIRE
	# Centre-line of the oval: two straight runs joined by semicircles (a stadium).
	var path: Array[Vector3] = []
	var tangents: Array[Vector3] = []
	for i in around:
		var t := float(i) / around
		var p: Vector3
		var tg: Vector3
		if t < 0.5:
			var ang := PI * (t / 0.5) - PI * 0.5      # right semicircle, from bottom to top
			p = Vector3(ring_r * cos(ang), half_l + ring_r * sin(ang), 0.0)
			tg = Vector3(-sin(ang), cos(ang), 0.0)
			if i == 0:
				p = Vector3(ring_r, -half_l, 0.0)
				tg = Vector3(0, 1, 0)
		else:
			var ang := PI * ((t - 0.5) / 0.5) + PI * 0.5   # left semicircle, top to bottom
			p = Vector3(ring_r * cos(ang), -half_l + ring_r * sin(ang), 0.0)
			tg = Vector3(-sin(ang), cos(ang), 0.0)
			if i == around / 2:
				p = Vector3(-ring_r, half_l, 0.0)
				tg = Vector3(0, -1, 0)
		path.push_back(p)
		tangents.push_back(tg.normalized())
	var rings: Array = []
	for i in around:
		var tg := tangents[i]
		var side := Vector3(0, 0, 1)
		var out := tg.cross(side).normalized()
		var ring := []
		for k in tube:
			var a := TAU * k / tube
			var nrm := (out * cos(a) + side * sin(a)).normalized()
			ring.push_back([path[i] + nrm * LINK_WIRE, nrm, Vector2(float(i) / around * 2.0, float(k) / tube)])
		rings.push_back(ring)
	for i in around:
		var r0: Array = rings[i]
		var r1: Array = rings[(i + 1) % around]
		for k in tube:
			var k1 := (k + 1) % tube
			for tri in [[r0[k], r1[k], r1[k1]], [r0[k], r1[k1], r0[k1]]]:
				for v in tri:
					st.set_normal(v[1])
					st.set_uv(v[2])
					st.add_vertex(v[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh
