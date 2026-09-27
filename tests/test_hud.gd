extends RefCounted
## The solo-mode HUD (docs/HOME.md → HUD): HudCopy's banner split, clock
## and BEST chip; every banner word in the display face; the Hud built
## off-tree (the clock or PRACTICE card, the score card, the BEST chip
## flipping to NEW BEST); the PauseMenu (RESUME / SHOT HELP / QUIT, the
## value cycles); the pause icon; the toggle switch.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func run(t) -> void:
	_copy(t)
	_widgets(t)


func _copy(t) -> void:
	t.eq(HudCopy.split_banner("SWISH +2"), ["SWISH", "+2"], "a trailing +N is the bottom line")
	t.eq(HudCopy.split_banner("+1"), ["+1", ""], "a bare +N stays on top")
	t.eq(HudCopy.split_banner("HEATING UP"), ["HEATING", "UP"], "two words split")
	t.eq(HudCopy.split_banner("TIME!"), ["TIME!", ""], "one word on top")
	t.eq(HudCopy.split_banner("GO!"), ["GO!", ""], "GO!")
	t.eq(HudCopy.split_banner("BUZZER BEATER +3"), ["BUZZER BEATER", "+3"], "the buzzer beater's points drop")
	t.eq(HudCopy.split_banner("IN AND OUT"), ["IN AND", "OUT"], "three words break after two")
	t.eq(HudCopy.split_banner("✨ SWISH +2"), ["SWISH", "+2"], "emoji are dropped")
	t.ok(HudCopy.is_note("30s MODE: spots shuffle every 10 s"), "a long message is a note")
	t.ok(HudCopy.is_note("BUZZER BEATER +3"), "BUZZER BEATER is too long for the big line")
	t.ok(not HudCopy.is_note("HEATING UP"), "HEATING UP is not")
	t.eq(HudCopy.clock_text(41.66), "41.7", "the clock")
	t.eq(HudCopy.clock_text(-0.2), "0.0", "never negative")
	t.eq(HudCopy.clock_text(12.3, 1), "OT1 12.3", "an OT tag")
	t.ok(HudCopy.clock_hot(9.9) and not HudCopy.clock_hot(10.1), "gold in the last ten seconds")
	t.eq(HudCopy.best_chip(29, 12), {"label": "BEST", "val": "29"}, "behind the best")
	t.eq(HudCopy.best_chip(29, 31), {"label": "NEW BEST", "val": "31"}, "past it")
	t.eq(HudCopy.best_chip(0, 0), {"label": "BEST", "val": "-"}, "no best yet")
	t.eq(HudCopy.best_chip(0, 1), {"label": "NEW BEST", "val": "1"}, "the first point is a new best")
	t.eq(HudCopy.shot_help_value(0), "OFF", "shot help off")
	t.eq(HudCopy.shot_help_value(2), "NUMBERS + ARC", "shot help full")
	var display := UiFont.display()
	for s in ["SWISH +2", "HEATING UP", "TIME!", "GO!", "IN AND OUT", "BUZZER BEATER +3", "NEW BEST", "30S MODE", "OT1 12.3", "SHOT HELP", "QUIT TO TITLE", "PAUSED", "RESUME"]:
		for ch in s:
			t.ok(display.has_char(ch.unicode_at(0)), "glyph '%s' in the display face" % ch)


func _widgets(t) -> void:
	var app = _app()
	if app == null:
		return
	var hud := Hud.new()
	hud._ready()
	t.ok(hud.find_child("Clock", true, false).visible and not hud.find_child("Practice", true, false).visible, "a trial shows the clock card")
	t.ok(hud.find_child("ScoreCard", true, false) is ShadowPanel, "the score card")
	t.ok(not hud.find_child("BestChip", true, false).visible, "no BEST chip until set")
	hud.set_best(29)
	t.eq(hud.best_text(), "BEST 29", "the saved best")
	hud.set_score(31)
	t.eq(hud.best_text(), "NEW BEST 31", "passing it flips the chip")
	hud.update_clock(41.66, 0.0, TimeTrial.PHASE_RUNNING)
	t.eq(hud.clock_text(), "41.7", "the clock text")
	hud.update_clock(2.0, 3.0, TimeTrial.PHASE_COUNTDOWN)
	t.ok(hud.find_child("Countdown", true, false).visible and (hud.find_child("Countdown", true, false) as Label).text == "3", "the countdown shows its digit")
	t.ok((hud.find_child("Countdown", true, false) as Label).material is ShaderMaterial, "dithered")
	hud.set_practice(true, "BEACH")
	t.ok(hud.find_child("Practice", true, false).visible and not hud.find_child("Clock", true, false).visible, "practice swaps in its card")
	t.eq((hud.find_child("PracticeLabel", true, false) as Label).text, "BEACH", "with the area's label")
	hud.free()
	var pm := PauseMenu.new()
	pm._ready()
	for nm in ["Resume", "ShotHelp", "Quit"]:
		t.ok(pm.find_child(nm, true, false) is ShadowCard, "the pause menu has %s" % nm)
	var was: int = app.shot_help
	pm.open()
	t.eq(pm.shot_help_text(), HudCopy.shot_help_value(was), "the shot-help value reads the setting")
	(pm.find_child("ShotHelp", true, false) as Button).pressed.emit()
	t.eq(pm.shot_help_text(), HudCopy.shot_help_value((was + 1) % App.SHOT_HELP_LABELS.size()), "a tap cycles it")
	app.set_shot_help(was)
	var resumed := []
	pm.resumed.connect(func() -> void: resumed.push_back(true))
	(pm.find_child("Resume", true, false) as Button).pressed.emit()
	t.eq(resumed.size(), 1, "RESUME emits")
	pm.free()
	var pb := IconButton.new("pause")
	t.eq(pb.kind, "pause", "the pause icon button")
	pb.free()
	var sw := ToggleSwitch.new(false)
	t.ok(not sw.on, "a switch starts off")
	sw.set_on(true)
	t.ok(sw.on, "and flips on")
	sw.free()
