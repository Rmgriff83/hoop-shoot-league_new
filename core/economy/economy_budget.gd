class_name EconomyBudget
extends RefCounted
## The economy's envelope (docs/ECONOMY.md): what the reference player earns
## per minute in each mode, how long every locker item takes to afford and
## which price tier that puts it in, how long the whole catalog takes, and
## how many heats each card rarity costs in each league. Pure arithmetic
## over data/economy.json, data/leagues.json and the cosmetic prices — the
## same numbers tools/economy_ledger.gd prints and tests/test_economy.gd
## enforces, so a green ledger is a green suite.


static func ref_player() -> Dictionary:
	return Economy.tickets_cfg().get("reference", {})


## Tickets per minute a reference trial pays at this location.
static func trial_rate(location: String) -> float:
	var ref := ref_player()
	var score := float(Dictionary(ref.get("avg_score", {})).get(location, 24))
	var n := Economy.trial_tickets({"score": score, "location": location}, false)
	return float(n) / maxf(float(ref.get("trial_minutes", 1.5)), 0.1)


## Tickets per minute a reference heat pays in this league.
static func heat_rate(league: Dictionary) -> float:
	return Economy.expected_tickets_per_heat(league) / maxf(float(ref_player().get("heat_minutes", 2.5)), 0.1)


## Every ticket-paying mode with its rate: [{mode, rate}].
static func rates() -> Array:
	var out := []
	var locs: Array = Dictionary(ref_player().get("avg_score", {})).keys()
	locs.sort()
	for loc in locs:
		out.push_back({"mode": "trial %s" % loc, "rate": trial_rate(str(loc))})
	for l in LeagueData.leagues():
		out.push_back({"mode": "heat %s" % l["id"], "rate": heat_rate(l)})
	return out


## The grind rate the tiers are measured against: the mean trial rate.
static func grind_rate() -> float:
	var locs: Array = Dictionary(ref_player().get("avg_score", {})).keys()
	if locs.is_empty():
		return 1.0
	var s := 0.0
	for loc in locs:
		s += trial_rate(str(loc))
	return maxf(s / locs.size(), 0.01)


static func minutes_to_afford(price: int) -> float:
	return float(price) / grind_rate()


## The tier whose minutes band holds this price ("" = none).
static func tier_of(price: int) -> String:
	var m := minutes_to_afford(price)
	var tiers: Dictionary = Economy.tickets_cfg().get("tiers", {})
	for name_ in tiers:
		if m >= float(tiers[name_][0]) and m <= float(tiers[name_][1]):
			return str(name_)
	return ""


## Every priced locker item: [{kind, id, name, price, minutes, tier}].
static func catalog() -> Array:
	var out := []
	for kind in ["hoop", "ball"]:
		var sets: Array = CosmeticLibrary.hoops() if kind == "hoop" else CosmeticLibrary.balls()
		for cs in sets:
			if cs.price_coins <= 0:
				continue
			out.push_back({"kind": kind, "id": cs.id, "name": cs.display_name, "price": int(cs.price_coins),
				"minutes": minutes_to_afford(int(cs.price_coins)), "tier": tier_of(int(cs.price_coins))})
	return out


static func catalog_hours() -> float:
	var total := 0
	for item in catalog():
		total += int(item["price"])
	return minutes_to_afford(total) / 60.0


static func heats_to_afford(league: Dictionary, price: int) -> float:
	return float(price) / maxf(Economy.expected_coins_per_heat(league), 0.01)


## Every rule, as problems (empty = the economy is inside its envelope).
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var cfg := Economy.tickets_cfg()
	var band: Array = cfg.get("rate_band_per_min", [6, 14])
	for r in rates():
		if float(r["rate"]) < float(band[0]) or float(r["rate"]) > float(band[1]):
			out.push_back("mode %s pays %.1f tickets/min, outside %s-%s" % [r["mode"], r["rate"], band[0], band[1]])
	var tiers: Dictionary = cfg.get("tiers", {})
	var ceiling := 0.0
	for name_ in tiers:
		ceiling = maxf(ceiling, float(tiers[name_][1]))
	for item in catalog():
		if str(item["tier"]) == "":
			out.push_back("%s %s at %d tickets takes %.0f min: in no price tier" % [item["kind"], item["id"], item["price"], item["minutes"]])
		elif float(item["minutes"]) > ceiling:
			out.push_back("%s %s at %d tickets takes %.0f min, past the grail ceiling %.0f" % [item["kind"], item["id"], item["price"], item["minutes"], ceiling])
	var hours: Array = cfg.get("catalog_hours", [15, 35])
	var h := catalog_hours()
	if h < float(hours[0]) or h > float(hours[1]):
		out.push_back("the whole catalog takes %.1f hours, outside %s-%s" % [h, hours[0], hours[1]])
	var bands: Dictionary = Economy.coins_cfg().get("heats_to_afford", {})
	for l in LeagueData.leagues():
		for c in CardDefs.all():
			var rarity := str(c.get("rarity", ""))
			if not bands.has(rarity):
				continue
			var n := heats_to_afford(l, int(c.get("price", 0)))
			if n < float(bands[rarity][0]) or n > float(bands[rarity][1]):
				out.push_back("league %s: %s card %s costs %.1f heats, outside %s-%s" % [l["id"], rarity, c["id"], n, bands[rarity][0], bands[rarity][1]])
	return out
