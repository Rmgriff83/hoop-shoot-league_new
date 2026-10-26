class_name RanksCopy
extends RefCounted
## The Ranks page's words (docs/HOME.md → Ranks; design "Ranks" 41a,
## 2026-10-25): the area tabs and the RANKED tab (the global 1v1 ladder —
## docs/BACKEND.md → Ranked), the BOARD note, the two periods (ALL TIME
## first), the status line, the rows from a server board or the device's
## own, and the player card's rank and line. Pure; the page and the tests read it.

const AREAS := ["cage", "beach", "park", "city"]
## The ladder's tab id (not an area): one board, no periods.
const RANKED := "ranked"
const PERIODS := ["all", "week"]   # ALL TIME first: the default
const BOARD_SIZE := 50
const TOP_COLOURS := 3


static func tab_name(area: String) -> String:
	match area:
		"beach":
			return "BEACH"
		"park":
			return "PARK"
		"city":
			return "CITY"
		RANKED:
			return "RANKED"
	return "CAGE"


static func period_name(period: String) -> String:
	return "THIS WEEK" if period == "week" else "ALL TIME"


## The tabs by level: {area, text, locked, lock_text}, the ladder last.
static func tabs(level: int, gating := true) -> Array:
	var out := []
	for a in AREAS:
		var locked: bool = gating and not Progression.area_unlocked(level, a)
		out.push_back({"area": a, "text": tab_name(a), "locked": locked,
			"lock_text": "LVL %d" % Progression.area_level(a) if locked else ""})
	out.push_back({"area": RANKED, "text": tab_name(RANKED), "locked": false, "lock_text": ""})
	return out


static func loading_status() -> String:
	return "LOADING..."


## Over the BOARD grid: how many courts are open (the ladder is always open).
static func board_note(tabs_: Array) -> String:
	var open := 0
	var areas := 0
	for tb in tabs_:
		if str(tb["area"]) == RANKED:
			continue
		areas += 1
		if not bool(tb.get("locked", false)):
			open += 1
	return "ALL COURTS OPEN" if open == areas else "%d OF %d COURTS OPEN" % [open, areas]


static func status(period: String, count: int) -> String:
	if count == 0:
		return "NO RUNS YET · BE FIRST"
	return "TOP %d · %s" % [count, period_name(period)]


## The ladder's status line.
static func ranked_status(count: int) -> String:
	if count == 0:
		return "NO RATED GAMES YET · BE FIRST"
	return "TOP %d · RATED 1V1" % count


## Ladder rows → {rank, name, tag, score, me}: the score column is the badge
## and the record (`PRO II · 12-9`, `LEGEND #1 · 40-11`).
static func ranked_rows(data: Dictionary) -> Array:
	var out := []
	for r in data.get("rows", []):
		var pos := int(r.get("position", 0))
		var rank := {"tier": str(r.get("tier", "rookie")), "division": int(r.get("division", 3)), "position": pos, "games": int(r.get("games", 1))}
		out.push_back({"rank": "#%d" % pos, "name": str(r.get("name", "")), "tag": tag_text(str(r.get("tag", ""))),
			"score": "%s · %d-%d" % [RankedRules.badge_text(rank), int(r.get("wins", 0)), int(r.get("losses", 0))], "me": bool(r.get("me", false))})
	return out


## A handle's tag as the rows show it after the name: `#07`.
static func tag_text(tag: String) -> String:
	return "#" + tag if tag != "" else ""


## The player card on the ladder: your position and your badge and record
## (the same as your row), or UNRANKED before a rated game.
static func ranked_me_card(data: Dictionary) -> Dictionary:
	var me: Variant = data.get("me", null)
	if me == null or not (me is Dictionary) or me.is_empty() or int(me.get("games", 0)) <= 0:
		return {"rank": "-", "sub": "UNRANKED · PLAY A RATED GAME"}
	return {"rank": "#%d" % int(me.get("position", 0)),
		"sub": "%s · %d-%d" % [RankedRules.badge_text(me), int(me.get("wins", 0)), int(me.get("losses", 0))]}


static func ranked_offline_status() -> String:
	return "NO SIGNAL · THE LADDER NEEDS A CONNECTION"


static func offline_status() -> String:
	return "NO SIGNAL · DEVICE BOARD"


## Server rows → {rank, name, tag, score, me}.
static func rows(data: Dictionary) -> Array:
	var out := []
	for r in data.get("rows", []):
		out.push_back({"rank": "#%d" % int(r.get("rank", 0)), "name": str(r.get("name", "")), "tag": tag_text(str(r.get("tag", ""))),
			"score": str(int(r.get("score", 0))), "me": bool(r.get("me", false))})
	return out


## The device's own board (SaveService.top_scores) as rows: every run is YOU.
static func local_rows(top: Array) -> Array:
	var out := []
	for i in mini(top.size(), BOARD_SIZE):
		out.push_back({"rank": "#%d" % (i + 1), "name": "YOU", "tag": "", "score": str(int(top[i].get("score", 0))), "me": i == 0})
	return out


## The player card on an area board: your rank and best (`#12`, `31 PTS ·
## BEST`), or NO RUN HERE YET.
static func me_card(data: Dictionary) -> Dictionary:
	var me: Variant = data.get("me", null)
	if me == null or not (me is Dictionary) or me.is_empty():
		return {"rank": "-", "sub": "NO RUN HERE YET"}
	return {"rank": "#%d" % int(me.get("rank", 0)), "sub": "%d PTS · BEST" % int(me.get("score", 0))}


## No signal: the device's own best, no rank.
static func local_me_card(top: Array) -> Dictionary:
	if top.is_empty():
		return {"rank": "-", "sub": "NO RUN HERE YET"}
	return {"rank": "-", "sub": "%d PTS · DEVICE BEST" % int(top[0].get("score", 0))}


## Every string the page can show, for the glyph test.
static func strings(data: Dictionary, top: Array) -> Array:
	var out := ["RANKS", "<", "BOARD", loading_status(), offline_status(), status("week", 0), status("all", 12),
		ranked_status(0), ranked_status(50), ranked_offline_status(), board_note(tabs(1, true)), board_note(tabs(9, true))]
	for c in [me_card(data), me_card({}), local_me_card(top), ranked_me_card({}), ranked_me_card({"me": {"tier": "legend", "division": 1, "position": 12, "games": 3, "wins": 40, "losses": 11}})]:
		out.push_back(c["rank"])
		out.push_back(c["sub"])
	for t in RankedRules.tiers():
		for d in [1, 2, 3]:
			out.push_back(RankedRules.badge_text({"tier": t["id"], "division": d, "games": 1}))
	for tb in tabs(1, true):
		out.push_back(tb["text"])
		out.push_back(tb["lock_text"])
	for p in PERIODS:
		out.push_back(period_name(p))
	for r in rows(data) + local_rows(top):
		out.push_back(r["rank"])
		out.push_back(r["name"])
		out.push_back(r["tag"])
		out.push_back(r["score"])
	return out
