extends RefCounted
## LedBoard: 3×5 font rendering into the 48×8 LED matrix, event queue
## (flash / marquee → back to idle), and the backboard band schedule.


func _glyph_count(text: String) -> int:
	var n := 0
	for ch in text:
		var key: String = ch if LedBoard.FONT.has(ch) else ch.to_upper()
		if LedBoard.FONT.has(key):
			for row in LedBoard.FONT[key]:
				n += row.count("#")
	return n


func run(t) -> void:
	var led := LedBoard.new()
	t.eq(led.material.albedo_texture.get_width(), LedBoard.WIDTH, "texture is 192 wide")
	t.eq(led.material.albedo_texture.get_height(), LedBoard.HEIGHT, "texture is 32 tall")
	var wide := LedBoard.new(LedBoard.LEAGUE_COLS)
	t.eq(wide.material.albedo_texture.get_width(), LedBoard.LEAGUE_COLS * LedBoard.CELL, "the league ribbon is 288 wide")
	t.eq(wide.cols, 72, "…72 columns")
	wide.free()

	# Every glyph renders, and the lit count matches the font's '#' count.
	for key in LedBoard.FONT.keys():
		led.set_text(key)
		led.advance(0.0)
		t.eq(led.lit_count(), _glyph_count(key), "glyph '%s' lights its dots" % key)

	# Idle score line.
	led.set_text("")
	led._mode = "idle"
	led.show_score(12)
	led.advance(0.0)
	t.eq(led.mode(), "idle", "idle after show_score")
	t.eq(led.lit_count(), _glyph_count("SCORE 12"), "SCORE 12 lit count")
	led.show_score(12, 3)
	led.advance(0.0)
	t.eq(led.lit_count(), _glyph_count("SCORE 12 x3"), "streak tier tag renders (SCORE 12 x3)")
	led.show_score(12)
	led.advance(0.0)

	# Unknown characters are blank, lowercase maps to uppercase.
	led.set_text("é")
	led.advance(0.0)
	t.eq(led.lit_count(), 0, "unknown char renders blank")
	led.set_text("go")
	led.advance(0.0)
	t.eq(led.lit_count(), _glyph_count("GO"), "lowercase renders as uppercase")

	# Flash: blinks `times` times then returns to idle (with the score restored).
	led.set_text("")
	led._mode = "idle"
	led.flash("GO!", 2)
	t.eq(led.mode(), "flash", "flash starts immediately from idle")
	led.advance(0.0)
	var on_count := led.lit_count()
	t.ok(on_count > 0, "flash frame on")
	led.advance(LedBoard.FLASH_PERIOD + 0.001)
	t.eq(led.lit_count(), 0, "flash frame off")
	led.advance(LedBoard.FLASH_PERIOD * 3 + 0.01)
	t.eq(led.mode(), "idle", "flash finishes back to idle")
	t.eq(led.lit_count(), _glyph_count("SCORE 12"), "score restored after flash")

	# Marquee scrolls right→left and ends back on idle; queued events run in order.
	led.marquee("HOT STREAK", 40.0)
	led.flash("X", 1)
	t.eq(led.mode(), "marquee", "marquee running")
	led.advance(0.5)
	t.ok(led._marquee_x < float(LedBoard.COLS), "marquee advanced")
	led.advance(3.0)
	t.eq(led.mode(), "flash", "queued flash starts after the marquee")
	led.advance(1.0)
	t.eq(led.mode(), "idle", "queue drains to idle")

	# set_text interrupts and clears the queue.
	led.marquee("A", 10.0)
	led.flash("B", 1)
	led.set_text("TIME")
	t.eq(led.mode(), "text", "set_text overrides")
	led.advance(5.0)
	t.eq(led.mode(), "text", "persistent text stays")
	t.eq(led.lit_count(), _glyph_count("TIME"), "TIME rendered")

	# Band schedule + states.
	t.close(LedBoard.band_hz_for(30.0), 0.0, 0.0, "band off above 10 s")
	t.close(LedBoard.band_hz_for(10.0), 1.0, 0.0, "band 1 Hz at 10 s")
	t.close(LedBoard.band_hz_for(7.0), 1.0, 0.0, "band 1 Hz at 7 s")
	t.close(LedBoard.band_hz_for(4.9), 2.0, 0.0, "band 2 Hz under 5 s")
	t.close(LedBoard.band_hz_for(0.0), 2.0, 0.0, "band 2 Hz at 0 s")
	led.band_flash(LedBoard.YELLOW, 1.0)
	led.advance(0.1)
	t.ok(led.band_lit(), "1 Hz band lit in the first half-second")
	led.advance(0.5)
	t.ok(not led.band_lit(), "1 Hz band off in the second half-second")
	led.band_solid(LedBoard.BAND_RED, 2.0)
	t.ok(led.band_lit(), "solid band lit immediately")
	t.eq(led.band_material.albedo_color, LedBoard.BAND_RED, "solid band is red")
	led.advance(1.0)
	t.ok(led.band_lit(), "solid holds through its duration")
	led.advance(1.5)
	t.ok(not led.band_lit() or led._band_hz > 0.0, "solid expires")
	led.band_off()
	led.advance(0.1)
	t.ok(not led.band_lit(), "band_off turns it off")
	# Ribbon board: unlike a marquee it never finishes, it rotates.
	var rb := LedBoard.new()
	rb.ticker(PackedStringArray(["ONE", "TWO", "THREE"]), 20.0)
	t.eq(rb.mode(), "ticker", "ticker mode starts")
	t.eq(rb.ticker_index(), 0, "on the first item")
	for i in 600:
		rb.advance(1.0 / 60.0)
		if rb.ticker_index() == 1:
			break
	t.eq(rb.ticker_index(), 1, "advances to the next item once one scrolls off")
	t.eq(rb.mode(), "ticker", "and keeps running instead of finishing")
	# It wraps rather than stopping at the end of the list.
	for i in 3000:
		rb.advance(1.0 / 60.0)
		if rb.ticker_index() == 0:
			break
	t.eq(rb.ticker_index(), 0, "wraps back to the start")
	# Swapping content must not restart the slide in progress: a score changing
	# mid-scroll would otherwise make the text jump.
	rb.ticker(PackedStringArray(["AAAA", "BBBB"]), 20.0)
	rb.advance(0.2)
	var x_before: float = rb._marquee_x
	rb.set_ticker_items(PackedStringArray(["CCCC", "DDDD"]))
	t.close(rb._marquee_x, x_before, 1e-9, "swapping items leaves the current slide alone")
	t.eq(rb._text, "AAAA", "the old item finishes its pass")
	for i in 600:
		rb.advance(1.0 / 60.0)
		if rb._text != "AAAA":
			break
	t.eq(rb._text, "DDDD", "the new list takes over at the wrap")
	# Paused: the ribbon holds where it is rather than snapping back, and the
	# band tick below it in advance() must keep running (a `return` there would
	# have silently killed the backboard light band on every board).
	rb.ticker(PackedStringArray(["HOLD"]), 20.0)
	rb.advance(0.3)
	var held: float = rb._marquee_x
	rb.set_ticker_paused(true)
	for i in 60:
		rb.advance(1.0 / 60.0)
	t.close(rb._marquee_x, held, 1e-9, "a paused ribbon does not move")
	t.ok(rb.ticker_paused(), "and reports itself paused")
	rb.band_solid(Color.RED, 0.05)
	rb.advance(0.2)
	t.ok(not rb.band_lit(), "the band still ticks while the ribbon is paused")
	rb.set_ticker_paused(false)
	rb.advance(0.2)
	t.ok(rb._marquee_x < held, "and it resumes from where it stopped")
	rb.free()

	led.free()
