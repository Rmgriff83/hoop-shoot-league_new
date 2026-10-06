extends RefCounted
## The Ranks page (docs/HOME.md → Ranks): RanksCopy's tabs by level, rows
## from a server board and from the device's own, the status and YOU lines,
## glyph coverage; the page off-tree fed the fixture — tabs, a locked tab,
## `request` on select, set_board / set_offline, and stale data dropped.


func run(t) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ranks_board.json"))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	t.ok(not data.is_empty(), "the fixture loads")
	# Copy.
	t.eq(RanksCopy.tab_name("cage"), "CAGE", "the cage's tab")
	t.eq(RanksCopy.period_name("week"), "THIS WEEK", "the week")
	var tabs1 := RanksCopy.tabs(1, true)
	t.eq(tabs1.size(), 3, "a tab per area")
	t.eq([tabs1[0]["locked"], tabs1[1]["locked"], tabs1[2]["locked"]], [false, true, true], "at level 1 the beach and city are locked")
	t.eq(tabs1[1]["lock_text"], "LVL 3", "…with the level that opens them")
	t.ok(not bool(RanksCopy.tabs(1, false)[2]["locked"]), "with the gate off every tab is open")
	t.ok(not bool(RanksCopy.tabs(5, true)[2]["locked"]), "at level 5 the city is open")
	var rows := RanksCopy.rows(data)
	t.eq(rows.size(), 12, "a row per server row")
	t.eq(rows[0], {"rank": "#1", "name": "GLASS WIZARD 07", "score": "41", "me": false}, "the first row")
	t.ok(bool(rows[6]["me"]), "my row is marked")
	t.eq(RanksCopy.me_line(data), "YOU · #7 · 29", "the pinned line")
	t.eq(RanksCopy.me_line({"rows": []}), "YOU · NO RUN HERE YET", "no run on this board")
	t.eq(RanksCopy.status("week", 12), "TOP 12 · THIS WEEK", "the status")
	t.eq(RanksCopy.status("all", 0), "NO RUNS YET · BE FIRST", "an empty board")
	var local := [{"score": 31}, {"score": 20}]
	t.eq(RanksCopy.local_rows(local), [{"rank": "#1", "name": "YOU", "score": "31", "me": true}, {"rank": "#2", "name": "YOU", "score": "20", "me": false}], "the device board as rows")
	t.eq(RanksCopy.local_me_line(local), "YOU · BEST 31", "the device best")
	t.eq(RanksCopy.local_me_line([]), "YOU · NO RUN HERE YET", "no device run")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in RanksCopy.strings(data, local):
		for ch in str(s):
			t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, s])
	# The page.
	var page := RanksPage.new()
	var root := page.build(RanksCopy.tabs(3, true), "BRICK BARON 42")
	t.eq((root.find_child("Handle", true, false) as Label).text, "BRICK BARON 42", "my handle in the header")
	t.ok(root.find_child("Back", true, false) != null, "the < back button")
	t.ok(page.tab("city").disabled, "the locked city tab cannot be tapped")
	t.eq((page.tab("city").get_node("Text") as Label).text, "CITY · LVL 5", "…and says what opens it")
	t.eq((page.tab("cage").get_node("Text") as Label).text, "CAGE", "the cage tab's word")
	t.ok(not page.tab("beach").disabled, "the open beach tab can")
	var asked := []
	page.request.connect(func(a: String, p: String) -> void: asked.push_back([a, p]))
	page.select("beach", "week")
	t.eq(asked, [["beach", "week"]], "selecting asks for the board")
	t.eq(page.status_text(), "LOADING...", "…and shows LOADING")
	page.select("city", "week")
	t.eq(asked.size(), 1, "a locked area is ignored")
	page.set_board("cage", "week", data)
	t.eq(page.row_count(), 0, "a board for another area is dropped")
	page.set_board("beach", "all", data)
	t.eq(page.row_count(), 0, "…as is another period")
	page.set_board("beach", "week", data)
	t.eq(page.row_count(), 12, "the board's rows")
	t.eq(page.status_text(), "TOP 12 · THIS WEEK", "the status after loading")
	t.eq(page.me_text(), "YOU · #7 · 29", "my line")
	var row7: Control = root.find_child("Row7", true, false)
	t.ok(row7 != null and (row7.find_child("Name", true, false) as Label).text == "BRICK BARON 42", "my row carries my handle")
	page.select("beach", "all")
	t.eq(asked.size(), 2, "switching the period asks again")
	t.eq(page.row_count(), 0, "…and clears the list")
	page.set_offline("beach", "all", local)
	t.eq(page.row_count(), 2, "the device board as a fallback")
	t.eq(page.status_text(), "NO SIGNAL · DEVICE BOARD", "…says so")
	t.eq(page.me_text(), "YOU · BEST 31", "…with the device best")
	var closed := [false]
	page.closed.connect(func() -> void: closed[0] = true)
	page.close()
	t.ok(closed[0], "close emits closed")
	# The settings sheet has the PLAYER section (off-tree: Net is the autoload).
	t.ok(HandleWords.valid(HandleWords.normalize("glass wizard")), "a typed name tidies into a valid one")
