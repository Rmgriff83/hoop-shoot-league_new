extends RefCounted
## The time-trial results page (docs/HOME.md → Results): its copy through
## the design's three states (a new best, a mid-board run, an iced run) and
## the chrome building off-tree from a seeded run — NEW BEST only when it
## is, the tickets card only when tickets were earned, ICED only when it
## happened, this run marked on the board.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func run(t) -> void:
	_copy(t)
	_chrome(t)


func _copy(t) -> void:
	var best := {"score": 31, "makes": 17, "attempts": 26, "swishes": 7, "bestStreak": 8, "bonus": 9, "iced": 0, "location": "cage", "id": "r1", "tickets": 30}
	t.eq(ResultsCopy.title(best), "ARCADE CAGE · TIME TRIAL", "the header names the area")
	t.eq(ResultsCopy.title({"location": "beach"}), "BEACH · TIME TRIAL", "the beach too")
	t.eq(ResultsCopy.board_name("cage"), "ARCADE", "the board's short name")
	t.eq(ResultsCopy.board_name("beach"), "BEACH", "and the beach's")
	t.eq(ResultsCopy.run_sub("cage"), "60 S · SAME CAGE", "RUN IT BACK's sub-line")
	t.eq(ResultsCopy.run_sub("beach"), "60 S · SAME BEACH", "on the beach")
	t.eq(ResultsCopy.best_line(31, 24), "BEST 31 · 7 SHORT", "the gap to the best")
	t.eq(ResultsCopy.best_line(31, 31), "BEST 31 · LEVEL", "a tie is level, not a best")
	var tiles := ResultsCopy.tiles(best)
	t.eq(tiles.size(), 4, "four tiles when not iced")
	t.eq(tiles[0], {"v": "17/26", "l": "MAKES"}, "makes over attempts")
	t.eq(tiles[1], {"v": "7", "l": "SWISHES"}, "swishes")
	t.eq(tiles[2], {"v": "8", "l": "STREAK"}, "streak")
	t.eq(tiles[3], {"v": "+9", "l": "BONUS"}, "bonus with its plus")
	var iced := best.duplicate()
	iced["iced"] = 2
	var tiles5 := ResultsCopy.tiles(iced)
	t.eq(tiles5.size(), 5, "an iced run adds a tile")
	t.eq(tiles5[4], {"v": "2", "l": "ICED"}, "ICED last")
	t.eq(ResultsCopy.tickets(best, true), {"big": "+30", "sub": "TICKETS · BEST BONUS IN"}, "the tickets card on a best")
	t.eq(ResultsCopy.tickets(best, false), {"big": "+30", "sub": "TICKETS"}, "and on a plain run")
	t.eq(ResultsCopy.tickets({"tickets": 0}, false), {}, "no card without tickets")
	var top := [{"score": 31, "swishes": 7, "bestStreak": 8, "id": "r1"}, {"score": 27, "swishes": 5, "bestStreak": 6, "id": "r0"}, {"score": 26}]
	var rows := ResultsCopy.board(top, "r1")
	t.eq(rows.size(), 3, "every row")
	t.eq(rows[0], {"n": "1", "pts": "31", "sw": "7", "st": "8", "mine": true}, "this run is marked")
	t.eq(rows[1]["mine"], false, "the others are not")
	t.eq(rows[2]["sw"], "0", "an old row without swishes reads zero")
	var big := []
	for i in 14:
		big.push_back({"score": 40 - i})
	t.eq(ResultsCopy.board(big, "").size(), ResultsCopy.BOARD_SIZE, "the board is capped at ten")
	# Every glyph in the copy exists in the faces (no system fallback).
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in [ResultsCopy.title(best), ResultsCopy.best_line(31, 24), ResultsCopy.run_sub("cage"), "TICKETS · BEST BONUS IN", "THIS RUN"]:
		for ch in s:
			t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces" % ch)


func _chrome(t) -> void:
	var app = _app()
	if app == null:
		return
	var screen = load("res://game/screens/results_screen.gd").new()
	var best := {"score": 31, "makes": 17, "attempts": 26, "swishes": 7, "bestStreak": 8, "bonus": 9, "iced": 0, "location": "cage", "id": "r1", "tickets": 30}
	var c: Control = screen.build_chrome(best, true)
	t.ok(c.find_child("NewBest", true, false) != null, "a best shows the NEW BEST chip")
	t.ok(c.find_child("BestLine", true, false) == null, "and not the gap line")
	t.eq((c.find_child("Score", true, false) as Label).text, "31", "the score")
	t.ok((c.find_child("Score", true, false) as Label).material is ShaderMaterial, "with the dithered shadow")
	t.ok(c.find_child("Tile_BONUS", true, false) != null and c.find_child("Tile_ICED", true, false) == null, "four tiles, no ICED")
	t.ok(c.find_child("Tickets", true, false) != null, "the tickets card")
	t.eq((c.find_child("TicketsBig", true, false) as Label).text, "+30", "with the amount")
	t.ok(c.find_child("RunItBack", true, false) is ShadowCard and c.find_child("Home", true, false) is ShadowCard, "RUN IT BACK and HOME are shadow cards")
	t.ok(c.find_child("Board", true, false) is ShadowPanel, "the board is a see-through panel")
	c.free()
	var iced := best.duplicate()
	iced["iced"] = 2
	iced["tickets"] = 0
	c = screen.build_chrome(iced, false)
	t.ok(c.find_child("NewBest", true, false) == null, "not a best: no chip")
	t.ok(c.find_child("BestLine", true, false) != null, "the gap line instead")
	t.ok(c.find_child("Tile_ICED", true, false) != null, "the ICED tile")
	t.ok(c.find_child("Tickets", true, false) == null, "no tickets card without tickets")
	c.free()
	screen.free()
