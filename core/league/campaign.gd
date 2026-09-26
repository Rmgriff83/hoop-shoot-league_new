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
	PlayerRatings.update_self(doc["selfRatings"], {"makes": you.get("makes", 0), "swishes": you.get("swishes", 0), "shots": you.get("attempts", 0)})
	doc["lastPlayedAt"] = now_ms
	maybe_finish_season(doc, league)


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
	return {"year": int(s["year"]), "w": w, "l": l, "finish": finish, "playoffResult": playoff_result,
		"championId": s["championId"]}


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


static func start_next_season(doc: Dictionary, league: Dictionary) -> void:
	var s: Dictionary = doc["season"]
	if s["phase"] != Season.PHASE_DONE:
		return
	doc["year"] = int(doc["year"]) + 1
	doc["season"] = Season.create(league, LeagueData.team_ids(league), int(doc["year"]),
		QuickSim.seed_from([s["seed"], "next", doc["year"]]))


## Does the player satisfy this league's unlock rule given their campaigns
## ({league_id: doc})? A null rule is always open.
static func unlock_ok(league: Dictionary, campaigns: Dictionary) -> bool:
	var rule: Variant = league.get("unlock", null)
	if rule == null:
		return true
	var doc: Dictionary = campaigns.get(str(rule["league"]), {})
	if doc.is_empty():
		return false
	for summary in doc["career"]["seasons"]:
		if int(summary["finish"]) > 0 and int(summary["finish"]) <= int(rule["min_finish"]):
			return true
	return false
