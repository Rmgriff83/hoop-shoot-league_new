class_name CardRewards
extends RefCounted
## Card supply, both sides of the table. The player's drops after a league
## heat (seeded by the campaign, so a replayed season rolls the same); the
## AI's per-season hands (a fixed allowance per league, seeded by the season,
## consumed when played — see docs/CARDS.md). Odds and rarity weights come
## from data/cards.json.


## The player's drop after a league heat (docs/CARDS.md § Drops, 2026-10-19):
## → {id, reason} with reason win | comeback_win | close_loss | loss_streak,
## or {id: "", reason: ""} for none. `ctx`: won, playoff, level (the player's),
## difficulty (easy|normal|hard), margin (player − opponent points), ot
## (periods), trailing_at_half, loss_streak (straight league-heat losses
## BEFORE this one, counting this one if it is a loss). Rules, all numbers
## from data/cards.json → drop_odds:
##   - the pool is every card with level ≤ level + level_ahead; the rarity
##     weights apply inside it, falling back to any eligible card; none → no drop;
##   - a win rolls at `win` (+ playoff_bonus in the playoffs, + comeback_win_bonus
##     when trailing at the half), × difficulty_mult[difficulty];
##   - a loss drops nothing, except: lost by ≤ close_margin or in overtime →
##     a roll at `close_loss` (× the multiplier); the loss_streak_n-th straight
##     loss → the loss_streak_card, guaranteed (no multiplier, no roll).
## Seeded (the campaign's seed): a replayed season rolls the same.
static func roll(ctx: Dictionary, seed_value: int) -> Dictionary:
	var none := {"id": "", "reason": ""}
	var odds := CardDefs.drop_odds()
	var won := bool(ctx.get("won", false))
	var level := int(ctx.get("level", 1))
	var pool := eligible_ids(level)
	var rng := DetRng.new(seed_value)
	var mults: Dictionary = odds.get("difficulty_mult", {}) if odds.get("difficulty_mult") is Dictionary else {}
	var mult := float(mults.get(str(ctx.get("difficulty", "normal")), 1.0))
	if not won:
		var streak := int(ctx.get("loss_streak", 0))
		var n := int(odds.get("loss_streak_n", 4))
		if n > 0 and streak > 0 and streak % n == 0:
			var ice := str(odds.get("loss_streak_card", "ice"))
			return {"id": ice, "reason": "loss_streak"} if not CardDefs.get_card(ice).is_empty() else none
		var close := int(ctx.get("margin", 0)) >= -int(odds.get("close_margin", 2)) or int(ctx.get("ot", 0)) > 0
		if not close or pool.is_empty():
			return none
		if rng.next() >= float(odds.get("close_loss", 0.35)) * mult:
			return none
		var picked := pick_weighted(pool, rng)
		return {"id": picked, "reason": "close_loss"} if picked != "" else none
	if pool.is_empty():
		return none
	var p := float(odds.get("win", 0.6))
	if bool(ctx.get("playoff", false)):
		p += float(odds.get("playoff_bonus", 0.15))
	var comeback := bool(ctx.get("trailing_at_half", false))
	if comeback:
		p += float(odds.get("comeback_win_bonus", 0.2))
	if rng.next() >= p * mult:
		return none
	var id := pick_weighted(pool, rng)
	if id == "":
		return none
	return {"id": id, "reason": "comeback_win" if comeback else "win"}


## The cards a player at `level` can drop: level ≤ level + level_ahead.
static func eligible_ids(level: int) -> Array:
	var ahead := int(CardDefs.drop_odds().get("level_ahead", 1))
	var out := []
	for c in CardDefs.all():
		if Progression.card_level(c) <= level + ahead:
			out.push_back(str(c["id"]))
	return out


## The straight league-heat losses after this result: a loss adds one, a win
## resets. Kept on the league doc (`lossStreak`) so a replayed season rolls
## the same.
static func next_loss_streak(before: int, won: bool) -> int:
	return 0 if won else before + 1


## A rarity-weighted pick from `ids`: roll a rarity by weight, take a card of
## that rarity, fall back to any of them when the rolled rarity has none.
static func pick_weighted(ids: Array, rng: DetRng) -> String:
	if ids.is_empty():
		return ""
	var weights := CardDefs.rarity_weights()
	var total := 0.0
	for r in weights:
		total += float(weights[r])
	var x := rng.next() * total
	var rarity := ""
	for r in weights:
		x -= float(weights[r])
		if x <= 0.0:
			rarity = str(r)
			break
	var pool := []
	for id in ids:
		if CardDefs.get_card(str(id)).get("rarity", "") == rarity:
			pool.push_back(str(id))
	if pool.is_empty():
		pool = ids.duplicate()
	return str(rng.pick(pool))


## The AI roster's hands for one season: {shooter_id: [card ids]}. Every
## shooter starts from its authored signature cards (`ai_cards`), then
## `ai_cards_per_season` − those are dealt one at a time, rarity-weighted
## from `ai_pool`, to a seeded shooter still under `ai_hand_max`. Deterministic
## per seed. A league without the fields gets just its authored hands.
static func ai_hands(league: Dictionary, seed_value: int) -> Dictionary:
	var roster: Array = league.get("roster", [])
	var authored: Dictionary = league.get("ai_cards", {})
	var hands := {}
	var dealt := 0
	for id in roster:
		hands[str(id)] = Array(authored.get(str(id), [])).duplicate()
		dealt += hands[str(id)].size()
	var total := int(league.get("ai_cards_per_season", dealt))
	var cap := int(league.get("ai_hand_max", 1 << 30))
	var pool := Array(league.get("ai_pool", []))
	if pool.is_empty():
		pool = CardDefs.all().map(func(c): return str(c["id"]))
	var rng := DetRng.new(seed_value)
	while dealt < total:
		var open := []
		for id in roster:
			if hands[str(id)].size() < cap:
				open.push_back(str(id))
		if open.is_empty():
			break
		var who := str(rng.pick(open))
		var card := pick_weighted(pool, rng)
		if card == "":
			break
		hands[who].push_back(card)
		dealt += 1
	return hands
