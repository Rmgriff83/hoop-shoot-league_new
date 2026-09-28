class_name CardBudget
extends RefCounted
## The area envelope (docs/CARDS.md): how much card power a league hands its
## AI per season against how much the player can expect to earn there, as a
## ratio checked against the league's declared `card_parity`. Pure arithmetic
## over data/cards.json, data/leagues.json and the measured powers in
## assets/cards/card_power.json — the same numbers tools/card_ledger.gd prints
## and tests/test_card_budget.gd enforces, so a green ledger is a green suite.

## A league's parity may sit this far (relative) from its target.
const PARITY_TOL := 0.2
## Expected playoff heats the player plays in a season (semis Bo3 + final Bo5,
## weighted by making them at all).
const PLAYOFF_GAMES := 4.0
## Chance of the title (its coin bonus) in an average season.
const P_TITLE := 0.2
## Both rows of the standings taken as a coin flip.
const P_WIN := 0.5


static func regular_games(league: Dictionary) -> int:
	return Array(league.get("roster", [])).size() * int(league.get("rounds", 2))


## Rarity-weighted mean power of a set of card ids in a league, the way the
## dealer draws them (roll a rarity by weight, then a card of that rarity,
## falling back to any when the rarity is empty).
static func mean_dealt_power(ids: Array, league_id: String) -> float:
	if ids.is_empty():
		return 0.0
	var weights := CardDefs.rarity_weights()
	var total_w := 0.0
	for r in weights:
		total_w += float(weights[r])
	var all_mean := 0.0
	for id in ids:
		all_mean += CardDefs.power(str(id), league_id)
	all_mean /= ids.size()
	var out := 0.0
	for r in weights:
		var pool_sum := 0.0
		var pool_n := 0
		for id in ids:
			if str(CardDefs.get_card(str(id)).get("rarity", "")) == str(r):
				pool_sum += CardDefs.power(str(id), league_id)
				pool_n += 1
		var m := (pool_sum / pool_n) if pool_n > 0 else all_mean
		out += float(weights[r]) / total_w * m
	return out


static func all_ids() -> Array:
	return CardDefs.all().map(func(c): return str(c["id"]))


## The cards a player can actually PLAY while in this league: those whose
## level sits below the league's cap (docs/PROGRESSION.md — at the cap you
## have graduated, and a card that opens there is the next league's). A card
## you cannot play yet is not income, however often it drops.
static func usable_ids(league: Dictionary) -> Array:
	var cap := Progression.cap_level(league)
	var out := []
	for c in CardDefs.all():
		if Progression.card_level(c) < cap:
			out.push_back(str(c["id"]))
	return out


static func mean_price() -> float:
	var cards := CardDefs.all()
	if cards.is_empty():
		return 1.0
	var s := 0.0
	for c in cards:
		s += float(c.get("price", 0))
	return maxf(s / cards.size(), 1.0)


## Authored power + the dealt remainder at the pool's dealt mean.
static func ai_budget(league: Dictionary) -> Dictionary:
	var lid := str(league.get("id", ""))
	var authored_power := 0.0
	var authored_n := 0
	for sid in league.get("ai_cards", {}):
		for id in Array(league["ai_cards"][sid]):
			authored_power += CardDefs.power(str(id), lid)
			authored_n += 1
	var per_season := int(league.get("ai_cards_per_season", authored_n))
	var pool := Array(league.get("ai_pool", []))
	if pool.is_empty():
		pool = all_ids()
	var dealt_n := maxi(per_season - authored_n, 0)
	var dealt_power := dealt_n * mean_dealt_power(pool, lid)
	return {"authored_n": authored_n, "authored_power": authored_power, "dealt_n": dealt_n,
		"dealt_power": dealt_power, "power": authored_power + dealt_power, "per_season": per_season}


## Expected card power the player earns in one season of this league: drops
## (regular + playoff games at the drop odds, at the dealt mean power) plus
## what the coin income buys at the shop (mean price → mean power).
static func player_income(league: Dictionary, p_win := P_WIN) -> Dictionary:
	var lid := str(league.get("id", ""))
	var odds := CardDefs.drop_odds()
	var p_drop := p_win * float(odds.get("win", 0.6)) + (1.0 - p_win) * float(odds.get("loss", 0.25))
	var games := regular_games(league)
	var drops := games * p_drop + PLAYOFF_GAMES * minf(p_drop + float(odds.get("playoff_bonus", 0.15)), 1.0)
	var usable := usable_ids(league)
	var drop_power := drops * mean_dealt_power(usable, lid)
	var rewards: Dictionary = league.get("rewards", {})
	var coins_per_game := p_win * float(rewards.get("win_coins", 50)) + (1.0 - p_win) * float(rewards.get("loss_coins", 20))
	var coins := (games + PLAYOFF_GAMES) * coins_per_game + P_TITLE * float(rewards.get("title_coins", 300))
	var bought := coins / mean_price()
	var bought_power := bought * mean_dealt_power(usable, lid)
	return {"drops": drops, "drop_power": drop_power, "coins": coins, "bought": bought,
		"bought_power": bought_power, "power": drop_power + bought_power}


static func parity(league: Dictionary) -> float:
	var income := float(player_income(league)["power"])
	if income <= 0.0:
		return 0.0
	return float(ai_budget(league)["power"]) / income


## Leagues ordered along the unlock chain: open leagues first, then each one
## after the league its unlock rule names.
static func unlock_chain(leagues: Array) -> Array:
	var depth := {}
	for l in leagues:
		var d := 0
		var cur: Dictionary = l
		var guard := 0
		while cur.get("unlock", null) != null and guard < 16:
			guard += 1
			d += 1
			var parent_id := str(cur["unlock"].get("league", ""))
			cur = {}
			for p in leagues:
				if str(p.get("id", "")) == parent_id:
					cur = p
			if cur.is_empty():
				break
		depth[str(l.get("id", ""))] = d
	var out := leagues.duplicate()
	out.sort_custom(func(a, b): return int(depth[str(a["id"])]) < int(depth[str(b["id"])]))
	return out


## Every rule, as problems (empty = the graph is inside its envelope).
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for c in CardDefs.all():
		var id := str(c["id"])
		if not CardDefs.has_power(id):
			out.push_back("card %s has no measured power (run tools/card_lab.gd)" % id)
			continue
		var p := CardDefs.power_mean(id)
		var band := CardDefs.rarity_for(p)
		if str(c.get("rarity", "")) != band:
			out.push_back("card %s is %s but its power %.2f sits in the %s band" % [id, c.get("rarity", "?"), p, band])
		if not CardDefs.price_ok(int(c.get("price", 0)), p):
			out.push_back("card %s priced %d, the curve says %d (±%.0f%%)" % [id, int(c.get("price", 0)),
				CardDefs.price_for(p), 100.0 * float(CardDefs.price_curve().get("tolerance", 0.2))])
	var leagues := LeagueData.leagues()
	for l in leagues:
		var lid := str(l.get("id", "?"))
		if not l.has("card_parity"):
			continue
		var target := float(l["card_parity"])
		var got := parity(l)
		if absf(got - target) > PARITY_TOL * target:
			out.push_back("league %s parity %.2f is outside %.2f ±%.0f%%" % [lid, got, target, 100.0 * PARITY_TOL])
		for sid in l.get("ai_cards", {}):
			var epics := 0
			for id in Array(l["ai_cards"][sid]):
				if CardDefs.rarity_for(CardDefs.power_mean(str(id))) == "epic":
					epics += 1
			if epics > 1:
				out.push_back("league %s hands %s %d epic-band cards (max 1)" % [lid, sid, epics])
	for l in leagues:
		var rule: Variant = l.get("unlock", null)
		if rule == null or not l.has("card_parity"):
			continue
		var parent := LeagueData.league(str(rule.get("league", "")))
		if not parent.is_empty() and parent.has("card_parity") and float(parent["card_parity"]) > float(l["card_parity"]):
			out.push_back("league %s (parity %.2f) unlocks after %s (parity %.2f): parity must not fall along the chain" % [
				l.get("id", "?"), float(l["card_parity"]), parent.get("id", "?"), float(parent["card_parity"])])
	return out
