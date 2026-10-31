class_name MatchCopy
extends RefCounted
## The online match words (docs/BACKEND.md → Phase 3; design "Online Lobby"
## 37a, 2026-10-17, the face-off 2026-10-18): the lobby page's buttons and
## states, the face-off cards, the code display, the result header. Pure.

const AREAS := ["any", "cage", "beach", "park", "city"]


static func title() -> String:
	return "ONLINE"


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
static func ranked_title() -> String:
	return "RANKED MATCH"


static func ranked_sub() -> String:
	return "RATED · ONE GLOBAL LADDER"


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


# ---- the menu's player card and leaderboard (design 37a, 2026-10-25) ------------------


## The card's badge: `MVP II`, `LEGEND #3`, or UNRANKED before a rated game.
static func you_badge(rank: Dictionary) -> String:
	if rank.is_empty() or int(rank.get("games", 0)) <= 0:
		return "UNRANKED"
	return RankedRules.badge_text(rank)


## Under the badge: `#18 · 32-16` (your ladder position and record).
static func you_record_line(rank: Dictionary) -> String:
	if rank.is_empty() or int(rank.get("games", 0)) <= 0:
		return "PLAY A RATED GAME"
	var bits := []
	if int(rank.get("position", 0)) > 0:
		bits.push_back("#" + RetroTheme.thousands(int(rank["position"])))
	bits.push_back("%d-%d" % [int(rank.get("wins", 0)), int(rank.get("losses", 0))])
	return " · ".join(bits)


## The bar's words: `16 / 50 TO MVP I`.
static func progress_line(p: Dictionary) -> String:
	var next := {"tier": str(p.get("next_tier", "")), "division": int(p.get("next_division", 3)), "games": 1}
	return "%d / %d TO %s" % [int(p.get("have", 0)), int(p.get("need", 0)), RankedRules.badge_text(next)]


static func leaderboard_head() -> String:
	return "GLOBAL LEADERBOARD"


static func leaderboard_sub() -> String:
	return "TOP 5 · RATED"


static func all_ranks() -> String:
	return "ALL RANKS >"


static func leaderboard_loading() -> String:
	return "LOADING..."


static func leaderboard_empty() -> String:
	return "NO RATED GAMES YET · BE FIRST"


static func leaderboard_offline() -> String:
	return "NO SIGNAL · THE LADDER NEEDS A CONNECTION"


# ---- the pre-match pick (docs/BACKEND.md → Ranked, 2026-10-19) -------------------------


static func prematch_title() -> String:
	return "PICK YOUR CARDS"


## `CARD CAP · LVL 3 · THE LOWER LEVEL PLAYS` — both loadouts stop at the
## lower of the two levels (a level-7 card never meets a level-2 player).
static func cap_line(cap: int, league := false) -> String:
	if league:
		return "CARD CAP · LVL %d · YOUR LEVEL" % maxi(1, cap)
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


# ---- the pre-match page (design "Pre Match" 37a, 2026-10-23) -------------------------------------

static func prematch_tab_opp() -> String:
	return "OPPONENT"


static func prematch_tab_you() -> String:
	return "YOU"


static func their_loadout() -> String:
	return "THEIR LOADOUT"


static func your_loadout() -> String:
	return "YOUR LOADOUT"


## YOUR CARDS' count on the right: `4 CARDS` (every owned card, spares and armed).
static func cards_count(n: int) -> String:
	return "%d CARD%s" % [n, "" if n == 1 else "S"]


static func load_count(n: int) -> String:
	return "%d OF %d" % [n, CardDefs.SLOTS]


static func your_cards_hint() -> String:
	return "YOUR CARDS · HOLD + DRAG TO A SLOT"


## Their side's state while they pick: `PICKING CARDS...` while slots are still filling, else `DECIDING...`.
static func opp_status(picking: bool) -> String:
	return "PICKING CARDS..." if picking else "DECIDING..."


static func starts_in() -> String:
	return "MATCH STARTS IN"


static func go_word() -> String:
	return "GO"


static func arm_word() -> String:
	return "ARM"


## `1,480`.
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var k := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		k += 1
		if k % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


## An online card's three stats from the room's `matched` stats + tier: RANK (the world
## position, or the badge, or NEW), RATING (the shown rating), RECORD.
static func online_stats(st: Dictionary, tier: Dictionary) -> Array:
	var games := int(st.get("games", 0))
	var rank := "NEW"
	if games > 0:
		rank = "#%d" % int(st["position"]) if int(st.get("position", 0)) > 0 else RankedRules.badge_text({"tier": str(tier.get("tier", "rookie")), "division": int(tier.get("division", 3)), "games": games})
	var rating := thousands(int(st.get("cons", 0))) if games > 0 else "-"
	var out := [[rank, "RANK"], [rating, "RATING"], ["%d-%d" % [int(st.get("wins", 0)), int(st.get("losses", 0))], "RECORD"]]
	var ws := int(st.get("win_streak", 0))
	var ls := int(st.get("loss_streak", 0))
	return with_streak(out, "W" if ws >= ls else "L", maxi(ws, ls))


## A win or loss streak of 2+ tagged on the RECORD stat (design "Pre Match"
## 37a, 2026-10-25): the stat gets a third field, `W3` / `L2`.
static func with_streak(stats: Array, kind: String, n: int) -> Array:
	if n < 2:
		return stats
	for st in stats:
		if str(st[1]) == "RECORD":
			(st as Array).push_back("%s%d" % [kind, n])
	return stats


## A league card's three stats from a standings row: RECORD · SEED · AVG PTS.
static func league_stats(row: Dictionary) -> Array:
	var w := int(row.get("w", 0))
	var l := int(row.get("l", 0))
	var seed := int(row.get("seed", 0))
	var avg := "-"
	if w + l > 0:
		avg = str(roundi(float(row.get("pointsFor", 0)) / float(w + l)))
	return [["%d-%d" % [w, l], "RECORD"], ["#%d" % seed if seed > 0 else "-", "SEED"], [avg, "AVG PTS"]]


## The READY button by state: {top, sub, mark, gold}. `pick` (orange: READY · n OF 3
## CARDS SET · >), `ready` (gold: WAITING FOR NAME · TAP TO
## UNLOCK), `count` (STARTING IN n, no sub-line), `go` (TIP-OFF, no sub-line).
static func ready_button(state: String, n: int, opp_name: String, left: int) -> Dictionary:
	match state:
		# Both ready (design 37a, 2026-10-26): the count stands alone, no sub-line.
		"go": return {"top": "TIP-OFF", "sub": "", "mark": "", "gold": true}
		"count": return {"top": "STARTING IN %d" % left, "sub": "", "mark": "", "gold": true}
		"ready": return {"top": "READY", "sub": "WAITING FOR %s · TAP TO UNLOCK" % opp_name.split(" #")[0], "mark": "", "gold": true}
	return {"top": "READY", "sub": "%d OF %d CARDS SET" % [n, CardDefs.SLOTS], "mark": ">", "gold": false}


# ---- the post-match payout (docs/BACKEND.md → Ranked → Stage B) ----------------------------

## Card ids → `DEEP FREEZE, HEAT CHECK`.
static func card_names(ids: Array) -> String:
	var out := []
	for id in ids:
		var c := CardDefs.get_card(str(id))
		out.push_back(str(c.get("name", id)).to_upper())
	return ", ".join(out)


## The right-hand panel of the rewards row: what the decision did with cards.
## {caption, card (id or ""), lost: bool} — the first that applies: a card
## the server granted (the meter, the streak Ice), the spoils you took, what
## you lost (and what insurance kept), the cap, a close one; {} for nothing.
static func spoils_panel(settle: Dictionary) -> Dictionary:
	if not bool(settle.get("ranked", false)):
		return {}
	var granted: Array = settle.get("granted", []) if settle.get("granted") is Array else []
	for g in granted:
		var gd: Dictionary = g if g is Dictionary else {}
		var why := str(gd.get("why", ""))
		var cap := "TOUGH STRETCH · HERE'S AN ICE" if why == "loss_streak" else "METER FULL · NEW CARD"
		return {"caption": cap, "card": str(gd.get("card", "")), "lost": false}
	var sp: Dictionary = settle.get("spoils", {}) if settle.get("spoils") is Dictionary else {}
	var captured: Array = sp.get("captured", []) if sp.get("captured") is Array else []
	var lost: Array = sp.get("lost", []) if sp.get("lost") is Array else []
	var insured := str(sp.get("insured", "")) if sp.get("insured") != null else ""
	if not captured.is_empty():
		return {"caption": "SPOILS · " + card_names(captured), "card": str(captured[0]), "lost": false}
	if not lost.is_empty() or insured != "":
		var cap := ("LOST · " + card_names(lost)) if not lost.is_empty() else "NOTHING LOST"
		if insured != "":
			cap += " · INSURED · %s BACK" % card_names([insured])
		return {"caption": cap, "card": str(lost[0]) if not lost.is_empty() else insured, "lost": not lost.is_empty()}
	if settle.has("pay") and not bool(settle.get("pay", true)):
		return {"caption": "SAME OPPONENT · NO SPOILS TODAY", "card": "", "lost": false}
	return {}


## `METER 14/22 · 70% COMMON · 25% RARE · 5% EPIC`; "" without a meter.
static func meter_line(settle: Dictionary) -> String:
	var m: Dictionary = settle.get("meter", {}) if settle.get("meter") is Dictionary else {}
	if m.is_empty():
		return ""
	var line := "METER %d/%d" % [int(m.get("after", 0)), int(m.get("size", OnlineDrops.meter_size()))]
	var odds := OnlineDrops.odds_text(m.get("odds", {}) if m.get("odds") is Dictionary else {})
	if odds != "":
		line += " · " + odds
	return line


## The meter's fill, 0..1.
static func meter_frac(settle: Dictionary) -> float:
	var m: Dictionary = settle.get("meter", {}) if settle.get("meter") is Dictionary else {}
	return clampf(float(m.get("after", 0)) / maxf(float(m.get("size", 1)), 1.0), 0.0, 1.0)


## A loss by two or less, or in overtime: the meter paid nearly a win's worth.
static func close_loss_line(heat: Dictionary) -> String:
	if bool(heat.get("won", false)) or not bool(heat.get("online", false)):
		return ""
	var margin := int(heat.get("player_score", 0)) - int(heat.get("ai_score", 0))
	var close := int(OnlineDrops.meter_cfg().get("close", {}).get("margin", 2))
	if absi(margin) <= close or int(heat.get("ot", 0)) > 0:
		return "CLOSE ONE · THE METER NOTICED"
	return ""


static func shoot_around_title() -> String:
	return "SHOOT AROUND?"


static func shoot_around_sub(bonus: int) -> String:
	return "A TIME TRIAL · +%d TICKETS" % bonus


static func rewards_title() -> String:
	return "REWARDS"


static func meter_head() -> String:
	return "DROP METER"


static func meter_caption() -> String:
	return "A FULL METER DROPS A CARD · RANKED MATCHES FILL IT"


static func pending_head() -> String:
	return "WAITING FOR YOU"


static func nothing_pending() -> String:
	return "NOTHING WAITING · PLAY RANKED, COME BACK TOMORROW"


static func claim_word(claimed: bool) -> String:
	return "CLAIMED" if claimed else "CLAIM"


static func login_line(days: int, next_day: int) -> String:
	var line := "LOGIN DAYS · %d" % days
	if next_day > 0:
		line += " · NEXT CARD AT DAY %d" % next_day
	return line


static func milestones_head() -> String:
	return "MILESTONES"


static func rewards_offline() -> String:
	return "OFFLINE · REWARDS NEED A SIGNAL"


static func strings() -> Array:
	var out := ["QUICK MATCH", "CREATE CODE", "ENTER CODE", "GO", "CANCEL", "BACK", "<", ">", title(), code_sub(), join_sub(), code_caption(),
		you_badge({}), you_record_line({}), you_record_line({"games": 48, "position": 18, "wins": 32, "losses": 16}),
		progress_line({"have": 16, "need": 50, "next_tier": "mvp", "next_division": 1}), leaderboard_head(), leaderboard_sub(), all_ranks(),
		leaderboard_loading(), leaderboard_empty(), leaderboard_offline(),
		code_line("ABCDE"), waiting_big("quick"), waiting_big("code"), waiting_line("quick"), waiting_line("code"), found_big(),
		found_line(), you_label(), opp_label(), vs_word(), "?", "...", card_tag({"tag": "07"}),
		card_place({"town": "SALT HARBOR", "level": 9}), card_place({"level": 7}), card_online({}),
		card_online({"rank": {"tier": "pro", "division": 2, "wins": 12, "losses": 9, "games": 21}}),
		card_online({"rank": {"tier": "legend", "division": 1, "position": 12, "wins": 40, "losses": 11, "games": 51}}),
		waiting_big("ranked"), waiting_line("ranked"), ranked_sub(), ranked_title(), "RANKED", prematch_title(), cap_line(3), cap_line(3, true), ready_word(true), ready_word(false),
		timer_line(12.4), ranked_chip(), rank_delta_line({"ranked": true, "rating": {"delta": 18}, "rank": {"tier": "pro", "division": 2}, "events": ["promoted"]}),
		rank_delta_line({"ranked": true, "rating": {"delta": -7}, "rank": {"tier": "rookie", "division": 3}, "events": ["shielded", "floored", "demoted"]}),
		rank_delta_line({"ranked": true}),
		court_note(1), court_note(3), loadout_line(2), spares_caption(true), spares_caption(false), slot_empty(2), "LOADOUT", "YOUR CARDS", "COURT",
		header({"location": "beach"}), header({"location": "city", "reason": "forfeit"}), header({"location": "cage", "reason": "void"}),
		prematch_tab_opp(), prematch_tab_you(), their_loadout().replace("\n", " "), your_loadout().replace("\n", " "), load_count(2), your_cards_hint(), opp_status(true), opp_status(false), "×2",
		starts_in(), go_word(), arm_word(), thousands(1480), "RANK", "RATING", "RECORD", "SEED", "AVG PTS", "NEW", "#142",
		ready_button("pick", 2, "JUNIE SAP", 0)["sub"], ready_button("ready", 2, "JUNIE SAP #4471", 0)["sub"], ready_button("count", 3, "X", 7)["top"],
		ready_button("count", 3, "X", 7)["sub"], ready_button("go", 3, "X", 0)["top"], ready_button("go", 3, "X", 0)["sub"],
		spoils_panel({"ranked": true, "granted": [{"why": "meter", "card": "ice"}]})["caption"],
		spoils_panel({"ranked": true, "granted": [{"why": "loss_streak", "card": "ice"}]})["caption"],
		spoils_panel({"ranked": true, "spoils": {"captured": ["ice", "fire7"], "lost": [], "insured": null}})["caption"],
		spoils_panel({"ranked": true, "spoils": {"captured": [], "lost": ["fire7"], "insured": "ice"}})["caption"],
		spoils_panel({"ranked": true, "spoils": {"captured": [], "lost": [], "insured": "ice"}})["caption"],
		spoils_panel({"ranked": true, "pay": false})["caption"],
		meter_line({"meter": {"after": 14, "size": 22, "odds": {"common": 0.7, "rare": 0.25, "epic": 0.05}}}),
		close_loss_line({"online": true, "won": false, "player_score": 20, "ai_score": 22}),
		shoot_around_title(), shoot_around_sub(5), rewards_title(), meter_head(), meter_caption(),
		pending_head(), nothing_pending(), claim_word(true), claim_word(false), login_line(7, 10), login_line(30, 0), milestones_head(), rewards_offline()]
	out.append_array(MilestoneCopy.strings())
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
