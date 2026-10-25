class_name TatteredNet
extends CottonNet
## The worn-out park net (docs/BLENDER_101.md §32, Ross's design "Tattered
## Net Model" 26d, 2026-10-24): the cotton net's twelve cords, aged. Three
## hooks have torn off the rim (two side by side, one opposite), so that
## flank sags and pulls inward; twelve cord pieces have snapped, leaving
## holes and loose ends; strands still hang from the rim where hooks gave
## way; and the bottom is ragged, with uneven tails and a few long ones. The
## cord is a grimy grey-cream. Every loose strand hangs on its own free
## Tail_n particle (a spring of its length to its knot or hook), so it
## swings in the sim. Starts from the classic cotton defaults.

## The hooks that tore off: their loops are gone, their top knots hang free.
const BROKEN_HOOKS := [3, 4, 9]
## The snapped cord pieces: "<cord><L|R><ring>" — the diagonal of cord i's
## left / right run from ring k down to k + 1.
const BROKEN := ["2R3", "5L4", "7R4", "8L2", "10R5", "0L5", "4R5", "6L5", "11R3", "1L4", "3L1", "9R2"]
## The strands left on the rim: [hook, length, dx, dz].
const RIM_STRANDS := [[3, 0.22, 0.004, 0.0], [3, 0.15, -0.006, 0.004], [4, 0.26, 0.0, -0.004], [9, 0.18, 0.003, 0.003]]
## The sag around a torn hook: depth (m), pull-in (fraction), the fade down the net.
const SAG_DEPTH := 0.09
const SAG_PULL := 0.2
const SAG_FADE := 0.4
const SAG_SPREAD := 1.6
const CORD_COLORS_T := ["#CFC6B0", "#8A8070", "#E6DFCC"]
const KNOT_COLORS_T := ["#B8AE98", "#7E7464", "#D6CDB8"]


## The cotton layout, aged (seeded, so every build is the same net):
## the rings sag and pull in around the torn hooks, rings 1+ are jittered a
## little, the broken pieces lose their springs, and the loose strands hang
## as Tail_n particles. Adds `broken` (piece key → true), `broken_hooks`,
## `tails` ([{knot, tail, len, kind}]) and `knot_names` to the layout.
static func layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	var lay := NetSim.cotton_layout(rim_r, tube_r)
	var cols: int = NetSim.COLS
	var rows: int = int(lay["rows"])
	var knots: PackedVector3Array = lay["knots"]
	var hooks: PackedVector3Array = lay["hooks"]
	var seed: Array = [5]   # the LCG's state, by reference (a closure would copy it)
	# The sag: each torn hook pulls the knots around it down and inward,
	# strongest at the rim, fading toward the bottom.
	var names := PackedStringArray()
	for k in rows + 1:
		for i in cols:
			names.push_back("Knot_%d_%d" % [k, i])
			var pos := float(i) + float(k) * 0.5
			var w := 0.0
			for hk in BROKEN_HOOKS:
				var d := _cdist(pos, float(hk) + 0.5, cols)
				var s := 0.55 if int(hk) == 9 else 1.0
				w = maxf(w, s * exp(-d * d / SAG_SPREAD))
			var f := 1.0 - SAG_FADE * float(k) / float(rows)
			var p := knots[k * cols + i]
			p.y -= SAG_DEPTH * w * f
			p.x *= 1.0 - SAG_PULL * w * f
			p.z *= 1.0 - SAG_PULL * w * f
			if k > 0:
				p.x += (_lcg(seed) - 0.5) * 0.01
				p.z += (_lcg(seed) - 0.5) * 0.01
				p.y += (_lcg(seed) - 0.5) * 0.012
			knots[k * cols + i] = p
	# The springs: the cotton pairs at their new lengths, minus the snapped
	# pieces and the torn hooks' loops.
	var broken := {}
	for key in BROKEN:
		broken[str(key)] = true
	var gone := {}
	var cords: Array = lay["cords"]
	for c in cords.size():
		var left: Array = cords[c]["left"]
		var right: Array = cords[c]["right"]
		for k in rows:
			if broken.has("%dL%d" % [c, k]):
				gone[_pair(int(left[k]), int(left[k + 1]))] = true
			if broken.has("%dR%d" % [c, k]):
				gone[_pair(int(right[k]), int(right[k + 1]))] = true
		if BROKEN_HOOKS.has(c):
			gone[_pair(int(cords[c]["k0"]), int(cords[c]["hook"]))] = true
	var springs: Array = []
	for sp in lay["springs"]:
		var a := int(sp[0])
		var b := int(sp[1])
		if gone.has(_pair(a, b)):
			continue
		springs.push_back([a, b, _at(hooks, knots, cols, a).distance_to(_at(hooks, knots, cols, b))])
	# The loose strands: [parent particle, length, dx, dz, kind] — the
	# snapped ends under the upper knot of each broken piece, the strands
	# left on the torn hooks, the ragged bottom.
	var strands: Array = []
	for key in BROKEN:
		var ks := str(key)
		var side := "L" if ks.contains("L") else "R"
		var parts: PackedStringArray = ks.split(side)
		var i := int(parts[0])
		var k := int(parts[1])
		var up := cols + k * cols + posmod(i - k if side == "L" else i, cols)
		strands.push_back([up, 0.04 + _lcg(seed) * 0.07, (_lcg(seed) - 0.5) * 0.02, (_lcg(seed) - 0.5) * 0.02, "snap"])
	for rs in RIM_STRANDS:
		strands.push_back([int(rs[0]), float(rs[1]), float(rs[2]), float(rs[3]), "rim"])
	for i in cols:
		var r := _lcg(seed)
		if r < 0.2:
			continue
		var len: float = (0.10 + _lcg(seed) * 0.05) if r > 0.85 else (0.02 + _lcg(seed) * 0.04)
		strands.push_back([int(lay["bottom"][i]), len, (_lcg(seed) - 0.5) * 0.012, (_lcg(seed) - 0.5) * 0.012, "bottom"])
	# Each strand: a free Tail_n particle on a spring of its length to its
	# knot or hook; they hang heavy like the bottom ring.
	var tails: Array = []
	var bottom: Array = Array(lay["bottom"]).duplicate()
	for st in strands:
		var parent := int(st[0])
		var len := float(st[1])
		var from := _at(hooks, knots, cols, parent)
		var end := from + Vector3(float(st[2]), -len, float(st[3]))
		var it := cols + knots.size()
		knots.push_back(end)
		names.push_back("Tail_%d" % tails.size())
		springs.push_back([parent, it, from.distance_to(end)])
		bottom.push_back(it)
		tails.push_back({"knot": parent, "tail": it, "len": len, "kind": str(st[4])})
	lay["knots"] = knots
	lay["springs"] = springs
	lay["bottom"] = bottom
	lay["knot_names"] = names
	lay["tails"] = tails
	lay["broken"] = broken
	lay["broken_hooks"] = BROKEN_HOOKS.duplicate()
	return lay


## The particle at `idx` (hooks first, then knots).
static func _at(hooks: PackedVector3Array, knots: PackedVector3Array, cols: int, idx: int) -> Vector3:
	return hooks[idx] if idx < cols else knots[idx - cols]


static func _pair(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


## The seeded generator (the design's LCG; `st` = [state], by reference).
static func _lcg(st: Array) -> float:
	st[0] = (int(st[0]) * 16807) % 2147483647
	return float(st[0]) / 2147483647.0


## Distance around the ring between two cord positions (in knot steps).
static func _cdist(a: float, b: float, cols: int) -> float:
	var d := fmod(absf(a - b), float(cols))
	return minf(d, float(cols) - d)


## Grimy grey-cream cord and darker knots; no tint, no glow.
func _materials() -> Array:
	return [_material(twist_texture(CORD_COLORS_T), 1.0, 0.0, false), _material(twist_texture(KNOT_COLORS_T), 1.0, 0.0, false)]


## Every loose strand: one thin tube from its knot (or hook) to its Tail
## bone, bowed a little sideways, so it swings with the sim.
func _build_tails(mb: _MeshBuilder, lay: Dictionary) -> void:
	for t in lay.get("tails", []):
		var ia := int(t["knot"])
		var ib := int(t["tail"])
		var len := float(t["len"])
		var a := _rest[ia]
		var b := _rest[ib]
		var mid := a.lerp(b, 0.5) + Vector3((_rnd() - 0.5) * 0.012, 0.0, (_rnd() - 0.5) * 0.012)
		var segs := 6 if len > 0.1 else 3
		var pts: Array[Vector3] = []
		for j in segs + 1:
			var u := float(j) / float(segs)
			pts.push_back(a.lerp(mid, u).lerp(mid.lerp(b, u), u))
		_tube(mb, pts, _cord_r() * 0.85, 2.0, _bone_of_particle[ia], _bone_of_particle[ib], 5, false, _tail_color(0))
