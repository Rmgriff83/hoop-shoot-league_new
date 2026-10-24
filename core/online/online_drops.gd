class_name OnlineDrops
extends RefCounted
## Ranked Stage B numbers (docs/BACKEND.md → Ranked → Stage B): the game's
## mirror of the server's online_drops.ts over the same
## data/online_drops.json. The server grants every card (spoils, the meter,
## the streak Ice, logins, milestones); this only turns the data into the
## words and odds the game shows, and tests/fixtures/online_drops_cases.json
## pins both sides to the same derivation. Headless.

const PATH := "res://data/online_drops.json"
const RARITIES := ["common", "rare", "epic"]

static var _doc: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_doc = parsed


static func doc() -> Dictionary:
	_load()
	return _doc


static func weekly_target() -> int:
	return int(doc().get("weekly_card_target", 5))


static func reference_player() -> Dictionary:
	return doc().get("reference", {})


static func meter_cfg() -> Dictionary:
	return doc().get("meter", {})


static func streak_cfg() -> Dictionary:
	return doc().get("streak_card", {})


static func insurance_cfg() -> Dictionary:
	return doc().get("insurance", {})


static func logins_cfg() -> Dictionary:
	return doc().get("logins", {})


static func milestones_cfg() -> Dictionary:
	return doc().get("milestones", {})


static func shoot_around_cfg() -> Dictionary:
	return doc().get("shoot_around", {})


static func same_opponent_cap() -> int:
	return int(doc().get("same_opponent_cap_per_day", 2))


static func card_min_tier(id: String) -> String:
	var tiers := RankedRules.tiers()
	var first := str(tiers[0].get("id", "rookie")) if not tiers.is_empty() else "rookie"
	return str(Dictionary(doc().get("card_min_tier", {})).get(id, first))


## The derivation the ledger prints (the server's derive(), to the number):
## expected meter points a week for the reference player, the streak Ice
## they fall into, the meter size that lands the weekly target, and cards in
## per ranked match against cards played.
static func derive() -> Dictionary:
	var r := reference_player()
	var m := meter_cfg()
	var w := float(r.get("win_rate", 0.5))
	var per_week := float(r.get("ranked_per_week", 12))
	var login_days := float(r.get("login_days_per_week", 5))
	var close_share := float(r.get("close_loss_share", 0.3))
	var points_per_match := w * float(m.get("win", 10)) + (1.0 - w) * (close_share * float(m.get("close_loss", 8)) + (1.0 - close_share) * float(m.get("loss", 3)))
	var first_win_days := login_days * (1.0 - pow(1.0 - w, per_week / maxf(login_days, 1.0)))
	var points_per_week := per_week * points_per_match + first_win_days * float(m.get("first_win_day", 4))
	var streak_cards := per_week * w * pow(1.0 - w, float(streak_cfg().get("losses", 4)))
	var size := roundi(points_per_week / maxf(float(weekly_target()) - streak_cards, 0.01))
	var cards_in := float(weekly_target()) / maxf(per_week, 1.0)
	return {
		"points_per_match": points_per_match, "first_win_days": first_win_days, "points_per_week": points_per_week,
		"streak_cards_per_week": streak_cards, "meter_size": size, "cards_in_per_match": cards_in,
		"ratio": cards_in / maxf(float(r.get("cards_played_per_match", 1.5)), 0.01),
	}


static func meter_size() -> int:
	return int(derive()["meter_size"])


## The cards a player at (tier, level) may be dealt: the level and the card's
## minimum tier both allow it. Sorted ids.
static func eligible_cards(tier: String, level: int) -> Array:
	var ti := RankedRules.tier_index(tier)
	var out := []
	for c in CardDefs.all():
		var id := str(c["id"])
		if Progression.card_level(c) <= level and RankedRules.tier_index(card_min_tier(id)) <= ti:
			out.push_back(id)
	out.sort()
	return out


## The rarity odds the game shows: the tier's weights over the rarities the
## pool holds, renormalised (a rarity with no eligible card drops out).
static func odds_for(tier: String, level: int) -> Dictionary:
	var by_tier: Dictionary = doc().get("rarity_by_tier", {})
	var tiers := RankedRules.tiers()
	var first := str(tiers[0].get("id", "rookie")) if not tiers.is_empty() else "rookie"
	var weights: Dictionary = by_tier.get(tier, by_tier.get(first, {}))
	var present := {}
	for id in eligible_cards(tier, level):
		present[str(CardDefs.get_card(id).get("rarity", "common"))] = true
	var sum := 0.0
	for r in RARITIES:
		if present.has(r):
			sum += float(weights.get(r, 0))
	var out := {"common": 0.0, "rare": 0.0, "epic": 0.0}
	if sum <= 0.0:
		return out
	for r in RARITIES:
		out[r] = float(weights.get(r, 0)) / sum if present.has(r) else 0.0
	return out


## `70% COMMON · 25% RARE · 5% EPIC` (a rarity at 0 is left out).
static func odds_text(odds: Dictionary) -> String:
	var parts := []
	for r in RARITIES:
		var pct := roundi(100.0 * float(odds.get(r, 0.0)))
		if pct > 0:
			parts.push_back("%d%% %s" % [pct, str(r).to_upper()])
	return " · ".join(parts)


## The next schedule day above the count (0 when the schedule is spent).
static func next_login_card(login_days: int) -> int:
	for entry in logins_cfg().get("schedule", []):
		if entry is Array and entry.size() >= 1 and int(entry[0]) > login_days:
			return int(entry[0])
	return 0


## Every milestone key the game can show, in the server's order (the locked
## list on the rewards page).
static func all_milestone_keys() -> Array:
	var out := ["first_login", "first_ranked_match", "first_ranked_win", "first_capture"]
	var wins: Array = Dictionary(milestones_cfg().get("ranked_wins", {})).keys()
	wins.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for n in wins:
		out.push_back("ranked_wins_%d" % int(n))
	var tiers := RankedRules.tiers()
	var legend := str(tiers[tiers.size() - 1].get("id", "legend")) if not tiers.is_empty() else "legend"
	for t in tiers:
		var id := str(t.get("id", ""))
		out.push_back("tier_%s" % id)
		if id != legend:
			for d in range(RankedRules.divisions(), 0, -1):
				out.push_back("division_%s_%d" % [id, d])
	return out
