class_name CardDefs
extends RefCounted
## Power-up card definitions (data/cards.json): one-time-use cards, three
## equippable per heat, consumed on deploy, acting on the opponent. The effect
## registry lives in CardEffects; a new card is a JSON row plus (at most) one
## new effect kind.

const PATH := "res://data/cards.json"
const SLOTS := 3

static var _doc: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_doc = parsed


static func all() -> Array:
	_load()
	return _doc.get("cards", [])


static func get_card(id: String) -> Dictionary:
	for c in all():
		if c["id"] == id:
			return c
	return {}


static func rarity_weights() -> Dictionary:
	_load()
	return _doc.get("rarity_weights", {"common": 60, "rare": 30, "epic": 10})


static func drop_odds() -> Dictionary:
	_load()
	return _doc.get("drop_odds", {"win": 0.6, "loss": 0.25, "playoff_bonus": 0.15})


# ---- power: measured by tools/card_lab.gd, the scale by data/cards.json -------
# See docs/CARDS.md. A card's power is its mean point swing per heat, per
# league; rarity and price DERIVE from it (bands + curve below) so a new card
# lands on the same scale as the old ones.

const POWER_PATH := "res://assets/cards/card_power.json"

static var _power: Dictionary = {}
static var _power_loaded := false


static func power_doc() -> Dictionary:
	if not _power_loaded:
		_power_loaded = true
		if FileAccess.file_exists(POWER_PATH):
			var f := FileAccess.open(POWER_PATH, FileAccess.READ)
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_power = parsed
	return _power


static func has_power(id: String) -> bool:
	return power_doc().get("cards", {}).has(id)


## Measured power in one league (0 when unmeasured — validate() flags that).
static func power(id: String, league_id: String) -> float:
	var row: Dictionary = power_doc().get("cards", {}).get(id, {})
	if row.has(league_id):
		return float(row[league_id])
	return power_mean(id)


## Mean over every league it was measured in — the number rarity and price
## hang on (they are global; the envelope uses the per-league power).
static func power_mean(id: String) -> float:
	var row: Dictionary = power_doc().get("cards", {}).get(id, {})
	if row.is_empty():
		return 0.0
	var s := 0.0
	for k in row:
		s += float(row[k])
	return s / row.size()


## {rarity: [lo, hi)} in power points, ascending.
static func rarity_bands() -> Dictionary:
	_load()
	return _doc.get("rarity_bands", {"common": [0.0, 2.5], "rare": [2.5, 4.0], "epic": [4.0, 99.0]})


static func rarity_for(p: float) -> String:
	var bands := rarity_bands()
	var best := ""
	var best_lo := -INF
	for r in bands:
		var lo := float(bands[r][0])
		var hi := float(bands[r][1])
		if p >= lo and p < hi and lo > best_lo:
			best = str(r)
			best_lo = lo
	if best == "":
		# Below every band → the lowest; above → the highest.
		var lowest := ""
		var highest := ""
		for r in bands:
			if lowest == "" or float(bands[r][0]) < float(bands[lowest][0]):
				lowest = str(r)
			if highest == "" or float(bands[r][1]) > float(bands[highest][1]):
				highest = str(r)
		best = lowest if p < float(bands[lowest][0]) else highest
	return best


## {k, exp, tolerance}: price = round10(k · power^exp), ± tolerance for feel.
static func price_curve() -> Dictionary:
	_load()
	return _doc.get("price_curve", {"k": 40.0, "exp": 1.3, "tolerance": 0.2})


static func price_for(p: float) -> int:
	var c := price_curve()
	return int(roundf(float(c.get("k", 40.0)) * pow(maxf(p, 0.0), float(c.get("exp", 1.3))) / 10.0) * 10)


## Is a stored price within the curve's tolerance of the derived one?
static func price_ok(price: int, p: float) -> bool:
	var want := price_for(p)
	var tol := float(price_curve().get("tolerance", 0.2))
	return absf(float(price) - float(want)) <= tol * float(maxi(want, 10))


static func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var ids := {}
	for c in all():
		for key in ["id", "name", "rarity", "price", "target", "effect", "blurb"]:
			if not c.has(key):
				problems.push_back("card %s missing %s" % [c.get("id", "?"), key])
		if ids.has(c.get("id", "")):
			problems.push_back("duplicate card id %s" % c.get("id", ""))
		ids[c.get("id", "")] = true
		if not CardEffects.KINDS.has(str(c.get("effect", {}).get("kind", ""))):
			problems.push_back("card %s has unknown effect kind" % c.get("id", "?"))
		if not rarity_weights().has(str(c.get("rarity", ""))):
			problems.push_back("card %s has unknown rarity" % c.get("id", "?"))
		if not (str(c.get("target", "")) in TARGETS):
			problems.push_back("card %s has unknown target" % c.get("id", "?"))
		if str(c.get("effect", {}).get("kind", "")) == "fire" and float(c.get("effect", {}).get("seconds", 0.0)) <= 0.0:
			problems.push_back("card %s fire effect needs seconds > 0" % c.get("id", "?"))
	return problems


## Who a card acts on: "self" (a boost for the player who plays it) or
## "opponent" (unknown ids count as opponent cards).
const TARGETS := ["self", "opponent"]


static func target_of(id: String) -> String:
	return str(get_card(id).get("target", "opponent"))


## Fresh inventory/loadout doc for the save's `cards` part. `inventory` holds
## the spare copies (id → n); `loadout` holds three slots, each a real copy
## taken out of the inventory (equipping moves it, unequipping returns it,
## playing it in a heat empties the slot). `v` 2 marks that layout; older
## docs (slots that merely referenced the inventory) go through migrate().
const DOC_VERSION := 2


static func empty_doc() -> Dictionary:
	return {"updatedAt": 0, "v": DOC_VERSION, "inventory": {}, "loadout": [null, null, null]}


## Spare (unequipped) copies of a card.
static func count(doc: Dictionary, id: String) -> int:
	return int(doc.get("inventory", {}).get(id, 0))


## Every copy of a card: spares plus the ones sitting in loadout slots.
static func owned(doc: Dictionary, id: String) -> int:
	var n := count(doc, id)
	for s in doc.get("loadout", []):
		if s != null and str(s) == id:
			n += 1
	return n


static func add(doc: Dictionary, id: String, n := 1) -> void:
	if not doc.has("inventory"):
		doc["inventory"] = {}
	doc["inventory"][id] = count(doc, id) + n


static func _take(doc: Dictionary, id: String) -> void:
	doc["inventory"][id] = count(doc, id) - 1
	if count(doc, id) <= 0:
		doc["inventory"].erase(id)


## Equip a copy into a slot (0..2): it leaves the inventory. A card already in
## that slot goes back first. False if the card is unknown or none are spare.
static func equip(doc: Dictionary, slot: int, id: String) -> bool:
	if slot < 0 or slot >= SLOTS or get_card(id).is_empty() or count(doc, id) <= 0:
		return false
	unequip(doc, slot)
	_take(doc, id)
	doc["loadout"][slot] = id
	return true


## Clear a slot; its copy returns to the inventory.
static func unequip(doc: Dictionary, slot: int) -> void:
	if slot < 0 or slot >= SLOTS:
		return
	var cur: Variant = doc["loadout"][slot]
	if cur != null and str(cur) != "":
		add(doc, str(cur))
	doc["loadout"][slot] = null


## A card was played: the first slot holding it empties. Cards are one-time
## use, so nothing returns to the inventory. False if no slot holds it.
static func consume(doc: Dictionary, id: String) -> bool:
	for i in SLOTS:
		if doc["loadout"][i] != null and str(doc["loadout"][i]) == id:
			doc["loadout"][i] = null
			return true
	return false


## Same, for a known slot: empties it only if it holds `id`.
static func consume_slot(doc: Dictionary, slot: int, id: String) -> bool:
	if slot < 0 or slot >= SLOTS or doc["loadout"][slot] == null or str(doc["loadout"][slot]) != id:
		return false
	doc["loadout"][slot] = null
	return true


## The equipped ids as a plain list (nulls dropped) — a heat's starting hand.
static func loadout_ids(doc: Dictionary) -> Array:
	var out := []
	for id in doc.get("loadout", []):
		if id != null and str(id) != "":
			out.push_back(str(id))
	return out


## The three slots as saved (null = empty), for slot-by-slot displays.
static func loadout_slots(doc: Dictionary) -> Array:
	var out := [null, null, null]
	var lo: Array = doc.get("loadout", [])
	for i in SLOTS:
		if i < lo.size() and lo[i] != null and str(lo[i]) != "":
			out[i] = str(lo[i])
	return out


## Bring an older doc up to DOC_VERSION. Version-1 slots only referenced the
## inventory (one owned copy could sit in all three slots): each equipped slot
## now takes a copy out of the inventory, and a slot with no copy to back it
## empties. Idempotent; returns true when anything changed.
static func migrate(doc: Dictionary) -> bool:
	if int(doc.get("v", 1)) >= DOC_VERSION:
		return false
	if not doc.has("inventory"):
		doc["inventory"] = {}
	var lo: Array = doc.get("loadout", [])
	while lo.size() < SLOTS:
		lo.push_back(null)
	for i in SLOTS:
		var id: Variant = lo[i]
		if id == null or str(id) == "" or get_card(str(id)).is_empty():
			lo[i] = null
		elif count(doc, str(id)) > 0:
			_take(doc, str(id))
		else:
			lo[i] = null
	doc["loadout"] = lo
	doc["v"] = DOC_VERSION
	return true
