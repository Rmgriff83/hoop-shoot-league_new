class_name Towns
extends RefCounted
## The player's hometown (design "New Game Flow" 35a, 2026-10-17): a random
## town from data/towns.json on the NEW PLAYER form, typed over or re-rolled,
## editable in Settings → PLAYER. A synced setting (`hometown`), not a server
## field — the league still says YOU; the gold card is where name sits over
## hometown. Pure: no nodes, a DetRng for the roll.

const PATH := "res://data/towns.json"
const TOWN_MAX := 16

static var _towns: Array = []


static func list() -> Array:
	if _towns.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_towns = Array(parsed.get("towns", [])) if parsed is Dictionary else []
		if _towns.is_empty():
			_towns = ["OAKRIDGE"]
	return _towns


## A town from the list, not `avoid` when there is a choice.
static func pick(rng: DetRng, avoid := "") -> String:
	var all := list()
	var town := str(rng.pick(all))
	if town == avoid and all.size() > 1:
		town = str(all[(all.find(town) + 1) % all.size()])
	return town


## What the player typed, tidied: upper-case A–Z, 0–9 and single spaces,
## trimmed, at most TOWN_MAX.
static func normalize(raw: String) -> String:
	var re := RegEx.create_from_string("[^A-Z0-9 ]")
	var cleaned := re.sub(raw.to_upper(), "", true)
	var parts := cleaned.strip_edges().split(" ", false)
	return " ".join(parts).left(TOWN_MAX)


## Non-empty after tidying, within TOWN_MAX.
static func valid(town: String) -> bool:
	var n := normalize(town)
	return n != "" and n == town and n.length() <= TOWN_MAX
