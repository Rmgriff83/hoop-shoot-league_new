class_name TicketShop
extends RefCounted
## The ticket packs (design "Ticket Store" 50a, docs/ECONOMY.md → Ticket
## packs): two consumables that buy tickets, nothing else — the real-money
## rule holds (no path from money to online cards). The table is
## data/store.json, which the Worker reads too, so the ids, the amounts and
## the US prices never drift between the phone and the credit. The buying
## itself is `Store` (game/net/store.gd): RevenueCat's sheet, then the
## Worker's credit.

const PATH := "res://data/store.json"

static var _packs: Array = []
static var _entitlements: Array = []


## [{id, tickets, price (the US tier), best}], in the design's order.
static func packs() -> Array:
	if _packs.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		var rows: Array = Array(Dictionary(parsed).get("packs", [])) if parsed is Dictionary else []
		for p in rows:
			_packs.push_back({"id": str(p["id"]), "tickets": int(p["tickets"]), "price": str(p.get("priceUsd", "")), "best": bool(p.get("best", false))})
	return _packs


static func pack(id: String) -> Dictionary:
	for p in packs():
		if str(p["id"]) == id:
			return p
	return {}


static func ids() -> Array:
	return packs().map(func(p: Dictionary) -> String: return str(p["id"]))


## The one-time purchases the player OWNS (docs/ECONOMY.md → Remove ads):
## [{id, key, price}] — `key` is the RevenueCat entitlement the product
## is attached to, what Store.owns() answers for.
static func entitlements() -> Array:
	if _entitlements.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		var rows: Array = Array(Dictionary(parsed).get("entitlements", [])) if parsed is Dictionary else []
		for e in rows:
			_entitlements.push_back({"id": str(e["id"]), "key": str(e.get("key", e["id"])), "price": str(e.get("priceUsd", ""))})
	return _entitlements


static func entitlement(id: String) -> Dictionary:
	for e in entitlements():
		if str(e["id"]) == id:
			return e
	return {}


static func is_entitlement(id: String) -> bool:
	return not entitlement(id).is_empty()


## Every product id the store sells (packs first): what the prices are fetched for.
static func product_ids() -> Array:
	return ids() + entitlements().map(func(e: Dictionary) -> String: return str(e["id"]))


## The price as the player's store shows it: the live string `Store` fetched
## (the player's own currency), else the US tier from the table.
static func price(id: String) -> String:
	var store: Node = Engine.get_main_loop().root.get_node_or_null("Store") if Engine.get_main_loop() is SceneTree else null
	if store != null:
		var live := str(store.get("prices").get(id, ""))
		if live != "":
			return live
	var p := pack(id)
	return str(p.get("price", "")) if not p.is_empty() else str(entitlement(id).get("price", ""))
