class_name NetRig
extends Node3D
## The body of a knotted net (docs/BLENDER_101.md §28–29): one Skeleton3D
## "NetRoot" with a bone per hook (pinned) and per knot (driven by NetSim),
## a Skin whose binds are the bones' rest poses, and the helpers the bodies
## build their skinned meshes with — flat-shaded tube and rigid pieces, 4
## bones/weights per vertex, 16×16 nearest pixel textures. CottonNet and
## ChainNet extend it. Origin = the rim centre, y up, metres.

const TEX_SIZE := 16

var skeleton: Skeleton3D
var skin: Skin
var _layout: Dictionary = {}
var _rest := PackedVector3Array()            # particle rest positions (hooks first)
var _bone_of_particle := PackedInt32Array()   # particle index → bone index
var _tris := 0
var _rng_state := 5
var _textures: Array[ImageTexture] = []


## The rig from a NetSim layout: NetRoot, Hook_0…11, then Knot_k_i.
func build_rig(layout: Dictionary) -> void:
	_layout = layout
	_rng_state = 5
	_tris = 0
	_textures = []
	var hooks: PackedVector3Array = layout["hooks"]
	var knots: PackedVector3Array = layout["knots"]
	var n_hooks := hooks.size()
	var n_knots := knots.size()
	skeleton = Skeleton3D.new()
	skeleton.name = "NetRoot"
	add_child(skeleton)
	_rest = PackedVector3Array()
	_rest.resize(n_hooks + n_knots)
	_bone_of_particle.resize(n_hooks + n_knots)
	var root := skeleton.add_bone("NetRoot")
	skeleton.set_bone_rest(root, Transform3D.IDENTITY)
	for i in n_hooks:
		_bone_of_particle[i] = _add_bone("Hook_%d" % i, hooks[i])
		_rest[i] = hooks[i]
	var cols: int = NetSim.COLS
	for p in n_knots:
		var k := p / cols
		var i := p % cols
		_bone_of_particle[n_hooks + p] = _add_bone("Knot_%d_%d" % [k, i], knots[p])
		_rest[n_hooks + p] = knots[p]
	skin = Skin.new()
	for b in skeleton.get_bone_count():
		skin.add_bind(b, skeleton.get_bone_rest(b).affine_inverse())


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


## Skinned surfaces on the rig (a link multimesh is not one).
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


## The design's seeded LCG, so the jitter and speckle are the same every build.
func _rnd() -> float:
	_rng_state = (_rng_state * 16807) % 2147483647
	return float(_rng_state) / 2147483647.0


## A SIDES-sided tube along a polyline, flat shaded, UV u along (× uvx), v
## around; vertex weights lerp bone_a → bone_b along the length.
func _tube(mb: _MeshBuilder, pts: Array[Vector3], r: float, uvx: float, bone_a: int, bone_b: int, sides := 5, closed := false) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings: Array[PackedVector3Array] = []
	var normal := Vector3.ZERO
	for j in n:
		var tangent: Vector3
		if closed:
			tangent = pts[(j + 1) % n] - pts[(j - 1 + n) % n]
		elif j == 0:
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
		for sd in sides:
			var a := float(sd) / float(sides) * TAU
			ring.push_back(pts[j] + (normal * cos(a) + binormal * sin(a)) * r)
		rings.push_back(ring)
	var segs := n if closed else n - 1
	for j in segs:
		var j1 := (j + 1) % n
		var u0 := float(j) / float(segs) * uvx
		var u1 := float(j + 1) / float(segs) * uvx
		var w0 := float(j) / float(segs)
		var w1 := float(j + 1) / float(segs)
		for sd in sides:
			var s1 := (sd + 1) % sides
			var v0 := float(sd) / float(sides)
			var v1 := float(sd + 1) / float(sides)
			var a0 := rings[j][sd]
			var a1 := rings[j][s1]
			var b0 := rings[j1][sd]
			var b1 := rings[j1][s1]
			mb.tri([a0, b0, b1], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)],
				[bone_a, bone_b], [w0, w1, w1])
			mb.tri([a0, b1, a1], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)],
				[bone_a, bone_b], [w0, w1, w0])
	_tris += segs * sides * 2


func _add_surface(name_: String, mb: _MeshBuilder, mat: Material) -> MeshInstance3D:
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
	# The bones move the pieces well past the rest bounds in a swish.
	mi.extra_cull_margin = 0.5
	return mi


func _material(tex: Texture2D, roughness := 1.0, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = roughness
	m.metallic = metallic
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	return m


func _blank(base: Color) -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	img.fill(base)
	return img


func _keep(img: Image) -> ImageTexture:
	var tex := ImageTexture.create_from_image(img)
	_textures.push_back(tex)
	return tex


## The design's cotton twist: a diagonal dark stripe every 8 texels, a
## light one between, ten seeded speckles. [base, dark, light].
func twist_texture(colors: Array) -> ImageTexture:
	var dark := Color.html(colors[1])
	var light := Color.html(colors[2])
	var img := _blank(Color.html(colors[0]))
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var k := (x + y) % 8
			if k < 2:
				img.set_pixel(x, y, dark)
			elif k == 4:
				img.set_pixel(x, y, light)
	for _i in 10:
		var c := dark if _rnd() < 0.5 else light
		img.set_pixel(int(floor(_rnd() * TEX_SIZE)), int(floor(_rnd() * TEX_SIZE)), c)
	return _keep(img)


## The design's galvanised steel: a light band and a dark band every 8
## rows, fourteen seeded speckles, a third of them rust. [base, dark, light, rust].
func steel_texture(colors: Array) -> ImageTexture:
	var dark := Color.html(colors[1])
	var light := Color.html(colors[2])
	var rust := Color.html(colors[3])
	var img := _blank(Color.html(colors[0]))
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			if y % 8 < 2:
				img.set_pixel(x, y, light)
			elif y % 8 > 5:
				img.set_pixel(x, y, dark)
	for _i in 14:
		var c: Color
		if _rnd() < 0.35:
			c = rust
		else:
			c = dark if _rnd() < 0.5 else light
		img.set_pixel(int(floor(_rnd() * TEX_SIZE)), int(floor(_rnd() * TEX_SIZE)), c)
	return _keep(img)


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
