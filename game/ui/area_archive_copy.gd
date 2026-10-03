class_name AreaArchiveCopy
extends RefCounted
## The area archive's copy (design "Area Archive" 17a, docs/HOME.md → Area
## archive), pure and headless: the areas in page order, how many are open,
## each area's row — name, stars, the level that opens it, whether it is
## locked, its titles, seasons and best trial score — and the history line.
## The home page and the snapshot tool read AREAS too, so it is the single
## list of areas.

const AREAS := [{"area": "cage", "mode": "practice"}, {"area": "beach", "mode": "beach"}, {"area": "city", "mode": "city"}]


static func ids() -> Array:
	var out := []
	for a in AREAS:
		out.push_back(str(a["area"]))
	return out


static func index_of(id: String) -> int:
	for i in AREAS.size():
		if str(AREAS[i]["area"]) == id:
			return i
	return -1


static func level_pad(level: int) -> String:
	return "LVL%02d" % level


static func lock_line(lvl: int) -> String:
	return "OPENS AT LVL %d" % lvl


## `2/3 OPEN` from the rows (or [{lvl}] dicts) at a level.
static func open_count(level: int, rows: Array) -> String:
	var n := 0
	for r in rows:
		if r.has("locked"):
			if not bool(r["locked"]):
				n += 1
		elif level >= int(r.get("lvl", 1)):
			n += 1
	return "%d/%d OPEN" % [n, rows.size()]


## `["2 TITLES", "3 SEASONS", "BEST 31"]` (singulars, `NO RUNS`).
static func history(titles: int, seasons: int, best: int) -> Array:
	return [
		"%d %s" % [titles, "TITLE" if titles == 1 else "TITLES"],
		"%d %s" % [seasons, "SEASON" if seasons == 1 else "SEASONS"],
		"BEST %d" % best if best > 0 else "NO RUNS",
	]


## Every area's best trial score, {id: best} (game layer: the save).
static func bests() -> Dictionary:
	var out := {}
	for a in AREAS:
		var id := str(a["area"])
		var top: Array = SaveService.top_scores(1, id)
		out[id] = int(top[0]["score"]) if not top.is_empty() else 0
	return out


## The rows at a level: [{id, mode, name, stars, lvl, locked, titles,
## seasons, best, history}]. `states` are App.league_states() rows.
static func rows(level: int, states: Array, best_by_area: Dictionary, gating := true, visited: Array = []) -> Array:
	var out := []
	for a in AREAS:
		var id := str(a["area"])
		var arena := CosmeticLibrary.get_arena(id)
		var lvl := Progression.area_level(id)
		var titles := 0
		var seasons := 0
		for st in states:
			var cfg: Dictionary = st.get("league", {})
			if str(cfg.get("location", "")) != id:
				continue
			var doc: Dictionary = st.get("doc", {})
			var career: Dictionary = doc.get("career", {})
			titles = int(career.get("championships", 0))
			seasons = Array(career.get("seasons", [])).size()
		var best := int(best_by_area.get(id, 0))
		var locked := gating and level < lvl
		out.push_back({
			"unvisited": not locked and not visited.has(id),
			"id": id, "mode": str(a["mode"]),
			"name": (str(arena.display_name) if arena != null else id).to_upper(),
			"stars": maxi(int(arena.title_stars), 1) if arena != null else 1,
			"lvl": lvl, "locked": locked,
			"titles": titles, "seasons": seasons, "best": best,
			"history": history(titles, seasons, best),
		})
	return out


## Every string on the page, for the glyph check.
static func strings(rows_: Array, open_text: String) -> Array:
	var out := ["AREAS", open_text, "<", ">"]
	for r in rows_:
		out.push_back(str(r["name"]))
		out.push_back(lock_line(int(r["lvl"])))
		for h in r["history"]:
			out.push_back(str(h))
	return out
