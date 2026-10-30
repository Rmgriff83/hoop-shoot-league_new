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
	t.eq(ResultsCopy.title(best), "ARCADE CAGE", "the title is the area's name (design 7a: under the TIME TRIAL kicker)")
	t.eq(ResultsCopy.title({"location": "beach"}), "BEACH", "the beach too")
	t.eq(ResultsCopy.KICKER, "TIME TRIAL", "the kicker")
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
	t.eq(ResultsCopy.tickets(best, true), {"n": 30, "big": "+30", "sub": "TICKETS · BEST BONUS IN", "none": false}, "the tickets box on a best")
	t.eq(ResultsCopy.tickets(best, false)["sub"], "TICKETS", "and on a plain run")
	t.eq(ResultsCopy.tickets({"tickets": 0}, false), {"n": 0, "big": "+0", "sub": "TICKETS", "none": true}, "nothing earned: +0, dimmed, no stream")
	var top := [{"score": 31, "swishes": 7, "bestStreak": 8, "id": "r1"}, {"score": 27, "swishes": 5, "bestStreak": 6, "id": "r0"}, {"score": 26}]
	var rows := ResultsCopy.board(top, "r1")
	t.eq(rows.size(), 3, "every row")
	t.eq(rows[0], {"n": "1", "pts": "31", "sw": "7", "st": "8", "mine": true}, "this run is marked")
	t.eq(rows[1]["mine"], false, "the others are not")
	t.eq(rows[2]["sw"], "0", "an old row without swishes reads zero")
	var big := []
	for i in 14:
		big.push_back({"score": 40 - i})
	t.eq(ResultsCopy.board(big, "").size(), ResultsCopy.BOARD_SIZE, "the board is capped at five")
	big[7]["id"] = "me"
	var rows7 := ResultsCopy.board_rows(big, "me")
	t.eq(Array(rows7["top"]).size(), 5, "the top five")
	t.eq(Array(rows7["out"]).size(), 1, "…and this run as a sixth row when it is lower")
	t.eq(rows7["out"][0]["n"], "8", "…with its real rank")
	t.ok(Array(ResultsCopy.board_rows(top, "r1")["out"]).is_empty(), "no sixth row when this run is in the top five")
	# The stream: one flyer per two tickets, fifteen at most, the count in step with the landings.
	t.eq([TicketStream.count(0), TicketStream.count(1), TicketStream.count(30), TicketStream.count(100)], [0, 1, 15, 15], "flyers per haul")
	var stream := TicketStream.new()
	stream.manual = true
	stream.play(Vector2(150, 320), Vector2(490, 274), 30, 0.45)
	t.eq(stream.shown_at(0.0), 0, "nothing landed at the start")
	t.eq(stream.landed_at(0.45 + 0.75 + 0.01), 1, "the first flyer lands after its flight")
	t.eq(stream.shown_at(0.45 + 0.75 + 14 * 0.09 + 0.01), 30, "the last landing shows the whole haul")
	t.ok(stream.flyer_at(0, 0.2).is_empty() and not stream.flyer_at(0, 0.5).is_empty(), "a flyer is up only during its flight")
	t.ok(float(stream.flyer_at(0, 0.46)["scale"]) > 1.4 and float(stream.flyer_at(0, 0.46)["alpha"]) < 0.5, "…in big and faint")
	stream.free()
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
	t.ok(c.find_child("Stat_BONUS", true, false) != null and c.find_child("Stat_ICED", true, false) == null, "four stats, no ICED")
	t.ok(c.find_child("Tickets", true, false) is TicketBox, "the tickets box")
	t.eq((c.find_child("TicketsBig", true, false) as Label).text, "+30", "with the amount (off-tree: no stream, the full count)")
	t.ok((c.find_child("Kicker", true, false) as Label).text == "TIME TRIAL" and (c.find_child("Title", true, false) as Label).text == "ARCADE CAGE", "the TIME TRIAL kicker over the area name")
	t.ok(c.find_child("RunItBack", true, false) is ShadowCard and c.find_child("Home", true, false) is ShadowCard, "RUN IT BACK and HOME are shadow cards")
	t.ok((c.find_child("Home", true, false) as Control).get_parent() == (c.find_child("RunItBack", true, false) as Control).get_parent(), "…on one row")
	t.ok(c.find_child("Board", true, false) is ShadowPanel and c.find_child("Stream", true, false) is TicketStream, "the board is a see-through panel; the stream sits over the page")
	c.free()
	# 7a on both screens (2026-10-30): the 9:16 design's tops at 1280, the
	# iPhone design's at 1560.
	var rs := load("res://game/screens/results_screen.gd")
	t.eq(rs.tall_y(rs.BOARD_Y, rs.BOARD_Y_TALL, 1280.0), 556.0, "the board at 556 on a 9:16 screen")
	t.eq(rs.tall_y(rs.BOARD_Y, rs.BOARD_Y_TALL, 1560.0), 741.0, "…741 on the iPhone")
	t.eq(rs.tall_y(rs.BUTTONS_Y, rs.BUTTONS_Y_TALL, 1560.0), 1390.0, "the buttons at 1390 on it")
	t.ok(rs.tall_y(rs.HEAD_POS.y, rs.HEAD_Y_TALL, 1420.0) > 48.0 and rs.tall_y(rs.HEAD_POS.y, rs.HEAD_Y_TALL, 1420.0) < 134.0, "between, in between")
	var iced := best.duplicate()
	iced["iced"] = 2
	iced["tickets"] = 0
	c = screen.build_chrome(iced, false)
	t.ok(c.find_child("NewBest", true, false) == null, "not a best: no chip")
	t.ok(c.find_child("BestLine", true, false) != null, "the gap line instead")
	t.ok(c.find_child("Stat_ICED", true, false) != null, "the ICED stat")
	t.ok(c.find_child("Tickets", true, false) != null and (c.find_child("TicketsBig", true, false) as Label).text == "+0", "the box reads +0 without tickets")
	t.ok(absf((c.find_child("Tickets", true, false) as Control).modulate.a - 0.5) < 0.01, "…dimmed")
	c.free()
	screen.free()
