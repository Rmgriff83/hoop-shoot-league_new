class_name CottonNet
extends NetRig
## The nylon net's body (2026-10-14, docs/BLENDER_101.md §28): Ross's design
## model (26a) built in Godot. Twelve continuous cords skinned to the rig —
## a bone per knot (84, driven by NetSim) and a pinned bone per hook (12,
## under the rim tube) — in three skinned meshes: the cords (5-sided tubes
## blending between the two bones they join), the knots (a flattened
## octahedron rigid on its bone) and the frayed tails under the bottom ring.
## Nothing is rebuilt per frame: sync() moves the bones.
##
## Also the base of the other cord styles (§31 wool): a subclass supplies
## its layout(), cord and knot sizes, materials, colours and tails.

const CORD_R := 0.004
const KNOT_R := 0.0085
const LW := 0.009              # loop half-width (m): the two halves spread this far
const SAG := 0.0015            # a diagonal's middle hangs this far under its chord
const DIAG_SEGS := 4
const LOOP_SEGS := 6
const CORD_COLORS := ["#EDE6D4", "#B9AE96", "#FFFBF0"]
const KNOT_COLORS := ["#DDD3BC", "#A99D84", "#F4EEDD"]


## The style's rest layout (NetSim.cotton_layout for the stock cotton).
static func layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	return NetSim.cotton_layout(rim_r, tube_r)


## Build the rig and the three meshes from layout().
func build(lay: Dictionary) -> void:
	build_rig(lay)
	var knots: PackedVector3Array = lay["knots"]
	var n_hooks: int = (lay["hooks"] as PackedVector3Array).size()
	var cols: int = NetSim.COLS
	var rows: int = int(lay.get("rows", NetSim.COTTON_ROWS))
	var mats := _materials()
	var cord_mat: Material = mats[0]
	var knot_mat: Material = mats[1]

	# Net_Cords: per cord the diagonals + the two loop halves.
	var cords := _MeshBuilder.new()
	var ci := 0
	for c in lay["cords"]:
		var left: Array = c["left"]
		var right: Array = c["right"]
		var color := _cord_color(ci)
		for k in rows:
			_diagonal(cords, int(left[k]), int(left[k + 1]), color)
			_diagonal(cords, int(right[k]), int(right[k + 1]), color)
		_loop_half(cords, int(c["k0"]), int(c["hook"]), -1.0, color)
		_loop_half(cords, int(c["k0"]), int(c["hook"]), 1.0, color)
		ci += 1
	_add_surface("Net_Cords", cords, cord_mat)

	# Net_Knots: a blob at every crossing, rigid on its bone.
	var blobs := _MeshBuilder.new()
	for p in (rows + 1) * cols:
		var k := p / cols
		var i := p % cols
		var pos := knots[p]
		var r := _knot_r() * (1.05 if k == 0 else 1.0)
		var turn := atan2(pos.z, pos.x) + _rnd() * 0.6
		_octahedron(blobs, pos, r, turn, _bone_of_particle[n_hooks + p], _knot_color(k, i))
	_add_surface("Net_Knots", blobs, knot_mat)

	# Net_Tails: what runs on past the bottom knots.
	var tails := _MeshBuilder.new()
	_build_tails(tails, lay)
	_add_surface("Net_Tails", tails, cord_mat)


# ---- The style's parts (overridden by WoolNet) ---------------------------------


func _cord_r() -> float:
	return CORD_R


func _knot_r() -> float:
	return KNOT_R


## The knot blob's height over its radius (cotton: squashed).
func _knot_y_scale() -> float:
	return 0.8


## [cord material, knot material].
func _materials() -> Array:
	return [_material(twist_texture(CORD_COLORS)), _material(twist_texture(KNOT_COLORS))]


## Vertex colour of cord i (white = the texture alone).
func _cord_color(_i: int) -> Color:
	return Color.WHITE


func _knot_color(_k: int, _i: int) -> Color:
	return Color.WHITE


## Texture repeats along a diagonal piece / a loop half.
func _uv_x_diag() -> float:
	return 2.0


func _uv_x_loop() -> float:
	return 3.0


## Cotton: two short frayed stubs under each bottom knot, rigid on it.
func _build_tails(mb: _MeshBuilder, lay: Dictionary) -> void:
	for p in lay["bottom"]:
		var pos := _rest[int(p)]
		var f := _frame(pos)
		var f_out: Vector3 = f["out"]
		var f_tan: Vector3 = f["tan"]
		for s in [-1.0, 1.0]:
			var end: Vector3 = pos + Vector3(0.0, -0.02 - _rnd() * 0.006, 0.0) + f_out * 0.004 + f_tan * (s * 0.006)
			var bone := _bone_of_particle[int(p)]
			_tube(mb, [pos, pos.lerp(end, 0.5), end], _cord_r() * 0.85, 1.0, bone, bone)


# ---- Pieces ----------------------------------------------------------------------


## A diagonal piece between two knots: a quadratic bezier sagging SAG under
## its chord, skinned from bone A at the start to bone B at the end.
func _diagonal(mb: _MeshBuilder, a: int, b: int, color := Color.WHITE) -> void:
	var pa := _rest[a]
	var pb := _rest[b]
	var mid := pa.lerp(pb, 0.5) + Vector3(0.0, -SAG, 0.0)
	var pts: Array[Vector3] = []
	for j in DIAG_SEGS + 1:
		var u := float(j) / float(DIAG_SEGS)
		pts.push_back(pa.lerp(mid, u).lerp(mid.lerp(pb, u), u))
	_tube(mb, pts, _cord_r(), _uv_x_diag(), _bone_of_particle[a], _bone_of_particle[b], 5, false, color)


## One half of the hook loop: a cubic bezier from the top knot up and round
## to the hook, spread sideways by s × LW so the two halves make a loop.
func _loop_half(mb: _MeshBuilder, k0: int, hook: int, s: float, color := Color.WHITE) -> void:
	var p0 := _rest[k0]
	var p3 := _rest[hook]
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
	_tube(mb, pts, _cord_r(), _uv_x_loop(), _bone_of_particle[k0], _bone_of_particle[hook], 5, false, color)


## A knot blob: an octahedron of radius r scaled in y, turned about y,
## rigid on its bone.
func _octahedron(mb: _MeshBuilder, at: Vector3, r: float, turn: float, bone: int, color := Color.WHITE) -> void:
	var rot := Basis(Vector3.UP, turn)
	var ys := _knot_y_scale()
	var px := at + rot * Vector3(r, 0.0, 0.0)
	var nx := at + rot * Vector3(-r, 0.0, 0.0)
	var py := at + Vector3(0.0, r * ys, 0.0)
	var ny := at + Vector3(0.0, -r * ys, 0.0)
	var pz := at + rot * Vector3(0.0, 0.0, r)
	var nz := at + rot * Vector3(0.0, 0.0, -r)
	var uv := [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.25, 0.5)]
	for face in [[px, pz, py], [pz, nx, py], [nx, nz, py], [nz, px, py],
			[pz, px, ny], [nx, pz, ny], [nz, nx, ny], [px, nz, ny]]:
		mb.tri(face, uv, [bone, bone], [0.0, 0.0, 0.0], color)
	_tris += 8
