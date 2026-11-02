class_name FakePlatformBackend
extends PlatformBackend
## A scriptable store backend for tests: the provider, whether it is signed
## in, and the proof it hands over (the Vitest `test` verifier's shape).

var provider := "test"
var available := true
var signed := true
var proof := {"subject": "fake-1"}
var sign_in_calls := 0
## The ids awarded, in order; `banners` the banner flag beside each.
var unlocked: Array = []
var banners: Array = []
## What unlock() answers (false: the platform refused the call).
var accept_awards := true
## What load_achievements() answers.
var remote := {"ok": true, "earned": []}
var load_calls := 0
var sheet_shown := 0
var proof_calls := 0


func provider_id() -> String:
	return provider


func display_name() -> String:
	return "GAME CENTER"


func is_available() -> bool:
	return available


func is_signed_in() -> bool:
	return signed


func sign_in() -> void:
	sign_in_calls += 1
	signed = true
	signed_in.emit()


func get_identity_proof() -> Dictionary:
	proof_calls += 1
	return proof.duplicate()


func unlock(id: String, banner := true) -> bool:
	if not accept_awards:
		return false
	unlocked.push_back(id)
	banners.push_back(banner)
	return true


func load_achievements() -> Dictionary:
	load_calls += 1
	return remote.duplicate(true)


func has_achievements_sheet() -> bool:
	return true


func show_achievements() -> bool:
	sheet_shown += 1
	return true
