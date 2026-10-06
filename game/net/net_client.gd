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

const FLUSH_GAP_S := 30.0
const BOARD_TTL_S := 60.0
const TIMEOUT_S := 8.0
const TRANSFER_GAP_S := 600.0

## Off headless (the suite) and under --no-net (QA); the QA driver may flip it.
var enabled := DisplayServer.get_name() != "headless" and not NetConfig.disabled_by_args()
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


func _ready() -> void:
	_rng.randomize()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		flush()


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
	if a.is_empty():
		var rng := DetRng.new(int(Time.get_ticks_usec()) ^ DetRng.hash_seed(SaveService.get_client_id()))
		var h := HandleWords.generate(rng)
		a = {"playerId": SaveService.uuid4(), "secret": _new_secret(), "name": h["name"], "tag": h["tag"], "registered": false}
		SaveService.put_account(a)
	if not bool(a.get("registered", false)):
		await _register()


func _register() -> bool:
	if _registering or not _can_call():
		return false
	_registering = true
	var a := account()
	var r := await _request("register", HTTPClient.METHOD_POST, "/v1/register",
		{"playerId": a["playerId"], "secret": a["secret"], "clientId": SaveService.get_client_id(), "name": a["name"], "tag": a["tag"]}, false)
	_registering = false
	if r["ok"]:
		a["registered"] = true
		a["name"] = str(r["json"].get("name", a["name"]))
		a["tag"] = str(r["json"].get("tag", a["tag"]))
		SaveService.put_account(a)
		_fails = 0
		account_ready.emit(a["name"], a["tag"])
		flush(true)
		return true
	if r["code"] == 403:
		# Someone registered this id with another secret (a restored backup
		# of a transferred account): start over with a fresh identity.
		a["playerId"] = SaveService.uuid4()
		a["secret"] = _new_secret()
		SaveService.put_account(a)
	_back_off(r)
	return false


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
	return true


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
	if SaveService.pending_scores().is_empty():
		return
	_flushing = true
	_last_flush = _now()
	if not registered():
		await _register()
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


# ---- the wire ---------------------------------------------------------------------------


## One HTTP call. {ok, code, json, retry_after}: code 0 = no answer at all,
## -1 = skipped (disabled, blocked, or that endpoint is already in flight).
func _request(key: String, method: int, path: String, body: Variant = null, auth := true) -> Dictionary:
	var out := {"ok": false, "code": -1, "json": {}, "retry_after": -1.0}
	if not _can_call() or _busy.get(key, false):
		return out
	_busy[key] = true
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	req.accept_gzip = false
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if auth:
		var a := account()
		headers.append("Authorization: Bearer %s.%s" % [str(a.get("playerId", "")), str(a.get("secret", ""))])
	var payload := JSON.stringify(body) if body != null else ""
	var err := req.request(NetConfig.base_url() + path, headers, method, payload)
	if err != OK:
		req.queue_free()
		_busy[key] = false
		out["code"] = 0
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
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	out["json"] = parsed if parsed is Dictionary else {}
	out["code"] = code
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
