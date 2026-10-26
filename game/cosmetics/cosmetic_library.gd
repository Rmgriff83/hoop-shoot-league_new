class_name CosmeticLibrary
extends RefCounted
## Registry of every hoop, ball, net and arena set. Explicit lists (no directory
## scanning) so exported builds behave; manifests load on demand and are
## cached. Adding a set = adding its folder under assets/ and one path here.
## Order matters for starters: the first price-0 set of each kind is the one
## everyone owns.

const HOOPS: Array[String] = [
	"res://assets/hoops/classic/hoop_set.tres",
	"res://assets/hoops/street/hoop_set.tres",
	"res://assets/hoops/chain/hoop_set.tres",
	"res://assets/hoops/park/hoop_set.tres",
]
const BALLS: Array[String] = [
	"res://assets/balls/classic/ball_set.tres",
	"res://assets/balls/cherry/ball_set.tres",
	"res://assets/balls/pink/ball_set.tres",
	"res://assets/balls/royal/ball_set.tres",
	"res://assets/balls/forest/ball_set.tres",
	"res://assets/balls/grape/ball_set.tres",
	"res://assets/balls/lemon/ball_set.tres",
	"res://assets/balls/snow/ball_set.tres",
	"res://assets/balls/lagoon/ball_set.tres",
	"res://assets/balls/lime/ball_set.tres",
	"res://assets/balls/blacktop/ball_set.tres",
	"res://assets/balls/midnight/ball_set.tres",
	"res://assets/balls/offwhite/ball_set.tres",
	"res://assets/balls/lightgray/ball_set.tres",
	"res://assets/balls/tan/ball_set.tres",
	"res://assets/balls/babyblue/ball_set.tres",
	"res://assets/balls/usa/ball_set.tres",
	"res://assets/balls/italia/ball_set.tres",
	"res://assets/balls/brasil/ball_set.tres",
	"res://assets/balls/jamaica/ball_set.tres",
	"res://assets/balls/mexico/ball_set.tres",
	"res://assets/balls/colombia/ball_set.tres",
	"res://assets/balls/venezuela/ball_set.tres",
	"res://assets/balls/argentina/ball_set.tres",
	"res://assets/balls/france/ball_set.tres",
	"res://assets/balls/globetrotters/ball_set.tres",
	"res://assets/balls/aba/ball_set.tres",
	"res://assets/balls/neon/ball_set.tres",
	"res://assets/balls/bubblegum/ball_set.tres",
	"res://assets/balls/retro/ball_set.tres",
	"res://assets/balls/varsity/ball_set.tres",
	"res://assets/balls/neon_lime/ball_set.tres",
	"res://assets/balls/neon_pink/ball_set.tres",
	"res://assets/balls/neon_cyan/ball_set.tres",
	"res://assets/balls/neon_volt/ball_set.tres",
	"res://assets/balls/neon_violet/ball_set.tres",
	"res://assets/balls/speckle_cream/ball_set.tres",
	"res://assets/balls/speckle_navy/ball_set.tres",
	"res://assets/balls/speckle_mint/ball_set.tres",
	"res://assets/balls/speckle_coral/ball_set.tres",
	"res://assets/balls/camo/ball_set.tres",
	"res://assets/balls/desert/ball_set.tres",
	"res://assets/balls/urban/ball_set.tres",
	"res://assets/balls/pinkcamo/ball_set.tres",
	"res://assets/balls/tiger/ball_set.tres",
	"res://assets/balls/zebra/ball_set.tres",
	"res://assets/balls/leopard/ball_set.tres",
	"res://assets/balls/leopard_snow/ball_set.tres",
	"res://assets/balls/leopard_pink/ball_set.tres",
	"res://assets/balls/leopard_neon/ball_set.tres",
	"res://assets/balls/leopard_blue/ball_set.tres",
	"res://assets/balls/checker/ball_set.tres",
	"res://assets/balls/checker_bw/ball_set.tres",
	"res://assets/balls/checker_red/ball_set.tres",
	"res://assets/balls/checker_teal/ball_set.tres",
	"res://assets/balls/checker_purple/ball_set.tres",
	"res://assets/balls/polka/ball_set.tres",
	"res://assets/balls/polka_navy/ball_set.tres",
	"res://assets/balls/polka_mint/ball_set.tres",
	"res://assets/balls/polka_yellow/ball_set.tres",
	"res://assets/balls/polka_black/ball_set.tres",
	"res://assets/balls/pineapple/ball_set.tres",
	"res://assets/balls/watermelon/ball_set.tres",
	"res://assets/balls/galaxy/ball_set.tres",
	"res://assets/balls/galaxy_rose/ball_set.tres",
	"res://assets/balls/galaxy_emerald/ball_set.tres",
	"res://assets/balls/galaxy_solar/ball_set.tres",
	"res://assets/balls/galaxy_aqua/ball_set.tres",
	"res://assets/balls/sunset/ball_set.tres",
	"res://assets/balls/ice/ball_set.tres",
	"res://assets/balls/fire/ball_set.tres",
	"res://assets/balls/gold/ball_set.tres",
	"res://assets/balls/chrome/ball_set.tres",
	"res://assets/balls/beach/ball_set.tres",
	"res://assets/balls/eightball/ball_set.tres",
	"res://assets/balls/pumpkin/ball_set.tres",
	"res://assets/balls/smiley/ball_set.tres",
	"res://assets/balls/soccer/ball_set.tres",
	"res://assets/balls/globe/ball_set.tres",
	"res://assets/balls/tennis/ball_set.tres",
	"res://assets/balls/baseball/ball_set.tres",
	"res://assets/balls/moon/ball_set.tres",
	"res://assets/balls/mars/ball_set.tres",
	"res://assets/balls/donut/ball_set.tres",
	"res://assets/balls/skeleton/ball_set.tres",
	"res://assets/balls/frankenstein/ball_set.tres",
	"res://assets/balls/woodgrain/ball_set.tres",
	"res://assets/balls/mahogany/ball_set.tres",
	"res://assets/balls/mosaic/ball_set.tres",
	"res://assets/balls/mosaic_blue/ball_set.tres",
	"res://assets/balls/mosaic_red/ball_set.tres",
]
## Net styles (docs/LOCKER.md → NETS): the stock pair first, then the counter.
const NETS: Array[String] = [
	"res://assets/nets/cotton/net_set.tres",
	"res://assets/nets/chain/net_set.tres",
	"res://assets/nets/jack/net_set.tres",
	"res://assets/nets/ladder/net_set.tres",
	"res://assets/nets/wool/net_set.tres",
	"res://assets/nets/neon_yellow/net_set.tres",
	"res://assets/nets/neon_orange/net_set.tres",
	"res://assets/nets/rwb/net_set.tres",
	"res://assets/nets/tattered/net_set.tres",
	"res://assets/nets/neon_blue/net_set.tres",
	"res://assets/nets/neon_purple/net_set.tres",
	"res://assets/nets/wool_ocean/net_set.tres",
	"res://assets/nets/wool_ember/net_set.tres",
	"res://assets/nets/rasta/net_set.tres",
]
const ARENAS: Array[String] = [
	"res://assets/arena/cage/arena_set.tres",
	"res://assets/arena/beach/arena_set.tres",
	"res://assets/arena/city/arena_set.tres",
	"res://assets/arena/park/arena_set.tres",
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


static func nets() -> Array[NetSet]:
	var out: Array[NetSet] = []
	for p in NETS:
		var s := _load(p)
		if s is NetSet:
			out.push_back(s)
	return out


static func get_net(id: String) -> NetSet:
	for s in nets():
		if s.id == id:
			return s
	return null


static func nets_of_kind(kind: String) -> Array[NetSet]:
	var out: Array[NetSet] = []
	for s in nets():
		if s.kind == kind:
			out.push_back(s)
	return out


## The stock net of a kind (the `stock` flag; else the first of the kind).
static func stock_net(kind: String) -> NetSet:
	var all := nets_of_kind(kind)
	for s in all:
		if s.stock:
			return s
	return all[0] if not all.is_empty() else null


## A kit off the wire (MatchProtocol.kit: ids only) as the sets this build
## has: {ball: BallSet, net: NetSet, hoop: HoopSet|null}. An id this catalog
## does not know — a newer build's net, a typo, {} — resolves to the court's
## stock: the starter ball, the stock net of `stock_kind` (the court's hoop's
## kind), no hoop (the court keeps its own). Any net hangs on any hoop
## (Ross, 2026-10-16), so no fit rule lives here — this is where one would.
static func resolve_kit(kit: Dictionary, stock_kind: String) -> Dictionary:
	var ball := get_ball(str(kit.get("ball", "")))
	var net := get_net(str(kit.get("net", "")))
	var hoop := get_hoop(str(kit.get("hoop", ""))) if kit.has("hoop") else null
	return {
		"ball": ball if ball != null else starter_ball(),
		"net": net if net != null else stock_net(stock_kind),
		"hoop": hoop,
	}


## Every stock net: owned by every save. Every other net is a PEGGY prize.
static func stock_nets() -> Array[NetSet]:
	var out: Array[NetSet] = []
	for s in nets():
		if s.stock:
			out.push_back(s)
	return out
