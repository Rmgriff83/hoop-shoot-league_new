class_name TickerText
extends RefCounted
## Text for the cage's league ribbon board (game/view/led_board.gd, ticker mode).
##
## Pure static string building, headless and testable, which matters more here
## than usual for a presentation concern: the LED is a 48x8 matrix with a 3x5
## font holding ONLY 0-9, A-Z, space and `! : + - x *`. _draw_text silently
## drops anything else, so a stray character is an invisible bug rather than a
## crash. Every existing league formatter (heat_screen's old sash_line, the
## chalkboard, the league hub) uses `·`, `★`, `✓`, `✗`, `→` and emoji — none of
## which render. Hence this module, and hence is_font_safe(), which the tests
## run over everything generated here.
##
## Data comes from the same calls the dashboard and the beach banner use:
## App.league_cfg / App.league_doc, Standings.table, Season.player_series.

## Segment separator. A middot would be the natural choice and is exactly the
## kind of character that renders as a gap, so the ribbon uses the `*` glyph.
const SEP := "   *   "


## Three-letter code for a team. data/shooters.json has no abbreviation field —
## only ids like "brickport" / "thunder-mesa" and full names like "Mo Mortar" —
## so one is derived from the id, which doubles as the hometown.
static func abbr(team_id: String) -> String:
	if team_id == "player":
		return "YOU"
	var letters := ""
	for c in team_id.to_upper():
		if c >= "A" and c <= "Z":
			letters += c
		if letters.length() == 3:
			break
	while letters.length() < 3:
		letters += "X"
	return letters


## Is every character renderable by LedBoard's font? Space is always fine.
static func is_font_safe(text: String) -> bool:
	for c in text.to_upper():
		if c != " " and not LedBoard.FONT.has(c):
			return false
	return true


static func ordinal(n: int) -> String:
	var suffix := "TH"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "ST"
			2: suffix = "ND"
			3: suffix = "RD"
	return "%d%s" % [n, suffix]


## The ribbon's segments during a league heat: who is playing, where the player
## stands (or the series, in the playoffs), the live score, then the table.
static func league_items(cfg: Dictionary, doc: Dictionary, you := -1, opp := -1,
		opp_id := "") -> PackedStringArray:
	var out := PackedStringArray()
	var league_name := str(cfg.get("name", "LEAGUE")).to_upper()
	out.push_back(_safe(league_name))
	if doc.is_empty() or not doc.has("season"):
		return out
	var season: Dictionary = doc["season"]
	var ids := LeagueData.team_ids(cfg)
	var table := Standings.table(ids, season["schedule"], int(season["seed"]))

	if season.get("phase", "") == Season.PHASE_PLAYOFFS:
		var s := Season.player_series(season, Campaign.PLAYER)
		if not s.is_empty():
			var high: bool = s["highSeedId"] == Campaign.PLAYER
			var w: int = int(s["highWins"]) if high else int(s["lowWins"])
			var l: int = int(s["lowWins"]) if high else int(s["highWins"])
			var round_name := "SEMIS" if s["round"] == "semifinal" else "FINAL"
			out.push_back("%s GAME %d" % [round_name, int(s["highWins"]) + int(s["lowWins"]) + 1])
			out.push_back("SERIES %d-%d" % [w, l])
	elif str(season.get("championId", "")) != "":
		out.push_back("CHAMPS" if season["championId"] == Campaign.PLAYER else "SEASON OVER")
	else:
		for i in table.size():
			if table[i]["teamId"] == Campaign.PLAYER:
				out.push_back("YOU %s  %d-%d" % [ordinal(i + 1), int(table[i]["w"]), int(table[i]["l"])])
				break

	if you >= 0 and opp >= 0:
		out.push_back("YOU %d  %s %d" % [you, abbr(opp_id), opp])
	for i in table.size():
		var row: Dictionary = table[i]
		out.push_back("%d %s %d-%d" % [i + 1, abbr(str(row["teamId"])), int(row["w"]), int(row["l"])])
	return out


## Attract copy outside league play, so the ribbon is never dead.
static func arcade_items(best := 0) -> PackedStringArray:
	var out := PackedStringArray()
	if best > 0:
		out.push_back("HIGH SCORE %d" % best)
	out.push_back("HOOP SHOOT")
	out.push_back("SWISH FOR 2")
	out.push_back("KEEP THE STREAK ALIVE")
	return out


## Strip anything the LED cannot draw, so a stray character shortens a word
## rather than punching a hole in it.
static func _safe(text: String) -> String:
	var out := ""
	for c in text.to_upper():
		if c == " " or LedBoard.FONT.has(c):
			out += c
	return out
