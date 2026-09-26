class_name CardRewards
extends RefCounted
## Card supply, both sides of the table. The player's drops after a league
## heat (seeded by the campaign, so a replayed season rolls the same); the
## AI's per-season hands (a fixed allowance per league, seeded by the season,
## consumed when played — see docs/CARDS.md). Odds and rarity weights come
## from data/cards.json.


## → card id or "" (no drop).
static func roll(won: bool, playoff: bool, seed_value: int) -> String:
	var cards := CardDefs.all()
	if cards.is_empty():
		return ""
	var rng := DetRng.new(seed_value)
	var odds := CardDefs.drop_odds()
	var p := float(odds.get("win", 0.6)) if won else float(odds.get("loss", 0.25))
	if playoff:
		p += float(odds.get("playoff_bonus", 0.15))
	if rng.next() >= p:
		return ""
	return pick_weighted(cards.map(func(c): return str(c["id"])), rng)


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
