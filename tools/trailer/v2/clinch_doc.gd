extends SceneTree
## Trailer v2, part 3 (docs/TRAILER.md → v2): a cage campaign doc on the regular
## season's LAST day, built so that the player's one remaining game decides a
## playoff spot — not clinched before it, the top seed after a win — and the
## game's own CLINCHED page (design 39a: the standings climb, PLAYOFFS slams)
## follows the real heat. Every other game of the season is filled in here, the
## last day's other games included, so the table after the win is a fact of the
## save, not of a sim.
##
##   godot --headless --path . -s tools/trailer/v2/clinch_doc.gd [-- --seed=45]
##
## prints the tables before and after (the director's `clinch_day` stage calls
## `build` and saves the doc the same way).

const PLAYER := LeagueData.PLAYER_ID
const DEFAULT_SEED := 45


## {doc, opp, seed_before, seed_after, before: [rows], after: [rows], tries} or {}.
## `rows` are the match-end page's [{teamId, w, l, seed}].
static func build(cfg: Dictionary, seed_value: int, tries := 6000) -> Dictionary:
	var ids := LeagueData.team_ids(cfg)
	var doc := Campaign.new_doc(cfg, seed_value, 1000)
	var season: Dictionary = doc["season"]
	var games: Array = season["schedule"]
	var days := Season.days(season)
	var last := Season.player_game_on(season, days, PLAYER)
	if last.is_empty():
		return {}
	var opp := str(last["awayId"] if str(last["homeId"]) == PLAYER else last["homeId"])
	var others: Array = games.filter(func(g: Dictionary) -> bool: return str(g["id"]) != str(last["id"]))
	var spots := int(season.get("playoffTeams", 4))
	var rng := DetRng.new(seed_value)
	var best := {}
	var best_rank := -1
	for t in tries:
		for g in others:
			_fill(g, rng, "")
		_unplay(last)
		var tb := Standings.table(ids, games, int(season["seed"]))
		var sb := _seed_of(tb, PLAYER)
		var cl: Dictionary = Standings.compute_clinches(ids, games, spots).get(PLAYER, {})
		if bool(cl.get("playoffs", false)) or bool(cl.get("eliminated", false)):
			continue
		_fill(last, rng, PLAYER)
		var ta := Standings.table(ids, games, int(season["seed"]))
		var sa := _seed_of(ta, PLAYER)
		_unplay(last)
		# What reads as a reward (the storyboard: NO. 1 or NO. 2), from outside
		# the line if it can be had: the row hops up INTO a playoff spot.
		var rank := -1
		if sa == 1 and sb > spots:
			rank = 4
		elif sa == 2 and sb > spots:
			rank = 3
		elif sa == 1:
			rank = 2
		elif sa == 2:
			rank = 1
		if rank > best_rank:
			best_rank = rank
			best = {"before": _rows(tb), "after": _rows(ta), "seed_before": sb, "seed_after": sa,
				"schedule": games.duplicate(true), "tries": t + 1}
			if rank == 4:
				break
	if best.is_empty():
		return {}
	season["schedule"] = best["schedule"]
	season["currentDay"] = days
	season["cardHands"] = {}   # the opponent plays no cards on the day (an empty hand, not a fresh deal)
	return {"doc": doc, "opp": opp, "seed_before": best["seed_before"], "seed_after": best["seed_after"],
		"before": best["before"], "after": best["after"], "tries": best["tries"]}


## A played game: a random winner (or `winner`), scores a heat would give.
static func _fill(g: Dictionary, rng: DetRng, winner: String) -> void:
	var home_wins := rng.next() < 0.5 if winner == "" else str(g["homeId"]) == winner
	var w := rng.range_i(24, 36)
	var l := w - rng.range_i(1, 12)
	g["homeScore"] = w if home_wins else l
	g["awayScore"] = l if home_wins else w
	g["homeSwishes"] = rng.range_i(2, 8)
	g["awaySwishes"] = rng.range_i(2, 8)
	g["ot"] = 0
	g["played"] = true
	g["playedLive"] = false


static func _unplay(g: Dictionary) -> void:
	g["homeScore"] = 0
	g["awayScore"] = 0
	g["homeSwishes"] = 0
	g["awaySwishes"] = 0
	g["ot"] = 0
	g["played"] = false
	g["playedLive"] = false


static func _seed_of(table: Array, id: String) -> int:
	for row in table:
		if str(row["teamId"]) == id:
			return int(row["seed"])
	return 0


static func _rows(table: Array) -> Array:
	var out := []
	for row in table:
		out.push_back({"teamId": str(row["teamId"]), "w": int(row["w"]), "l": int(row["l"]), "seed": int(row["seed"])})
	return out


static func describe(r: Dictionary) -> String:
	var lines := ["clinch day: vs %s, seed %d -> %d (%d tries)" % [str(r["opp"]), int(r["seed_before"]), int(r["seed_after"]), int(r["tries"])]]
	for key in ["before", "after"]:
		lines.push_back("  %s:" % key)
		for row in r[key]:
			var id := str(row["teamId"])
			var nm := "YOU" if id == PLAYER else str(LeagueData.shooter(id).get("name", id)).to_upper()
			lines.push_back("    %d. %-18s %d-%d" % [int(row["seed"]), nm, int(row["w"]), int(row["l"])])
	return "\n".join(lines)


func _initialize() -> void:
	var seed_value := DEFAULT_SEED
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--seed="):
			seed_value = int(str(a).substr(7))
	var r := build(LeagueData.league("cage"), seed_value)
	if r.is_empty():
		print("clinch day: no table found on seed %d" % seed_value)
		quit(1)
		return
	print(describe(r))
	quit(0)
