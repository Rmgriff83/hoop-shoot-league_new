class_name RanksCopy
extends RefCounted
## The Ranks page's words (docs/HOME.md → Ranks): the area tabs, the two
## periods, the status line, the rows from a server board or the device's
## own, and the pinned YOU line. Pure; the page and the tests read it.

const AREAS := ["cage", "beach", "city"]
const PERIODS := ["week", "all"]
const BOARD_SIZE := 50
const TOP_COLOURS := 3


static func tab_name(area: String) -> String:
	return "BEACH" if area == "beach" else ("CITY" if area == "city" else "CAGE")


static func period_name(period: String) -> String:
	return "THIS WEEK" if period == "week" else "ALL TIME"


## The tabs by level: {area, text, locked, lock_text}.
static func tabs(level: int, gating := true) -> Array:
	var out := []
	for a in AREAS:
		var locked: bool = gating and not Progression.area_unlocked(level, a)
		out.push_back({"area": a, "text": tab_name(a), "locked": locked,
			"lock_text": "LVL %d" % Progression.area_level(a) if locked else ""})
	return out


static func loading_status() -> String:
	return "LOADING..."


static func status(period: String, count: int) -> String:
	if count == 0:
		return "NO RUNS YET · BE FIRST"
	return "TOP %d · %s" % [count, period_name(period)]


static func offline_status() -> String:
	return "NO SIGNAL · DEVICE BOARD"


## Server rows → {rank, name, score, me}.
static func rows(data: Dictionary) -> Array:
	var out := []
	for r in data.get("rows", []):
		out.push_back({"rank": "#%d" % int(r.get("rank", 0)), "name": HandleWords.display(str(r.get("name", "")), str(r.get("tag", ""))),
			"score": str(int(r.get("score", 0))), "me": bool(r.get("me", false))})
	return out


## The device's own board (SaveService.top_scores) as rows: every run is YOU.
static func local_rows(top: Array) -> Array:
	var out := []
	for i in mini(top.size(), BOARD_SIZE):
		out.push_back({"rank": "#%d" % (i + 1), "name": "YOU", "score": str(int(top[i].get("score", 0))), "me": i == 0})
	return out


## The pinned line: `YOU · #12 · 31`, or where you stand without a run.
static func me_line(data: Dictionary) -> String:
	var me: Variant = data.get("me", null)
	if me == null or not (me is Dictionary) or me.is_empty():
		return "YOU · NO RUN HERE YET"
	return "YOU · #%d · %d" % [int(me.get("rank", 0)), int(me.get("score", 0))]


static func local_me_line(top: Array) -> String:
	return "YOU · BEST %d" % int(top[0].get("score", 0)) if not top.is_empty() else "YOU · NO RUN HERE YET"


## Every string the page can show, for the glyph test.
static func strings(data: Dictionary, top: Array) -> Array:
	var out := ["RANKS", "<", loading_status(), offline_status(), status("week", 0), status("all", 12), me_line(data), local_me_line(top)]
	for tb in tabs(1, true):
		out.push_back(tb["text"])
		out.push_back(tb["lock_text"])
	for p in PERIODS:
		out.push_back(period_name(p))
	for r in rows(data) + local_rows(top):
		out.push_back(r["rank"])
		out.push_back(r["name"])
		out.push_back(r["score"])
	return out
