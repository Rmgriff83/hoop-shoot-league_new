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
				"sub_at": 2.9, "sub_y": 884.0, "ready_s": 3.6, "sound": {"name": "chime_win", "at": 2.5},
				"button": {"title": "CONTINUE", "sub": "TO THE POST-MATCH", "at": 3.6}})
		"series":
			v.merge({"head": "YOU WIN" if won else "THEY TOOK IT", "head_color": GOLD if won else CREAM, "win_anim": won,
				"rays": GOLD if won else Color.TRANSPARENT, "spin_s": 22.0, "flash": won, "scrim": 0.55 if won else 0.8,
				"confetti_n": 24 if won else 0, "palette": PALETTE_PLAYOFF if won else [],
				"sub": "FIRST TO %d" % (int(e.get("best_of", 3)) / 2 + 1)})
		"advance":
			v.merge({"head": "ADVANCE", "head_color": GOLD, "win_anim": true, "rays": GOLD, "spin_s": 22.0,
				"flash": true, "scrim": 0.55, "confetti_n": 50, "palette": PALETTE_PLAYOFF, "sub": "ONE WIN FROM THE TITLE"})
		"eliminated":
			v.merge({"head": "ELIMINATED", "head_color": ORANGE, "win_anim": false, "rays": Color.TRANSPARENT, "spin_s": 30.0,
				"flash": false, "scrim": 0.82, "confetti_n": 0, "palette": [],
				"sub": "SEASON %d OVER · %s PLACE" % [year, ordinal(maxi(int(e.get("place_after", 3)), 3))]})
		"runner_up":
			v.merge({"head": "SO CLOSE", "head_color": CREAM, "win_anim": false, "rays": Color.TRANSPARENT, "spin_s": 30.0,
				"flash": false, "scrim": 0.8, "confetti_n": 0, "palette": [],
				"sub": "SEASON %d OVER · RUNNER-UP" % year})
		"champion":
			# 39b: the trophy drops and shakes the page, CHAMPIONS slams over it.
			var sa: Array = e.get("series_after", [0, 0])
			v.merge({"head": "CHAMPIONS", "head_color": GOLD, "win_anim": true, "rays": GOLD, "spin_s": 14.0,
				"flash": true, "flash_at": 0.05, "rays_at": 0.2, "head_at": 1.0, "head_y": 520.0, "scrim": 0.5,
				"confetti_n": 26, "palette": PALETTE_CHAMP, "no_score": true, "no_rewards": true, "sub": "",
				"line": "SEASON %d · BEAT %s %d-%d · %d-%d" % [year, opp_first, int(sa[0]) if sa.size() > 0 else 0,
					int(sa[1]) if sa.size() > 1 else 0, int(heat.get("player_score", 0)), int(heat.get("ai_score", 0))],
				"ready_s": 3.2, "sound": {"name": "chime_big", "at": 1.0},
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
		v["block"] = "bracket"
		var others: Array = e.get("other_semi", [])
		var other_names := []
		for id in others:
			other_names.push_back(LeagueSummary.short_name(str(id)))
		var final_opp := str(e.get("final_opp", ""))
		var decided := bool(e.get("decided", false))
		var series_won := bool(e.get("series_won", false))
		var final_round := round_ == "final"
		v["bracket"] = {
			"round_label": "FINAL" if final_round else "SEMIFINAL",
			"you": int(heat.get("player_score", 0)), "opp": int(heat.get("ai_score", 0)),
			"series": "%d - %d" % [int(Array(e.get("series_after", [0, 0]))[0]), int(Array(e.get("series_after", [0, 0]))[1])],
			"decided": decided,
			"lost": decided and not series_won,
			"next_label": "CHAMPION" if final_round else "FINAL",
			"next_name": ("YOU" if series_won else opp_first) if decided else "",
			"next_opp": ("VS %s" % LeagueSummary.short_name(final_opp)) if final_opp != "" else
				("VS %s" % " / ".join(other_names) if not other_names.is_empty() else ""),
			"opp_first": opp_first,
		}
	return v


## Every string on the page, for the glyph check.
static func strings(v: Dictionary) -> Array:
	var out := [str(v.get("tag", "")), str(v.get("head", "")), str(v.get("sub", "")), str(v.get("tickets", "")),
		str(v.get("opp_first", "")), str(v.get("line", "")), "YOU", "TAP TO CONTINUE", "NEW CARD", "TITLES"]
	for key in ["record", "bracket", "matchup", "standings", "button"]:
		if v.has(key):
			for val in Dictionary(v[key]).values():
				if val is String:
					out.push_back(val)
				elif val is Array:
					for row in val:
						if row is Dictionary:
							out.push_back(str(row.get("name", "")))
							out.push_back(str(row.get("record", "")))
	if v.has("cards"):
		out.push_back(str(Dictionary(Dictionary(v["cards"]).get("xp", {})).get("label", "")))
		out.push_back(str(Dictionary(Dictionary(v["cards"]).get("xp", {})).get("sub", "")))
	return out
