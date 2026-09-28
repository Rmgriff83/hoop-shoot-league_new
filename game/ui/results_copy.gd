class_name ResultsCopy
extends RefCounted
## The time-trial results page's copy (design "Time Trial Results",
## docs/HOME.md → Results), pure and headless: the header line, the gap to
## your best, the stat tiles (ICED only when it happened), the board rows
## with this run marked, the tickets card and the RUN IT BACK sub-line.
## Reads App.last_run's shape ({score, makes, attempts, swishes, bestStreak,
## bonus, iced, location, id, tickets}) and SaveService.top_scores rows.

const BOARD_SIZE := 10


## `ARCADE CAGE · TIME TRIAL` — the arena's display name over the location.
static func title(run: Dictionary) -> String:
	return "%s · TIME TRIAL" % area_name(str(run.get("location", "cage")))


static func area_name(location: String) -> String:
	var arena := CosmeticLibrary.get_arena(location)
	return str(arena.display_name).to_upper() if arena != null else location.to_upper()


## The board's short name: ARCADE / BEACH / CITY (the leaderboard header's right side).
static func board_name(location: String) -> String:
	return "BEACH" if location == "beach" else ("CITY" if location == "city" else "ARCADE")


## The area's short word for RUN IT BACK: `60 S · SAME CAGE` / `SAME BEACH`.
static func run_sub(location: String, seconds := int(TimeTrial.TIME_TRIAL_SECONDS)) -> String:
	return "%d S · SAME %s" % [seconds, "BEACH" if location == "beach" else ("COURT" if location == "city" else "CAGE")]


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


## The top rows as [{n, pts, sw, st, mine}] with this run (by id) marked.
static func board(top: Array, run_id: String) -> Array:
	var out := []
	for i in mini(top.size(), BOARD_SIZE):
		var d: Dictionary = top[i]
		out.push_back({"n": str(i + 1), "pts": str(int(d.get("score", 0))), "sw": str(int(d.get("swishes", 0))),
			"st": str(int(d.get("bestStreak", 0))), "mine": run_id != "" and str(d.get("id", "")) == run_id})
	return out


## The tickets card: {big: "+30", sub: "TICKETS · BEST BONUS IN"}, or {} when nothing was earned.
static func tickets(run: Dictionary, is_best: bool) -> Dictionary:
	var n := int(run.get("tickets", 0))
	if n <= 0:
		return {}
	return {"big": "+%d" % n, "sub": "TICKETS · BEST BONUS IN" if is_best else "TICKETS"}
