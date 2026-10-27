class_name ResultsCopy
extends RefCounted
## The time-trial results page's copy (design "Time Trial Results",
## docs/HOME.md → Results), pure and headless: the header line, the gap to
## your best, the stat tiles (ICED only when it happened), the board rows
## with this run marked, the tickets card and the RUN IT BACK sub-line.
## Reads App.last_run's shape ({score, makes, attempts, swishes, bestStreak,
## bonus, iced, location, id, tickets}) and SaveService.top_scores rows.

## The board shows the top five (design 7a, 2026-10-24); a lower run joins as a sixth row.
const BOARD_SIZE := 5
## The kicker over the area name.
const KICKER := "TIME TRIAL"


## The page title: the arena's display name (`ARCADE CAGE`) under the TIME TRIAL kicker.
static func title(run: Dictionary) -> String:
	return area_name(str(run.get("location", "cage")))


static func area_name(location: String) -> String:
	var arena := CosmeticLibrary.get_arena(location)
	return str(arena.display_name).to_upper() if arena != null else location.to_upper()


## The board's short name: ARCADE / BEACH / PARK / CITY (the leaderboard header's right side).
static func board_name(location: String) -> String:
	match location:
		"beach":
			return "BEACH"
		"park":
			return "PARK"
		"city":
			return "CITY"
	return "ARCADE"


## The area's short word for RUN IT BACK: `60 S · SAME CAGE` / `SAME BEACH`.
static func run_sub(location: String, seconds := int(TimeTrial.TIME_TRIAL_SECONDS)) -> String:
	var word := "CAGE"
	match location:
		"beach":
			word = "BEACH"
		"park":
			word = "PARK"
		"city":
			word = "COURT"
	return "%d S · SAME %s" % [seconds, word]


## Not a best: `BEST 31 · 7 SHORT`, or `BEST 31 · LEVEL` on a tie (a tie is
## not a best: the earlier run keeps it).
static func best_line(top_score: int, score: int) -> String:
	var gap := top_score - score
	if gap <= 0:
		return "BEST %d · LEVEL" % top_score
	return "BEST %d · %d SHORT" % [top_score, gap]


## The stat tiles: MAKES · SWISHES · STREAK · BONUS, and ICED when it happened.
static func tiles(run: Dictionary) -> Array:
	var out := [
		{"v": "%d/%d" % [int(run.get("makes", 0)), int(run.get("attempts", 0))], "l": "MAKES"},
		{"v": str(int(run.get("swishes", 0))), "l": "SWISHES"},
		{"v": str(int(run.get("bestStreak", 0))), "l": "STREAK"},
		{"v": "+%d" % int(run.get("bonus", 0)), "l": "BONUS"},
	]
	if int(run.get("iced", 0)) > 0:
		out.push_back({"v": str(int(run.get("iced", 0))), "l": "ICED"})
	return out


static func _row(d: Dictionary, i: int, run_id: String) -> Dictionary:
	return {"n": str(i + 1), "pts": str(int(d.get("score", 0))), "sw": str(int(d.get("swishes", 0))),
		"st": str(int(d.get("bestStreak", 0))), "mine": run_id != "" and str(d.get("id", "")) == run_id}


## The top rows as [{n, pts, sw, st, mine}] with this run (by id) marked, capped at BOARD_SIZE.
static func board(top: Array, run_id: String) -> Array:
	var out := []
	for i in mini(top.size(), BOARD_SIZE):
		out.push_back(_row(top[i], i, run_id))
	return out


## The board as the page draws it: {top: the first BOARD_SIZE rows, out: [this
## run's row with its real rank] when it sits below them (a sixth row after a
## break), else []}. `top` is the area's whole list, best first.
static func board_rows(top: Array, run_id: String) -> Dictionary:
	var out := {"top": board(top, run_id), "out": []}
	for i in range(BOARD_SIZE, top.size()):
		if run_id != "" and str(Dictionary(top[i]).get("id", "")) == run_id:
			out["out"] = [_row(top[i], i, run_id)]
			break
	return out


## The tickets box: {n, big: "+30", sub: "TICKETS · BEST BONUS IN"}; with nothing
## earned it still reads (`+0`, dimmed on the page — `none`), no stream.
## An all-time global best (the big chime, Ross 2026-10-26): the run beats
## every row of the area's cached all-time board (Net.cached_board(area,
## "all"), the server's `rows` with `score`). No board in hand — offline, or
## never fetched — claims nothing; a tie is not a new best.
static func global_best(score: int, board: Dictionary) -> bool:
	var rows: Array = board.get("rows", []) if board.get("rows") is Array else []
	if rows.is_empty():
		return false
	var top := 0
	for r in rows:
		if r is Dictionary:
			top = maxi(top, int(r.get("score", 0)))
	return score > top


static func tickets(run: Dictionary, is_best: bool) -> Dictionary:
	var n := int(run.get("tickets", 0))
	if n <= 0:
		return {"n": 0, "big": "+0", "sub": "TICKETS", "none": true}
	if int(run.get("shoot_bonus", 0)) > 0:
		return {"n": n, "big": "+%d" % n, "sub": "TICKETS · +%d SHOOT AROUND" % int(run["shoot_bonus"]), "none": false}
	return {"n": n, "big": "+%d" % n, "sub": "TICKETS · BEST BONUS IN" if is_best else "TICKETS", "none": false}
