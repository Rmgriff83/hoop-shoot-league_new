class_name MatchCopy
extends RefCounted
## The online match words (docs/BACKEND.md → Phase 3; design "Online Lobby"
## 37a, 2026-10-17, the face-off 2026-10-18): the lobby page's buttons and
## states, the face-off cards, the code display, the result header. Pure.

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
	match how:
		"ranked": return "FINDING A RATED OPPONENT"
		"quick": return "FINDING A PLAYER"
	return "WAITING"


static func waiting_line(how: String) -> String:
	match how:
		"ranked": return "CLOSE IN RATING FIRST · WIDER AS YOU WAIT"
		"quick": return "USUALLY UNDER 30 SECONDS"
	return "THE MATCH STARTS AS SOON AS THEY JOIN"


## Under RANKED on the menu (2026-10-19): one global rated queue, any court.
static func ranked_sub() -> String:
	return "ANY COURT · RATED · ONE GLOBAL LADDER"


static func found_big() -> String:
	return "PLAYER FOUND"


## Under PLAYER FOUND: STARTING (dots added live). Who it is sits on the
## opponent's card now (design 37a, 2026-10-18).
static func found_line() -> String:
	return "STARTING"


# ---- the face-off (design 37a, 2026-10-18) ----------------------------------------------


static func you_label() -> String:
	return "YOU"


static func opp_label() -> String:
	return "OPP"


static func vs_word() -> String:
	return "VS"


## `#42`: the tag beside the name on a face-off card.
static func card_tag(rec: Dictionary) -> String:
	var tag := str(rec.get("tag", ""))
	return "#" + tag if tag != "" else ""


## `SALT HARBOR · LVL 09`, or `LVL 09` without a town (an old Worker sends none).
static func card_place(rec: Dictionary) -> String:
	var town := str(rec.get("town", "")).strip_edges()
	var lvl := "LVL %02d" % maxi(1, int(rec.get("level", 1)))
	return "%s · %s" % [town, lvl] if town != "" else lvl


## The online line of a face-off card: the ladder badge and the record
## (`PRO II · 12-9`, `LEGEND #12 · 40-11`) from `rank` ({tier, division,
## position?, wins, losses, games}); `ONLINE · UNRANKED` without a rated game.
static func card_online(rec: Dictionary) -> String:
	var rank: Variant = rec.get("rank", null)
	if not (rank is Dictionary) or int(rank.get("games", 0)) <= 0:
		return "ONLINE · UNRANKED"
	var line := RankedRules.badge_text(rank)
	if rank.has("wins") and rank.has("losses"):
		line += " · %d-%d" % [int(rank["wins"]), int(rank["losses"])]
	return line


# ---- the pre-match pick (docs/BACKEND.md → Ranked, 2026-10-19) -------------------------


static func prematch_title() -> String:
	return "PICK YOUR CARDS"


## `CARD CAP · LVL 3 · THE LOWER LEVEL PLAYS` — both loadouts stop at the
## lower of the two levels (a level-7 card never meets a level-2 player).
static func cap_line(cap: int) -> String:
	return "CARD CAP · LVL %d · THE LOWER LEVEL PLAYS" % maxi(1, cap)


static func ready_word(ready: bool) -> String:
	return "WAITING FOR THEM" if ready else "READY"


## `TIP-OFF IN 12` over the timer bar; the room starts at zero either way.
static func timer_line(seconds_left: float) -> String:
	return "TIP-OFF IN %d" % maxi(0, int(ceil(seconds_left)))


static func ranked_chip() -> String:
	return "RATED"


## The post-match rank line: `RATING +18 · PRO II`, with the event after it
## (`PROMOTED`, `SHIELDED`, `FLOOR HELD`); `RATED · NO CHANGE` on a void.
static func rank_delta_line(settle: Dictionary) -> String:
	if not bool(settle.get("ranked", false)):
		return ""
	var rating: Variant = settle.get("rating", null)
	if not (rating is Dictionary):
		return "RATED · NO CHANGE"
	var delta := int(roundf(float(rating.get("delta", 0.0))))
	var line := "RATING %s%d" % ["+" if delta >= 0 else "", delta]
	if settle.get("rank") is Dictionary:
		var rank: Dictionary = settle["rank"]
		rank = rank.duplicate()
		rank["games"] = maxi(1, int(rank.get("games", 1)))
		line += " · " + RankedRules.badge_text(rank)
	for ev in settle.get("events", []):
		match str(ev):
			"promoted": line += " · PROMOTED"
			"shielded": line += " · SHIELDED"
			"floored": line += " · FLOOR HELD"
			"demoted": line += " · DOWN A DIVISION"
	return line


## `COURT · BEACH` under the found card ("ANY OPEN COURT" until it is known).
static func found_court(area: String) -> String:
	return "COURT · %s" % court_full(area if area != "" else "any")


## One face on the search reel: a handle, a town, a level and a rank, all
## made up — the spinner, not real players.
static func reel_entry(rng: DetRng) -> Dictionary:
	var h := HandleWords.generate(rng)
	return {
		"name": str(h["name"]),
		"place": "%s · LVL %02d" % [str(rng.pick(Towns.list())), rng.range_i(1, 12)],
		"online": "ONLINE #%s" % RetroTheme.thousands(rng.range_i(100, 5000)),
	}


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
		found_line(), you_label(), opp_label(), vs_word(), "?", "...", card_tag({"tag": "07"}),
		card_place({"town": "SALT HARBOR", "level": 9}), card_place({"level": 7}), card_online({}),
		card_online({"rank": {"tier": "pro", "division": 2, "wins": 12, "losses": 9, "games": 21}}),
		card_online({"rank": {"tier": "legend", "division": 1, "position": 12, "wins": 40, "losses": 11, "games": 51}}),
		waiting_big("ranked"), waiting_line("ranked"), ranked_sub(), "RANKED", prematch_title(), cap_line(3), ready_word(true), ready_word(false),
		timer_line(12.4), ranked_chip(), rank_delta_line({"ranked": true, "rating": {"delta": 18}, "rank": {"tier": "pro", "division": 2}, "events": ["promoted"]}),
		rank_delta_line({"ranked": true, "rating": {"delta": -7}, "rank": {"tier": "rookie", "division": 3}, "events": ["shielded", "floored", "demoted"]}),
		rank_delta_line({"ranked": true}),
		court_note(1), court_note(3), loadout_line(2), spares_caption(true), spares_caption(false), slot_empty(2), "LOADOUT", "YOUR CARDS", "COURT",
		header({"location": "beach"}), header({"location": "city", "reason": "forfeit"}), header({"location": "cage", "reason": "void"})]
	for a in AREAS:
		out.push_back(court_name(a))
		out.push_back(court_full(a))
		out.push_back(quick_sub(a))
		out.push_back(found_court(a))
	for r in ["expired", "not_found", "own_code", "offline", "peer_left", "throttled", "x"]:
		out.push_back(failed_big(r))
		out.push_back(failed_line(r))
	for st in REMATCH_STATES:
		out.push_back(rematch_title(st))
		out.push_back(rematch_sub(st))
	return out
