class_name Season
extends RefCounted
## Season orchestration for a compact league (ported from season.ts): a
## `rounds`-cycle round robin → playoffs → champion. Every game the player
## isn't in is quick-simmed; the player's regular-season games take a live
## result or a self-ratings sim; the player's playoff games are always live.
## State is a plain Dictionary so it round-trips through the save.

const PHASE_REGULAR := "regular"
const PHASE_PLAYOFFS := "playoffs"
const PHASE_DONE := "done"


static func create(league: Dictionary, team_ids: Array, year: int, seed_value: int) -> Dictionary:
	return {
		"leagueId": league["id"], "year": year, "seed": seed_value,
		"schedule": ScheduleGen.generate(team_ids, int(league.get("rounds", 2)),
			QuickSim.seed_from([seed_value, year, "schedule"]), "y%d" % year),
		"currentDay": 1, "phase": PHASE_REGULAR, "series": [], "championId": "",
		"seconds": float(league.get("heat_seconds", 90)), "otSeconds": float(league.get("ot_seconds", 20)),
		"ballReturn": float(league.get("ball_return_s", 1.0)),
		"playoffTeams": int(league.get("playoff_teams", 4)),
		"semisBestOf": int(league.get("semis_best_of", 3)), "finalBestOf": int(league.get("final_best_of", 5)),
		"cardHands": CardRewards.ai_hands(league, QuickSim.seed_from([seed_value, year, "cards"])),
	}


## The AI roster's card hands for this season (the fixed per-season
## allowance, docs/CARDS.md). Seasons saved before hands existed get theirs
## dealt on first use — from the season seed, so it is the same deal a fresh
## season would have had.
static func ensure_card_hands(state: Dictionary, league: Dictionary) -> void:
	if not state.has("cardHands"):
		state["cardHands"] = CardRewards.ai_hands(league, QuickSim.seed_from([int(state["seed"]), int(state["year"]), "cards"]))


## The shooter's hand for its next meeting with the player.
static func card_hand(state: Dictionary, shooter_id: String) -> Array:
	return Array(state.get("cardHands", {}).get(shooter_id, [])).duplicate()


## A shooter played these in a live heat: they leave its season hand.
static func consume_cards(state: Dictionary, shooter_id: String, ids: Array) -> void:
	if not state.has("cardHands") or not state["cardHands"].has(shooter_id):
		return
	var hand: Array = state["cardHands"][shooter_id]
	for id in ids:
		hand.erase(str(id))


static func days(state: Dictionary) -> int:
	return ScheduleGen.season_days(state["schedule"])


static func games_on(state: Dictionary, day: int) -> Array:
	return ScheduleGen.games_on(state["schedule"], day)


static func player_game_on(state: Dictionary, day: int, player_id: String) -> Dictionary:
	for g in games_on(state, day):
		if g["homeId"] == player_id or g["awayId"] == player_id:
			return g
	return {}


static func _fill_quick(g: Dictionary, home: AiRatings, away: AiRatings, state: Dictionary) -> void:
	var r := QuickSim.sim_heat(home, away, QuickSim.seed_from([state["seed"], state["year"], g["day"], g["id"]]),
		float(state["seconds"]), float(state["otSeconds"]), float(state.get("ballReturn", 1.0)))
	g["homeScore"] = r["home"]["points"]
	g["awayScore"] = r["away"]["points"]
	g["homeSwishes"] = r["home"]["swishes"]
	g["awaySwishes"] = r["away"]["swishes"]
	g["ot"] = r["ot"]
	g["played"] = true
	g["playedLive"] = false


static func _fill_live(g: Dictionary, player_is_home: bool, live: Dictionary) -> void:
	g["homeScore"] = live["playerScore"] if player_is_home else live["oppScore"]
	g["awayScore"] = live["oppScore"] if player_is_home else live["playerScore"]
	g["homeSwishes"] = live.get("playerSwishes", 0) if player_is_home else live.get("oppSwishes", 0)
	g["awaySwishes"] = live.get("oppSwishes", 0) if player_is_home else live.get("playerSwishes", 0)
	g["ot"] = int(live.get("ot", 0))
	g["played"] = true
	g["playedLive"] = true


## Resolve the current regular-season day. `ratings` maps every AI id to
## AiRatings; `player_self` sims the player's game when `live` is empty.
## live = {playerScore, oppScore, playerSwishes, oppSwishes, ot}.
static func resolve_day(state: Dictionary, ratings: Dictionary, player_id: String, player_self: AiRatings, live: Dictionary) -> void:
	if state["phase"] != PHASE_REGULAR:
		return
	for g in games_on(state, int(state["currentDay"])):
		if g["played"]:
			continue
		var mine: bool = g["homeId"] == player_id or g["awayId"] == player_id
		if mine and not live.is_empty():
			_fill_live(g, g["homeId"] == player_id, live)
		else:
			var home: AiRatings = player_self if g["homeId"] == player_id else ratings[g["homeId"]]
			var away: AiRatings = player_self if g["awayId"] == player_id else ratings[g["awayId"]]
			_fill_quick(g, home, away, state)
	state["currentDay"] = int(state["currentDay"]) + 1
	if int(state["currentDay"]) > days(state):
		start_playoffs(state, ratings.keys() + [player_id])


static func start_playoffs(state: Dictionary, team_ids: Array) -> void:
	state["phase"] = PHASE_PLAYOFFS
	var table := Standings.table(team_ids, state["schedule"], int(state["seed"]))
	state["series"] = Playoffs.build_semis(table, int(state["semisBestOf"]))


## The player's unfinished series, or {}.
static func player_series(state: Dictionary, player_id: String) -> Dictionary:
	for s in state["series"]:
		if s["winnerId"] == "" and (s["highSeedId"] == player_id or s["lowSeedId"] == player_id):
			return s
	return {}


static func _series_game(s: Dictionary, game_no: int, day_base: int, high_score: int, low_score: int,
		high_sw: int, low_sw: int, ot: int, live: bool) -> Dictionary:
	var g := ScheduleGen.game_record("%s-g%d" % [s["id"], game_no], day_base + game_no, s["highSeedId"], s["lowSeedId"])
	g["homeScore"] = high_score
	g["awayScore"] = low_score
	g["homeSwishes"] = high_sw
	g["awaySwishes"] = low_sw
	g["ot"] = ot
	g["played"] = true
	g["playedLive"] = live
	return g


## Resolve one playoff step: the player's live series game (if any), then every
## AI-only series to completion, advancing rounds and crowning the champion.
static func resolve_playoff_step(state: Dictionary, ratings: Dictionary, player_id: String, live: Dictionary) -> void:
	if state["phase"] != PHASE_PLAYOFFS:
		return
	var day_base := days(state)
	var mine := player_series(state, player_id)
	if not mine.is_empty() and not live.is_empty():
		var high: bool = mine["highSeedId"] == player_id
		var game_no: int = int(mine["highWins"]) + int(mine["lowWins"]) + 1
		var hs: int = live["playerScore"] if high else live["oppScore"]
		var ls: int = live["oppScore"] if high else live["playerScore"]
		Playoffs.record_series_game(mine, hs, ls)
		mine["games"].push_back(_series_game(mine, game_no, day_base, hs, ls,
			int(live.get("playerSwishes", 0) if high else live.get("oppSwishes", 0)),
			int(live.get("oppSwishes", 0) if high else live.get("playerSwishes", 0)), int(live.get("ot", 0)), true))
	for pass_ in 4:
		for s in state["series"]:
			if s["winnerId"] != "" or s["highSeedId"] == player_id or s["lowSeedId"] == player_id:
				continue
			var game_no: int = int(s["highWins"]) + int(s["lowWins"])
			while s["winnerId"] == "":
				game_no += 1
				var r := QuickSim.sim_heat(ratings[s["highSeedId"]], ratings[s["lowSeedId"]],
					QuickSim.seed_from([state["seed"], s["id"], game_no]), float(state["seconds"]), float(state["otSeconds"]), float(state.get("ballReturn", 1.0)))
				Playoffs.record_series_game(s, r["home"]["points"], r["away"]["points"])
				s["games"].push_back(_series_game(s, game_no, day_base, r["home"]["points"], r["away"]["points"],
					r["home"]["swishes"], r["away"]["swishes"], r["ot"], false))
		var created := Playoffs.advance_bracket(state["series"], int(state["finalBestOf"]))
		for c in created:
			state["series"].push_back(c)
		var champ := Playoffs.champion(state["series"])
		if champ != "":
			state["championId"] = champ
			state["phase"] = PHASE_DONE
			return
		if created.is_empty():
			break
