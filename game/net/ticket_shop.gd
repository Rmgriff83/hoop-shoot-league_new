class_name TicketShop
extends RefCounted
## The ticket packs (design "Ticket Store" 50a, docs/ECONOMY.md → Ticket
## packs): two consumables that buy tickets, nothing else — the real-money
## rule holds (no path from money to online cards). The prices are the US
## tiers until the platform store (StoreKit / Play Billing) reports the
## player's own currency.
##
## The store itself is not wired yet (Ross, 2026-10-31): `purchase` holds the
## spinner for BUSY_S and then reports no sale, so nothing is ever granted.
## The real flow replaces it: the platform sheet, then the receipt verified
## by the Worker, which grants the tickets server-side before `done(true)`.

const BUSY_S := 1.4
const PACKS := [
	{"id": "tickets_300", "tickets": 300, "price": "$0.99"},
	{"id": "tickets_1000", "tickets": 1000, "price": "$2.99", "best": true},
]


static func pack(id: String) -> Dictionary:
	for p in PACKS:
		if str(p["id"]) == id:
			return p
	return {}


## The price as the player's store shows it (the US tier for now).
static func price(id: String) -> String:
	return str(pack(id).get("price", ""))


## Buy pack `id`; `done(ok: bool)` once the store answers. A stub for now:
## always false, nothing granted.
static func purchase(id: String, done: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or pack(id).is_empty():
		done.call(false)
		return
	tree.create_timer(BUSY_S).timeout.connect(func() -> void:
		if done.is_valid():   # the page may have closed meanwhile
			done.call(false)
	)
