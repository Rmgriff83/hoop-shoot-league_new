extends RefCounted
## League core: data, schedule, standings + clinches, quick-sim, playoffs,
## season, campaign — ports of league.spec / clinch.spec shrunk to the
## compact 8-team format.


func _g(home: String, away: String, hs: int, as_: int, played := true, day := 1) -> Dictionary:
	var g := ScheduleGen.game_record("t-%s-%s-%d" % [home, away, hs + as_], day, home, away)
	g["homeScore"] = hs
	g["awayScore"] = as_
	g["played"] = played
	return g


func run(t) -> void:
	_data(t)
	_schedule(t)
	_standings(t)
	_clinch(t)
	_quick_sim(t)
	_playoffs(t)
	_season(t)
	_campaign(t)


func _data(t) -> void:
	t.eq(LeagueData.validate(), PackedStringArray(), "league data validates")
	t.eq(LeagueData.shooters().size(), 21, "21 authored shooters")
	t.eq(LeagueData.leagues().size(), 3, "three leagues (cage, beach, city)")
	for l in LeagueData.leagues():
		t.eq(LeagueData.team_ids(l).size(), 8, "%s has 8 teams" % l["id"])
		t.eq(LeagueData.league_ratings(l).size(), 7, "%s has 7 AI ratings" % l["id"])
	t.ok(LeagueData.league("cage")["unlock"] == null, "arcade league is open")
	t.eq(int(LeagueData.league("beach")["unlock"]["level"]), 3, "the beach opens at level 3")
	t.eq(int(LeagueData.league("city")["unlock"]["level"]), 5, "the city opens at level 5")
	t.close(LeagueData.ratings_of("starfall").accuracy, 0.59, 1e-9, "ratings parse (the city star, re-tiered 2026-10-03)")
	for l in LeagueData.leagues():
		t.close(float(l["ball_return_s"]), 1.0, 1e-9, "%s league ball-return wait is 1 s" % l["id"])


func _schedule(t) -> void:
	var ids := LeagueData.team_ids(LeagueData.league("cage"))
	for seed_v in [1, 77, 4242]:
		var games := ScheduleGen.generate(ids, 2, seed_v)
		t.eq(games.size(), 56, "8 teams × 2 rounds = 56 games (seed %d)" % seed_v)
		t.eq(ScheduleGen.season_days(games), 14, "14 days")
		var pairs := {}
		for day in range(1, 15):
			var on := ScheduleGen.games_on(games, day)
			t.eq(on.size(), 4, "day %d has 4 games" % day)
			var seen := {}
			for g in on:
				seen[g["homeId"]] = true
				seen[g["awayId"]] = true
				var key: String = g["homeId"] + "|" + g["awayId"] if g["homeId"] < g["awayId"] else g["awayId"] + "|" + g["homeId"]
				pairs[key] = int(pairs.get(key, 0)) + 1
			t.eq(seen.size(), 8, "everyone plays on day %d" % day)
		t.eq(pairs.size(), 28, "every pair meets")
		for key in pairs:
			t.eq(pairs[key], 2, "pair %s meets twice" % key)
	var a := ScheduleGen.generate(ids, 2, 9)
	var b := ScheduleGen.generate(ids, 2, 9)
	t.eq(a[5]["homeId"], b[5]["homeId"], "schedule is deterministic per seed")
	# Home/away balance: each team hosts 7 of its 14.
	var home_count := {}
	for g in a:
		home_count[g["homeId"]] = int(home_count.get(g["homeId"], 0)) + 1
	for id in ids:
		t.eq(int(home_count.get(id, 0)), 7, "%s hosts 7" % id)


func _standings(t) -> void:
	var ids := ["A", "B", "C", "D"]
	var games := [_g("A", "B", 30, 20), _g("C", "D", 30, 20), _g("A", "C", 25, 20), _g("B", "D", 10, 20)]
	var table := Standings.table(ids, games, 1)
	t.eq(table[0]["teamId"], "A", "A leads at 2-0")
	t.eq(int(table[0]["seed"]), 1, "seed 1")
	t.eq(table[3]["teamId"], "B", "B last at 0-2")
	# C and D both 1-1: head-to-head (C beat D) puts C ahead.
	t.eq(table[1]["teamId"], "C", "h2h breaks the 1-1 tie")
	t.close(Standings.games_behind(table[0], table[3]), 2.0, 1e-9, "games behind")
	t.eq(Standings.current_streak("A", games), {"type": "W", "count": 2}, "A on a 2-game win streak")
	t.eq(Standings.current_streak("Z", games), {}, "no games → no streak")
	# Level on everything → seeded coin flip, symmetric and deterministic.
	var even := [_g("A", "B", 20, 10), _g("B", "A", 20, 10)]
	var t1 := Standings.table(["A", "B"], even, 5)
	var t2 := Standings.table(["B", "A"], even, 5)
	t.eq(t1[0]["teamId"], t2[0]["teamId"], "coin flip independent of input order")


func _clinch(t) -> void:
	var games := [_g("A", "B", 30, 20), _g("A", "B", 30, 20)]
	t.ok(Standings.guaranteed_ahead("A", "B", games), "insurmountable lead")
	t.ok(not Standings.guaranteed_ahead("B", "A", games), "…and not the other way")
	var open_ := [_g("A", "B", 30, 20), _g("A", "B", 30, 20), _g("A", "B", 0, 0, false), _g("B", "C", 0, 0, false)]
	t.ok(not Standings.guaranteed_ahead("A", "B", open_), "equal max wins with a meeting left → not clinched")
	var settled := [_g("A", "B", 30, 20), _g("A", "B", 30, 20), _g("B", "A", 30, 20), _g("B", "C", 0, 0, false)]
	t.ok(Standings.guaranteed_ahead("A", "B", settled), "all meetings played, h2h settled → clinched")
	var split := [_g("A", "B", 30, 20), _g("B", "A", 30, 20), _g("B", "C", 0, 0, false), _g("A", "C", 0, 0, false)]
	t.ok(not Standings.guaranteed_ahead("A", "B", split), "a split h2h is not a settled edge")
	# Dominant team in an 8-team table clinches playoffs + top seed.
	var ids := ["A", "B", "C", "D", "E", "F", "G", "H"]
	var dom := []
	for opp in ["B", "C", "D", "E", "F", "G", "H"]:
		dom.push_back(_g("A", opp, 30, 20))
		dom.push_back(_g(opp, "A", 20, 30))
	var c := Standings.compute_clinches(ids, dom, 4)
	t.eq(c["A"], {"playoffs": true, "topSeed": true, "eliminated": false}, "dominant A clinches everything")
	t.ok(not c["B"]["playoffs"] and not c["B"]["eliminated"], "pack unmarked")
	# Team beaten by five different rivals with nothing left → eliminated.
	var out := []
	for w in ["A", "B", "C", "D", "E"]:
		out.push_back(_g(w, "H", 30, 20))
	var c2 := Standings.compute_clinches(ids, out, 4)
	t.ok(c2["H"]["eliminated"], "H eliminated")
	# Monotone over a real season: once clinched, never retracted.
	var league := LeagueData.league("cage")
	var team_ids := LeagueData.team_ids(league)
	var state := Season.create(league, team_ids, 1, 3)
	var ratings := LeagueData.league_ratings(league)
	var ever := {}
	for day in 14:
		Season.resolve_day(state, ratings, "player", AiRatings.make(0.55, 0.5), {})
		var cl := Standings.compute_clinches(team_ids, state["schedule"], 4)
		for id in team_ids:
			if ever.has(id):
				t.ok(cl[id]["playoffs"], "%s clinch never retracted" % id)
			elif cl[id]["playoffs"]:
				ever[id] = true
			t.ok(not (cl[id]["playoffs"] and cl[id]["eliminated"]), "%s never both" % id)
	var final_cl := Standings.compute_clinches(team_ids, state["schedule"], 4)
	var ins := 0
	var outs := 0
	for id in team_ids:
		if final_cl[id]["playoffs"]:
			ins += 1
		if final_cl[id]["eliminated"]:
			outs += 1
	t.eq(ins, 4, "four in at season's end")
	t.eq(outs, 4, "four out at season's end")


func _quick_sim(t) -> void:
	var a := AiRatings.make(0.6, 0.6, 4.0, 0.5, 0.3, 0.8)
	var b := AiRatings.make(0.6, 0.6, 4.0, 0.5, 0.3, 0.8)
	var r1 := QuickSim.sim_heat(a, b, 11)
	var r2 := QuickSim.sim_heat(a, b, 11)
	t.eq(r1, r2, "deterministic per seed")
	for s in 200:
		var r := QuickSim.sim_heat(a, b, s)
		t.ok(r["home"]["points"] != r["away"]["points"], "never ties (seed %d)" % s) if s < 3 or r["home"]["points"] == r["away"]["points"] else null
	var strong := AiRatings.make(0.78, 0.72, 3.8, 0.85, 0.1, 0.95)
	var weak := AiRatings.make(0.38, 0.15, 3.2, 0.55, 0.3, 0.75)
	var strong_wins := 0
	for s in 200:
		var r := QuickSim.sim_heat(strong, weak, 1000 + s)
		if r["home"]["points"] > r["away"]["points"]:
			strong_wins += 1
	t.ok(strong_wins > 150, "ratings matter (%d/200)" % strong_wins)
	t.eq(QuickSim.shots_for(a, 90.0, 1.0), 37, "90 s at pace 4 with a 1 s return → 37 shots")
	t.eq(QuickSim.shots_for(a, 90.0, 1.5), 31, "… 1.5 s return → 31 shots")
	# Box coherence: points ≥ makes (tiers/swish only add).
	t.ok(int(r1["home"]["points"]) >= int(r1["home"]["makes"]), "points ≥ makes")
	t.ok(int(r1["home"]["swishes"]) <= int(r1["home"]["makes"]), "swishes ≤ makes")
	# A cold shooter gets iced now and then.
	var iced_seen := 0
	for s in 60:
		var r := QuickSim.sim_heat(weak, weak, 5000 + s)
		iced_seen += int(r["home"]["iced"]) + int(r["away"]["iced"])
	t.ok(iced_seen > 0, "cold shooters ice over in quick sims (%d)" % iced_seen)


func _playoffs(t) -> void:
	var table := []
	for id in ["S1", "S2", "S3", "S4"]:
		table.push_back({"teamId": id, "seed": table.size() + 1})
	var series := Playoffs.build_semis(table, 3)
	t.eq(series.size(), 2, "two semis")
	t.eq(series[0]["highSeedId"], "S1", "1v4 high seed")
	t.eq(series[0]["lowSeedId"], "S4", "1v4 low seed")
	t.eq(Playoffs.needed_wins(series[0]), 2, "Bo3 needs 2")
	t.ok(not Playoffs.record_series_game(series[0], 20, 10), "1-0 not over")
	t.ok(Playoffs.record_series_game(series[0], 20, 10), "2-0 over")
	t.eq(series[0]["winnerId"], "S1", "S1 advances")
	t.eq(Playoffs.advance_bracket(series, 5).size(), 0, "no final until both semis decided")
	Playoffs.record_series_game(series[1], 10, 20)
	Playoffs.record_series_game(series[1], 10, 20)
	var created := Playoffs.advance_bracket(series, 5)
	t.eq(created.size(), 1, "final created")
	t.eq(created[0]["highSeedId"], "S1", "1v4 winner is the final's high seed")
	t.eq(created[0]["lowSeedId"], "S3", "2v3 winner (S3) meets them")
	t.eq(int(created[0]["bestOf"]), 5, "final is Bo5")
	t.eq(Playoffs.needed_wins(created[0]), 3, "Bo5 needs 3")


func _season(t) -> void:
	var league := LeagueData.league("cage")
	var team_ids := LeagueData.team_ids(league)
	var ratings := LeagueData.league_ratings(league)
	var state := Season.create(league, team_ids, 1, 42)
	t.eq(Season.days(state), 14, "14-day season")
	t.eq(state["phase"], "regular", "starts regular")
	# The AI roster's per-season card hands are dealt with the season.
	t.ok(state.has("cardHands") and state["cardHands"].size() == 7, "season deals a card hand per roster shooter")
	var dealt := 0
	for sid in state["cardHands"]:
		dealt += state["cardHands"][sid].size()
	t.eq(dealt, int(league["ai_cards_per_season"]), "season hands total the league's allowance")
	t.ok(Season.card_hand(state, "brickport").has("fire7"), "brickport carries its signature fire card")
	t.eq(Season.card_hand(state, "nobody"), [], "unknown shooter → empty hand")
	var before := Season.card_hand(state, "brickport").size()
	Season.consume_cards(state, "brickport", ["fire7"])
	t.eq(Season.card_hand(state, "brickport").size(), before - 1, "a played card leaves the season hand")
	Season.consume_cards(state, "brickport", ["nope"])
	t.eq(Season.card_hand(state, "brickport").size(), before - 1, "consuming ids it does not hold is a no-op")
	var old := Season.create(league, team_ids, 1, 42)
	old.erase("cardHands")
	Season.ensure_card_hands(old, league)
	t.eq(old["cardHands"], Season.create(league, team_ids, 1, 42)["cardHands"], "a pre-hands save is dealt the same hands from its seed")
	Season.ensure_card_hands(old, league)
	t.eq(old["cardHands"], Season.create(league, team_ids, 1, 42)["cardHands"], "ensure is idempotent")
	var self_ := AiRatings.make(0.55, 0.5)
	# Day 1 with a live result for the player.
	var g1 := Season.player_game_on(state, 1, "player")
	t.ok(not g1.is_empty(), "player plays day 1")
	Season.resolve_day(state, ratings, "player", self_, {"playerScore": 30, "oppScore": 12, "playerSwishes": 5, "oppSwishes": 2, "ot": 0})
	t.ok(g1["played"] and g1["playedLive"], "player's game recorded live")
	t.eq(int(g1["homeScore"] if g1["homeId"] == "player" else g1["awayScore"]), 30, "player score stored on the right side")
	t.eq(int(state["currentDay"]), 2, "advanced to day 2")
	for g in Season.games_on(state, 1):
		t.ok(g["played"], "every day-1 game resolved")
	# Sim the rest.
	while state["phase"] == "regular":
		Season.resolve_day(state, ratings, "player", self_, {})
	t.eq(state["phase"], "playoffs", "playoffs after day 14")
	t.eq(state["series"].size(), 2, "two semis")
	var rows := Standings.compute(team_ids, state["schedule"])
	var total_w := 0
	for id in rows:
		total_w += int(rows[id]["w"])
		t.eq(int(rows[id]["w"]) + int(rows[id]["l"]), 14, "%s played 14" % id)
	t.eq(total_w, 56, "56 wins handed out")
	# Playoffs: if the player is in, feed live wins; else AI-only resolves.
	var guard := 0
	while state["phase"] == "playoffs" and guard < 20:
		guard += 1
		var mine := Season.player_series(state, "player")
		var live := {} if mine.is_empty() else {"playerScore": 25, "oppScore": 10, "playerSwishes": 3, "oppSwishes": 1, "ot": 0}
		Season.resolve_playoff_step(state, ratings, "player", live)
	t.eq(state["phase"], "done", "season done")
	t.ok(state["championId"] != "", "champion crowned")
	var in_playoffs := false
	for s in state["series"]:
		if s["highSeedId"] == "player" or s["lowSeedId"] == "player":
			in_playoffs = true
	if in_playoffs:
		t.eq(state["championId"], "player", "the player wins every live playoff game → champion")
	var final_ := Playoffs.find(state["series"], "final")
	t.ok(not final_.is_empty() and final_["games"].size() >= 3, "final played at least 3 games")


func _campaign(t) -> void:
	var league := LeagueData.league("cage")
	var doc := Campaign.new_doc(league, 7, 1000)
	t.eq(doc["leagueId"], "cage", "doc keyed to the league")
	t.ok(Campaign.next_opponent(doc) != "" and Campaign.next_opponent(doc) != "player", "a first opponent")
	var result := {"won": true, "player_score": 28, "ai_score": 15, "ot": 0,
		"sides": {"player": {"score": 28, "makes": 20, "swishes": 6, "attempts": 30, "bestStreak": 7, "bonus": 4, "iced": 0},
			"ai": {"score": 15, "makes": 12, "swishes": 2, "attempts": 25, "bestStreak": 3, "bonus": 0, "iced": 1}}}
	# The opponent's card plays come off its season hand.
	var opp := Campaign.next_opponent(doc)
	var opp_hand := Season.card_hand(doc["season"], opp)
	if opp_hand.is_empty():
		doc["season"]["cardHands"][opp] = ["ice"]
		opp_hand = ["ice"]
	result["sides"]["ai"]["cardsPlayed"] = [opp_hand[0]]
	Campaign.apply_live_result(doc, league, result, 2000)
	t.eq(Season.card_hand(doc["season"], opp).size(), opp_hand.size() - 1, "the opponent's played card left its season hand")
	result["sides"]["ai"].erase("cardsPlayed")
	t.eq(int(doc["season"]["currentDay"]), 2, "season advanced")
	t.eq(int(doc["career"]["totals"]["wins"]), 1, "career win")
	t.eq(int(doc["career"]["highs"]["points"]), 28, "career high points")
	t.ok(float(doc["selfRatings"]["accuracy"]) > 0.45, "self ratings moved toward the live make rate")
	Campaign.sim_to_playoffs(doc, league)
	t.eq(doc["season"]["phase"], "playoffs", "simmed to the playoffs")
	t.eq(int(doc["career"]["totals"]["games"]), 14, "14 games on the career after a full regular season")
	# Play through the playoffs, winning if in.
	var guard := 0
	while doc["season"]["phase"] == "playoffs" and guard < 20:
		guard += 1
		if Campaign.player_alive(doc):
			Campaign.apply_live_result(doc, league, result, 3000)
		else:
			Campaign.sim_step(doc, league)
	t.eq(doc["season"]["phase"], "done", "campaign season done")
	t.eq(doc["career"]["seasons"].size(), 1, "season folded into the career")
	var summary: Dictionary = doc["career"]["seasons"][0]
	t.ok(int(summary["finish"]) >= 1 and int(summary["finish"]) <= 8, "finish recorded (%d)" % summary["finish"])
	t.ok(summary["playoffResult"] in ["missed", "semifinal", "runner_up", "champion"], "playoff result recorded")
	var titles_before := int(doc["career"]["championships"])
	Campaign.start_next_season(doc, league)
	t.eq(int(doc["year"]), 2, "year 2")
	t.eq(doc["season"]["phase"], "regular", "fresh season")
	t.eq(int(doc["career"]["championships"]), titles_before, "career persists across seasons")
	# Unlock rule: by level (docs/PROGRESSION.md).
	var beach := LeagueData.league("beach")
	t.ok(not Progression.league_unlocked(2, beach), "the beach is locked at level 2")
	t.ok(Progression.league_unlocked(3, beach), "and opens at 3")
	t.ok(Progression.league_unlocked(1, league), "no rule → open")
