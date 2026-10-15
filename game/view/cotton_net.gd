class_name CottonNet
extends Node3D
## The nylon net's body (2026-10-14, docs/BLENDER_101.md §28): Ross's design
## model (26a) built in Godot. Twelve continuous cords skinned to one
## Skeleton3D — a bone per knot (84, driven by NetSim) and a pinned bone per
## hook (12, under the rim tube) — in three skinned meshes: the cords
## (5-sided tubes blending between the two bones they join), the knots (a
## flattened octahedron rigid on its bone) and the frayed tails under the
## bottom ring. Nothing is rebuilt per frame: sync() moves the bones.
## Origin = the rim centre, y up, metres.

const CORD_R := 0.004
const KNOT_R := 0.0085
const LW := 0.009              # loop half-width (m): the two halves spread this far
const SAG := 0.0015            # a diagonal's middle hangs this far under its chord
const SIDES := 5
const DIAG_SEGS := 4
const LOOP_SEGS := 6
const TEX_SIZE := 16
const CORD_COLORS := ["#EDE6D4", "#B9AE96", "#FFFBF0"]
const KNOT_COLORS := ["#DDD3BC", "#A99D84", "#F4EEDD"]

var skeleton: Skeleton3D
var _layout: Dictionary = {}
var _bone_of_particle := PackedInt32Array()   # particle index → bone index
var _tris := 0
var _rng_state := 5
var _textures: Array[ImageTexture] = []


## Build the rig and the three meshes from NetSim.cotton_layout().
func build(layout: Dictionary) -> void:
	_layout = layout
	_rng_state = 5
	var hooks: PackedVector3Array = layout["hooks"]
	var knots: PackedVector3Array = layout["knots"]
	var n_hooks := hooks.size()
	var n_knots := knots.size()
	skeleton = Skeleton3D.new()
	skeleton.name = "NetRoot"
	add_child(skeleton)
	var rest := PackedVector3Array()
	rest.resize(n_hooks + n_knots)
	_bone_of_particle.resize(n_hooks + n_knots)
	var root := skeleton.add_bone("NetRoot")
	skeleton.set_bone_rest(root, Transform3D.IDENTITY)
	for i in n_hooks:
		_bone_of_particle[i] = _add_bone("Hook_%d" % i, hooks[i])
		rest[i] = hooks[i]
	var cols: int = NetSim.COTTON_COLS
	for p in n_knots:
		var k := p / cols
		var i := p % cols
		_bone_of_particle[n_hooks + p] = _add_bone("Knot_%d_%d" % [k, i], knots[p])
		rest[n_hooks + p] = knots[p]
	var skin := Skin.new()
	for b in skeleton.get_bone_count():
		skin.add_bind(b, skeleton.get_bone_rest(b).affine_inverse())
	_textures = [_twist_texture(CORD_COLORS), _twist_texture(KNOT_COLORS)]
	var cord_mat := _material(_textures[0])
	var knot_mat := _material(_textures[1])
	_tris = 0

	# Net_Cords: per cord 12 diagonals + the two loop halves.
	var cords := _MeshBuilder.new()
	for c in layout["cords"]:
		var left: Array = c["left"]
		var right: Array = c["right"]
		for k in NetSim.COTTON_ROWS:
			_diagonal(cords, rest, int(left[k]), int(left[k + 1]))
			_diagonal(cords, rest, int(right[k]), int(right[k + 1]))
		_loop_half(cords, rest, int(c["k0"]), int(c["hook"]), -1.0)
		_loop_half(cords, rest, int(c["k0"]), int(c["hook"]), 1.0)
	_add_surface("Net_Cords", cords, cord_mat, skin)

	# Net_Knots: a blob at every crossing, rigid on its bone.
	var blobs := _MeshBuilder.new()
	for p in n_knots:
		var k := p / cols
		var pos := knots[p]
		var r := KNOT_R * (1.05 if k == 0 else 1.0)
		var turn := atan2(pos.z, pos.x) + _rnd() * 0.6
		_octahedron(blobs, pos, r, turn, _bone_of_particle[n_hooks + p])
	_add_surface("Net_Knots", blobs, knot_mat, skin)

	# Net_Tails: two frayed ends under each bottom knot.
	var tails := _MeshBuilder.new()
	for p in layout["bottom"]:
		var pos := rest[int(p)]
		var f := _frame(pos)
		var f_out: Vector3 = f["out"]
		var f_tan: Vector3 = f["tan"]
		for s in [-1.0, 1.0]:
			var end: Vector3 = pos + Vector3(0.0, -0.02 - _rnd() * 0.006, 0.0) + f_out * 0.004 + f_tan * (s * 0.006)
			var bone := _bone_of_particle[int(p)]
			_tube(tails, [pos, pos.lerp(end, 0.5), end], CORD_R * 0.85, 1.0, bone, bone)
	_add_surface("Net_Tails", tails, cord_mat, skin)


## Move the knot bones to the sim's particles (each frame the net is awake,
## and once after a re-settle). Hooks are pinned: they never move.
func sync(sim: NetSim) -> void:
	if skeleton == null:
		return
	var n := mini(sim.particle_count(), _bone_of_particle.size())
	for i in n:
		if sim.is_pinned(i):
			continue
		skeleton.set_bone_pose_position(_bone_of_particle[i], sim.particle_position(i))


func bone_count() -> int:
	return skeleton.get_bone_count() if skeleton != null else 0


func surface_count() -> int:
	var n := 0
	if skeleton != null:
		for c in skeleton.get_children():
			if c is MeshInstance3D:
				n += 1
	return n


func tri_count() -> int:
	return _tris


func textures() -> Array[ImageTexture]:
	return _textures


## The bone a particle drives (−1 if none).
func bone_of_particle(i: int) -> int:
	return _bone_of_particle[i] if i < _bone_of_particle.size() else -1


func _add_bone(name_: String, p: Vector3) -> int:
	var b := skeleton.add_bone(name_)
	skeleton.set_bone_parent(b, 0)
	skeleton.set_bone_rest(b, Transform3D(Basis.IDENTITY, p))
	skeleton.set_bone_pose_position(b, p)
	return b


## Tangent-out frame at a point on the net (about the hoop's axis).
static func _frame(p: Vector3) -> Dictionary:
	var a := atan2(p.z, p.x)
	return {"tan": Vector3(-sin(a), 0.0, cos(a)), "out": Vector3(cos(a), 0.0, sin(a)), "a": a}


func _rnd() -> float:
	_rng_state = (_rng_state * 16807) % 2147483647
	return float(_rng_state) / 2147483647.0


## A diagonal piece between two knots: a quadratic bezier sagging SAG under
## its chord, skinned from bone A at the start to bone B at the end.
func _diagonal(mb: _MeshBuilder, rest: PackedVector3Array, a: int, b: int) -> void:
	var pa := rest[a]
	var pb := rest[b]
	var mid := pa.lerp(pb, 0.5) + Vector3(0.0, -SAG, 0.0)
	var pts: Array[Vector3] = []
	for j in DIAG_SEGS + 1:
		var u := float(j) / float(DIAG_SEGS)
		pts.push_back(pa.lerp(mid, u).lerp(mid.lerp(pb, u), u))
	_tube(mb, pts, CORD_R, 2.0, _bone_of_particle[a], _bone_of_particle[b])


## One half of the hook loop: a cubic bezier from the top knot up and round
## to the hook, spread sideways by s × LW so the two halves make a loop.
func _loop_half(mb: _MeshBuilder, rest: PackedVector3Array, k0: int, hook: int, s: float) -> void:
	var p0 := rest[k0]
	var p3 := rest[hook]
	var f := _frame(p0)
	var f_out: Vector3 = f["out"]
	var f_tan: Vector3 = f["tan"]
	var hh := p3.y - p0.y
	var p1: Vector3 = p0 + f_tan * (s * LW * 1.15) + Vector3(0.0, hh * 0.3, 0.0) + f_out * 0.001
	var p2: Vector3 = p3 + f_tan * (s * LW * 0.95) + f_out * 0.002
	var pts: Array[Vector3] = []
	for j in LOOP_SEGS + 1:
		var u := float(j) / float(LOOP_SEGS)
		pts.push_back(p0.bezier_interpolate(p1, p2, p3, u))
	_tube(mb, pts, CORD_R, 3.0, _bone_of_particle[k0], _bone_of_particle[hook])


## A SIDES-sided tube along a polyline, flat shaded, UV u along (× uvx), v
## around; vertex weights lerp bone_a → bone_b along the length.
func _tube(mb: _MeshBuilder, pts: Array[Vector3], r: float, uvx: float, bone_a: int, bone_b: int) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings: Array[PackedVector3Array] = []
	var normal := Vector3.ZERO
	for j in n:
		var tangent: Vector3
		if j == 0:
			tangent = pts[1] - pts[0]
		elif j == n - 1:
			tangent = pts[n - 1] - pts[n - 2]
		else:
			tangent = pts[j + 1] - pts[j - 1]
		tangent = tangent.normalized() if tangent.length() > 1e-9 else Vector3.DOWN
		if j == 0:
			var ref := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			normal = ref.cross(tangent).normalized()
		else:
			normal = (normal - tangent * normal.dot(tangent))
			normal = normal.normalized() if normal.length() > 1e-9 else tangent.cross(Vector3.RIGHT).normalized()
		var binormal := tangent.cross(normal).normalized()
		var ring := PackedVector3Array()
		for sd in SIDES:
			var a := float(sd) / float(SIDES) * TAU
			ring.push_back(pts[j] + (normal * cos(a) + binormal * sin(a)) * r)
		rings.push_back(ring)
	for j in n - 1:
		var u0 := float(j) / float(n - 1) * uvx
		var u1 := float(j + 1) / float(n - 1) * uvx
		var w0 := float(j) / float(n - 1)
		var w1 := float(j + 1) / float(n - 1)
		for sd in SIDES:
			var s1 := (sd + 1) % SIDES
			var v0 := float(sd) / float(SIDES)
			var v1 := float(sd + 1) / float(SIDES)
			var a0 := rings[j][sd]
			var a1 := rings[j][s1]
			var b0 := rings[j + 1][sd]
			var b1 := rings[j + 1][s1]
			mb.tri([a0, b0, b1], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)],
				[bone_a, bone_b], [w0, w1, w1])
			mb.tri([a0, b1, a1], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)],
				[bone_a, bone_b], [w0, w1, w0])
	_tris += (n - 1) * SIDES * 2


## A knot blob: an octahedron of radius r squashed to 0.8 in y, turned about
## y, rigid on its bone.
func _octahedron(mb: _MeshBuilder, at: Vector3, r: float, turn: float, bone: int) -> void:
	var rot := Basis(Vector3.UP, turn)
	var px := at + rot * Vector3(r, 0.0, 0.0)
	var nx := at + rot * Vector3(-r, 0.0, 0.0)
	var py := at + Vector3(0.0, r * 0.8, 0.0)
	var ny := at + Vector3(0.0, -r * 0.8, 0.0)
	var pz := at + rot * Vector3(0.0, 0.0, r)
	var nz := at + rot * Vector3(0.0, 0.0, -r)
	var uv := [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.25, 0.5)]
	for face in [[px, pz, py], [pz, nx, py], [nx, nz, py], [nz, px, py],
			[pz, px, ny], [nx, pz, ny], [nz, nx, ny], [px, nz, ny]]:
		mb.tri(face, uv, [bone, bone], [0.0, 0.0, 0.0])
	_tris += 8


func _add_surface(name_: String, mb: _MeshBuilder, mat: Material, skin: Skin) -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mb.verts
	arrays[Mesh.ARRAY_NORMAL] = mb.normals
	arrays[Mesh.ARRAY_TEX_UV] = mb.uvs
	arrays[Mesh.ARRAY_BONES] = mb.bones
	arrays[Mesh.ARRAY_WEIGHTS] = mb.weights
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.skin = skin
	skeleton.add_child(mi)
	mi.skeleton = mi.get_path_to(skeleton)
	# The bones move the cords well past the rest bounds in a swish.
	mi.extra_cull_margin = 0.5


func _material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 1.0
	m.metallic = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	return m


## The design's 16×16 pixel twist: a diagonal dark stripe every 8 texels, a
## light one between, ten seeded speckles.
func _twist_texture(colors: Array) -> ImageTexture:
	var base := Color.html(colors[0])
	var dark := Color.html(colors[1])
	var light := Color.html(colors[2])
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	img.fill(base)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var k := (x + y) % 8
			if k < 2:
				img.set_pixel(x, y, dark)
			elif k == 4:
				img.set_pixel(x, y, light)
	for _i in 10:
		var c := dark if _rnd() < 0.5 else light
		var x := int(floor(_rnd() * TEX_SIZE))
		var y := int(floor(_rnd() * TEX_SIZE))
		img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Non-indexed, flat-shaded triangle accumulator with 4 bones/weights per
## vertex (two used: a and b; weight on b = w, on a = 1 − w).
class _MeshBuilder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()

	func tri(p: Array, uv: Array, ab: Array, w: Array) -> void:
		var nrm: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
		nrm = nrm.normalized() if nrm.length() > 1e-12 else Vector3.UP
		for i in 3:
			verts.push_back(p[i])
			normals.push_back(nrm)
			uvs.push_back(uv[i])
			var wb: float = clampf(float(w[i]), 0.0, 1.0)
			bones.push_back(int(ab[0]))
			bones.push_back(int(ab[1]))
			bones.push_back(0)
			bones.push_back(0)
			weights.push_back(1.0 - wb)
			weights.push_back(wb)
			weights.push_back(0.0)
			weights.push_back(0.0)
