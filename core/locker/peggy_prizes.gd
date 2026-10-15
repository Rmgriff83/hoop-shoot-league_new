class_name PeggyPrizes
extends RefCounted
## What PEGGY pays (docs/LOCKER.md): the seven slot plates for a level, which
## unowned prize each one hides, and what a landing is worth. Pure over an
## Array of {id, rarity, kind} roster entries (kind "ball" | "net"; a
## missing kind is a ball) so tests need no resources; the game layer passes
## CosmeticLibrary's roster (the balls and the nets) and the save's owned
## ids, both kinds in one list.
##
## Rules: a drop costs DROP_COST tickets — tickets only ever buy plays
## (Ross, 2026-10-15): nothing is bought outright. Plates only ever hide
## prizes the player does not own. Outer plates are the rarest the level
## allows (epic from EPIC_LEVEL, legend from LEGEND_LEVEL). When a plate's
## rarity has no unowned ball left it PROMOTES to the next rarity up that
## still has one at this level, then falls back down. Plates prefer seven
## different balls, but once fewer remain the same ball sits on several
## plates (the last ball of all is on every plate), so the roster never
## stalls on a rare plate. THE NETS: while any net is unowned, one plate per
## drop — drawn by the seed — hides a net instead of a ball (the plate keeps
## its rarity dot; nets have no rarity scale of their own), and every plate
## that would otherwise be empty hides a net too. Only when nothing unowned
## is left at this level does a plate pay REFUND back.

const DROP_COST := 300
const REFUND := 150
const RARITIES := ["common", "rare", "epic", "legend"]
const EPIC_LEVEL := 3
const LEGEND_LEVEL := 5

const LAYOUT_LOW := ["rare", "common", "common", "common", "common", "common", "rare"]
const LAYOUT_MID := ["epic", "rare", "common", "common", "common", "rare", "epic"]
const LAYOUT_HIGH := ["legend", "epic", "rare", "common", "rare", "epic", "legend"]


static func rarity_index(rarity: String) -> int:
	return RARITIES.find(rarity)


## The level a rarity first appears at.
static func rarity_level(rarity: String) -> int:
	match rarity:
		"epic":
			return EPIC_LEVEL
		"legend":
			return LEGEND_LEVEL
	return 1


static func visible_rarities(level: int) -> Array:
	var out := []
	for r in RARITIES:
		if level >= rarity_level(str(r)):
			out.push_back(r)
	return out


static func top_rarity(level: int) -> String:
	var v := visible_rarities(level)
	return str(v[v.size() - 1])


## Seven plate rarities, outer = rarest.
static func layout(level: int) -> Array:
	if level >= LEGEND_LEVEL:
		return LAYOUT_HIGH.duplicate()
	if level >= EPIC_LEVEL:
		return LAYOUT_MID.duplicate()
	return LAYOUT_LOW.duplicate()


static func kind_of(entry: Dictionary) -> String:
	return str(entry.get("kind", "ball"))


## Ball ids of this rarity the player does not own (roster order).
static func unowned(rarity: String, owned_ids: Array, balls: Array) -> Array:
	var out := []
	for b in balls:
		if kind_of(b) == "ball" and str(b.get("rarity", "")) == rarity and not owned_ids.has(str(b["id"])):
			out.push_back(str(b["id"]))
	return out


## Net ids the player does not own (roster order).
static func unowned_nets(owned_ids: Array, roster: Array) -> Array:
	var out := []
	for b in roster:
		if kind_of(b) == "net" and not owned_ids.has(str(b["id"])):
			out.push_back(str(b["id"]))
	return out


## The rarity a plate of `slot_rarity` actually pays at this level: itself if
## it still has an unowned ball, else the next one up, else back down. "" if
## nothing is left.
static func effective_rarity(slot_rarity: String, level: int, owned_ids: Array, balls: Array) -> String:
	var visible := visible_rarities(level)
	var start := visible.find(slot_rarity)
	if start < 0:
		start = visible.size() - 1   # a plate rarer than the level allows pays the level's best
	var order := []
	for i in range(start, visible.size()):
		order.push_back(visible[i])
	for i in range(start - 1, -1, -1):
		order.push_back(visible[i])
	for r in order:
		if not unowned(str(r), owned_ids, balls).is_empty():
			return str(r)
	return ""


## One prize id for a plate, drawn from the unowned balls of its effective
## rarity, avoiding `exclude` (the ids already on other plates) while that
## leaves a choice. "" = nothing left at this level.
static func prize_for(slot_rarity: String, level: int, owned_ids: Array, balls: Array, rng: DetRng, exclude: Array = []) -> String:
	var r := effective_rarity(slot_rarity, level, owned_ids, balls)
	if r == "":
		return ""
	var all := unowned(r, owned_ids, balls)
	var pool := []
	for id in all:
		if not exclude.has(id):
			pool.push_back(id)
	if pool.is_empty():
		pool = all
	return str(rng.pick(pool))


## The seven plates: [{base, rarity, kind, id}] — base is the layout's
## rarity, rarity the one actually paid (after promotion; a net plate keeps
## its base), kind "ball" | "net", id "" for a refund plate. Balls are
## assigned rarest-first so the outer plates get first pick; then the net
## pass (one seeded plate, plus every empty one).
static func slots(level: int, owned_ids: Array, balls: Array, rng: DetRng) -> Array:
	var lay := layout(level)
	var order := range(lay.size())
	order.sort_custom(func(a, b): return rarity_index(str(lay[a])) > rarity_index(str(lay[b])))
	var out := []
	out.resize(lay.size())
	var exclude := []
	for s in order:
		var base := str(lay[s])
		var id := prize_for(base, level, owned_ids, balls, rng, exclude)
		var eff := ""
		if id != "":
			exclude.push_back(id)
			for b in balls:
				if str(b["id"]) == id:
					eff = str(b.get("rarity", ""))
		out[s] = {"base": base, "rarity": eff, "kind": "ball", "id": id}
	var nets := unowned_nets(owned_ids, balls)
	if not nets.is_empty():
		var forced := int(rng.range_i(0, lay.size() - 1))
		var picks := [forced]
		for s in lay.size():
			if s != forced and str(out[s]["id"]) == "":
				picks.push_back(s)
		var first := int(rng.range_i(0, nets.size() - 1))
		for k in picks.size():
			var s: int = picks[k]
			var base := str(lay[s])
			out[s] = {"base": base, "rarity": base, "kind": "net", "id": nets[(first + k) % nets.size()]}
	return out


## Tickets paid back when the puck lands on this plate.
static func refund(slot: Dictionary) -> int:
	return REFUND if str(slot.get("id", "")) == "" else 0


## Expected tickets to win every prize (the balls and the nets), from `p`
## (the seven slot odds at the aim the player is assumed to use), averaged
## over seeded collection runs with the promotion/refund rules and this
## level's gates. Returns -1 when the roster cannot be completed at this
## level.
static func expected_tickets_to_complete(p: PackedFloat64Array, balls: Array, start_owned: Array, level := 99, runs := 200, seed_base := 7) -> float:
	var total := 0.0
	var want := 0
	for b in balls:
		if start_owned.has(str(b["id"])):
			continue
		if kind_of(b) == "net" or level >= rarity_level(str(b.get("rarity", ""))):
			want += 1
	if want == 0:
		return 0.0
	for run in runs:
		var rng := DetRng.new(seed_base * 1000003 + run)
		var owned := start_owned.duplicate()
		var tickets := 0
		var won := 0
		var guard := 0
		while won < want and guard < want * 50:
			guard += 1
			var plates := slots(level, owned, balls, rng)
			var u := rng.next()
			var s := 0
			var acc := 0.0
			for i in p.size():
				acc += p[i]
				if u < acc:
					s = i
					break
				s = i
			tickets += DROP_COST
			var id := str(plates[s]["id"])
			if id == "":
				tickets -= REFUND
			else:
				owned.push_back(id)
				won += 1
		if won < want:
			return -1.0
		total += tickets
	return total / float(runs)
