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
	# The preview follows the latest rows it is given.
	var bp := BoardPreview.new()
	var rows := []
	for i in 5:
		rows.push_back({"rank": "#%d" % (i + 1), "name": "P%d" % i, "score": str(30 - i), "me": false})
	bp.set_rows(rows, {"rank": 9, "score": 12})
	t.eq(bp.row_count(), 6, "five and YOU")
	bp.set_rows(RanksCopy.local_rows([{"score": 31}]))
	t.eq(bp.row_count(), 1, "re-rendered from the device list")
	bp.set_rows(rows.slice(0, 2), {"rank": 9, "score": 20})
	t.eq(bp.row_count(), 2, "…and again from a shorter server list (YOU pins only under a full five)")
	bp.free()
