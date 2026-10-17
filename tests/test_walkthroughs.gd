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
	t.eq(steps.size(), 7, "seven steps")
	t.eq(steps.map(func(s): return s["id"]), ["welcome", "three", "league", "level", "online", "locker", "end"], "…in the design's order")
	t.ok(steps[0]["kind"] == "welcome" and steps[6]["kind"] == "end" and steps[1]["kind"] == "plain", "bookends and plain steps")
	t.eq(Walkthroughs.plain_count(steps), 5, "five counted steps")
	t.eq(steps[0]["cta"], "LET'S GO", "the welcome's CTA")
	t.eq(steps[6]["cta"], "LET'S SHOOT", "the end's CTA")
	t.eq(Walkthroughs.tour("nope"), [], "an unknown tour is empty")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in steps:
		for ch in str(s["title"]):
			t.ok(ch == "\n" or display.has_char(ch.unicode_at(0)), "title glyph '%s' (%s)" % [ch, s["id"]])
		for ch in str(s["body"]):
			t.ok(bold.has_char(ch.unicode_at(0)), "body glyph '%s' (%s)" % [ch, s["id"]])
	# The overlay over fake rects: one in the top half, one in the bottom half.
	var rects := {"three": Rect2(36, 800, 648, 400), "league": Rect2(36, 800, 648, 300), "level": Rect2(36, 32, 170, 56),
		"online": Rect2(486, 230, 132, 56), "locker": Rect2(230, 32, 56, 56)}
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
	t.eq(w.step_index(), 1, "NEXT → THREE WAYS TO PLAY")
	card = w.find_child("Card", true, false)
	t.eq((card.find_child("Title", true, false) as Label).text, "THREE WAYS TO PLAY", "the step's title")
	t.eq((card.find_child("Count", true, false) as Label).text, "1 / 5", "counted 1 / 5")
	t.eq((card.find_child("Cta", true, false) as Label).text, "NEXT", "NEXT by default")
	t.ok(w.has_spot() and w.spot_rect() == rects["three"], "the spot is the resolved rect")
	t.ok(w.card_above() and w.card_top() + 10.0 < rects["three"].position.y, "a lower-half spot: the card sits above it")
	t.ok(card.find_child("TourBack", true, false) != null, "< from the second card")
	w.next()
	w.next()
	t.eq(w.step_index(), 3, "→ LEVEL UP")
	t.ok(not w.card_above() and w.card_top() > rects["level"].end.y, "an upper-half spot: the card sits below it")
	w.back()
	t.eq(w.step_index(), 2, "< goes back")
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
	for i in 6:
		w2.next()
	t.eq(w2.step_index(), 6, "on THAT'S IT!")
	card = w2.find_child("Card", true, false)
	t.ok(card.find_child("TourSkip", true, false) == null and (card.find_child("Cta", true, false) as Label).text == "LET'S SHOOT" and not w2.has_spot(), "the end: no SKIP, LET'S SHOOT, no spotlight")
	w2.next()
	t.ok(closed2 == [true] and app.walkthrough_seen("home"), "the last NEXT completes and marks it seen")
	w2.free()
	# The seen flag round-trips like unlocksSeen.
	t.ok(SaveService.default_settings().has("walkthroughsSeen"), "walkthroughsSeen is a default key")
	save.put_settings(was_settings)
