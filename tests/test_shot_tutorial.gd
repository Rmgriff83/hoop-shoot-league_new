extends RefCounted
## The first-shot tutorial (design 38a): the copy, the verdicts, the demo
## clock, the gate, and the overlay's card over a stub screen — off-tree.


class StubScreen extends RefCounted:
	var calls: Array = []
	func ball_rest_point() -> Vector2:
		return Vector2(360, 1050)
	func demo_press() -> bool:
		calls.push_back("press")
		return true
	func demo_drag(_pos: Vector2) -> void:
		calls.push_back("drag")
	func demo_windup(_pull: float) -> void:
		calls.push_back("windup")
	func demo_shoot(_angle: float) -> void:
		calls.push_back("shoot")
	func demo_drop() -> void:
		calls.push_back("drop")
	func demo_readout(_arc: float, _pct: float) -> void:
		calls.push_back("readout")
	func demo_readout_clear() -> void:
		pass
	func tutorial_grabbed() -> bool:
		return false
	func tutorial_ball_flying() -> bool:
		return false


func run(t) -> void:
	var app = Engine.get_main_loop().root.get_node("App")
	var save = Engine.get_main_loop().root.get_node("SaveService")
	var was_settings: Dictionary = save.get_settings()
	# The copy.
	t.eq(ShotTutorialCopy.step_count(), 5, "five steps")
	t.eq(ShotTutorialCopy.STEPS.map(func(s): return s["title"]), ["HOW TO SHOOT", "PULL DOWN TO AIM", "FLICK UP TO SHOOT", "READ YOUR SHOT", "YOUR TURN"], "…in the design's order")
	t.ok(ShotTutorialCopy.is_live(4) and not ShotTutorialCopy.is_live(3), "only the last step is live")
	t.ok(bool(ShotTutorialCopy.step(3).get("legend", false)), "READ YOUR SHOT carries the legend")
	t.eq(ShotTutorialCopy.result("swish"), {"title": "SWISH!", "body": "That's it. You're ready to play.", "color": ShotTutorialCopy.GREEN}, "a swish's result")
	t.eq(ShotTutorialCopy.result("long")["title"], "LONG", "a long miss")
	t.ok(ShotTutorialCopy.result("rim")["color"] == ShotTutorialCopy.AMBER, "a miss reads in amber")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in ShotTutorialCopy.strings():
		for ch in s:
			t.ok(display.has_char(ch.unicode_at(0)) or bold.has_char(ch.unicode_at(0)), "glyph '%s' (%s)" % [ch, s])
	# The verdicts.
	t.eq(ShotTutorialCopy.verdict(ShotClassify.SWISH, 100.0), "swish", "swish")
	t.eq(ShotTutorialCopy.verdict(ShotClassify.BANK, 108.0), "bank", "bank")
	t.eq(ShotTutorialCopy.verdict(ShotClassify.MAKE, 103.0), "bank", "a plain make counts as in off the glass")
	t.eq(ShotTutorialCopy.verdict(ShotClassify.FRONT_RIM, 94.0), "rim", "front rim")
	t.eq(ShotTutorialCopy.verdict(ShotClassify.IN_AND_OUT, 100.0), "rim", "in and out")
	t.eq(ShotTutorialCopy.verdict(ShotClassify.AIRBALL, 80.0), "short", "an air ball under 100 % is short")
	t.eq(ShotTutorialCopy.verdict(ShotClassify.BOARD_MISS, 121.0), "long", "a board miss over 100 % is long")
	t.ok(ShotTutorialCopy.is_make("swish") and ShotTutorialCopy.is_make("bank") and not ShotTutorialCopy.is_make("rim"), "makes")
	# The demo clock (the design's demo()).
	var d0 := ShotTutorialCopy.demo(0, 0.7)
	t.ok(d0["finger"] != null and d0["ripple"] != null and not bool(d0["holding"]), "step 1: the finger bobs with a ripple, nothing pressed")
	t.ok(absf(float(d0["ripple"]["s"]) - 120.0) < 1.0 and absf(float(d0["ripple"]["op"]) - 0.5) < 0.01, "…the ring half grown and half faded at 0.7 s")
	t.ok(not bool(ShotTutorialCopy.demo(1, 0.2)["holding"]), "step 2: approaching, not pressed yet")
	var d1 := ShotTutorialCopy.demo(1, 1.0)
	t.ok(bool(d1["holding"]) and float(d1["pull"]) > 50.0 and float(d1["pull"]) < 180.0, "…pressed and pulling at 1.0 s (%.0f px)" % float(d1["pull"]))
	t.ok(absf(float(ShotTutorialCopy.demo(1, 2.0)["pull"]) - ShotTutorialCopy.PULL_AIM) < 0.5, "…fully pulled by 2.0 s")
	t.ok(not bool(ShotTutorialCopy.demo(1, 2.5)["holding"]), "…let go after 2.3 s")
	t.ok(absf(float(ShotTutorialCopy.demo(4, 1.0)["alpha"]) - 0.6) < 0.01, "step 5's ghost is the aim demo at 60 %")
	var f2 := ShotTutorialCopy.demo(2, 1.58)
	t.ok(bool(f2["flick"]) and bool(f2["holding"]) and float((f2["finger"] as Vector2).y) < ShotTutorialCopy.PULL_FLICK, "step 3: the flick at 1.58 s, the finger on its way up")
	var r2 := ShotTutorialCopy.demo(2, 1.7)
	t.ok(bool(r2["release"]) and not bool(r2["holding"]), "…let go after 1.66 s")
	t.ok(ShotTutorialCopy.demo(2, 2.1)["finger"] == null, "…the finger gone a third of a second later")
	t.ok(float(ShotTutorialCopy.demo(2, 3.9)["loop"]) < 0.2, "…the loop wraps at 3.8 s")
	t.eq(ShotTutorialCopy.read_sample(0.5), [52.0, 100.0], "step 4 cycle: 52° 100%")
	t.eq(ShotTutorialCopy.read_sample(2.0), [52.0, 112.0], "…then 112%")
	t.eq(ShotTutorialCopy.read_sample(3.5), [44.0, 78.0], "…then 44° 78%")
	# The gate.
	t.ok(ShotTutorial.due(false, false, false), "due on a fresh save, offline")
	t.ok(not ShotTutorial.due(true, false, false), "never once seen")
	t.ok(not ShotTutorial.due(false, true, false), "never online")
	t.ok(not ShotTutorial.due(false, false, true), "never under a QA pass that did not ask")
	var qa := load("res://tools/qa_driver.gd")
	t.ok(not qa.skips_tutorial(PackedStringArray()), "a plain launch keeps the tutorial (the phone, 2026-10-24)")
	t.ok(not qa.skips_tutorial(PackedStringArray(["--rendering-driver", "vulkan"])), "…engine flags are not a QA pass")
	t.ok(qa.skips_tutorial(PackedStringArray(["--qa-heat"])), "a QA pass skips it")
	t.ok(qa.skips_tutorial(PackedStringArray(["--qa-perf=cage"])), "…a valued QA flag too")
	t.ok(not qa.skips_tutorial(PackedStringArray(["--qa-tutorial"])), "…unless it is the tutorial pass")
	t.ok(save.default_settings().has("shotTutorialSeen") and not bool(save.default_settings()["shotTutorialSeen"]), "shotTutorialSeen defaults off")
	# The flick mapping's inverses (the demo's perfect throw).
	var tuning := FlickTuning.new()
	var vh := 1280.0
	var pull := FlickMap.pull_for_angle(55.0, vh, tuning)
	t.ok(absf(FlickMap.windup_angle(pull, vh, tuning) - 55.0) < 0.01, "pull_for_angle inverts windup_angle")
	var geo := SimGeometry.arcade()
	var sh := FlickMap.speed_sh_for_reach(55.0, geo.hoop_x, geo.rise, tuning)
	var v := FlickMap.anchored_speed(geo.hoop_x, geo.rise, sh, tuning)
	t.ok(absf(AimReadout.reach_pct(55.0, v, geo.hoop_x, geo.rise) - 100.0) < 0.5, "speed_sh_for_reach carries exactly to the rim (%.1f %%)" % AimReadout.reach_pct(55.0, v, geo.hoop_x, geo.rise))
	# The overlay over a stub screen.
	var st := was_settings.duplicate(true)
	st["shotTutorialSeen"] = false
	save.put_settings(st)
	var screen := StubScreen.new()
	var tut := ShotTutorial.new()
	var closed := []
	tut.closed.connect(func(c: bool) -> void: closed.push_back(c))
	tut.start(screen)
	t.eq(tut.step_index(), 0, "starts on HOW TO SHOOT")
	var card: ShadowPanel = tut.find_child("Card", true, false)
	t.ok(card != null and absf(card.position.x - ShotTutorial.CARD_X) < 0.5, "the card at the top-left")
	t.eq((card.find_child("Title", true, false) as Label).text, "HOW TO SHOOT", "the step's title")
	t.eq((card.find_child("Count", true, false) as Label).text, "1 / 5", "counted 1 / 5")
	t.ok(card.find_child("TourSkip", true, false) != null and card.find_child("TourBack", true, false) == null, "SKIP, no < on the first card")
	t.eq((card.find_child("Cta", true, false) as Label).text, "NEXT", "NEXT")
	t.ok((tut.find_child("Root", true, false) as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "the demo steps own every touch")
	tut.next()
	card = tut.find_child("Card", true, false)
	t.ok(card.find_child("TourBack", true, false) != null, "< from the second card")
	tut.next()
	tut.next()
	card = tut.find_child("Card", true, false)
	t.ok(card.find_child("Legend", true, false) != null, "READ YOUR SHOT shows the legend")
	tut.next()
	t.ok(tut.live(), "YOUR TURN is live")
	card = tut.find_child("Card", true, false)
	t.ok(card.find_child("TourNext", true, false) == null and card.find_child("Waiting", true, false) != null, "…no NEXT until a make: the dashed TAKE A SHOT")
	t.ok((tut.find_child("Root", true, false) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "…the court gets the touches")
	tut.on_outcome({"type": ShotClassify.FRONT_RIM}, 94.0)
	card = tut.find_child("Card", true, false)
	t.eq((card.find_child("Title", true, false) as Label).text, "OFF THE RIM", "a miss rewrites the title")
	t.ok(not tut.made() and card.find_child("TourSkip", true, false) != null and card.find_child("TourNext", true, false) == null, "…still waiting, SKIP still there")
	tut.on_outcome({"type": ShotClassify.SWISH}, 100.0)
	card = tut.find_child("Card", true, false)
	t.ok(tut.made() and (card.find_child("Title", true, false) as Label).text == "SWISH!", "a swish: SWISH!")
	t.ok(card.find_child("TourSkip", true, false) == null and (card.find_child("Cta", true, false) as Label).text == "LET'S PLAY", "…SKIP gone, LET'S PLAY on")
	t.ok(not app.shot_tutorial_seen(), "not seen until it closes")
	tut.next()
	t.ok(closed == [true] and app.shot_tutorial_seen(), "LET'S PLAY closes (completed) and marks it seen")
	# SKIP marks it seen too.
	save.put_settings(st)
	var tut2 := ShotTutorial.new()
	var closed2 := []
	tut2.closed.connect(func(c: bool) -> void: closed2.push_back(c))
	tut2.start(StubScreen.new())
	tut2.skip()
	t.ok(closed2 == [false] and app.shot_tutorial_seen(), "SKIP closes (not completed) and marks it seen")
	save.put_settings(was_settings)
