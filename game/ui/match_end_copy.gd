class_name MatchEndCopy
extends RefCounted
## The league match-end page's copy (design "League Match End", docs/HOME.md
## → Results), pure and headless: from App.last_heat (Heat.result() +
## opponent, league {id, game, playoff}, coins, card_drop and the campaign
## snapshot `league_end` App._apply_league_heat captured) pick the moment —
## win, loss, series (a playoff game that did not decide the series),
## advance, eliminated, runner_up, champion — and everything the overlay
## draws for it.

const GOLD := Color("#F0B84A")
const ORANGE := Color("#E8703A")
const CREAM := Color("#F1E8D0")
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
		"coins": "+%d" % int(heat.get("coins", 0)),
		"drop": str(heat.get("card_drop", "")),
		"year": year,
	}
	var playoff := bool(e.get("playoff", false))
	var round_ := str(e.get("round", ""))
	# The tag pill.
	if not playoff:
		var tag := str(league.get("game", ""))
		v["tag"] = "%s · FINAL" % ("DAY %s" % tag.substr(1) if tag.begins_with("d") else tag.to_upper())
		v["tag_color"] = CREAM
	elif k == "champion":
		v["tag"] = "%s · FINAL" % str(e.get("league_name", "LEAGUE"))
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
			v.merge({"head": "CHAMPIONS", "head_color": GOLD, "win_anim": true, "rays": GOLD, "spin_s": 14.0,
				"flash": true, "scrim": 0.5, "confetti_n": 80, "palette": PALETTE_CHAMP, "sub": "SEASON %d TITLE" % year})
	v["head_size"] = mini(64, int(620.0 / maxi(str(v["head"]).length(), 1)))
	# The middle block.
	if not playoff:
		v["block"] = "record"
		v["record"] = {
			"label": "SEASON %d RECORD" % year,
			"old": record_text(Array(e.get("record_before", [0, 0]))),
			"new": record_text(Array(e.get("record_after", [0, 0]))),
			"place": place_text(int(e.get("place_before", 0)), int(e.get("place_after", 0))),
			"gold": won,
		}
	elif k == "champion":
		v["block"] = "trophy"
		v["trophy"] = {"titles": maxi(int(e.get("titles_after", 1)), 1)}
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
	var out := [str(v.get("tag", "")), str(v.get("head", "")), str(v.get("sub", "")), str(v.get("coins", "")),
		str(v.get("opp_first", "")), "YOU", "TAP TO CONTINUE", "NEW CARD", "TITLES"]
	for key in ["record", "bracket"]:
		if v.has(key):
			for val in Dictionary(v[key]).values():
				if val is String:
					out.push_back(val)
	return out
