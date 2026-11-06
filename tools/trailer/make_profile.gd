extends RefCounted
## The trailer's save (docs/TRAILER.md → The profile): a believable mid-game
## player, written into the redirected save folder and nowhere else.
##   Godot --path . -- --qa-trailer-profile --save-dir=trailer_save --no-net
## Level 6 with every court open, tickets, a dozen balls and five nets, the
## park and the city on chain, a cage season under way, cards in hand, a
## ranked tier, a few time-trial runs. The name and hometown are Ross's
## (BILLY BONGO of EUGENE, picked at Checkpoint A); league opponents are the
## game's shooters; board rows come from tools/trailer/fixtures.

const NAME := "BILLY BONGO"   # Ross's pick, 2026-11-06 (GO BLAZERS read as the NBA team)
const TAG := "58"
const TOWN := "EUGENE"
const LEVEL := 6
const TICKETS := 2480
const BALLS_PER_RARITY := {"common": 5, "rare": 4, "epic": 2, "legend": 1}
const WORN_BALL := "galaxy"
const NETS := ["rasta", "rwb", "wool"]
const AREA_NETS := {"cage": "cotton", "beach": "cotton", "park": "chain", "city": "chain"}
const RANK := {"tier": "pro", "division": 2, "games": 48, "position": 212, "wins": 31, "losses": 17, "cons": 1284.0}
## The cage season so far: nine games, seven won.
const SEASON := [true, true, false, true, true, true, false, true, true]


## Build it. Refuses the real save folder: this wipes what it writes into.
static func build() -> bool:
	if SaveService.save_dir == SaveService.SAVE_DIR:
		print("TRAILER profile: refusing to write the real save (run with --save-dir=trailer_save)")
		return false
	SaveService.wipe_all()
	Net.enabled = false
	App.create_player(NAME, TAG, TOWN, false)
	App.pending_walkthrough = ""
	App.pending_welcome = {}
	# Level and courts.
	var pr: Dictionary = SaveService.get_progress()
	pr["xp"] = (LEVEL - Progression.start_level()) * Progression.xp_per_level() + 40
	SaveService.put_progress(pr)
	# The wallet and the collection.
	App.grant_tickets(TICKETS)
	var left := BALLS_PER_RARITY.duplicate()
	App.grant_cosmetic("ball", WORN_BALL)
	for b in CosmeticLibrary.balls():
		if int(left.get(b.rarity, 0)) > 0 and not App.owns("ball", b.id):
			App.grant_cosmetic("ball", b.id)
			left[b.rarity] = int(left[b.rarity]) - 1
	for n in NETS:
		App.grant_cosmetic("net", n)
	App.select("ball", WORN_BALL)
	for area in AREA_NETS:
		App.select_net(area, str(AREA_NETS[area]))
	App.mark_prizes_seen()
	# A cage season under way, and cards to play.
	var cfg := LeagueData.league("cage")
	var doc := Campaign.new_doc(cfg, 20261106, 1000)
	for won in SEASON:
		Campaign.apply_live_result(doc, cfg, _result(won), 2000)
	App.save_league_doc(doc, "cage")
	for area in ["cage", "beach", "park", "city"]:
		App.enter_league(area)
		for id in ["ice", "fire7", "magnet6", "shield5"]:
			App.add_card(id, 2, area)
	App.add_card("ice", 1, Net.ONLINE_BUCKET)
	App.add_card("fire7", 1, Net.ONLINE_BUCKET)
	# Ranked, and a few runs on every court's board.
	Net.set_me_rank(RANK)
	for area in ["cage", "beach", "park", "city"]:
		for score in [23, 27, 31]:
			SaveService.put_score({"score": score, "makes": score - 9, "attempts": score, "swishes": 6, "bestStreak": 6, "bonus": 5, "iced": 0, "location": area})
	# Nothing left to greet a new player with.
	var st: Dictionary = SaveService.get_settings()
	st["walkthroughsSeen"] = ["home", "league", "peggy"]
	st["shotTutorialSeen"] = true
	st["firstPlayDone"] = true
	st["visitedAreas"] = ["cage", "beach", "park", "city"]
	st["unlocksSeen"] = ["beach", "park", "city"]
	st["musicOn"] = false
	SaveService.put_settings(st)
	print("TRAILER profile: %s #%s of %s, level %d, %d tickets, %d balls, %d nets, cage %s" % [NAME, TAG, TOWN, App.level(), App.tickets(),
		App.owned_count("ball"), App.owned_count("net"), str(doc["career"]["totals"])])
	return App.level() >= 5


static func _result(won: bool) -> Dictionary:
	var hi := {"score": 34, "makes": 21, "swishes": 7, "attempts": 29, "bestStreak": 8, "bonus": 6, "iced": 0}
	var lo := {"score": 27, "makes": 17, "swishes": 4, "attempts": 28, "bestStreak": 5, "bonus": 3, "iced": 0}
	return {"won": won, "player_score": 34 if won else 27, "ai_score": 27 if won else 34, "ot": 0,
		"sides": {"player": hi if won else lo, "ai": lo if won else hi}}
