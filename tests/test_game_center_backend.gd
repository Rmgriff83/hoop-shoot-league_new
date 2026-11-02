extends RefCounted
## GameCenterBackend over a stand-in `GameCenter` singleton (the vendored
## plugin's shape: methods that return an Error and a queue of event
## dictionaries) — sign-in, the proof's shape, the error paths, and the null
## behaviour when the singleton is absent.


## The plugin's surface, scripted.
class StubGameCenter:
	extends Object   # a singleton is a raw pointer: an Object, freed by hand below
	var events: Array = []
	var calls: Array = []
	var auth_err: int = OK
	var sig_err: int = OK
	var auth_event := {"type": "authentication", "result": "ok", "alias": "brick", "displayName": "Brick B.", "player_id": "T:abc"}
	var sig_event := {"type": "identity_verification_signature", "result": "ok", "public_key_url": "https://static.gc.apple.com/public-key/gc-prod-9.cer",
		"signature": "c2ln", "salt": "c2FsdA==", "timestamp": 1761955200000, "player_id": "T:abc"}
	var authed := false
	var award_err: int = OK
	var award_result := "ok"
	var awards: Array = []
	var ach_event := {"type": "achievements", "result": "ok", "names": PackedStringArray(["hs.ach.pure", "hs.ach.on_fire"]), "progress": PackedFloat32Array([100.0, 40.0])}
	var shown: Array = []

	func award_achievement(params: Dictionary) -> int:
		calls.push_back("award")
		if award_err == OK:
			awards.push_back(params.duplicate())
			events.push_back({"type": "award_achievement", "result": award_result, "name": str(params.get("name", "")), "error_code": 3})
		return award_err

	func request_achievements() -> void:
		calls.push_back("achievements")
		events.push_back(ach_event.duplicate())

	func show_game_center(params: Dictionary) -> int:
		shown.push_back(params.duplicate())
		return OK

	func authenticate() -> int:
		calls.push_back("authenticate")
		if auth_err == OK:
			events.push_back(auth_event.duplicate())
			authed = str(auth_event.get("result", "")) == "ok"
		return auth_err

	func is_authenticated() -> bool:
		return authed

	func request_identity_verification_signature() -> int:
		calls.push_back("signature")
		if sig_err == OK:
			events.push_back(sig_event.duplicate())
		return sig_err

	func get_pending_event_count() -> int:
		return events.size()

	func pop_pending_event() -> Variant:
		return events.pop_front()


func run(t) -> void:
	var loop := Engine.get_main_loop()
	# No singleton: the null backend.
	t.ok(not Engine.has_singleton("GameCenter"), "(no GameCenter singleton here)")
	var none := GameCenterBackend.new()
	t.ok(not none.is_available() and not none.is_signed_in() and none.provider_id() == "gamecenter" and none.display_name() == "GAME CENTER", "absent plugin: unavailable, named")
	none.sign_in()
	t.ok((await none.get_identity_proof()).is_empty(), "…no proof")

	var stub := StubGameCenter.new()
	Engine.register_singleton("GameCenter", stub)
	var be := GameCenterBackend.new()
	t.ok(be.is_available() and not be.is_signed_in(), "the singleton present: available, not signed in")
	t.ok((await be.get_identity_proof()).is_empty(), "no proof before a sign-in")
	var signed := []
	be.signed_in.connect(func() -> void: signed.push_back(true))
	be.sign_in()
	await loop.create_timer(be.POLL_S + 0.2).timeout
	t.ok(be.is_signed_in() and signed.size() == 1 and be.player_name() == "Brick B.", "authenticate's ok event: signed in, once, the platform name kept aside")
	t.eq(stub.calls, ["authenticate"], "…one call")
	be.sign_in()
	t.eq(stub.calls, ["authenticate"], "signed in: sign_in is a no-op")
	var proof: Dictionary = await be.get_identity_proof()
	t.eq(proof, {"publicKeyURL": "https://static.gc.apple.com/public-key/gc-prod-9.cer", "signature": "c2ln", "salt": "c2FsdA==", "timestamp": 1761955200000, "teamPlayerID": "T:abc"}, "the proof is the Worker's shape: team player id, base64 signature and salt, the raw timestamp")
	t.ok(stub.events.is_empty(), "…the queue drained")
	stub.sig_event["result"] = "error"
	stub.sig_event["error_description"] = "no network"
	t.ok((await be.get_identity_proof()).is_empty(), "a signature error → no proof")
	stub.sig_err = ERR_UNAUTHORIZED
	t.ok((await be.get_identity_proof()).is_empty(), "the plugin refusing → no proof, no wait")
	# Achievements (docs/ACHIEVEMENTS.md): the award call, its answer, the
	# earned list and the sheet.
	stub.calls.clear()
	var failed: Array = []
	be.achievement_failed.connect(func(id: String) -> void: failed.push_back(id))
	t.ok(be.unlock("hs.ach.pure"), "unlock: the plugin took the award")
	t.eq(stub.awards, [{"name": "hs.ach.pure", "progress": 100.0, "show_completion_banner": true}], "…complete, with Apple's banner")
	t.ok(be.unlock("hs.ach.on_fire", false) and stub.awards[1]["show_completion_banner"] == false, "…the banner off on request")
	await loop.create_timer(be.POLL_S + 0.2).timeout
	t.ok(stub.events.is_empty() and failed.is_empty(), "…the ok answers drained, nothing failed")
	stub.award_result = "error"
	be.unlock("hs.ach.jackpot")
	await loop.create_timer(be.POLL_S + 0.2).timeout
	t.eq(failed, ["hs.ach.jackpot"], "an award GameKit refused → achievement_failed with its id")
	stub.award_err = ERR_UNAVAILABLE
	t.ok(not be.unlock("hs.ach.drop_it") and not be.unlock(""), "the plugin refusing (or no id) → false")
	var loaded: Dictionary = await be.load_achievements()
	t.eq(loaded, {"ok": true, "earned": ["hs.ach.pure"]}, "load_achievements: the ids at 100%, not the partial one")
	stub.ach_event = {"type": "achievements", "result": "error", "error_code": 2}
	t.eq(await be.load_achievements(), {"ok": false, "earned": []}, "…an error → not ok (nothing to merge)")
	t.ok(be.has_achievements_sheet() and be.show_achievements(), "the sheet opens")
	t.eq(stub.shown, [{"view": "achievements"}], "…on the achievements view")
	t.ok(not none.unlock("hs.ach.pure") and not none.show_achievements() and not (await none.load_achievements())["ok"], "the absent plugin: no awards, no sheet, no list")
	# A failed sign-in.
	var be2 := GameCenterBackend.new()
	stub.calls.clear()
	stub.auth_event = {"type": "authentication", "result": "error", "error_code": 2, "error_description": "cancelled"}
	stub.authed = false
	be2.sign_in()
	await loop.create_timer(be2.POLL_S + 0.2).timeout
	t.ok(not be2.is_signed_in(), "an authentication error: not signed in")
	stub.auth_err = ERR_UNAVAILABLE
	var be3 := GameCenterBackend.new()
	be3.sign_in()
	t.ok(not be3.is_signed_in() and not be3._signing, "the plugin refusing: nothing pending")
	Engine.unregister_singleton("GameCenter")
	t.ok(not Engine.has_singleton("GameCenter") and not GameCenterBackend.new().is_available(), "(unregistered again)")
	stub.free()
	t.ok(not be.is_available(), "a backend whose plugin is gone is unavailable")
