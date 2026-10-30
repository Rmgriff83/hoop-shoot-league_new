class_name MatchEndCopy
extends RefCounted
## The league match-end page's copy (design "League Match End", docs/HOME.md
## → Results), pure and headless: from App.last_heat (Heat.result() +
## opponent, league {id, game, playoff}, tickets, card_drop and the campaign
## snapshot `league_end` App._apply_league_heat captured) pick the moment —
## win, loss, series (a playoff game that did not decide the series),
## advance, eliminated, runner_up, champion — and everything the overlay
## draws for it.

const GOLD := Color("#F0B84A")
const ORANGE := Color("#E8703A")
const CREAM := Color("#FFFFFF")
const BLUE := Color("#7FAEC6")
const PALETTE_WIN := [ORANGE, GOLD, CREAM]
const PALETTE_PLAYOFF := [GOLD, ORANGE, CREAM]
const PALETTE_CHAMP := [GOLD, ORANGE, CREAM, BLUE]


static func ordinal(n: int) -> String:
	var suffix := "TH"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "ST"
			2:
				suffix = "ND"
			3:
				suffix = "RD"
	return "%d%s" % [n, suffix]


static func _end(heat: Dictionary) -> Dictionary:
	var e: Variant = heat.get("league_end", {})
	return e if e is Dictionary else {}


## Which moment this is.
static func kind(heat: Dictionary) -> String:
	var won := bool(heat.get("won", false))
	var e := _end(heat)
	if not bool(e.get("playoff", false)):
		# Season moments (design 39a, Ross 2026-10-27): the last day's win that
		# puts the player in the playoffs is the CLINCHED page; a mid-season
		# clinch keeps the plain win with a CLINCHED tag.
		if won and bool(e.get("last_day", false)) and bool(e.get("in_playoffs_after", false)):
			return "clinch"
		return "win" if won else "loss"
	if not bool(e.get("decided", false)):
		return "series"
	var final_round := str(e.get("round", "")) == "final"
	if bool(e.get("series_won", false)):
		return "champion" if final_round else "advance"
	return "runner_up" if final_round else "eliminated"


static func record_text(r: Array) -> String:
	return "%d-%d" % [int(r[0]) if r.size() > 0 else 0, int(r[1]) if r.size() > 1 else 0]


## `2ND PLACE · UP 1` / `4TH PLACE · DOWN 2` / `3RD PLACE · HOLD` (first
## game: just the place).
static func place_text(before: int, after: int) -> String:
	if after <= 0:
		return ""
	var out := "%s PLACE" % ordinal(after)
	if before <= 0:
		return out
	if after < before:
		return out + " · UP %d" % (before - after)
	if after > before:
		return out + " · DOWN %d" % (after - before)
	return out + " · HOLD"


## The bracket block (design 15a): `style` "semis" (the semifinal round:
## the FINAL box over both semis) or "final" (the final round: the final's
## rows over the small semis). Rows carry a name, the season record, the
## series wins, gold for the series winner, a strike for the loser and a
## pop on the number this game moved.
static func bracket(heat: Dictionary, opp_first := "THEM") -> Dictionary:
	var e := _end(heat)
	var won := bool(heat.get("won", false))
	var recs := {}
	for row in e.get("table_after", []):
		recs[str(row["teamId"])] = "%d-%d" % [int(row["w"]), int(row["l"])]
	var names := {}
	var mine := {}
	var semis := []
	var fin := {}
	for s in e.get("bracket_after", []):
		if str(s.get("round", "")) == "final":
			fin = s
		else:
			semis.push_back(s)
		if str(s.get("id", "")) == str(e.get("series_id", "")):
			mine = s
	if mine.is_empty():
		# An older snapshot without the bracket: your series from the score.
		var sa: Array = e.get("series_after", [0, 0])
		names["?opp"] = opp_first
		mine = {"id": str(e.get("series_id", "")), "round": str(e.get("round", "semifinal")), "highSeedId": Campaign.PLAYER,
			"lowSeedId": "?opp", "highWins": int(sa[0]) if sa.size() > 0 else 0, "lowWins": int(sa[1]) if sa.size() > 1 else 0,
			"winnerId": "", "bestOf": int(e.get("best_of", 3))}
		if bool(e.get("decided", false)):
			mine["winnerId"] = Campaign.PLAYER if bool(e.get("series_won", false)) else "?opp"
		if str(mine["round"]) == "final":
			fin = mine
		else:
			semis = [mine]
	var opp_id := str(mine["lowSeedId"] if mine["highSeedId"] == Campaign.PLAYER else mine["highSeedId"])
	var pop_id := Campaign.PLAYER if won else opp_id
	var decided := str(mine.get("winnerId", "")) != ""
	var game_no := int(mine.get("highWins", 0)) + int(mine.get("lowWins", 0))
	var best_of := maxi(int(mine.get("bestOf", e.get("best_of", 3))), 1)
	var out := {"decided": decided, "lost": decided and str(mine.get("winnerId", "")) != Campaign.PLAYER}
	var semi_list := []
	var n := 0
	for s in semis:
		n += 1
		var is_mine := str(s.get("id", "")) == str(mine.get("id", ""))
		var winner := str(s.get("winnerId", ""))
		var played := int(s.get("highWins", 0)) + int(s.get("lowWins", 0))
		var head := "SEMI %d" % n
		var gold := winner == Campaign.PLAYER or (is_mine and winner == "" and won)
		semi_list.push_back({
			"head": head, "mine": is_mine, "decided": winner != "",
			"note": ("G%d OF %d" % [game_no, best_of]) if is_mine else ("G%d NEXT" % (played + 1) if winner == "" else "DONE"),
			"line": GOLD if gold else (CREAM if is_mine else Color(CREAM, 0.35)),
			"gold": gold,
			"path": GOLD if winner == Campaign.PLAYER else (CREAM if winner != "" else Color(CREAM, 0.35)),
			"winner": "" if winner == "" else _short(winner, names),
			"you_won": winner == Campaign.PLAYER,
			"rows": _rows(s, recs, names, pop_id if is_mine else "")})
	out["semis"] = semi_list
	if str(mine.get("round", "")) != "final":
		out["style"] = "semis"
		var left := str(semi_list[0]["winner"]) if semi_list.size() > 0 and str(semi_list[0]["winner"]) != "" else "?"
		var right := str(semi_list[1]["winner"]) if semi_list.size() > 1 and str(semi_list[1]["winner"]) != "" else "?"
		var finalist := false
		for sm in semi_list:
			finalist = finalist or bool(sm["you_won"])
		out["final"] = {"label": "FINAL", "text": "%s VS %s" % [left, right], "you_in": finalist,
			"line": GOLD if finalist else Color(CREAM, 0.5), "color": GOLD if finalist else CREAM, "pop": decided}
		return out
	out["style"] = "final"
	var fin_gold := str(fin.get("winnerId", "")) == Campaign.PLAYER or (str(fin.get("winnerId", "")) == "" and won)
	out["final"] = {"label": "FINAL", "game": "GAME %d OF %d" % [game_no, best_of], "gold": fin_gold,
		"rows": _rows(fin, recs, names, pop_id)}
	for sm in semi_list:
		# The final's small semis: your semi gold-edged, the other faint.
		var path_gold := false
		for r in sm["rows"]:
			path_gold = path_gold or (str(r["id"]) == Campaign.PLAYER)
		sm["line"] = GOLD if path_gold else Color(CREAM, 0.5)
		sm["path"] = GOLD if path_gold else Color(CREAM, 0.6)
	return out


static func _short(id: String, names: Dictionary) -> String:
	return str(names[id]) if names.has(id) else LeagueSummary.short_name(id)


## A series' two rows, you first when you are in it (else the high seed).
static func _rows(s: Dictionary, recs: Dictionary, names: Dictionary, pop_id: String) -> Array:
	var sides := [["highSeedId", "highWins"], ["lowSeedId", "lowWins"]]
	if str(s.get("lowSeedId", "")) == Campaign.PLAYER:
		sides.reverse()
	var winner := str(s.get("winnerId", ""))
	var out := []
	for side in sides:
		var id := str(s.get(side[0], ""))
		out.push_back({"id": id, "name": _short(id, names), "rec": str(recs.get(id, "")), "wins": int(s.get(side[1], 0)),
			"won": winner != "" and winner == id, "struck": winner != "" and winner != id, "pop": pop_id != "" and id == pop_id})
	return out


## Everything the overlay draws.
static func state(heat: Dictionary) -> Dictionary:
	var k := kind(heat)
	var won := bool(heat.get("won", false))
	var e := _end(heat)
	var year := int(e.get("year", 1))
	var league: Dictionary = heat.get("league", {}) if heat.get("league", null) is Dictionary else {}
	var opp: Dictionary = heat.get("opponent", {})
	var opp_first := str(opp.get("name", "THEM")).to_upper()
	if opp_first.find(" ") > 0:
		opp_first = opp_first.substr(0, opp_first.find(" "))
	var v := {
		"kind": k, "won": won,
		"score_you": int(heat.get("player_score", 0)), "score_opp": int(heat.get("ai_score", 0)),
		"opp_first": opp_first,
		"tickets": "+%d" % int(heat.get("tickets", 0)),
		"ticket_count": int(heat.get("tickets", 0)),
		"drop": str(heat.get("card_drop", "")),
		"year": year,
	}
	var playoff := bool(e.get("playoff", false))
	var round_ := str(e.get("round", ""))
	# The tag pill.
	if k == "clinch":
		v["tag"] = "DAY %d · FINAL · W %d-%d" % [int(e.get("day", 0)), int(heat.get("player_score", 0)), int(heat.get("ai_score", 0))]
		v["tag_color"] = CREAM
	elif not playoff:
		var tag := str(league.get("game", ""))
		v["tag"] = "%s · FINAL" % ("DAY %s" % tag.substr(1) if tag.begins_with("d") else tag.to_upper())
		if won and bool(e.get("clinch_after", false)) and not bool(e.get("clinch_before", false)):
			v["tag"] += " · CLINCHED"
		v["tag_color"] = CREAM
	elif k == "champion":
		var game_no := int(e.get("series_game_no", 0))
		if game_no <= 0:
			game_no = int(Array(e.get("series_after", [0, 0]))[0]) + int(Array(e.get("series_after", [0, 0]))[1])
		v["tag"] = "%s · FINAL · GAME %d" % [str(e.get("league_name", "LEAGUE")), maxi(game_no, 1)]
		v["tag_color"] = GOLD
	else:
		v["tag"] = "PLAYOFFS · %s" % ("FINAL" if round_ == "final" else "SEMIFINAL")
		v["tag_color"] = ORANGE if (k == "eliminated" or k == "runner_up") else GOLD
	# The headline, the mood.
	match k:
		"win":
			v.merge({"head": "YOU WIN", "head_color": GOLD, "win_anim": true, "rays": ORANGE, "spin_s": 30.0,
				"flash": true, "scrim": 0.55, "confetti_n": 36, "palette": PALETTE_WIN, "sub": ""})
		"loss":
			v.merge({"head": "THEY TOOK IT", "head_color": CREAM, "win_anim": false, "rays": Color.TRANSPARENT, "spin_s": 30.0,
				"flash": false, "scrim": 0.8, "confetti_n": 0, "palette": [], "sub": ""})
			if bool(e.get("last_day", false)) and bool(e.get("in_playoffs_after", false)):
				v["sub"] = "IN THE PLAYOFFS · NO. %d SEED" % int(e.get("seed_after", 0))
		"clinch":
			# 39a: PLAYOFFS slams at 2.5 s over the standings that just climbed.
			v.merge({"head": "PLAYOFFS", "head_color": GOLD, "win_anim": true, "rays": GOLD, "spin_s": 22.0,
				"flash": true, "flash_at": 2.5, "rays_at": 2.5, "head_at": 2.5, "head_y": 790.0, "scrim": 0.62,
				"confetti_n": 0, "palette": [], "no_score": true, "no_rewards": true,
				"sub": "%s · NO. %d SEED" % ["LOCKED IN" if bool(e.get("clinch_before", false)) else "CLINCHED", int(e.get("seed_after", 0))],
				"sub_at": 2.9, "sub_y": 884.0, "ready_s": 3.6, "tag_y": 220.0, "rays_y": 380.0, "sound": {"name": "chime_win", "at": 2.5},
				"button": {"title": "CONTINUE", "sub": "TO THE POST-MATCH", "at": 3.6}})
		"series":
			v.merge({"head": "YOU WIN" if won else "THEY TOOK IT", "head_color": GOLD if won else CREAM, "win_anim": won,
				"rays": GOLD if won else Color.TRANSPARENT, "spin_s": 22.0, "flash": won, "scrim": 0.55 if won else 0.8,
				"confetti_n": 24 if won else 0, "palette": PALETTE_PLAYOFF if won else []})
		"advance":
			v.merge({"head": "ADVANCE", "head_color": GOLD, "win_anim": true, "rays": GOLD, "spin_s": 22.0,
				"flash": true, "scrim": 0.55, "confetti_n": 50, "palette": PALETTE_PLAYOFF})
		"eliminated":
			v.merge({"head": "ELIMINATED", "head_color": ORANGE, "win_anim": false, "rays": Color.TRANSPARENT, "spin_s": 30.0,
				"flash": false, "scrim": 0.82, "confetti_n": 0, "palette": []})
		"runner_up":
			v.merge({"head": "SO CLOSE", "head_color": CREAM, "win_anim": false, "rays": Color.TRANSPARENT, "spin_s": 30.0,
				"flash": false, "scrim": 0.8, "confetti_n": 0, "palette": []})
		"champion":
			# 39b: the trophy drops and shakes the page, CHAMPIONS slams over it.
			var sa: Array = e.get("series_after", [0, 0])
			v.merge({"head": "CHAMPIONS", "head_color": GOLD, "win_anim": true, "rays": GOLD, "spin_s": 14.0,
				"flash": true, "flash_at": 0.05, "rays_at": 0.2, "head_at": 1.0, "head_y": 520.0, "scrim": 0.5,
				"confetti_n": 26, "palette": PALETTE_CHAMP, "no_score": true, "no_rewards": true, "sub": "",
				"line": "SEASON %d · BEAT %s %d-%d · %d-%d" % [year, opp_first, int(sa[0]) if sa.size() > 0 else 0,
					int(sa[1]) if sa.size() > 1 else 0, int(heat.get("player_score", 0)), int(heat.get("ai_score", 0))],
				"ready_s": 3.2, "sound": {"name": "chime_big", "at": 1.0}, "tag_y": 220.0, "rays_y": 380.0,
				"button": {"title": "CONTINUE", "sub": "TO THE POST-MATCH", "at": 3.2}})
	v["head_size"] = 72 if k == "clinch" else mini(64, int(620.0 / maxi(str(v["head"]).length(), 1)))
	# The middle block.
	if k == "clinch":
		v["block"] = "standings"
		var rows := {}
		for key in ["table_before", "table_after"]:
			var list := []
			for row in e.get(key, []):
				var id := str(row["teamId"])
				list.push_back({"id": id, "name": LeagueSummary.short_name(id), "record": "%d-%d" % [int(row["w"]), int(row["l"])],
					"you": id == Campaign.PLAYER})
			rows[key] = list
		v["standings"] = {"rows_before": rows["table_before"], "rows_after": rows["table_after"],
			"spots": int(e.get("spots", 4)), "record_before": record_text(Array(e.get("record_before", [0, 0]))),
			"record_after": record_text(Array(e.get("record_after", [0, 0]))), "seed": int(e.get("seed_after", 0)),
			"head": "STANDINGS", "note": "TOP %d MAKE IT" % int(e.get("spots", 4)), "line_label": "PLAYOFF LINE", "chip": "IN"}
		var ns: Dictionary = e.get("next_series", {}) if e.get("next_series", null) is Dictionary else {}
		v["matchup"] = {
			"title": "%s · BEST OF %d" % ["FINAL" if str(ns.get("round", "")) == "final" else "SEMIFINAL", int(ns.get("best_of", 3))],
			"line": "GAME 1 · %s" % ("HOME" if bool(ns.get("home", false)) else "AWAY"),
			"you": "NO. %d" % int(ns.get("seed_you", 0)), "you_name": "YOU", "vs": "VS",
			"opp": "NO. %d" % int(ns.get("seed_opp", 0)), "opp_name": LeagueSummary.short_name(str(ns.get("opp", ""))),
		}
	elif not playoff:
		v["block"] = "record"
		v["record"] = {
			"label": "SEASON %d RECORD" % year,
			"old": record_text(Array(e.get("record_before", [0, 0]))),
			"new": record_text(Array(e.get("record_after", [0, 0]))),
			"place": place_text(int(e.get("place_before", 0)), int(e.get("place_after", 0))),
			"gold": won,
		}
	elif k == "champion":
		v["block"] = "champion"
		v["trophy"] = {"titles": maxi(int(e.get("titles_after", 1)), 1)}
		var xp: Dictionary = heat.get("xp", {}) if heat.get("xp", null) is Dictionary else {}
		var gained := int(xp.get("gained", 0))
		var bonus := int(xp.get("title_gained", 0))
		v["cards"] = {
			"xp": {"label": "+%d XP" % gained, "sub": "CHAMPIONS BONUS" if bonus > 0 else ("AT THE CAP" if gained <= 0 else "MATCH XP"),
				"meter": HeatCopy.level_meter(heat, int(heat.get("xp_now", 0)))},
			"tickets_n": int(heat.get("tickets", 0)),
		}
	else:
		# Design 15a (2026-10-30): the bracket itself — the final over both
		# semis in the semifinal round, the final's two rows over the small
		# semis in the final. The page says no sub line under it.
		v["block"] = "bracket"
		v["bracket"] = bracket(heat, opp_first)
		v["sub"] = ""
	return v


## Every string on the page, for the glyph check.
static func strings(v: Dictionary) -> Array:
	var out := [str(v.get("tag", "")), str(v.get("head", "")), str(v.get("sub", "")), str(v.get("tickets", "")),
		str(v.get("opp_first", "")), str(v.get("line", "")), "YOU", "TAP TO CONTINUE", "NEW CARD", "TITLES"]
	for key in ["record", "matchup", "standings", "button"]:
		if v.has(key):
			for val in Dictionary(v[key]).values():
				if val is String:
					out.push_back(val)
				elif val is Array:
					for row in val:
						if row is Dictionary:
							out.push_back(str(row.get("name", "")))
							out.push_back(str(row.get("record", "")))
	if v.get("bracket", null) is Dictionary:
		var b: Dictionary = v["bracket"]
		var fin: Dictionary = b.get("final", {})
		for key in ["label", "text", "game"]:
			out.push_back(str(fin.get(key, "")))
		var lists := [fin.get("rows", [])]
		for sm in b.get("semis", []):
			out.push_back("%s · %s" % [sm["head"], sm["note"]])
			lists.push_back(sm["rows"])
		for rows in lists:
			for r in rows:
				out.push_back(str(r["name"]))
				out.push_back(str(r["rec"]))
				out.push_back(str(r["wins"]))
	if v.has("cards"):
		out.push_back(str(Dictionary(Dictionary(v["cards"]).get("xp", {})).get("label", "")))
		out.push_back(str(Dictionary(Dictionary(v["cards"]).get("xp", {})).get("sub", "")))
	return out
