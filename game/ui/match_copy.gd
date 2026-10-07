class_name MatchCopy
extends RefCounted
## The online match words (docs/BACKEND.md → Phase 3): the lobby page's
## buttons and states, the code display, the result header. Pure.


static func title(area: String) -> String:
	return "%s · 1V1" % RanksCopy.tab_name(area)


static func quick_sub() -> String:
	return "THE NEXT PLAYER IN THIS AREA"


static func code_sub() -> String:
	return "MAKE A CODE FOR A FRIEND"


static func join_sub() -> String:
	return "GOT ONE? TYPE IT IN"


## `CODE AB CDE · TELL YOUR FRIEND`
static func code_line(code: String) -> String:
	var c := code.to_upper()
	return "CODE %s %s · TELL YOUR FRIEND" % [c.substr(0, 2), c.substr(2)] if c.length() == 5 else "CODE %s" % c


static func waiting_line(how: String) -> String:
	return "FINDING A PLAYER..." if how == "quick" else "WAITING FOR YOUR FRIEND..."


static func found_line(peer: Dictionary) -> String:
	return "%s IS HERE · TIP OFF" % HandleWords.display(str(peer.get("name", "THEM")), str(peer.get("tag", "")))


static func failed_line(reason: String) -> String:
	match reason:
		"expired": return "NOBODY CAME · TRY AGAIN"
		"not_found": return "NO MATCH FOR THAT CODE"
		"own_code": return "THAT IS YOUR OWN CODE"
		"offline": return "NO SIGNAL · TRY AGAIN LATER"
		"peer_left": return "THEY LEFT · TRY AGAIN"
		"throttled": return "EASY · TRY AGAIN IN A MINUTE"
		_: return "COULD NOT CONNECT · TRY AGAIN"


## The post-match header: `ONLINE MATCH · BEACH`, with how it ended.
static func header(heat: Dictionary) -> String:
	var area := RanksCopy.tab_name(str(heat.get("location", "cage")))
	match str(heat.get("reason", "")):
		"forfeit": return "ONLINE MATCH · %s · THEY LEFT" % area
		"void": return "ONLINE MATCH · %s · VOID" % area
	return "ONLINE MATCH · %s" % area


static func strings() -> Array:
	var out := ["QUICK MATCH", "CREATE CODE", "ENTER CODE", "GO", "CANCEL", "<", quick_sub(), code_sub(), join_sub(),
		code_line("ABCDE"), waiting_line("quick"), waiting_line("code"), found_line({"name": "GLASS WIZARD", "tag": "07"}),
		header({"location": "beach"}), header({"location": "city", "reason": "forfeit"}), header({"location": "cage", "reason": "void"})]
	for a in RanksCopy.AREAS:
		out.push_back(title(a))
	for r in ["expired", "not_found", "own_code", "offline", "peer_left", "throttled", "x"]:
		out.push_back(failed_line(r))
	return out
