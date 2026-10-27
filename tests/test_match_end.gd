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
		"decided": false, "series_won": false, "other_semi": ["kingsbridge", "ferry-row"], "final_opp": "", "teams": 6,
		"table_before": _table(5), "table_after": _table(3), "clinch_before": false, "clinch_after": false,
		"last_day": false, "day": 4, "seed_after": 2 if won else 4, "in_playoffs_after": false, "next_series": {},
		"series_game_no": 0, "earned": {"xp": 60, "tickets": 72}, "spots": 4}
	e.merge(end, true)
	return {"won": won, "player_score": 41 if won else 33, "ai_score": 37 if won else 36, "ot": 0,
		"opponent": LeagueData.shooter("brickport"), "mode": "heat", "location": "cage",
		"league": {"id": "cage", "game": "po-sf-1" if playoff else "d4", "playoff": playoff},
		"tickets": 36 if won else 16, "card_drop": drop, "league_end": e}


## Eight rows with the player at seed `you` (the others in roster order).
func _table(you: int) -> Array:
	var ids := ["brickport", "dustplain", "sunnyvale-flex", "maple-falls", "cactus-flats", "goldgulch", "pinewick"]
	var out := []
	var seed := 1
	for i in 8:
		if i == you - 1:
			out.push_back({"teamId": "player", "w": 9, "l": 5, "seed": seed})
		else:
			var id: String = ids.pop_front()
			out.push_back({"teamId": id, "w": 12 - i, "l": 2 + i, "seed": seed})
		seed += 1
	return out


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
	t.eq(win["tickets"], "+36", "the tickets")
	t.eq(win["ticket_count"], 36, "…and the count the stream builds up to")
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
	# Design 39b (2026-10-27): the tag names the game, the line the series.
	t.eq(champ["tag"], "ARCADE LEAGUE · FINAL · GAME 4", "the league's final, by game (3-1: four games)")
	t.eq(champ["block"], "champion", "the champions block")
	t.eq(champ["trophy"]["titles"], 2, "two titles")
	t.eq(champ["line"], "SEASON 2 · BEAT MO 3-1 · 41-37", "the series line")
	t.eq(champ["confetti_n"], 26, "26 pieces of confetti")
	t.eq(champ["spin_s"], 14.0, "the fastest rays")
	t.eq(champ["ready_s"], 3.2, "CONTINUE at 3.2 s")
	t.eq(champ["button"]["sub"], "TO THE POST-MATCH", "…the button")
	t.eq(champ["sound"], {"name": "chime_big", "at": 1.0}, "the big chime with the slam")
	t.ok(bool(champ["no_score"]) and bool(champ["no_rewards"]), "no score row, no rewards row: the cards carry it")
	t.eq(champ["cards"]["tickets_n"], 36, "the ticket haul")
	t.eq(champ["cards"]["xp"]["sub"], "AT THE CAP", "no XP recorded: at the cap")
	var champ_xp := MatchEndCopy.state(_heat(true, {"round": "final", "series_after": [3, 1], "decided": true, "series_won": true, "titles_after": 2, "series_game_no": 3}, true)
		.merged({"xp": {"gained": 180, "title_gained": 120, "level_before": 2, "level_after": 3, "capped": false, "title": true}, "xp_now": 260}))
	t.eq(champ_xp["tag"], "ARCADE LEAGUE · FINAL · GAME 3", "the game number from the snapshot")
	t.eq(champ_xp["cards"]["xp"]["label"], "+180 XP", "the match's XP, title jump included")
	t.eq(champ_xp["cards"]["xp"]["sub"], "CHAMPIONS BONUS", "…as the champions bonus")
	t.ok(not champ_xp["cards"]["xp"]["meter"].is_empty(), "…with the level meter")
	# Design 39a: the last day's win into the playoffs is the CLINCHED page.
	var clinch_end := {"last_day": true, "day": 14, "in_playoffs_after": true, "clinch_after": true, "seed_after": 3,
		"next_series": {"round": "semifinal", "id": "sf-2v3", "opp": "dustplain", "home": false, "best_of": 3, "seed_you": 3, "seed_opp": 2},
		"record_before": [8, 5], "record_after": [9, 5]}
	var clinch := MatchEndCopy.state(_heat(true, clinch_end))
	t.eq(clinch["kind"], "clinch", "a last-day win that makes the playoffs")
	t.eq(clinch["tag"], "DAY 14 · FINAL · W 41-37", "the day and score tag")
	t.eq(clinch["head"], "PLAYOFFS", "PLAYOFFS")
	t.eq(clinch["head_size"], 72, "…at 72")
	t.eq(clinch["block"], "standings", "the standings block")
	t.eq(clinch["standings"]["rows_before"].size(), 8, "eight rows before")
	t.eq(clinch["standings"]["rows_after"].size(), 8, "…and after")
	t.ok(clinch["standings"]["rows_before"][4]["you"] and clinch["standings"]["rows_after"][2]["you"], "you climb from fifth to third")
	t.eq(clinch["standings"]["record_after"], "9-5", "the record after")
	t.eq(clinch["standings"]["note"], "TOP 4 MAKE IT", "the note")
	t.eq(clinch["sub"], "CLINCHED · NO. 3 SEED", "the seed line")
	t.eq(clinch["matchup"]["title"], "SEMIFINAL · BEST OF 3", "the matchup")
	t.eq(clinch["matchup"]["line"], "GAME 1 · AWAY", "…away first")
	t.eq(clinch["matchup"]["you"], "NO. 3", "…your seed")
	t.eq(clinch["matchup"]["opp"] + " " + clinch["matchup"]["opp_name"], "NO. 2 " + LeagueSummary.short_name("dustplain"), "…theirs")
	t.eq(clinch["ready_s"], 3.6, "CONTINUE at 3.6 s")
	t.eq(clinch["confetti_n"], 0, "no confetti on the clinch")
	t.eq(clinch["sound"], {"name": "chime_win", "at": 2.5}, "the small chime with the slam")
	var locked := MatchEndCopy.state(_heat(true, clinch_end.merged({"clinch_before": true})))
	t.eq(locked["sub"], "LOCKED IN · NO. 3 SEED", "already clinched: locked in")
	t.eq(MatchEndCopy.state(_heat(true, {"last_day": false, "in_playoffs_after": true}))["kind"], "win", "not the last day: a plain win")
	t.eq(MatchEndCopy.state(_heat(true, {"last_day": true, "in_playoffs_after": false, "seed_after": 6}))["kind"], "win", "the last day but out: a plain win")
	t.eq(MatchEndCopy.state(_heat(true, {"clinch_after": true}))["tag"], "DAY 4 · FINAL · CLINCHED", "a mid-season clinch tags the win")
	t.eq(MatchEndCopy.state(_heat(true, {"clinch_after": true, "clinch_before": true}))["tag"], "DAY 4 · FINAL", "…once")
	var in_loss := MatchEndCopy.state(_heat(false, {"last_day": true, "in_playoffs_after": true, "seed_after": 4}))
	t.eq(in_loss["kind"], "loss", "a last-day loss that still makes it is a loss page")
	t.eq(in_loss["sub"], "IN THE PLAYOFFS · NO. 4 SEED", "…that says so")
	# Every string in both pixel faces (the glyph rule).
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for v in [win, loss, series, adv, out, ru, champ, champ_xp, clinch, in_loss]:
		for s in MatchEndCopy.strings(v):
			for ch in str(s):
				t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, s])


func _overlay(t) -> void:
	var win := MatchEndCopy.state(_heat(true, {}))
	var o := MatchEndOverlay.new()
	var page := o.build(win)
	for n in ["Scrim", "Tag", "Head", "ScoreYou", "ScoreOpp", "Record", "RecordOld", "RecordNew", "Place", "Tickets", "Drop", "DropArt", "Continue", "Rays", "Confetti", "Flash"]:
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
	# 39b: the trophy sinks in and quakes the page, the titles row, the cards.
	var champ := MatchEndOverlay.new()
	var cp := champ.build(MatchEndCopy.state(_heat(true, {"round": "final", "series_after": [3, 1], "decided": true, "series_won": true, "titles_after": 2}, true)
		.merged({"xp": {"gained": 180, "title_gained": 120, "level_before": 2, "level_after": 3, "capped": false, "title": true}, "xp_now": 260})))
	for n in ["Cup", "Line", "Titles", "Title1", "TitleCount", "XpCard", "XpMeter", "TicketsCard", "Stream", "ContinueButton", "Flash", "Rays"]:
		t.ok(cp.find_child(n, true, false) != null, "the champions page has %s" % n)
	t.ok(cp.find_child("ScoreYou", true, false) == null and cp.find_child("Rewards", true, false) == null and cp.find_child("Continue", true, false) == null, "…and no score row, rewards row or blinking label")
	t.eq((cp.find_child("TitleCount", true, false) as Label).text, "X2", "X2")
	t.eq(champ.confetti_count(), 26, "26 pieces of confetti")
	var cup: Control = cp.find_child("Cup", true, false)
	t.eq(cup.modulate.a, 0.0, "the cup waits")
	champ.step(0.5)
	t.ok(cup.position.y < 250.0 and cup.modulate.a > 0.0, "at 0.5 s it is sinking in from above (%.0f)" % cup.position.y)
	champ.step(0.45)
	t.ok(champ.page().position != Vector2.ZERO, "at 0.95 s the page quakes")
	champ.step(0.4)
	t.ok(champ.page().position.is_equal_approx(Vector2.ZERO), "…and is still by 1.35 s")
	t.close(cup.position.y, 250.0, 1e-3, "the cup has landed")
	var t1: Control = cp.find_child("Title1", true, false)
	champ.step(0.8)
	t.eq(t1.modulate.a, 0.0, "the new cup waits until 2.2 s")
	champ.step(0.5)
	t.ok(t1.modulate.a > 0.0, "…then pops")
	var frac0 := champ.meter_frac()
	champ.step(0.5)
	t.ok(champ.meter_frac() > frac0, "the bonus bar is filling by 3.15 s (%.2f from %.2f)" % [champ.meter_frac(), frac0])
	t.ok(not champ.ready_to_continue(), "…not yet ready")
	champ.step(0.1)
	t.ok(champ.ready_to_continue(), "CONTINUE from 3.2 s")
	t.eq(champ.continue_button().mouse_filter, Control.MOUSE_FILTER_STOP, "…and the button takes taps")
	champ.step(0.8)
	t.close(champ.meter_frac(), 1.0, 1e-3, "the bar is full by 4 s")
	var cgot := []
	champ.continued.connect(func() -> void: cgot.push_back(true))
	champ.continue_button().pressed.emit()
	champ.continue_button().pressed.emit()
	t.eq(cgot.size(), 1, "the button continues once")
	champ.free()
	# 39a: the standings climb, the IN chip, PLAYOFFS, the matchup, CONTINUE.
	var cl := MatchEndOverlay.new()
	var clp := cl.build(MatchEndCopy.state(_heat(true, {"last_day": true, "day": 14, "in_playoffs_after": true, "clinch_after": true, "seed_after": 3,
		"next_series": {"round": "semifinal", "id": "sf-2v3", "opp": "dustplain", "home": false, "best_of": 3, "seed_you": 3, "seed_opp": 2}})))
	for n in ["Standings", "Row_player", "RecordAfter", "In", "PlayoffLine", "HeadBox", "Sub", "Matchup", "MatchupOppName", "ContinueButton", "Flash", "Rays"]:
		t.ok(clp.find_child(n, true, false) != null, "the clinch page has %s" % n)
	t.ok(clp.find_child("ScoreYou", true, false) == null and clp.find_child("Rewards", true, false) == null, "…and no score or rewards row")
	t.close(cl.row_y("player"), 4.0 * MatchEndOverlay.ROW_H, 1e-3, "you start fifth")
	var chip: Control = clp.find_child("In", true, false)
	var hb: Control = clp.find_child("HeadBox", true, false)
	cl.step(1.0)
	t.close(cl.row_y("player"), 4.0 * MatchEndOverlay.ROW_H, 1e-3, "…still fifth at 1 s")
	cl.step(1.0)
	t.close(cl.row_y("player"), 2.0 * MatchEndOverlay.ROW_H, 1e-3, "…third by 2 s")
	t.eq(chip.modulate.a, 0.0, "the IN chip waits")
	t.eq(hb.modulate.a, 0.0, "…so does PLAYOFFS")
	cl.step(0.3)
	t.ok(chip.modulate.a > 0.0, "the chip pops at 2.1 s")
	cl.step(0.4)
	t.ok(hb.modulate.a > 0.0 and hb.scale.x > 1.0, "PLAYOFFS is slamming in at 2.7 s")
	t.eq(cl.continue_button().mouse_filter, Control.MOUSE_FILTER_IGNORE, "the button ignores taps before 3.6 s")
	cl.step(0.8)
	t.ok(not cl.ready_to_continue(), "not ready at 3.5 s")
	cl.step(0.2)
	t.ok(cl.ready_to_continue() and cl.continue_button().mouse_filter == Control.MOUSE_FILTER_STOP, "ready at 3.7 s")
	cl.free()


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
	t.ok(heat.has("tickets") and not heat.has("coins") and heat.has("xp"), "payout (tickets only) and XP settled")
	t.eq(MatchEndCopy.state(heat)["kind"], "win", "and the page reads it as a win")
	# Season moments (design 39, 2026-10-27): the snapshot carries the table
	# before and after, the clinch, the last-day flag, the season's take.
	t.eq(e["table_before"].size(), 8, "eight rows before")
	t.eq(e["table_after"].size(), 8, "…and after")
	t.ok(not bool(e["last_day"]) and not bool(e["clinch_before"]) and not bool(e["in_playoffs_after"]), "day 1: not the last day, nothing clinched")
	t.eq(int(e["seed_after"]), int(e["place_after"]), "the seed after is the place after")
	t.eq(e["earned"], {"xp": int(heat["xp"]["gained"]), "tickets": int(heat["tickets"])}, "the season's take starts with this match")
	t.eq(int(heat["xp"]["title_gained"]), 0, "no title jump on day 1")
	t.eq(int(heat["xp_now"]), app.xp(), "the XP after the match rides along")
	t.eq(Campaign.earned(app.league_doc("cage")), e["earned"], "…and is saved on the league doc")
	# The last day: a win that makes the playoffs is the CLINCHED page's.
	var d: Dictionary = app.league_doc("cage")
	var cfg: Dictionary = app.league_cfg("cage")
	var guard := 0
	while d["season"]["phase"] == Season.PHASE_REGULAR and int(d["season"]["currentDay"]) < Season.days(d["season"]) and guard < 20:
		Campaign.sim_step(d, cfg)
		guard += 1
	app.save_league_doc(d, "cage")
	app.next_heat = app.league_heat_config(d, cfg)
	var last: Dictionary = app.settle_heat(result)
	var le: Dictionary = last["league_end"]
	t.ok(bool(le["last_day"]), "day 14 is the last day")
	t.eq(le["phase"], Season.PHASE_PLAYOFFS, "…and the playoffs start after it")
	t.eq(bool(le["in_playoffs_after"]), bool(le["seed_after"]) and int(le["seed_after"]) <= 4, "in the playoffs iff seeded top four (seed %d)" % int(le["seed_after"]))
	if bool(le["in_playoffs_after"]):
		t.eq(MatchEndCopy.state(last)["kind"], "clinch", "a last-day win into the playoffs: the CLINCHED page")
		t.ok(le["next_series"].has("opp") and int(le["next_series"]["best_of"]) == 3, "the semifinal matchup rides along")
	else:
		t.eq(MatchEndCopy.state(last)["kind"], "win", "a last-day win that misses: the plain win")
	t.ok(not app.wrap_pending("cage"), "the wrap-up is not owed before the season is done")
	SaveService.put_league_doc("cage", doc_before)
	SaveService.put_cosmetics(cos_before)
	SaveService.put_progress(prog_before)
	SaveService.put_cards(cards_before)
