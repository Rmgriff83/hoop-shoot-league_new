extends RefCounted
## The 1v1 lobby (docs/BACKEND.md → Phase 3): MatchCopy's words in both
## faces, the page off-tree through its states, a code of the wrong length
## refused, the post-match header for an online heat.


func run(t) -> void:
	t.eq(MatchCopy.title("beach"), "BEACH · 1V1", "the title")
	t.eq(MatchCopy.code_line("abcde"), "CODE AB CDE · TELL YOUR FRIEND", "the code, split to read")
	t.eq(MatchCopy.waiting_line("quick"), "FINDING A PLAYER...", "quick waits")
	t.eq(MatchCopy.found_line({"name": "GLASS WIZARD", "tag": "07"}), "GLASS WIZARD 07 IS HERE · TIP OFF", "found")
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
	# The page.
	var page := MatchLobbyPage.new()
	var root := page.build("beach")
	t.eq((root.find_child("Title", true, false) as Label).text, "BEACH · 1V1", "the title on the page")
	t.eq(page.state(), "menu", "opens on the menu")
	var got := []
	page.quick.connect(func() -> void: got.push_back("quick"))
	page.create.connect(func() -> void: got.push_back("create"))
	page.join.connect(func(code: String) -> void: got.push_back("join:" + code))
	(root.find_child("Quick", true, false) as Button).pressed.emit()
	(root.find_child("Create", true, false) as Button).pressed.emit()
	t.eq(got, ["quick", "create"], "the buttons emit")
	var edit: LineEdit = root.find_child("CodeEdit", true, false)
	edit.text = "abc"
	(root.find_child("Go", true, false) as Button).pressed.emit()
	t.eq(got.size(), 2, "a short code does not go out")
	t.eq(page.state(), "menu", "…and the page stays on the menu")
	edit.text = "ab cde"
	(root.find_child("Go", true, false) as Button).pressed.emit()
	t.eq(got[2], "join:ABCDE", "a five-letter code goes out tidied")
	page.show_waiting("create", "ABCDE")
	t.eq(page.state(), "waiting", "waiting")
	t.eq(page.big_text(), "CODE AB CDE · TELL YOUR FRIEND", "with the code big")
	t.eq(page.status_text(), "WAITING FOR YOUR FRIEND...", "and the wait under it")
	page.show_waiting("quick")
	t.eq(page.big_text(), "FINDING A PLAYER...", "quick: the wait big")
	page.show_found({"name": "GLASS WIZARD", "tag": "07"})
	t.eq(page.state(), "found", "found")
	t.ok(not (root.find_child("Cancel", true, false) as Control).visible, "no cancel once they are here")
	page.show_failed("not_found")
	t.eq(page.status_text(), "NO MATCH FOR THAT CODE", "a failure line")
	var cancels := [0]
	page.cancel.connect(func() -> void: cancels[0] += 1)
	(root.find_child("Cancel", true, false) as Button).pressed.emit()
	t.eq(cancels[0], 1, "cancel emits")
	t.eq(page.state(), "menu", "…and goes back to the menu")
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
