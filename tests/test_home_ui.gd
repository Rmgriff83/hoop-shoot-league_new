extends RefCounted
## The home screen's chrome (docs/HOME.md): both palettes complete, the card
## face is flat and sharp with an ink border, dark mode persists and flips the
## theme, the league line reads every season state, the ticker copy is
## built from real data with only glyphs the pixel face has, and every
## widget builds off-tree.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func run(t) -> void:
	_theme(t)
	_dark_mode(t)
	_league_line(t)
	_ticker(t)
	_widgets(t)


func _theme(t) -> void:
	for pal in [RetroTheme.LIGHT, RetroTheme.DARK]:
		for token in RetroTheme.TOKENS:
			t.ok(pal.has(token), "palette carries %s" % token)
	var face := RetroTheme.face(RetroTheme.LIGHT["orange"])
	t.eq(face.border_width_left, 0, "no border: the shape is the shadow")
	t.eq(face.shadow_offset, RetroTheme.SHADOW, "a hard offset drop shadow")
	t.ok(face.shadow_size > 0, "the shadow is drawn")
	t.eq(face.corner_radius_top_left, 0, "sharp corners")
	t.eq(RetroTheme.RADIUS, 0, "the theme's radius is zero")
	var pressed := RetroTheme.pressed(RetroTheme.LIGHT["orange"])
	t.ok(pressed.shadow_offset.length() < face.shadow_offset.length(), "a pressed face drops onto its shadow")
	t.eq(RetroTheme.flat(RetroTheme.LIGHT["panel"]).shadow_size, 0, "a strip has no shadow")
	t.eq(RetroTheme.flat(RetroTheme.LIGHT["panel"]).border_width_top, RetroTheme.RULE, "a strip has its rule")
	var sc := ShadowCard.new(RetroTheme.LIGHT["teal"])
	t.eq(sc.color, RetroTheme.LIGHT["teal"], "a shadow card carries its colour")
	t.ok(sc.get_theme_stylebox("normal") is StyleBoxEmpty, "a shadow card draws itself, not a stylebox")
	t.eq(sc.texture_repeat, CanvasItem.TEXTURE_REPEAT_ENABLED, "the dither tiles")
	sc.free()
	var dt := ShadowStyle.dither_tex()
	t.eq(dt.get_size(), Vector2(ShadowStyle.CELL * 2, ShadowStyle.CELL * 2), "dither tile is two cells square")
	var img := dt.get_image()
	t.ok(img.get_pixel(0, 0).a > 0.5 and img.get_pixel(ShadowStyle.CELL, 0).a < 0.5, "the tile is a checkerboard")
	var dots := ShadowStyle.dot_tex().get_image()
	t.eq(dots.get_size(), Vector2i(ShadowStyle.DOT_CELL, ShadowStyle.DOT_CELL), "dot tile is one cell")
	t.ok(dots.get_pixel(0, 0).a > 0.5 and dots.get_pixel(ShadowStyle.DOT_CELL - 1, ShadowStyle.DOT_CELL - 1).a < 0.5, "one dot per cell")
	var m := ShadowStyle.margins(10.0)
	t.eq(m.content_margin_right, 10.0 + ShadowStyle.OFFSET, "content keeps clear of the shadow strip")
	t.ok(ModeCards.practice_card() is ShadowCard, "mode cards are shadow cards")
	var over := RetroTheme.on_scene(Label.new())
	t.eq(over.get_theme_color("font_color"), RetroTheme.SCENE_TEXT, "on-scene text is cream")
	t.eq(over.get_theme_constant("outline_size"), RetroTheme.OUTLINE, "on-scene text carries an ink outline")
	over.free()
	for id in ["cage", "beach", "park", "city"]:
		t.ok(int(CosmeticLibrary.get_arena(id).title_stars) >= 1, "%s rates its difficulty in stars" % id)
	t.eq(int(CosmeticLibrary.get_arena("city").title_stars), 3, "the city is three stars")
	t.eq(int(CosmeticLibrary.get_arena("park").title_stars), 3, "the park is three stars")
	t.eq(int(CosmeticLibrary.get_arena("cage").title_stars), 1, "the cage is one star")
	t.ok(int(CosmeticLibrary.get_arena("beach").title_stars) > int(CosmeticLibrary.get_arena("cage").title_stars), "the beach is harder")
	for icon in ["ball", "coin", "jersey", "multiplayer", "star", "stopwatch", "trophy", "ticket", "lock"]:
		t.ok(ResourceLoader.exists("res://assets/ui/icon_%s.png" % icon), "icon_%s ships" % icon)
	var solid := ShadowCard.solid(RetroTheme.SCENE_TEXT, RetroTheme.TAN, RetroTheme.LIGHT["orange"])
	t.eq(solid.fill, RetroTheme.SCENE_TEXT, "a solid card fills its face")
	t.ok(solid.shadow.r > solid.shadow.b, "with its own shadow colour")
	solid.free()
	var dl := RetroTheme.dithered(Label.new())
	t.ok(dl.material is ShaderMaterial and (dl.material as ShaderMaterial).shader != null, "a dithered label carries the checker shader")
	t.eq(dl.get_theme_constant("shadow_offset_x"), int(RetroTheme.TEXT_SHADOW.x), "its shadow sits at the design offset")
	dl.free()
	t.eq(RetroTheme.thousands(1240), "1,240", "thousands separator")
	t.eq(RetroTheme.thousands(999), "999", "no separator under a thousand")
	t.eq(RetroTheme.thousands(1234567), "1,234,567", "millions")
	t.eq(RetroTheme.thousands(0), "0", "zero")


func _dark_mode(t) -> void:
	var app = _app()
	if app == null:
		return
	# One palette, everywhere (Ross, 2026-10-26): no setting, no switch.
	t.eq(RetroTheme.current(), RetroTheme.DARK, "the game is dark")
	t.ok(not ("dark_mode" in app) and not app.has_method("set_dark_mode"), "App has no dark-mode setting")


func _league_line(t) -> void:
	_summary(t)
	t.eq(ModeCards.league_line({}), "NEW LEAGUE", "no league state → new")
	var cage := LeagueData.league("cage")
	t.eq(ModeCards.league_line({"league": cage, "unlocked": true, "doc": {}}), "NEW LEAGUE", "no campaign → new")
	var locked := {"league": LeagueData.league("beach"), "unlocked": false, "doc": {}}
	t.eq(ModeCards.league_line(locked), "LOCKED · REACH LEVEL 3", "locked line names the level")
	var doc := Campaign.new_doc(cage, 7, 1000)
	var st := {"league": cage, "unlocked": true, "doc": doc}
	t.eq(ModeCards.league_line(st), "SEASON 1 · DAY 1 · TIP OFF", "fresh season, nothing played")
	var result := {"won": true, "player_score": 28, "ai_score": 15, "ot": 0,
		"sides": {"player": {"score": 28, "makes": 20, "swishes": 6, "attempts": 30, "bestStreak": 7, "bonus": 4, "iced": 0},
			"ai": {"score": 15, "makes": 12, "swishes": 2, "attempts": 25, "bestStreak": 3, "bonus": 0, "iced": 1}}}
	Campaign.apply_live_result(doc, cage, result, 2000)
	var line := ModeCards.league_line(st)
	t.ok(line.begins_with("SEASON 1 · DAY 2 · ") and line.ends_with(" PLACE"), "in season: day and place (%s)" % line)
	Campaign.sim_to_playoffs(doc, cage)
	line = ModeCards.league_line(st)
	t.ok(line.begins_with("SEASON 1 · ") and (line.contains("SEMIS") or line.contains("FINAL") or line.contains("OUT")), "playoffs line (%s)" % line)
	doc["season"]["phase"] = Season.PHASE_DONE
	doc["season"]["championId"] = Campaign.PLAYER
	t.eq(ModeCards.league_line(st), "SEASON 1 · CHAMPIONS", "champions")
	doc["season"]["championId"] = "brickport"
	line = ModeCards.league_line(st)
	t.ok(line.begins_with("SEASON 1 · DONE · ") and line.ends_with(" PLACE"), "season over, your place (%s)" % line)


## The LEAGUE card's copy and the floats through every phase.
func _summary(t) -> void:
	var cage := LeagueData.league("cage")
	var fresh := LeagueSummary.card({"league": cage, "unlocked": true, "doc": {}})
	t.eq(fresh["top"], "ARCADE LEAGUE", "the card names the league")
	t.eq(fresh["sub"], "NEW LEAGUE", "a new league says so")
	t.eq(fresh["next_right"], "DAY 1 OF 14", "and counts the season (%s)" % fresh["next_right"])
	var locked := LeagueSummary.card({"league": LeagueData.league("beach"), "unlocked": false, "doc": {}})
	t.eq(locked["sub"], "LOCKED", "a locked league says so")
	t.eq(locked["next_left"], "REACH LEVEL 3", "and names the level")
	t.eq(Array(locked["stats"]).size(), 0, "with no numbers")
	var doc := Campaign.new_doc(cage, 7, 1000)
	var st := {"league": cage, "unlocked": true, "doc": doc}
	var c := LeagueSummary.card(st)
	t.eq(c["sub"], "SEASON 1", "in season: the season")
	t.eq(Array(c["stats"]).size(), 3, "three numbers")
	t.eq(c["stats"][0], {"v": "0-0", "l": "RECORD"}, "record first")
	t.eq(c["stats"][1]["v"], "-", "no place before a game")
	t.eq(c["chip"], ["SEASON 1", "0-0"], "the season chip: the season and the record")
	t.eq(c["done"], false, "not done")
	t.ok(str(c["next_left"]).begins_with("NEXT · "), "the next game (%s)" % c["next_left"])
	t.eq(c["next_right"], "DAY 1 OF 14", "day of the season")
	var up := LeagueSummary.upcoming(doc, cage, 3)
	t.eq(up.size(), 3, "three upcoming cards")
	t.eq(up[0]["day"], "D1", "the first is today")
	t.eq(up[0]["tag"], "TODAY", "tagged")
	t.eq(up[1]["tag"], "", "the next is not")
	t.ok(str(up[0]["name"]).begins_with("@ ") or str(up[0]["name"]).begins_with("VS "), "home or away (%s)" % up[0]["name"])
	var sp := LeagueSummary.spot(doc, cage)
	t.eq(sp["big"], "-", "no spot before a game")
	var result := {"won": true, "player_score": 28, "ai_score": 15, "ot": 0,
		"sides": {"player": {"score": 28, "makes": 20, "swishes": 6, "attempts": 30, "bestStreak": 7, "bonus": 4, "iced": 0},
			"ai": {"score": 15, "makes": 12, "swishes": 2, "attempts": 25, "bestStreak": 3, "bonus": 0, "iced": 1}}}
	Campaign.apply_live_result(doc, cage, result, 2000)
	c = LeagueSummary.card(st)
	t.eq(c["stats"][0]["v"], "1-0", "a win in the record")
	t.ok(str(c["stats"][1]["v"]).is_valid_int(), "PLACE is the bare number (%s)" % c["stats"][1]["v"])
	t.eq(c["chip"][1], "1-0", "the chip's record moved")
	t.eq(c["stats"][2]["v"], "W1", "and the streak")
	t.eq(c["next_right"], "DAY 2 OF 14", "the day moved on")
	sp = LeagueSummary.spot(doc, cage)
	t.eq(sp["cap"], "YOUR SPOT", "the table float")
	t.ok(str(sp["big"]).ends_with("ST") or str(sp["big"]).ends_with("ND") or str(sp["big"]).ends_with("RD") or str(sp["big"]).ends_with("TH"), "a place (%s)" % sp["big"])
	t.ok(str(sp["line1"]).begins_with("1-0 · "), "record and games back (%s)" % sp["line1"])
	var ss := LeagueSummary.season_stats(doc)
	t.eq(ss[1], {"v": "28", "l": "HIGH PTS"}, "season high points")
	Campaign.sim_to_playoffs(doc, cage)
	c = LeagueSummary.card(st)
	t.ok(str(c["sub"]).ends_with("PLAYOFFS") or str(c["sub"]).ends_with("OVER"), "playoffs (%s)" % c["sub"])
	sp = LeagueSummary.spot(doc, cage)
	t.ok(sp["cap"] == "PLAYOFFS" or str(sp["cap"]).begins_with("SEASON"), "the playoff spot (%s)" % str(sp))
	up = LeagueSummary.upcoming(doc, cage, 3)
	t.eq(up.size(), 3, "still three cards")
	doc["season"]["phase"] = Season.PHASE_DONE
	doc["season"]["championId"] = Campaign.PLAYER
	doc["career"]["championships"] = 1
	c = LeagueSummary.card(st)
	t.eq(c["titles"], 1, "a title counts")
	t.eq(c["sub"], "SEASON 1 · OVER", "season over")
	t.eq(c["stats"][2]["v"], "CHAMPS", "champions")
	t.ok(str(c["stats"][1]["v"]).is_valid_int(), "FINISH is the bare number (%s)" % c["stats"][1]["v"])
	t.eq(c["done"], true, "done")
	t.ok(str(c["chip"][1]).ends_with(" · CHAMPS") and c["chip"][0] == "SEASON 1 · OVER", "the done chip (%s)" % str(c["chip"]))
	var done_card := ModeCards.league_card(st, {"name": "BRICK BARON", "town": "OAKRIDGE"})
	t.ok(done_card.find_child("EnterLabel", true, false) == null and done_card.find_child("Chevron", true, false) != null, "a finished season's ENTER is the chevron alone")
	done_card.free()
	t.eq(LeagueSummary.spot(doc, cage)["line2"], "CHAMPIONS", "the spot says so")
	t.eq(LeagueSummary.upcoming(doc, cage, 3)[0]["name"], "SEASON 2", "next season is up")
	t.eq(LeagueSummary.short_name("brickport"), "MO", "a shooter's short name (%s)" % LeagueSummary.team_name("brickport"))


func _ticker(t) -> void:
	var cage := LeagueData.league("cage")
	var doc := Campaign.new_doc(cage, 3, 0)
	var items := HomeTicker.items_from([{"name": "Arcade Cage", "best": 29}, {"name": "Beach", "best": 0}],
		[{"league": cage, "unlocked": true, "doc": doc}], 1240, "Prudence Chime")
	t.ok(items.has("ARCADE CAGE BEST 29"), "best per area")
	t.ok(not "BEACH BEST 0" in items, "no best → no line")
	t.ok(items.has("NEXT UP: PRUDENCE CHIME"), "next opponent")
	t.ok(items.has("1,240 TICKETS"), "ticket balance")
	var league_seen := false
	for it in items:
		if it.begins_with("ARCADE LEAGUE · SEASON 1"):
			league_seen = true
	t.ok(league_seen, "league standing line (%s)" % str(items))
	# Every glyph in every item exists in the display face (system fallback
	# is off, so a missing glyph would render as nothing).
	var font := UiFont.display()
	var missing := []
	for it in items:
		for ch in it:
			if not font.has_char(ch.unicode_at(0)):
				missing.push_back(ch)
	for ch in HomeTicker.SEP + HomeTicker.SEAM:
		if not font.has_char(ch.unicode_at(0)):
			missing.push_back(ch)
	t.eq(missing, [], "every ticker glyph is in the pixel face")
	var few := HomeTicker.items_from([], [], 0)
	t.ok(few.size() >= 3, "sparse data is padded with attract copy")
	var ticker := HomeTicker.new()
	ticker.set_items(items)
	t.ok(ticker.text().contains(HomeTicker.SEAM), "the strip lays the copy around a seam")
	t.ok(ticker.text().count("1,240 TICKETS") == 2, "copy laid twice for a seamless wrap")
	ticker._process(0.5)
	t.ok(ticker._label.position.x < 0.0, "the copy scrolls left")
	ticker.free()


func _widgets(t) -> void:
	var badge := LevelBadge.new()
	t.eq(badge.level_text(), "LVL01", "LVL · 01 to start")
	badge.set_level(7, 0.5)
	t.eq(badge.level_text(), "LVL07", "level pads to two digits")
	# The meter follows the share, not "any XP = full": straight under the
	# bar's PanelContainer the fill was stretched to the whole bar.
	badge.set_level(3, 0.5)
	var fill: ColorRect = badge.find_child("Fill", true, false)
	t.ok(not (fill.get_parent() is Container), "the fill's parent is a plain Control, not a Container")
	t.ok(absf(badge.fill_fraction() - 0.5) < 0.001 and is_equal_approx(fill.anchor_right, 0.5), "half a level = half a meter")
	badge.set_level(3, 0.0)
	t.ok(not fill.visible, "no XP into the level, no fill")
	badge.free()
	# The home board (design 3a, 2026-10-30): a window onto the top fifteen,
	# YOU pinned under it.
	var bp := BoardPreview.new()
	var brows := []
	for i in 20:
		brows.push_back({"rank": "#%d" % (i + 1), "name": "PLAYER %d" % (i + 1), "score": str(40 - i), "me": false})
	bp.set_rows(brows, {"rank": 212, "score": 29})
	t.eq(bp.row_count(), BoardPreview.TOP + 1, "fifteen rows and YOU")
	var you: Control = bp.find_child("RowYou", true, false)
	t.ok(you != null and (you.find_child("Name", true, false) as Label).text == "YOU" and (you.find_child("Pts", true, false) as Label).text == "29", "YOU · 212 · 29 pinned under the window")
	t.eq((you.find_child("Rank", true, false) as Label).text, "212", "…at its rank")
	bp.set_rows(brows.slice(0, 3))
	t.eq(bp.row_count(), 3, "fewer rows, no YOU row without a rank")
	t.ok(not bp.has_you(), "…none pinned")
	bp.set_rows(RanksCopy.local_rows([{"score": 31}, {"score": 20}]))
	t.ok(bp.has_you(), "the device board pins your best")
	t.eq(bp.rows_shown(), BoardPreview.ROWS_SHOWN, "three rows in view by default")
	bp.set_max_height(160.0)
	t.eq(bp.rows_shown(), 1, "a short screen shows fewer rows")
	bp.set_max_height(400.0)
	t.eq(bp.rows_shown(), 3, "…never more than three")
	bp.free()
	for kind in ["locker", "ranks", "shop", "multi"]:
		var ib := IconButton.new(kind)
		t.eq(ib.kind, kind, "%s icon button builds" % kind)
		ib.free()
	var pill := CoinsPill.new()
	pill.set_coins(1240)
	t.eq(pill.text(), "1,240", "coins pill formats thousands")
	pill.free()
	var app = _app()
	if app == null:
		return
	var me := {"name": "Brick Baron", "town": "Oakridge"}
	var league := ModeCards.league_card({"league": LeagueData.league("cage"), "unlocked": true, "doc": {}}, me)
	t.eq((league.find_child("Season", true, false) as Label).text, "NEW LEAGUE", "the season over the card's corner")
	t.eq((league.find_child("PlayerName", true, false) as Label).text, "BRICK BARON", "your name on the card")
	t.eq((league.find_child("PlayerTown", true, false) as Label).text, "OAKRIDGE", "…over your hometown")
	t.ok(league.find_child("Chevron", true, false) != null, "league card has its chevron")
	t.ok(ModeCards.enter_button(league) != null, "and its ENTER LEAGUE button")
	t.ok(ModeCards.enter_button(league).find_child("Shine", true, false) is PreMatchPage.Shine, "…with the dot sweep across it")
	t.ok(league.find_child("Trophies", true, false) == null, "no trophies without a title")
	t.ok(league.find_child("Chips", true, false) == null, "the loadout chips left the card")
	t.eq(league.find_child("Stats", true, false).get_child_count(), 3, "three numbers")
	t.eq(league.custom_minimum_size.y, ModeCards.LEAGUE_H + ShadowCard.OFFSET, "the league card is 310 tall")
	t.eq(ModeCards.LEAGUE_H, 310.0, "…per the design")
	league.free()
	var cage_doc := Campaign.new_doc(LeagueData.league("cage"), 3, 0)
	cage_doc["career"]["championships"] = 7
	var champ := ModeCards.league_card({"league": LeagueData.league("cage"), "unlocked": true, "doc": cage_doc}, me)
	var trophies: Control = champ.find_child("Trophies", true, false)
	t.ok(trophies != null and trophies.get_child_count() == ModeCards.MAX_TROPHIES + 1, "seven titles: five trophies and a +2")
	t.eq((champ.find_child("MoreTitles", true, false) as Label).text, "+2", "…the +2 in gold")
	t.ok(champ.find_child("Trophy0", true, false).find_child("Sparkle", true, false) is ModeCards.Sparkle, "each trophy has its sparkle")
	champ.free()
	var practice := ModeCards.practice_card()
	t.eq((practice.find_child("Icon", true, false) as PixelIcon).icon_name, "icon_barbell", "PRACTICE wears the barbell")
	t.eq(practice.custom_minimum_size.y, ModeCards.PAIR_H + ShadowCard.OFFSET, "the pair is 110 tall")
	practice.free()
	var trial := ModeCards.trial_card(29)
	t.eq(ModeCards.sub_text(trial), "BEST 29", "trial card shows the best")
	trial.free()
	t.eq(ModeCards.sub_text(ModeCards.trial_card(0)), "NO RUNS YET", "no best yet")
	t.eq(ModeCards.sub_text(ModeCards.practice_card()), "NO CLOCK", "practice card")
	var locked_trial := ModeCards.trial_card(29, 3)
	t.ok(locked_trial.disabled and ModeCards.sub_text(locked_trial) == "LOCKED · LEVEL 3", "a locked area's trial card says the level")
	locked_trial.free()
	t.ok(ModeCards.practice_card(3).disabled, "and its practice card is off")
	var with_xp := HomeTicker.items_from([], [], 0, "", 164)
	t.ok(with_xp.has("LEVEL 2 · 64/100 XP"), "the ticker carries the level (%s)" % str(with_xp))
	# The locker page (docs/LOCKER.md, design 31a / 31b, 2026-10-30): the
	# collection — BALLS by rarity, NETS by kind, OWNED / ALL; PLAY PEGGY
	# opens its page; `< BACK` at the foot.
	var cos_before: Dictionary = SaveService.get_cosmetics()
	var cos: Dictionary = SaveService.default_cosmetics()   # the suite's parts start empty (headless)
	cos.merge(SaveService.get_cosmetics(), true)
	cos["tickets"] = 0
	cos["net"] = SaveService.default_nets()
	SaveService.put_cosmetics(cos)
	var locker := LockerPanel.new()
	locker._ready()
	t.eq(locker.tab(), "BALLS", "the locker opens on BALLS")
	t.eq(locker.view(), "OWNED", "…showing what you own")
	var tickets_panel: Control = locker.find_child("Tickets", true, false)
	t.ok(tickets_panel != null, "the big ticket panel sits beside LOCKER")
	t.eq((tickets_panel.find_child("Count", true, false) as Label).text, "0", "…with the balance")
	t.eq((tickets_panel.find_child("Label", true, false) as Label).text, "TICKETS", "…over TICKETS")
	var peggy: Button = locker.find_child("Peggy", true, false)
	t.ok(peggy != null and (peggy.find_child("Word", true, false) as Label).text == "PLAY PEGGY", "PLAY PEGGY sits under the head")
	t.eq((peggy.find_child("Sub", true, false) as Label).text, "WIN BALLS + NETS · 300 TICKETS", "…saying what a play costs")
	t.ok(not (peggy.find_child("Shine", true, false) as Control).visible, "…dull while a drop is out of reach")
	var asked := [false]
	locker.peggy_requested.connect(func() -> void: asked[0] = true)
	peggy.pressed.emit()
	t.ok(asked[0], "…and asks for the PEGGY page")
	t.ok(locker.find_child("Back", true, false) != null and locker.find_child("Close", true, false) == null, "`< BACK` at the foot, no CLOSE")
	var tab_balls: Button = locker.find_child("Tab_BALLS", true, false)
	t.ok(tab_balls != null and tab_balls.text == "BALLS %d" % app.owned_count("ball"), "the BALLS tab counts what you own (%s)" % (tab_balls.text if tab_balls != null else "?"))
	var rows: Array = locker.rows()
	t.ok(rows.has("Ball_classic"), "the classic ball is in the locker (%s)" % str(rows.slice(0, 4)))
	t.ok(not rows.has("Ball_gold") and not rows.has("Hoop_street"), "nothing unowned is listed under OWNED")
	for r in rows:
		t.ok(app.owns("ball", String(r).trim_prefix("Ball_")) or String(r) == "Ball_" + locker._current_id("ball"), "%s is owned" % r)
	t.eq(locker.locked_count(), 0, "no ???? tiles under OWNED")
	var common_group: Control = locker.find_child("Group_common", true, false)
	t.ok(common_group != null, "the balls are grouped by rarity")
	t.eq((common_group.find_child("Level", true, false) as Label).text, "LVL 1", "…each group says its level")
	var commons := 0
	var owned_commons := 0
	var legends_owned := 0
	for cs in CosmeticLibrary.balls():
		var bs := cs as BallSet
		if bs.rarity == "common":
			commons += 1
			if rows.has("Ball_" + bs.id):
				owned_commons += 1
		elif bs.rarity == "legend" and rows.has("Ball_" + bs.id):
			legends_owned += 1
	t.eq((common_group.find_child("Count", true, false) as Label).text, "%d/%d" % [owned_commons, commons], "…and its owned / total")
	if legends_owned == 0:
		t.ok(locker.find_child("Group_legend", true, false) == null, "a rarity you own nothing of stays out under OWNED")
	t.eq((locker.find_child("Meta", true, false) as Label).text, "%d OWNED" % rows.size(), "the count beside OWNED / ALL")
	locker.show_view("ALL")
	t.eq(locker.view(), "ALL", "ALL switches")
	t.eq(locker.locked_count(), CosmeticLibrary.balls().size() - rows.size(), "ALL adds a ???? tile per ball you do not own")
	t.ok(locker.find_child("Group_legend", true, false) != null, "…and every rarity shows")
	t.eq((locker.find_child("Meta", true, false) as Label).text, "%d / %d OWNED" % [rows.size(), CosmeticLibrary.balls().size()], "…with the count out of all")
	locker.show_view("OWNED")
	t.ok(locker.find_child("Head_hoop", true, false) == null, "no HOOPS heading")
	t.ok(not app.try_buy("hoop", "street"), "a hoop cannot be bought while the counter is closed")
	t.ok(app.grant_cosmetic("ball", "gold"), "winning the gold ball")
	locker._fill()
	var gold_tile: ShadowCard = locker.find_child("Ball_gold", true, false)
	t.ok(gold_tile != null and gold_tile.color == HomePage.CREAM, "a won ball joins its group, cream (not in use)")
	var ball_before: String = locker._current_id("ball")
	locker.tap_ball("gold")
	t.eq(locker.armed(), "gold", "the first tap arms it")
	gold_tile = locker.find_child("Ball_gold", true, false)
	t.ok(gold_tile.color == RetroTheme.LIGHT["orange"] and (gold_tile.find_child("Name", true, false) as Label).text == "EQUIP?", "…orange, asking EQUIP?")
	t.eq(locker._current_id("ball"), ball_before, "…and nothing is equipped yet")
	locker.tap_ball("gold")
	t.eq(locker.armed(), "", "the second tap uses it")
	if app.ball_set != null:
		t.eq(app.ball_set.id, "gold", "…the gold ball is in use")
		t.eq(locker.in_use_row(), "Ball_gold", "…and its tile is gold")
		locker.tap_ball("gold")
		t.eq(locker.armed(), "", "a tap on the ball in use does nothing")
		app.select("ball", ball_before)
	else:
		t.eq(locker.in_use_row(), "Ball_classic", "no save (headless): the starter reads as in use")
	locker.tap_ball("gold")
	locker._disarm()
	t.eq(locker.armed(), "", "an armed ball lets go (after ARM_S)")
	# The NETS tab: every net by kind, the dots, HANG IT ON.
	t.ok(locker.find_child("Tab_NETS", true, false) != null, "the NETS tab button exists")
	locker.show_tab("NETS")
	t.eq((locker.find_child("Tab_NETS", true, false) as Button).text, "NETS 2", "the tab counts the stock pair")
	t.eq(locker.rows(), ["Net_cotton", "Net_chain"], "the owned nets, cotton first, then chain")
	t.ok(locker.find_child("Group_cotton", true, false) != null and locker.find_child("Group_chain", true, false) != null, "grouped by kind")
	var cotton_n := 0
	for cs in CosmeticLibrary.nets():
		if (cs as NetSet).kind == "cotton":
			cotton_n += 1
	t.eq(((locker.find_child("Group_cotton", true, false) as Control).find_child("Count", true, false) as Label).text, "1/%d" % cotton_n, "COTTON counts 1 of its nets")
	var areas: Array = app.unlocked_areas()
	var cotton_tile: ShadowCard = locker.find_child("Net_cotton", true, false)
	var dots: Control = cotton_tile.find_child("Dots", true, false)
	t.eq(dots.get_child_count(), areas.size(), "a dot per court you have reached")
	if areas.has("cage"):
		t.ok((dots.get_node("Dot_cage") as LockerPanel.AreaDot).on, "…the cotton's cage dot is gold")
	if areas.has("city"):
		t.ok(not (dots.get_node("Dot_city") as LockerPanel.AreaDot).on, "…its city dot is not (the chain hangs there)")
	t.eq(locker.in_use_row("net"), "Net_cotton", "a net that hangs is gold")
	t.ok(app.grant_cosmetic("net", "jack"), "owning the jack chain")
	locker._fill()
	var jack_tile: ShadowCard = locker.find_child("Net_jack", true, false)
	t.ok(jack_tile != null and jack_tile.color == HomePage.CREAM, "an owned chain joins CHAIN, cream (hung nowhere)")
	locker.tap_net("jack")
	t.eq(locker.open_net(), "jack", "a tap opens its HANG IT ON")
	var hang_panel: Control = locker.find_child("HangPanel", true, false)
	t.ok(hang_panel != null, "…under its row")
	t.eq(((hang_panel.find_child("Title", true, false)) as Label).text, "JACK", "…named")
	t.eq((locker.find_child("Net_jack", true, false) as ShadowCard).color, RetroTheme.LIGHT["orange"], "…the tile orange while open")
	var area_btns := []
	for c in hang_panel.find_children("Area_*", "Button", true, false):
		area_btns.push_back(str(c.name).trim_prefix("Area_"))
	t.eq(area_btns, areas, "…a button per court you have reached, in order")
	if areas.has("city"):
		t.eq(((hang_panel.find_child("Area_city", true, false) as Control).find_child("Sub", true, false) as Label).text, "TAP TO HANG", "…the city's says TAP TO HANG")
		locker.hang("jack", "city")
		t.eq(app.net_set_for("city").id, "jack", "hanging it on the city saves it")
		t.eq(locker.open_net(), "jack", "…HANG IT ON stays open")
		hang_panel = locker.find_child("HangPanel", true, false)
		t.eq(((hang_panel.find_child("Area_city", true, false) as Control).find_child("Sub", true, false) as Label).text, "HANGING", "…and the city's says HANGING")
		t.eq((locker.find_child("Net_chain", true, false) as ShadowCard).color, HomePage.CREAM, "the stock chain came down (one net a court)")
	if areas.has("park"):
		locker.hang("jack", "park")
		t.eq(app.net_set_for("park").id, "jack", "a chain hangs on the park too")
	if areas.has("cage"):
		t.eq(app.net_set_for("cage").id, "cotton", "…the cage untouched")
	locker.tap_net("jack")
	t.eq(locker.open_net(), "", "a second tap closes it")
	t.ok(locker.find_child("HangPanel", true, false) == null, "…and the panel is gone")
	locker.tap_net("jack")
	t.ok(locker.find_child("Shut", true, false) is Button, "HANG IT ON has its X")
	locker.tap_net("jack")
	locker.show_view("ALL")
	t.eq(locker.locked_count(), CosmeticLibrary.nets().size() - locker.rows().size(), "ALL adds a ???? per net you do not own")
	t.eq((locker.find_child("Meta", true, false) as Label).text, "%d / %d OWNED" % [locker.rows().size(), CosmeticLibrary.nets().size()], "…with the count out of all")
	locker.show_view("OWNED")
	# A court not yet reached has no button and no dot.
	var gating_before: bool = app.league_gating
	app.league_gating = true
	locker.tap_net("jack")
	var gated_btns: int = (locker.find_child("HangPanel", true, false) as Control).find_children("Area_*", "Button", true, false).size()
	t.eq(gated_btns, app.unlocked_areas().size(), "HANG IT ON offers only the courts you have reached")
	locker.tap_net("jack")
	app.league_gating = gating_before
	app.select_net_everywhere("cotton")
	app.select_net("city", "chain")
	var names := []
	for l in locker.find_children("Name", "Label", true, false):
		names.push_back(str(l.text))
	for nm in names:
		t.ok(not str(nm).contains("TICKETS"), "no price on the locker (%s)" % nm)
	var closed_ := [false]
	locker.closed.connect(func() -> void: closed_[0] = true)
	(locker.find_child("Back", true, false) as Button).pressed.emit()
	t.ok(closed_[0], "BACK off-tree emits closed at once")
	# The PEGGY page: the cabinet filling the frame, PLAY over it, the credit
	# flow, the ball and net cards.
	PeggyMachine.threaded = false   # the threaded load (and its spinner) is the game's; build at once here
	var page := PeggyPage.new()
	page._ready()
	t.ok(page.machine() != null and page.machine().peg_count() == 84, "the drop machine is built with its 84 pegs")
	t.eq(page.machine().slots().size(), 7, "seven plates are set")
	t.ok(page.find_child("Stage", true, false) != null and page.find_child("Back", true, false) != null, "the machine's stage and `< BACK`")
	t.eq(((page.find_child("Back", true, false) as Control).find_child("Word", true, false) as Label).text, "BACK", "…which says BACK (design 30a, 2026-10-30)")
	t.ok(page.find_child("Tickets", true, false) != null, "the big ticket panel sits in the head")
	var badges := 0
	for c in BeachFx._descendants(page):
		if c is LevelBadge:
			badges += 1
	t.eq(badges, 0, "…and the level chip is gone")
	t.eq(page.body.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the body lets taps through to the joystick and DROP under it")
	t.ok(page.find_child("Close", true, false) == null and page.find_child("Hint", true, false) == null, "no CLOSE, no hint line")
	t.ok(page.play_button() != null and page.play_button().visible and page.play_button().disabled, "with no tickets PLAY shows, greyed")
	var need: Label = page.find_child("Need", true, false)
	t.ok(need != null and need.visible and need.text == "NEED 300 MORE", "…saying how many more (%s)" % (need.text if need != null else "?"))
	t.eq(page.play_button().custom_minimum_size.x, PeggyPage.SMALL_PLAY_W + ShadowStyle.OFFSET, "…the small grey PLAY (30f)")
	t.ok(not (page.play_button().find_child("Shine", true, false) as Control).visible, "…with no shine")
	t.ok(page.machine().locked(), "…and the cap is locked")
	app.grant_tickets(480)
	page._refresh_machine()
	t.ok(not page.play_button().disabled and not need.visible, "with a drop's worth PLAY is live")
	t.eq(page.play_button().custom_minimum_size, PeggyPage.BIG_PLAY + Vector2.ONE * ShadowStyle.OFFSET, "…the big PLAY (30a)")
	t.ok((page.play_button().find_child("Shine", true, false) as Control).visible, "…shining")
	t.eq((page.play_button().find_child("Price", true, false) as Label).text, "300", "…for 300")
	page._on_play()
	t.eq(app.tickets(), 180, "PLAY spends the drop")
	t.ok(page.machine().is_busy() and not page.play_button().visible, "the ticket is flying; PLAY is hidden")
	page.machine()._process(PeggyMachine.FEED_S + 0.1)
	t.ok(page.machine().credit() and app.peggy_credit(), "…and the machine is credited")
	t.ok(not page.play_button().visible, "PLAY stays hidden while a ticket is in")
	page._on_dropped({"slot": 3, "base": "common", "rarity": "common", "kind": "ball", "id": "gold", "refund": 0, "owned_after": 2, "roster_size": 47, "result": {}})
	t.ok(page.prize_card() != null, "a prize pops the card")
	for n in ["Equip", "Keep", "Again"]:
		t.ok(page.prize_card().find_child(n, true, false) != null, "…with %s" % n)
	t.ok((page.prize_card().find_child("Again", true, false) as Button).disabled, "AGAIN needs 300: 180 is short")
	page._dismiss_card()
	t.ok(page.prize_card() == null, "KEEP / EQUIP / AGAIN dismiss it")
	page._show_card({"slot": 1, "base": "rare", "rarity": "rare", "kind": "net", "id": "jack", "refund": 0, "owned_after": 3, "roster_size": 8, "result": {}})
	var card_words := []
	for l in page.prize_card().find_children("*", "Label", true, false):
		card_words.push_back(str(l.text))
	t.ok(card_words.has("NEW NET") and card_words.has("HANG IT ON YOUR COURTS?") and card_words.has("RARE · 3/8 NETS"), "a net card says so (%s)" % str(card_words))
	page._dismiss_card()
	page._show_card({"slot": 0, "base": "epic", "rarity": "epic", "kind": "ball", "id": "tiger", "refund": 0, "owned_after": 3, "roster_size": 47, "result": {}})
	t.ok(page._rays != null, "an epic pull turns the rays")
	page._dismiss_card()
	page.close()
	SaveService.put_cosmetics(cos_before)
	# The league in context: enter without a scene change, build the panel.
	var was_league: String = app.current_league
	t.ok(app.enter_league("cage"), "entering the cage league succeeds")
	t.eq(app.current_league, "cage", "the league is current")
	t.ok(not app.league_doc("cage").is_empty(), "its campaign exists")
	t.ok(not app.enter_league("nope"), "an unknown league is refused")
	var lc := LeagueContext.new()
	lc.setup("cage")
	for tab in LeagueContext.TABS:
		t.ok(lc.find_child("Tab_" + tab, true, false) != null, "league context has the %s tab" % tab)
	t.ok(lc.find_child("Back", true, false) == null, "no back in the tab row (BACK TO HOME is on the home)")
	t.ok(lc.find_child("MatchDot", true, false) is LeagueContext.TabDot, "a gold dot on MATCH while a game waits")
	t.eq(lc.current_tab(), "HEAT", "opens on the match")
	var active: Button = lc.find_child("Tab_HEAT", true, false)
	t.eq((active.find_child("Label", true, false) as Label).text, "MATCH", "the first tab reads MATCH (as a child label over the solid face)")
	t.eq((lc.find_child("Tab_TABLE", true, false) as Button).text, "TABLE", "an inactive tab carries its text")
	t.ok(lc.find_child("Opponent", true, false) != null, "MATCH shows the next opponent")
	t.ok(lc.find_child("PlayHeat", true, false) != null, "MATCH has PLAY")
	t.ok(lc.find_child("SimDay", true, false) == null and lc.find_child("SimAll", true, false) == null, "no sim buttons: every game is played")
	t.ok(lc.find_child("Row_8", true, false) != null, "TABLE lists eight rows")
	t.ok(lc.find_child("Standings", true, false) is ShadowPanel, "the table is a see-through panel")
	t.ok(lc.find_child("Schedule", true, false) != null, "SCHED has its panel")
	t.ok(lc.find_child("OppRecord", true, false) != null and lc.find_child("OppCards", true, false) != null, "the opponent's record and their cards for the game")
	t.ok(lc.find_child("PlayHeat", true, false).find_child("Shine", true, false) != null, "PLAY carries its shine")
	t.ok(lc.find_child("CardSubs", true, false) == null, "CARDS is the shop alone (what you own floats on the home)")
	t.ok(lc.find_child("ShopHead", true, false) != null, "SHOP and its note")
	for card in CardDefs.all():
		t.ok(lc.find_child("Shop_" + str(card["id"]), true, false) != null, "the shop sells %s" % card["id"])
	t.ok(lc.find_child("Career", true, false) != null, "STATS has the career grid")
	# Season rollover from the MATCH pane: START SEASON is a button inside
	# the pane it rebuilds, so refresh() must not free it mid-press. Staged
	# on a copy of the campaign and restored after.
	var kept: Dictionary = app.league_doc("cage").duplicate(true)
	var done: Dictionary = app.league_doc("cage")
	done["season"]["phase"] = "done"
	done["season"]["championId"] = str(done["season"]["schedule"][0]["homeId"]) if not done["season"]["schedule"].is_empty() else "pinewick"
	app.save_league_doc(done, "cage")
	var over := LeagueContext.new()
	over.setup("cage")
	var nxt: Button = over.find_child("NextSeason", true, false)
	t.ok(nxt != null, "a finished season offers START SEASON on the match pane")
	# Season moments (design 39d, 2026-10-27): the card asks the title for
	# the NEW SEASON page instead of rolling the season itself.
	var asked_new := []
	over.new_season_requested.connect(func() -> void: asked_new.push_back(true))
	nxt.pressed.emit()
	t.eq(asked_new.size(), 1, "pressing it asks for the new season")
	t.eq(int(app.league_doc("cage")["year"]), int(kept["year"]), "…and leaves the year alone")
	t.ok(app.wrap_pending("cage"), "a done season owes its wrap-up")
	app.mark_wrap_seen("cage")
	t.ok(not app.wrap_pending("cage"), "…until it is seen")
	var rolled: Dictionary = app.roll_season("cage")
	t.eq(int(rolled["year"]), int(kept["year"]) + 1, "App.roll_season starts the next year")
	t.ok(rolled.has("lastSeason") and int(rolled["lastSeason"]["year"]) == int(kept["year"]), "…keeping the old season's summary for the page")
	over.refresh()
	t.ok(over.find_child("NextSeason", true, false) == null or not is_instance_valid(over.find_child("NextSeason", true, false)), "…the START SEASON card is gone after the refresh")
	t.ok(over.find_child("Opponent", true, false) != null and over.find_child("PlayHeat", true, false) != null, "…and the match pane shows the new season's first opponent, not a blank")
	over.free()
	app.save_league_doc(kept, "cage")
	var tabs := []
	lc.tab_changed.connect(func(tab: String) -> void: tabs.push_back(tab))
	lc._show_tab("STATS")
	t.eq(lc.current_tab(), "STATS", "tabs switch")
	t.eq(tabs, ["STATS"], "and say so")
	lc.go_loadout()
	t.eq(lc.current_tab(), "CARDS", "go_loadout lands on CARDS")
	lc.free()
	app.current_league = was_league
	var panel := SettingsPanel.new()
	panel._ready()
	# The rows scroll (2026-10-24) and a touch that starts on a row scrolls the
	# list: a ShadowCard under a ScrollContainer passes its press up once in the tree.
	var sp: ScrollContainer = panel.find_child("Scroll", true, false)
	t.ok(sp != null and sp.find_child("Rows", true, false) != null, "settings rows sit in a ScrollContainer")
	# (The runner works off-tree — the root joins the tree after _initialize —
	# so the hook is called by hand, as the panels' _ready is.)
	var probe := ScrollContainer.new()
	var probe_col := VBoxContainer.new()
	probe.add_child(probe_col)
	var probe_row := HomePage.button("ROW", Color.WHITE, 16, 40.0)
	probe_col.add_child(probe_row)
	probe_row._enter_tree()
	t.eq(probe_row.mouse_filter, Control.MOUSE_FILTER_PASS, "a button in a scroll list passes its press to the scroller")
	probe.free()
	var loose_box := VBoxContainer.new()
	var loose := HomePage.button("LOOSE", Color.WHITE, 16, 40.0)
	loose_box.add_child(loose)
	loose._enter_tree()
	t.eq(loose.mouse_filter, Control.MOUSE_FILTER_STOP, "…a button outside one keeps the press")
	loose_box.free()
	t.eq(int(ProjectSettings.get_setting("gui/common/default_scroll_deadzone", 0)), 18, "a tap wobbles 18 px before the list scrolls")
	# Settings v2 (design 42a, 2026-10-25): GAME pickers, switches, the PLAYER card.
	t.ok(panel.find_child("ShotHelp", true, false) != null, "settings has shot help")
	t.eq((panel.find_child("ShotHelp", true, false).find_child("Options", false, false) as Control).get_child_count(), 3, "SHOT HELP shows its three choices")
	t.eq(panel.picked("ShotHelp"), str(_app().shot_help), "…the saved one gold")
	var was_shot: int = _app().shot_help
	(panel.find_child("ShotHelp_0", true, false) as ShadowCard).pressed.emit()
	t.eq([_app().shot_help, panel.picked("ShotHelp")], [0, "0"], "a tap on OFF picks it")
	t.eq((panel.find_child("ShotHelp", true, false).get_node("Head/Sub") as Label).text, "NO AIM HELP", "…and the sub-line says what it does")
	_app().set_shot_help(was_shot)
	var was_diff: String = _app().ai_difficulty
	_app().set_ai_difficulty("normal")
	t.ok(panel.has_difficulty(), "settings has the AI DIFFICULTY picker")
	(panel.find_child("Difficulty_hard", true, false) as ShadowCard).pressed.emit()
	t.eq([_app().ai_difficulty, panel.picked("Difficulty")], ["hard", "hard"], "a tap on HARD picks it")
	t.eq(str(SaveService.get_settings().get("aiDifficulty", "")), "hard", "…and the settings part remembers")
	_app().set_ai_difficulty(was_diff)
	var was_side: String = _app().hud_side
	t.ok(panel.has_hud_side(), "settings has the HUD SIDE picker")
	(panel.find_child("HudSide_right", true, false) as ShadowCard).pressed.emit()
	t.eq([_app().hud_side, panel.picked("HudSide")], ["right", "right"], "RIGHT moves the toasts and the note")
	t.eq(str(SaveService.get_settings().get("hudSide", "")), "right", "…and the settings part remembers")
	_app().set_hud_side(was_side)
	t.ok(panel.find_child("DarkMode", true, false) == null, "no DARK MODE row")
	# SOUND (2026-10-27): MUSIC and SOUND EFFECTS switches, each a bus mute.
	t.ok(panel.has_sound() and panel.find_child("SoundPanel", true, false) != null, "settings has the SOUND panel")
	var was_music: bool = _app().music_sound
	var was_sfx: bool = _app().sfx_sound
	_app().set_music_sound(true)
	_app().set_sfx_sound(true)
	(panel.find_child("Music", true, false) as Button).pressed.emit()
	t.ok(not _app().music_sound and not panel.switch_on("Music"), "a tap on MUSIC turns it off, the switch following")
	t.eq(SaveService.get_settings().get("musicSound", null), false, "…the settings part remembers")
	t.ok(not Sfx.music_sound() and Sfx.sfx_sound(), "…the music bus is muted, the sfx bus is not")
	(panel.find_child("Sfx", true, false) as Button).pressed.emit()
	t.ok(not _app().sfx_sound and not panel.switch_on("Sfx"), "a tap on SOUND EFFECTS turns it off")
	t.eq(SaveService.get_settings().get("sfxSound", null), false, "…the settings part remembers")
	t.ok(not Sfx.sfx_sound(), "…and the sfx bus is muted")
	(panel.find_child("Music", true, false) as Button).pressed.emit()
	t.ok(_app().music_sound and panel.switch_on("Music") and Sfx.music_sound(), "a second tap on MUSIC turns it back on")
	_app().set_music_sound(was_music)
	_app().set_sfx_sound(was_sfx)
	t.eq(panel.has_tuning(), OS.is_debug_build(), "tuning switch only in a debug build")
	t.eq(panel.has_gates(), OS.is_debug_build(), "the LEVEL GATES switch only in a debug build")
	if OS.is_debug_build():
		var was_gating: bool = _app().league_gating
		(panel.find_child("Gates", true, false) as Button).pressed.emit()
		t.eq(_app().league_gating, not was_gating, "tapping flips the gates")
		t.eq(panel.switch_on("Gates"), _app().league_gating, "…and the switch follows")
		t.eq(bool(SaveService.get_tuning().get("gates", false)), _app().league_gating, "…and the tuning part remembers")
		_app().set_league_gating(was_gating)
	# PLAYER: the gold card and its pencil.
	t.ok(panel.has_player() and panel.find_child("PlayerCard", true, false) != null, "the PLAYER card")
	t.ok(not panel.edit_open(), "NAME / HOMETOWN wait behind the pencil")
	(panel.find_child("Edit", true, false) as ShadowCard).pressed.emit()
	t.ok(panel.edit_open(), "the pencil opens them")
	var ne: LineEdit = panel.find_child("NameEdit", true, false)
	var te: LineEdit = panel.find_child("TownEdit", true, false)
	ne.text = ""
	ne.text_changed.emit("glass  wizard!")
	t.eq(ne.text, "GLASS WIZARD", "the name field tidies as you type")
	t.ok(panel.card_text().begins_with("GLASS WIZARD"), "…and the card follows")
	te.text = ""
	te.text_changed.emit("")
	(panel.find_child("Save", true, false) as ShadowCard).pressed.emit()
	t.eq(panel.message(), "PICK A HOMETOWN", "SAVE checks the hometown")
	t.ok(panel.edit_open(), "…and stays open")
	ne.text = "AB"
	(panel.find_child("Save", true, false) as ShadowCard).pressed.emit()
	t.eq(panel.message(), "NAME NOT ALLOWED · A-Z, 0-9, 3-24", "…and the name")
	(panel.find_child("CloseEdit", true, false) as ShadowCard).pressed.emit()
	t.ok(not panel.edit_open() and panel.message() == "", "CLOSE drops the changes")
	t.eq(ne.text, str(Net.account().get("name", "")), "…the name back to the saved one")
	var link_row: ShadowCard = panel.find_child("PlatformLink", true, false)
	t.ok(link_row != null and not link_row.visible, "the platform link row exists but hides behind the null backend")
	# DANGER ZONE.
	t.ok(panel.find_child("MoveToPhone", true, false) != null and panel.find_child("DangerZoneHead", true, false) != null, "MOVE TO NEW PHONE under DANGER ZONE")
	(panel.find_child("EnterCode", true, false) as ShadowCard).pressed.emit()
	t.ok((panel.find_child("CodeRow", true, false) as Control).visible, "ENTER CODE opens the code field")
	t.eq(panel.row_sub("EnterCode"), "TYPE THE CODE FROM YOUR OLD PHONE", "…and says so")
	(panel.find_child("Claim", true, false) as ShadowCard).pressed.emit()
	t.eq(panel.row_sub("EnterCode"), "A CODE IS 8 LETTERS", "CLAIM checks the length")
	var del_row: ShadowCard = panel.find_child("DeleteAccount", true, false)
	t.ok(del_row != null and (del_row.find_child("Top", true, false) as Label).text == "DELETE ACCOUNT", "DELETE ACCOUNT row (Apple 5.1.1(v))")
	del_row.pressed.emit()
	t.ok(panel.delete_armed() and (del_row.find_child("Top", true, false) as Label).text.begins_with("TAP AGAIN"), "the first tap only arms it")
	t.ok(panel.find_child("Close", true, false) == null and panel.find_child("Back", true, false) != null, "the back square is CLOSE now")
	t.ok(panel.find_child("Credits", true, false) is ShadowCard, "CREDITS under MORE")
	var settings_closed := []
	panel.closed.connect(func() -> void: settings_closed.push_back(true))
	panel.close()
	t.eq(settings_closed.size(), 1, "CLOSE off-tree emits closed at once")
