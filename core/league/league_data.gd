class_name LeagueData
extends RefCounted
## The authored league content: data/shooters.json (15 AI shooters, ported
## from the original's shooters.ts) and data/leagues.json (one league per
## location: roster, difficulty, format, unlock rule, rewards). Loaded once,
## validated by tests/test_league_data.gd.

const SHOOTERS_PATH := "res://data/shooters.json"
const LEAGUES_PATH := "res://data/leagues.json"
const PLAYER_ID := "player"

static var _shooters: Array = []
static var _leagues: Array = []
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_shooters = _read(SHOOTERS_PATH).get("shooters", [])
	_leagues = _read(LEAGUES_PATH).get("leagues", [])


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func shooters() -> Array:
	_load()
	return _shooters


static func shooter(id: String) -> Dictionary:
	_load()
	for s in _shooters:
		if s["id"] == id:
			return s
	return {}


static func ratings_of(id: String) -> AiRatings:
	var s := shooter(id)
	return AiRatings.from_dict(s.get("ratings", {})) if not s.is_empty() else AiRatings.make(0.5, 0.5)


static func leagues() -> Array:
	_load()
	return _leagues


static func league(id: String) -> Dictionary:
	_load()
	for l in _leagues:
		if l["id"] == id:
			return l
	return {}


## The league's team ids: the player first, then the roster in order.
static func team_ids(league_cfg: Dictionary) -> Array:
	var out := [PLAYER_ID]
	for id in league_cfg.get("roster", []):
		out.push_back(str(id))
	return out


## id → AiRatings for every AI team in the league.
static func league_ratings(league_cfg: Dictionary) -> Dictionary:
	var out := {}
	for id in league_cfg.get("roster", []):
		out[str(id)] = ratings_of(str(id))
	return out


## Problems with the data files (empty = fine).
static func validate() -> PackedStringArray:
	_load()
	var problems := PackedStringArray()
	var ids := {}
	for s in _shooters:
		for key in ["id", "name", "hometown", "number", "nickname", "colors", "ratings"]:
			if not s.has(key):
				problems.push_back("shooter %s missing %s" % [s.get("id", "?"), key])
		if ids.has(s.get("id", "")):
			problems.push_back("duplicate shooter id %s" % s.get("id", ""))
		ids[s.get("id", "")] = true
	for l in _leagues:
		for key in ["id", "name", "location", "mode", "roster", "err_mult", "heat_seconds", "rounds", "playoff_teams", "semis_best_of", "final_best_of"]:
			if not l.has(key):
				problems.push_back("league %s missing %s" % [l.get("id", "?"), key])
		for id in l.get("roster", []):
			if not ids.has(str(id)):
				problems.push_back("league %s roster names unknown shooter %s" % [l.get("id", "?"), id])
		if (Array(l.get("roster", [])).size() + 1) % 2 != 0:
			problems.push_back("league %s needs an even team count" % l.get("id", "?"))
		var unlock: Variant = l.get("unlock", null)
		if unlock != null and (not (unlock is Dictionary) or not unlock.has("level")):
			problems.push_back("league %s has a malformed unlock rule (needs a level)" % l.get("id", "?"))
		var levels: Variant = l.get("levels", null)
		if not (levels is Dictionary) or not levels.has("min") or not levels.has("cap"):
			problems.push_back("league %s needs a levels band {min, cap}" % l.get("id", "?"))
		for key in ["win_coins", "loss_coins", "title_coins", "win_tickets", "loss_tickets", "title_tickets"]:
			if not Dictionary(l.get("rewards", {})).has(key):
				problems.push_back("league %s rewards missing %s" % [l.get("id", "?"), key])
		_validate_cards(l, problems)
	return problems


## The card allowance fields (docs/CARDS.md): every authored or pooled id is a
## real card, the authored hands fit the allowance and the per-hand cap.
static func _validate_cards(l: Dictionary, problems: PackedStringArray) -> void:
	var lid := str(l.get("id", "?"))
	for key in ["ai_cards_per_season", "ai_hand_max", "ai_pool", "card_parity"]:
		if not l.has(key):
			problems.push_back("league %s missing %s" % [lid, key])
	var authored: Dictionary = l.get("ai_cards", {})
	var total := 0
	var cap := int(l.get("ai_hand_max", 1 << 30))
	for sid in authored:
		if not Array(l.get("roster", [])).has(str(sid)):
			problems.push_back("league %s ai_cards names %s, not on its roster" % [lid, sid])
		var hand := Array(authored[sid])
		if hand.size() > cap:
			problems.push_back("league %s authored hand for %s exceeds ai_hand_max %d" % [lid, sid, cap])
		for id in hand:
			total += 1
			if CardDefs.get_card(str(id)).is_empty():
				problems.push_back("league %s ai_cards gives %s unknown card %s" % [lid, sid, id])
	if total > int(l.get("ai_cards_per_season", total)):
		problems.push_back("league %s authored cards (%d) exceed ai_cards_per_season (%d)" % [lid, total, int(l.get("ai_cards_per_season", 0))])
	for id in Array(l.get("ai_pool", [])):
		if CardDefs.get_card(str(id)).is_empty():
			problems.push_back("league %s ai_pool names unknown card %s" % [lid, id])
	if l.has("ai_pool") and Array(l["ai_pool"]).is_empty():
		problems.push_back("league %s has an empty ai_pool" % lid)
