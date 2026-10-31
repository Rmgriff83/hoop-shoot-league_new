extends RefCounted
## Walkthroughs (design 36a): the data, and the spotlight overlay's steps,
## placement and the seen flag — over a fake resolver, off-tree.


func run(t) -> void:
	var app = Engine.get_main_loop().root.get_node("App")
	var save = Engine.get_main_loop().root.get_node("SaveService")
	var was_settings: Dictionary = save.get_settings()
	# The data.
	t.eq(Walkthroughs.ids(), ["home"], "one tour today: home")
	var steps := Walkthroughs.tour("home")
	t.eq(steps.size(), 6, "six steps (design 36a, 2026-10-30)")
	t.eq(steps.map(func(s): return s["id"]), ["welcome", "three", "top", "online", "board", "end"], "…in the design's order")
	t.ok(steps[0]["kind"] == "welcome" and steps[5]["kind"] == "end" and steps[1]["kind"] == "plain", "bookends and plain steps")
	t.eq(Walkthroughs.plain_count(steps), 4, "four spotlit steps")
	t.eq(steps[0]["cta"], "LET'S GO", "the welcome's CTA")
	t.eq(steps[5]["cta"], "LET'S SHOOT", "the end's CTA")
	t.eq(Walkthroughs.tour("nope"), [], "an unknown tour is empty")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in steps:
		for ch in str(s["title"]):
			t.ok(ch == "\n" or display.has_char(ch.unicode_at(0)), "title glyph '%s' (%s)" % [ch, s["id"]])
		for ch in str(s["body"]):
			t.ok(bold.has_char(ch.unicode_at(0)), "body glyph '%s' (%s)" % [ch, s["id"]])
	# The overlay over fake rects: one in the top half, one in the bottom half.
	var rects := {"three": Rect2(36, 1000, 648, 480), "top": Rect2(26, 108, 662, 92),
		"online": Rect2(486, 300, 200, 92), "board": Rect2(130, 687, 454, 264)}
	var w := Walkthrough.new()
	var closed := []
	w.closed.connect(func(c: bool) -> void: closed.push_back(c))
	t.ok(w.start("home", func(id: String) -> Rect2: return rects.get(id, Rect2())), "the home tour starts")
	t.eq(w.step_index(), 0, "on the welcome")
	t.ok(not w.has_spot(), "the welcome has no spotlight")
	t.ok(absf(w.card_top() - Walkthrough.BOOKEND_TOP) < 0.5, "a bookend card rests at %d" % int(Walkthrough.BOOKEND_TOP))
	var card: ShadowPanel = w.find_child("Card", true, false)
	t.ok(card.find_child("TourSkip", true, false) != null and card.find_child("TourBack", true, false) == null, "SKIP, no < on the first card")
	t.eq((card.find_child("Cta", true, false) as Label).text, "LET'S GO", "LET'S GO")
	t.ok((card.find_child("Title", true, false) as Label).text.begins_with("HOOP SHOOT"), "WELCOME TO HOOP SHOOT LEAGUE")
	w.next()
	t.eq(w.step_index(), 1, "NEXT → DOWN HERE..")
	card = w.find_child("Card", true, false)
	t.eq((card.find_child("Title", true, false) as Label).text, "DOWN HERE..", "the step's title")
	t.eq((card.find_child("Count", true, false) as Label).text, "1 / 5", "counted 1 / 5")
	t.eq((card.find_child("Cta", true, false) as Label).text, "NEXT", "NEXT by default")
	t.ok(w.has_spot() and w.spot_rect() == rects["three"], "the spot is the resolved rect")
	t.ok(w.card_above() and w.card_top() + 10.0 < rects["three"].position.y, "a lower-half spot: the card sits above it")
	t.ok(card.find_child("TourBack", true, false) != null, "< from the second card")
	w.next()
	t.eq(w.step_index(), 2, "→ UP HERE..")
	t.eq((w.find_child("Count", true, false) as Label).text, "2 / 5", "counted 2 / 5")
	t.ok(not w.card_above() and w.card_top() > rects["top"].end.y, "an upper-half spot: the card sits below it")
	w.next()
	w.next()
	t.eq(w.step_index(), 4, "→ TOP 5")
	t.ok(w.spot_rect() == rects["board"], "…spotting the board")
	w.back()
	t.eq(w.step_index(), 3, "< goes back")
	# SKIP marks it seen and closes.
	save.put_settings(was_settings)
	t.ok(not app.walkthrough_seen("home"), "not seen yet")
	w.skip()
	t.ok(closed == [false] and app.walkthrough_seen("home"), "SKIP closes (not completed) and marks the tour seen")
	w.free()
	# The whole way through.
	var st: Dictionary = save.get_settings()
	st["walkthroughsSeen"] = []
	save.put_settings(st)
	var w2 := Walkthrough.new()
	var closed2 := []
	w2.closed.connect(func(c: bool) -> void: closed2.push_back(c))
	w2.start("home", func(id: String) -> Rect2: return rects.get(id, Rect2()))
	for i in 5:
		w2.next()
	t.eq(w2.step_index(), 5, "on THAT'S IT!")
	card = w2.find_child("Card", true, false)
	t.ok(card.find_child("TourSkip", true, false) == null and (card.find_child("Cta", true, false) as Label).text == "LET'S SHOOT" and not w2.has_spot(), "the end: no SKIP, LET'S SHOOT, no spotlight")
	w2.next()
	t.ok(closed2 == [true] and app.walkthrough_seen("home"), "the last NEXT completes and marks it seen")
	w2.free()
	# The seen flag round-trips like unlocksSeen.
	t.ok(SaveService.default_settings().has("walkthroughsSeen"), "walkthroughsSeen is a default key")
	save.put_settings(was_settings)
