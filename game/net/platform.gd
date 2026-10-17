extends Node
## `Platform` (autoload, docs/BACKEND.md → Platform identity): the facade the
## game talks to about store sign-in. One `backend` (PlatformBackend: the null
## one until the Game Center / Play Games plugins land) and the link flow on
## top of the anonymous account:
##   launch → Net.ensure_account as today → sync_link(): if the platform is
##   signed in and its provider is not linked, link. 409 (the identity already
##   belongs to another account) → `conflict` with that account's handle and
##   level, and the AccountFoundSheet asks "USE IT?"; accept_conflict() runs
##   restore_from_platform (a new device secret, the account rewritten, a forced
##   save pull — the claimed-code path); decline keeps this account unlinked.
## The handle stays ours; the platform's display name is never adopted.

signal conflict(info: Dictionary)
signal link_changed

var backend: PlatformBackend = PlatformBackend.new()
var _pending_conflict := {}
var _sheet: Node


func _ready() -> void:
	backend.signed_in.connect(func() -> void: sync_link())


## Providers linked to this account, from the account part (never a proof).
func linked_providers() -> Array:
	return Array(Net.account().get("linked", []))


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


func has_conflict() -> bool:
	return not _pending_conflict.is_empty()


func pending_conflict() -> Dictionary:
	return _pending_conflict.duplicate()


## USE IT: become the account the platform knows (a new device secret added
## there; this phone's old identity is left behind), then its progress.
func accept_conflict() -> bool:
	if _pending_conflict.is_empty():
		return false
	var c := _pending_conflict
	_pending_conflict = {}
	var ok: bool = await Net.restore_from_platform(str(c["provider"]), c["proof"])
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
