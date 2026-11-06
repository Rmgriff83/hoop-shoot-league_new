class_name Walkthroughs
extends RefCounted
## The tours (design "First Time Walkthrough" 36a home, 36b league, 36c
## free PEGGY play; docs/HOME.md → Walkthroughs), from data/walkthroughs.json:
## one list of steps per tour id, and optionally `bookend_top`, where a card
## with no spotlight rests. A step: {id, kind: welcome | plain | end | gift,
## pre?, title?, body, cta?}. A plain step's `id` doubles as its spotlight
## target, which the hosting screen resolves to a rectangle (none: the card
## rests like a bookend); welcome, end and gift are centred bookends with no
## spot (`pre` is the small line over a welcome's or a gift's big title).
## Text may carry {TOKENS} the host fills (fill()). Pure: the overlay
## (game/ui/walkthrough.gd) reads this.

const PATH := "res://data/walkthroughs.json"
const KINDS := ["welcome", "plain", "end", "gift"]
const BOOKEND_TOP := 520.0
const TEXT_KEYS := ["pre", "title", "body", "cta"]

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
		out.push_back({"id": str(raw["id"]), "kind": kind, "pre": str(raw.get("pre", "")), "title": str(raw.get("title", "")),
			"body": str(raw["body"]), "cta": str(raw.get("cta", ""))})
	return out


## Where a tour's cards with no spotlight rest (design px from the top).
static func bookend_top(id: String) -> float:
	var t: Variant = doc().get(id, null)
	return float(t.get("bookend_top", BOOKEND_TOP)) if t is Dictionary else BOOKEND_TOP


## The steps with their {TOKENS} filled from `vars` (a token with no value stays).
static func fill(steps: Array, vars: Dictionary) -> Array:
	if vars.is_empty():
		return steps
	var out := []
	for s in steps:
		var st: Dictionary = Dictionary(s).duplicate()
		for k in TEXT_KEYS:
			st[k] = str(st.get(k, "")).format(vars)
		out.push_back(st)
	return out


## Plain steps are counted "n / N" (the bookends are not steps to count).
static func plain_count(steps: Array) -> int:
	var n := 0
	for s in steps:
		if str(s.get("kind", "plain")) == "plain":
			n += 1
	return n
