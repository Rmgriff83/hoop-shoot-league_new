class_name Playoffs
extends RefCounted
## Compact playoffs: the top `playoff_teams` (4) seeds — semifinals 1v4 and
## 2v3 (best of `semis_best_of`), then the final (best of `final_best_of`).
## Series shape matches the original's PlayoffSeries.


static func make_series(id: String, round_: String, high: String, low: String, best_of: int) -> Dictionary:
	return {"id": id, "round": round_, "highSeedId": high, "lowSeedId": low, "bestOf": best_of,
		"highWins": 0, "lowWins": 0, "winnerId": "", "games": []}


static func needed_wins(series: Dictionary) -> int:
	return int(series["bestOf"]) / 2 + 1


## Seeds from a sorted table (index 0 = seed 1).
static func build_semis(table: Array, best_of: int) -> Array:
	return [
		make_series("sf-1v4", "semifinal", table[0]["teamId"], table[3]["teamId"], best_of),
		make_series("sf-2v3", "semifinal", table[1]["teamId"], table[2]["teamId"], best_of),
	]


## Record one series game. True when the series just ended.
static func record_series_game(series: Dictionary, high_score: int, low_score: int) -> bool:
	if series["winnerId"] != "":
		return false
	if high_score > low_score:
		series["highWins"] += 1
	else:
		series["lowWins"] += 1
	var need := needed_wins(series)
	if int(series["highWins"]) >= need:
		series["winnerId"] = series["highSeedId"]
	elif int(series["lowWins"]) >= need:
		series["winnerId"] = series["lowSeedId"]
	return series["winnerId"] != ""


static func find(series: Array, id: String) -> Dictionary:
	for s in series:
		if s["id"] == id:
			return s
	return {}


## Create the final once both semis are decided (the 1v4 winner is the high
## seed). Returns newly created series.
static func advance_bracket(series: Array, final_best_of: int) -> Array:
	var created := []
	var one := find(series, "sf-1v4")
	var two := find(series, "sf-2v3")
	if find(series, "final").is_empty() and not one.is_empty() and not two.is_empty() \
			and one["winnerId"] != "" and two["winnerId"] != "":
		created.push_back(make_series("final", "final", one["winnerId"], two["winnerId"], final_best_of))
	return created


static func champion(series: Array) -> String:
	var f := find(series, "final")
	return str(f.get("winnerId", "")) if not f.is_empty() else ""
