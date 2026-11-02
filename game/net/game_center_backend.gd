class_name GameCenterBackend
extends PlatformBackend
## Game Center (iOS) behind `Platform`, over the vendored godot-ios-plugins
## `GameCenter` singleton (tools/ios_plugins/gamecenter; docs/BACKEND.md →
## Platform identity). The plugin answers through a queue of event
## dictionaries (`get_pending_event_count` / `pop_pending_event`), so every
## wait here is a short timer loop draining it. The proof is Apple's
## identity-verification signature over the TEAM player id — exactly what the
## Worker's `gamecenter` verifier checks; nothing else leaves the device.
## Off a device with the plugin the singleton is absent and this is the null
## backend (`is_available()` false).

const SINGLETON := "GameCenter"
## The queue is read this often while something is pending.
const POLL_S := 0.25
## A sign-in or a signature that never answers is given up on after this long.
const SIGN_IN_WAIT_S := 60.0
const PROOF_WAIT_S := 15.0

var _gc: Object
var _signed := false
var _name := ""
var _signing := false
## The last signature event (consumed by get_identity_proof).
var _proof_event := {}
var _proof_waiting := false


func _init() -> void:
	if Engine.has_singleton(SINGLETON):
		_gc = Engine.get_singleton(SINGLETON)


func provider_id() -> String:
	return "gamecenter"


func display_name() -> String:
	return "GAME CENTER"


func is_available() -> bool:
	return _gc != null and is_instance_valid(_gc)


func is_signed_in() -> bool:
	return is_available() and _signed


## The platform's own name for the player (never adopted as the handle).
func player_name() -> String:
	return _name


## GameKit's sign-in: a sheet when the device has no Game Center player,
## else a banner; the `authentication` event lands either way.
func sign_in() -> void:
	if not is_available() or _signing or _signed:
		return
	_signing = true
	var err: int = int(_gc.call("authenticate"))
	if err != OK:
		_signing = false
		return
	_pump(SIGN_IN_WAIT_S)


## The proof for the Worker, or {} (not signed in, the plugin declined, no
## answer within PROOF_WAIT_S).
func get_identity_proof() -> Dictionary:
	if not is_signed_in() or _proof_waiting:
		return {}
	_proof_event = {}
	_proof_waiting = true
	var err: int = int(_gc.call("request_identity_verification_signature"))
	if err != OK:
		_proof_waiting = false
		return {}
	await _pump(PROOF_WAIT_S, func() -> bool: return not _proof_event.is_empty())
	_proof_waiting = false
	var ev := _proof_event
	_proof_event = {}
	if str(ev.get("result", "")) != "ok":
		return {}
	return {"publicKeyURL": str(ev.get("public_key_url", "")), "signature": str(ev.get("signature", "")),
		"salt": str(ev.get("salt", "")), "timestamp": int(ev.get("timestamp", 0)), "teamPlayerID": str(ev.get("player_id", ""))}


## Drain the plugin's queue every POLL_S until `until` says so (or the sign-in
## settles), for at most `wait` seconds.
func _pump(wait: float, until: Callable = Callable()) -> void:
	var left := wait
	while left > 0.0:
		_drain()
		if until.is_valid():
			if until.call():
				return
		elif not _signing:
			return
		var loop := Engine.get_main_loop() as SceneTree
		if loop == null:
			return
		await loop.create_timer(POLL_S).timeout
		left -= POLL_S
	if not until.is_valid():
		_signing = false   # the sheet never answered: a later sign_in may try again


func _drain() -> void:
	if not is_available():
		return
	while int(_gc.call("get_pending_event_count")) > 0:
		var ev: Variant = _gc.call("pop_pending_event")
		if ev is Dictionary:
			_on_event(ev)


func _on_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"authentication":
			_signing = false
			var ok := str(ev.get("result", "")) == "ok"
			_signed = ok
			_name = str(ev.get("displayName", "")) if ok else ""
			if ok:
				signed_in.emit()
		"identity_verification_signature":
			_proof_event = ev
		_:
			pass
