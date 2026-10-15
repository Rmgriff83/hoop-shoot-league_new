class_name JackNet
extends ChainNet
## The jack-chain net (docs/BLENDER_101.md §30, Ross's design 27c): twelve
## chains of thin twisted figure-8 links in a stretched-hexagon mesh, five
## rows deep. At every junction two neighbouring chains run together down a
## short shared vertical stretch (30 mm, Knot_k_i → Join_k_i) and split off
## on the diagonals, so each cell is a tall hexagon. No junction rings —
## where two chains cross they share a link. Long open S-hooks, bright zinc.

const ROWS := 5
const SEG := 0.03                 # the shared vertical run at each junction
const J_LINK_LEN := 0.022
const J_LINK_W := 0.010
const J_LINK_WIRE := 0.0016
const J_PITCH := 0.0165           # each figure-8's end loop through the next
const J_HOOK_DROP := 0.046        # the long S-hook's top curl (+0.026, r 8 mm) on the rim's NetHook wire
const J_HOOK_HH := 0.025          # ring 0 (the hexagons' top) this far under the hooks
const J_LINK_COLORS := ["#C3C9CF", "#808890", "#F4F7FA", "#A7AEB5"]   # ZincBright
const J_HOOK_COLORS := ["#AEB4BB", "#737A82", "#E6EAEE", "#969DA5"]   # ZincHook


## Bones per column and row: Knot_k_i (top of the shared run, k = 0…5) then
## Join_k_i (its bottom, k = 0…4). Particles: hooks first, then per row the
## 12 knots and the 12 joins. Springs: hook→Knot_0, Knot_k→Join_k, and
## Join_k→Knot_(k+1)_i / Knot_(k+1)_(i−1).
static func layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	var cols: int = NetSim.COLS
	var hook_y := -(tube_r + J_HOOK_DROP)
	var ring0_y := hook_y - J_HOOK_HH
	var knots := PackedVector3Array()
	var names := PackedStringArray()
	var hooks := PackedVector3Array()
	var knot_idx := {}   # [k, i] → particle index
	var join_idx := {}
	for i in cols:
		var a := float(i) / float(cols) * TAU
		hooks.push_back(Vector3(rim_r * cos(a), hook_y, rim_r * sin(a)))
	for k in ROWS + 1:
		var t := float(k) / float(ROWS)
		var r := NetSim.cotton_ring_radius(t, rim_r)
		var y := ring0_y + (-NetSim.NET_LEN - ring0_y) * t
		var lift := SEG * 0.5 if k < ROWS else 0.0
		for i in cols:
			var a := (float(i) + float(k) * 0.5) / float(cols) * TAU
			knot_idx[Vector2i(k, i)] = cols + knots.size()
			knots.push_back(Vector3(r * cos(a), y + lift, r * sin(a)))
			names.push_back("Knot_%d_%d" % [k, i])
		if k < ROWS:
			for i in cols:
				var a := (float(i) + float(k) * 0.5) / float(cols) * TAU
				join_idx[Vector2i(k, i)] = cols + knots.size()
				knots.push_back(Vector3(r * cos(a), y - SEG * 0.5, r * sin(a)))
				names.push_back("Join_%d_%d" % [k, i])
	var at := func(idx: int) -> Vector3:
		return hooks[idx] if idx < cols else knots[idx - cols]
	var springs: Array = []
	var add := func(a: int, b: int) -> void:
		springs.push_back([a, b, (at.call(a) as Vector3).distance_to(at.call(b))])
	for i in cols:
		add.call(i, knot_idx[Vector2i(0, i)])
	for k in ROWS:
		for i in cols:
			var j: int = join_idx[Vector2i(k, i)]
			add.call(knot_idx[Vector2i(k, i)], j)
			add.call(j, knot_idx[Vector2i(k + 1, i)])
			add.call(j, knot_idx[Vector2i(k + 1, posmod(i - 1, cols))])
	var bottom: Array = []
	for i in cols:
		bottom.push_back(knot_idx[Vector2i(ROWS, i)])
	var cords: Array = []
	for i in cols:
		cords.push_back({"hook": i, "k0": knot_idx[Vector2i(0, i)]})
	return {"knots": knots, "hooks": hooks, "springs": springs, "bottom": bottom, "cords": cords,
		"knot_names": names, "rows": ROWS, "joins": join_idx.values()}


func _pitch() -> float:
	return J_PITCH


func _materials() -> Array:
	return [_material(steel_texture(J_LINK_COLORS), 0.5, 0.35), _material(steel_texture(J_HOOK_COLORS), 0.5, 0.35)]


## No junction rings: the crossings share a link.
func _ring_particles(_lay: Dictionary) -> Array:
	return []


## The long open S-hook (~38 mm): the top curl hangs over the rim's hook
## (inward), the bottom curl carries the chain's first link.
func _hook_points(p: Vector3, f_out: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for s in 11:
		var a := PI * float(s) / 10.0 * 1.15
		pts.push_back(p + f_out * (-0.008 + 0.008 * cos(a)) + Vector3(0.0, 0.026 + 0.008 * sin(a), 0.0))
	pts.push_back(p + Vector3(0.0, 0.016, 0.0))
	pts.push_back(p + f_out * 0.002 + Vector3(0.0, 0.008, 0.0))
	for s in 11:
		var a := PI * float(s) / 10.0 * 1.15
		pts.push_back(p + f_out * (0.007 - 0.007 * cos(a)) + Vector3(0.0, 0.004 - 0.007 * sin(a), 0.0))
	return pts


func _hook_wire() -> float:
	return 0.0019


## A figure-8 jack link: two end loops joined by a single twist in the
## middle (the wire crosses over itself, offset in z so it never intersects).
func _link_mesh(mat: Material) -> ArrayMesh:
	var h := J_LINK_LEN * 0.5 - J_LINK_WIRE
	var w := J_LINK_W * 0.5 - J_LINK_WIRE
	var z := J_LINK_WIRE * 1.2
	var n := 16
	var path: Array[Vector3] = []
	for i in n:
		var t := float(i) / float(n) * TAU
		path.push_back(Vector3(w * sin(2.0 * t) * 1.15, h * cos(t), z * sin(t)))
	var tangents: Array[Vector3] = []
	for i in n:
		var tg := path[(i + 1) % n] - path[(i - 1 + n) % n]
		tangents.push_back(tg.normalized() if tg.length() > 1e-9 else Vector3.UP)
	return wire_loop_mesh(path, tangents, J_LINK_WIRE, 3, mat, 1.0)
