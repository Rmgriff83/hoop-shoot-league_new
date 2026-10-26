class_name WoolNet
extends CottonNet
## The hand-knitted wool net (docs/BLENDER_101.md §31, Ross's design 26b):
## the cotton net's twelve cords as thick knitted i-cord (~14 mm), each cord
## its own yarn colour (a vertex colour tinting a grey V-stitch knit
## texture), the knots a little uneven as if tied by hand, and both yarns
## running on past every bottom knot as long tails that swing on their own
## free Tail_i bones (particles with a spring to their knot).

const W_CORD_R := 0.0068
const W_KNOT_R := 0.0115
const TAIL_MIN := 0.04
const TAIL_VAR := 0.08
## One yarn per cord, from the reference photo.
const YARN := ["#FF4A1C", "#A8E070", "#F2F1EC", "#A9C8EC", "#9CCBB6", "#FFE01A",
	"#1FA6B8", "#F06A8C", "#2E5FD0", "#1F7A3A", "#9C98BC", "#C9E85A"]


## The cotton layout, hand-tied: rings 1+ jittered a little (seeded, so
## every build is the same net), then twelve Tail_i particles hanging
## 40–120 mm under the bottom knots on a spring of that length.
static func layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	return knitted_layout(rim_r, tube_r, 0.07, 0.06, 0.012, TAIL_MIN, TAIL_VAR)


## The knitted family's layout: the cotton rings 1+ jittered by ± half of
## `ang_j` (rad), `rad_j` (fraction) and `y_j` (m), plus the Tail_i
## particles of `tail_min + rnd × tail_var` under the bottom knots.
static func knitted_layout(rim_r: float, tube_r: float, ang_j: float, rad_j: float, y_j: float, tail_min: float, tail_var: float) -> Dictionary:
	var lay := NetSim.cotton_layout(rim_r, tube_r)
	var cols: int = NetSim.COLS
	var rows: int = int(lay["rows"])
	var knots: PackedVector3Array = lay["knots"]
	var hooks: PackedVector3Array = lay["hooks"]
	var seed := 5
	var rnd := func() -> float:
		seed = (seed * 16807) % 2147483647
		return float(seed) / 2147483647.0
	var names := PackedStringArray()
	for k in rows + 1:
		for i in cols:
			names.push_back("Knot_%d_%d" % [k, i])
			if k == 0:
				continue
			var p := knots[k * cols + i]
			var r := Vector2(p.x, p.z).length()
			var a: float = atan2(p.z, p.x) + (rnd.call() - 0.5) * ang_j
			var rr: float = r * (1.0 + (rnd.call() - 0.5) * rad_j)
			var y: float = p.y + (rnd.call() - 0.5) * y_j
			knots[k * cols + i] = Vector3(rr * cos(a), y, rr * sin(a))
	# Springs keep their pairs; their rest lengths follow the jittered knots.
	var at := func(idx: int) -> Vector3:
		return hooks[idx] if idx < cols else knots[idx - cols]
	var springs: Array = []
	for sp in lay["springs"]:
		springs.push_back([int(sp[0]), int(sp[1]), (at.call(int(sp[0])) as Vector3).distance_to(at.call(int(sp[1])))])
	# The tails.
	var tails: Array = []
	var bottom: Array = Array(lay["bottom"]).duplicate()
	var cords: Array = lay["cords"]
	for i in cols:
		var ib: int = int(lay["bottom"][i])
		var p := knots[ib - cols]
		var ang := atan2(p.z, p.x)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var len: float = tail_min + rnd.call() * tail_var
		var it := cols + knots.size()
		knots.push_back(p + Vector3(0.0, -len, 0.0) - out * 0.006)
		names.push_back("Tail_%d" % i)
		springs.push_back([ib, it, len])
		bottom.push_back(it)
		# The other yarn through this knot: the cord whose LEFT diagonal ends here.
		var left_cord := i
		for c in cords.size():
			if int((cords[c]["left"] as Array)[rows]) == ib:
				left_cord = c
				break
		tails.push_back({"knot": ib, "tail": it, "len": len, "right_cord": i, "left_cord": left_cord})
	lay["knots"] = knots
	lay["springs"] = springs
	lay["bottom"] = bottom
	lay["knot_names"] = names
	lay["tails"] = tails
	return lay


func _cord_r() -> float:
	return W_CORD_R


func _knot_r() -> float:
	return W_KNOT_R


func _knot_y_scale() -> float:
	return 1.15


func _materials() -> Array:
	var cord := _material(knit_texture(), 1.0, 0.0, true)
	var knot := _material(knit_texture(), 1.0, 0.0, true)
	var kb := _knot_brightness()
	knot.albedo_color = Color(kb, kb, kb)
	return [cord, knot]


## The knots' brightness over the cords'.
func _knot_brightness() -> float:
	return 0.88


## The twelve yarns, one per cord (a colour variant overrides this:
## WoolOceanNet, WoolEmberNet — Ross's 26e / 26f, 2026-10-25).
func _yarn() -> Array:
	return YARN


func _cord_color(i: int) -> Color:
	var y := _yarn()
	return Color.html(y[posmod(i, y.size())])


func _knot_color(k: int, i: int) -> Color:
	var y := _yarn()
	return Color.html(y[posmod(i + (k % 2) * 7, y.size())])


func _uv_x_diag() -> float:
	return 3.0


func _uv_x_loop() -> float:
	return 4.0


## Both yarns run on past each bottom knot to its Tail bone: two tubes
## skinned knot → tail, so they swing with the sim.
func _build_tails(mb: _MeshBuilder, lay: Dictionary) -> void:
	for t in lay.get("tails", []):
		var ib: int = int(t["knot"])
		var it: int = int(t["tail"])
		var len: float = float(t["len"])
		var p := _rest[ib]
		var f := _frame(p)
		var f_tan: Vector3 = f["tan"]
		var end0 := _rest[it]
		for pair in [[-1.0, int(t["right_cord"])], [1.0, int(t["left_cord"])]]:
			var s: float = pair[0]
			var color := _tail_color(int(pair[1]))
			var end: Vector3 = end0 + f_tan * (s * 0.005) + Vector3(0.0, s * len * 0.12, 0.0)
			var mid: Vector3 = p.lerp(end, 0.5) + f_tan * (s * 0.004)
			var pts: Array[Vector3] = []
			for j in 6:
				var u := float(j) / 5.0
				pts.push_back(p.lerp(mid, u).lerp(mid.lerp(end, u), u))
			_tube(mb, pts, _cord_r() * 0.9, 3.0, _bone_of_particle[ib], _bone_of_particle[it], 5, false, color)
