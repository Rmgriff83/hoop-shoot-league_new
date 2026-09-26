class_name LeagueSummary
extends RefCounted
## The league's state as home-page copy (docs/HOME.md, design "Home League
## Context v2"), pure and headless: the LEAGUE card's header, three numbers
## and next-game line; the floating layer's YOUR SPOT, COMING UP and THIS
## SEASON; the one-line status the ticker and the zone read. Everything is
## computed from an App.league_states() row ({league, unlocked, doc}) or a
## campaign doc + league cfg — no nodes, so tests/test_home_ui.gd drives it
## through every phase.

const PLAYER := Campaign.PLAYER


# ---- the one-liner (the ticker, the zone) -------------------------------------


## `NEW LEAGUE`, `LOCKED · TOP 4 IN THE ARCADE LEAGUE`, `SEASON 1 · DAY 1 ·
## TIP OFF`, `SEASON 2 · DAY 4 · 3RD PLACE`, `SEASON 2 · SEMIS 1-0`,
## `SEASON 2 · CHAMPIONS`, `SEASON 2 · DONE · 5TH PLACE`.
static func line(state: Dictionary) -> String:
	if state.is_empty():
		return "NEW LEAGUE"
	var cfg: Dictionary = state.get("league", {})
	if not bool(state.get("unlocked", true)):
		return locked_line(cfg)
	var doc: Dictionary = state.get("doc", {})
	if doc.is_empty():
		return "NEW LEAGUE"
	var season: Dictionary = doc["season"]
	var head := "SEASON %d" % year_of(doc)
	match str(season["phase"]):
		Season.PHASE_REGULAR:
			var day := int(season["currentDay"])
			var p := place(cfg, season)
			if day <= 1 and p == 0:
				return "%s · DAY 1 · TIP OFF" % head
			return "%s · DAY %d · %s PLACE" % [head, day, TickerText.ordinal(p)] if p > 0 else "%s · DAY %d" % [head, day]
		Season.PHASE_PLAYOFFS:
			var mine := Season.player_series(season, PLAYER)
			if mine.is_empty():
				return "%s · PLAYOFFS · OUT" % head
			var wl := series_record(mine)
			return "%s · %s %d-%d" % [head, "FINAL" if str(mine.get("round", "")) == "final" else "SEMIS", wl[0], wl[1]]
		_:
			if str(season.get("championId", "")) == PLAYER:
				return "%s · CHAMPIONS" % head
			var summary := Campaign.season_summary(doc, cfg)
			return "%s · DONE · %s PLACE" % [head, TickerText.ordinal(int(summary["finish"]))]


static func locked_line(cfg: Dictionary) -> String:
	var rule: Dictionary = cfg.get("unlock", {})
	var parent := LeagueData.league(str(rule.get("league", "")))
	return "LOCKED · TOP %d IN THE %s" % [int(rule.get("min_finish", 4)), str(parent.get("name", "LEAGUE")).to_upper()]


static func year_of(doc: Dictionary) -> int:
	return int(doc.get("year", Dictionary(doc.get("season", {})).get("year", 1)))


# ---- the LEAGUE card -------------------------------------------------------------


## The card's copy: {top, sub, titles, stats: [{v, l}]×3 (or []), next_left,
## next_right, line}. Season: RECORD · PLACE · STREAK, `NEXT · @ NAME` /
## `DAY 4 OF 14`; playoffs: SERIES · ROUND · SEED, `SEMI 2 · GAME 3`; a new
## league counts down to tip-off; locked and finished seasons say so.
static func card(state: Dictionary) -> Dictionary:
	var cfg: Dictionary = state.get("league", {})
	var out := {"top": str(cfg.get("name", "LEAGUE")).to_upper(), "sub": "NEW LEAGUE", "titles": 0,
		"stats": [], "next_left": "", "next_right": "", "line": line(state)}
	if state.is_empty():
		return out
	if not bool(state.get("unlocked", true)):
		out["sub"] = "LOCKED"
		out["next_left"] = locked_line(cfg).trim_prefix("LOCKED · ")
		out["next_right"] = "TO UNLOCK"
		return out
	var doc: Dictionary = state.get("doc", {})
	if doc.is_empty():
		out["stats"] = [{"v": "0-0", "l": "RECORD"}, {"v": "-", "l": "PLACE"}, {"v": "-", "l": "STREAK"}]
		out["next_left"] = "TIP OFF · DAY 1"
		# A round robin: every cycle is (teams − 1) days, and the roster is the teams but you.
		out["next_right"] = "DAY 1 OF %d" % (int(cfg.get("rounds", 2)) * Array(cfg.get("roster", [])).size())
		return out
	var s: Dictionary = doc["season"]
	var year := year_of(doc)
	out["titles"] = int(Dictionary(doc.get("career", {})).get("championships", 0))
	var rec := record(s)
	match str(s["phase"]):
		Season.PHASE_REGULAR:
			out["sub"] = "SEASON %d" % year
			var p := place(cfg, s)
			out["stats"] = [{"v": "%d-%d" % rec, "l": "RECORD"}, {"v": TickerText.ordinal(p) if p > 0 else "-", "l": "PLACE"},
				{"v": streak_text(s), "l": "STREAK"}]
			var day := int(s["currentDay"])
			var g := Season.player_game_on(s, day, PLAYER)
			out["next_left"] = "NEXT · %s" % vs_text(g) if not g.is_empty() else "NEXT · DAY %d" % day
			out["next_right"] = "DAY %d OF %d" % [day, Season.days(s)]
		Season.PHASE_PLAYOFFS:
			out["sub"] = "SEASON %d · PLAYOFFS" % year
			var mine := Season.player_series(s, PLAYER)
			var seed := place(cfg, s)
			if mine.is_empty():
				out["stats"] = [{"v": "%d-%d" % rec, "l": "RECORD"}, {"v": TickerText.ordinal(seed) if seed > 0 else "-", "l": "PLACE"},
					{"v": "OUT", "l": "PLAYOFFS"}]
				out["next_left"] = "OUT OF THE PLAYOFFS"
				out["next_right"] = "SEASON %d" % year
			else:
				var wl := series_record(mine)
				out["stats"] = [{"v": "%d-%d" % wl, "l": "SERIES"}, {"v": round_name(mine), "l": "ROUND"}, {"v": str(seed), "l": "SEED"}]
				out["next_left"] = "NEXT · %s %s" % ["VS" if mine["highSeedId"] == PLAYER else "@", team_name(opponent_in(mine))]
				out["next_right"] = "%s · GAME %d" % [series_label(s, mine), wl[0] + wl[1] + 1]
		_:
			out["sub"] = "SEASON %d · OVER" % year
			var summ := Campaign.season_summary(doc, cfg)
			var champ := str(s.get("championId", "")) == PLAYER
			out["stats"] = [{"v": "%d-%d" % rec, "l": "RECORD"}, {"v": TickerText.ordinal(int(summ["finish"])), "l": "FINISH"},
				{"v": "CHAMPS" if champ else playoff_short(str(summ["playoffResult"])), "l": "PLAYOFFS"}]
			out["next_left"] = "SEASON %d AWAITS" % (year + 1)
			out["next_right"] = "START INSIDE"
	return out


# ---- the floating layer ----------------------------------------------------------


## TABLE: {cap, big, line1, line2}. Season: `YOUR SPOT` / `3RD` / `2-1 · 1.0
## GB` / `IN A PLAYOFF SPOT`; playoffs: `PLAYOFFS` / `SEMI` / `SERIES 1-1` /
## `WIN GAME 3 TO REACH THE FINAL`.
static func spot(doc: Dictionary, cfg: Dictionary) -> Dictionary:
	var s: Dictionary = doc["season"]
	var spots := int(s.get("playoffTeams", 4))
	var rec := record(s)
	match str(s["phase"]):
		Season.PHASE_REGULAR:
			var p := place(cfg, s)
			if p == 0:
				return {"cap": "YOUR SPOT", "big": "-", "line1": "0-0", "line2": "TIP OFF · DAY 1"}
			var table := Standings.table(LeagueData.team_ids(cfg), s["schedule"], int(s["seed"]))
			var mine: Dictionary = table[p - 1]
			var gb := Standings.games_behind(table[0], mine)
			var line1 := "%d-%d · %s" % [rec[0], rec[1], "LEADING" if p == 1 else "%.1f GB" % gb]
			var line2 := "IN A PLAYOFF SPOT"
			if p > spots:
				var back := Standings.games_behind(table[spots - 1], mine)
				line2 = "%.1f BACK OF THE LINE" % back if back > 0.0 else "LEVEL WITH THE LINE"
			return {"cap": "YOUR SPOT", "big": TickerText.ordinal(p), "line1": line1, "line2": line2}
		Season.PHASE_PLAYOFFS:
			var mine := Season.player_series(s, PLAYER)
			if mine.is_empty():
				var seed := place(cfg, s)
				var summ := Campaign.season_summary(doc, cfg)
				var how := "OUT IN THE SEMIS" if str(summ["playoffResult"]) == "semifinal" else "MISSED THE PLAYOFFS"
				return {"cap": "PLAYOFFS", "big": "OUT", "line1": "SEEDED %s" % TickerText.ordinal(seed) if seed > 0 else "", "line2": how}
			var wl := series_record(mine)
			var final_ := str(mine.get("round", "")) == "final"
			var need: int = Playoffs.needed_wins(mine) - int(wl[0])
			var g: int = int(wl[0]) + int(wl[1]) + 1
			var line2 := ("WIN GAME %d TO %s" % [g, "TAKE THE TITLE" if final_ else "REACH THE FINAL"]) if need <= 1 \
				else "%d MORE WIN%s TO %s" % [need, "" if need == 1 else "S", "THE TITLE" if final_ else "THE FINAL"]
			return {"cap": "PLAYOFFS", "big": round_name(mine), "line1": "SERIES %d-%d" % wl, "line2": line2}
		_:
			var summ := Campaign.season_summary(doc, cfg)
			var champ := str(s.get("championId", "")) == PLAYER
			return {"cap": "SEASON %d" % year_of(doc), "big": "1ST" if champ else TickerText.ordinal(int(summ["finish"])),
				"line1": "%d-%d" % rec, "line2": "CHAMPIONS" if champ else playoff_long(str(summ["playoffResult"]))}


## SCHED: the next `n` games as [{day, name, tag}], blanks past the end.
## Season: `D4 · @ OLLIE · TODAY`, `D5 · VS JUNIE`; playoffs: `SEMI 3 · @
## OLLIE · NEXT`, `FINAL 1 · VS PACO · IF YOU WIN`.
static func upcoming(doc: Dictionary, cfg: Dictionary, n := 3) -> Array:
	var s: Dictionary = doc["season"]
	var out := []
	match str(s["phase"]):
		Season.PHASE_REGULAR:
			var day := int(s["currentDay"])
			for g in s["schedule"]:
				if int(g["day"]) < day or (g["homeId"] != PLAYER and g["awayId"] != PLAYER) or g["played"]:
					continue
				out.push_back({"day": "D%d" % int(g["day"]), "name": vs_text(g, true), "tag": "TODAY" if int(g["day"]) == day else ""})
				if out.size() >= n:
					break
		Season.PHASE_PLAYOFFS:
			var mine := Season.player_series(s, PLAYER)
			if not mine.is_empty():
				var wl := series_record(mine)
				var home: bool = mine["highSeedId"] == PLAYER
				out.push_back({"day": "%s %d" % [series_label(s, mine), wl[0] + wl[1] + 1],
					"name": "%s %s" % ["VS" if home else "@", short_name(opponent_in(mine))], "tag": "NEXT"})
				if str(mine.get("round", "")) != "final":
					var other := other_semi(s, mine)
					var who := str(other.get("winnerId", "")) if not other.is_empty() else ""
					out.push_back({"day": "FINAL 1", "name": "VS %s" % (short_name(who) if who != "" else "TBD"), "tag": "IF YOU WIN"})
			else:
				out.push_back({"day": "OUT", "name": "SEASON %d" % year_of(doc), "tag": "PLAYOFFS"})
		_:
			out.push_back({"day": "NEXT", "name": "SEASON %d" % (year_of(doc) + 1), "tag": "START INSIDE"})
	while out.size() < n:
		out.push_back({"day": "", "name": "", "tag": ""})
	if out.size() > n:
		out.resize(n)
	return out


## STATS: this season's RECORD, HIGH PTS and STREAK.
static func season_stats(doc: Dictionary) -> Array:
	var s: Dictionary = doc["season"]
	var high := 0
	for g in all_player_games(s):
		high = maxi(high, int(g["homeScore"] if g["homeId"] == PLAYER else g["awayScore"]))
	return [{"v": "%d-%d" % record(s), "l": "RECORD"}, {"v": str(high), "l": "HIGH PTS"}, {"v": streak_text(s), "l": "STREAK"}]


# ---- pieces ----------------------------------------------------------------------


## The player's standings seed (0 before any game).
static func place(cfg: Dictionary, season: Dictionary) -> int:
	var played := false
	for g in season.get("schedule", []):
		if g.get("played", false):
			played = true
			break
	if not played:
		return 0
	for row in Standings.table(LeagueData.team_ids(cfg), season["schedule"], int(season["seed"])):
		if row["teamId"] == PLAYER:
			return int(row["seed"])
	return 0


## The player's regular-season [w, l].
static func record(season: Dictionary) -> Array:
	var w := 0
	var l := 0
	for g in season.get("schedule", []):
		if g["played"] and (g["homeId"] == PLAYER or g["awayId"] == PLAYER):
			if Standings.winner_of(g) == PLAYER:
				w += 1
			else:
				l += 1
	return [w, l]


## Every played game of the player's, season and playoffs.
static func all_player_games(season: Dictionary) -> Array:
	var out := []
	for g in season.get("schedule", []):
		if g["played"] and (g["homeId"] == PLAYER or g["awayId"] == PLAYER):
			out.push_back(g)
	for series in season.get("series", []):
		if series["highSeedId"] == PLAYER or series["lowSeedId"] == PLAYER:
			for g in series.get("games", []):
				out.push_back(g)
	return out


## `W2` / `L1`, `-` before any game.
static func streak_text(season: Dictionary) -> String:
	var st := Standings.current_streak(PLAYER, season.get("schedule", []))
	return "%s%d" % [st["type"], int(st["count"])] if not st.is_empty() else "-"


## [your wins, their wins] in a series.
static func series_record(series: Dictionary) -> Array:
	var high: bool = series["highSeedId"] == PLAYER
	return [int(series["highWins"] if high else series["lowWins"]), int(series["lowWins"] if high else series["highWins"])]


static func opponent_in(series: Dictionary) -> String:
	return str(series["lowSeedId"] if series["highSeedId"] == PLAYER else series["highSeedId"])


static func round_name(series: Dictionary) -> String:
	return "FINAL" if str(series.get("round", "")) == "final" else "SEMI"


## `SEMI 1` / `SEMI 2` (its place among the semis) or `FINAL`.
static func series_label(season: Dictionary, series: Dictionary) -> String:
	if str(series.get("round", "")) == "final":
		return "FINAL"
	var n := 0
	for s in season.get("series", []):
		if str(s.get("round", "")) == "semifinal":
			n += 1
			if s["id"] == series["id"]:
				return "SEMI %d" % n
	return "SEMI"


static func other_semi(season: Dictionary, mine: Dictionary) -> Dictionary:
	for s in season.get("series", []):
		if str(s.get("round", "")) == "semifinal" and s["id"] != mine["id"]:
			return s
	return {}


## `@ OLLIE KNOTS` / `VS OLLIE KNOTS` for a schedule game (short: first name only).
static func vs_text(g: Dictionary, short := false) -> String:
	var home: bool = g["homeId"] == PLAYER
	var opp: String = g["awayId"] if home else g["homeId"]
	return "%s %s" % ["VS" if home else "@", short_name(opp) if short else team_name(opp)]


static func team_name(id: String) -> String:
	if id == PLAYER:
		return "YOU"
	return str(LeagueData.shooter(id).get("name", id)).to_upper()


## The first word of a shooter's name, for the compact upcoming cards.
static func short_name(id: String) -> String:
	var full := team_name(id)
	var sp := full.find(" ")
	return full.substr(0, sp) if sp > 0 else full


static func playoff_short(result: String) -> String:
	match result:
		"champion":
			return "CHAMPS"
		"runner_up":
			return "FINAL"
		"semifinal":
			return "SEMIS"
		_:
			return "MISSED"


static func playoff_long(result: String) -> String:
	match result:
		"champion":
			return "CHAMPIONS"
		"runner_up":
			return "RUNNERS-UP"
		"semifinal":
			return "OUT IN THE SEMIS"
		_:
			return "MISSED THE PLAYOFFS"
