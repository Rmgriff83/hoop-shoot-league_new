class_name CardBudget
extends RefCounted
## The area envelope (docs/CARDS.md): how much card power a league hands its
## AI per season against how much the player can expect to earn there, as a
## ratio reported beside the league's declared `card_parity` (reported, not
## gated, since 2026-10-19: with one wallet the share of tickets a player
## puts into cards is theirs to choose, and league card buying exists to
## relieve friction, not to balance the AI). Pure arithmetic
## over data/cards.json, data/leagues.json and the measured powers in
## assets/cards/card_power.json — the same numbers tools/card_ledger.gd prints
## and tests/test_card_budget.gd enforces, so a green ledger is a green suite.

## A league's parity "near" its target, for the ledger's remark only.
const PARITY_TOL := 0.2
## Expected playoff heats the player plays in a season (semis Bo3 + final Bo5,
## weighted by making them at all).
const PLAYOFF_GAMES := 4.0
## Chance of the title (its ticket bonus) in an average season.
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
## what the assumed share of the ticket income (economy.json
## cards.ticket_share, informational) buys at the shop (mean price → mean
## power).
static func player_income(league: Dictionary, p_win := P_WIN) -> Dictionary:
	var lid := str(league.get("id", ""))
	var odds := CardDefs.drop_odds()
	var ref: Dictionary = odds.get("reference", {}) if odds.get("reference") is Dictionary else {}
	var mult := float(Dictionary(odds.get("difficulty_mult", {})).get("normal", 1.0))
	# A win rolls at `win` (a comeback share of wins adds the bonus); a loss
	# rolls only when close (a share of losses), at `close_loss`.
	var p_win_drop := minf((float(odds.get("win", 0.6)) + float(ref.get("comeback_win_share", 0.25)) * float(odds.get("comeback_win_bonus", 0.2))) * mult, 1.0)
	var p_loss_drop := float(ref.get("close_loss_share", 0.3)) * minf(float(odds.get("close_loss", 0.35)) * mult, 1.0)
	var p_drop := p_win * p_win_drop + (1.0 - p_win) * p_loss_drop
	var games := regular_games(league)
	var p_po := p_win * minf(p_win_drop + float(odds.get("playoff_bonus", 0.15)) * mult, 1.0) + (1.0 - p_win) * p_loss_drop
	var drops := games * p_drop + PLAYOFF_GAMES * p_po
	# The streak Ice: the expected number of 4th-straight-loss moments in a
	# season (a Markov chain over the streak counter, reset by a win).
	var streak_cards := expected_streak_cards(int(round(games + PLAYOFF_GAMES)), 1.0 - p_win, int(odds.get("loss_streak_n", 4)))
	var usable := usable_ids(league)
	var ice_power := CardDefs.power_mean(str(odds.get("loss_streak_card", "ice"))) if CardDefs.has_power(str(odds.get("loss_streak_card", "ice"))) else mean_dealt_power(usable, lid)
	var drop_power := drops * mean_dealt_power(usable, lid) + streak_cards * ice_power
	var rewards: Dictionary = league.get("rewards", {})
	var per_game := p_win * float(rewards.get("win_tickets", 0)) + (1.0 - p_win) * float(rewards.get("loss_tickets", 0))
	var tickets := (games + PLAYOFF_GAMES) * per_game + P_TITLE * float(rewards.get("title_tickets", 0))
	var share := float(Economy.cards_cfg().get("ticket_share", 0.5))
	var bought := share * tickets / mean_price()
	var bought_power := bought * mean_dealt_power(usable, lid)
	return {"drops": drops, "streak_cards": streak_cards, "drop_power": drop_power, "tickets": tickets, "share": share, "bought": bought,
		"bought_power": bought_power, "power": drop_power + bought_power}


## Expected guaranteed streak cards over `games` with a loss chance `p_loss`:
## the counter climbs on a loss, resets on a win, and pays at every n-th.
static func expected_streak_cards(games: int, p_loss: float, n: int) -> float:
	if n <= 0:
		return 0.0
	var dist := []   # probability of each counter value 0..n-1
	dist.resize(n)
	dist.fill(0.0)
	dist[0] = 1.0
	var paid := 0.0
	for _g in games:
		var next := []
		next.resize(n)
		next.fill(0.0)
		for k in n:
			var pk := float(dist[k])
			if pk == 0.0:
				continue
			next[0] += pk * (1.0 - p_loss)
			if k + 1 == n:
				paid += pk * p_loss   # the n-th straight loss: a card, counter on
				next[0] += pk * p_loss
			else:
				next[k + 1] += pk * p_loss
		dist = next
	return paid


## The ledger's word on a league's parity against its declared target.
static func parity_remark(league: Dictionary) -> String:
	if not league.has("card_parity"):
		return "no target"
	var target := float(league["card_parity"])
	var got := parity(league)
	if absf(got - target) <= PARITY_TOL * target:
		return "near %.2f" % target
	return "%s %.2f (not gated)" % ["above" if got > target else "below", target]


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
		# Parity against `card_parity` is reported by the ledger (parity_remark),
		# not gated here (2026-10-19).
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
