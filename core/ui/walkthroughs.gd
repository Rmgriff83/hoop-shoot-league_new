class_name Walkthroughs
extends RefCounted
## The tours (design "First Time Walkthrough" 36a, 2026-10-17; docs/HOME.md →
## Walkthroughs), from data/walkthroughs.json: one list of steps per tour id.
## A step: {id, kind: welcome | plain | end, title?, body, cta?}. A plain
## step's `id` doubles as its spotlight target, which the hosting screen
## resolves to a rectangle; welcome and end are centred bookends with no
## spot. Pure: the overlay (game/ui/walkthrough.gd) reads this.

const PATH := "res://data/walkthroughs.json"
const KINDS := ["welcome", "plain", "end"]

static var _doc: Dictionary = {}


static func doc() -> Dictionary:
	if _doc.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_doc = parsed if parsed is Dictionary else {}
	return _doc


static func ids() -> Array:
	var out := doc().keys()
	out.sort()
	return out


## The steps of a tour, tidied: kind defaults to plain, cta to "" (NEXT).
## [] for an unknown tour or a bad step.
static func tour(id: String) -> Array:
	var t: Variant = doc().get(id, null)
	if not (t is Dictionary) or not (t.get("steps") is Array):
		return []
	var out := []
	for raw in t["steps"]:
		if not (raw is Dictionary) or str(raw.get("id", "")) == "" or str(raw.get("body", "")) == "":
			return []
		var kind := str(raw.get("kind", "plain"))
		if not KINDS.has(kind) or (kind == "plain" and str(raw.get("title", "")) == ""):
			return []
		out.push_back({"id": str(raw["id"]), "kind": kind, "title": str(raw.get("title", "")),
			"body": str(raw["body"]), "cta": str(raw.get("cta", ""))})
	return out


## Plain steps are counted "n / N" (the bookends are not steps to count).
static func plain_count(steps: Array) -> int:
	var n := 0
	for s in steps:
		if str(s.get("kind", "plain")) == "plain":
			n += 1
	return n
