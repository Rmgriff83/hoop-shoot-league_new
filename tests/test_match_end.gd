extends RefCounted
## The league match-end page (docs/HOME.md → Results): MatchEndCopy picks
## the moment from the heat and the campaign snapshot — win, loss, a series
## game, advance, eliminated, runner-up, champion — with the tag, the
## headline, the stakes block (record flip + place move, bracket, trophy),
## the sub line and the rewards; every string in both pixel faces; the
## overlay builds off-tree for each and its clock schedules the elements;
## App.settle_heat fills the snapshot and leaves the scene alone.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func _heat(won: bool, end: Dictionary, playoff := false, drop := "fire7") -> Dictionary:
	var e := {"year": 2, "league_name": "ARCADE LEAGUE", "record_before": [2, 1], "record_after": [3, 1] if won else [2, 2],
		"place_before": 3, "place_after": 2 if won else 4, "titles_before": 1, "titles_after": 1,
		"playoff": playoff, "round": "", "series_id": "", "best_of": 3, "series_before": [0, 0], "series_after": [0, 0],
		"decided": false, "series_won": false, "other_semi": ["kingsbridge", "ferry-row"], "final_opp": "", "teams": 6}
	e.merge(end, true)
	return {"won": won, "player_score": 41 if won else 33, "ai_score": 37 if won else 36, "ot": 0,
		"opponent": LeagueData.shooter("brickport"), "mode": "heat", "location": "cage",
		"league": {"id": "cage", "game": "po-sf-1" if playoff else "d4", "playoff": playoff},
		"coins": 50 if won else 15, "tickets": 28, "card_drop": drop, "league_end": e}


func run(t) -> void:
	_copy(t)
	_overlay(t)
	_settle(t)


func _copy(t) -> void:
	t.eq(MatchEndCopy.ordinal(1), "1ST", "1st")
	t.eq(MatchEndCopy.ordinal(2), "2ND", "2nd")
	t.eq(MatchEndCopy.ordinal(3), "3RD", "3rd")
	t.eq(MatchEndCopy.ordinal(4), "4TH", "4th")
	t.eq(MatchEndCopy.ordinal(11), "11TH", "11th")
	t.eq(MatchEndCopy.place_text(3, 2), "2ND PLACE · UP 1", "moved up")
	t.eq(MatchEndCopy.place_text(2, 4), "4TH PLACE · DOWN 2", "moved down")
	t.eq(MatchEndCopy.place_text(2, 2), "2ND PLACE · HOLD", "held")
	t.eq(MatchEndCopy.place_text(0, 1), "1ST PLACE", "the first game has no move")
	var win := MatchEndCopy.state(_heat(true, {}))
	t.eq(win["kind"], "win", "a regular-season win")
	t.eq(win["tag"], "DAY 4 · FINAL", "the day tag")
	t.eq(win["head"], "YOU WIN", "the headline")
	t.ok(bool(win["win_anim"]) and bool(win["flash"]) and int(win["confetti_n"]) == 36, "slam, flash, confetti")
	t.ok(Color(win["rays"]).a > 0.0, "rays on a win")
	t.eq(win["block"], "record", "the record block")
	t.eq(win["record"]["old"], "2-1", "the old record")
	t.eq(win["record"]["new"], "3-1", "the new record")
	t.eq(win["record"]["place"], "2ND PLACE · UP 1", "the place chip")
	t.eq(win["record"]["label"], "SEASON 2 RECORD", "the record label")
	t.eq(win["coins"], "+50", "the coins")
	t.eq(win["opp_first"], "MO", "the opponent's first name")
	t.eq(win["head_size"], 64, "a short headline at 64")
	var loss := MatchEndCopy.state(_heat(false, {}))
	t.eq(loss["kind"], "loss", "a regular-season loss")
	t.eq(loss["head"], "THEY TOOK IT", "the loss headline")
	t.ok(not bool(loss["win_anim"]) and not bool(loss["flash"]) and int(loss["confetti_n"]) == 0, "sinks, no flash, no confetti")
	t.eq(Color(loss["rays"]).a, 0.0, "no rays on a loss")
	t.ok(float(loss["scrim"]) > float(win["scrim"]), "a darker scrim on a loss")
	t.eq(loss["record"]["place"], "4TH PLACE · DOWN 1", "the place drop")
	t.eq(loss["head_size"], 51, "a long headline shrinks (620 / 12)")
	var series := MatchEndCopy.state(_heat(true, {"round": "semifinal", "series_after": [1, 0]}, true))
	t.eq(series["kind"], "series", "an undecided playoff game")
	t.eq(series["tag"], "PLAYOFFS · SEMIFINAL", "the playoff tag")
	t.eq(series["sub"], "FIRST TO 2", "best of three")
	t.eq(series["block"], "bracket", "the bracket")
	t.eq(series["bracket"]["series"], "1 - 0", "the series score")
	t.eq(series["bracket"]["next_opp"], "VS DRE / SOL", "the other semi, first names")
	var adv := MatchEndCopy.state(_heat(true, {"round": "semifinal", "series_after": [2, 1], "decided": true, "series_won": true, "final_opp": "kingsbridge"}, true))
	t.eq(adv["kind"], "advance", "the semi won")
	t.eq(adv["head"], "ADVANCE", "ADVANCE")
	t.eq(adv["sub"], "ONE WIN FROM THE TITLE", "the sub")
	t.eq(adv["bracket"]["next_name"], "YOU", "you move into the final")
	t.eq(adv["bracket"]["next_opp"], "VS DRE", "against the known finalist")
	t.ok(not bool(adv["bracket"]["lost"]), "no strike")
	var out := MatchEndCopy.state(_heat(false, {"round": "semifinal", "series_after": [1, 2], "decided": true, "series_won": false, "place_after": 3}, true))
	t.eq(out["kind"], "eliminated", "the semi lost")
	t.eq(out["head"], "ELIMINATED", "ELIMINATED")
	t.eq(out["sub"], "SEASON 2 OVER · 3RD PLACE", "the season is over")
	t.ok(bool(out["bracket"]["lost"]), "your row is struck")
	t.eq(out["bracket"]["next_name"], "MO", "they move on")
	var ru := MatchEndCopy.state(_heat(false, {"round": "final", "series_after": [2, 3], "decided": true, "series_won": false}, true))
	t.eq(ru["kind"], "runner_up", "the final lost")
	t.eq(ru["sub"], "SEASON 2 OVER · RUNNER-UP", "runner-up")
	t.eq(ru["tag"], "PLAYOFFS · FINAL", "the final's tag")
	var champ := MatchEndCopy.state(_heat(true, {"round": "final", "series_after": [3, 1], "decided": true, "series_won": true, "titles_after": 2}, true))
	t.eq(champ["kind"], "champion", "the final won")
	t.eq(champ["head"], "CHAMPIONS", "CHAMPIONS")
	t.eq(champ["tag"], "ARCADE LEAGUE · FINAL", "the league's final")
	t.eq(champ["block"], "trophy", "the trophy block")
	t.eq(champ["trophy"]["titles"], 2, "two titles")
	t.eq(champ["sub"], "SEASON 2 TITLE", "the title line")
	t.eq(champ["confetti_n"], 80, "the most confetti")
	t.eq(champ["spin_s"], 14.0, "the fastest rays")
	# Every string in both pixel faces (the glyph rule).
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for v in [win, loss, series, adv, out, ru, champ]:
		for s in MatchEndCopy.strings(v):
			for ch in str(s):
				t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, s])


func _overlay(t) -> void:
	var win := MatchEndCopy.state(_heat(true, {}))
	var o := MatchEndOverlay.new()
	var page := o.build(win)
	for n in ["Scrim", "Tag", "Head", "ScoreYou", "ScoreOpp", "Record", "RecordOld", "RecordNew", "Place", "Coins", "Drop", "DropArt", "Continue", "Rays", "Confetti", "Flash"]:
		t.ok(page.find_child(n, true, false) != null, "the win page has %s" % n)
	t.eq((page.find_child("Head", true, false) as Label).text, "YOU WIN", "the headline text")
	t.eq((page.find_child("ScoreYou", true, false) as Label).text, "41", "your score")
	t.eq((page.find_child("ScoreOppName", true, false) as Label).text, "MO", "their name under the score")
	t.eq(o.confetti_count(), 36, "36 pieces of confetti")
	var head: Control = page.find_child("HeadBox", true, false)
	t.eq(head.modulate.a, 0.0, "the headline is hidden at the buzzer")
	o.step(0.2)
	t.eq(head.modulate.a, 0.0, "…still at 0.2 s")
	o.step(0.3)
	t.ok(head.modulate.a > 0.0 and head.scale.x > 1.0, "at 0.5 s it is slamming in, still big (%.2f)" % head.scale.x)
	o.step(1.0)
	t.close(head.scale.x, 1.0, 1e-6, "settled by 1.5 s")
	var old: Control = page.find_child("RecordOld", true, false)
	var new_: Control = page.find_child("RecordNew", true, false)
	t.close(new_.position.y, 64.0, 1e-6, "the new record waits below the clip")
	o.step(1.0)
	t.ok(old.position.y < -60.0 and absf(new_.position.y) < 1.0, "by 2.5 s the record has flipped")
	t.ok(not (page.find_child("Continue", true, false) as Control).visible and not o.ready_to_continue(), "no continue before 3 s")
	o.step(0.6)
	t.ok(o.ready_to_continue() and (page.find_child("Continue", true, false) as Control).visible, "TAP TO CONTINUE from 3 s")
	var got := []
	o.continued.connect(func() -> void: got.push_back(true))
	o.skip()
	o.skip()
	t.eq(got.size(), 1, "a tap continues once")
	o.free()
	var loss := MatchEndOverlay.new()
	var lp := loss.build(MatchEndCopy.state(_heat(false, {}, false, "")))
	t.ok(lp.find_child("Rays", true, false) == null and lp.find_child("Flash", true, false) == null, "a loss has no rays or flash")
	t.ok(lp.find_child("Drop", true, false) == null, "no drop tile without a drop")
	t.eq(loss.confetti_count(), 0, "no confetti")
	var lh: Control = lp.find_child("HeadBox", true, false)
	loss.step(0.45)
	t.ok(lh.position.y < 300.0 and lh.modulate.a > 0.0, "the loss headline sinks in from above (%.1f)" % lh.position.y)
	loss.free()
	var out := MatchEndOverlay.new()
	var op := out.build(MatchEndCopy.state(_heat(false, {"round": "semifinal", "series_after": [1, 2], "decided": true, "series_won": false, "place_after": 3}, true, "")))
	t.ok(op.find_child("Bracket", true, false) != null and op.find_child("Strike", true, false) != null, "the eliminated page has the bracket with a strike")
	var strike: Control = op.find_child("Strike", true, false)
	out.step(2.5)
	t.ok(strike.size.x > 200.0, "the strike has grown across your row (%.0f)" % strike.size.x)
	out.free()
	var champ := MatchEndOverlay.new()
	var cp := champ.build(MatchEndCopy.state(_heat(true, {"round": "final", "series_after": [3, 1], "decided": true, "series_won": true, "titles_after": 2}, true)))
	t.ok(cp.find_child("Trophy", true, false) != null and cp.find_child("Title1", true, false) != null, "the champion page has the trophy and two title cups")
	t.eq((cp.find_child("TitleCount", true, false) as Label).text, "X2", "X2")
	t.eq(champ.confetti_count(), 80, "80 pieces of confetti")
	champ.free()


func _settle(t) -> void:
	var app = _app()
	if app == null:
		return
	var doc_before: Dictionary = SaveService.league_doc("cage")
	var cos_before: Dictionary = SaveService.get_cosmetics()
	var prog_before: Dictionary = SaveService.get_progress()
	var cards_before: Dictionary = SaveService.get_cards()
	t.ok(app.enter_league("cage"), "into the cage league")
	app.next_heat = app.league_heat_config(app.league_doc("cage"), app.league_cfg("cage"))
	var result := {"won": true, "player_score": 40, "ai_score": 30, "ot": 0,
		"sides": {"player": {"makes": 17, "attempts": 26, "swishes": 6, "bestStreak": 7, "bonus": 8, "iced": 0},
			"ai": {"makes": 15, "attempts": 27, "swishes": 4, "bestStreak": 5, "bonus": 6, "iced": 1}}}
	var heat: Dictionary = app.settle_heat(result)
	t.ok(heat.has("league_end"), "settle_heat captures the campaign snapshot")
	var e: Dictionary = heat["league_end"]
	t.eq(e["record_before"], [0, 0], "no games before")
	t.eq(e["record_after"], [1, 0], "one win after")
	t.ok(int(e["place_after"]) >= 1, "a place after the first game (%d)" % int(e["place_after"]))
	t.eq(e["playoff"], false, "a regular-season game")
	t.ok(heat.has("coins") and heat.has("xp"), "payout and XP settled")
	t.eq(MatchEndCopy.state(heat)["kind"], "win", "and the page reads it as a win")
	SaveService.put_league_doc("cage", doc_before)
	SaveService.put_cosmetics(cos_before)
	SaveService.put_progress(prog_before)
	SaveService.put_cards(cards_before)
