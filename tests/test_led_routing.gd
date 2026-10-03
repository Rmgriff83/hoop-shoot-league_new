extends RefCounted
## The two reader boards (2026-10-03): in the cage the hoop's board shows
## nothing but the score and every message (GO!, SWISH +2, HEATING UP, MOVE
## TO …) goes to the back wall's ribbon, which idles blank. On an arena with
## no ribbon the hoop's board carries both, as before.


func run(t) -> void:
	var root := Node3D.new()
	# The cage: a ribbon.
	var cage := CourtGeometry.new()
	cage.geo = SimGeometry.arcade()
	cage.arena_set = CosmeticLibrary.get_arena("cage")
	cage.hoop_set = CosmeticLibrary.starter_hoop()
	root.add_child(cage)
	cage._ready()   # headless: no tree frame, so ready it by hand like the other view tests
	t.ok(cage.league_led != null, "the cage has its ribbon board")
	t.ok(cage.info == cage.league_led and cage.info != cage.led, "messages go to the ribbon")
	t.eq(cage.info.idle_text(), "", "the ribbon idles blank")
	t.eq(cage.led.idle_text(), "SCORE 0", "the hoop's board idles on the score")
	cage.info.advance(0.0)
	t.eq(cage.info.lit_count(), 0, "…so nothing is lit on it before a message")
	cage.info.flash("GO!", 1, cage.info.accent_color)
	cage.info.advance(0.0)
	t.ok(cage.info.lit_count() > 0, "a message lights the ribbon")
	cage.info.advance(LedBoard.FLASH_PERIOD * 2 + 0.01)
	t.eq(cage.info.mode(), "idle", "…and it finishes")
	cage.info.advance(0.0)
	t.eq(cage.info.lit_count(), 0, "…back to blank")
	cage.led.show_score(7)
	cage.led.advance(0.0)
	t.ok(cage.led.lit_count() > 0 and cage.led.mode() == "idle", "the hoop's board keeps the score")
	t.ok(not cage.has_method("set_ticker"), "no attract ticker on the ribbon any more")
	# The beach: no ribbon, one board for both.
	var beach := CourtGeometry.new()
	beach.geo = SimGeometry.beach()
	beach.arena_set = CosmeticLibrary.get_arena("beach")
	beach.hoop_set = CosmeticLibrary.get_hoop("street") if CosmeticLibrary.get_hoop("street") != null else CosmeticLibrary.starter_hoop()
	root.add_child(beach)
	beach._ready()
	t.ok(beach.league_led == null and beach.info == beach.led, "the beach's one board takes the messages")
	root.free()
