extends Node
## `Platform` (autoload, docs/BACKEND.md → Platform identity): the facade the
## game talks to about store sign-in. One `backend` — GameCenterBackend on an
## iPhone with the plugin, the null PlatformBackend everywhere else (desktop,
## headless, QA, Android until Play Games) — and the link flow on top of the
## anonymous account:
##   launch → start(): the backend signs in (Game Center's banner or sheet).
##   signed in, registered → sync_link(): the provider not linked yet → link.
##   409 (the identity already belongs to another account) → `conflict` with
##   that account's handle and level, and the AccountFoundSheet asks "USE IT?";
##   accept_conflict() runs restore_from_platform (a new device secret, the
##   account rewritten, a forced save pull — the claimed-code path); decline
##   keeps this account unlinked.
##   signed in on a fresh install (no player made, nothing registered) →
##   restore_first_launch(): POST /v1/link/restore straight away — a reinstall
##   gets its account back before NEW GAME is ever tapped (404: a new player).
##   Net.account_ready (a registration, a restore) → sync_link() again, for a
##   sign-in that landed before the account existed.
## The handle stays ours; the platform's display name is never adopted.

signal conflict(info: Dictionary)
signal link_changed
## A milestone the server witnessed reached this device for the first time
## (the future achievement mirror; docs/BACKEND.md → Ranked → Stage B).
signal milestone_unlocked(key: String)

var backend: PlatformBackend = PlatformBackend.new()
var _pending_conflict := {}
var _sheet: Node
var _restoring_first := false


func _ready() -> void:
	backend = GameCenterBackend.new()   # the null backend wherever the plugin is absent
	_connect_backend()
	Net.account_ready.connect(func(_n: String, _t: String) -> void: sync_link())
	start.call_deferred()


func _connect_backend() -> void:
	if not backend.signed_in.is_connected(_on_signed_in):
		backend.signed_in.connect(_on_signed_in)


## A fake backend (tests, QA) in place of the plugin's.
func use_backend(b: PlatformBackend) -> void:
	if backend.signed_in.is_connected(_on_signed_in):
		backend.signed_in.disconnect(_on_signed_in)
	backend = b
	_connect_backend()
	_pending_conflict = {}


## Launch: the platform's own sign-in, once, where there is a platform.
func start() -> void:
	if backend.is_available() and not backend.is_signed_in():
		backend.sign_in()


func _on_signed_in() -> void:
	if Net.registered():
		sync_link()
	elif not App.player_created():
		restore_first_launch()
	else:
		sync_link()   # registration pending: the link waits in the outbox


## Providers linked to this account, from the account part (never a proof).
func linked_providers() -> Array:
	return Array(Net.account().get("linked", []))


## The milestone keys mirrored so far (the account part, device-local; the
## server is the source of truth — GET /v1/me → milestones).
func unlocked() -> Array:
	return Array(Net.account().get("milestones", []))


## New keys from the server: remember them and hand each to the backend once.
func note_milestones(keys: Array) -> void:
	var had := unlocked()
	var fresh := []
	for k in keys:
		if not had.has(str(k)):
			fresh.push_back(str(k))
	if fresh.is_empty():
		return
	var a := Net.account()
	var all := had.duplicate()
	all.append_array(fresh)
	a["milestones"] = all
	SaveService.put_account(a)
	for k in fresh:
		backend.unlock(str(k))
		milestone_unlocked.emit(str(k))


func is_linked() -> bool:
	return backend.provider_id() != "" and linked_providers().has(backend.provider_id())


## Link the signed-in platform player to this account, when there is one to link.
func sync_link() -> void:
	if not backend.is_available() or not backend.is_signed_in() or backend.provider_id() == "":
		return
	if is_linked() or not Net.registered():
		return
	var proof: Dictionary = await backend.get_identity_proof()
	if proof.is_empty():
		return
	var r: Dictionary = await Net.link_platform(backend.provider_id(), proof)
	if r.get("ok", false):
		link_changed.emit()
	elif int(r.get("code", 0)) == 409:
		var j: Dictionary = r.get("json", {})
		_pending_conflict = {"provider": backend.provider_id(), "proof": proof,
			"name": str(j.get("name", "")), "tag": str(j.get("tag", "")), "level": int(j.get("level", 1))}
		conflict.emit(_pending_conflict.duplicate())
		_show_sheet()


## A fresh install with a signed-in platform player: the account that player
## owns, if any, before NEW GAME — true when one came down.
func restore_first_launch() -> bool:
	if _restoring_first or Net.registered() or App.player_created():
		return false
	if not backend.is_available() or not backend.is_signed_in() or backend.provider_id() == "":
		return false
	_restoring_first = true
	var proof: Dictionary = await backend.get_identity_proof()
	var ok := false
	if not proof.is_empty():
		ok = await Net.restore_from_platform(backend.provider_id(), proof)
	_restoring_first = false
	if ok:
		link_changed.emit()
	return ok


func has_conflict() -> bool:
	return not _pending_conflict.is_empty()


func pending_conflict() -> Dictionary:
	return _pending_conflict.duplicate()


## USE IT: become the account the platform knows (a new device secret added
## there; this phone's old identity is left behind), then its progress. The
## proof is asked for afresh — the one the link sent is spent (the Worker
## takes each signature once) — with the stored one as the fallback.
func accept_conflict() -> bool:
	if _pending_conflict.is_empty():
		return false
	var c := _pending_conflict
	_pending_conflict = {}
	var proof: Dictionary = await backend.get_identity_proof()
	if proof.is_empty():
		proof = c["proof"]
	var ok: bool = await Net.restore_from_platform(str(c["provider"]), proof)
	if ok:
		link_changed.emit()
	return ok


## NOT NOW: keep this account, unlinked.
func decline_conflict() -> void:
	_pending_conflict = {}


func unlink() -> bool:
	if backend.provider_id() == "":
		return false
	var ok: bool = await Net.unlink_platform(backend.provider_id())
	if ok:
		link_changed.emit()
	return ok


## The "FOUND YOUR ACCOUNT" sheet over whatever is on screen.
func _show_sheet() -> void:
	if _sheet != null and is_instance_valid(_sheet):
		return
	if not is_inside_tree():
		return
	var sheet := AccountFoundSheet.new()
	sheet.build(_pending_conflict)
	sheet.closed.connect(func() -> void: _sheet = null)
	_sheet = sheet
	get_tree().root.add_child(sheet)


func sheet() -> Node:
	return _sheet if _sheet != null and is_instance_valid(_sheet) else null
