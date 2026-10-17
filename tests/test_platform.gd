extends RefCounted
## Platform identity prep (docs/BACKEND.md → Platform identity): the facade,
## the link / 409 / restore / unlink / delete flows and the 401 recovery, over
## a FakePlatformBackend and a scripted Net.transport — no HTTP, no server.


var _calls: Array = []
var _answers: Dictionary = {}   # "METHOD path" → {code, json}


func _transport(method: int, path: String, body: Variant, headers: PackedStringArray) -> Dictionary:
	var names := {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_PUT: "PUT", HTTPClient.METHOD_DELETE: "DELETE", HTTPClient.METHOD_PATCH: "PATCH"}
	var m: String = str(names.get(method, str(method)))
	var key := "%s %s" % [m, path]
	_calls.push_back({"key": key, "body": body, "headers": headers})
	var ans: Variant = _answers.get(key, {"code": 404, "json": {"error": "not_found"}})
	if ans is Callable:
		return ans.call(body)
	return ans


func run(t) -> void:
	var sfx_root = Engine.get_main_loop().root
	var net: Node = sfx_root.get_node_or_null("Net")
	var plat: Node = sfx_root.get_node_or_null("Platform")
	if net == null or plat == null:
		t.ok(false, "Net and Platform autoloads present")
		return
	var save: Node = sfx_root.get_node("SaveService")
	var was_enabled: bool = net.enabled
	var was_account: Dictionary = save.get_account()
	var was_backend = plat.backend
	net.enabled = true
	net.transport = _transport
	# Registration waits for NEW PLAYER (design 35a): this install has one.
	var was_fresh: bool = plat.get_parent().get_node("App").qa_fresh
	var app_node: Node = sfx_root.get_node("App")
	app_node.qa_fresh = false
	var st: Dictionary = save.get_settings()
	st["playerCreated"] = true
	save.put_settings(st)
	net._blocked_until = 0.0
	net._fails = 0
	var fake := FakePlatformBackend.new()
	plat.backend = fake

	# The null backend: never available, never linked, nothing to sync.
	var nul := PlatformBackend.new()
	t.ok(not nul.is_available() and not nul.is_signed_in() and nul.provider_id() == "" and nul.get_identity_proof().is_empty(), "the base PlatformBackend is the null backend")

	# A registered account to start from.
	save.put_account({"playerId": SaveService.uuid4(), "secret": "s" .repeat(40), "name": "BRICK BARON", "tag": "42", "registered": true})
	_answers = {"GET /v1/save": {"code": 200, "json": {"parts": {}, "now": 0}},
		"POST /v1/link": {"code": 200, "json": {"linked": true, "provider": "test"}}}
	await plat.sync_link()
	t.ok(_calls.size() == 1 and _calls[0]["key"] == "POST /v1/link" and _calls[0]["body"]["provider"] == "test" and _calls[0]["body"]["proof"]["subject"] == "fake-1", "sync_link posts the backend's proof")
	t.ok(_calls[0]["headers"][0].begins_with("Authorization: Bearer "), "…authenticated")
	t.eq(plat.linked_providers(), ["test"], "the account part records the provider")
	t.ok(plat.is_linked(), "is_linked")
	t.ok(not save.get_account().has("proof"), "the proof is never stored")
	_calls.clear()
	await plat.sync_link()
	t.eq(_calls.size(), 0, "already linked: nothing sent")

	# 409: the identity belongs to another account → conflict, USE IT restores.
	save.put_account({"playerId": SaveService.uuid4(), "secret": "a" .repeat(40), "name": "NEW GUY", "tag": "07", "registered": true})
	_answers["POST /v1/link"] = {"code": 409, "json": {"error": "conflict", "provider": "test", "name": "BRICK BARON", "tag": "42", "level": 7}}
	var seen := []
	plat.conflict.connect(func(info: Dictionary) -> void: seen.push_back(info))
	_calls.clear()
	await plat.sync_link()
	t.ok(seen.size() == 1 and seen[0]["name"] == "BRICK BARON" and seen[0]["tag"] == "42" and int(seen[0]["level"]) == 7, "409 → conflict with the other account's handle and level")
	t.ok(plat.has_conflict() and not plat.is_linked(), "nothing linked while the choice is open")
	# Decline keeps this account.
	plat.decline_conflict()
	t.ok(not plat.has_conflict() and save.get_account()["name"] == "NEW GUY", "NOT NOW keeps the current account, unlinked")
	# Again, and accept: restore with a new secret, then a forced pull.
	await plat.sync_link()
	var old_secret := str(save.get_account()["secret"])
	var owner_id := SaveService.uuid4()
	var pulled := []
	_answers["POST /v1/link/restore"] = func(body: Variant) -> Dictionary:
		return {"code": 200, "json": {"playerId": owner_id, "name": "BRICK BARON", "tag": "42"}}
	_answers["GET /v1/save"] = {"code": 200, "json": {"parts": {}, "now": 0}}
	_calls.clear()
	var ok: bool = await plat.accept_conflict()
	t.ok(ok, "USE IT restores")
	var restore_call: Dictionary = _calls[0]
	t.ok(restore_call["key"] == "POST /v1/link/restore" and restore_call["headers"].is_empty(), "restore is unauthenticated")
	t.ok(str(restore_call["body"]["newSecret"]) != old_secret and str(restore_call["body"]["newSecret"]).length() >= 32, "…with a fresh device secret")
	var a: Dictionary = save.get_account()
	t.ok(a["playerId"] == owner_id and a["name"] == "BRICK BARON" and a["tag"] == "42" and a["registered"] == true and Array(a["linked"]) == ["test"], "the account is theirs now, linked")
	t.ok(_calls.size() >= 2 and _calls[1]["key"] == "GET /v1/save", "…and their progress is pulled (the claimed-code path)")
	t.ok(not plat.has_conflict(), "conflict cleared")

	# fetch_me refreshes the linked list from the server.
	_answers["GET /v1/me"] = {"code": 200, "json": {"playerId": owner_id, "name": "BRICK BARON", "tag": "42", "level": 7, "providers": []}}
	await net.fetch_me()
	t.eq(plat.linked_providers(), [], "GET /v1/me's providers win")
	_answers["GET /v1/me"] = {"code": 200, "json": {"playerId": owner_id, "name": "BRICK BARON", "tag": "42"}}
	a = save.get_account()
	a["linked"] = ["test"]
	save.put_account(a)
	await net.fetch_me()
	t.eq(plat.linked_providers(), ["test"], "an old Worker without `providers` changes nothing")

	# Unlink.
	_answers["DELETE /v1/link/test"] = {"code": 200, "json": {"linked": false, "provider": "test"}}
	ok = await plat.unlink()
	t.ok(ok and not plat.is_linked() and plat.linked_providers().is_empty(), "unlink drops the provider")

	# 401 recovery: linked + signed in → restore; else a fresh identity.
	a = save.get_account()
	a["linked"] = ["test"]
	save.put_account(a)
	_answers["GET /v1/save"] = {"code": 401, "json": {"error": "unauthorized"}}
	var restored_id := SaveService.uuid4()
	_answers["POST /v1/link/restore"] = func(body: Variant) -> Dictionary:
		_answers["GET /v1/save"] = {"code": 200, "json": {"parts": {}, "now": 0}}
		return {"code": 200, "json": {"playerId": restored_id, "name": "BRICK BARON", "tag": "42"}}
	_calls.clear()
	await net.pull_save(true)
	t.ok(_calls.size() >= 2 and _calls[1]["key"] == "POST /v1/link/restore" and save.get_account()["playerId"] == restored_id, "a 401 on the mirror restores from the platform when linked")
	fake.signed = false
	_answers["GET /v1/save"] = {"code": 401, "json": {"error": "unauthorized"}}
	var before := str(save.get_account()["playerId"])
	await net.pull_save(true)
	a = save.get_account()
	t.ok(a["playerId"] != before and a["registered"] == false and Array(a["linked"]).is_empty(), "a 401 with no platform to ask mints a fresh identity")
	fake.signed = true

	# Offline link waits in the outbox; flush replays it once registered.
	save.put_account({"playerId": SaveService.uuid4(), "secret": "b" .repeat(40), "name": "NEW GUY", "tag": "07", "registered": false})
	var r: Dictionary = await net.link_platform("test", {"subject": "fake-1"})
	t.ok(not r["ok"] and save.pending_link() == "test", "unregistered: the link waits in the outbox")
	_answers["POST /v1/register"] = {"code": 200, "json": {"playerId": "x", "name": "NEW GUY", "tag": "07", "created": true}}
	_answers["GET /v1/save"] = {"code": 200, "json": {"parts": {}, "now": 0}}
	_answers["POST /v1/link"] = {"code": 200, "json": {"linked": true, "provider": "test"}}
	_calls.clear()
	await net.flush(true)
	await Engine.get_main_loop().process_frame
	t.ok(save.pending_link() == "" and plat.is_linked(), "flush registers, then the waiting link goes out (%s)" % str(_calls.map(func(c): return c["key"])))

	# Delete: the server account, then a wiped phone.
	save.put_settings({"updatedAt": 1, "shotHelp": 2})
	_answers["DELETE /v1/me"] = {"code": 200, "json": {"deleted": true}}
	ok = await net.delete_account()
	t.ok(ok, "delete_account")
	t.ok(save.get_account().is_empty() and int(save.get_settings().get("shotHelp", 0)) == 0, "the phone is a fresh install: no account, default settings")
	t.ok(FileAccess.file_exists("user://save/meta.json") and not FileAccess.file_exists("user://save/account.json"), "a new meta, no account on disk")

	# The sheet builds from a conflict.
	var sheet := AccountFoundSheet.new()
	sheet.build({"name": "BRICK BARON", "tag": "42", "level": 7})
	t.ok((sheet.find_child("Handle", true, false) as Label).text == "BRICK BARON 42" and (sheet.find_child("Level", true, false) as Label).text == "LVL 7", "FOUND YOUR ACCOUNT · handle · LVL n")
	t.ok(sheet.find_child("UseIt", true, false) != null and sheet.find_child("NotNow", true, false) != null, "USE IT / NOT NOW")
	sheet.free()

	# Put the world back.
	app_node.qa_fresh = was_fresh
	net.transport = Callable()
	net.enabled = was_enabled
	plat.backend = was_backend
	save.wipe_all()
	if not was_account.is_empty():
		save.put_account(was_account)
