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
	for id in ["cage", "beach"]:
		t.ok(str(CosmeticLibrary.get_arena(id).title_tier) != "", "%s names its difficulty" % id)
	t.eq(CosmeticLibrary.get_arena("cage").title_tier, "EASY LEVEL", "the cage is the easy level")
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
	t.eq(ModeCards.league_line({}), "NEW LEAGUE", "no league state → new")
	var cage := LeagueData.league("cage")
	t.eq(ModeCards.league_line({"league": cage, "unlocked": true, "doc": {}}), "NEW LEAGUE", "no campaign → new")
	var locked := {"league": LeagueData.league("beach"), "unlocked": false, "doc": {}}
	t.eq(ModeCards.league_line(locked), "LOCKED · TOP 4 IN THE ARCADE LEAGUE", "locked line names the rule")
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
	t.eq(badge.level_text(), "LVL01", "placeholder LVL01")
	badge.set_level(7, 0.5)
	t.eq(badge.level_text(), "LVL07", "level pads to two digits")
	badge.free()
	for kind in ["locker", "ranks", "shop"]:
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
	var league := ModeCards.league_card({"league": LeagueData.league("cage"), "unlocked": true, "doc": {}})
	t.eq(ModeCards.sub_text(league), "NEW LEAGUE", "league card sub-line")
	t.ok(league.find_child("Chevron", true, false) != null, "league card has its chevron")
	league.free()
	var trial := ModeCards.trial_card(29)
	t.eq(ModeCards.sub_text(trial), "BEST 29", "trial card shows the best")
	trial.free()
	t.eq(ModeCards.sub_text(ModeCards.trial_card(0)), "NO RUNS YET", "no best yet")
	t.eq(ModeCards.sub_text(ModeCards.practice_card()), "NO CLOCK", "practice card")
	# The locker lists the owned balls and sets one.
	var locker := LockerPanel.new()
	locker._ready()
	var rows: Array = locker.rows()
	t.ok(rows.has("Ball_classic"), "the classic ball is in the locker (%s)" % str(rows))
	t.eq(rows.size(), CosmeticLibrary.balls().size() + CosmeticLibrary.hoops().size(), "every ball and hoop is listed: owned to equip, the rest to buy")
	t.ok(rows.has("Ball_gold") and rows.has("Hoop_street"), "unowned sets are on the counter")
	var gold: Button = locker.find_child("Ball_gold", true, false)
	t.ok(gold != null and gold.text.contains("TICKETS"), "an unowned set shows its ticket price (%s)" % (gold.text if gold != null else "?"))
	t.ok(gold != null and gold.disabled == (app.tickets() < 1500), "buying is gated on tickets")
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
	var panel := SettingsPanel.new()
	panel._ready()
	t.ok(panel.has_dark_mode(), "settings has the dark-mode row")
	t.ok(panel.find_child("ShotHelp", true, false) != null, "settings has shot help")
	t.eq(panel.has_tuning(), OS.is_debug_build(), "tuning toggle only in a debug build")
	panel.close()
