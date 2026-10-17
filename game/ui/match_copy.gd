class_name MatchCopy
extends RefCounted
## The online match words (docs/BACKEND.md → Phase 3; design "Online Lobby"
## 37a, 2026-10-17): the lobby page's buttons and states, the code display,
## the result header. Pure.

const AREAS := ["any", "cage", "beach", "park", "city"]


static func title() -> String:
	return "ONLINE · 1V1"


## The court picker's short names (ANY first).
static func court_name(area: String) -> String:
	return "ANY" if area == "any" else RanksCopy.tab_name(area)


static func court_full(area: String) -> String:
	match area:
		"any": return "ANY OPEN COURT"
		"cage": return "ARCADE CAGE"
	return RanksCopy.tab_name(area)


## `n OF 4 OWNED`, or the nudge while only the cage is open.
static func court_note(owned: int) -> String:
	return "UNLOCK MORE COURTS TO CHOOSE" if owned < 2 else "%d OF 4 OWNED" % owned


static func quick_sub(area := "any") -> String:
	return "FIRST OPEN MATCH ON YOUR COURTS" if area == "any" else "PLAY WHOEVER IS ON %s" % court_full(area)


static func code_sub() -> String:
	return "PLAY A FRIEND"


static func join_sub() -> String:
	return "GOT A CODE FROM A FRIEND? TYPE IT IN"


## Over the big gold code while a friend is awaited.
static func code_caption() -> String:
	return "TELL A FRIEND THIS CODE"


## `CODE AB CDE · TELL YOUR FRIEND` (the heat screen's banner).
static func code_line(code: String) -> String:
	var c := code.to_upper()
	return "CODE %s %s · TELL YOUR FRIEND" % [c.substr(0, 2), c.substr(2)] if c.length() == 5 else "CODE %s" % c


## The big line while waiting: FINDING A PLAYER / WAITING (dots added live).
static func waiting_big(how: String) -> String:
	return "FINDING A PLAYER" if how == "quick" else "WAITING"


static func waiting_line(how: String) -> String:
	return "USUALLY UNDER 30 SECONDS" if how == "quick" else "THE MATCH STARTS AS SOON AS THEY JOIN"


static func found_big() -> String:
	return "PLAYER FOUND"


## `NEON OWL 42 · LVL 07 · STARTING` (dots added live).
static func found_line(peer: Dictionary) -> String:
	var who := HandleWords.display(str(peer.get("name", "THEM")), str(peer.get("tag", "")))
	var lvl := int(peer.get("level", 0))
	return ("%s · LVL %02d · STARTING" % [who, lvl]) if lvl > 0 else ("%s · STARTING" % who)


static func failed_big(reason: String) -> String:
	match reason:
		"expired": return "NOBODY CAME"
		"not_found": return "CODE NOT FOUND"
		"own_code": return "THAT IS YOUR CODE"
		"offline": return "NO SIGNAL"
		"peer_left": return "THEY LEFT"
		"throttled": return "EASY THERE"
		_: return "NO CONNECTION"


static func failed_line(reason: String) -> String:
	match reason:
		"expired": return "NOBODY CAME · TRY AGAIN"
		"not_found": return "CHECK THE 5 LETTERS AND TRY AGAIN"
		"own_code": return "GIVE IT TO A FRIEND, THEN WAIT HERE"
		"offline": return "NO SIGNAL · TRY AGAIN LATER"
		"peer_left": return "THEY LEFT · TRY AGAIN"
		"throttled": return "TRY AGAIN IN A MINUTE"
		_: return "COULD NOT CONNECT · TRY AGAIN"


## The loadout's lines: `n OF 3 · TAP TO REMOVE`, the spares' caption.
static func loadout_line(set_count: int) -> String:
	return "%d OF 3 · TAP TO REMOVE" % set_count


static func spares_caption(any_spares: bool) -> String:
	return "TAP TO ADD" if any_spares else "NONE LEFT · WIN MORE IN LEAGUES"


static func slot_empty(i: int) -> String:
	return "SLOT %d EMPTY" % (i + 1)


## The post-match header: `ONLINE MATCH · BEACH`, with how it ended.
static func header(heat: Dictionary) -> String:
	var area := RanksCopy.tab_name(str(heat.get("location", "cage")))
	match str(heat.get("reason", "")):
		"forfeit": return "ONLINE MATCH · %s · THEY LEFT" % area
		"void": return "ONLINE MATCH · %s · VOID" % area
	return "ONLINE MATCH · %s" % area


## The post-match REMATCH card by state: "" (nothing yet), offered (we
## asked), wanted (they asked), both (tipping off), gone (they left).
static func rematch_title(state: String) -> String:
	match state:
		"wanted": return "THEY WANT A REMATCH"
		"both": return "REMATCH ON"
		"gone": return "THEY LEFT"
	return "REMATCH?"


static func rematch_sub(state: String) -> String:
	match state:
		"offered": return "WAITING FOR THEM..."
		"wanted": return "TAP TO ACCEPT"
		"both": return "TIPPING OFF..."
		"gone": return "BACK HOME FOR ANOTHER"
	return "ASK FOR ANOTHER"


## Can the card be tapped in this state?
static func rematch_active(state: String) -> bool:
	return state == "" or state == "wanted"


const REMATCH_STATES := ["", "offered", "wanted", "both", "gone"]


static func strings() -> Array:
	var out := ["QUICK MATCH", "CREATE CODE", "ENTER CODE", "GO", "CANCEL", "BACK", "<", ">", title(), code_sub(), join_sub(), code_caption(),
		code_line("ABCDE"), waiting_big("quick"), waiting_big("code"), waiting_line("quick"), waiting_line("code"), found_big(),
		found_line({"name": "GLASS WIZARD", "tag": "07", "level": 7}), found_line({"name": "GLASS WIZARD", "tag": "07"}),
		court_note(1), court_note(3), loadout_line(2), spares_caption(true), spares_caption(false), slot_empty(2), "LOADOUT", "YOUR CARDS", "COURT",
		header({"location": "beach"}), header({"location": "city", "reason": "forfeit"}), header({"location": "cage", "reason": "void"})]
	for a in AREAS:
		out.push_back(court_name(a))
		out.push_back(court_full(a))
		out.push_back(quick_sub(a))
	for r in ["expired", "not_found", "own_code", "offline", "peer_left", "throttled", "x"]:
		out.push_back(failed_big(r))
		out.push_back(failed_line(r))
	for st in REMATCH_STATES:
		out.push_back(rematch_title(st))
		out.push_back(rematch_sub(st))
	return out
