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


## The price as the player's store shows it: the live string `Store` fetched
## (the player's own currency), else the US tier from the table.
static func price(id: String) -> String:
	var store: Node = Engine.get_main_loop().root.get_node_or_null("Store") if Engine.get_main_loop() is SceneTree else null
	if store != null:
		var live := str(store.get("prices").get(id, ""))
		if live != "":
			return live
	return str(pack(id).get("price", ""))
