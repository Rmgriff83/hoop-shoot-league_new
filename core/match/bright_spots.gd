class_name BrightSpots
extends RefCounted
## The bright spots of a league heat (docs/CARDS.md § Drops, 2026-10-19): what
## went well even in a loss, against the player's own running bests kept on
## the league doc (`career.bright = {bestStreak, swishes, pct10: [...]}`).
## `note(doc, result)` updates the store and returns the lines to show —
## `NEW BEST STREAK · 9`, `8 SWISHES · YOUR MOST`, `SHOOTING 62% · UP FROM
## 51% · LAST 10` — newest first, at most MAX. Headless; the online
## post-match page will read the same lines from its own store later.

const MAX := 2
const WINDOW := 10


static func note(doc: Dictionary, result: Dictionary) -> Array:
	var you: Dictionary = result.get("sides", {}).get("player", {}) if result.get("sides") is Dictionary else {}
	if you.is_empty():
		return []
	if not (doc.get("career") is Dictionary):
		doc["career"] = {}
	var career: Dictionary = doc["career"]
	if not (career.get("bright") is Dictionary):
		career["bright"] = {"bestStreak": 0, "swishes": 0, "pct10": []}
	var store: Dictionary = career["bright"]
	var out := []
	var streak := int(you.get("bestStreak", 0))
	if streak > int(store.get("bestStreak", 0)) and streak >= 3:
		out.push_back("NEW BEST STREAK · %d" % streak)
	store["bestStreak"] = maxi(int(store.get("bestStreak", 0)), streak)
	var swishes := int(you.get("swishes", 0))
	if swishes > int(store.get("swishes", 0)) and swishes >= 3:
		out.push_back("%d SWISHES · YOUR MOST" % swishes)
	store["swishes"] = maxi(int(store.get("swishes", 0)), swishes)
	var attempts := int(you.get("attempts", 0))
	if attempts > 0:
		var pct := 100.0 * float(you.get("makes", 0)) / attempts
		var past: Array = store.get("pct10", []) if store.get("pct10") is Array else []
		if past.size() >= 3:
			var mean := 0.0
			for v in past:
				mean += float(v)
			mean /= past.size()
			if pct >= mean + 5.0:
				out.push_back("SHOOTING %d%% · UP FROM %d%% · LAST %d" % [roundi(pct), roundi(mean), past.size()])
		past.push_back(snappedf(pct, 0.1))
		while past.size() > WINDOW:
			past.pop_front()
		store["pct10"] = past
	if out.size() > MAX:
		out.resize(MAX)
	return out
