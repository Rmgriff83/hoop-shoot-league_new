extends RefCounted
## Ranked Stage B's mirror (core/online/online_drops.gd): the derivation and
## the odds agree with the server to the number
## (tests/fixtures/online_drops_cases.json, shared with server/test/drops.test.ts),
## the pool follows the level and the card's minimum tier, the words.


func run(t) -> void:
	var fx: Variant = JSON.parse_string(FileAccess.open("res://tests/fixtures/online_drops_cases.json", FileAccess.READ).get_as_text())
	t.ok(fx is Dictionary, "the shared fixture loads")
	var d := OnlineDrops.derive()
	var fd: Dictionary = fx["derive"]
	for k in ["points_per_match", "first_win_days", "points_per_week", "streak_cards_per_week", "cards_in_per_match", "ratio"]:
		t.close(float(d[k]), float(fd[k]), 1e-3, "derive %s agrees with the server" % k)
	t.eq(int(d["meter_size"]), int(fd["meter_size"]), "the meter size agrees")
	t.eq(OnlineDrops.meter_size(), int(fd["meter_size"]), "meter_size() is the derived one")
	var band: Array = OnlineDrops.doc().get("ratio_band", [0.2, 0.5])
	t.ok(float(d["ratio"]) >= float(band[0]) and float(d["ratio"]) <= float(band[1]), "cards in / played sits in the band (%.3f)" % d["ratio"])
	for c in fx["odds"]:
		var o := OnlineDrops.odds_for(str(c["tier"]), int(c["level"]))
		for r in ["common", "rare", "epic"]:
			t.close(float(o[r]), float(c[r]), 1e-3, "%s L%d %s odds agree" % [c["tier"], c["level"], r])
	t.eq(OnlineDrops.eligible_cards("rookie", 5), ["fire7", "ice"], "a rookie at level 5: the magnet waits a tier")
	t.eq(OnlineDrops.eligible_cards("starter", 5), ["fire7", "ice", "magnet6"], "a starter at level 5 may be dealt the magnet")
	t.eq(OnlineDrops.eligible_cards("legend", 1), ["ice"], "level 1: the ice alone")
	t.eq(OnlineDrops.odds_text({"common": 0.7, "rare": 0.25, "epic": 0.05}), "70% COMMON · 25% RARE · 5% EPIC", "the odds line")
	t.eq(OnlineDrops.odds_text({"common": 1.0, "rare": 0.0, "epic": 0.0}), "100% COMMON", "a rarity at zero is left out")
	t.eq(OnlineDrops.next_login_card(0), 1, "the first schedule day")
	t.eq(OnlineDrops.next_login_card(3), 7, "after day 3, day 7")
	t.eq(OnlineDrops.next_login_card(30), 0, "the schedule spent")
	var keys := OnlineDrops.all_milestone_keys()
	t.ok(keys.has("first_login") and keys.has("ranked_wins_10") and keys.has("tier_legend") and keys.has("division_rookie_3") and not keys.has("division_legend_1"), "the milestone list (%d keys)" % keys.size())
	t.eq(keys.slice(0, 4), ["first_login", "first_ranked_match", "first_ranked_win", "first_capture"], "…in the server's order")
	t.eq(OnlineDrops.card_min_tier("magnet6"), "starter", "the magnet's floor from data")
	t.eq(OnlineDrops.card_min_tier("nope"), "rookie", "an unlisted card: the first tier")
	t.eq(int(OnlineDrops.shoot_around_cfg().get("bonus", 0)), 5, "the shoot-around bonus from data")
	t.eq(MilestoneCopy.name("first_capture"), "FIRST SPOILS", "milestone copy")
	t.eq(MilestoneCopy.name("ranked_wins_50"), "50 RANKED WINS", "win counts")
	t.eq(MilestoneCopy.name("tier_pro"), "PRO REACHED", "a tier")
	t.eq(MilestoneCopy.name("division_allstar_2"), "ALL-STAR II REACHED", "a division")
	t.eq(MilestoneCopy.name("login_day_7"), "LOGIN DAY 7", "a login day")
	t.eq(MilestoneCopy.name("welcome_back_20750"), "WELCOME BACK", "welcome back")
