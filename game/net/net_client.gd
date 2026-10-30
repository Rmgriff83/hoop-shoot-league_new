extends Node
## The game's one door to the server (docs/BACKEND.md): the anonymous device
## account, leaderboard submissions from SaveService's outbox, board reads,
## the move-to-new-phone code. Everything is fire-and-forget behind signals;
## nothing in the game ever waits on the net. Throttled on this side too
## (layer 1): one request in flight per endpoint, a flush at most every
## FLUSH_GAP_S, boards cached BOARD_TTL_S, exponential backoff with jitter
## honouring Retry-After, and no network at all headless or with --no-net.

signal account_ready(name: String, tag: String)
signal score_accepted(area: String, reply: Dictionary)
signal board_loaded(area: String, period: String, data: Dictionary)
signal board_failed(area: String, period: String)
## The ranked ladder (docs/BACKEND.md → Ranked): the board, and your own rank
## whenever the server tells it (GET /v1/me, a rated decision).
signal ranked_board_loaded(data: Dictionary)
signal ranked_board_failed
signal rank_changed(rank: Dictionary)
## The mirror brought newer copies of these parts; App re-reads what it caches.
signal save_pulled(parts: Array)
signal save_pushed(parts: Array)
## The online card cache changed (a refresh, a settle).
signal cards_changed
## Ranked Stage B (docs/BACKEND.md → Ranked → Stage B): GET /v1/rewards
## landed / failed, a CLAIM moved a card, the lobby badge's count changed.
signal rewards_loaded(data: Dictionary)
signal rewards_failed
signal rewards_changed
signal rewards_badge(pending: int)

const FLUSH_GAP_S := 30.0
const BOARD_TTL_S := 60.0
const TIMEOUT_S := 8.0
const TRANSFER_GAP_S := 600.0
## The mirror: a push of dirty parts at most this often (focus-out and a
## transfer code force one), a pull of newer parts at most this often.
const PUSH_GAP_S := 300.0
const PULL_GAP_S := 60.0

## Off headless (the suite) and under --no-net (QA); the QA driver may flip it.
var enabled := DisplayServer.get_name() != "headless" and not NetConfig.disabled_by_args()
## Tests: when valid, `transport.call(method, path, body, headers)` answers
## {code, json, bytes} in place of an HTTPRequest; the busy / backoff / online
## bookkeeping is unchanged.
var transport := Callable()
var _recovering := false
## Did the last request reach the server (any HTTP answer counts)?
var online := false

var _busy: Dictionary = {}
var _flushing := false
var _registering := false
var _last_flush := -1.0
var _last_transfer := -1.0
var _blocked_until := 0.0
var _fails := 0
var _board_cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _pushing := false
var _pulling := false
var _level_reported := -1
## The server's view of the level, from the last cards refresh.
var online_level := 1
## Your ladder rank as the server last told it ({tier, division, games, wins,
## losses, cons, position?}); {} until a rated game or the first /v1/me.
var me_rank: Dictionary = {}
## Grants waiting for a CLAIM (the lobby's REWARDS badge) and the milestone
## keys the server has witnessed, both from the last /v1/me or /v1/rewards.
var pending_rewards := 0
var me_milestones: Array = []
var _rewards_cache: Dictionary = {}
var _last_push := -1.0
var _last_pull := -1.0


func _ready() -> void:
	_rng.randomize()


## Focus changes arrive mid-notification, when the tree may refuse a new
## child (the HTTPRequest node): the work waits for the next frame.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		flush.call_deferred()
		pull_save.call_deferred()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		push_save.call_deferred(true)


# ---- account -----------------------------------------------------------------------


func account() -> Dictionary:
	return SaveService.get_account()


func registered() -> bool:
	return bool(account().get("registered", false))


## "BRICK BARON 42", minted on the spot if this is the first launch.
func handle() -> String:
	var a := account()
	return HandleWords.display(str(a.get("name", "")), str(a.get("tag", "")))


## Mint the device account if there is none, then register it when the net
## allows. Idempotent; safe to call every launch.
func ensure_account() -> void:
	var a := account()
	if not a.has("playerId"):   # none yet (a fresh install, or a wiped part that kept only its stamp)
		var rng := DetRng.new(int(Time.get_ticks_usec()) ^ DetRng.hash_seed(SaveService.get_client_id()))
		var h := HandleWords.generate(rng)
		a = {"playerId": SaveService.uuid4(), "secret": _new_secret(), "name": h["name"], "tag": h["tag"], "registered": false}
		SaveService.put_account(a)
	if not bool(a.get("registered", false)):
		await _register()
	else:
		# A launch: anything newer on the mirror first, then anything we owe it,
		# and the level the online card cap should hold us to.
		await pull_save(true)
		push_save(true)
		report_level(App.level())
		fetch_me()


func _register() -> bool:
	# A fresh install registers once NEW PLAYER has picked the name (design
	# 35a): the register call carries it, no rename round-trip.
	if _registering or not _can_call() or not App.player_created():
		return false
	_registering = true
	var a := account()
	var r := await _request("register", HTTPClient.METHOD_POST, "/v1/register",
		{"playerId": a["playerId"], "secret": a["secret"], "clientId": SaveService.get_client_id(), "name": a["name"], "tag": a["tag"], "level": App.level()}, false)
	_registering = false
	if r["ok"]:
		a["registered"] = true
		a["name"] = str(r["json"].get("name", a["name"]))
		a["tag"] = str(r["json"].get("tag", a["tag"]))
		SaveService.put_account(a)
		_fails = 0
		account_ready.emit(a["name"], a["tag"])
		flush(true)
		await pull_save(true)
		push_save(true)
		return true
	if r["code"] == 403:
		# Someone registered this id with another secret (a restored backup
		# of a transferred account): the platform may still know us; else
		# start over with a fresh identity.
		await _recover_identity()
	_back_off(r)
	return false


## The server no longer takes this identity (a 403 on register, a 401 on an
## authenticated call: a transfer claimed elsewhere, a deleted account, an
## evicted device secret). A linked, signed-in platform restores the account
## with a new device secret; otherwise a fresh identity is minted.
func _recover_identity() -> void:
	if _recovering:
		return
	_recovering = true
	if Platform.is_linked() and Platform.backend.is_signed_in():
		var proof: Dictionary = await Platform.backend.get_identity_proof()
		if not proof.is_empty() and await restore_from_platform(Platform.backend.provider_id(), proof):
			_recovering = false
			return
	_mint_fresh()
	_recovering = false


## A fresh anonymous identity (same handle); registers on the next call.
func _mint_fresh() -> void:
	var a := account()
	a["playerId"] = SaveService.uuid4()
	a["secret"] = _new_secret()
	a["registered"] = false
	a["linked"] = []
	SaveService.put_account(a)
	_board_cache.clear()


## Rename on the server; the local copy follows on success.
func rename(raw: String) -> bool:
	var name := HandleWords.normalize(raw)
	if not HandleWords.valid(name) or not registered():
		return false
	var r := await _request("me", HTTPClient.METHOD_PATCH, "/v1/me", {"name": name})
	if r["ok"]:
		var a := account()
		a["name"] = str(r["json"].get("name", name))
		SaveService.put_account(a)
		account_ready.emit(a["name"], a["tag"])
		return true
	_back_off(r)
	return false


## A one-time code for the new phone, {code, expiresAt} or {} (rate-limited here too).
func transfer_code() -> Dictionary:
	if not registered() or not Backoff.can_fire(_now(), _last_transfer, TRANSFER_GAP_S):
		return {}
	_last_transfer = _now()
	await push_save(true)   # the new phone should find everything
	var r := await _request("transfer", HTTPClient.METHOD_POST, "/v1/transfer/code", {})
	if r["ok"]:
		return r["json"]
	_back_off(r)
	return {}


## Become the player behind `code`: a fresh secret, their id, their handle.
func claim_transfer(code: String) -> bool:
	var secret := _new_secret()
	var r := await _request("transfer", HTTPClient.METHOD_POST, "/v1/transfer/claim",
		{"code": code.strip_edges().to_upper(), "newSecret": secret}, false)
	if not r["ok"]:
		return false
	var a := {"playerId": str(r["json"].get("playerId", "")), "secret": secret,
		"name": str(r["json"].get("name", "")), "tag": str(r["json"].get("tag", "")), "registered": true}
	SaveService.put_account(a)
	_board_cache.clear()
	account_ready.emit(a["name"], a["tag"])
	await pull_save(true)   # their progress, onto this phone
	return true


# ---- platform identities (docs/BACKEND.md → Platform identity; driven by Platform) --------


## GET /v1/me: the linked providers onto the account part (never the proof).
func fetch_me() -> void:
	if not registered():
		return
	var r := await _request("me", HTTPClient.METHOD_GET, "/v1/me")
	if r["ok"]:
		if r["json"].has("providers"):
			var a := account()
			a["linked"] = Array(r["json"]["providers"])
			SaveService.put_account(a)
		if r["json"].get("rank") is Dictionary:
			set_me_rank(Dictionary(r["json"]["rank"]))
		if r["json"].has("level"):
			online_level = int(r["json"]["level"])
		if r["json"].get("milestones") is Array:
			note_milestones(Array(r["json"]["milestones"]))
		if r["json"].has("pending"):
			set_pending_rewards(int(r["json"]["pending"]))
	elif r["code"] == 401:
		await _recover_identity()


## The milestone keys the server holds → the Platform facade's mirror.
func note_milestones(keys: Array) -> void:
	me_milestones = keys.duplicate()
	var plat: Node = get_tree().root.get_node_or_null("Platform") if is_inside_tree() else null
	if plat != null and plat.has_method("note_milestones"):
		plat.call("note_milestones", me_milestones)


func set_pending_rewards(n: int) -> void:
	if n == pending_rewards:
		return
	pending_rewards = n
	rewards_badge.emit(n)


## GET /v1/rewards: what waits for a CLAIM, the meter and its odds, the login
## days, the milestones. Emits rewards_loaded / rewards_failed.
func load_rewards() -> void:
	if not _can_call() or not registered():
		rewards_failed.emit.call_deferred()
		return
	var r := await _request("rewards", HTTPClient.METHOD_GET, "/v1/rewards")
	if r["ok"]:
		_rewards_cache = Dictionary(r["json"]).duplicate(true)
		if r["json"].get("unlocked") is Array:
			note_milestones(Array(r["json"]["unlocked"]))
		set_pending_rewards(Array(r["json"].get("pending", [])).size())
		rewards_loaded.emit(_rewards_cache)
	else:
		if r["code"] != -1:
			_back_off(r)
		rewards_failed.emit()


func cached_rewards() -> Dictionary:
	return _rewards_cache


## POST /v1/rewards/claim: the grant becomes a card (the answer carries the
## inventory, which refreshes the online bucket). False when it could not.
func claim_reward(key: String) -> bool:
	if not _can_call() or not registered():
		return false
	var r := await _request("rewards_claim", HTTPClient.METHOD_POST, "/v1/rewards/claim", {"key": key})
	if r["ok"]:
		_apply_cards(r["json"])
		var pending: Array = Array(_rewards_cache.get("pending", [])).filter(func(g: Variant) -> bool: return str(Dictionary(g).get("key", "")) != key)
		_rewards_cache["pending"] = pending
		set_pending_rewards(pending.size())
		rewards_changed.emit()
		return true
	if r["code"] != -1 and r["code"] != 404 and r["code"] != 409:
		_back_off(r)
	return false


## POST /v1/link: bind the platform identity to this account. {ok, code, json};
## a 409 carries the other account's {name, tag, level}. Offline, the link
## waits in the outbox and flush() retries it once registered.
func link_platform(provider: String, proof: Dictionary) -> Dictionary:
	if not registered():
		SaveService.set_pending_link(provider)
		return {"ok": false, "code": -1, "json": {}}
	var r := await _request("link", HTTPClient.METHOD_POST, "/v1/link", {"provider": provider, "proof": proof})
	if r["ok"]:
		var a := account()
		var linked: Array = Array(a.get("linked", []))
		if not linked.has(provider):
			linked.push_back(provider)
		a["linked"] = linked
		SaveService.put_account(a)
		SaveService.clear_pending_link()
		_fails = 0
	elif r["code"] == -1 or r["code"] == 0:
		SaveService.set_pending_link(provider)
		if r["code"] == 0:
			_back_off(r)
	else:
		SaveService.clear_pending_link()
		if r["code"] == 401:
			await _recover_identity()
		elif r["code"] != 409 and r["code"] != 400 and r["code"] != 501:
			_back_off(r)
	return {"ok": r["ok"], "code": r["code"], "json": r["json"]}


## POST /v1/link/restore: become the account the platform knows — a new device
## secret added there (the other phone stays signed in), their id and handle,
## then their progress (the claimed-code path).
func restore_from_platform(provider: String, proof: Dictionary) -> bool:
	var secret := _new_secret()
	var r := await _request("link", HTTPClient.METHOD_POST, "/v1/link/restore",
		{"provider": provider, "proof": proof, "newSecret": secret}, false)
	if not r["ok"]:
		if r["code"] == 0:
			_back_off(r)
		return false
	var a := {"playerId": str(r["json"].get("playerId", "")), "secret": secret,
		"name": str(r["json"].get("name", "")), "tag": str(r["json"].get("tag", "")), "registered": true, "linked": [provider]}
	SaveService.put_account(a)
	SaveService.clear_pending_link()
	_board_cache.clear()
	_fails = 0
	account_ready.emit(a["name"], a["tag"])
	await pull_save(true)   # their progress, onto this phone
	return true


## DELETE /v1/link/<provider>: unlink (the account and its secrets stay).
func unlink_platform(provider: String) -> bool:
	if not registered():
		return false
	var r := await _request("link", HTTPClient.METHOD_DELETE, "/v1/link/" + provider)
	if r["ok"]:
		var a := account()
		var linked: Array = Array(a.get("linked", []))
		linked.erase(provider)
		a["linked"] = linked
		SaveService.put_account(a)
		return true
	if r["code"] == 401:
		await _recover_identity()
	elif r["code"] != -1 and r["code"] != 404:
		_back_off(r)
	return false


## DELETE /v1/me (Apple 5.1.1(v)): the account and everything under it on the
## server; then this phone's save is wiped (Ross: a fresh install) and the next
## ensure_account mints a new identity.
func delete_account() -> bool:
	if not registered():
		return false
	var r := await _request("me", HTTPClient.METHOD_DELETE, "/v1/me")
	if not (r["ok"] or r["code"] == 401):
		if r["code"] != -1:
			_back_off(r)
		return false
	SaveService.wipe_all()
	_board_cache.clear()
	_fails = 0
	return true


# ---- cards online (docs/BACKEND.md → Cards online) ----------------------------------------

const ONLINE_BUCKET := "online"


## The server's inventory into the `online` bucket of cards.json (a read-only
## cache: spares = copies owned minus the ones in the loadout; a loadout slot
## the ledger no longer covers is emptied). Online cards are never bought;
## they come only from the server (drops and spoils, a later task).
func _apply_cards(json: Dictionary) -> void:
	var d := SaveService.get_cards()
	CardDefs.migrate(d)   # a stale doc would be wiped on save anyway; wipe it first
	var b := CardDefs.league_doc(d, ONLINE_BUCKET)
	var owned: Dictionary = json.get("inventory", {}) if json.get("inventory") is Dictionary else {}
	var left := {}
	for id in owned:
		left[str(id)] = int(owned[id])
	var loadout: Array = b.get("loadout", [null, null, null])
	for i in loadout.size():
		if loadout[i] == null:
			continue
		var id := str(loadout[i])
		if int(left.get(id, 0)) > 0:
			left[id] = int(left[id]) - 1
		else:
			print("Net: the ledger no longer covers %s in online slot %d: emptied" % [id, i])
			loadout[i] = null
	var inv := {}
	for id in left:
		if int(left[id]) > 0:
			inv[id] = int(left[id])
	b["inventory"] = inv
	b["loadout"] = loadout
	SaveService.put_cards(d)
	online_level = int(json.get("level", online_level))
	cards_changed.emit()


## The server's word on your rank (a /v1/me, a rated decision).
func set_me_rank(rank: Dictionary) -> void:
	me_rank = rank.duplicate(true)
	rank_changed.emit(me_rank)


## The ranked ladder: top 50 + your own line, cached BOARD_TTL_S like the
## time-trial boards (`ranked:all`). Emits ranked_board_loaded / _failed.
func load_ranked_board(force := false) -> void:
	var key := "ranked:all"
	var hit: Dictionary = _board_cache.get(key, {})
	if not force and not hit.is_empty() and Time.get_ticks_msec() / 1000.0 - float(hit["at"]) < BOARD_TTL_S:
		ranked_board_loaded.emit.call_deferred(hit["data"])
		return
	if not registered():
		if not await _register():
			ranked_board_failed.emit.call_deferred()
			return
	var r := await _request("board", HTTPClient.METHOD_GET, "/v1/ranked/board")
	if r["ok"]:
		_board_cache[key] = {"at": Time.get_ticks_msec() / 1000.0, "data": r["json"]}
		if r["json"].get("me") is Dictionary:
			set_me_rank(Dictionary(r["json"]["me"]))
		ranked_board_loaded.emit(r["json"])
	else:
		if r["code"] != -1:
			_back_off(r)
		ranked_board_failed.emit()


func cached_ranked_board() -> Dictionary:
	return Dictionary(_board_cache.get("ranked:all", {})).get("data", {})


## Pull the ledger (the lobby opens, a match settled). False when it could not.
func refresh_cards() -> bool:
	if not _can_call() or not registered():
		return false
	var r := await _request("cards", HTTPClient.METHOD_GET, "/v1/cards")
	if r["ok"]:
		_apply_cards(r["json"])
		return true
	if r["code"] != -1:
		_back_off(r)
	return false


## The game's level, for the online card cap and the courts ranked may pick
## (sent once per change; `force` sends it again — a ranked search does, so
## a report that failed at the level-up is not waiting for the next one).
func report_level(level: int, force := false) -> void:
	if (level == _level_reported and not force) or not _can_call() or not registered():
		return
	_level_reported = level
	var r := await _request("me", HTTPClient.METHOD_PATCH, "/v1/me", {"level": level})
	if not r["ok"]:
		_level_reported = -1


# ---- scores -----------------------------------------------------------------------------


## A finished run: into the outbox if the server would take it, then a flush.
func queue_run(run: Dictionary) -> void:
	var p := ScorePayload.from_run(run, NetConfig.version())
	var why := ScorePayload.why_implausible(p, _now_ms())
	if why != "":
		push_warning("Net: run not queued (%s)" % why)
		return
	SaveService.queue_score(p)
	flush(true)


## Send what is pending, oldest first; stop at the first failure and back off.
func flush(force := false) -> void:
	if _flushing or not _can_call():
		return
	if not force and not Backoff.can_fire(_now(), _last_flush, FLUSH_GAP_S):
		return
	if SaveService.pending_scores().is_empty() and SaveService.pending_link() == "":
		return
	_flushing = true
	_last_flush = _now()
	if not registered():
		await _register()
	if registered() and SaveService.pending_link() != "" and Platform.backend.is_signed_in():
		# A link that waited for the signal: Platform asks the backend afresh.
		SaveService.clear_pending_link()
		Platform.sync_link()
	if registered():
		for p in SaveService.pending_scores():
			var r := await _request("scores", HTTPClient.METHOD_POST, "/v1/scores", p)
			if r["ok"] or r["code"] == 400:
				# Taken, a duplicate, or refused for good: either way done.
				SaveService.drop_score(str(p.get("runId", "")))
				_fails = 0
				if r["ok"]:
					score_accepted.emit(str(p.get("area", "")), r["json"])
					_board_cache.clear()
			else:
				_back_off(r)
				break
	_flushing = false


# ---- the cloud save mirror (docs/BACKEND.md → Phase 2) -------------------------------------


## Push every dirty sync part the server does not already hold newer: PUT its
## gzipped JSON with its own updatedAt. Taken or already-newer (409) both
## clear the dirty flag; a 409 also queues a pull. Stops at the first failure.
func push_save(force := false) -> void:
	if _pushing or not _can_call() or not registered():
		return
	if not force and not Backoff.can_fire(_now(), _last_push, PUSH_GAP_S):
		return
	var dirty := []
	for part in SaveService.dirty_parts():
		if SaveCodec.is_sync_part(part):
			dirty.push_back(part)
	if dirty.is_empty():
		return
	_pushing = true
	_last_push = _now()
	var pushed := []
	var stale := false
	for part in dirty:
		var doc := SaveService.part_doc(part)
		var stamp := int(doc.get("updatedAt", 0))
		if stamp <= 0:
			SaveService.clear_dirty(part)
			continue
		var bytes := SaveCodec.encode(doc)
		if bytes.size() > SaveCodec.PART_MAX_BYTES:
			push_warning("Net: %s too large to mirror (%d bytes)" % [part, bytes.size()])
			SaveService.clear_dirty(part)
			continue
		var r := await _request("save", HTTPClient.METHOD_PUT, "/v1/save/" + part, null, true,
			bytes, PackedStringArray(["Content-Type: application/gzip", "X-Updated-At: %d" % stamp]))
		if r["ok"]:
			SaveService.clear_dirty(part)
			pushed.push_back(part)
			_fails = 0
		elif r["code"] == 409:
			SaveService.clear_dirty(part)
			stale = true
		elif r["code"] == 400 or r["code"] == 413:
			push_warning("Net: %s refused by the mirror (%d)" % [part, r["code"]])
			SaveService.clear_dirty(part)
		elif r["code"] == 401:
			_pushing = false
			await _recover_identity()
			return
		else:
			_back_off(r)
			break
	if not pushed.is_empty():
		SaveService.set_last_sync(_now_ms())
		save_pushed.emit(pushed)
	_pushing = false
	if stale:
		pull_save(true)


## Pull every part the server holds newer than ours: the manifest, then each
## newer part's bytes into SaveService.restore_part. `save_pulled` names them.
func pull_save(force := false) -> void:
	if _pulling or not _can_call() or not registered():
		return
	if not force and not Backoff.can_fire(_now(), _last_pull, PULL_GAP_S):
		return
	_pulling = true
	_last_pull = _now()
	var m := await _request("save", HTTPClient.METHOD_GET, "/v1/save")
	var pulled := []
	if m["ok"]:
		_fails = 0
		var parts: Dictionary = m["json"].get("parts", {})
		for part in parts:
			if not SaveCodec.is_sync_part(str(part)):
				continue
			var remote := int(Dictionary(parts[part]).get("updatedAt", 0))
			if remote <= SaveService.part_updated_at(str(part)):
				continue
			var r := await _request("save", HTTPClient.METHOD_GET, "/v1/save/" + str(part), null, true, PackedByteArray(), PackedStringArray(), true)
			if not r["ok"]:
				_back_off(r)
				break
			var doc := SaveCodec.decode(r["bytes"])
			if doc.is_empty():
				push_warning("Net: %s from the mirror did not decode" % part)
				continue
			if SaveService.restore_part(str(part), doc):
				pulled.push_back(str(part))
	elif m["code"] == 401:
		_pulling = false
		await _recover_identity()
		return
	elif m["code"] != -1:
		_back_off(m)
	if not pulled.is_empty():
		SaveService.set_last_sync(_now_ms())
		save_pulled.emit(pulled)
	_pulling = false


## One line for the settings sheet: CLOUD · SAVED 3 MIN AGO / 2 PARTS WAITING / OFF.
func cloud_line() -> String:
	if not enabled or NetConfig.base_url() == "":
		return "CLOUD SAVE · OFF"
	if not registered():
		return "CLOUD SAVE · WAITING FOR SIGNAL"
	var waiting := 0
	for part in SaveService.dirty_parts():
		if SaveCodec.is_sync_part(part):
			waiting += 1
	if waiting > 0:
		return "CLOUD SAVE · %d PART%s WAITING" % [waiting, "" if waiting == 1 else "S"]
	var last := SaveService.last_sync_at()
	if last <= 0:
		return "CLOUD SAVE · NOTHING TO SEND YET"
	var ago := maxi(0, (_now_ms() - last) / 60000)
	if ago < 1:
		return "CLOUD SAVE · SAVED JUST NOW"
	if ago < 60:
		return "CLOUD SAVE · SAVED %d MIN AGO" % ago
	return "CLOUD SAVE · SAVED %d H AGO" % (ago / 60)


# ---- boards -----------------------------------------------------------------------------


## The board for an area and period ("week" / "all"), from the cache when it
## is fresh; `board_loaded` or `board_failed` follows either way.
func load_board(area: String, period: String, force := false) -> void:
	var key := "%s:%s" % [area, period]
	var cached: Dictionary = _board_cache.get(key, {})
	if not force and not cached.is_empty() and _now() - float(cached["at"]) < BOARD_TTL_S:
		board_loaded.emit.call_deferred(area, period, cached["data"])
		return
	if not _can_call() or not registered():
		if not registered() and _can_call():
			await _register()
		if not registered():
			board_failed.emit.call_deferred(area, period)
			return
	var r := await _request("board", HTTPClient.METHOD_GET, "/v1/leaderboard?area=%s&period=%s&limit=50" % [area, period])
	if r["ok"]:
		_board_cache[key] = {"at": _now(), "data": r["json"]}
		_fails = 0
		board_loaded.emit(area, period, r["json"])
	else:
		if r["code"] != -1:
			_back_off(r)
		board_failed.emit(area, period)


func cached_board(area: String, period: String) -> Dictionary:
	return Dictionary(_board_cache.get("%s:%s" % [area, period], {})).get("data", {})


## A plain authenticated JSON call for the match lobby ({ok, code, json}).
func request_json(key: String, method: int, path: String, body: Variant = null) -> Dictionary:
	var r := await _request(key, method, path, body)
	if not r["ok"] and r["code"] != -1 and r["code"] != 404 and r["code"] != 400:
		_back_off(r)
	return r


# ---- the wire ---------------------------------------------------------------------------


## One HTTP call. {ok, code, json, bytes, retry_after}: code 0 = no answer at
## all, -1 = skipped (disabled, blocked, or that endpoint is already in
## flight). `raw` (with `raw_headers`) sends bytes instead of JSON; `want_bytes`
## keeps the answer's bytes (a gzipped save part) instead of parsing JSON.
func _request(key: String, method: int, path: String, body: Variant = null, auth := true,
		raw := PackedByteArray(), raw_headers := PackedStringArray(), want_bytes := false) -> Dictionary:
	var out := {"ok": false, "code": -1, "json": {}, "bytes": PackedByteArray(), "retry_after": -1.0}
	if not _can_call() or _busy.get(key, false):
		return out
	_busy[key] = true
	if transport.is_valid():
		var th := PackedStringArray()
		if auth:
			var ta := account()
			th.append("Authorization: Bearer %s.%s" % [str(ta.get("playerId", "")), str(ta.get("secret", ""))])
		var tr: Dictionary = transport.call(method, path, body if raw.is_empty() else raw, th)
		_busy[key] = false
		var tcode := int(tr.get("code", 0))
		online = tcode != 0
		out["code"] = tcode
		out["json"] = tr.get("json", {}) if tr.get("json", {}) is Dictionary else {}
		out["bytes"] = tr.get("bytes", PackedByteArray())
		out["ok"] = tcode >= 200 and tcode < 300
		out["retry_after"] = float(tr.get("retry_after", -1.0))
		return out
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	req.accept_gzip = false
	add_child(req)
	if not req.is_inside_tree():
		# The tree was busy (a notification mid-setup): one frame, then again.
		await get_tree().process_frame
		if is_instance_valid(req) and not req.is_inside_tree():
			add_child(req)
	if not is_instance_valid(req) or not req.is_inside_tree():
		if is_instance_valid(req):
			req.queue_free()
		_busy[key] = false
		return out   # skipped, not a network failure: no backoff
	var headers := PackedStringArray(["Accept: application/json"])
	if raw.is_empty():
		headers.append("Content-Type: application/json")
	for h in raw_headers:
		headers.append(h)
	if auth:
		var a := account()
		headers.append("Authorization: Bearer %s.%s" % [str(a.get("playerId", "")), str(a.get("secret", ""))])
	var err: int
	if not raw.is_empty():
		err = req.request_raw(NetConfig.base_url() + path, headers, method, raw)
	else:
		err = req.request(NetConfig.base_url() + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		# Could not even send (a local error): skipped, never a backoff.
		req.queue_free()
		_busy[key] = false
		return out
	var res: Array = await req.request_completed
	req.queue_free()
	_busy[key] = false
	var result: int = res[0]
	var code: int = res[1]
	var hdrs: PackedStringArray = res[2]
	var bytes: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		online = false
		out["code"] = 0
		return out
	online = true
	out["code"] = code
	if want_bytes and code >= 200 and code < 300:
		out["bytes"] = bytes
	else:
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		out["json"] = parsed if parsed is Dictionary else {}
	out["ok"] = code >= 200 and code < 300
	for h in hdrs:
		if str(h).to_lower().begins_with("retry-after:"):
			out["retry_after"] = float(str(h).split(":", true, 1)[1].strip_edges())
	return out


func _can_call() -> bool:
	return enabled and NetConfig.base_url() != "" and _now() >= _blocked_until


## A failure: wait 2, 4, 8 … s (jittered), or what the server asked for.
func _back_off(r: Dictionary) -> void:
	var delay := Backoff.next_delay(_fails, float(r.get("retry_after", -1.0)), _rng.randf())
	_fails += 1
	_blocked_until = _now() + delay


## Seconds until the next call may go out (0 = now); for the UI and tests.
func blocked_for() -> float:
	return maxf(0.0, _blocked_until - _now())


static func _new_secret() -> String:
	var bytes := Crypto.new().generate_random_bytes(32)
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
