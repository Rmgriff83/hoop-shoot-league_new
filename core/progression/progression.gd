class_name Progression
extends RefCounted
## The player's level (docs/PROGRESSION.md), headless: XP comes only from
## league matches, scaled by how well you played; each league spans a band
## of levels and caps there (the cap is the next card's level and the next
## league's unlock); a season pays about a level (soft-capped), the title
## jumps you to the cap. Levels gate cards (you can hold one early, not play
## it) and areas. Every number is data/progression.json + the `levels` /
## `unlock` / `xp_mult` rows in data/leagues.json and `level` on each card.
## State is the save's `progress` part: {xp, seasonXp, seasonKey}.

const PATH := "res://data/progression.json"

static var _doc: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_doc = parsed


static func doc() -> Dictionary:
	_load()
	return _doc


static func xp_per_level() -> int:
	return int(doc().get("xp_per_level", 100))


static func start_level() -> int:
	return int(doc().get("start_level", 1))


static func empty_state() -> Dictionary:
	return {"xp": 0, "seasonXp": 0, "seasonKey": ""}


# ---- levels ----------------------------------------------------------------------


static func level_for(xp: int) -> int:
	return start_level() + maxi(xp, 0) / xp_per_level()


## Progress inside the current level, 0-1.
static func frac_for(xp: int) -> float:
	return float(maxi(xp, 0) % xp_per_level()) / float(xp_per_level())


## XP into the current level and the level's size, for copy ("64/100").
static func xp_in_level(xp: int) -> Array:
	return [maxi(xp, 0) % xp_per_level(), xp_per_level()]


## The XP where a league's band tops out ((cap − start) × per level).
static func cap_xp(league: Dictionary) -> int:
	return (cap_level(league) - start_level()) * xp_per_level()


static func cap_level(league: Dictionary) -> int:
	return int(Dictionary(league.get("levels", {})).get("cap", start_level()))


static func min_level(league: Dictionary) -> int:
	return int(Dictionary(league.get("levels", {})).get("min", start_level()))


## At the league's cap: its matches pay nothing more.
static func at_cap(xp: int, league: Dictionary) -> bool:
	return xp >= cap_xp(league)


# ---- a match ---------------------------------------------------------------------


## The match's raw XP from the formula (before the league cap and the season
## soft cap), as a float: the win or the loss, the swishes, the best streak,
## a wide win, an overtime win, the playoff and league multipliers.
static func match_raw(result: Dictionary, league: Dictionary, playoff: bool) -> float:
	var m: Dictionary = doc().get("match", {})
	var won := bool(result.get("won", false))
	var you: Dictionary = Dictionary(result.get("sides", {})).get("player", {})
	var raw := float(m.get("win", 9)) if won else float(m.get("loss", 2))
	raw += float(m.get("per_swish", 0.4)) * int(you.get("swishes", 0))
	var streak := int(you.get("bestStreak", 0))
	var bonus := 0.0
	for tier in m.get("streak", []):
		if streak >= int(tier[0]):
			bonus = float(tier[1])
	raw += bonus
	var margin: Array = m.get("margin", [10, 2])
	if won and int(result.get("player_score", 0)) - int(result.get("ai_score", 0)) >= int(margin[0]):
		raw += float(margin[1])
	if won and int(result.get("ot", 0)) > 0:
		raw += float(m.get("ot_win", 1))
	if playoff:
		raw *= float(m.get("playoff_mult", 1.5))
	return raw * float(league.get("xp_mult", 1.0))


## What a match pays given the season's XP so far: XP past the season's
## soft cap counts at the over-cap rate. Returns {raw, gained} (ints).
static func match_xp(result: Dictionary, league: Dictionary, season_xp: int, playoff: bool) -> Dictionary:
	var raw := match_raw(result, league, playoff)
	var cap := int(doc().get("season_soft_cap", 100))
	var rate := float(doc().get("over_cap_rate", 0.3))
	var room := maxf(float(cap - season_xp), 0.0)
	var under := minf(raw, room)
	var over := raw - under
	return {"raw": roundi(raw), "gained": roundi(under + over * rate)}


## Fold a match into the state: {gained, level_before, level_after, capped}.
## `capped`: the league's cap took some or all of it.
static func apply_match(state: Dictionary, result: Dictionary, league: Dictionary, year: int) -> Dictionary:
	var key := "%s:%d" % [str(league.get("id", "")), year]
	if str(state.get("seasonKey", "")) != key:
		state["seasonKey"] = key
		state["seasonXp"] = 0
	var before := int(state.get("xp", 0))
	var pay := match_xp(result, league, int(state.get("seasonXp", 0)), bool(Dictionary(result.get("league", {})).get("playoff", false)))
	var gained := int(pay["gained"])
	var after := mini(before + gained, maxi(cap_xp(league), before))
	state["xp"] = after
	state["seasonXp"] = int(state.get("seasonXp", 0)) + (after - before)
	return {"gained": after - before, "level_before": level_for(before), "level_after": level_for(after), "capped": after - before < gained}


## The title: straight to the league's cap. {gained, level_before, level_after}.
static func apply_title(state: Dictionary, league: Dictionary) -> Dictionary:
	var before := int(state.get("xp", 0))
	var after := maxi(before, cap_xp(league))
	state["xp"] = after
	return {"gained": after - before, "level_before": level_for(before), "level_after": level_for(after), "capped": false}


# ---- gates -----------------------------------------------------------------------


static func card_level(card: Dictionary) -> int:
	return int(card.get("level", start_level()))


static func can_use(level: int, card: Dictionary) -> bool:
	return level >= card_level(card)


## The lowest-level card above the level (the carrot), or {}.
static func next_card(level: int) -> Dictionary:
	var best := {}
	for c in CardDefs.all():
		if card_level(c) > level and (best.is_empty() or card_level(c) < card_level(best)):
			best = c
	return best


static func league_unlocked(level: int, league: Dictionary) -> bool:
	var rule: Variant = league.get("unlock", null)
	if rule == null or not (rule is Dictionary):
		return true
	return level >= int(rule.get("level", start_level()))


## The level an area needs: the lowest unlock among its leagues (open = start).
static func area_level(location: String) -> int:
	var need := -1
	for l in LeagueData.leagues():
		if str(l.get("location", "")) != location:
			continue
		var rule: Variant = l.get("unlock", null)
		var lvl := int(rule.get("level", start_level())) if rule is Dictionary else start_level()
		need = lvl if need < 0 else mini(need, lvl)
	return need if need >= 0 else start_level()


static func area_unlocked(level: int, location: String) -> bool:
	return level >= area_level(location)


# ---- data ------------------------------------------------------------------------


## The shipped data holds together: bands run start → cap → next min, a
## league's unlock is the previous cap, every card's level is a band edge.
static func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var leagues := LeagueData.leagues()
	var edges := {}
	var prev_cap := -1
	for i in leagues.size():
		var l: Dictionary = leagues[i]
		var lv: Dictionary = l.get("levels", {})
		if not lv.has("min") or not lv.has("cap"):
			problems.push_back("league %s has no levels band" % l.get("id", "?"))
			continue
		if int(lv["cap"]) <= int(lv["min"]):
			problems.push_back("league %s band does not rise" % l.get("id", "?"))
		edges[int(lv["min"])] = true
		edges[int(lv["cap"])] = true
		if i == 0 and int(lv["min"]) != start_level():
			problems.push_back("the first league starts above the start level")
		if prev_cap >= 0 and int(lv["min"]) != prev_cap:
			problems.push_back("league %s starts at %d, the previous cap is %d" % [l.get("id", "?"), int(lv["min"]), prev_cap])
		var rule: Variant = l.get("unlock", null)
		if i > 0 and (not (rule is Dictionary) or int(rule.get("level", -1)) != prev_cap):
			problems.push_back("league %s should unlock at level %d" % [l.get("id", "?"), prev_cap])
		if float(l.get("xp_mult", 1.0)) <= 0.0:
			problems.push_back("league %s xp_mult must be positive" % l.get("id", "?"))
		prev_cap = int(lv["cap"])
	for c in CardDefs.all():
		if not c.has("level"):
			problems.push_back("card %s has no level" % c.get("id", "?"))
		elif not edges.has(int(c["level"])):
			problems.push_back("card %s level %d is not a league band edge" % [c.get("id", "?"), int(c["level"])])
	return problems
