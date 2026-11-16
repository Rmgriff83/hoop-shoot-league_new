class_name PlayGamesBackend
extends PlatformBackend
## Play Games Services (Android) behind `Platform`, over the
## godot-sdk-integrations/godot-play-game-services `GodotPlayGameServices`
## singleton (tools/fetch_play_games_plugin.sh; addons/PlayGamesPlugin ships it
## in the Play build; docs/BACKEND.md → Platform identity → Android). The
## plugin answers through signals on the singleton, so every wait here is a
## short timer loop on a flag the handlers set. The proof is a single-use
## server auth code from `requestServerSideAccess(WEB_CLIENT_ID, false)` plus
## the per-game player id the phone sees — the Worker's `playgames` verifier
## exchanges the code with that client's secret and checks the id matches.
## Achievements (docs/ACHIEVEMENTS.md): `Achievements` speaks Apple ids, so
## `unlock` / `load_achievements` map apple_id → key → play_id here, with
## Google's generated ids from data/achievements.json; a key whose play_id is
## still "" cannot be reported (unlock returns false and Achievements parks it).
## Off a Play build with the plugin the singleton is absent and this is the
## null backend (`is_available()` false) — as it is with placeholder ids in
## data/play_games.json, where the export leaves the plugin out anyway.

## An unlock the plugin reported as not unlocked (its Apple id).
signal achievement_failed(id: String)

const SINGLETON := "GodotPlayGameServices"
const CONFIG := "res://data/play_games.json"
const PLACEHOLDER := "REPLACE_ME"
## Flags are read this often while something is pending.
const POLL_S := 0.25
## A sign-in that never answers is given up on after this long (Google's
## sign-in UI can sit open); a server auth code or the earned list, sooner.
const SIGN_IN_WAIT_S := 60.0
const PROOF_WAIT_S := 15.0
const ACHIEVEMENTS_WAIT_S := 15.0
## Google's state names in the plugin's achievement JSON.
const UNLOCKED := "STATE_UNLOCKED"

var _pg: Object
var _cfg := {}
var _signed := false
var _signing := false
## The isAuthenticated probe said no and signIn() has been shown once this launch.
var _sign_in_shown := false
var _player_id := ""
var _name := ""
## The last server auth code (consumed by get_identity_proof).
var _code := ""
var _proof_waiting := false
## The last achievementsLoaded payload, parsed (consumed by load_achievements).
var _ach_list: Variant = null
var _ach_waiting := false
## Unlock calls out, play_id → apple_id, until the plugin answers.
var _awards := {}


func _init(config_path: String = CONFIG) -> void:
	_cfg = load_config(config_path)
	if Engine.has_singleton(SINGLETON):
		_pg = Engine.get_singleton(SINGLETON)
		_pg.connect("userAuthenticated", _on_authenticated)
		_pg.connect("currentPlayerLoaded", _on_player)
		_pg.connect("serverSideAccessRequested", _on_code)
		_pg.connect("achievementUnlocked", _on_unlocked)
		_pg.connect("achievementsLoaded", _on_achievements)
		if is_available():
			_pg.call("initialize")   # PlayGamesSdk.initialize: starts Google's automatic sign-in


## data/play_games.json; {} when it is missing or still carries placeholders.
static func load_config(path: String = CONFIG) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var d := Dictionary(parsed)
	var game_id := str(d.get("game_id", ""))
	var client := str(d.get("web_client_id", ""))
	if game_id == "" or client == "" or game_id.contains(PLACEHOLDER) or client.contains(PLACEHOLDER):
		return {}
	if not game_id.is_valid_int() or not client.ends_with(".apps.googleusercontent.com"):
		return {}
	return {"game_id": game_id, "web_client_id": client}


func provider_id() -> String:
	return "playgames"


func display_name() -> String:
	return "PLAY GAMES"


## The plugin present and the ids real (a build never ships one without the other).
func is_available() -> bool:
	return _pg != null and is_instance_valid(_pg) and not _cfg.is_empty()


func is_signed_in() -> bool:
	return is_available() and _signed


## Google's name for the player (never adopted as the handle).
func player_name() -> String:
	return _name


## The per-game Play Games player id ("" before a sign-in).
func player_id() -> String:
	return _player_id


## Google signs the player in by itself when the game starts; this asks
## whether it did, and shows the sign-in UI once if not. Either answer lands
## in `userAuthenticated`; a yes is followed by the player load.
func sign_in() -> void:
	if not is_available() or _signing or _signed:
		return
	_signing = true
	_pg.call("isAuthenticated")
	_pump(SIGN_IN_WAIT_S, func() -> bool: return not _signing)
	# No answer: a later sign_in may try again.
	if _signing:
		_signing = false


## The proof for the Worker, or {} (not signed in, no code within PROOF_WAIT_S
## — the plugin says nothing on a failure).
func get_identity_proof() -> Dictionary:
	if not is_signed_in() or _proof_waiting:
		return {}
	_code = ""
	_proof_waiting = true
	_pg.call("requestServerSideAccess", str(_cfg.get("web_client_id", "")), false)
	await _pump(PROOF_WAIT_S, func() -> bool: return _code != "")
	_proof_waiting = false
	var code := _code
	_code = ""
	if code == "" or _player_id == "":
		return {}
	return {"serverAuthCode": code, "playerId": _player_id}


## Report an achievement complete (its Apple id, as Achievements speaks). True
## when the plugin took the call; Google answers through `achievementUnlocked`
## (a no → achievement_failed). Play shows its own popup: `banner` is Apple's.
func unlock(id: String, _banner := true) -> bool:
	if not is_signed_in() or id == "":
		return false
	var play := AchievementDefs.play_id(AchievementDefs.key_for_apple_id(id))
	if play == "":
		return false
	_awards[play] = id
	_pg.call("unlockAchievement", play)
	return true


## The player's unlocked achievements from Google, as Apple ids: {ok, earned}.
func load_achievements() -> Dictionary:
	if not is_signed_in() or _ach_waiting:
		return {"ok": false, "earned": []}
	_ach_list = null
	_ach_waiting = true
	_pg.call("loadAchievements", true)
	await _pump(ACHIEVEMENTS_WAIT_S, func() -> bool: return _ach_list != null)
	_ach_waiting = false
	var list: Variant = _ach_list
	_ach_list = null
	if not list is Array:
		return {"ok": false, "earned": []}
	var earned := []
	for row in Array(list):
		if not row is Dictionary:
			continue
		var d := Dictionary(row)
		if not _is_unlocked(d.get("state")):
			continue
		var key := AchievementDefs.key_for_play_id(str(d.get("achievementId", "")))
		if key != "":
			earned.push_back(AchievementDefs.apple_id(key))
	return {"ok": true, "earned": earned}


## The plugin's JSON names the state (the addon maps it through its enum);
## a bare number is Google's own constant, 0 = unlocked.
static func _is_unlocked(state: Variant) -> bool:
	if state is String:
		return state == UNLOCKED
	if state is float or state is int:
		return int(state) == 0
	return false


func has_achievements_sheet() -> bool:
	return is_available()


## Google's achievements screen.
func show_achievements() -> bool:
	if not is_signed_in():
		return false
	_pg.call("showAchievements")
	return true


## Wait, POLL_S at a time, until `until` says so, for at most `wait` seconds.
func _pump(wait: float, until: Callable) -> void:
	var left := wait
	while left > 0.0:
		if until.call():
			return
		var loop := Engine.get_main_loop() as SceneTree
		if loop == null:
			return
		await loop.create_timer(POLL_S).timeout
		left -= POLL_S


func _on_authenticated(authenticated: bool) -> void:
	if authenticated:
		_pg.call("loadCurrentPlayer", true)
		return
	if _signing and not _sign_in_shown:
		_sign_in_shown = true
		_pg.call("signIn")
		return
	_signed = false
	_signing = false


func _on_player(json: String) -> void:
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		_signing = false
		return
	var d := Dictionary(parsed)
	var id := str(d.get("playerId", ""))
	if id == "":
		_signing = false
		return
	_player_id = id
	_name = str(d.get("displayName", ""))
	var was := _signed
	_signed = true
	_signing = false
	if not was:
		signed_in.emit()


func _on_code(code: String) -> void:
	_code = code


func _on_unlocked(unlocked: bool, play: String) -> void:
	var apple := str(_awards.get(play, ""))
	_awards.erase(play)
	if not unlocked:
		push_warning("PlayGames: unlock %s failed" % play)
		if apple != "":
			achievement_failed.emit(apple)


func _on_achievements(json: String) -> void:
	var parsed: Variant = JSON.parse_string(json)
	_ach_list = parsed if parsed is Array else []
