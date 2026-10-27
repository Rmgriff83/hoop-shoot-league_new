class_name SeasonCopy
extends RefCounted
## The season moments' words (design "Season Moments" 39c/e/f and 39d,
## docs/LEAGUE.md → Season moments), pure: the SEASON WRAP-UP page's view
## from a finished season (SeasonWrap.stats), the NEW SEASON page's from the
## rolled doc (SeasonWrap.opening_week). Names via LeagueSummary.

const GOLD := Color("#F0B84A")
const ORANGE := Color("#E8703A")
const CREAM := Color("#FFFFFF")

const STAT_LABELS := ["RECORD", "FINISH", "HIGH PTS", "AVG PTS", "BEST STREAK", "SWISHES"]


static func thousands(n: int) -> String:
	return RetroTheme.thousands(n)


static func _games_out(n: float) -> String:
	if n <= 0.0:
		return "ON THE TIEBREAK"
	if is_equal_approx(n, 0.5):
		return "HALF A GAME OUT"
	if is_equal_approx(n, 1.0):
		return "ONE GAME OUT"
	if is_equal_approx(n, floorf(n)):
		return "%d GAMES OUT" % int(n)
	return "%.1f GAMES OUT" % n


## The wrap-up: variant, banner, the title cards, six stats, three
## highlights, the season's earnings, the buttons.
static func wrap(doc: Dictionary, cfg: Dictionary) -> Dictionary:
	var w := SeasonWrap.stats(doc, cfg)
	var result := str(w["playoffResult"])
	var variant := "champs" if result == "champion" else ("missed" if result == "missed" else "out")
	var record := "%d-%d" % [int(w["w"]), int(w["l"])]
	var seed_text := "%s SEED" % TickerText.ordinal(int(w["finish"]))
	var head := ""
	var line := ""
	match result:
		"champion":
			head = "CHAMPIONS"
			var fs: Array = w["yourFinal"] if not Array(w["yourFinal"]).is_empty() else w["finalScore"]
			line = "%s · %s · WON THE FINAL %d-%d" % [record, seed_text, int(fs[0]) if fs.size() > 0 else 0, int(fs[1]) if fs.size() > 1 else 0]
		"runner_up":
			head = "LOST THE FINAL"
			var fs: Array = w["yourFinal"]
			line = "%s · %s · LOST THE FINAL %d-%d TO %s" % [record, seed_text, int(fs[0]) if fs.size() > 0 else 0,
				int(fs[1]) if fs.size() > 1 else 0, LeagueSummary.short_name(str(w["championId"]))]
		"semifinal":
			head = "OUT IN THE SEMIS"
			var ss: Array = w["semiScore"]
			line = "%s · %s · LOST %d-%d TO %s" % [record, seed_text, int(ss[0]) if ss.size() > 0 else 0,
				int(ss[1]) if ss.size() > 1 else 0, LeagueSummary.short_name(str(w["semiOpp"]))]
		_:
			head = "MISSED THE PLAYOFFS"
			line = "%s · %s · %s" % [record, TickerText.ordinal(int(w["finish"])), _games_out(float(w["gamesOut"]))]
	var banner := GOLD if variant == "champs" else (ORANGE if variant == "out" else CREAM)
	var bg: Dictionary = w["bestGame"]
	var tough: Dictionary = w["toughest"]
	var fs2: Array = w["finalScore"]
	return {
		"variant": variant, "head": head, "head_color": GOLD if variant == "champs" else CREAM, "banner_color": banner,
		"trophy": variant == "champs", "line": line,
		"league": str(cfg.get("name", "LEAGUE")).to_upper(), "season": "SEASON %d" % int(w["year"]), "year": int(w["year"]),
		"champion": {"title": "CHAMPION · %d-%d" % [int(fs2[0]) if fs2.size() > 0 else 0, int(fs2[1]) if fs2.size() > 1 else 0],
			"name": LeagueSummary.team_name(str(w["championId"])) if str(w["championId"]) != "" else "-"},
		"runner_up": {"title": "RUNNER-UP", "name": LeagueSummary.team_name(str(w["runnerUpId"])) if str(w["runnerUpId"]) != "" else "-"},
		"stats": [
			{"v": record, "l": STAT_LABELS[0]},
			{"v": TickerText.ordinal(int(w["finish"])) if int(w["finish"]) > 0 else "-", "l": STAT_LABELS[1]},
			{"v": str(int(w["highPts"])), "l": STAT_LABELS[2]},
			{"v": "%.1f" % float(w["avgPts"]), "l": STAT_LABELS[3]},
			{"v": str(int(w["bestStreak"])) if int(w["bestStreak"]) > 0 else "-", "l": STAT_LABELS[4]},
			{"v": str(int(w["swishes"])), "l": STAT_LABELS[5]},
		],
		"highlights": [
			{"l": "BEST GAME", "v": "%d-%d %s" % [int(bg["you"]), int(bg["them"]), LeagueSummary.short_name(str(bg["oppId"]))] if not bg.is_empty() else "-"},
			{"l": "TOUGHEST", "v": "%s · %d-%d" % [LeagueSummary.short_name(str(tough["oppId"])), int(tough["w"]), int(tough["l"])] if not tough.is_empty() else "-"},
			{"l": "TITLES", "v": str(int(w["titles"]))},
		],
		"earned": {"xp": "+%s XP" % thousands(int(w["earned"]["xp"])), "xp_n": int(w["earned"]["xp"]),
			"tickets": "+%s" % thousands(int(w["earned"]["tickets"])), "tickets_n": int(w["earned"]["tickets"]), "head": "SEASON EARNINGS"},
		"start": {"title": "START SEASON %d" % (int(w["year"]) + 1), "sub": "NEW SCHEDULE"},
		"later": "LATER",
	}


## The NEW SEASON page: the roll, the record strike, the opening week.
static func new_season(doc: Dictionary, cfg: Dictionary) -> Dictionary:
	var o := SeasonWrap.opening_week(doc, cfg)
	var cards := []
	for g in o["games"]:
		var h: Dictionary = g["h2h"]
		cards.push_back({
			"day": "DAY %d" % int(g["day"]), "name": LeagueSummary.team_name(str(g["oppId"])),
			"h2h": "YOU WENT %d-%d VS THEM" % [int(h["w"]), int(h["l"])] if not h.is_empty() else "FIRST MEETING",
			"side": "HOME" if bool(g["home"]) else "AWAY",
		})
	var first: Dictionary = cards[0] if not cards.is_empty() else {"name": "-", "side": "HOME"}
	var old_rec: Array = o["oldRecord"]
	return {
		"league": str(cfg.get("name", "LEAGUE")).to_upper(),
		"old_year": str(int(o["oldYear"])), "new_year": str(int(o["newYear"])),
		"defending": bool(o["defending"]), "defending_text": "DEFENDING CHAMPS",
		"record_old": "%d-%d" % [int(old_rec[0]), int(old_rec[1])] if old_rec.size() == 2 else "", "record_new": "0-0",
		"week": {"title": "OPENING WEEK", "sub": "%d DAYS · %d TEAMS" % [int(o["days"]), int(o["teams"])]},
		"cards": cards,
		"more": "+ %d MORE DAYS · TOP %d MAKE THE PLAYOFFS" % [int(o["more_days"]), int(o["spots"])],
		"play": {"title": "PLAY DAY 1", "sub": "VS %s · %s" % [str(first["name"]), str(first["side"])]},
		"later": "LATER",
	}


## Every string on either page, for the glyph check.
static func strings(v: Dictionary) -> Array:
	var out := []
	for key in ["head", "line", "league", "season", "later", "old_year", "new_year", "defending_text", "record_old", "record_new", "more"]:
		if v.has(key):
			out.push_back(str(v[key]))
	for key in ["champion", "runner_up", "earned", "start", "week", "play"]:
		if v.has(key):
			for val in Dictionary(v[key]).values():
				if val is String:
					out.push_back(val)
	for key in ["stats", "highlights", "cards"]:
		if v.has(key):
			for row in v[key]:
				for val in Dictionary(row).values():
					if val is String:
						out.push_back(val)
	return out
