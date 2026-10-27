class_name SeasonWrap
extends RefCounted
## Season moments (design 39, docs/LEAGUE.md → Season moments), pure and
## headless: the numbers behind the SEASON WRAP-UP page (39c/e/f) from a
## finished season still on the doc, and behind the NEW SEASON page (39d)
## from the rolled doc's `lastSeason` and its fresh schedule. Ids and
## numbers only — the words are game/ui/season_copy.gd's.

const PLAYER := LeagueData.PLAYER_ID


## Every played game of the player's, regular season and playoffs.
static func player_games(season: Dictionary) -> Array:
	var out := []
	for g in season.get("schedule", []):
		if g.get("played", false) and (g["homeId"] == PLAYER or g["awayId"] == PLAYER):
			out.push_back(g)
	for series in season.get("series", []):
		if series["highSeedId"] == PLAYER or series["lowSeedId"] == PLAYER:
			for g in series.get("games", []):
				if g.get("played", false):
					out.push_back(g)
	return out


static func _you(g: Dictionary) -> int:
	return int(g["homeScore"] if g["homeId"] == PLAYER else g["awayScore"])


static func _them(g: Dictionary) -> int:
	return int(g["awayScore"] if g["homeId"] == PLAYER else g["homeScore"])


static func _opp(g: Dictionary) -> String:
	return str(g["awayId"] if g["homeId"] == PLAYER else g["homeId"])


## The wrap-up's numbers for a season (done or not: a mid-season call just
## reports so far).
static func stats(doc: Dictionary, league: Dictionary) -> Dictionary:
	var s: Dictionary = doc["season"]
	var team_ids := LeagueData.team_ids(league)
	var summary := Campaign.season_summary(doc, league)
	var games := player_games(s)
	var high := 0
	var points := 0
	var swishes := 0
	var best_game := {}
	for g in games:
		var you := _you(g)
		var them := _them(g)
		high = maxi(high, you)
		points += you
		swishes += int(g["homeSwishes"] if g["homeId"] == PLAYER else g["awaySwishes"])
		var margin := you - them
		# The biggest-margin win; with no win, the most points scored.
		var better: bool = best_game.is_empty() \
			or (margin > 0 and (int(best_game["margin"]) <= 0 or margin > int(best_game["margin"]))) \
			or (margin <= 0 and int(best_game["margin"]) <= 0 and you > int(best_game["you"]))
		if better:
			best_game = {"oppId": _opp(g), "you": you, "them": them, "margin": margin, "day": int(g.get("day", 0))}
	var h2h: Dictionary = summary["h2h"]
	# The toughest opponent: the lowest win share among those met; ties go
	# to the one with more losses, then roster order.
	var toughest := {}
	for id in team_ids:
		if id == PLAYER or not h2h.has(id):
			continue
		var r: Dictionary = h2h[id]
		var n: int = int(r["w"]) + int(r["l"])
		if n <= 0:
			continue
		var pct: float = float(r["w"]) / n
		if toughest.is_empty() or pct < float(toughest["pct"]) \
				or (is_equal_approx(pct, float(toughest["pct"])) and int(r["l"]) > int(toughest["l"])):
			toughest = {"oppId": str(id), "w": int(r["w"]), "l": int(r["l"]), "pct": pct}
	toughest.erase("pct")
	# How far off the playoff line (games behind the last spot); 0 when in.
	var spots := int(s.get("playoffTeams", int(league.get("playoff_teams", 4))))
	var table := Standings.table(team_ids, s["schedule"], int(s["seed"]))
	var games_out := 0.0
	var on_tiebreak := false
	if int(summary["finish"]) > spots and table.size() >= spots:
		var line: Dictionary = table[spots - 1]
		for row in table:
			if row["teamId"] == PLAYER:
				games_out = Standings.games_behind(line, row)
				on_tiebreak = games_out <= 0.0
	# The player's own final / semifinal series.
	var your_final := []
	var semi_opp := ""
	var semi_score := []
	for series in s.get("series", []):
		if series["highSeedId"] != PLAYER and series["lowSeedId"] != PLAYER:
			continue
		var high_you: bool = series["highSeedId"] == PLAYER
		var rec := [int(series["highWins"] if high_you else series["lowWins"]), int(series["lowWins"] if high_you else series["highWins"])]
		if series["round"] == "final":
			your_final = rec
		else:
			semi_opp = str(series["lowSeedId"] if high_you else series["highSeedId"])
			semi_score = rec
	return {
		"year": int(summary["year"]), "w": int(summary["w"]), "l": int(summary["l"]),
		"finish": int(summary["finish"]), "playoffResult": str(summary["playoffResult"]),
		"championId": str(summary["championId"]), "runnerUpId": str(summary["runnerUpId"]),
		"finalScore": summary["finalScore"], "yourFinal": your_final,
		"semiOpp": semi_opp, "semiScore": semi_score,
		"highPts": high, "avgPts": float(points) / games.size() if not games.is_empty() else 0.0,
		"bestStreak": int(summary["bestStreak"]), "swishes": swishes,
		"titles": int(Dictionary(doc.get("career", {})).get("championships", 0)),
		"bestGame": best_game, "toughest": toughest, "h2h": h2h,
		"gamesOut": games_out, "onTiebreak": on_tiebreak, "spots": spots,
		"earned": Campaign.earned(doc),
	}


## The NEW SEASON page's numbers, read after the rollover: the season that
## just ended (`doc.lastSeason`) and the fresh schedule's opening days.
static func opening_week(doc: Dictionary, league: Dictionary, n := 3) -> Dictionary:
	var s: Dictionary = doc["season"]
	var last: Dictionary = doc.get("lastSeason", {}) if doc.get("lastSeason", null) is Dictionary else {}
	var h2h: Dictionary = last.get("h2h", {})
	var games := []
	var days := Season.days(s)
	for day in range(1, mini(n, days) + 1):
		var g := Season.player_game_on(s, day, PLAYER)
		if g.is_empty():
			continue
		var opp := _opp(g)
		games.push_back({"day": day, "oppId": opp, "home": g["homeId"] == PLAYER,
			"h2h": {"w": int(h2h[opp]["w"]), "l": int(h2h[opp]["l"])} if h2h.has(opp) else {}})
	return {
		"oldYear": int(last.get("year", int(s["year"]) - 1)), "newYear": int(s["year"]),
		"defending": str(last.get("championId", "")) == PLAYER,
		"oldRecord": [int(last["w"]), int(last["l"])] if last.has("w") else [],
		"days": days, "teams": LeagueData.team_ids(league).size(),
		"spots": int(s.get("playoffTeams", int(league.get("playoff_teams", 4)))),
		"more_days": maxi(days - games.size(), 0), "games": games,
	}
