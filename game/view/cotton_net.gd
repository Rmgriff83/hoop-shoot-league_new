class_name CottonNet
extends NetRig
## The nylon net's body (2026-10-14, docs/BLENDER_101.md §28): Ross's design
## model (26a) built in Godot. Twelve continuous cords skinned to the rig —
## a bone per knot (84, driven by NetSim) and a pinned bone per hook (12,
## under the rim tube) — in three skinned meshes: the cords (5-sided tubes
## blending between the two bones they join), the knots (a flattened
## octahedron rigid on its bone) and the frayed tails under the bottom ring.
## Nothing is rebuilt per frame: sync() moves the bones.

const CORD_R := 0.004
const KNOT_R := 0.0085
const LW := 0.009              # loop half-width (m): the two halves spread this far
const SAG := 0.0015            # a diagonal's middle hangs this far under its chord
const DIAG_SEGS := 4
const LOOP_SEGS := 6
const CORD_COLORS := ["#EDE6D4", "#B9AE96", "#FFFBF0"]
const KNOT_COLORS := ["#DDD3BC", "#A99D84", "#F4EEDD"]


## Build the rig and the three meshes from NetSim.cotton_layout().
func build(layout: Dictionary) -> void:
	build_rig(layout)
	var knots: PackedVector3Array = layout["knots"]
	var n_hooks: int = (layout["hooks"] as PackedVector3Array).size()
	var cols: int = NetSim.COLS
	var rows: int = int(layout.get("rows", NetSim.COTTON_ROWS))
	var cord_mat := _material(twist_texture(CORD_COLORS))
	var knot_mat := _material(twist_texture(KNOT_COLORS))

	# Net_Cords: per cord the diagonals + the two loop halves.
	var cords := _MeshBuilder.new()
	for c in layout["cords"]:
		var left: Array = c["left"]
		var right: Array = c["right"]
		for k in rows:
			_diagonal(cords, int(left[k]), int(left[k + 1]))
			_diagonal(cords, int(right[k]), int(right[k + 1]))
		_loop_half(cords, int(c["k0"]), int(c["hook"]), -1.0)
		_loop_half(cords, int(c["k0"]), int(c["hook"]), 1.0)
	_add_surface("Net_Cords", cords, cord_mat)

	# Net_Knots: a blob at every crossing, rigid on its bone.
	var blobs := _MeshBuilder.new()
	for p in knots.size():
		var k := p / cols
		var pos := knots[p]
		var r := KNOT_R * (1.05 if k == 0 else 1.0)
		var turn := atan2(pos.z, pos.x) + _rnd() * 0.6
		_octahedron(blobs, pos, r, turn, _bone_of_particle[n_hooks + p])
	_add_surface("Net_Knots", blobs, knot_mat)

	# Net_Tails: two frayed ends under each bottom knot.
	var tails := _MeshBuilder.new()
	for p in layout["bottom"]:
		var pos := _rest[int(p)]
		var f := _frame(pos)
		var f_out: Vector3 = f["out"]
		var f_tan: Vector3 = f["tan"]
		for s in [-1.0, 1.0]:
			var end: Vector3 = pos + Vector3(0.0, -0.02 - _rnd() * 0.006, 0.0) + f_out * 0.004 + f_tan * (s * 0.006)
			var bone := _bone_of_particle[int(p)]
			_tube(tails, [pos, pos.lerp(end, 0.5), end], CORD_R * 0.85, 1.0, bone, bone)
	_add_surface("Net_Tails", tails, cord_mat)


## A diagonal piece between two knots: a quadratic bezier sagging SAG under
## its chord, skinned from bone A at the start to bone B at the end.
func _diagonal(mb: _MeshBuilder, a: int, b: int) -> void:
	var pa := _rest[a]
	var pb := _rest[b]
	var mid := pa.lerp(pb, 0.5) + Vector3(0.0, -SAG, 0.0)
	var pts: Array[Vector3] = []
	for j in DIAG_SEGS + 1:
		var u := float(j) / float(DIAG_SEGS)
		pts.push_back(pa.lerp(mid, u).lerp(mid.lerp(pb, u), u))
	_tube(mb, pts, CORD_R, 2.0, _bone_of_particle[a], _bone_of_particle[b])


## One half of the hook loop: a cubic bezier from the top knot up and round
## to the hook, spread sideways by s × LW so the two halves make a loop.
func _loop_half(mb: _MeshBuilder, k0: int, hook: int, s: float) -> void:
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
	_tube(mb, pts, CORD_R, 3.0, _bone_of_particle[k0], _bone_of_particle[hook])


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
