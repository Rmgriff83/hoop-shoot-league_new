extends RefCounted
## The cage's league ribbon board: the text it builds, and above all that every
## character of it can actually be DRAWN.
##
## The LED is a 3x5 font holding only 0-9, A-Z, space and `! : + - x *`.
## LedBoard._draw_text drops anything else silently, so an unrenderable
## character is an invisible bug, not a crash — and every league formatter that
## already existed (the old sash line, the chalkboard, the league hub) is full
## of `·`, `★`, `✓`, `✗`, `→` and emoji. That is why the ribbon builds its own
## strings and why the font-safety sweep below is the most important assertion
## in this file.


func run(t) -> void:
	_abbreviations(t)
	_font_safety(t)
	_regular_season(t)
	_playoffs(t)
	_arcade(t)


func _abbreviations(t) -> void:
	t.eq(TickerText.abbr("player"), "YOU", "the player is YOU, not a hometown")
	t.eq(TickerText.abbr("brickport"), "BRI", "a one-word id takes its first three")
	t.eq(TickerText.abbr("thunder-mesa"), "THU", "a hyphen is skipped, not counted")
	t.eq(TickerText.abbr("ab"), "ABX", "a short id is padded to three")
	# Every team in the shipped league must get a distinct, drawable code, or
	# the standings rows become ambiguous.
	var cfg := LeagueData.league("cage")
	var seen := {}
	for id in LeagueData.team_ids(cfg):
		var a := TickerText.abbr(str(id))
		t.eq(a.length(), 3, "%s -> a 3-letter code (%s)" % [id, a])
		t.ok(not seen.has(a), "%s's code %s is unique in the league" % [id, a])
		seen[a] = true


## The sweep: nothing the ribbon can emit may contain an undrawable character.
func _font_safety(t) -> void:
	t.ok(TickerText.is_font_safe("YOU 1ST 3-2"), "plain text is safe")
	t.ok(not TickerText.is_font_safe("4th · 3-3"), "the old sash separator is NOT safe")
	t.ok(not TickerText.is_font_safe("BOS ★"), "nor a star")
	var cfg := LeagueData.league("cage")
	var ids := LeagueData.team_ids(cfg)
	var doc := {"season": Season.create(cfg, ids, 1, 3)}
	var all := TickerText.league_items(cfg, doc, 24, 19, "brickport")
	all.append_array(TickerText.arcade_items(1240))
	all.push_back(TickerText.SEP)
	t.ok(all.size() > 8, "the ribbon has something to say (%d segments)" % all.size())
	var bad := ""
	for seg in all:
		if not TickerText.is_font_safe(seg):
			bad = seg
	t.eq(bad, "", "every ribbon segment renders on the LED font")
	# And each fits the 48-column board with room to read.
	var too_long := ""
	for seg in all:
		if LedBoard.text_cols(seg) > 120:
			too_long = seg
	t.eq(too_long, "", "no segment is absurdly long for a ribbon (%s)" % too_long)


func _regular_season(t) -> void:
	var cfg := LeagueData.league("cage")
	var ids := LeagueData.team_ids(cfg)
	var doc := {"season": Season.create(cfg, ids, 1, 3)}
	var items := TickerText.league_items(cfg, doc, 24, 19, "brickport")
	t.ok(str(items[0]).length() > 0, "the league name leads")
	var joined := " ".join(items)
	t.ok(joined.contains("YOU 24"), "the live score is on the ribbon")
	t.ok(joined.contains("BRI 19"), "with the opponent's code")
	# One standings row per team: "<rank> <ABB> <w>-<l>".
	var rows := 0
	for seg in items:
		var parts := str(seg).split(" ", false)
		if parts.size() == 3 and str(parts[0]).is_valid_int() and str(parts[1]).length() == 3 \
				and str(parts[2]).contains("-"):
			rows += 1
	t.eq(rows, ids.size(), "a standings row for all %d teams (%d)" % [ids.size(), rows])


func _playoffs(t) -> void:
	var cfg := LeagueData.league("cage")
	var ids := LeagueData.team_ids(cfg)
	var state := Season.create(cfg, ids, 1, 3)
	state["phase"] = Season.PHASE_PLAYOFFS
	state["series"] = [Playoffs.make_series("final", "final", Campaign.PLAYER, "brickport", 5)]
	state["series"][0]["highWins"] = 2
	state["series"][0]["lowWins"] = 1
	var items := TickerText.league_items(cfg, {"season": state}, 10, 8, "brickport")
	var joined := " ".join(items)
	t.ok(joined.contains("FINAL GAME 4"), "the playoff round and game number (%s)" % joined)
	t.ok(joined.contains("SERIES 2-1"), "and the series score")
	t.ok(TickerText.is_font_safe(joined), "playoff text is drawable too")


func _arcade(t) -> void:
	var items := TickerText.arcade_items(1240)
	t.ok(" ".join(items).contains("HIGH SCORE 1240"), "attract copy carries the best score")
	t.ok(not " ".join(TickerText.arcade_items(0)).contains("HIGH SCORE"), "no best score, no boast")
	t.ok(TickerText.arcade_items(0).size() > 0, "the ribbon is never empty outside league play")
