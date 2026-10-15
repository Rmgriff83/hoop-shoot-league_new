class_name LadderNet
extends ChainNet
## The ladder chain net (docs/BLENDER_101.md §30, Ross's design 27b): twelve
## chains drop straight down from the S-hooks, tied together by three
## horizontal hoop chains at 30 %, 58 % and 86 % of the length with a steel
## ring at every crossing; below the bottom hoop each drop hangs free as a
## short tail. The hoop chains carry 4 % slack so they droop a little
## between drops. Worn galvanised steel: dull mottled zinc, bright scuffs,
## dark pits, a few rust blooms.

const ROWS := 4
const T := [0.0, 0.3, 0.58, 0.86, 1.0]   # row heights as a fraction of the drop
const HOOP_SLACK := 1.04
const L_LINK_COLORS := ["#979DA3", "#666C72", "#C9CED3", "#8A4E2A"]   # GalvSteelWorn
const L_RING_COLORS := ["#80868D", "#565B61", "#B4BAC0", "#7A4426"]   # GalvSteelWornDark


## Rows 0–4 × 12 (0 under the hook, 1–3 the hoop crossings, 4 the free tail
## ends), no half-step turn. Springs: hook→Knot_0, the drops, and the three
## hoop chains (rest × 1.04).
static func layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	var cols: int = NetSim.COLS
	var hook_y := -(tube_r + NetSim.CHAIN_HOOK_DROP)
	var ring0_y := hook_y - NetSim.CHAIN_HOOK_HH
	var knots := PackedVector3Array()
	var hooks := PackedVector3Array()
	for i in cols:
		var a := float(i) / float(cols) * TAU
		hooks.push_back(Vector3(rim_r * cos(a), hook_y, rim_r * sin(a)))
	for k in ROWS + 1:
		var t: float = T[k]
		var r := NetSim.cotton_ring_radius(minf(t, 0.86) / 0.86 * 0.78, rim_r)
		var y := ring0_y + (-NetSim.NET_LEN - ring0_y) * t
		for i in cols:
			var a := float(i) / float(cols) * TAU
			knots.push_back(Vector3(r * cos(a), y, r * sin(a)))
	var knot_idx := func(k: int, i: int) -> int:
		return cols + k * cols + posmod(i, cols)
	var at := func(idx: int) -> Vector3:
		return hooks[idx] if idx < cols else knots[idx - cols]
	var springs: Array = []
	var add := func(a: int, b: int, slack: float) -> void:
		springs.push_back([a, b, (at.call(a) as Vector3).distance_to(at.call(b)) * slack])
	var cords: Array = []
	for i in cols:
		add.call(i, knot_idx.call(0, i), 1.0)
		for k in ROWS:
			add.call(knot_idx.call(k, i), knot_idx.call(k + 1, i), 1.0)
		cords.push_back({"hook": i, "k0": knot_idx.call(0, i)})
	var hoops: Array = []
	for k in range(1, ROWS):
		for i in cols:
			hoops.push_back(springs.size())
			add.call(knot_idx.call(k, i), knot_idx.call(k, i + 1), HOOP_SLACK)
	var bottom: Array = []
	for i in cols:
		bottom.push_back(knot_idx.call(ROWS, i))
	return {"knots": knots, "hooks": hooks, "springs": springs, "bottom": bottom, "cords": cords,
		"rows": ROWS, "hoop_springs": hoops}


func _materials() -> Array:
	return [_material(worn_steel_texture(L_LINK_COLORS), 0.78, 0.25), _material(worn_steel_texture(L_RING_COLORS), 0.78, 0.25)]


## Rings where the hoop chains cross the drops: rows 1–3.
func _ring_particles(lay: Dictionary) -> Array:
	var cols: int = NetSim.COLS
	var n_hooks: int = (lay["hooks"] as PackedVector3Array).size()
	var out: Array = []
	for k in range(1, ROWS):
		for i in cols:
			out.push_back(n_hooks + k * cols + i)
	return out
