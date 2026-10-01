class_name PeggyPrizes
extends RefCounted
## What PEGGY pays (docs/LOCKER.md): the seven slot plates for a level, which
## unowned ball each one shows, and what a landing is worth. Pure over an
## Array of {id, rarity} balls so tests need no resources; the game layer
## passes CosmeticLibrary's roster and the save's owned list.
##
## Rules: a drop costs DROP_COST tickets. Slots only ever show balls the
## player does not own. Outer slots are the rarest the level allows (epic
## from EPIC_LEVEL, legend from LEGEND_LEVEL). When a slot's rarity has no
## unowned ball left it PROMOTES to the next rarity up that still has one at
## this level, then falls back down. Plates prefer to show seven different
## balls, but once fewer remain the same ball sits on several plates (the
## last ball of all is on every plate), so the roster never stalls on a 4 %
## plate. Only when nothing unowned is left at this level does a plate show
## a ticket glyph and pay REFUND back.

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


## Ids of this rarity the player does not own (roster order).
static func unowned(rarity: String, owned_ids: Array, balls: Array) -> Array:
	var out := []
	for b in balls:
		if str(b.get("rarity", "")) == rarity and not owned_ids.has(str(b["id"])):
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


## The seven plates: [{base, rarity, ball_id}] — base is the layout's rarity,
## rarity the one actually paid (after promotion), ball_id "" for a refund
## plate. Assigned rarest-first so the outer plates get first pick.
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
		out[s] = {"base": base, "rarity": eff, "ball_id": id}
	return out


## Tickets paid back when the puck lands on this plate.
static func refund(slot: Dictionary) -> int:
	return REFUND if str(slot.get("ball_id", "")) == "" else 0


## Expected tickets to win every ball, from `p` (the seven slot odds at the
## aim the player is assumed to use), averaged over seeded collection runs
## with the promotion/refund rules and this level's gates. Returns -1 when
## the roster cannot be completed at this level.
static func expected_tickets_to_complete(p: PackedFloat64Array, balls: Array, start_owned: Array, level := 99, runs := 200, seed_base := 7) -> float:
	var total := 0.0
	var want := 0
	for b in balls:
		if not start_owned.has(str(b["id"])) and level >= rarity_level(str(b.get("rarity", ""))):
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
			var id := str(plates[s]["ball_id"])
			if id == "":
				tickets -= REFUND
			else:
				owned.push_back(id)
				won += 1
		if won < want:
			return -1.0
		total += tickets
	return total / float(runs)
