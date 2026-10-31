class_name StoreKeys
extends RefCounted
## RevenueCat's public SDK keys (docs/BUILD.md → The store plugin): one per
## store app, `appl_…` for the iOS app and `goog_…` for the Android one,
## read from res://store_keys.json — gitignored, like the keystore, with
## store_keys.example.json as the template. Missing or unfilled, the key is
## "" and Store runs the null backend (desktop, QA, a build without keys).

const PATH := "res://store_keys.json"
const PLACEHOLDER := "REPLACE_ME"

static var _cache: Dictionary = {}
static var _read := false


static func _keys() -> Dictionary:
	if not _read:
		_read = true
		if FileAccess.file_exists(PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if parsed is Dictionary and Dictionary(parsed).get("revenuecat") is Dictionary:
				_cache = Dictionary(parsed["revenuecat"])
	return _cache


## The key for this device's store: iOS → ios, Android → android, else "".
static func revenuecat_key(os_name := OS.get_name()) -> String:
	var which := "ios" if os_name == "iOS" else ("android" if os_name == "Android" else "")
	var key := str(_keys().get(which, "")) if which != "" else ""
	return "" if key.contains(PLACEHOLDER) else key


## Tests: the keys a run pretends to have read.
static func set_keys_for_test(keys: Dictionary) -> void:
	_cache = keys.duplicate()
	_read = true
