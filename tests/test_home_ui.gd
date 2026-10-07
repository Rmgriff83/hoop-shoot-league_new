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
	for id in ["cage", "beach", "city"]:
		t.ok(int(CosmeticLibrary.get_arena(id).title_stars) >= 1, "%s rates its difficulty in stars" % id)
	t.eq(int(CosmeticLibrary.get_arena("city").title_stars), 3, "the city is three stars")
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
	var was: bool = app.dark_mode
	app.set_dark_mode(true)
	t.eq(app.dark_mode, true, "dark mode set")
	t.eq(RetroTheme.current(), RetroTheme.DARK, "the theme follows the setting")
	var svc = Engine.get_main_loop().root.get_node_or_null("SaveService")
	if svc != null:
		t.eq(bool(svc.get_settings().get("darkMode", false)), true, "dark mode persists in settings")
	app.set_dark_mode(false)
	t.eq(RetroTheme.current(), RetroTheme.LIGHT, "back to the cream page")
	app.set_dark_mode(was)


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
	var done_card := ModeCards.league_card(st, [null, null, null])
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
	badge.free()
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
	var league := ModeCards.league_card({"league": LeagueData.league("cage"), "unlocked": true, "doc": {}}, [null, null, null])
	t.eq(ModeCards.sub_text(league), "NEW LEAGUE", "league card sub-line")
	t.ok(league.find_child("Chevron", true, false) != null, "league card has its chevron")
	t.ok(ModeCards.enter_button(league) != null, "and its ENTER LEAGUE button")
	t.ok(league.find_child("Trophies", true, false) == null, "no trophies without a title")
	t.eq(league.find_child("Chips", true, false).get_child_count(), 3, "three loadout chips")
	t.eq(league.find_child("Stats", true, false).get_child_count(), 3, "three numbers")
	league.free()
	var cage_doc := Campaign.new_doc(LeagueData.league("cage"), 3, 0)
	cage_doc["career"]["championships"] = 7
	var champ := ModeCards.league_card({"league": LeagueData.league("cage"), "unlocked": true, "doc": cage_doc}, ["fire7", null, null])
	var trophies: Control = champ.find_child("Trophies", true, false)
	t.ok(trophies != null and trophies.get_child_count() == ModeCards.MAX_TROPHIES + 1, "seven titles: five trophies and a +2")
	t.ok(champ.find_child("Titles", true, false) != null and (champ.find_child("Titles", true, false) as Label).text == "7 TITLES", "the header counts them")
	t.ok(champ.find_child("Chips", true, false).get_child(0) is ModeCards.Chip, "an equipped card is a chip")
	t.ok(not (champ.find_child("Chips", true, false).get_child(1) is ModeCards.Chip), "an empty slot is the dashed plus")
	champ.free()
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
	# The locker: PEGGY first, the BALLS tab lists every ball (owned equip,
	# the rest show their rarity) and the hoops (owned equip, unowned buy).
	var locker := LockerPanel.new()
	locker._ready()
	t.eq(locker.tab(), "PEGGY", "the locker opens on PEGGY")
	t.ok(locker.machine() != null and locker.machine().peg_count() == 81, "the drop machine is built with its 81 pegs")
	t.eq(locker.machine().slots().size(), 7, "seven plates are set")
	t.ok(locker.find_child("Hint", true, false) != null, "the deck has its hint line")
	t.ok(locker.stick() != null and locker.stick().deflection() == 0.0, "the joystick rests at centre")
	var aim0: float = locker.machine().aim()
	locker.stick()._set_from_px(PeggyStick.TRACK.x)
	t.ok(locker.stick().deflection() > 0.9, "pushing the stick right deflects it (%.2f)" % locker.stick().deflection())
	locker._process(0.5)
	t.ok(locker.machine().aim() > aim0, "…and the aim follows while it is held")
	locker.stick()._held = false
	locker.stick()._process(1.0)
	t.eq(locker.stick().deflection(), 0.0, "let go, the stick springs back")
	locker.meter().set_progress(150, 2)
	t.ok(locker.meter().label.begins_with("150/200 XP TO EPIC"), "the meter counts XP to the epic plates (%s)" % locker.meter().label)
	t.close(locker.meter().frac, 0.75, 1e-6, "…three quarters of the way")
	locker.meter().set_progress(250, 3)
	t.ok(locker.meter().label.begins_with("50/200 XP TO LEGEND"), "past the epic gate it counts to legend (%s)" % locker.meter().label)
	locker.meter().set_progress(900, 10)
	t.eq(locker.meter().label, "EVERY RARITY OPEN", "at level 5+ the meter is full")
	t.ok(locker.find_child("Tab_BALLS", true, false) != null, "the BALLS tab button exists")
	locker.show_tab("BALLS")
	var rows: Array = locker.rows()
	t.ok(rows.has("Ball_classic"), "the classic ball is in the locker (%s)" % str(rows.slice(0, 4)))
	t.eq(rows.size(), CosmeticLibrary.balls().size(), "every ball is listed, and nothing else")
	t.ok(rows.has("Ball_gold") and not rows.has("Hoop_street"), "unowned balls are on the counter; hoops are not (the counter is closed for now)")
	t.ok(locker.find_child("Head_hoop", true, false) == null, "no HOOPS heading")
	t.ok(not app.try_buy("hoop", "street"), "a hoop cannot be bought while the counter is closed")
	var gold: Button = locker.find_child("Ball_gold", true, false)
	var gold_tag: Label = gold.find_child("Tag", true, false) if gold != null else null
	t.ok(gold != null and gold.disabled, "an unowned ball cannot be tapped: it is won on PEGGY")
	t.ok(gold_tag != null and gold_tag.text == "EPIC", "an unowned ball shows its rarity (%s)" % (gold_tag.text if gold_tag != null else "?"))
	if app.ball_set != null:
		t.eq(locker.in_use_row(), "Ball_" + str(app.ball_set.id), "the ball in use is tagged")
		var before: String = app.ball_set.id
		t.ok(app.select("ball", "classic"), "selecting an owned ball succeeds")
		locker._fill()
		t.eq(locker.in_use_row(), "Ball_classic", "the locker follows the selection")
		app.select("ball", before)
	else:
		t.eq(locker.in_use_row(), "Ball_classic", "no save (headless): the starter reads as in use")
	locker.close()
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
	t.ok(lc.find_child("Back", true, false) != null, "league context has its back button")
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
	t.ok(lc.find_child("Slot_2", true, false) == null, "the equipped slots are not in the pane (they float on the home)")
	t.ok(lc.find_child("Spares", true, false) != null, "CARDS shows the spares")
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
	nxt.pressed.emit()
	t.eq(int(app.league_doc("cage")["year"]), int(kept["year"]) + 1, "pressing it starts the next year")
	t.ok(over.find_child("NextSeason", true, false) == null or not is_instance_valid(over.find_child("NextSeason", true, false)), "…the START SEASON card is gone")
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
	t.eq(lc.card_sub(), "LOADOUT", "on the loadout")
	var closed := []
	lc.closed.connect(func() -> void: closed.push_back(true))
	(lc.find_child("Back", true, false) as Button).pressed.emit()
	t.eq(closed.size(), 1, "back emits closed")
	lc.free()
	app.current_league = was_league
	var panel := SettingsPanel.new()
	panel._ready()
	t.ok(panel.has_dark_mode(), "settings has the dark-mode row")
	t.ok(panel.find_child("ShotHelp", true, false) != null, "settings has shot help")
	t.eq(panel.has_tuning(), OS.is_debug_build(), "tuning toggle only in a debug build")
	panel.close()
