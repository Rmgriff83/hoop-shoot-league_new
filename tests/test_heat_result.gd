extends RefCounted
## The league post-match page (docs/HOME.md → Results): HeatCopy through
## a win, a loss, overtime and a heat outside a league — the header, the
## result and score, the opponent line and chip, the box score's gold side
## (fewer ICED is better, ties plain), the coins and tickets, the drop, the
## CONTINUE SEASON sub-line after a folded result — and the chrome off-tree.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func _heat(won: bool, ot: int, drop: String) -> Dictionary:
	return {"won": won, "player_score": 41 if won else 33, "ai_score": 37 if won else 36, "ot": ot,
		"opponent": LeagueData.shooter("brickport"), "mode": "heat", "location": "cage",
		"league": {"id": "cage", "game": "d4", "playoff": false}, "coins": 50 if won else 15, "tickets": 28 if won else 11, "card_drop": drop,
		"sides": {"player": {"makes": 17, "attempts": 26, "swishes": 6, "bestStreak": 7, "bonus": 8, "iced": 0},
			"ai": {"makes": 15, "attempts": 27, "swishes": 4, "bestStreak": 5, "bonus": 6, "iced": 1}}}


func run(t) -> void:
	_copy(t)
	_continue(t)
	_chrome(t)


func _copy(t) -> void:
	var cage := LeagueData.league("cage")
	var doc := Campaign.new_doc(cage, 5, 0)
	var win := _heat(true, 0, "fire7")
	t.eq(HeatCopy.header(win, doc), "ARCADE LEAGUE · SEASON 1 · DAY 4", "the header: league, season, day")
	t.eq(HeatCopy.header({"league": null}, doc), "QUICK HEAT", "no league: a quick heat")
	t.eq(HeatCopy.game_line("d7", doc), "DAY 7", "a day tag")
	t.eq(HeatCopy.result(win), {"text": "YOU WIN", "size": 56, "gold": true}, "a win is gold at 56")
	t.eq(HeatCopy.result(_heat(false, 0, "")), {"text": "THEY TOOK IT", "size": 48, "gold": false}, "a loss is cream at 48")
	t.eq(HeatCopy.score_line(win), "41-37", "the score line")
	t.ok(not HeatCopy.ot(win) and HeatCopy.ot(_heat(true, 1, "")), "OT only when it went there")
	var vs := HeatCopy.vs_line(win)
	t.ok(vs.begins_with("VS MO MORTAR · \""), "the opponent line (%s)" % vs)
	var chip := HeatCopy.opponent_chip(win)
	t.eq(chip["text"], "MO", "the chip is the first name")
	t.ok(chip["color"] is Color and chip["color"] != LeagueContext.PINE, "in their shooter colour")
	t.eq(HeatCopy.opponent_chip({"opponent": {"name": "Solo"}})["color"], LeagueContext.PINE, "pine without a colour")
	var box := HeatCopy.box(win)
	t.eq(box.size(), 6, "six rows")
	t.eq(box[0], {"l": "MAKES", "a": "17/26", "b": "15/27", "hi": "a"}, "makes: you")
	t.eq(box[1]["a"], "65%", "shooting percent")
	t.eq(box[1]["hi"], "a", "the better percent")
	t.eq(box[4], {"l": "STREAK BONUS", "a": "+8", "b": "+6", "hi": "a"}, "bonus with its plus")
	t.eq(box[5], {"l": "ICED OVER", "a": "0", "b": "1", "hi": "a"}, "fewer iced is better")
	var tie := _heat(true, 0, "")
	tie["sides"]["ai"] = tie["sides"]["player"].duplicate()
	for r in HeatCopy.box(tie):
		t.eq(r["hi"], "", "%s: a tie marks nobody" % r["l"])
	t.eq(HeatCopy.pct_text({"attempts": 0}), "-", "no attempts, no percent")
	t.eq(HeatCopy.coins(win), {"big": "+50", "sub": "COINS · WIN", "sub2": "+28 TICKETS"}, "the coins card with the tickets")
	t.eq(HeatCopy.coins(_heat(false, 0, ""))["sub"], "COINS · LOSS", "a loss says so")
	t.eq(HeatCopy.coins({"league": null, "coins": 9}), {}, "no card outside a league")
	t.eq(HeatCopy.drop(win)["id"], "fire7", "the dropped card")
	t.eq(HeatCopy.drop(_heat(true, 0, "")), {}, "no drop, no card")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in [HeatCopy.header(win, doc), vs, "COINS · WIN", "NOW 3-1 · 2ND PLACE · DAY 5 NEXT", "THEY TOOK IT"]:
		for ch in s:
			t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces" % ch)


func _continue(t) -> void:
	var cage := LeagueData.league("cage")
	var doc := Campaign.new_doc(cage, 5, 0)
	var result := {"won": true, "player_score": 28, "ai_score": 15, "ot": 0,
		"sides": {"player": {"score": 28, "makes": 20, "swishes": 6, "attempts": 30, "bestStreak": 7, "bonus": 4, "iced": 0},
			"ai": {"score": 15, "makes": 12, "swishes": 2, "attempts": 25, "bestStreak": 3, "bonus": 0, "iced": 1}}}
	Campaign.apply_live_result(doc, cage, result, 1000)
	var sub := HeatCopy.continue_sub(doc, cage)
	t.ok(sub.begins_with("NOW 1-0 · ") and sub.ends_with(" PLACE · DAY 2 NEXT"), "after a win: record, place, next day (%s)" % sub)
	Campaign.sim_to_playoffs(doc, cage)
	sub = HeatCopy.continue_sub(doc, cage)
	t.ok(sub.contains("NEXT") or sub == "OUT OF THE PLAYOFFS" or sub == "CHAMPIONS", "the playoffs line (%s)" % sub)
	var po: Dictionary = doc["season"]
	if not Season.player_series(po, Campaign.PLAYER).is_empty():
		var mine := Season.player_series(po, Campaign.PLAYER)
		t.ok(HeatCopy.game_line("po-" + str(mine["id"]), doc).begins_with("SEMI"), "a playoff tag names the series (%s)" % HeatCopy.game_line("po-" + str(mine["id"]), doc))
	doc["season"]["phase"] = Season.PHASE_DONE
	doc["season"]["championId"] = Campaign.PLAYER
	t.eq(HeatCopy.continue_sub(doc, cage), "CHAMPIONS · SEASON 1 OVER", "champions")
	doc["season"]["championId"] = "brickport"
	t.ok(HeatCopy.continue_sub(doc, cage).begins_with("SEASON OVER · "), "season over, your place")
	t.eq(HeatCopy.continue_sub({}, cage), "", "no doc, no line")


func _chrome(t) -> void:
	var app = _app()
	if app == null:
		return
	var cage := LeagueData.league("cage")
	var doc := Campaign.new_doc(cage, 5, 0)
	var screen = load("res://game/screens/heat_result_screen.gd").new()
	var c: Control = screen.build_chrome(_heat(true, 1, "fire7"), doc, cage)
	t.eq((c.find_child("Result", true, false) as Label).text, "YOU WIN", "the result")
	t.ok((c.find_child("ScoreLine", true, false) as Label).material is ShaderMaterial, "the score carries the dithered shadow")
	t.ok(c.find_child("OT", true, false) != null, "the OT chip in overtime")
	t.ok(c.find_child("Row_ICED_OVER", true, false) != null, "six box rows end with ICED OVER")
	t.ok(c.find_child("YouChip", true, false) is ShadowPanel and c.find_child("ThemChip", true, false) is ShadowPanel, "the two chips")
	t.ok(c.find_child("Coins", true, false) != null and c.find_child("TicketsLine", true, false) != null, "coins with the tickets line")
	t.ok(c.find_child("Drop", true, false) != null, "the card drop")
	t.ok(c.find_child("ContinueSeason", true, false) is ShadowCard, "CONTINUE SEASON")
	t.ok((c.find_child("ContinueSub", true, false) as Label).text.begins_with("NOW 0-0"), "with the season line")
	c.free()
	c = screen.build_chrome(_heat(false, 0, ""), doc, cage)
	t.ok(c.find_child("OT", true, false) == null, "no OT chip in regulation")
	t.ok(c.find_child("Drop", true, false) == null, "no drop card without a drop")
	c.free()
	var quick := _heat(true, 0, "")
	quick["league"] = null
	c = screen.build_chrome(quick, {}, {})
	t.eq((c.find_child("Header", true, false) as Label).text, "QUICK HEAT", "a quick heat's header")
	t.ok(c.find_child("Coins", true, false) == null and c.find_child("ContinueSeason", true, false) == null, "no coins, no continue")
	t.ok(c.find_child("Home", true, false) != null, "HOME stays")
	c.free()
	screen.free()
