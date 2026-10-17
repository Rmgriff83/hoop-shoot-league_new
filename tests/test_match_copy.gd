extends RefCounted
## The 1v1 lobby (docs/BACKEND.md → Phase 3): MatchCopy's words in both
## faces, the page off-tree through its states, a code of the wrong length
## refused, the post-match header for an online heat.


func run(t) -> void:
	t.eq(MatchCopy.title(), "ONLINE · 1V1", "the title")
	t.eq(MatchCopy.court_name("any"), "ANY", "the picker's ANY")
	t.eq(MatchCopy.court_full("cage"), "ARCADE CAGE", "the cage's full name")
	t.eq(MatchCopy.court_note(1), "UNLOCK MORE COURTS TO CHOOSE", "one court: the nudge")
	t.eq(MatchCopy.court_note(3), "3 OF 4 OWNED", "three courts owned")
	t.eq(MatchCopy.quick_sub("any"), "FIRST OPEN MATCH ON YOUR COURTS", "quick on any court")
	t.eq(MatchCopy.quick_sub("beach"), "PLAY WHOEVER IS ON BEACH", "quick on one court")
	t.eq(MatchCopy.code_line("abcde"), "CODE AB CDE · TELL YOUR FRIEND", "the heat's code line, split to read")
	t.eq(MatchCopy.waiting_big("quick"), "FINDING A PLAYER", "quick waits big")
	t.eq(MatchCopy.waiting_line("quick"), "USUALLY UNDER 30 SECONDS", "…with the reassurance")
	t.eq(MatchCopy.found_line({"name": "GLASS WIZARD", "tag": "07", "level": 7}), "GLASS WIZARD 07 · LVL 07 · STARTING", "found, with their level")
	t.eq(MatchCopy.found_line({"name": "GLASS WIZARD", "tag": "07"}), "GLASS WIZARD 07 · STARTING", "found without a level")
	t.eq(MatchCopy.failed_big("not_found"), "CODE NOT FOUND", "a bad code, big")
	t.eq(MatchCopy.failed_line("not_found"), "CHECK THE 5 LETTERS AND TRY AGAIN", "…and what to do")
	t.eq(MatchCopy.failed_line("expired"), "NOBODY CAME · TRY AGAIN", "nobody came")
	t.eq(MatchCopy.header({"location": "beach", "online": true}), "ONLINE MATCH · BEACH", "the online header")
	t.eq(MatchCopy.header({"location": "city", "reason": "forfeit"}), "ONLINE MATCH · CITY · THEY LEFT", "a forfeit header")
	t.eq(HeatCopy.header({"online": true, "location": "cage"}, {}), "ONLINE MATCH · CAGE", "HeatCopy hands online heats to MatchCopy")
	t.eq(HeatCopy.header({}, {}), "QUICK HEAT", "…and keeps QUICK HEAT for the test heat")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in MatchCopy.strings():
		for ch in str(s):
			t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, s])
	# The page (design 37a): a HomePage with the court picker and the cards.
	var page := MatchLobbyPage.new()
	var root := page.build("beach")
	t.eq((root.find_child("Title", true, false) as Label).text, "ONLINE · 1V1", "the title on the page")
	t.eq(page.state(), "menu", "opens on the menu")
	var owned := App.unlocked_areas()
	t.eq(page.area_choice, "beach" if owned.size() > 1 else "cage", "opens on the home's court, or the cage alone")
	for a in MatchCopy.AREAS:
		t.ok(root.find_child("Court_" + a, true, false) != null, "a %s court button" % a)
	var any_b: ShadowCard = root.find_child("Court_any", true, false)
	var city_b: ShadowCard = root.find_child("Court_city", true, false)
	t.eq(city_b.disabled, not owned.has("city") or owned.size() < 2, "a locked court is disabled")
	t.ok(root.find_child("Loadout", true, false) != null and root.find_child("Yours", true, false) != null, "LOADOUT and YOUR CARDS on the page")
	var got := []
	page.quick.connect(func(area: String) -> void: got.push_back("quick:" + area))
	page.create.connect(func(area: String) -> void: got.push_back("create:" + area))
	page.join.connect(func(area: String, code: String) -> void: got.push_back("join:%s:%s" % [area, code]))
	if owned.size() > 1:
		any_b.pressed.emit()
		t.eq(page.area_choice, "any", "ANY picked")
		t.eq((root.find_child("Quick/Col/Sub", true, false) as Label).text if root.find_child("Quick/Col/Sub", true, false) != null else (page._quick_sub as Label).text, MatchCopy.quick_sub("any"), "QUICK MATCH's sub follows the court")
	var choice := page.area_choice
	(root.find_child("Quick", true, false) as Button).pressed.emit()
	(root.find_child("Create", true, false) as Button).pressed.emit()
	t.eq(got, ["quick:" + choice, "create:" + choice], "the buttons emit with the court")
	var edit: LineEdit = root.find_child("CodeEdit", true, false)
	edit.text = "abc"
	(root.find_child("Go", true, false) as Button).pressed.emit()
	t.eq(got.size(), 2, "a short code does not go out")
	t.eq(page.state(), "failed", "…it shows CODE NOT FOUND")
	t.eq(page.big_text(), "CODE NOT FOUND", "…big and red")
	(root.find_child("Cancel", true, false) as Button).pressed.emit()
	t.eq(page.state(), "menu", "BACK returns to the menu")
	edit.text = "abcde"   # the field holds five characters; typing is tidied live
	(root.find_child("Go", true, false) as Button).pressed.emit()
	t.ok(got.size() == 3 and got[2] == "join:%s:ABCDE" % choice, "a five-letter code goes out upper-cased (%s)" % str(got))
	page.show_waiting("create", "ABCDE")
	t.eq(page.state(), "waiting", "waiting")
	t.eq(page.code_text(), "ABCDE", "with the code big and gold")
	t.eq(page.big_text(), "WAITING", "WAITING under it")
	t.eq(page.status_text(), "THE MATCH STARTS AS SOON AS THEY JOIN", "and the line under that")
	page._process(0.5)
	t.eq(page.big_text(), "WAITING.", "the dots tick")
	page.show_waiting("quick")
	t.eq(page.big_text(), "FINDING A PLAYER", "quick: the search big")
	t.ok(not (root.find_child("CodeBlock", true, false) as Control).visible, "no code block on a quick match")
	page.show_found({"name": "GLASS WIZARD", "tag": "07", "level": 7})
	t.eq(page.state(), "found", "found")
	t.eq(page.big_text(), "PLAYER FOUND", "PLAYER FOUND")
	t.ok(not (root.find_child("Cancel", true, false) as Control).visible, "no cancel once they are here")
	page.show_failed("expired")
	t.eq(page.status_text(), "NOBODY CAME · TRY AGAIN", "a failure line")
	t.eq((root.find_child("Cancel", true, false) as Button).text, "BACK", "…under BACK")
	var cancels := [0]
	page.cancel.connect(func() -> void: cancels[0] += 1)
	(root.find_child("Cancel", true, false) as Button).pressed.emit()
	t.eq(cancels[0], 1, "cancel emits")
	t.eq(page.state(), "menu", "…and goes back to the menu")
	page.free()
	# The rematch card's words and the page that carries it.
	t.eq([MatchCopy.rematch_title(""), MatchCopy.rematch_sub("")], ["REMATCH?", "ASK FOR ANOTHER"], "nothing yet")
	t.eq([MatchCopy.rematch_title("offered"), MatchCopy.rematch_sub("offered")], ["REMATCH?", "WAITING FOR THEM..."], "we asked")
	t.eq([MatchCopy.rematch_title("wanted"), MatchCopy.rematch_sub("wanted")], ["THEY WANT A REMATCH", "TAP TO ACCEPT"], "they asked")
	t.eq([MatchCopy.rematch_title("both"), MatchCopy.rematch_sub("both")], ["REMATCH ON", "TIPPING OFF..."], "both")
	t.eq([MatchCopy.rematch_title("gone"), MatchCopy.rematch_sub("gone")], ["THEY LEFT", "BACK HOME FOR ANOTHER"], "they left")
	t.ok(MatchCopy.rematch_active("") and MatchCopy.rematch_active("wanted"), "ask and accept are taps")
	t.ok(not MatchCopy.rematch_active("offered") and not MatchCopy.rematch_active("both") and not MatchCopy.rematch_active("gone"), "the rest are not")
	var heat := {"online": true, "won": false, "location": "beach", "player_score": 3, "ai_score": 7, "ot": 0, "coins": 20, "mult": 1.0,
		"opponent": MatchProtocol.opponent({"name": "GLASS WIZARD", "tag": "07"}), "sides": {"player": {}, "ai": {}}}
	var screen_script: GDScript = load("res://game/screens/heat_result_screen.gd")
	var screen: Node = screen_script.new()
	App.room = null
	App.rematch_state = ""
	var chrome_off: Control = screen.build_chrome(heat, {}, {})
	t.ok(chrome_off.find_child("Rematch", true, false) == null, "no REMATCH once the room is gone")
	chrome_off.free()
	var stub := QaFakePeer.new()
	App.room = stub
	var chrome: Control = screen.build_chrome(heat, {}, {})
	var rematch: Button = chrome.find_child("Rematch", true, false)
	t.ok(rematch != null and not rematch.disabled, "REMATCH? on an online post-match page with the room open")
	t.eq((chrome.find_child("RematchTitle", true, false) as Label).text, "REMATCH?", "…reads REMATCH?")
	rematch.pressed.emit()
	t.eq(App.rematch_state, "offered", "tapping asks")
	t.eq(stub.sent[-1]["t"], "rematch", "…over the wire")
	t.ok(rematch.disabled, "…and the card waits")
	t.eq((chrome.find_child("RematchSub", true, false) as Label).text, "WAITING FOR THEM...", "…saying so")
	App._set_rematch("both")
	t.eq((chrome.find_child("RematchTitle", true, false) as Label).text, "REMATCH ON", "both: REMATCH ON")
	App._set_rematch("gone")
	t.eq((chrome.find_child("RematchTitle", true, false) as Label).text, "THEY LEFT", "gone: THEY LEFT")
	chrome.free()
	screen.free()
	App.room = null
	App.rematch_state = ""
	stub.free()
	# The fake peer speaks the protocol.
	var fake := QaFakePeer.new()
	fake.stage({"seed": 5, "area": "beach", "seconds": 4.0}, SimGeometry.beach(SimGeometry.BEACH_DIST))
	var msgs := []
	fake.message.connect(func(m: Dictionary) -> void: msgs.push_back(m))
	for i in 60 * 9:
		fake._process(1.0 / 60.0)
	t.ok(msgs.size() >= 2, "the fake peer shot (%d messages)" % msgs.size())
	t.eq(str(msgs[-1]["t"]), "period_end", "…and reported its buzzer")
	t.ok(msgs.any(func(m: Dictionary) -> bool: return str(m["t"]) == "shot"), "with shots along the way")
	fake.free()
