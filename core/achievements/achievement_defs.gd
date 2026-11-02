class_name AchievementDefs
extends RefCounted
## The achievement roster (design "Achievement Roster", Ross's sheet,
## 2026-11-02; docs/ACHIEVEMENTS.md): data/achievements.json read once.
## Forty rows in six categories, each with a permanent Apple id
## (`hs.ach.<key>`) and an empty `play_id` until Play Games lands. The rules
## that unlock them are AchievementRules; the autoload `Achievements` decides
## and reports. Pure: no nodes, no RNG.

const PATH := "res://data/achievements.json"
## Apple's limits (App Store Connect): points per achievement and in all.
const APPLE_POINT_MAX := 100
const APPLE_TOTAL_MAX := 1000
## Server milestones (docs/BACKEND.md → Ranked → Stage B) mirrored as
## achievements; the other milestone keys have none.
const MILESTONE_MAP := {
	"first_ranked_win": "debut_dub", "first_capture": "spoils",
	"tier_starter": "tier_starter", "tier_pro": "tier_pro", "tier_allstar": "tier_allstar",
	"tier_mvp": "tier_mvp", "tier_legend": "tier_legend",
	"ranked_wins_10": "ranked_wins_10", "ranked_wins_50": "ranked_wins_50", "ranked_wins_100": "ranked_wins_100",
}

static var _doc: Dictionary = {}
static var _by_key: Dictionary = {}
static var _by_apple: Dictionary = {}


static func _load() -> void:
	if not _doc.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_doc = parsed if parsed is Dictionary else {"categories": [], "achievements": []}
	for a in all():
		_by_key[str(a["key"])] = a
		_by_apple[str(a.get("apple_id", ""))] = str(a["key"])


## The rows in the roster's order.
static func all() -> Array:
	_load()
	return Array(_doc.get("achievements", []))


## {id, label, colour} in the roster's order.
static func categories() -> Array:
	_load()
	return Array(_doc.get("categories", []))


static func has(key: String) -> bool:
	_load()
	return _by_key.has(key)


static func get_def(key: String) -> Dictionary:
	_load()
	return _by_key.get(key, {})


static func apple_id(key: String) -> String:
	return str(get_def(key).get("apple_id", ""))


## The key behind an Apple id ("" when it is not ours).
static func key_for_apple_id(id: String) -> String:
	_load()
	return str(_by_apple.get(id, ""))


static func points(key: String) -> int:
	return int(get_def(key).get("points", 0))


static func total_points() -> int:
	var n := 0
	for a in all():
		n += int(a.get("points", 0))
	return n


## The keys in the roster's order.
static func keys() -> Array:
	var out := []
	for a in all():
		out.push_back(str(a["key"]))
	return out


## Achievement keys for server milestone keys (unknown ones dropped), in order, once each.
static func for_milestones(milestones: Array) -> Array:
	var out := []
	for m in milestones:
		var k: String = str(MILESTONE_MAP.get(str(m), ""))
		if k != "" and not out.has(k):
			out.push_back(k)
	return out


## Problems with the roster (empty when it is sound): the shape the ASC
## script and Apple's review rely on.
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var rows := all()
	if rows.size() != 40:
		out.push_back("expected 40 achievements, found %d" % rows.size())
	var cats := {}
	for c in categories():
		cats[str(c.get("id", ""))] = true
		if not str(c.get("colour", "")).begins_with("#"):
			out.push_back("category %s: colour must be #RRGGBB" % str(c.get("id", "")))
	var seen_keys := {}
	var seen_apple := {}
	var total := 0
	for a in rows:
		var key := str(a.get("key", ""))
		if key == "" or not RegEx.create_from_string("^[a-z0-9_]+$").search(key):
			out.push_back("bad key '%s'" % key)
		if seen_keys.has(key):
			out.push_back("duplicate key %s" % key)
		seen_keys[key] = true
		var apple := str(a.get("apple_id", ""))
		if apple != "hs.ach." + key:
			out.push_back("%s: apple_id must be hs.ach.%s" % [key, key])
		if seen_apple.has(apple):
			out.push_back("duplicate apple id %s" % apple)
		seen_apple[apple] = true
		var name := str(a.get("name", ""))
		if name == "" or name != name.to_upper():
			out.push_back("%s: name must be upper case" % key)
		if str(a.get("unlock", "")) == "":
			out.push_back("%s: no unlock text" % key)
		var pts := int(a.get("points", 0))
		if pts <= 0 or pts > APPLE_POINT_MAX:
			out.push_back("%s: points %d outside 1..%d" % [key, pts, APPLE_POINT_MAX])
		total += pts
		if not cats.has(str(a.get("category", ""))):
			out.push_back("%s: unknown category %s" % [key, str(a.get("category", ""))])
		if not (a.get("hidden") is bool):
			out.push_back("%s: hidden must be a bool" % key)
		if not str(a.get("source", "")) in ["phone", "server"]:
			out.push_back("%s: source must be phone or server" % key)
		if not a.has("play_id"):
			out.push_back("%s: play_id missing" % key)
	if total > APPLE_TOTAL_MAX:
		out.push_back("points total %d over Apple's %d" % [total, APPLE_TOTAL_MAX])
	for m in MILESTONE_MAP.values():
		if not seen_keys.has(str(m)):
			out.push_back("MILESTONE_MAP points at unknown %s" % str(m))
	return out
