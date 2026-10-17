class_name FakePlatformBackend
extends PlatformBackend
## A scriptable store backend for tests: the provider, whether it is signed
## in, and the proof it hands over (the Vitest `test` verifier's shape).

var provider := "test"
var available := true
var signed := true
var proof := {"subject": "fake-1"}
var sign_in_calls := 0


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
	return proof.duplicate()
