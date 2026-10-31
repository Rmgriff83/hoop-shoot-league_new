extends RefCounted
## The home board stays current (Ross, 2026-10-26: it sat on the old area's
## list after a switch and on the pre-run list after a trial): both area
## switches refresh it, the title re-asks when the server accepts a run,
## and the hooks come off with the screen. The preview re-renders on data.


func run(t) -> void:
	var src := FileAccess.get_file_as_string("res://game/screens/title_screen.gd")
	# Both switch paths: _fill_cards() then _refresh_board().
	var switch_i := src.find("_index = next\n")
	var go_i := src.find("func _go_area(")
	t.ok(switch_i >= 0 and go_i >= 0, "both switch paths exist")
	for pair in [["the chevron switch", switch_i], ["the archive's GO THERE", go_i]]:
		var body := src.substr(int(pair[1]), 700)
		var fill := body.find("_fill_cards()")
		var refresh := body.find("_refresh_board()")
		t.ok(fill >= 0 and refresh > fill, "%s refreshes the board after the cards" % pair[0])
	# The accepted-run hook, on in _ready, off in _exit_tree, area-checked.
	t.ok(src.find("Net.score_accepted.connect(_on_score_accepted)") >= 0, "the title listens for an accepted run")
	t.ok(src.find("Net.score_accepted.disconnect(_on_score_accepted)") >= 0, "…and lets go on exit")
	var handler := src.substr(src.find("func _on_score_accepted("), 300)
	t.ok(handler.find("area == str(CARDS[_index][\"area\"])") >= 0 and handler.find("_refresh_board()") >= 0, "an accepted run for this area re-asks the server")
	# The tickets pill (Ross, 2026-10-27: it kept the pre-PEGGY amount after a
	# play; only the locker showed the spend): the ticker refresh re-reads it,
	# and both the locker and PEGGY run that refresh as they close.
	var ticker := src.substr(src.find("func _refresh_ticker("), 900)
	t.ok(ticker.find("_wallet.set_coins(App.tickets())") >= 0, "the ticker refresh re-reads the wallet")
	for pair in [["the locker", "_locker.closed.connect("], ["PEGGY", "_peggy.closed.connect("]]:
		var close := src.substr(src.find(str(pair[1])), 260)
		t.ok(close.find("_refresh_ticker()") >= 0, "%s refreshes the pill and ticker on close" % pair[0])
	# The preview follows the latest rows it is given (design 3a, 2026-10-30:
	# a window onto the top fifteen, YOU pinned whenever you have a rank).
	var bp := BoardPreview.new()
	var rows := []
	for i in 5:
		rows.push_back({"rank": "#%d" % (i + 1), "name": "P%d" % i, "score": str(30 - i), "me": false})
	bp.set_rows(rows, {"rank": 9, "score": 12})
	t.eq(bp.row_count(), 6, "five and YOU")
	bp.set_rows(RanksCopy.local_rows([{"score": 31}]))
	t.eq(bp.row_count(), 2, "re-rendered from the device list: your run, and you pinned")
	bp.set_rows(rows.slice(0, 2), {"rank": 9, "score": 20})
	t.eq(bp.row_count(), 3, "…and again from a shorter server list")
	bp.free()
	# The title opens the popup from the board, not the RANKS page.
	t.ok(src.find("_board.pressed.connect(_open_board)") >= 0, "a tap on the board opens the popup")
	t.ok(src.find("_board.set_max_height(") >= 0, "the board fits the room it has")
	# The popup (BoardSheet): ONLINE rows with YOU pinned, YOURS from the device.
	var online := []
	for i in 12:
		online.push_back({"rank": "#%d" % (i + 1), "name": "SHOOTER %d" % i, "score": str(41 - i), "me": false})
	var now := 1_800_000_000.0
	var runs := [{"score": 29, "swishes": 7, "playedAt": int(now * 1000.0)}, {"score": 27, "swishes": 5, "playedAt": int((now - 86400.0) * 1000.0)},
		{"score": 24, "swishes": 4, "playedAt": int((now - 20.0 * 86400.0) * 1000.0)}]
	var sheet := BoardSheet.new()
	sheet.setup("cage", online, {"rank": 212, "score": 29}, runs)
	t.eq(sheet.tab(), "ONLINE", "the popup opens on ONLINE")
	t.eq(sheet.rows().size(), 12, "…with the board's rows")
	t.eq(sheet.you_row(), ["212", "YOU", "29", true], "…and YOU pinned under them")
	t.eq((sheet.find_child("Sub", true, false) as Label).text, "ARCADE CAGE · 60 S", "the court and the clock")
	sheet.show_tab("YOURS")
	t.eq(sheet.rows().size(), 3, "YOURS lists the device's runs")
	t.eq(sheet.you_row(), [], "…nothing pinned")
	var yours := BoardSheet.your_rows(runs, now)
	t.eq(str(yours[0][1]), "TODAY · 7 SW", "today's run")
	t.eq(str(yours[1][1]), "YESTERDAY · 5 SW", "yesterday's")
	t.ok(str(yours[2][1]).ends_with(" · 4 SW") and str(yours[2][1]).split(" ")[1].is_valid_int(), "an older one by its date (%s)" % yours[2][1])
	t.ok(bool(yours[0][3]) and not bool(yours[1][3]), "the best on orange")
	var shut := []
	sheet.closed.connect(func() -> void: shut.push_back(true))
	(sheet.find_child("Close", true, false) as Button).pressed.emit()
	t.eq(shut.size(), 1, "CLOSE closes it")
	sheet.free()
	var empty := BoardSheet.new()
	empty.setup("cage", [], {}, [])
	t.ok(empty.find_child("Empty", true, false) != null and empty.you_row() == [], "no board yet: a line, nobody pinned")
	empty.free()
