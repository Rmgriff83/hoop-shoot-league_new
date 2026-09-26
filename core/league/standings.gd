class_name Standings
extends RefCounted
## Standings + seeding for one table (ported from standings.ts, no
## conferences). Tiebreakers: win% → head-to-head → point differential →
## seeded coin flip. Plus the clinch engine: a shown clinch is never wrong —
## everything derives from wins, exact remaining-game counts and settled
## head-to-heads (with two meetings a split h2h stays unsettled → conservative).


static func compute(team_ids: Array, games: Array) -> Dictionary:
	var rows := {}
	for id in team_ids:
		rows[str(id)] = {"teamId": str(id), "w": 0, "l": 0, "pct": 0.0, "pointsFor": 0, "pointsAgainst": 0, "seed": 0}
	for g in games:
		if not g["played"]:
			continue
		if not rows.has(g["homeId"]) or not rows.has(g["awayId"]):
			continue
		var home: Dictionary = rows[g["homeId"]]
		var away: Dictionary = rows[g["awayId"]]
		home["pointsFor"] += int(g["homeScore"])
		home["pointsAgainst"] += int(g["awayScore"])
		away["pointsFor"] += int(g["awayScore"])
		away["pointsAgainst"] += int(g["homeScore"])
		if int(g["homeScore"]) > int(g["awayScore"]):
			home["w"] += 1
			away["l"] += 1
		else:
			away["w"] += 1
			home["l"] += 1
	for id in rows:
		var row: Dictionary = rows[id]
		var total: int = row["w"] + row["l"]
		row["pct"] = float(row["w"]) / total if total > 0 else 0.0
	return rows


static func winner_of(g: Dictionary) -> String:
	return str(g["homeId"]) if int(g["homeScore"]) > int(g["awayScore"]) else str(g["awayId"])


## Negative → a ahead on head-to-head, positive → b ahead, 0 → level.
static func head_to_head(a: String, b: String, games: Array) -> int:
	var a_wins := 0
	var b_wins := 0
	for g in games:
		if not g["played"]:
			continue
		var pair: bool = (g["homeId"] == a and g["awayId"] == b) or (g["homeId"] == b and g["awayId"] == a)
		if not pair:
			continue
		if winner_of(g) == a:
			a_wins += 1
		else:
			b_wins += 1
	return b_wins - a_wins


## Sorted table with seeds (1 = best).
static func table(team_ids: Array, games: Array, season_seed: int) -> Array:
	var rows := compute(team_ids, games)
	var out := []
	for id in team_ids:
		out.push_back(rows[str(id)])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["pct"] != b["pct"]:
			return a["pct"] > b["pct"]
		var h2h := head_to_head(a["teamId"], b["teamId"], games)
		if h2h != 0:
			return h2h < 0
		var da: int = a["pointsFor"] - a["pointsAgainst"]
		var db: int = b["pointsFor"] - b["pointsAgainst"]
		if da != db:
			return da > db
		# Deterministic coin flip, symmetric in (a, b).
		var first: String = a["teamId"] if a["teamId"] < b["teamId"] else b["teamId"]
		var second: String = b["teamId"] if first == a["teamId"] else a["teamId"]
		var flip := DetRng.new(season_seed ^ DetRng.hash_seed(first + "|" + second)).next() < 0.5
		return flip == (a["teamId"] == first)
	)
	for i in out.size():
		out[i]["seed"] = i + 1
	return out


## Classic games-behind.
static func games_behind(leader: Dictionary, row: Dictionary) -> float:
	return float(int(leader["w"]) - int(row["w"]) + (int(row["l"]) - int(leader["l"]))) / 2.0


## {"type": "W"|"L", "count": n} or {} before any game.
static func current_streak(team_id: String, games: Array) -> Dictionary:
	var mine := []
	for g in games:
		if g["played"] and (g["homeId"] == team_id or g["awayId"] == team_id):
			mine.push_back(g)
	mine.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	if mine.is_empty():
		return {}
	var type_ := "W" if winner_of(mine[mine.size() - 1]) == team_id else "L"
	var count := 0
	for i in range(mine.size() - 1, -1, -1):
		var t := "W" if winner_of(mine[i]) == team_id else "L"
		if t != type_:
			break
		count += 1
	return {"type": type_, "count": count}


# ---- clinch math ----

static func _tally(games: Array) -> Dictionary:
	var wins := {}
	var remaining := {}
	var between := {}
	for g in games:
		if g["played"]:
			var w := winner_of(g)
			wins[w] = int(wins.get(w, 0)) + 1
		else:
			remaining[g["homeId"]] = int(remaining.get(g["homeId"], 0)) + 1
			remaining[g["awayId"]] = int(remaining.get(g["awayId"], 0)) + 1
			var key := _pair_key(g["homeId"], g["awayId"])
			between[key] = int(between.get(key, 0)) + 1
	return {"wins": wins, "remaining": remaining, "between": between}


static func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func _guaranteed_ahead_with(t: Dictionary, games: Array, a: String, b: String) -> bool:
	var a_wins: int = t["wins"].get(a, 0)
	var b_max: int = int(t["wins"].get(b, 0)) + int(t["remaining"].get(b, 0))
	if a_wins > b_max:
		return true
	if a_wins < b_max:
		return false
	# Worst case: a tie at equal wins. Settled only if no meetings remain and
	# the head-to-head already favours a (a split h2h is not a settled edge).
	var meetings_left: int = t["between"].get(_pair_key(a, b), 0)
	return meetings_left == 0 and head_to_head(a, b, games) < 0


## Is `a` mathematically guaranteed to finish ahead of `b`?
static func guaranteed_ahead(a: String, b: String, games: Array) -> bool:
	return _guaranteed_ahead_with(_tally(games), games, a, b)


## Per-team flags: playoffs (guaranteed ahead of enough rivals), top_seed
## (ahead of everyone), eliminated (`spots` rivals are each guaranteed ahead).
static func compute_clinches(team_ids: Array, games: Array, spots := 4) -> Dictionary:
	var t := _tally(games)
	var out := {}
	for a in team_ids:
		var ahead_of := 0
		var behind := 0
		for b in team_ids:
			if a == b:
				continue
			if _guaranteed_ahead_with(t, games, str(a), str(b)):
				ahead_of += 1
			if _guaranteed_ahead_with(t, games, str(b), str(a)):
				behind += 1
		out[str(a)] = {
			"playoffs": ahead_of >= team_ids.size() - spots,
			"topSeed": ahead_of == team_ids.size() - 1,
			"eliminated": behind >= spots,
		}
	return out
