class_name StoreCopy
extends RefCounted
## The Ticket Store's lines beyond the design (docs/ECONOMY.md → Ticket
## packs): what the toasts say when a purchase fails, when the store took
## the money but the credit is still on its way, and when it lands.


static func failed() -> String:
	return "PURCHASE FAILED"


## The store sold the pack but the Worker has not credited it yet (the fast poll gave up).
static func on_the_way() -> String:
	return "TICKETS ON THE WAY"


static func credited(n: int) -> String:
	return "+%s TICKETS" % RetroTheme.thousands(n)


static func unavailable() -> String:
	return "STORE UNAVAILABLE"


## Every line, for the glyph test.
static func strings() -> Array:
	return [failed(), on_the_way(), credited(1300), unavailable()]
