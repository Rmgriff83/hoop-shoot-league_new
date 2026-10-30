class_name HeatCopy
extends RefCounted
## The league post-match page's copy (design "League Post-Match",
## docs/HOME.md → Results), pure and headless: the header line, the result
## and score, the opponent line and chip, the box score with the better
## number marked, the rewards card (tickets), the card drop and the CONTINUE
## SEASON sub-line from the updated campaign doc. Reads App.last_heat's shape
## (Heat.result() + opponent, mode, location, league {id, game, playoff},
## tickets, card_drop).

const PLAYER := Campaign.PLAYER
const ROWS := [["MAKES", "makes"], ["SHOOTING", "pct"], ["SWISHES", "swishes"], ["BEST STREAK", "bestStreak"],
	["STREAK BONUS", "bonus"], ["ICED OVER", "iced"]]


static func league_of(heat: Dictionary) -> Dictionary:
	var l: Variant = heat.get("league", null)
	return l if l is Dictionary else {}


## `ARCADE LEAGUE · SEASON 2 · DAY 4` / `… · SEMI 2 · GAME 3`; `QUICK HEAT` without a league.
static func header(heat: Dictionary, doc: Dictionary) -> String:
	var league := league_of(heat)
	if league.is_empty():
		return MatchCopy.header(heat) if bool(heat.get("online", false)) else "QUICK HEAT"
	var cfg := LeagueData.league(str(league.get("id", "")))
	var name_ := str(cfg.get("name", "LEAGUE")).to_upper()
	if doc.is_empty():
		return name_
	return "%s · SEASON %d · %s" % [name_, LeagueSummary.year_of(doc), game_line(str(league.get("game", "")), doc)]


## The game just played from its tag: `d4` → `DAY 4`; `po-sf-2v3` → `SEMI 2 ·
## GAME n` (n = the games in that series after the result); `po-final` → `FINAL · GAME n`.
static func game_line(tag: String, doc: Dictionary) -> String:
	if tag.begins_with("d"):
		return "DAY %s" % tag.substr(1)
	if tag.begins_with("po-"):
		var sid := tag.substr(3)
		var season: Dictionary = doc.get("season", {})
		for s in season.get("series", []):
			if str(s.get("id", "")) == sid:
				return "%s · GAME %d" % [LeagueSummary.series_label(season, s), maxi(Array(s.get("games", [])).size(), 1)]
		return "PLAYOFFS"
	return tag.to_upper()


static func result(heat: Dictionary) -> Dictionary:
	var won := bool(heat.get("won", false))
	return {"text": "YOU WIN" if won else "THEY TOOK IT", "size": 36 if won else 28, "gold": won}


## The page title (design "League Post-Match v2" 6b, 2026-10-25): the league's
## name (`ARCADE LEAGUE`); an online match's header; QUICK HEAT for the test heat.
static func title(heat: Dictionary) -> String:
	var league := league_of(heat)
	if league.is_empty():
		return MatchCopy.header(heat) if bool(heat.get("online", false)) else "QUICK HEAT"
	return str(LeagueData.league(str(league.get("id", ""))).get("name", "LEAGUE")).to_upper()


## The line over the title: `SEASON 2 · DAY 4` / `SEMI 2 · GAME 3`; "" outside a league.
static func kicker(heat: Dictionary, doc: Dictionary) -> String:
	var league := league_of(heat)
	if league.is_empty() or doc.is_empty():
		return ""
	var game := game_line(str(league.get("game", "")), doc)
	return game if bool(league.get("playoff", false)) or game.begins_with("SEMI") or game.begins_with("FINAL") \
		else "SEASON %d · %s" % [LeagueSummary.year_of(doc), game]


## The XP meter (6b): where the bar starts and ends this match, in the level
## the player was in. {} outside a league. {level, need, from, to, gained, up,
## cap}: `from` / `to` are XP into the level (`to` = need on a level up, the
## bar fills to the end and the line turns gold); `cap` holds it full.
static func level_meter(heat: Dictionary, xp_now: int) -> Dictionary:
	var xp: Dictionary = heat.get("xp", {})
	if league_of(heat).is_empty() or xp.is_empty():
		return {}
	var gained := int(xp.get("gained", 0))
	var after := int(xp.get("level_after", Progression.level_for(xp_now)))
	var before := int(xp.get("level_before", after))
	var before_in: Array = Progression.xp_in_level(maxi(xp_now - gained, 0))
	var now_in: Array = Progression.xp_in_level(xp_now)
	var cfg := LeagueData.league(str(league_of(heat).get("id", "")))
	var cap := not cfg.is_empty() and Progression.at_cap(xp_now, cfg)
	var up := after > before
	var need := int(now_in[1])
	return {"level": after, "level_before": before, "need": need, "gained": gained, "up": up, "cap": cap and not up,
		"from": int(before_in[0]), "to": need if up else (need if cap else int(now_in[0]))}


## The meter's line at fill fraction `k` (0 … 1): `LEVEL 2 · 64/100 XP`
## counting up, `LEVEL UP · LEVEL 3` once a level-up bar is full, `LEVEL 3 · CAP`.
static func meter_text(m: Dictionary, k: float) -> String:
	if m.is_empty():
		return ""
	if bool(m["cap"]):
		return "LEVEL %d · CAP" % int(m["level"])
	if bool(m["up"]) and k >= 1.0:
		return "LEVEL UP · LEVEL %d" % int(m["level"])
	var now := roundi(lerpf(float(m["from"]), float(m["to"]), clampf(k, 0.0, 1.0)))
	return "LEVEL %d · %d/%d XP" % [int(m["level_before"]) if bool(m["up"]) else int(m["level"]), now, int(m["need"])]


static func score_line(heat: Dictionary) -> String:
	return "%d-%d" % [int(heat.get("player_score", 0)), int(heat.get("ai_score", 0))]


static func ot(heat: Dictionary) -> bool:
	return int(heat.get("ot", 0)) > 0


## `VS OLLIE KNOTS · "TIMBER"`.
static func vs_line(heat: Dictionary) -> String:
	var opp: Dictionary = heat.get("opponent", {})
	var nick := str(opp.get("nickname", "")).to_upper()
	var line := "VS %s" % str(opp.get("name", "?")).to_upper()
	return line + (" · \"%s\"" % nick if nick != "" else "")


## The opponent's chip: their first name in their shooter colour.
static func opponent_chip(heat: Dictionary) -> Dictionary:
	var opp: Dictionary = heat.get("opponent", {})
	var full := str(opp.get("name", "THEM")).to_upper()
	var sp := full.find(" ")
	var colors: Dictionary = opp.get("colors", {})
	var col := Color(str(colors.get("primary", ""))) if str(colors.get("primary", "")) != "" else LeagueContext.PINE
	return {"text": full.substr(0, sp) if sp > 0 else full, "color": col}


## The box score: [{l, a, b, hi}] — `hi` marks the better side ("a" you,
## "b" them, "" a tie); fewer ICED OVER is better.
static func box(heat: Dictionary) -> Array:
	var sides: Dictionary = heat.get("sides", {})
	var you: Dictionary = sides.get("player", {})
	var them: Dictionary = sides.get("ai", {})
	var out := []
	for spec in ROWS:
		var key: String = spec[1]
		var a := 0.0
		var b := 0.0
		var ta := ""
		var tb := ""
		match key:
			"makes":
				a = float(you.get("makes", 0))
				b = float(them.get("makes", 0))
				ta = "%d/%d" % [int(you.get("makes", 0)), int(you.get("attempts", 0))]
				tb = "%d/%d" % [int(them.get("makes", 0)), int(them.get("attempts", 0))]
			"pct":
				a = pct_of(you)
				b = pct_of(them)
				ta = pct_text(you)
				tb = pct_text(them)
			"bonus":
				a = float(you.get("bonus", 0))
				b = float(them.get("bonus", 0))
				ta = "+%d" % int(a)
				tb = "+%d" % int(b)
			_:
				a = float(you.get(key, 0))
				b = float(them.get(key, 0))
				ta = str(int(a))
				tb = str(int(b))
		var hi := ""
		if a != b:
			var a_better := a < b if key == "iced" else a > b
			hi = "a" if a_better else "b"
		out.push_back({"l": spec[0], "a": ta, "b": tb, "hi": hi})
	return out


static func pct_of(side: Dictionary) -> float:
	var att := int(side.get("attempts", 0))
	return 100.0 * int(side.get("makes", 0)) / att if att > 0 else 0.0


static func pct_text(side: Dictionary) -> String:
	return "%d%%" % roundi(pct_of(side)) if int(side.get("attempts", 0)) > 0 else "-"


## The rewards card: {big, sub, sub2} — the tickets the heat paid and the
## XP; {} for a heat outside a league, and for an online match until its
## settle brings `tickets` (docs/BACKEND.md → Ranked → Stage B; no XP online).
static func rewards(heat: Dictionary) -> Dictionary:
	if bool(heat.get("online", false)):
		if int(heat.get("tickets", 0)) <= 0:
			return {}
		return {"big": "+%d" % int(heat["tickets"]), "sub": "TICKETS · %s" % ("WIN" if bool(heat.get("won", false)) else "LOSS"), "sub2": ""}
	if league_of(heat).is_empty():
		return {}
	var out := {"big": "+%d" % int(heat.get("tickets", 0)), "sub": "TICKETS · %s" % ("WIN" if bool(heat.get("won", false)) else "LOSS"), "sub2": ""}
	var xp: Dictionary = heat.get("xp", {})
	if int(xp.get("gained", 0)) > 0:
		out["sub2"] = "+%d XP" % int(xp["gained"])
	return out



## The level line under the opponent (docs/PROGRESSION.md): `LEVEL UP · LEVEL
## 2` (gold) when it rose, `LEVEL 3 · CAP` at the league's cap, else `LEVEL 2
## · 64/100 XP`; {} outside a league.
static func level_line(heat: Dictionary, xp_now: int) -> Dictionary:
	var xp: Dictionary = heat.get("xp", {})
	if league_of(heat).is_empty() or xp.is_empty():
		return {}
	var after := int(xp.get("level_after", Progression.level_for(xp_now)))
	if after > int(xp.get("level_before", after)):
		return {"text": "LEVEL UP · LEVEL %d" % after, "gold": true}
	var cfg := LeagueData.league(str(league_of(heat).get("id", "")))
	if not cfg.is_empty() and Progression.at_cap(xp_now, cfg):
		return {"text": "LEVEL %d · CAP" % after, "gold": false}
	var inl := Progression.xp_in_level(xp_now)
	return {"text": "LEVEL %d · %d/%d XP" % [after, inl[0], inl[1]], "gold": false}


## The dropped card's row, or {}.
static func drop(heat: Dictionary) -> Dictionary:
	var id := str(heat.get("card_drop", ""))
	return CardDefs.get_card(id) if id != "" else {}


## Every card the match dropped, [{card, caption}] (design 6b, 2026-10-30:
## a row of them). A record may carry `card_drops` [{id, reason}]; today's
## matches drop one, `card_drop` / `drop_reason`.
static func drops(heat: Dictionary) -> Array:
	var out := []
	if heat.get("card_drops") is Array:
		for d in heat["card_drops"]:
			var c := CardDefs.get_card(str(Dictionary(d).get("id", "")))
			if not c.is_empty():
				out.push_back({"card": c, "caption": reason_caption(str(Dictionary(d).get("reason", "")))})
		return out
	var one := drop(heat)
	if not one.is_empty():
		out.push_back({"card": one, "caption": drop_caption(heat)})
	return out


## Why it dropped (docs/CARDS.md § Drops): the caption over the card's name.
static func drop_caption(heat: Dictionary) -> String:
	return reason_caption(str(heat.get("drop_reason", "")))


static func reason_caption(reason: String) -> String:
	match reason:
		"comeback_win": return "COMEBACK CARD"
		"close_loss": return "CLOSE ONE"
		"loss_streak": return "TOUGH STRETCH · HERE'S AN ICE"
	return "CARD DROP"


## The bright spots (BrightSpots.note, kept on `heat.bright`), shown in a loss.
static func bright_lines(heat: Dictionary) -> Array:
	if bool(heat.get("won", false)) or not (heat.get("bright") is Array):
		return []
	var out := []
	for l in heat["bright"]:
		out.push_back(str(l))
	return out


## CONTINUE SEASON's sub-line from the campaign doc the result was folded into.
static func continue_sub(doc: Dictionary, cfg: Dictionary) -> String:
	if doc.is_empty():
		return ""
	var s: Dictionary = doc["season"]
	var rec := LeagueSummary.record(s)
	match str(s["phase"]):
		Season.PHASE_REGULAR:
			var p := LeagueSummary.place(cfg, s)
			return "NOW %d-%d · %s PLACE · DAY %d NEXT" % [rec[0], rec[1], TickerText.ordinal(p), int(s["currentDay"])] if p > 0 \
				else "NOW %d-%d · DAY %d NEXT" % [rec[0], rec[1], int(s["currentDay"])]
		Season.PHASE_PLAYOFFS:
			var mine := Season.player_series(s, PLAYER)
			if mine.is_empty():
				return "CHAMPIONS" if str(s.get("championId", "")) == PLAYER else "OUT OF THE PLAYOFFS"
			var wl := LeagueSummary.series_record(mine)
			var played: int = int(wl[0]) + int(wl[1])
			if played == 0:
				return "%s NEXT · GAME 1" % LeagueSummary.series_label(s, mine)
			return "SERIES %d-%d · GAME %d NEXT" % [wl[0], wl[1], played + 1]
		_:
			if str(s.get("championId", "")) == PLAYER:
				return "CHAMPIONS · SEASON %d OVER" % LeagueSummary.year_of(doc)
			var summ := Campaign.season_summary(doc, cfg)
			return "SEASON OVER · %s PLACE" % TickerText.ordinal(int(summ["finish"]))
