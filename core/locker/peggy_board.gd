class_name PeggyBoard
extends RefCounted
## PEGGY's peg board (docs/LOCKER.md): the headless physics of one drop.
## Board units, 1 u = 0.1 m on the cabinet model; origin at the slot floor's
## centre, +x right, +y up. A round puck is released at rest from the rail,
## falls through ten staggered rows of pegs, and lands in one of seven slots.
## Honest rigid-body contacts (push-out + restitution) with a small seeded
## per-hit jitter from DetRng, so the same seed always replays the same path
## while nearby seeds diverge. No nodes, no Vector3, no engine RNG.
##
## The numbers were measured (tools/peggy_ledger.gd): from the rail's centre
## the two edge slots take ~4-5 % each, the next pair ~9 %, the middle three
## ~22-30 %; at the rail's end-stop (AIM_MAX) the near edge rises to ~16 %.

const WALL_X := 3.5                      # inner faces of the side walls
const SLOTS := 7                         # slot i spans [-3.5 + i, -2.5 + i]
const SLOT_W := 1.0
const DIV_H := 1.2                       # divider height; tops are circles
const DIV_TOP_R := 0.08
const ROWS := 10
const ROW_DY := 0.8
const PEG_R := 0.12
const BUMP_R := 0.30                     # wall bumpers on every row (a scalloped wall, no V-pocket)
const PUCK_R := 0.25
const Y_TOP := DIV_H + 1.0 + ROWS * ROW_DY   # row 0's y (10.2)
const RELEASE_Y := Y_TOP + 1.2
const AIM_MAX := 1.0                     # rail half-travel (end-stops over the inner edges of the second slots)
const G := 98.0                          # 9.8 m/s² in board units
const E_PEG := 0.30
const E_WALL := 0.50
const JITTER_DEG := 4.0
const RELEASE_JITTER := 0.02
const DT := 1.0 / 240.0
const MAX_T := 6.0
const HIT_VN := 1.5                      # a contact is a "hit" (sound, flash) above this normal speed
const SAMPLE_EVERY := 4                  # path samples at 60 Hz
const STUCK_STEPS := 60

static var _pegs_cache: Array = []


## Every circle on the board, in a FIXED order the cabinet glb mirrors:
## row by row from the top, each row's left bumper, its pegs left to right,
## its right bumper; then the six divider tops. [{x, y, r, kind, row}].
static func pegs() -> Array:
	if not _pegs_cache.is_empty():
		return _pegs_cache
	var out := []
	for r in ROWS:
		var y := Y_TOP - r * ROW_DY
		out.push_back({"x": -WALL_X, "y": y, "r": BUMP_R, "kind": "bumper", "row": r})
		if r % 2 == 0:
			for k in 6:
				out.push_back({"x": -2.5 + k, "y": y, "r": PEG_R, "kind": "peg", "row": r})
		else:
			for k in 5:
				out.push_back({"x": -2.0 + k, "y": y, "r": PEG_R, "kind": "peg", "row": r})
		out.push_back({"x": WALL_X, "y": y, "r": BUMP_R, "kind": "bumper", "row": r})
	for k in SLOTS - 1:
		out.push_back({"x": -2.5 + k, "y": DIV_H, "r": DIV_TOP_R, "kind": "divider", "row": -1})
	_pegs_cache = out
	return out


static func slot_centre(i: int) -> float:
	return -3.0 + i


static func slot_of(x: float) -> int:
	return clampi(int(floor(x + WALL_X)), 0, SLOTS - 1)


static func clamp_aim(aim_x: float) -> float:
	return clampf(aim_x, -AIM_MAX, AIM_MAX)


## One drop. {path: [[x, y, t]...] at 60 Hz (+ the landing), hits: [[x, y, t,
## peg_index]...], slot, duration, landed}. every_step samples every physics
## step (tests use it to prove the puck never tunnels).
static func simulate(aim_x: float, seed_value: int, every_step := false) -> Dictionary:
	var rng := DetRng.new(seed_value)
	var circles := pegs()
	var x := clamp_aim(aim_x) + rng.randf_range(-RELEASE_JITTER, RELEASE_JITTER)
	var y := RELEASE_Y
	var vx := 0.0
	var vy := 0.0
	var t := 0.0
	var path := [[x, y, t]]
	var hits := []
	var landed := false
	var step := 0
	var slow := 0
	while t < MAX_T:
		vy -= G * DT
		x += vx * DT
		y += vy * DT
		t += DT
		step += 1
		# Circle contacts: only the rows near y (bucketed), plus the divider tops.
		var r0 := int(round((Y_TOP - y) / ROW_DY))
		for i in circles.size():
			var c: Dictionary = circles[i]
			var row := int(c["row"])
			if row >= 0 and absi(row - r0) > 1:
				continue
			if row < 0 and y > DIV_H + PUCK_R + 0.2:
				continue
			var px := float(c["x"])
			var py := float(c["y"])
			var rr := PUCK_R + float(c["r"])
			var dx := x - px
			var dy := y - py
			if dx * dx + dy * dy >= rr * rr:
				continue
			var d := maxf(sqrt(dx * dx + dy * dy), 1e-9)
			var nx := dx / d
			var ny := dy / d
			x = px + nx * rr
			y = py + ny * rr
			var vn := vx * nx + vy * ny
			if vn < 0.0:
				vx -= (1.0 + E_PEG) * vn * nx
				vy -= (1.0 + E_PEG) * vn * ny
				var a := deg_to_rad(rng.randf_range(-JITTER_DEG, JITTER_DEG))
				var ca := cos(a)
				var sa := sin(a)
				var rvx := vx * ca - vy * sa
				var rvy := vx * sa + vy * ca
				vx = rvx
				vy = rvy
				if -vn > HIT_VN:
					hits.push_back([x, y, t, i])
		# Walls.
		if x - PUCK_R < -WALL_X:
			x = -WALL_X + PUCK_R
			if vx < 0.0:
				vx = -E_WALL * vx
		if x + PUCK_R > WALL_X:
			x = WALL_X - PUCK_R
			if vx > 0.0:
				vx = -E_WALL * vx
		# Inside a slot: the divider sides.
		if y < DIV_H:
			var s := slot_of(x)
			var lo := -WALL_X + s + DIV_TOP_R
			var hi := -WALL_X + s + SLOT_W - DIV_TOP_R
			if s == 0:
				lo = -WALL_X
			if s == SLOTS - 1:
				hi = WALL_X
			if x - PUCK_R < lo:
				x = lo + PUCK_R
				vx = absf(vx) * E_WALL
			if x + PUCK_R > hi:
				x = hi - PUCK_R
				vx = -absf(vx) * E_WALL
		# Stuck guard (never triggers in the measured geometry; a safety net).
		if vx * vx + vy * vy < 0.09 and y > PUCK_R + 0.01:
			slow += 1
			if slow >= STUCK_STEPS:
				vx += (1.0 if x < 0.0 else -1.0) * rng.randf_range(1.0, 2.0)
				slow = 0
		else:
			slow = 0
		if every_step or step % SAMPLE_EVERY == 0:
			path.push_back([x, y, t])
		if y - PUCK_R <= 0.0:
			y = PUCK_R
			landed = true
			break
	if path.is_empty() or path[path.size() - 1][2] != t:
		path.push_back([x, y, t])
	return {"path": path, "hits": hits, "slot": slot_of(x), "duration": t, "landed": landed}


## Slot probabilities for an aim, from n seeded drops (sums to 1).
static func odds(aim_x: float, n := 400, seed_base := 1) -> PackedFloat64Array:
	var counts := PackedInt32Array()
	counts.resize(SLOTS)
	for i in n:
		var r := simulate(aim_x, seed_base * 1000003 + i)
		counts[int(r["slot"])] += 1
	var out := PackedFloat64Array()
	out.resize(SLOTS)
	for s in SLOTS:
		out[s] = float(counts[s]) / float(maxi(n, 1))
	return out


## {rarity: p} for a PeggyPrizes layout (7 rarity names) at this aim.
static func rarity_odds(aim_x: float, layout: Array, n := 400) -> Dictionary:
	return rarity_odds_from(odds(aim_x, n), layout)


static func rarity_odds_from(p: PackedFloat64Array, layout: Array) -> Dictionary:
	var out := {}
	for s in mini(layout.size(), p.size()):
		var k := str(layout[s])
		out[k] = float(out.get(k, 0.0)) + p[s]
	return out
