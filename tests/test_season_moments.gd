extends RefCounted
## Season moments (design 39c/e/f and 39d, docs/LEAGUE.md → Season moments):
## SeasonCopy writes the wrap-up for each way a season ends and the new
## season's opening week, every string in both pixel faces; the two pages
## build off-tree and their clocks schedule the banner, the stats, the
## count-up, the roll, the strike, the deal and the buttons.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


## A season played to the end: every live playoff game won (`win`) or lost
## (the player goes out), on a fixed seed.
func _done_doc(league: Dictionary, seed_value: int, win_playoffs: bool) -> Dictionary:
	var doc := Campaign.new_doc(league, seed_value, 1000)
	var win := {"won": true, "player_score": 30, "ai_score": 18, "ot": 0,
		"sides": {"player": {"score": 30, "makes": 20, "swishes": 6, "attempts": 28, "bestStreak": 9, "bonus": 4, "iced": 0},
			"ai": {"score": 18, "makes": 12, "swishes": 2, "attempts": 25, "bestStreak": 3, "bonus": 0, "iced": 0}}}
	var loss := {"won": false, "player_score": 20, "ai_score": 29, "ot": 0,
		"sides": {"player": {"score": 20, "makes": 14, "swishes": 3, "attempts": 26, "bestStreak": 4, "bonus": 0, "iced": 0},
			"ai": {"score": 29, "makes": 19, "swishes": 5, "attempts": 27, "bestStreak": 6, "bonus": 2, "iced": 0}}}
	Campaign.apply_live_result(doc, league, win, 2000)
	Campaign.sim_to_playoffs(doc, league)
	var guard := 0
	while doc["season"]["phase"] == "playoffs" and guard < 20:
		guard += 1
		if Campaign.player_alive(doc):
			Campaign.apply_live_result(doc, league, win if win_playoffs else loss, 3000)
		else:
			Campaign.sim_step(doc, league)
	Campaign.note_earned(doc, 1240, 310)
	return doc


func run(t) -> void:
	var league := LeagueData.league("cage")
	_copy(t, league)
	_wrap_page(t, league)
	_new_page(t, league)


func _copy(t, league: Dictionary) -> void:
	t.eq(SeasonCopy.thousands(1240), "1,240", "thousands")
	t.eq(SeasonCopy.thousands(310), "310", "…under a thousand")
	# Champions (every live playoff game won).
	var champ_doc := _done_doc(league, 7, true)
	var c := SeasonCopy.wrap(champ_doc, league)
	t.eq(c["variant"], "champs", "champions variant")
	t.eq(c["head"], "CHAMPIONS", "the headline")
	t.ok(bool(c["trophy"]) and c["banner_color"] == SeasonCopy.GOLD, "the gold banner with the trophy")
	t.ok(str(c["line"]).begins_with("%d-%d · " % [c["stats"][0]["v"].split("-")[0].to_int(), c["stats"][0]["v"].split("-")[1].to_int()]), "the line opens with the record (%s)" % c["line"])
	t.ok(str(c["line"]).find(" SEED · WON THE FINAL ") > 0, "…the seed and the final (%s)" % c["line"])
	t.eq(c["champion"]["name"], "YOU", "the champion is you")
	t.ok(str(c["champion"]["title"]).begins_with("CHAMPION · "), "…with the final's score (%s)" % c["champion"]["title"])
	t.ok(c["runner_up"]["name"] != "YOU" and c["runner_up"]["name"] != "-", "a runner-up (%s)" % c["runner_up"]["name"])
	t.eq(c["stats"].size(), 6, "six stats")
	for i in 6:
		t.eq(c["stats"][i]["l"], SeasonCopy.STAT_LABELS[i], "stat %d is %s" % [i, SeasonCopy.STAT_LABELS[i]])
	t.eq(c["stats"][1]["v"], TickerText.ordinal(SeasonWrap.stats(champ_doc, league)["finish"]), "FINISH is the seed")
	t.eq(c["stats"][4]["v"], "9", "BEST STREAK is the season's best shot streak")
	t.eq(c["highlights"].size(), 3, "three highlights")
	t.eq(c["highlights"][0]["l"], "BEST GAME", "BEST GAME")
	t.ok(str(c["highlights"][0]["v"]).match("*-* *"), "…score and opponent (%s)" % c["highlights"][0]["v"])
	t.eq(c["highlights"][1]["l"], "TOUGHEST", "TOUGHEST")
	t.ok(str(c["highlights"][1]["v"]).find(" · ") > 0, "…name and record (%s)" % c["highlights"][1]["v"])
	t.eq(c["highlights"][2], {"l": "TITLES", "v": "1"}, "TITLES counts the new one")
	t.eq(c["earned"]["xp"], "+1,240 XP", "the season's XP")
	t.eq(c["earned"]["tickets"], "+310", "…and tickets")
	t.eq(c["start"]["title"], "START SEASON 2", "START SEASON 2")
	t.eq(c["season"], "SEASON 1", "SEASON 1 in the head")
	t.eq(c["league"], "ARCADE LEAGUE", "the league")
	# Out in the playoffs (every live playoff game lost).
	var out_doc := _done_doc(league, 7, false)
	var o := SeasonCopy.wrap(out_doc, league)
	t.eq(o["variant"], "out", "out variant")
	t.ok(o["head"] in ["OUT IN THE SEMIS", "LOST THE FINAL"], "the headline names the round (%s)" % o["head"])
	t.ok(not bool(o["trophy"]) and o["banner_color"] == SeasonCopy.ORANGE, "the orange banner, no trophy")
	t.ok(str(o["line"]).find(" · LOST ") > 0 and str(o["line"]).find(" TO ") > 0, "the series lost and to whom (%s)" % o["line"])
	t.ok(o["champion"]["name"] != "YOU", "someone else is champion (%s)" % o["champion"]["name"])
	t.eq(o["highlights"][2]["v"], "0", "no titles")
	# Missed the playoffs: staged by emptying the player's series on a done doc.
	var miss_doc := _done_doc(league, 11, false)
	var kept_series: Array = miss_doc["season"]["series"]
	var others := []
	for sr in kept_series:
		if sr["highSeedId"] != "player" and sr["lowSeedId"] != "player":
			others.push_back(sr)
	miss_doc["season"]["series"] = others
	var m := SeasonCopy.wrap(miss_doc, league)
	t.eq(m["variant"], "missed", "missed variant")
	t.eq(m["head"], "MISSED THE PLAYOFFS", "the headline")
	t.eq(m["banner_color"], SeasonCopy.CREAM, "the cream banner")
	var w := SeasonWrap.stats(miss_doc, league)
	var tail := str(m["line"]).get_slice(" · ", 2)
	if int(w["finish"]) > 4:
		t.ok(tail.ends_with("OUT") or tail == "ON THE TIEBREAK", "how far off the line (%s)" % m["line"])
	else:
		t.ok(tail == "ON THE TIEBREAK", "seeded in the top four but not in the bracket reads as the tiebreak (%s)" % m["line"])
	t.eq(SeasonCopy._games_out(1.0), "ONE GAME OUT", "one game")
	t.eq(SeasonCopy._games_out(0.5), "HALF A GAME OUT", "half a game")
	t.eq(SeasonCopy._games_out(3.0), "3 GAMES OUT", "three")
	t.eq(SeasonCopy._games_out(0.0), "ON THE TIEBREAK", "level")
	# The new season, after the rollover.
	Campaign.start_next_season(champ_doc, league)
	var n := SeasonCopy.new_season(champ_doc, league)
	t.eq(n["old_year"], "1", "old year")
	t.eq(n["new_year"], "2", "new year")
	t.ok(bool(n["defending"]), "champions defend")
	t.ok(str(n["record_old"]).match("*-*"), "the old record (%s)" % n["record_old"])
	t.eq(n["record_new"], "0-0", "0-0")
	t.eq(n["week"]["sub"], "14 DAYS · 8 TEAMS", "the week line")
	t.eq(n["cards"].size(), 3, "three opening cards")
	t.eq(n["cards"][0]["day"], "DAY 1", "DAY 1")
	t.ok(n["cards"][0]["side"] in ["HOME", "AWAY"], "a side")
	t.ok(str(n["cards"][0]["h2h"]).begins_with("YOU WENT ") and str(n["cards"][0]["h2h"]).ends_with(" VS THEM"), "last season's record against them (%s)" % n["cards"][0]["h2h"])
	t.eq(n["more"], "+ 11 MORE DAYS · TOP 4 MAKE THE PLAYOFFS", "the more line")
	t.eq(n["play"]["title"], "PLAY DAY 1", "PLAY DAY 1")
	t.eq(n["play"]["sub"], "VS %s · %s" % [n["cards"][0]["name"], n["cards"][0]["side"]], "…against the first opponent")
	var fresh := Campaign.new_doc(league, 3, 1000)
	var n1 := SeasonCopy.new_season(fresh, league)
	t.ok(not bool(n1["defending"]) and n1["record_old"] == "" and n1["cards"][0]["h2h"] == "FIRST MEETING", "a first season: no history")
	# Every string in both pixel faces.
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for v in [c, o, m, n, n1]:
		for s in SeasonCopy.strings(v):
			for ch in str(s):
				t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, s])


func _wrap_page(t, league: Dictionary) -> void:
	if _app() == null:
		return
	var doc := _done_doc(league, 7, true)
	var v := SeasonCopy.wrap(doc, league)
	var page := SeasonWrapPage.new()
	var root := page.build(v)
	t.ok(root != null and page.sheet() != null, "the wrap-up builds off-tree")
	for n in ["Band", "League", "Season", "Close", "Banner", "BannerCup", "Head", "Line", "Champion", "ChampionName", "RunnerUp", "Stats", "Stat5", "Highlights", "Highlight_2", "Earnings", "XpCard", "XpText", "Tickets", "Start", "Later"]:
		t.ok(root.find_child(n, true, false) != null, "the wrap-up has %s" % n)
	t.eq(page.stat_count(), 6, "six stat cells")
	t.eq((root.find_child("Head", true, false) as Label).text, "CHAMPIONS", "the headline")
	t.eq((root.find_child("ChampionName", true, false) as Label).text, "YOU", "the champion card")
	var banner: Control = root.find_child("Banner", true, false)
	var start: Control = root.find_child("Start", true, false)
	t.eq(banner.modulate.a, 0.0, "the banner waits")
	t.eq(start.mouse_filter, Control.MOUSE_FILTER_IGNORE, "START ignores taps at first")
	page.step(0.7)
	t.ok(banner.modulate.a > 0.0, "the banner pops by 0.7 s")
	var s5: Control = root.find_child("Stat5", true, false)
	t.eq(s5.modulate.a, 0.0, "the last stat waits")
	page.step(1.3)
	t.ok(s5.modulate.a > 0.0, "…and is in by 2 s")
	t.eq(page.earned_text(), "+0 XP", "the XP has not counted yet")
	page.step(0.5)
	var mid := page.earned_text()
	t.ok(mid != "+0 XP" and mid != "+1,240 XP", "counting at 2.5 s (%s)" % mid)
	t.ok(not page.buttons_shown(), "the buttons are not up at 2.5 s")
	page.step(0.8)
	t.eq(page.earned_text(), "+1,240 XP", "full by 3.3 s")
	t.eq(page.tickets_text(), "+310", "…and the tickets")
	t.ok(page.buttons_shown() and start.mouse_filter == Control.MOUSE_FILTER_STOP, "the buttons take taps from 2.6 s")
	var got := []
	page.start_season.connect(func() -> void: got.push_back("start"))
	page.later.connect(func() -> void: got.push_back("later"))
	page.closed.connect(func() -> void: got.push_back("closed"))
	(start as Button).pressed.emit()
	t.eq(got, ["start"], "START SEASON asks for the new season")
	(root.find_child("Later", true, false) as Button).pressed.emit()
	t.eq(got, ["start", "later", "closed"], "LATER closes the page")
	var out_page := SeasonWrapPage.new()
	var out_root := out_page.build(SeasonCopy.wrap(_done_doc(league, 7, false), league))
	t.ok(out_root.find_child("BannerCup", true, false) == null, "no trophy on the banner when out")
	out_page.free()
	page.free()


func _new_page(t, league: Dictionary) -> void:
	if _app() == null:
		return
	var doc := _done_doc(league, 7, true)
	Campaign.start_next_season(doc, league)
	var page := NewSeasonPage.new()
	var root := page.build(SeasonCopy.new_season(doc, league))
	for n in ["Rays", "League", "SeasonRow", "SeasonBox", "Old", "New", "Defending", "RecordRow", "RecordOld", "Strike", "RecordNew", "Week", "DayCard_0", "DayCard_2", "More", "Play", "Later"]:
		t.ok(root.find_child(n, true, false) != null, "the new season page has %s" % n)
	var old: Control = root.find_child("Old", true, false)
	var new_: Control = root.find_child("New", true, false)
	var card0: Control = root.find_child("DayCard_0", true, false)
	var card2: Control = root.find_child("DayCard_2", true, false)
	var play: Control = root.find_child("Play", true, false)
	t.close(old.position.y, 0.0, 1e-3, "the old number sits in the box")
	t.close(new_.position.y, NewSeasonPage.BOX_H, 1e-3, "the new one waits below it")
	page.step(0.9)
	t.close(old.position.y, 0.0, 1e-3, "…until 1 s")
	page.step(0.5)
	t.ok(old.position.y < -100.0 and new_.position.y < 10.0, "by 1.4 s the number has rolled (%.0f / %.0f)" % [old.position.y, new_.position.y])
	t.close(page.strike_width(), 0.0, 1e-3, "no strike yet")
	page.step(1.0)
	t.ok(page.strike_width() > 60.0, "the old record is struck through by 2.4 s (%.0f)" % page.strike_width())
	t.ok((root.find_child("RecordNew", true, false) as Control).modulate.a > 0.0, "0-0 has popped")
	t.eq(card0.modulate.a, 0.0, "the cards wait")
	page.step(0.6)
	t.ok(card0.modulate.a > 0.0 and absf(card0.position.x) < 1.0, "the first card has dealt in by 3 s")
	t.eq(card2.modulate.a, 0.0, "…the third not yet")
	page.step(0.5)
	t.ok(card2.modulate.a > 0.0 and absf(card2.position.x) < 1.0, "…all three by 3.5 s")
	t.eq(play.mouse_filter, Control.MOUSE_FILTER_STOP, "PLAY DAY 1 takes taps from 3.4 s")
	var got := []
	page.play.connect(func() -> void: got.push_back("play"))
	(play as Button).pressed.emit()
	t.eq(got, ["play"], "PLAY DAY 1 asks for the match")
	page.free()
	var fresh := NewSeasonPage.new()
	var fr := fresh.build(SeasonCopy.new_season(Campaign.new_doc(league, 3, 1000), league))
	t.ok(fr.find_child("Defending", true, false) == null, "no DEFENDING CHAMPS chip without a title")
	t.ok(not (fr.find_child("RecordOld", true, false) as Control).visible, "no old record to strike on a first season")
	fresh.free()
	# slide_in with a delay off-tree is a no-op (the title adds the page first).
	var lone := SeasonWrapPage.new()
	lone.slide_in(false, 0.35)
	lone.free()
