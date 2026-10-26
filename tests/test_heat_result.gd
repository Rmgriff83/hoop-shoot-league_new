extends RefCounted
## The league post-match page (docs/HOME.md → Results): HeatCopy through
## a win, a loss, overtime and a heat outside a league — the header, the
## result and score, the opponent line and chip, the box score's gold side
## (fewer ICED is better, ties plain), the tickets, the drop, the
## CONTINUE SEASON sub-line after a folded result — and the chrome off-tree.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func _heat(won: bool, ot: int, drop: String) -> Dictionary:
	return {"won": won, "player_score": 41 if won else 33, "ai_score": 37 if won else 36, "ot": ot,
		"opponent": LeagueData.shooter("brickport"), "mode": "heat", "location": "cage",
		"league": {"id": "cage", "game": "d4", "playoff": false}, "tickets": 36 if won else 16, "card_drop": drop,
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
	t.eq(HeatCopy.result(win), {"text": "YOU WIN", "size": 36, "gold": true}, "a win is gold at 36 (design 6b)")
	t.eq(HeatCopy.result(_heat(false, 0, "")), {"text": "THEY TOOK IT", "size": 28, "gold": false}, "a loss is cream at 28")
	t.eq(HeatCopy.title(win), "ARCADE LEAGUE", "the title is the league's name")
	t.eq(HeatCopy.kicker(win, doc), "SEASON 1 · DAY 4", "…under the season and day")
	t.eq(HeatCopy.title({"league": null}), "QUICK HEAT", "no league: a quick heat")
	t.eq(HeatCopy.kicker({"league": null}, doc), "", "…with no kicker")
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
	t.eq(HeatCopy.rewards(win), {"big": "+36", "sub": "TICKETS · WIN", "sub2": ""}, "the rewards card: the tickets")
	var xp_win := win.duplicate(true)
	xp_win["xp"] = {"gained": 18, "level_before": 1, "level_after": 1}
	t.eq(HeatCopy.rewards(xp_win)["sub2"], "+18 XP", "the XP under the tickets")
	t.eq(HeatCopy.level_line(xp_win, 64), {"text": "LEVEL 1 · 64/100 XP", "gold": false}, "the level line")
	var m := HeatCopy.level_meter(xp_win, 64)
	t.eq([m["from"], m["to"], m["need"], m["up"]], [46, 64, 100, false], "the meter fills 46 → 64 of 100")
	t.eq(HeatCopy.meter_text(m, 0.0), "LEVEL 1 · 46/100 XP", "…counting from where you were")
	t.eq(HeatCopy.meter_text(m, 1.0), "LEVEL 1 · 64/100 XP", "…to where you are")
	xp_win["xp"] = {"gained": 30, "level_before": 1, "level_after": 2}
	t.eq(HeatCopy.level_line(xp_win, 110), {"text": "LEVEL UP · LEVEL 2", "gold": true}, "a level up is gold")
	var mu := HeatCopy.level_meter(xp_win, 110)
	t.eq([mu["from"], mu["to"], mu["up"]], [80, 100, true], "a level up fills the old level to the end")
	t.eq(HeatCopy.meter_text(mu, 0.5), "LEVEL 1 · 90/100 XP", "…counting in the old level")
	t.eq(HeatCopy.meter_text(mu, 1.0), "LEVEL UP · LEVEL 2", "…then LEVEL UP")
	xp_win["xp"] = {"gained": 0, "level_before": 3, "level_after": 3}
	t.eq(HeatCopy.level_line(xp_win, 200), {"text": "LEVEL 3 · CAP", "gold": false}, "at the league's cap")
	t.eq(HeatCopy.level_line({"league": null, "xp": {"gained": 5}}, 5), {}, "no line outside a league")
	t.eq(HeatCopy.rewards(_heat(false, 0, ""))["sub"], "TICKETS · LOSS", "a loss says so")
	t.eq(HeatCopy.rewards({"league": null, "tickets": 9}), {}, "no card outside a league")
	t.eq(HeatCopy.rewards({"online": true, "won": true, "league": null}), {}, "no card for an online match until its settle brings tickets")
	t.eq(HeatCopy.rewards({"online": true, "won": true, "league": null, "tickets": 30}), {"big": "+30", "sub": "TICKETS · WIN", "sub2": ""}, "the online tickets, no XP")
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
	t.ok(c.find_child("Tickets", true, false) is TicketBox, "the gold tickets box (design 6b)")
	t.eq((c.find_child("Tickets", true, false) as TicketBox).count_text(), "+36", "…with the haul")
	t.ok(c.find_child("Stream", true, false) is TicketStream, "the ticket stream")
	t.eq((c.find_child("Title", true, false) as Label).text, "ARCADE LEAGUE", "the league's name as the title")
	t.ok(c.find_child("DropPlus", true, false) != null, "the drop row says +1 CARD")
	t.ok(c.find_child("ContinueSeason", true, false).get_parent() == c.find_child("Home", true, false).get_parent(), "CONTINUE SEASON and HOME share the foot")
	t.ok(c.find_child("Coins", true, false) == null, "no coins anywhere (2026-10-19)")
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
	t.eq((c.find_child("Title", true, false) as Label).text, "QUICK HEAT", "a quick heat's title")
	t.ok(c.find_child("Tickets", true, false) == null and c.find_child("ContinueSeason", true, false) == null, "no tickets box, no continue")
	t.ok(c.find_child("Home", true, false) != null, "HOME stays")
	c.free()
	# Online (docs/BACKEND.md → Ranked → Stage B): the rank line reserves its
	# row, the tickets beside the spoils, the meter under them, bright rows slim.
	var on := _heat(false, 0, "")
	on["league"] = null
	on["online"] = true
	on["ranked"] = true
	on["tickets"] = 14
	on["rating"] = {"before": {"mu": 1500.0, "rd": 350.0, "cons": 800.0}, "after": {"mu": 1483.0, "rd": 290.0, "cons": 903.0}, "delta": -17.0}
	on["rank"] = {"tier": "rookie", "division": 3}
	on["events"] = []
	on["spoils"] = {"captured": [], "lost": ["fire7"], "insured": "ice"}
	on["meter"] = {"before": 6, "after": 14, "size": 22, "odds": {"common": 0.8163, "rare": 0.1837, "epic": 0.0}}
	on["granted"] = []
	on["bright"] = ["NEW BEST STREAK · 6", "7 SWISHES · YOUR MOST"]
	c = screen.build_chrome(on, {}, {})
	t.eq((c.find_child("RankLine", true, false) as Label).text, "RATING -17 · ROOKIE III", "the rank line from the heat's merged settle")
	t.eq((c.find_child("Box", true, false) as Control).position.y, 442.0, "the box keeps its place (the rank line sits in the score block)")
	t.eq((c.find_child("RewardsBig", true, false) as Label).text, "+14", "the online tickets")
	t.eq((c.find_child("RewardsSub", true, false) as Label).text, "TICKETS · LOSS", "…for the loss")
	t.eq((c.find_child("SpoilsCaption", true, false) as Label).text, "LOST · HEAT CHECK · INSURED · DEEP FREEZE BACK", "what the loss cost, and what insurance kept")
	t.eq((c.find_child("MeterLine", true, false) as Label).text, "METER 14/22 · 82% COMMON · 18% RARE", "the meter line")
	t.close((c.find_child("MeterFill", true, false) as ColorRect).anchor_right, 14.0 / 22.0, 1e-6, "the meter bar")
	t.eq(c.find_child("Row_ICED_OVER", true, false).custom_minimum_size.y, 50.0, "box rows slim under bright spots")
	t.ok(c.find_child("Bright", true, false) != null, "the bright spots in a loss")
	t.ok(c.find_child("Rematch", true, false) == null, "no REMATCH without a room")
	c.free()
	screen.free()
