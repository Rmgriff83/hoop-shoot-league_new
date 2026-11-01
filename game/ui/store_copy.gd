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


## The store SDK's own message under PURCHASE FAILED, made safe for the
## pixel font: printable ASCII only, upper case, at most DETAIL_MAX glyphs.
const DETAIL_MAX := 40

static func detail(message: String) -> String:
	var out := ""
	for ch in message:
		var c := ch.unicode_at(0)
		out += ch if c >= 32 and c < 127 else " "
	out = out.strip_edges().to_upper()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.substr(0, DETAIL_MAX)


## Every line, for the glyph test.
static func strings() -> Array:
	return [failed(), on_the_way(), credited(1300), unavailable(), detail("Error fetching product: \u201cx\u201d (code 23)")]
