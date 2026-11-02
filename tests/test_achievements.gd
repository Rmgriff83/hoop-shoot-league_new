extends RefCounted
## Achievements (docs/ACHIEVEMENTS.md): the roster, the rules, the backfill,
## and the autoload over a FakePlatformBackend — the cache, the pending
## queue, the sign-in flush, the remote merge, the server-fed ranks.


## (No `await` anywhere: the runner is synchronous, so a suspended test
## would leak its fake backend into the files after it.)
func run(t) -> void:
	_defs(t)
	_rules(t)
	_backfill(t)
	_autoload(t)


func _defs(t) -> void:
	t.eq(Array(AchievementDefs.validate()), [], "the roster validates")
	t.eq(AchievementDefs.keys().size(), 40, "forty achievements")
	t.eq(AchievementDefs.total_points(), 815, "815 points in all")
	var hidden := []
	for a in AchievementDefs.all():
		if bool(a["hidden"]):
			hidden.push_back(str(a["key"]))
	t.eq(hidden, ["perfect_run", "number_one", "big_steal", "cold_shoulder"], "four hidden")
	t.eq(AchievementDefs.categories().size(), 6, "six categories")
	t.eq(AchievementDefs.apple_id("nothing_but_net"), "hs.ach.nothing_but_net", "apple id = hs.ach.<key>")
	t.eq(AchievementDefs.key_for_apple_id("hs.ach.tier_mvp"), "tier_mvp", "…and back")
	t.eq(AchievementDefs.key_for_apple_id("hs.ach.nope"), "", "an unknown id → ''")
	t.eq(AchievementDefs.get_def("sharpshooter_2").get("unlock"), "Score 30 in a time trial", "the Sharpshooter text names its number")
	t.eq(AchievementDefs.points("tier_legend"), 60, "points")
	var missing := []
	for k in AchievementDefs.keys():
		if not FileAccess.file_exists("res://art/achievements/%s.png" % k):
			missing.push_back(k)
	t.eq(missing, [], "every achievement has its icon in art/achievements")
	t.eq(AchievementDefs.for_milestones(["first_login", "first_ranked_win", "tier_rookie", "tier_pro", "ranked_wins_50", "first_capture", "first_capture"]),
		["debut_dub", "tier_pro", "ranked_wins_50", "spoils"], "milestones → achievements, the unmirrored dropped, once each")


func _rules(t) -> void:
	# Streaks.
	var tr := AchievementRules.StreakTracker.new()
	var got := []
	for i in 9:
		got.append_array(tr.note(true, false))
	t.eq(got, [], "nine makes: nothing yet")
	t.eq(tr.note(true, false), ["heating_up"], "the tenth make → Heating Up")
	got = []
	for i in 14:
		got.append_array(tr.note(true, false))
	t.eq(got, [], "…then quiet to 24")
	t.eq(tr.note(true, false), ["on_fire"], "the 25th → On Fire")
	t.eq(tr.note(false, false), [], "a miss")
	t.eq(tr.makes, 0, "…resets the make streak")
	t.eq(tr.note(true, true), ["nothing_but_net"], "a swish → Nothing But Net (the autoload keeps it to once)")
	for i in 3:
		tr.note(true, true)
	t.eq(tr.note(true, true), ["nothing_but_net", "pure"], "five swishes in a row → Pure")
	tr.note(true, false)
	t.eq(tr.swishes, 0, "a plain make resets the swish streak, not the make streak")
	t.eq(tr.makes, 6, "…")
	# Runs.
	t.eq(AchievementRules.for_run({"score": 12, "makes": 6, "attempts": 9}), ["on_the_clock"], "a run: On the Clock")
	t.eq(AchievementRules.for_run({"score": 20, "makes": 10, "attempts": 12}), ["on_the_clock", "sharpshooter_1"], "20 → Sharpshooter I")
	t.eq(AchievementRules.for_run({"score": 44, "makes": 20, "attempts": 20}), ["on_the_clock", "sharpshooter_1", "sharpshooter_2", "sharpshooter_3", "perfect_run"], "44 and no misses → all three and Perfect Run")
	t.eq(AchievementRules.for_run({"score": 3, "makes": 2, "attempts": 2}), ["on_the_clock"], "two for two is not a Perfect Run")
	# Levels.
	t.eq(AchievementRules.for_level(1), [], "level 1: nothing")
	t.eq(AchievementRules.for_level(3), ["beach_bound"], "level 3: the beach")
	t.eq(AchievementRules.for_level(5), ["beach_bound", "park_regular", "city_lights"], "level 5: every area")
	t.eq(AchievementRules.for_level(7), ["beach_bound", "park_regular", "city_lights", "hall_of_famer"], "level 7: the Hall")
	# League heats.
	t.eq(AchievementRules.for_league_heat({"won": false, "ot": 1, "trailing_at_half": true, "level_after": 2}), [], "a loss earns nothing")
	t.eq(AchievementRules.for_league_heat({"won": true, "ot": 0, "level_after": 2}), ["opening_night"], "a win: Opening Night")
	t.eq(AchievementRules.for_league_heat({"won": true, "ot": 1, "trailing_at_half": true, "level_after": 2}), ["opening_night", "bonus_basketball", "never_out_of_it"], "in OT after trailing at the half")
	t.eq(AchievementRules.for_league_heat({"won": true, "title": true, "league_id": "park", "difficulty": "normal", "level_after": 4}), ["opening_night", "park_champion", "beach_bound", "park_regular"], "a title: the league's Champion")
	t.eq(AchievementRules.for_league_heat({"won": true, "title": true, "league_id": "cage", "difficulty": "hard", "level_after": 7}), ["opening_night", "cage_champion", "hard_way", "beach_bound", "park_regular", "city_lights", "hall_of_famer"], "…on HARD the Hard Way, and the level's areas")
	# Cards, prizes, settles, ranks.
	t.eq(AchievementRules.for_card("fire", 5), ["ace_up_the_sleeve"], "a card: Ace Up the Sleeve")
	t.eq(AchievementRules.for_card("ice", 2), ["ace_up_the_sleeve"], "ice on a short streak: just the Ace")
	t.eq(AchievementRules.for_card("ice", 3), ["ace_up_the_sleeve", "cold_shoulder"], "ice on a 3 streak → Cold Shoulder")
	t.eq(AchievementRules.for_prize({"id": "", "rarity": "common", "refund": 2}), [], "a refund is no prize")
	t.eq(AchievementRules.for_prize({"id": "ball_x", "rarity": "rare"}), ["drop_it"], "a prize → Drop It")
	t.eq(AchievementRules.for_prize({"id": "ball_x", "rarity": "epic"}), ["drop_it", "jackpot"], "an epic → Jackpot")
	t.eq(AchievementRules.for_prize({"id": "ball_x", "rarity": "legend"}), ["drop_it", "golden_drop"], "a legend → Golden Drop")
	t.eq(AchievementRules.for_settle({"won": true}, "ranked"), [], "a ranked win: nothing here (the milestones come through Platform)")
	t.eq(AchievementRules.for_settle({"won": true}, "rematch"), ["run_it_back"], "a rematch won → Run It Back")
	t.eq(AchievementRules.for_settle({"won": false, "spoils": {"captured": ["fire3"]}}, "rematch"), [], "a lost rematch: nothing")
	t.eq(AchievementRules.for_settle({"won": true, "spoils": {"captured": ["fire3", "magnet6"]}}, "quick"), ["big_steal"], "the magnet captured → Big Steal")
	t.eq(AchievementRules.for_week_rank(0), [], "unranked")
	t.eq(AchievementRules.for_week_rank(101), [], "101st: nothing")
	t.eq(AchievementRules.for_week_rank(100), ["board_member"], "100th → Board Member")
	t.eq(AchievementRules.for_week_rank(1), ["board_member", "number_one"], "1st → Number One too")


func _backfill(t) -> void:
	t.eq(AchievementRules.backfill({}), [], "an empty device earns nothing")
	var state := {
		"level": 4,
		"leagues": [{"id": "cage", "championships": 2, "wins": 9, "best_streak": 11}, {"id": "beach", "championships": 0, "wins": 0, "best_streak": 3}],
		"runs": [{"score": 31, "makes": 14, "attempts": 15, "bestStreak": 9, "swishes": 4}, {"score": 18, "makes": 10, "attempts": 10, "bestStreak": 10, "swishes": 0}],
		"prizes": ["common", "legend"],
		"milestones": ["first_login", "first_ranked_win", "tier_starter"],
	}
	t.eq(AchievementRules.backfill(state), ["beach_bound", "park_regular", "cage_champion", "opening_night", "on_the_clock", "nothing_but_net", "perfect_run", "sharpshooter_1", "sharpshooter_2", "heating_up", "drop_it", "golden_drop", "debut_dub", "tier_starter"], "the records' due, once each")


func _autoload(t) -> void:
	var root = Engine.get_main_loop().root
	var ach: Node = root.get_node_or_null("Achievements")
	var plat: Node = root.get_node_or_null("Platform")
	var net: Node = root.get_node_or_null("Net")
	var save: Node = root.get_node_or_null("SaveService")
	if ach == null or plat == null or net == null or save == null:
		t.ok(false, "Achievements, Platform, Net and SaveService autoloads present")
		return
	var was_account: Dictionary = save.get_account()
	var was_backend = plat.backend
	var acc: Dictionary = save.get_account()
	acc.erase("achievements")
	acc.erase("achievementsPending")
	acc.erase("milestones")
	acc["achievementsBackfilled"] = true
	save.put_account(acc)
	var fake := FakePlatformBackend.new()
	plat.use_backend(fake)
	var heard: Array = []
	var hear := func(k: String) -> void: heard.push_back(k)
	ach.unlocked.connect(hear)

	t.eq(ach.earned(), [], "nothing earned yet")
	t.ok(ach.unlock("pure"), "unlock: earned")
	t.ok(not ach.unlock("pure"), "…once")
	t.ok(not ach.unlock("not_a_thing"), "…and never an unknown key")
	t.eq(heard, ["pure"], "the signal, once")
	t.eq(fake.unlocked, ["hs.ach.pure"], "the backend got the Apple id")
	t.eq(fake.banners, [true], "…with the banner")
	t.ok(ach.has("pure") and ach.count() == 1 and ach.points() == 20, "the cache: held, counted, pointed")
	t.eq(ach.pending(), [], "nothing pending while the platform takes awards")
	# The platform refusing (or absent): the key waits.
	fake.accept_awards = false
	t.ok(ach.unlock("on_fire"), "earned while the platform refuses")
	t.eq(ach.pending(), ["on_fire"], "…parked")
	fake.signed = false
	ach.unlock("jackpot", false)
	t.eq(ach.pending(), ["on_fire", "jackpot"], "…and while signed out")
	t.eq(ach.earned(), ["pure", "on_fire", "jackpot"], "all three held")
	# Sign-in: Apple's list merged, the parked keys sent.
	fake.accept_awards = true
	fake.remote = {"ok": true, "earned": ["hs.ach.drop_it", "hs.ach.pure", "hs.ach.bogus"]}
	fake.sign_in()   # the fake answers load_achievements at once, so this all lands now
	t.ok(fake.load_calls >= 1, "signed in: the earned list is read")
	t.ok(ach.has("drop_it") and not ach.has("bogus"), "…what Apple has is adopted (an unknown id ignored)")
	t.eq(heard, ["pure", "on_fire", "jackpot"], "…adopting is no new unlock")
	t.eq(fake.unlocked, ["hs.ach.pure", "hs.ach.on_fire", "hs.ach.jackpot"], "…the parked keys flushed in order")
	t.eq(fake.banners, [true, true, false], "…each with the banner it was earned with")
	t.eq(ach.pending(), [], "…nothing left parked")
	# Apple missing something we hold → a quiet re-report.
	fake.unlocked.clear()
	fake.banners.clear()
	t.eq(ach.merge_remote(["hs.ach.pure"]), [], "merge: nothing new from Apple")
	t.eq(ach.pending(), ["on_fire", "jackpot", "drop_it"], "…the keys Apple lacks parked again")
	ach.flush_pending()
	t.eq(fake.banners, [false, false, false], "…and sent without banners")
	t.eq(ach.pending(), [], "…")
	# A failed award comes back to the queue.
	plat.achievement_failed.emit("hs.ach.jackpot")
	t.eq(ach.pending(), ["jackpot"], "an award the platform refused later is parked")
	ach.flush_pending()
	# Server milestones through Platform.
	fake.unlocked.clear()
	plat.note_milestones(["first_login", "first_capture", "tier_legend"])
	t.eq(fake.unlocked, ["hs.ach.spoils", "hs.ach.tier_legend"], "milestones with an achievement reach the backend")
	# The weekly board ranks through Net.
	net.score_accepted.emit("cage", {"accepted": true, "weekRank": 57})
	t.ok(ach.has("board_member") and not ach.has("number_one"), "a score reply's weekRank → Board Member")
	net.board_loaded.emit("beach", "all", {"me": {"rank": 1}})
	t.ok(not ach.has("number_one"), "an all-time board rank is not the weekly one")
	net.board_loaded.emit("beach", "week", {"me": {"rank": 1}})
	t.ok(ach.has("number_one"), "a weekly board's #1 → Number One")
	net.score_accepted.emit("cage", {"accepted": true, "weekRank": null})
	# The moments.
	ach.reset_streaks()
	t.eq(ach.note_shot(true, false, false), [], "a practice make: nothing")
	t.eq(ach.note_shot(true, true, false), ["nothing_but_net"], "a practice swish → Nothing But Net (Ross, 2026-11-02)")
	for i in 5:
		t.eq(ach.note_shot(true, true, false), [], "…more practice swishes: no Pure")
	t.eq(ach.tracker.swishes, 0, "…the streaks untouched by practice")
	t.eq(ach.note_shot(true, true), [], "a timed swish counts toward the streaks")
	t.eq(ach.tracker.swishes, 1, "…")
	t.eq(ach.note_run({"score": 40, "makes": 10, "attempts": 10}), ["on_the_clock", "sharpshooter_1", "sharpshooter_2", "sharpshooter_3", "perfect_run"], "a run noted: the new keys")
	t.eq(ach.note_card("ice", 4), ["ace_up_the_sleeve", "cold_shoulder"], "a card noted")
	t.eq(ach.note_prize({"id": "b", "rarity": "legend"}), ["golden_drop"], "a prize noted (Drop It already held)")
	t.eq(ach.note_settle({"won": true, "spoils": {"captured": ["magnet6"]}}, "rematch"), ["run_it_back", "big_steal"], "a settle noted")
	t.eq(ach.note_league_heat({"won": true, "ot": 2, "title": true, "league_id": "city", "difficulty": "hard", "level_after": 7}),
		["opening_night", "bonus_basketball", "city_champion", "hard_way", "beach_bound", "park_regular", "city_lights", "hall_of_famer"], "a heat noted")
	# The backfill runs once (again on demand), quietly.
	var acc2: Dictionary = save.get_account()
	acc2.erase("achievementsBackfilled")
	acc2["achievements"] = []
	acc2["achievementsPending"] = []
	save.put_account(acc2)
	fake.unlocked.clear()
	fake.banners.clear()
	var st: Dictionary = ach.backfill_state()
	t.ok(st.has("level") and st.has("leagues") and st.has("runs") and st.has("prizes") and st.has("milestones"), "the backfill state has every part")
	t.eq(st["milestones"], ["first_login", "first_capture", "tier_legend"], "…the milestone cache among them")
	var fresh: Array = ach.backfill()
	t.ok(fresh.has("spoils") and fresh.has("tier_legend"), "the backfill grants the records' due")
	t.ok(not fake.banners.has(true), "…without banners")
	t.eq(ach.backfill(), [], "…and not again")
	t.ok(ach.can_show() and ach.show_sheet() and fake.sheet_shown == 1, "the sheet opens on the signed-in fake")
	fake.signed = false
	t.ok(not ach.can_show() and not ach.show_sheet(), "…not signed out")

	ach.unlocked.disconnect(hear)
	plat.use_backend(was_backend)
	save.put_account(was_account)
