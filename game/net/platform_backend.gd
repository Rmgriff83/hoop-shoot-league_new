class_name PlatformBackend
extends RefCounted
## The store sign-in behind `Platform` (docs/BACKEND.md → Platform identity):
## Game Center on iOS, Play Games on Android, once their plugins exist. This
## base class IS the null backend — never available, never signed in — and is
## what desktop, headless, QA and today's phone builds run. A real backend
## overrides every method below and emits `signed_in` once the platform has
## a player; `get_identity_proof()` returns what the server's verifier for
## `provider_id()` expects (platform.ts), nothing else is ever stored.

signal signed_in

## "gamecenter" | "playgames" ("test" for the Vitest verifier; "" here).
func provider_id() -> String:
	return ""


## A human label for the settings row ("GAME CENTER").
func display_name() -> String:
	return ""


## The plugin is present on this device.
func is_available() -> bool:
	return false


func is_signed_in() -> bool:
	return false


## Ask the platform to sign the player in (a sheet on a real device).
func sign_in() -> void:
	pass


## The proof for the server: {} when there is none. A coroutine on a real backend.
func get_identity_proof() -> Dictionary:
	return {}


## Award an achievement by its platform id (AchievementDefs.apple_id;
## docs/ACHIEVEMENTS.md): true when the platform took the call (its own
## completion banner when `banner`). The null backend has nowhere to put it,
## so `Achievements` parks the key until a platform signs in.
func unlock(_id: String, _banner := true) -> bool:
	return false


## The player's earned achievements on the platform: {ok, earned: [ids]}
## — `ok` false when it could not be read (nothing is then re-reported).
## A coroutine on a real backend.
func load_achievements() -> Dictionary:
	return {"ok": false, "earned": []}


## The platform has an achievements sheet to show.
func has_achievements_sheet() -> bool:
	return false


## Open it: true when the call went out.
func show_achievements() -> bool:
	return false
