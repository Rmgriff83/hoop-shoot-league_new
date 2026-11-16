extends RefCounted
## PlayGamesBackend over a stand-in `GodotPlayGameServices` singleton (the
## godot-play-game-services plugin's shape: methods that answer through
## signals) — the config gate, sign-in (the probe, then Google's UI once), the
## proof's shape, achievements through the play_id mapping, the error paths,
## and the null behaviour when the singleton or the ids are absent.


## The plugin's surface, scripted. Answers arrive a frame later, as the
## plugin's do (Google's tasks complete off the call).
class StubPlayGames:
	extends Object   # a singleton is a raw pointer: an Object, freed by hand below
	signal userAuthenticated(authenticated: bool)
	signal currentPlayerLoaded(json: String)
	signal serverSideAccessRequested(code: String)
	signal achievementUnlocked(unlocked: bool, id: String)
	signal achievementsLoaded(json: String)
	var calls: Array = []
	var authed := false
	var sign_in_ok := true
	var player := {"playerId": "g_123456789", "displayName": "Brick B.", "title": "Novice"}
	var code := "4/0AbCdEf"
	var code_silent := false
	var unlock_ok := true
	var unlocked: Array = []
	var ach_json := '[{"achievementId": "CgkI_pure_0001", "name": "PURE", "state": "STATE_UNLOCKED", "type": "TYPE_STANDARD"}, {"achievementId": "CgkI_on_fire_02", "name": "ON FIRE", "state": "STATE_REVEALED"}, {"achievementId": "CgkI_not_ours", "state": "STATE_UNLOCKED"}]'
	var shown := 0

	func initialize() -> void:
		calls.push_back("initialize")

	func isAuthenticated() -> void:
		calls.push_back("isAuthenticated")
		call_deferred("emit_signal", "userAuthenticated", authed)

	func signIn() -> void:
		calls.push_back("signIn")
		authed = sign_in_ok
		call_deferred("emit_signal", "userAuthenticated", authed)

	func loadCurrentPlayer(_force: bool) -> void:
		calls.push_back("loadCurrentPlayer")
		call_deferred("emit_signal", "currentPlayerLoaded", JSON.stringify(player))

	func requestServerSideAccess(client_id: String, force_refresh: bool) -> void:
		calls.push_back("requestServerSideAccess:%s:%s" % [client_id, str(force_refresh)])
		if not code_silent:
			call_deferred("emit_signal", "serverSideAccessRequested", code)

	func unlockAchievement(id: String) -> void:
		calls.push_back("unlock")
		unlocked.push_back(id)
		call_deferred("emit_signal", "achievementUnlocked", unlock_ok, id)

	func loadAchievements(_force: bool) -> void:
		calls.push_back("loadAchievements")
		call_deferred("emit_signal", "achievementsLoaded", ach_json)

	func showAchievements() -> void:
		shown += 1


const CFG := "user://qa_play_games.json"
const SINGLETON := "GodotPlayGameServices"


func run(t) -> void:
	var loop := Engine.get_main_loop()
	var tick := PlayGamesBackend.POLL_S + 0.2
	# The config gate.
	var repo_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/play_games.json"))
	var repo_placeholder: bool = str(repo_cfg.get("game_id", "")).contains("REPLACE_ME")
	t.eq(PlayGamesBackend.load_config("res://data/play_games.json").is_empty(), repo_placeholder, "the repo's data/play_games.json: real ids load, placeholders do not")
	var f := FileAccess.open(CFG, FileAccess.WRITE)
	f.store_string(JSON.stringify({"game_id": "123456789012", "web_client_id": "1234-abc.apps.googleusercontent.com"}))
	f.close()
	t.eq(PlayGamesBackend.load_config(CFG), {"game_id": "123456789012", "web_client_id": "1234-abc.apps.googleusercontent.com"}, "a real config loads both ids")
	for bad in [{"game_id": "REPLACE_ME", "web_client_id": "x.apps.googleusercontent.com"}, {"game_id": "12", "web_client_id": "REPLACE_ME.apps.googleusercontent.com"}, {"game_id": "abc", "web_client_id": "x.apps.googleusercontent.com"}, {"game_id": "12", "web_client_id": "x.example.com"}]:
		f = FileAccess.open("user://qa_play_games_bad.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(bad))
		f.close()
		t.ok(PlayGamesBackend.load_config("user://qa_play_games_bad.json").is_empty(), "rejected: %s" % JSON.stringify(bad))
	t.ok(PlayGamesBackend.load_config("user://no_such_play_games.json").is_empty(), "a missing file → no config")
	# No singleton: the null backend.
	t.ok(not Engine.has_singleton(SINGLETON), "(no GodotPlayGameServices singleton here)")
	var none := PlayGamesBackend.new(CFG)
	t.ok(not none.is_available() and not none.is_signed_in() and none.provider_id() == "playgames" and none.display_name() == "PLAY GAMES", "absent plugin: unavailable, named")
	none.sign_in()
	t.ok((await none.get_identity_proof()).is_empty(), "…no proof")
	t.ok(Platform.default_backend("Android") is PlayGamesBackend and Platform.default_backend("iOS") is GameCenterBackend and Platform.default_backend("macOS") is GameCenterBackend, "Platform picks Play Games on Android, Game Center elsewhere")

	var stub := StubPlayGames.new()
	Engine.register_singleton(SINGLETON, stub)
	f = FileAccess.open("user://qa_play_games_bad.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"game_id": "REPLACE_ME", "web_client_id": "REPLACE_ME.apps.googleusercontent.com"}))
	f.close()
	var gated := PlayGamesBackend.new("user://qa_play_games_bad.json")
	t.ok(not gated.is_available() and not stub.calls.has("initialize"), "the plugin present but placeholder ids: unavailable, the SDK never initialized")
	var repo := PlayGamesBackend.new()   # the repo's config
	t.eq(repo.is_available(), not repo_placeholder, "the repo's ids: available iff they are real")
	stub.calls.clear()
	var be := PlayGamesBackend.new(CFG)
	t.ok(be.is_available() and not be.is_signed_in(), "the singleton present and ids real: available, not signed in")
	t.eq(stub.calls, ["initialize"], "…the SDK initialized once on construction")
	t.ok((await be.get_identity_proof()).is_empty(), "no proof before a sign-in")
	var signed := []
	be.signed_in.connect(func() -> void: signed.push_back(true))
	# Google had not signed the player in by itself: the probe says no, the UI once.
	be.sign_in()
	await loop.create_timer(tick).timeout
	t.ok(be.is_signed_in() and signed.size() == 1 and be.player_name() == "Brick B." and be.player_id() == "g_123456789", "probe no → signIn → player loaded: signed in once, Google's name kept aside")
	t.eq(stub.calls, ["initialize", "isAuthenticated", "signIn", "loadCurrentPlayer"], "…the call order")
	be.sign_in()
	t.eq(stub.calls.size(), 4, "signed in: sign_in is a no-op")
	var proof: Dictionary = await be.get_identity_proof()
	t.eq(proof, {"serverAuthCode": "4/0AbCdEf", "playerId": "g_123456789"}, "the proof is the Worker's shape: the server auth code and the per-game player id")
	t.eq(stub.calls[4], "requestServerSideAccess:1234-abc.apps.googleusercontent.com:false", "…asked with the web client id, no refresh token")
	stub.code_silent = true
	var t0 := Time.get_ticks_msec()
	be.PROOF_WAIT_S
	# A silent plugin (it says nothing on a failure): the wait gives up. Shorten it for the test.
	var waited: Dictionary = await _proof_with_wait(be, 0.5)
	t.ok(waited.is_empty() and Time.get_ticks_msec() - t0 < 3000, "no code → no proof, after the wait")
	stub.code_silent = false
	# Achievements (docs/ACHIEVEMENTS.md): Apple ids in, play ids to Google.
	var def_pure: Dictionary = AchievementDefs.get_def("pure")
	var def_fire: Dictionary = AchievementDefs.get_def("on_fire")
	var was_pure := str(def_pure.get("play_id", ""))
	var was_fire := str(def_fire.get("play_id", ""))
	def_pure["play_id"] = "CgkI_pure_0001"
	def_fire["play_id"] = "CgkI_on_fire_02"
	AchievementDefs._by_play["CgkI_pure_0001"] = "pure"
	AchievementDefs._by_play["CgkI_on_fire_02"] = "on_fire"
	t.eq(AchievementDefs.play_id("pure"), "CgkI_pure_0001", "(the roster given two play ids for the test)")
	t.eq(AchievementDefs.key_for_play_id("CgkI_on_fire_02"), "on_fire", "…and back")
	t.eq(AchievementDefs.key_for_play_id(""), "", "an empty play id is nobody's")
	stub.calls.clear()
	var failed: Array = []
	be.achievement_failed.connect(func(id: String) -> void: failed.push_back(id))
	t.ok(be.unlock("hs.ach.pure"), "unlock: the plugin took the award")
	t.eq(stub.unlocked, ["CgkI_pure_0001"], "…as its play id")
	t.ok(not be.unlock("hs.ach.jackpot"), "a key with no play id yet → false (Achievements parks it)")
	t.ok(not be.unlock("hs.ach.nope") and not be.unlock(""), "an unknown id, or none → false")
	await loop.create_timer(tick).timeout
	t.ok(failed.is_empty(), "…the ok answer: nothing failed")
	stub.unlock_ok = false
	be.unlock("hs.ach.on_fire")
	await loop.create_timer(tick).timeout
	t.eq(failed, ["hs.ach.on_fire"], "an unlock Google refused → achievement_failed with its Apple id")
	var loaded: Dictionary = await be.load_achievements()
	t.eq(loaded, {"ok": true, "earned": ["hs.ach.pure"]}, "load_achievements: the unlocked ones as Apple ids, not the revealed one, not a stranger's id")
	stub.ach_json = '[{"achievementId": "CgkI_pure_0001", "state": 0}, {"achievementId": "CgkI_on_fire_02", "state": 1}]'
	t.eq(await be.load_achievements(), {"ok": true, "earned": ["hs.ach.pure"]}, "…Google's numeric states read the same way")
	stub.ach_json = "not json"
	t.eq(await be.load_achievements(), {"ok": true, "earned": []}, "…an unparsable answer → nothing earned (the plugin's empty list on an error)")
	t.ok(be.has_achievements_sheet() and be.show_achievements() and stub.shown == 1, "the sheet opens")
	t.ok(not none.unlock("hs.ach.pure") and not none.show_achievements() and not (await none.load_achievements())["ok"], "the absent plugin: no awards, no sheet, no list")
	def_pure["play_id"] = was_pure
	def_fire["play_id"] = was_fire
	AchievementDefs._by_play.erase("CgkI_pure_0001")
	AchievementDefs._by_play.erase("CgkI_on_fire_02")
	# Google had already signed the player in: the probe says yes, no UI.
	stub.authed = true
	stub.calls.clear()
	var be2 := PlayGamesBackend.new(CFG)
	be2.sign_in()
	await loop.create_timer(tick).timeout
	t.ok(be2.is_signed_in(), "probe yes: signed in")
	t.eq(stub.calls, ["initialize", "isAuthenticated", "loadCurrentPlayer"], "…without Google's sign-in UI")
	# The player declines Google's UI.
	stub.authed = false
	stub.sign_in_ok = false
	stub.calls.clear()
	var be3 := PlayGamesBackend.new(CFG)
	be3.sign_in()
	await loop.create_timer(tick).timeout
	t.ok(not be3.is_signed_in() and not be3._signing, "the UI declined: not signed in, nothing pending")
	t.eq(stub.calls, ["initialize", "isAuthenticated", "signIn"], "…the UI shown once")
	be3.sign_in()
	await loop.create_timer(tick).timeout
	t.eq(stub.calls, ["initialize", "isAuthenticated", "signIn", "isAuthenticated"], "a later sign_in probes again but never re-opens the UI this launch")
	Engine.unregister_singleton(SINGLETON)
	t.ok(not Engine.has_singleton(SINGLETON) and not PlayGamesBackend.new(CFG).is_available(), "(unregistered again)")
	stub.free()
	t.ok(not be.is_available(), "a backend whose plugin is gone is unavailable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://qa_play_games_bad.json"))


## get_identity_proof with a shorter give-up, so the silent case does not hold the suite 15 s.
func _proof_with_wait(be: PlayGamesBackend, wait: float) -> Dictionary:
	be._code = ""
	be._proof_waiting = true
	be._pg.call("requestServerSideAccess", "x", false)
	await be._pump(wait, func() -> bool: return be._code != "")
	be._proof_waiting = false
	return {} if be._code == "" else {"serverAuthCode": be._code}
