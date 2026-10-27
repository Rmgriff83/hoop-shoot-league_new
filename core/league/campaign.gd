class_name Campaign
extends RefCounted
## Per-league campaign document helpers (pure): identity, the current season,
## the player's self-ratings, career totals/highs and each shooter's record.
## One doc per league lives in the save's `campaign` part.

const PLAYER := LeagueData.PLAYER_ID


static func new_doc(league: Dictionary, seed_value: int, now_ms: int) -> Dictionary:
	var team_ids := LeagueData.team_ids(league)
	return {
		"id": "", "leagueId": league["id"], "createdAt": now_ms, "lastPlayedAt": now_ms,
		"year": 1, "season": Season.create(league, team_ids, 1, seed_value),
		"selfRatings": PlayerRatings.init_self(),
		"career": {
			"seasons": [], "championships": 0,
			"totals": {"games": 0, "wins": 0, "losses": 0, "points": 0, "makes": 0, "swishes": 0, "shots": 0},
			"highs": {"points": 0, "swishes": 0, "streak": 0},
		},
		"shooterCareers": {},
	}


static func ratings_map(league: Dictionary) -> Dictionary:
	return LeagueData.league_ratings(league)


## The opponent id the player faces next (regular-season day or playoff
## series), "" when the season is over or the player is out of the playoffs.
static func next_opponent(doc: Dictionary) -> String:
	var s: Dictionary = doc["season"]
	if s["phase"] == Season.PHASE_REGULAR:
		var g := Season.player_game_on(s, int(s["currentDay"]), PLAYER)
		if g.is_empty():
			return ""
		return g["awayId"] if g["homeId"] == PLAYER else g["homeId"]
	if s["phase"] == Season.PHASE_PLAYOFFS:
		var mine := Season.player_series(s, PLAYER)
		if mine.is_empty():
			return ""
		return mine["lowSeedId"] if mine["highSeedId"] == PLAYER else mine["highSeedId"]
	return ""


## Is the player still alive in the playoffs (has an unfinished series)?
static func player_alive(doc: Dictionary) -> bool:
	var s: Dictionary = doc["season"]
	return s["phase"] == Season.PHASE_PLAYOFFS and not Season.player_series(s, PLAYER).is_empty()


## Heat.result() → the season's live-result shape.
static func live_from_heat(result: Dictionary) -> Dictionary:
	var sides: Dictionary = result.get("sides", {})
	return {
		"playerScore": int(result.get("player_score", 0)), "oppScore": int(result.get("ai_score", 0)),
		"playerSwishes": int(sides.get("player", {}).get("swishes", 0)),
		"oppSwishes": int(sides.get("ai", {}).get("swishes", 0)), "ot": int(result.get("ot", 0)),
	}


## Fold a live heat into the season and the career.
static func apply_live_result(doc: Dictionary, league: Dictionary, result: Dictionary, now_ms: int) -> void:
	var live := live_from_heat(result)
	var s: Dictionary = doc["season"]
	var ratings := ratings_map(league)
	# The opponent's card plays leave its season hand (the AI's cards are
	# consumed like the player's). Read the opponent before the day advances.
	Season.ensure_card_hands(s, league)
	Season.consume_cards(s, next_opponent(doc), Array(result.get("sides", {}).get("ai", {}).get("cardsPlayed", [])))
	if s["phase"] == Season.PHASE_REGULAR:
		Season.resolve_day(s, ratings, PLAYER, PlayerRatings.as_ai(doc["selfRatings"]), live)
	elif s["phase"] == Season.PHASE_PLAYOFFS:
		Season.resolve_playoff_step(s, ratings, PLAYER, live)
	var you: Dictionary = result.get("sides", {}).get("player", {})
	var totals: Dictionary = doc["career"]["totals"]
	totals["games"] += 1
	if result.get("won", false):
		totals["wins"] += 1
	else:
		totals["losses"] += 1
	totals["points"] += int(you.get("score", 0))
	totals["makes"] += int(you.get("makes", 0))
	totals["swishes"] += int(you.get("swishes", 0))
	totals["shots"] += int(you.get("attempts", 0))
	var highs: Dictionary = doc["career"]["highs"]
	highs["points"] = maxi(int(highs["points"]), int(you.get("score", 0)))
	highs["swishes"] = maxi(int(highs["swishes"]), int(you.get("swishes", 0)))
	highs["streak"] = maxi(int(highs["streak"]), int(you.get("bestStreak", 0)))
	var best: Dictionary = s.get("best", {"streak": 0})
	best["streak"] = maxi(int(best.get("streak", 0)), int(you.get("bestStreak", 0)))
	s["best"] = best
	PlayerRatings.update_self(doc["selfRatings"], {"makes": you.get("makes", 0), "swishes": you.get("swishes", 0), "shots": you.get("attempts", 0)})
	doc["lastPlayedAt"] = now_ms
	maybe_finish_season(doc, league)


## This season's take (design 39: the wrap-up's SEASON EARNINGS): the
## match's XP (title jump included) and tickets, kept on the season doc.
static func note_earned(doc: Dictionary, xp: int, tickets: int) -> void:
	var s: Dictionary = doc["season"]
	var e: Dictionary = s.get("earned", {"xp": 0, "tickets": 0})
	e["xp"] = int(e.get("xp", 0)) + xp
	e["tickets"] = int(e.get("tickets", 0)) + tickets
	s["earned"] = e


static func earned(doc: Dictionary) -> Dictionary:
	var e: Dictionary = Dictionary(doc.get("season", {})).get("earned", {})
	return {"xp": int(e.get("xp", 0)), "tickets": int(e.get("tickets", 0))}


## The player's record against every opponent this season, regular season
## and playoffs: {opp_id: {w, l}} (opponents never met are absent).
static func head_to_head_all(season: Dictionary, player_id: String) -> Dictionary:
	var out := {}
	var games: Array = Array(season.get("schedule", [])).duplicate()
	for series in season.get("series", []):
		if series["highSeedId"] == player_id or series["lowSeedId"] == player_id:
			games.append_array(series.get("games", []))
	for g in games:
		if not g.get("played", false):
			continue
		if g["homeId"] != player_id and g["awayId"] != player_id:
			continue
		var opp: String = str(g["awayId"] if g["homeId"] == player_id else g["homeId"])
		var r: Dictionary = out.get(opp, {"w": 0, "l": 0})
		if Standings.winner_of(g) == player_id:
			r["w"] += 1
		else:
			r["l"] += 1
		out[opp] = r
	return out


## The wrap-up (design 39c/e/f) is owed once a season is done, until shown.
static func wrap_pending(doc: Dictionary) -> bool:
	var s: Dictionary = doc.get("season", {})
	return s.get("phase", "") == Season.PHASE_DONE and not bool(s.get("wrapSeen", false))


static func mark_wrap_seen(doc: Dictionary) -> void:
	doc["season"]["wrapSeen"] = true


## Sim the current regular-season day (the player's game from self-ratings),
## or advance AI-only playoff series. Does nothing while the player has a live
## playoff game pending.
static func sim_step(doc: Dictionary, league: Dictionary) -> void:
	var s: Dictionary = doc["season"]
	var ratings := ratings_map(league)
	if s["phase"] == Season.PHASE_REGULAR:
		var g := Season.player_game_on(s, int(s["currentDay"]), PLAYER)
		Season.resolve_day(s, ratings, PLAYER, PlayerRatings.as_ai(doc["selfRatings"]), {})
		if not g.is_empty():
			var totals: Dictionary = doc["career"]["totals"]
			totals["games"] += 1
			var won: bool = (g["homeId"] == PLAYER) == (int(g["homeScore"]) > int(g["awayScore"]))
			totals["wins" if won else "losses"] += 1
	elif s["phase"] == Season.PHASE_PLAYOFFS:
		if not Season.player_series(s, PLAYER).is_empty():
			return
		Season.resolve_playoff_step(s, ratings, PLAYER, {})
	maybe_finish_season(doc, league)


## Sim to the playoffs (or to the end when the player is out).
static func sim_to_playoffs(doc: Dictionary, league: Dictionary) -> void:
	var guard := 0
	while doc["season"]["phase"] == Season.PHASE_REGULAR and guard < 64:
		sim_step(doc, league)
		guard += 1


## The player's regular-season finish (seed) and playoff result for a season.
static func season_summary(doc: Dictionary, league: Dictionary) -> Dictionary:
	var s: Dictionary = doc["season"]
	var team_ids := LeagueData.team_ids(league)
	var table := Standings.table(team_ids, s["schedule"], int(s["seed"]))
	var finish := 0
	var w := 0
	var l := 0
	for row in table:
		if row["teamId"] == PLAYER:
			finish = int(row["seed"])
			w = int(row["w"])
			l = int(row["l"])
	var playoff_result := "missed"
	for series in s["series"]:
		if series["highSeedId"] == PLAYER or series["lowSeedId"] == PLAYER:
			if series["round"] == "final":
				playoff_result = "champion" if series["winnerId"] == PLAYER else "runner_up"
			elif playoff_result == "missed":
				playoff_result = "semifinal"
	# The final's loser and score (design 39: CHAMPION · 2-1 / RUNNER-UP).
	var runner_up := ""
	var final_score := [0, 0]
	var final_ := Playoffs.find(s["series"], "final")
	if not final_.is_empty() and str(final_.get("winnerId", "")) != "":
		var champ_high: bool = final_["winnerId"] == final_["highSeedId"]
		runner_up = str(final_["lowSeedId"] if champ_high else final_["highSeedId"])
		final_score = [int(final_["highWins"]), int(final_["lowWins"])] if champ_high else [int(final_["lowWins"]), int(final_["highWins"])]
	return {"year": int(s["year"]), "w": w, "l": l, "finish": finish, "playoffResult": playoff_result,
		"championId": s["championId"], "runnerUpId": runner_up, "finalScore": final_score,
		"bestStreak": int(Dictionary(s.get("best", {})).get("streak", 0)), "h2h": head_to_head_all(s, PLAYER)}


## When the season is done, fold it into the career and every shooter's record.
static func maybe_finish_season(doc: Dictionary, league: Dictionary) -> void:
	var s: Dictionary = doc["season"]
	if s["phase"] != Season.PHASE_DONE or s.get("folded", false):
		return
	var summary := season_summary(doc, league)
	doc["career"]["seasons"].push_back(summary)
	if s["championId"] == PLAYER:
		doc["career"]["championships"] += 1
	var rows := Standings.compute(LeagueData.team_ids(league), s["schedule"])
	for id in rows:
		if id == PLAYER:
			continue
		var c: Dictionary = doc["shooterCareers"].get(id, {"w": 0, "l": 0, "championships": 0, "seasons": 0})
		c["w"] += int(rows[id]["w"])
		c["l"] += int(rows[id]["l"])
		c["seasons"] += 1
		if s["championId"] == id:
			c["championships"] += 1
		doc["shooterCareers"][id] = c
	s["folded"] = true


## Roll to the next season. The old season's summary (with its earnings)
## stays on the doc as `lastSeason` for the NEW SEASON page (design 39d:
## "YOU WENT 1-2 VS THEM", DEFENDING CHAMPS, the struck-out record) and on
## the career's entry.
static func start_next_season(doc: Dictionary, league: Dictionary) -> void:
	var s: Dictionary = doc["season"]
	if s["phase"] != Season.PHASE_DONE:
		return
	var last := season_summary(doc, league)
	last["earned"] = earned(doc)
	doc["lastSeason"] = last
	var seasons: Array = doc["career"]["seasons"]
	if not seasons.is_empty() and int(Dictionary(seasons[-1]).get("year", 0)) == int(s["year"]):
		seasons[-1]["earned"] = earned(doc)
	doc["year"] = int(doc["year"]) + 1
	doc["season"] = Season.create(league, LeagueData.team_ids(league), int(doc["year"]),
		QuickSim.seed_from([s["seed"], "next", doc["year"]]))
