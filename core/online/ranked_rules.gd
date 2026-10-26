class_name RankedRules
extends RefCounted
## The ranked ladder's display rules (docs/BACKEND.md → Ranked), the game's
## mirror of the server's rank.ts over the same data/ranked.json: the
## conservative rating, the visible tier and division, their names. The
## server is the authority (it rates, shields, floors and writes the row);
## this only turns numbers into words, and a test pins both sides to
## tests/fixtures/ranked_ladder.json. Headless.

const PATH := "res://data/ranked.json"

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


## The tiers in order, each {id, name, from}.
static func tiers() -> Array:
	return doc().get("tiers", [])


static func divisions() -> int:
	return int(doc().get("divisions", 3))


static func queue_cfg() -> Dictionary:
	return doc().get("queue", {})


static func prematch_cfg() -> Dictionary:
	return doc().get("prematch", {})


static func tickets_cfg() -> Dictionary:
	return doc().get("tickets", {})


## The rating the ladder shows: mu − k·rd, so an uncertain rating sits low.
static func conservative(mu: float, rd: float) -> float:
	return mu - float(Dictionary(doc().get("conservative", {})).get("rd_k", 2)) * rd


static func tier_index(id: String) -> int:
	var ts := tiers()
	for i in ts.size():
		if str(ts[i].get("id", "")) == id:
			return i
	return 0


static func tier_name(id: String) -> String:
	var ts := tiers()
	var i := tier_index(id)
	return str(ts[i].get("name", id.to_upper())) if i < ts.size() else id.to_upper()


static func is_top_tier(id: String) -> bool:
	var ts := tiers()
	return not ts.is_empty() and tier_index(id) == ts.size() - 1


## cons → {tier, division}: below the first tier is its division 3; inside a
## tier the span to the next tier splits into equal thirds, 3 the lowest, 1
## the highest; the top tier is always division 1 (it shows the position).
static func band_of(cons: float) -> Dictionary:
	var ts := tiers()
	var n := divisions()
	if ts.is_empty():
		return {"tier": "rookie", "division": n}
	var i := 0
	for k in ts.size():
		if cons >= float(ts[k].get("from", 0)):
			i = k
	var tier := str(ts[i].get("id", ""))
	if i == ts.size() - 1:
		return {"tier": tier, "division": 1}
	var lo := float(ts[i].get("from", 0))
	var hi := float(ts[i + 1].get("from", 0))
	if cons < lo:
		return {"tier": tier, "division": n}
	var width := (hi - lo) / float(n)
	var step := clampi(int(floor((cons - lo) / width)), 0, n - 1)
	return {"tier": tier, "division": n - step}


## "III" / "II" / "I".
static func division_numeral(division: int) -> String:
	match division:
		1: return "I"
		2: return "II"
		3: return "III"
	return str(division)


## The badge: "PRO II"; the top tier "LEGEND #12" (or "LEGEND" without a
## position); nothing played yet → "UNRANKED".
static func badge_text(rank: Dictionary) -> String:
	if rank.is_empty() or int(rank.get("games", 0)) <= 0 and not rank.has("tier"):
		return "UNRANKED"
	var tier := str(rank.get("tier", "rookie"))
	if is_top_tier(tier):
		var pos := int(rank.get("position", 0))
		return "%s #%s" % [tier_name(tier), RetroTheme.thousands(pos)] if pos > 0 else tier_name(tier)
	return "%s %s" % [tier_name(tier), division_numeral(int(rank.get("division", 3)))]


## Progress through your division (design "Online Lobby" 37a, 2026-10-25:
## `16 / 50 TO MVP I`): {have, need, next_tier, next_division} in
## conservative rating points, from the rank's tier and division (the badge
## you wear, shield and floors included) and its `cons` (or mu − k·rd).
## Empty at the top tier, before a rated game, or without a rating.
static func division_progress(rank: Dictionary) -> Dictionary:
	if rank.is_empty() or int(rank.get("games", 0)) <= 0:
		return {}
	var cons := 0.0
	if rank.has("cons"):
		cons = float(rank["cons"])
	elif rank.has("mu") and rank.has("rd"):
		cons = conservative(float(rank["mu"]), float(rank["rd"]))
	else:
		return {}
	var ts := tiers()
	var n := divisions()
	var i := tier_index(str(rank.get("tier", "")))
	if ts.is_empty() or i >= ts.size() - 1:
		return {}
	var division := clampi(int(rank.get("division", n)), 1, n)
	var width := (float(ts[i + 1].get("from", 0)) - float(ts[i].get("from", 0))) / float(n)
	var lo := float(ts[i].get("from", 0)) + float(n - division) * width
	var next_tier := str(ts[i].get("id", "")) if division > 1 else str(ts[i + 1].get("id", ""))
	var next_division := division - 1 if division > 1 else n
	return {"have": clampi(int(floor(cons - lo)), 0, int(round(width))), "need": int(round(width)),
		"next_tier": next_tier, "next_division": next_division}


## True when b outranks a.
static func outranks(a: Dictionary, b: Dictionary) -> bool:
	var ta := tier_index(str(a.get("tier", ""))) 
	var tb := tier_index(str(b.get("tier", "")))
	if ta != tb:
		return tb > ta
	return int(b.get("division", 3)) < int(a.get("division", 3))
