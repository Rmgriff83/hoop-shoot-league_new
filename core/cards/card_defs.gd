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
		for key in ["id", "name", "rarity", "price", "target", "effect", "blurb", "level"]:
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
		if str(c.get("effect", {}).get("kind", "")) in ["fire", "vortex"] and float(c.get("effect", {}).get("seconds", 0.0)) <= 0.0:
			problems.push_back("card %s %s effect needs seconds > 0" % [c.get("id", "?"), c.get("effect", {}).get("kind", "")])
		problems.append_array(validate_fx(c))
	return problems


## The face's loop (design "Card Icons" 9a, game/ui/card_face.gd): `fx =
## {sheet, frames, fps, rect: [x, y, w, h] in face pixels at 96×128, chip:
## [w, h] (the 40 px chip's sprite), chip_bg (the chip's colour), glyph (the
## small static icon for tags and captions)}. Files are checked by the suite.
const FACE_W := 96
const FACE_H := 128


static func validate_fx(c: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var id := str(c.get("id", "?"))
	if not (c.get("fx", null) is Dictionary):
		out.push_back("card %s missing fx" % id)
		return out
	var fx: Dictionary = c["fx"]
	for key in ["sheet", "frames", "fps", "rect", "chip", "chip_bg", "glyph"]:
		if not fx.has(key):
			out.push_back("card %s fx missing %s" % [id, key])
	if int(fx.get("frames", 0)) < 1:
		out.push_back("card %s fx needs frames >= 1" % id)
	if float(fx.get("fps", 0.0)) <= 0.0:
		out.push_back("card %s fx needs fps > 0" % id)
	var r: Array = fx.get("rect", []) if fx.get("rect", null) is Array else []
	if r.size() != 4 or int(r[0]) < 0 or int(r[1]) < 0 or int(r[2]) < 1 or int(r[3]) < 1 \
			or int(r[0]) + int(r[2]) > FACE_W or int(r[1]) + int(r[3]) > FACE_H:
		out.push_back("card %s fx rect must be [x, y, w, h] inside the %dx%d face" % [id, FACE_W, FACE_H])
	var ch: Array = fx.get("chip", []) if fx.get("chip", null) is Array else []
	if ch.size() != 2 or int(ch[0]) < 1 or int(ch[0]) > 36 or int(ch[1]) < 1 or int(ch[1]) > 36:
		out.push_back("card %s fx chip must be [w, h] within the chip's 36 px" % id)
	if not Color.html_is_valid(str(fx.get("chip_bg", ""))):
		out.push_back("card %s fx chip_bg is not a colour" % id)
	return out


## Who a card acts on: "self" (a boost for the player who plays it) or
## "opponent" (unknown ids count as opponent cards).
const TARGETS := ["self", "opponent"]


static func target_of(id: String) -> String:
	return str(get_card(id).get("target", "opponent"))


## The save's `cards` part, v3 (docs/ECONOMY.md): ONE BUCKET PER LEAGUE —
## `leagues[id] = {coins, inventory, loadout}`. Coins earned in a league are
## spent there; cards bought or dropped there stay there. `inventory` holds
## the spare copies (id → n); `loadout` holds three slots, each a real copy
## taken out of the inventory (equipping moves it, unequipping returns it,
## playing it in a heat empties the slot). The inventory ops below take a
## BUCKET (league_doc), not the whole doc. Older docs (v1 referenced slots,
## v2 one global inventory) are wiped by migrate() — the economy changed
## under them.
const DOC_VERSION := 3


static func empty_doc() -> Dictionary:
	return {"updatedAt": 0, "v": DOC_VERSION, "leagues": {}}


static func empty_bucket() -> Dictionary:
	return {"coins": 0, "inventory": {}, "loadout": [null, null, null]}


## The league's bucket inside `doc`, created on first touch (a reference:
## mutate it, then save the doc).
static func league_doc(doc: Dictionary, league_id: String) -> Dictionary:
	if not doc.has("leagues"):
		doc["leagues"] = {}
	if not doc["leagues"].has(league_id):
		doc["leagues"][league_id] = empty_bucket()
	return doc["leagues"][league_id]


static func coins(doc: Dictionary, league_id: String) -> int:
	return int(Dictionary(doc.get("leagues", {})).get(league_id, {}).get("coins", 0))


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


## Bring an older doc up to DOC_VERSION. v1 and v2 held one global inventory
## paid for with one global wallet; the economy is per league now, so they
## are wiped (dev saves, by decision). Idempotent; returns true when changed.
static func migrate(doc: Dictionary) -> bool:
	if int(doc.get("v", 1)) >= DOC_VERSION and doc.has("leagues"):
		return false
	for k in doc.keys():
		doc.erase(k)
	doc.merge(empty_doc())
	return true
