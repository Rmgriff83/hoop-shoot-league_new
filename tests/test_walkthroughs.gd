extends RefCounted
## Walkthroughs (design 36a home, 36b league, 36c free PEGGY play): the
## data, and the spotlight overlay's steps, placement and the seen flag —
## over a fake resolver, off-tree.

const LEAGUE_VARS := {"LEAGUE": "ARCADE\nLEAGUE", "AREA": "Arcade Cage", "SECONDS": 90, "GAMES": 14, "TOP": 4}
const TitleScreen := preload("res://game/screens/title_screen.gd")


func run(t) -> void:
	var app = Engine.get_main_loop().root.get_node("App")
	var save = Engine.get_main_loop().root.get_node("SaveService")
	var was_settings: Dictionary = save.get_settings()
	# The data.
	t.eq(Walkthroughs.ids(), ["home", "league", "peggy"], "three tours: the home, the league, the free PEGGY play")
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
	var all_vars := LEAGUE_VARS.duplicate()
	all_vars["COST"] = PeggyPrizes.DROP_COST
	for tour in Walkthroughs.ids():
		for s in Walkthroughs.fill(Walkthroughs.tour(tour), all_vars):
			for ch in str(s["title"]) + str(s["pre"]) + str(s["cta"]):
				t.ok(ch == "\n" or display.has_char(ch.unicode_at(0)), "display glyph '%s' (%s.%s)" % [ch, tour, s["id"]])
			for ch in str(s["body"]):
				t.ok(bold.has_char(ch.unicode_at(0)), "body glyph '%s' (%s.%s)" % [ch, tour, s["id"]])
			t.ok(not (str(s["title"]) + str(s["body"])).contains("{"), "no token left unfilled (%s.%s)" % [tour, s["id"]])
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
	_peggy_tour(t, app, save)
	save.put_settings(was_settings)
	_league_tour(t, app, save)
	save.put_settings(was_settings)


## The free PEGGY play (design 36c): the gift card over the home, then THIS
## IS PEGGY with no spotlight, the plates, and PLAY.
func _peggy_tour(t, app, save) -> void:
	var steps := Walkthroughs.tour("peggy")
	t.eq(steps.map(func(s): return s["id"]), ["gift", "machine", "slots", "play"], "the free-play tour's four cards")
	t.eq(steps.map(func(s): return s["kind"]), ["gift", "plain", "plain", "plain"], "a gift card, then three plain ones")
	t.eq([steps[0]["cta"], steps[3]["cta"]], ["OPEN PEGGY", "GOT IT"], "OPEN PEGGY … GOT IT")
	t.eq(Walkthroughs.bookend_top("peggy"), 520.0, "its spotless cards rest at 520")
	t.ok(str(steps[2]["body"]).contains("blue common, green rare, pink epic"), "the rarity line names the game's tiers (Ross, 2026-11-06)")
	var st: Dictionary = save.get_settings()
	st["walkthroughsSeen"] = []
	save.put_settings(st)
	var rects := {"slots": Rect2(150, 1010, 420, 110), "play": Rect2(136, 400, 448, 243)}
	var seen := []
	var closed := []
	var w := Walkthrough.new()
	w.step_changed.connect(func(i: int, s: Dictionary) -> void: seen.push_back("%d:%s" % [i, s["id"]]))
	w.closed.connect(func(c: bool) -> void: closed.push_back(c))
	t.ok(w.start("peggy", func(id: String) -> Rect2: return rects.get(id, Rect2()), {"COST": PeggyPrizes.DROP_COST}), "the free-play tour starts")
	t.eq(seen, ["0:gift"], "the host hears the first card")
	var card: ShadowPanel = w.find_child("Card", true, false)
	t.eq((card.find_child("Pre", true, false) as Label).text, "YOU EARNED A", "YOU EARNED A")
	t.eq((card.find_child("Title", true, false) as Label).text, "FREE PLAY!", "FREE PLAY!")
	var ticket: PixelIcon = card.find_child("Ticket", true, false)
	t.ok(ticket != null and ticket.icon_name == "icon_ticket" and ticket.turn == -14.0 and ticket.custom_minimum_size == Vector2(84, 84), "the ticket, 84 px, turned -14")
	t.ok(card.find_child("Count", true, false) == null and card.find_child("TourSkip", true, false) != null, "no count on the gift; SKIP is there")
	t.eq((card.find_child("Cta", true, false) as Label).text, "OPEN PEGGY", "OPEN PEGGY")
	t.ok(not w.has_spot() and absf(w.card_top() - 520.0) < 0.5, "over the home, no spotlight, at 520")
	w.next()
	card = w.find_child("Card", true, false)
	t.eq((card.find_child("Title", true, false) as Label).text, "THIS IS PEGGY", "THIS IS PEGGY")
	t.eq((card.find_child("Count", true, false) as Label).text, "1 / 3", "counted 1 / 3")
	t.ok(not w.has_spot() and absf(w.card_top() - 520.0) < 0.5, "the machine card has no spotlight and rests at 520 (the design nulls its spot)")
	w.next()
	t.ok(w.has_spot() and w.spot_rect() == rects["slots"], "THE PRIZES spots the plates")
	t.ok(w.card_above(), "…with its card above them")
	w.next()
	card = w.find_child("Card", true, false)
	t.eq((card.find_child("Title", true, false) as Label).text, "ON THE HOUSE", "ON THE HOUSE")
	t.eq((card.find_child("Count", true, false) as Label).text, "3 / 3", "counted 3 / 3")
	t.ok((card.find_child("Body", true, false) as Label).text.contains("each play costs 300 tickets"), "the price is the game's (COST filled)")
	t.ok(card.find_child("TourSkip", true, false) == null and card.find_child("TourBack", true, false) != null, "the last card: no SKIP, a <")
	t.eq((card.find_child("Cta", true, false) as Label).text, "GOT IT", "GOT IT")
	t.ok(w.spot_rect() == rects["play"] and not w.card_above() and absf(w.card_top() - (rects["play"].end.y + Walkthrough.GAP)) < 0.5, "PLAY spotted, the card under it")
	# The target moved (the page settled, the model loaded): refresh re-aims.
	rects["play"] = Rect2(136, 300, 448, 243)
	w.refresh()
	t.ok(w.spot_rect() == rects["play"] and absf(w.card_top() - (rects["play"].end.y + Walkthrough.GAP)) < 0.5, "refresh() follows a target that moved")
	w.back()
	w.back()
	w.back()
	t.eq(seen, ["0:gift", "1:machine", "2:slots", "3:play", "2:slots", "1:machine", "0:gift"], "every card is announced, forward and back")
	for i in 4:
		w.next()
	t.ok(closed == [true] and app.walkthrough_seen("peggy"), "GOT IT completes it and marks it seen")
	w.free()


## The league tour (design 36b): welcome, the tab row, the five tabs, GOOD LUCK!.
func _league_tour(t, app, save) -> void:
	t.eq(TitleScreen.league_tour_vars("cage"), LEAGUE_VARS, "the cage's own numbers are the design's words")
	var beach: Dictionary = TitleScreen.league_tour_vars("beach")
	t.ok(str(beach["LEAGUE"]) == "BEACH\nLEAGUE" and str(beach["AREA"]) == "Beach", "another league reads as itself")
	var steps := Walkthroughs.fill(Walkthroughs.tour("league"), LEAGUE_VARS)
	t.eq(steps.map(func(s): return s["id"]), ["welcome", "tabs", "HEAT", "TABLE", "SCHED", "CARDS", "STATS", "end"], "the league tour's eight cards")
	t.eq(Walkthroughs.bookend_top("league"), 480.0, "its bookends rest at 480")
	t.ok(str(steps[0]["body"]).begins_with("Matches are 90-second heats against shooters from the Arcade Cage. Play a 14-game season, finish in the top 4"), "the welcome's numbers are filled")
	t.eq([steps[0]["cta"], steps[7]["cta"]], ["SHOW ME", "LET'S PLAY"], "SHOW ME … LET'S PLAY")
	t.eq(steps.slice(2, 7).map(func(s): return s["title"]), ["MATCH", "TABLE", "SCHED", "CARDS", "STATS"], "HEAT is titled MATCH")
	for id in ["HEAT", "TABLE", "SCHED", "CARDS", "STATS"]:
		t.ok(LeagueContext.TABS.has(id), "step %s is a real tab" % id)
	var st: Dictionary = save.get_settings()
	st["walkthroughsSeen"] = []
	save.put_settings(st)
	var area := Rect2(30, 700, 660, 800)
	var rects := {"tabs": Rect2(26, 590, 668, 92)}
	for i in LeagueContext.TABS.size():
		rects[LeagueContext.TABS[i]] = Rect2(26 + i * 134, 590, 130, 92).merge(area)
	var seen := []
	var closed := []
	var w := Walkthrough.new()
	w.step_changed.connect(func(_i: int, s: Dictionary) -> void: seen.push_back(s["id"]))
	w.closed.connect(func(c: bool) -> void: closed.push_back(c))
	t.ok(w.start("league", func(id: String) -> Rect2: return rects.get(id, Rect2()), LEAGUE_VARS), "the league tour starts")
	var card: ShadowPanel = w.find_child("Card", true, false)
	t.eq((card.find_child("Pre", true, false) as Label).text, "WELCOME TO THE", "WELCOME TO THE")
	t.eq((card.find_child("Title", true, false) as Label).text, "ARCADE\nLEAGUE", "ARCADE LEAGUE on two lines")
	t.eq((card.find_child("Cta", true, false) as Label).text, "SHOW ME", "SHOW ME")
	t.ok(not w.has_spot() and absf(w.card_top() - 480.0) < 0.5, "the welcome rests at 480")
	w.next()
	t.eq((w.find_child("Count", true, false) as Label).text, "1 / 7", "counted 1 / 7")
	t.ok(w.spot_rect() == rects["tabs"], "THE TABS spots the row")
	w.next()
	t.ok(w.spot_rect() == rects["HEAT"] and w.card_above(), "MATCH spots its tab and the panes; the card sits above")
	for i in 4:
		w.next()
	t.eq((w.find_child("Count", true, false) as Label).text, "6 / 7", "STATS is 6 / 7")
	w.next()
	card = w.find_child("Card", true, false)
	t.eq((card.find_child("Title", true, false) as Label).text, "GOOD LUCK!", "GOOD LUCK!")
	t.ok(not w.has_spot() and absf(w.card_top() - 480.0) < 0.5 and card.find_child("TourSkip", true, false) == null, "the end: no spotlight, at 480, no SKIP")
	t.eq(seen, ["welcome", "tabs", "HEAT", "TABLE", "SCHED", "CARDS", "STATS", "end"], "the host hears every card (it switches the tab)")
	w.next()
	t.ok(closed == [true] and app.walkthrough_seen("league"), "LET'S PLAY completes it and marks it seen")
	w.free()
	# The home tour is unchanged: its bookends stay at 520.
	t.eq(Walkthroughs.bookend_top("home"), 520.0, "the home tour's bookends stay at 520")
