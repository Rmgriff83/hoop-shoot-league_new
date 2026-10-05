class_name AreaUnlockCopy
extends RefCounted
## Copy for the Area Unlock page (design "Area Unlock" 18a, 2026-10-05):
## which area a level rise opens, and what the page says for it.

const GOLD := Color("#F0B84A")
const ORANGE := Color("#E8703A")
const TEAL := Color("#3F8C7A")
const BLUE := Color("#7FAEC6")
const CREAM := Color("#F1E8D0")
## The rays' colour and the confetti palette per area.
const LOOK := {
	"beach": {"ray": ORANGE, "palette": [ORANGE, GOLD, BLUE, CREAM]},
	"city": {"ray": GOLD, "palette": [GOLD, TEAL, ORANGE, CREAM]},
}
const DEFAULT_LOOK := {"ray": GOLD, "palette": [GOLD, ORANGE, CREAM]}


## The area whose level was reached by going from `before` to `after` —
## the first one in archive order whose unlock level lies in (before,
## after]. "" when the rise opened nothing (the cage opens at the start).
static func crossed(before: int, after: int) -> String:
	for a in AreaArchiveCopy.AREAS:
		var id := str(a["area"])
		var lvl := Progression.area_level(id)
		if lvl > 1 and lvl > before and lvl <= after:
			return id
	return ""


## The page's state for an area reached at `level`.
static func state(id: String, level: int) -> Dictionary:
	var arena := CosmeticLibrary.get_arena(id)
	var name := id.to_upper()
	var stars := 1
	if arena != null:
		name = str(arena.display_name).to_upper()
		stars = maxi(1, int(arena.title_stars))
	var look: Dictionary = LOOK.get(id, DEFAULT_LOOK)
	return {
		"id": id, "name": name, "level": level,
		"level_text": "LEVEL %02d REACHED" % level,
		"stars": stars, "ray": look["ray"], "palette": look["palette"],
		"opens": [
			{"text": "LEAGUE", "icon": "icon_trophy", "color": ORANGE},
			{"text": "TIME TRIAL", "icon": "icon_stopwatch", "color": GOLD},
			{"text": "PRACTICE", "icon": "icon_jersey", "color": TEAL},
		],
		"title": "NEW AREA", "go": "GO THERE", "go_sub": "%s HOME" % name, "later": "LATER",
		"snap": "res://assets/ui/areas/area_%s.png" % id,
		"snap_tall": "res://assets/ui/areas/area_%s_tall.png" % id,
	}


## Every string the page draws (the glyph test).
static func strings(v: Dictionary) -> Array:
	var out := [v["level_text"], v["title"], v["name"], v["go"], v["go_sub"], v["later"]]
	for o in v["opens"]:
		out.push_back(str(o["text"]))
	return out
