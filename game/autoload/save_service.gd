extends Node
## Local-first persistence. File-per-part under user://save/ — each file maps
## 1:1 onto a future cloud sync "part" (see docs/SYNC.md). The three things the
## old game's cloud audit found missing exist here from the first byte written:
## UUIDv4 ids, updatedAt stamps, and a persisted dirty-part outbox.
## M1 writes the outbox but never drains it — the network layer is M3+.

const SAVE_DIR := "user://save"
const META_PART := "meta"
const SCORES_PART := "time_trial_scores"
## Device-local flick tuning scratchpad (tuning mode flag + overridden fields).
## Never synced: it is a dev tool, not player state.
const TUNING_PART := "tuning"
## Player cosmetics: coins, and per kind (hoop / ball) the selected + owned set ids.
const COSMETICS_PART := "cosmetics"
## Player preferences (display / assist toggles). Player state, so it syncs —
## unlike the tuning scratchpad above, which is a device-local dev tool.
const SETTINGS_PART := "settings"
const CAMPAIGN_PART := "campaign"
const LIVE_GAMES_PART := "liveGames"
const CARDS_PART := "cards"
## The player's level: XP from league matches (docs/PROGRESSION.md).
const PROGRESS_PART := "progress"
const LIVE_GAMES_KEEP := 50
const SCHEMA_VERSION := 1

var _meta: Dictionary = {}
var _scores: Dictionary = {}
var _outbox: Dictionary = {}
var _tuning: Dictionary = {}
var _campaign: Dictionary = {}
var _live_games: Dictionary = {}
var _cards: Dictionary = {}
var _progress: Dictionary = {}
var _cosmetics: Dictionary = {}
var _settings: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	_meta = _read_json(META_PART)
	if _meta.is_empty():
		var now := _now_ms()
		_meta = {
			"schemaVersion": SCHEMA_VERSION,
			"clientId": uuid4(),
			"createdAt": now,
			"updatedAt": now,
		}
		_write_json(META_PART, _meta)
	_scores = _read_json(SCORES_PART)
	if _scores.is_empty():
		_scores = {"updatedAt": 0, "docs": []}
	_outbox = _read_json("outbox")
	if _outbox.is_empty():
		_outbox = {"dirtyParts": [], "lastSyncAt": null, "lastError": null}
	_tuning = _read_json(TUNING_PART)
	if _tuning.is_empty():
		_tuning = {"updatedAt": 0, "tuningMode": false, "fields": {}}
	_cosmetics = _read_json(COSMETICS_PART)
	if _cosmetics.is_empty():
		_cosmetics = default_cosmetics()
	elif _cosmetics.has("coins") and not _cosmetics.has("tickets"):
		# The one-wallet economy is gone: coins are per league now (cards part),
		# tickets are the locker money. Old coins are wiped (docs/ECONOMY.md).
		_cosmetics.erase("coins")
		_cosmetics["tickets"] = 0
		_write_json(COSMETICS_PART, _cosmetics)
	_settings = _read_json(SETTINGS_PART)
	if _settings.is_empty():
		_settings = default_settings()
	_campaign = _read_json(CAMPAIGN_PART)
	if _campaign.is_empty():
		_campaign = default_campaign()
	_live_games = _read_json(LIVE_GAMES_PART)
	if _live_games.is_empty():
		_live_games = {"updatedAt": 0, "docs": []}
	_cards = _read_json(CARDS_PART)
	if _cards.is_empty():
		_cards = CardDefs.empty_doc()
	elif CardDefs.migrate(_cards):
		_write_json(CARDS_PART, _cards)
	_progress = _read_json(PROGRESS_PART)
	if _progress.is_empty():
		_progress = default_progress()


## The player's level state (Progression.empty_state + updatedAt). New keys
## need no migration: Progression reads with .get().
static func default_progress() -> Dictionary:
	var d := Progression.empty_state()
	d["updatedAt"] = 0
	return d


func get_progress() -> Dictionary:
	return _progress.duplicate(true)


## Persist the level state. Player state: marked dirty for sync.
func put_progress(doc: Dictionary) -> void:
	_progress = doc.duplicate(true)
	_progress["updatedAt"] = _now_ms()
	_write_json(PROGRESS_PART, _progress)
	mark_dirty(PROGRESS_PART)


## Power-up cards, v3: {leagues: {id: {coins, inventory: {id: n}, loadout: [id|null ×3]}}}.
func get_cards() -> Dictionary:
	return _cards.duplicate(true)


func put_cards(doc: Dictionary) -> void:
	_cards = doc.duplicate(true)
	CardDefs.migrate(_cards)
	_cards["updatedAt"] = _now_ms()
	_write_json(CARDS_PART, _cards)
	mark_dirty(CARDS_PART)


## Leagues: one Campaign doc per league id, plus per-league records.
static func default_campaign() -> Dictionary:
	return {"updatedAt": 0, "leagues": {}, "records": {}}


func get_campaign() -> Dictionary:
	return _campaign.duplicate(true)


func put_campaign(doc: Dictionary) -> void:
	_campaign = doc.duplicate(true)
	_campaign["updatedAt"] = _now_ms()
	_write_json(CAMPAIGN_PART, _campaign)
	mark_dirty(CAMPAIGN_PART)


## The league doc for one league ({} when none started).
func league_doc(league_id: String) -> Dictionary:
	return _campaign.get("leagues", {}).get(league_id, {}).duplicate(true)


func put_league_doc(league_id: String, doc: Dictionary) -> void:
	var c := get_campaign()
	if not c.has("leagues"):   # an unloaded part (headless tests) starts empty
		c = default_campaign()
	if doc.get("id", "") == "":
		doc["id"] = uuid4()
	c["leagues"][league_id] = doc
	put_campaign(c)


## Heat box scores (the player's live heats), newest first, pruned.
func put_live_game(doc: Dictionary) -> Dictionary:
	var d := doc.duplicate(true)
	d["id"] = uuid4()
	d["playedAt"] = _now_ms()
	var docs: Array = _live_games.get("docs", [])
	docs.push_front(d)
	if docs.size() > LIVE_GAMES_KEEP:
		docs.resize(LIVE_GAMES_KEEP)
	_live_games["docs"] = docs
	_live_games["updatedAt"] = _now_ms()
	_write_json(LIVE_GAMES_PART, _live_games)
	mark_dirty(LIVE_GAMES_PART)
	return d


func live_games(league_id := "", limit := 10) -> Array:
	var out := []
	for d in _live_games.get("docs", []):
		if league_id == "" or d.get("leagueId", "") == league_id:
			out.push_back(d.duplicate(true))
	out.sort_custom(func(a, b): return int(a.get("playerScore", 0)) > int(b.get("playerScore", 0)))
	if out.size() > limit:
		out.resize(limit)
	return out


static func default_cosmetics() -> Dictionary:
	return {
		"updatedAt": 0,
		"tickets": 0,
		"hoop": {"selected": "classic", "owned": ["classic"]},
		"ball": {"selected": "classic", "owned": ["classic"]},
		"peggy": {"drops": 0},
	}


func get_cosmetics() -> Dictionary:
	return _cosmetics.duplicate(true)


## Persist tickets / selections / ownership. Player state: marked dirty for sync.
func put_cosmetics(doc: Dictionary) -> void:
	_cosmetics = doc.duplicate(true)
	_cosmetics["updatedAt"] = _now_ms()
	_write_json(COSMETICS_PART, _cosmetics)
	mark_dirty(COSMETICS_PART)


## Player preference toggles. New keys need no migration: every read site
## defaults with .get(), so an older save simply falls back.
static func default_settings() -> Dictionary:
	return {"updatedAt": 0, "shotHelp": 0, "newBalls": [], "visitedAreas": []}


func get_settings() -> Dictionary:
	return _settings.duplicate(true)


## Persist preference toggles. Player state: marked dirty for sync.
func put_settings(doc: Dictionary) -> void:
	_settings = doc.duplicate(true)
	_settings["updatedAt"] = _now_ms()
	_write_json(SETTINGS_PART, _settings)
	mark_dirty(SETTINGS_PART)


## Tuning scratchpad: {"updatedAt", "tuningMode": bool, "fields": {name: float}, "undo": {name: float}}.
func get_tuning() -> Dictionary:
	return _tuning.duplicate(true)


## Persist the tuning flag + field overrides (synchronous; call on toggle /
## Save / Reset, never per adjustment). Device-local: not marked dirty. The
## undo snapshot (below) rides along untouched.
func put_tuning(mode: bool, fields: Dictionary) -> void:
	_tuning = {"updatedAt": _now_ms(), "tuningMode": mode, "fields": fields.duplicate(),
		"undo": _tuning.get("undo", {})}
	_write_json(TUNING_PART, _tuning)


## The fields as they were before the last RESET, so it can be undone — even
## after a restart (a reset wiped a week of Ross's tuning once). Empty = no undo.
func put_tuning_undo(fields: Dictionary) -> void:
	_tuning["undo"] = fields.duplicate()
	_tuning["updatedAt"] = _now_ms()
	_write_json(TUNING_PART, _tuning)


func get_client_id() -> String:
	return str(_meta.get("clientId", ""))


## Record a finished time-trial run. Stamps id/updatedAt, persists, marks dirty.
func put_score(doc: Dictionary) -> Dictionary:
	var now := _now_ms()
	doc = doc.duplicate()
	doc["id"] = uuid4()
	doc["updatedAt"] = now
	if not doc.has("playedAt"):
		doc["playedAt"] = now
	_scores["docs"].push_back(doc)
	_scores["updatedAt"] = now
	_write_json(SCORES_PART, _scores)
	mark_dirty(SCORES_PART)
	return doc


## Top scores: score desc, earlier playedAt wins ties (original leaderboard rule).
## `location` filters to one court ("" = every court); runs saved before
## locations existed count as the arcade cage.
func top_scores(limit := 10, location := "") -> Array:
	var docs: Array = []
	for d in _scores.get("docs", []):   # an unloaded part (headless tests) is just empty
		if location == "" or d.get("location", "cage") == location:
			docs.push_back(d)
	docs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["playedAt"] < b["playedAt"]
	)
	return docs.slice(0, limit)


func score_count() -> int:
	return _scores["docs"].size()


## Is this score a new device best (for that court)?
func is_best(score: int, location := "") -> bool:
	var top := top_scores(1, location)
	return top.is_empty() or score > top[0]["score"]


# ---- sync seam (drained by the M3+ network layer, never by M1) ---------------


func mark_dirty(part: String) -> void:
	if not _outbox.has("dirtyParts"):   # an unloaded outbox (headless tests) starts empty
		_outbox["dirtyParts"] = []
	var parts: Array = _outbox["dirtyParts"]
	if not parts.has(part):
		parts.push_back(part)
	_write_json("outbox", _outbox)


func dirty_parts() -> Array:
	return _outbox["dirtyParts"].duplicate()


# ---- helpers ------------------------------------------------------------------


static func uuid4() -> String:
	var crypto := Crypto.new()
	var b := crypto.generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40  # version 4
	b[8] = (b[8] & 0x3F) | 0x80  # RFC 4122 variant
	var hexed := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hexed.substr(0, 8), hexed.substr(8, 4), hexed.substr(12, 4),
		hexed.substr(16, 4), hexed.substr(20, 12),
	]


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _part_path(part: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, part]


func _read_json(part: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(_part_path(part))
	if raw == "":
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


## Atomic write: tmp file + rename, so a crash mid-write never corrupts a part.
func _write_json(part: String, data: Dictionary) -> void:
	var path := _part_path(part)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveService: cannot write " + tmp)
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var global_tmp := ProjectSettings.globalize_path(tmp)
	var global_path := ProjectSettings.globalize_path(path)
	DirAccess.rename_absolute(global_tmp, global_path)
