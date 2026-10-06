class_name HandleWords
extends RefCounted
## Player handles in the game's tone — "BRICK BARON" with a two-digit tag —
## from data/handle_words.json, which the server imports too (one list, two
## readers). `valid` mirrors the server's name rule (server/src/rules.ts).

const PATH := "res://data/handle_words.json"
const NAME_MIN := 3
const NAME_MAX := 24

static var _words: Dictionary = {}


static func words() -> Dictionary:
	if _words.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_words = parsed if parsed is Dictionary else {"first": ["HOOP"], "second": ["KID"], "blocked": []}
	return _words


## {name, tag} drawn from a DetRng (tests seed it; the game uses a fresh one).
static func generate(rng: DetRng) -> Dictionary:
	var w := words()
	var first: Array = w.get("first", ["HOOP"])
	var second: Array = w.get("second", ["KID"])
	return {
		"name": "%s %s" % [str(rng.pick(first)), str(rng.pick(second))],
		"tag": "%02d" % rng.range_i(0, 99),
	}


## Upper-case, single spaces, trimmed — what the player typed, tidied.
static func normalize(raw: String) -> String:
	var parts := raw.strip_edges().to_upper().split(" ", false)
	return " ".join(parts)


## 3–24 chars of A–Z, 0–9 and single spaces, no blocked word (whole tokens
## for short words, anywhere for the long ones).
static func valid(name: String) -> bool:
	if name.length() < NAME_MIN or name.length() > NAME_MAX:
		return false
	var re := RegEx.create_from_string("^[A-Z0-9]+( [A-Z0-9]+)*$")
	if re.search(name) == null:
		return false
	var tokens := name.split(" ")
	var squashed := name.replace(" ", "")
	for b in words().get("blocked", []):
		if tokens.has(str(b)):
			return false
		if str(b).length() >= 5 and squashed.contains(str(b)):
			return false
	return true


## "BRICK BARON 42": the handle as the boards print it.
static func display(name: String, tag: String) -> String:
	return "%s %s" % [name, tag] if tag != "" else name
