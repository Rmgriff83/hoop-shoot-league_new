extends RefCounted
## The level system (docs/PROGRESSION.md): the level math, a match's XP
## through every term of the formula, the season soft cap, the league cap,
## the title jump, the season key reset, the card / league / area gates,
## the shipped data holding together, and the pacing envelope: every
## archetype season inside its band.


func _result(won: bool, swishes := 0, streak := 0, you := 30, them := 25, ot := 0, playoff := false) -> Dictionary:
	return {"won": won, "player_score": you, "ai_score": them, "ot": ot, "league": {"playoff": playoff},
		"sides": {"player": {"swishes": swishes, "bestStreak": streak}, "ai": {}}}


func run(t) -> void:
	_levels(t)
	_match(t)
	_season(t)
	_gates(t)
	_data(t)
	_envelope(t)


func _levels(t) -> void:
	t.eq(Progression.xp_per_level(), 100, "a level is 100 XP")
	t.eq(Progression.level_for(0), 1, "level 1 at the start")
	t.eq(Progression.level_for(99), 1, "still 1 at 99")
	t.eq(Progression.level_for(100), 2, "2 at 100")
	t.eq(Progression.level_for(250), 3, "3 at 250")
	t.close(Progression.frac_for(64), 0.64, 1e-9, "progress inside the level")
	t.eq(Progression.xp_in_level(164), [64, 100], "64/100 at 164")
	var cage := LeagueData.league("cage")
	var beach := LeagueData.league("beach")
	t.eq(Progression.cap_level(cage), 3, "the cage caps at 3")
	t.eq(Progression.cap_xp(cage), 200, "= 200 XP")
	t.eq(Progression.min_level(beach), 3, "the beach starts at 3")
	t.eq(Progression.cap_xp(beach), 400, "and caps at 5 = 400 XP")
	var city := LeagueData.league("city")
	t.eq(Progression.min_level(city), 5, "the city starts at 5")
	t.eq(Progression.cap_xp(city), 600, "and caps at 7 = 600 XP")
	t.eq(Progression.area_level("city"), 5, "the city area opens at level 5")
	t.ok(not Progression.area_unlocked(4, "city") and Progression.area_unlocked(5, "city"), "city gate at 5")
	t.ok(Progression.at_cap(200, cage) and not Progression.at_cap(199, cage), "at the cap at 200")


func _match(t) -> void:
	var cage := LeagueData.league("cage")
	t.close(Progression.match_raw(_result(true), cage, false), 9.0, 1e-9, "a plain win")
	t.close(Progression.match_raw(_result(false), cage, false), 2.0, 1e-9, "a plain loss")
	t.close(Progression.match_raw(_result(true, 5), cage, false), 11.0, 1e-9, "0.4 a swish")
	t.close(Progression.match_raw(_result(true, 0, 5), cage, false), 11.0, 1e-9, "a 5 streak is +2")
	t.close(Progression.match_raw(_result(true, 0, 8), cage, false), 13.0, 1e-9, "an 8 streak is +4")
	t.close(Progression.match_raw(_result(true, 0, 0, 40, 28), cage, false), 11.0, 1e-9, "a wide win is +2")
	t.close(Progression.match_raw(_result(false, 0, 0, 20, 35), cage, false), 2.0, 1e-9, "a wide loss is not")
	t.close(Progression.match_raw(_result(true, 0, 0, 30, 28, 1), cage, false), 10.0, 1e-9, "an OT win is +1")
	t.close(Progression.match_raw(_result(true), cage, true), 13.5, 1e-9, "a playoff game is x1.5")
	var pay := Progression.match_xp(_result(true, 5, 8, 42, 30, 1), cage, 0, false)
	t.eq(pay, {"raw": 18, "gained": 18}, "the lot: 9 + 2 + 4 + 2 + 1")
	# The season soft cap: past 100 in a season, XP counts at a quarter.
	t.eq(Progression.match_xp(_result(true), cage, 100, false)["gained"], 2, "over the cap a win pays 2")
	t.eq(Progression.match_xp(_result(true, 5), cage, 95, false)["gained"], 7, "straddling it: 5 whole + 6 x 0.25, rounded")


func _season(t) -> void:
	var cage := LeagueData.league("cage")
	var st := Progression.empty_state()
	var info := Progression.apply_match(st, _result(true, 4, 5), cage, 1)
	t.eq(info, {"gained": 13, "level_before": 1, "level_after": 1, "capped": false}, "the first match")
	t.eq(int(st["xp"]), 13, "XP banked")
	t.eq(str(st["seasonKey"]), "cage:1", "the season keyed")
	t.eq(int(st["seasonXp"]), 13, "and counted")
	for i in 7:
		Progression.apply_match(st, _result(true, 6, 8, 40, 28), cage, 1)
	t.ok(int(st["xp"]) > 100, "eight good games pass a level (%d)" % int(st["xp"]))
	t.eq(Progression.level_for(int(st["xp"])), 2, "level 2")
	# A new season resets the soft cap's count.
	Progression.apply_match(st, _result(true), cage, 2)
	t.eq(str(st["seasonKey"]), "cage:2", "season 2 keyed")
	t.eq(int(st["seasonXp"]), 9, "its count restarted")
	# The league cap: nothing past 200 from the cage.
	st["xp"] = 195
	st["seasonXp"] = 0
	var capped := Progression.apply_match(st, _result(true, 6, 8), cage, 3)
	t.eq(int(st["xp"]), 200, "capped at 200")
	t.ok(bool(capped["capped"]) and int(capped["gained"]) == 5, "the cap took the rest")
	t.eq(int(capped["level_after"]), 3, "level 3 at the cap")
	t.eq(int(Progression.apply_match(st, _result(true), cage, 3)["gained"]), 0, "nothing more from the cage")
	# The title: straight to the cap from anywhere.
	var fresh := Progression.empty_state()
	fresh["xp"] = 40
	var jump := Progression.apply_title(fresh, cage)
	t.eq(int(fresh["xp"]), 200, "the title jumps to the cap")
	t.eq(jump, {"gained": 160, "level_before": 1, "level_after": 3, "capped": false}, "and says so")
	Progression.apply_title(fresh, cage)
	t.eq(int(fresh["xp"]), 200, "a second title changes nothing")
	# The beach's band continues from 3.
	var beach := LeagueData.league("beach")
	fresh["seasonKey"] = ""
	for i in 60:
		Progression.apply_match(fresh, _result(true, 6, 8, 40, 28), beach, 1)
	t.eq(int(fresh["xp"]), 400, "the beach caps at 400")
	t.eq(Progression.level_for(int(fresh["xp"])), 5, "level 5")


func _gates(t) -> void:
	var ice := CardDefs.get_card("ice")
	var fire := CardDefs.get_card("fire7")
	t.ok(Progression.can_use(1, ice), "Deep Freeze from level 1")
	t.ok(not Progression.can_use(2, fire) and Progression.can_use(3, fire), "Heat Check from level 3")
	t.eq(Progression.next_card(1)["id"], "fire7", "the next card up from level 1")
	t.eq(Progression.next_card(3)["id"], "vortex6", "the next card up from level 3 is the Vortex")
	t.ok(not Progression.can_use(4, CardDefs.get_card("vortex6")) and Progression.can_use(5, CardDefs.get_card("vortex6")), "Vortex from level 5")
	t.eq(Progression.next_card(5), {}, "nothing above level 5 yet")
	t.eq(Progression.area_level("cage"), 1, "the cage is open")
	t.eq(Progression.area_level("beach"), 3, "the beach needs level 3")
	t.ok(not Progression.area_unlocked(2, "beach") and Progression.area_unlocked(3, "beach"), "the whole beach area follows")
	t.ok(Progression.area_unlocked(1, "nowhere"), "an unknown area is open")


func _data(t) -> void:
	t.eq(Progression.validate(), PackedStringArray(), "the shipped bands, unlocks and card levels hold together")
	t.eq(LeagueData.validate(), PackedStringArray(), "the league data validates with its bands")
	t.eq(CardDefs.validate(), PackedStringArray(), "the card data validates with its levels")


func _envelope(t) -> void:
	var cage := LeagueData.league("cage")
	var rows := ProgressionBudget.seasons(cage)
	t.eq(rows.size(), 4, "four archetype seasons")
	var by := {}
	for r in rows:
		by[r["id"]] = r
		t.ok(bool(r["ok"]), "%s season pays %.2f levels, inside %s" % [r["id"], r["levels"], str(r["band"])])
	t.ok(float(by["terrible"]["levels"]) < float(by["awful"]["levels"]) and float(by["awful"]["levels"]) < float(by["decent"]["levels"]) and float(by["decent"]["levels"]) < float(by["strong"]["levels"]), "the seasons order")
	t.ok(float(by["decent"]["levels"]) >= 0.95 and float(by["decent"]["levels"]) <= 1.1, "a decent season is about a level (%.2f)" % by["decent"]["levels"])
	t.eq(ProgressionBudget.problems(), PackedStringArray(), "the progression is inside its envelope")
