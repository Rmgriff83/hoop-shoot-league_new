class_name CosmeticLibrary
extends RefCounted
## Registry of every hoop, ball and arena set. Explicit lists (no directory
## scanning) so exported builds behave; manifests load on demand and are
## cached. Adding a set = adding its folder under assets/ and one path here.
## Order matters for starters: the first price-0 set of each kind is the one
## everyone owns.

const HOOPS: Array[String] = [
	"res://assets/hoops/classic/hoop_set.tres",
	"res://assets/hoops/street/hoop_set.tres",
]
const BALLS: Array[String] = [
	"res://assets/balls/classic/ball_set.tres",
	"res://assets/balls/globetrotters/ball_set.tres",
	"res://assets/balls/aba/ball_set.tres",
	"res://assets/balls/blacktop/ball_set.tres",
	"res://assets/balls/midnight/ball_set.tres",
	"res://assets/balls/neon/ball_set.tres",
	"res://assets/balls/sunset/ball_set.tres",
	"res://assets/balls/lime/ball_set.tres",
	"res://assets/balls/bubblegum/ball_set.tres",
	"res://assets/balls/gold/ball_set.tres",
	"res://assets/balls/chrome/ball_set.tres",
	"res://assets/balls/camo/ball_set.tres",
	"res://assets/balls/beach/ball_set.tres",
	"res://assets/balls/eightball/ball_set.tres",
	"res://assets/balls/watermelon/ball_set.tres",
	"res://assets/balls/ice/ball_set.tres",
	"res://assets/balls/fire/ball_set.tres",
	"res://assets/balls/galaxy/ball_set.tres",
	"res://assets/balls/retro/ball_set.tres",
	"res://assets/balls/varsity/ball_set.tres",
	"res://assets/balls/tiger/ball_set.tres",
]
const ARENAS: Array[String] = [
	"res://assets/arena/cage/arena_set.tres",
	"res://assets/arena/beach/arena_set.tres",
]

static var _cache := {}


static func _load(path: String) -> CosmeticSet:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


static func hoops() -> Array[HoopSet]:
	var out: Array[HoopSet] = []
	for p in HOOPS:
		var s := _load(p)
		if s is HoopSet:
			out.push_back(s)
	return out


static func balls() -> Array[BallSet]:
	var out: Array[BallSet] = []
	for p in BALLS:
		var s := _load(p)
		if s is BallSet:
			out.push_back(s)
	return out


static func arenas() -> Array[ArenaSet]:
	var out: Array[ArenaSet] = []
	for p in ARENAS:
		var s := _load(p)
		if s is ArenaSet:
			out.push_back(s)
	return out


static func get_arena(id: String) -> ArenaSet:
	for s in arenas():
		if s.id == id:
			return s
	return null


static func starter_arena() -> ArenaSet:
	var all := arenas()
	for s in all:
		if s.price_coins == 0:
			return s
	return all[0] if not all.is_empty() else null


static func get_hoop(id: String) -> HoopSet:
	for s in hoops():
		if s.id == id:
			return s
	return null


static func get_ball(id: String) -> BallSet:
	for s in balls():
		if s.id == id:
			return s
	return null


## The free set everyone owns: the first with price 0 (or the first listed).
static func starter_hoop() -> HoopSet:
	var all := hoops()
	for s in all:
		if s.price_coins == 0:
			return s
	return all[0] if not all.is_empty() else null


static func starter_ball() -> BallSet:
	var all := balls()
	for s in all:
		if s.price_coins == 0:
			return s
	return all[0] if not all.is_empty() else null
