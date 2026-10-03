extends RefCounted
## The area archive (docs/HOME.md → Area archive): AreaArchiveCopy's open
## count, history line, lock line and rows by level; the page builds
## off-tree with a card per area (a locked one under the lock overlay and
## disabled, an open one with its `>` and history); `picked` fires once;
## the real-court snapshots and the lock icon ship.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func run(t) -> void:
	t.eq(AreaArchiveCopy.ids(), ["cage", "beach", "city"], "three areas in page order")
	t.eq(AreaArchiveCopy.index_of("beach"), 1, "the beach is the second page")
	t.eq(AreaArchiveCopy.index_of("nope"), -1, "an unknown area has no page")
	t.eq(AreaArchiveCopy.level_pad(3), "LVL03", "the padded level")
	t.eq(AreaArchiveCopy.lock_line(5), "OPENS AT LVL 5", "the lock line")
	t.eq(AreaArchiveCopy.history(2, 3, 31), ["2 TITLES", "3 SEASONS", "BEST 31"], "the history line")
	t.eq(AreaArchiveCopy.history(1, 1, 0), ["1 TITLE", "1 SEASON", "NO RUNS"], "singulars and no runs")
	var rows3 := AreaArchiveCopy.rows(3, [], {"cage": 31}, true, ["cage", "beach"])
	t.eq(rows3.size(), 3, "a row per area")
	t.eq(rows3[0]["name"], "ARCADE CAGE", "the cage's name")
	t.eq([rows3[0]["stars"], rows3[1]["stars"], rows3[2]["stars"]], [1, 2, 3], "stars 1 / 2 / 3")
	t.eq([rows3[0]["lvl"], rows3[1]["lvl"], rows3[2]["lvl"]], [1, 3, 5], "opens at 1 / 3 / 5")
	t.eq([rows3[0]["locked"], rows3[1]["locked"], rows3[2]["locked"]], [false, false, true], "at level 3 only the city is locked")
	t.eq(rows3[0]["history"], ["0 TITLES", "0 SEASONS", "BEST 31"], "the cage's history from the best")
	t.eq(AreaArchiveCopy.open_count(3, rows3), "2/3 OPEN", "two of three open")
	var rows1 := AreaArchiveCopy.rows(1, [], {}, true)
	t.eq(AreaArchiveCopy.open_count(1, rows1), "1/3 OPEN", "only the cage at level 1")
	t.ok(bool(rows1[1]["locked"]), "the beach is locked at level 1")
	var rows5 := AreaArchiveCopy.rows(5, [], {}, true)
	t.eq(AreaArchiveCopy.open_count(5, rows5), "3/3 OPEN", "everything at level 5")
	var ungated := AreaArchiveCopy.rows(1, [], {}, false)
	t.ok(not bool(ungated[2]["locked"]), "with the gate off (a debug build) the city is open")
	var visited := AreaArchiveCopy.rows(5, [], {}, true, ["cage", "beach"])
	t.eq([visited[0]["unvisited"], visited[1]["unvisited"], visited[2]["unvisited"]], [false, false, true], "the city is open and not yet visited")
	t.ok(not bool(AreaArchiveCopy.rows(3, [], {}, true, [])[2]["unvisited"]), "a locked area is never 'new'")
	# League history flows from the campaign doc.
	var cage := LeagueData.league("cage")
	var doc := Campaign.new_doc(cage, 5, 0)
	doc["career"]["championships"] = 2
	doc["career"]["seasons"] = [{}, {}, {}]
	var with_hist := AreaArchiveCopy.rows(5, [{"league": cage, "unlocked": true, "rule_met": true, "doc": doc}], {"cage": 40}, true)
	t.eq(with_hist[0]["history"], ["2 TITLES", "3 SEASONS", "BEST 40"], "titles and seasons from the career")
	# Every string in both pixel faces.
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in AreaArchiveCopy.strings(with_hist, "3/3 OPEN"):
		for ch in str(s):
			t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, s])
	# The snapshots and the lock icon ship.
	for id in AreaArchiveCopy.ids():
		var path := "res://assets/ui/areas/area_%s.png" % id
		t.ok(ResourceLoader.exists(path), "the %s snapshot ships (--qa-area-snaps)" % id)
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			t.ok(tex.get_width() > tex.get_height(), "the %s snapshot is landscape" % id)
	t.ok(ResourceLoader.exists("res://assets/ui/icon_lock.png"), "the lock icon ships")
	# The page.
	var page := AreaArchivePage.new()
	var root := page.build(rows3, "2/3 OPEN")
	t.eq(page.cards(), ["cage", "beach", "city"], "a card per area")
	t.eq((root.find_child("OpenCount", true, false) as Label).text, "2/3 OPEN", "the open count in the header")
	t.ok(root.find_child("Back", true, false) != null, "the < back button")
	var city: Button = page.card("city")
	t.ok(city.disabled, "the locked city cannot be tapped")
	t.ok(city.find_child("Lock", true, false) != null, "…and sits under the lock overlay")
	t.eq((city.find_child("LockLine", true, false) as Label).text, "OPENS AT LVL 5", "with the level that opens it")
	t.ok(city.find_child("Go", true, false) == null and city.find_child("History", true, false) == null, "no > and no history on a locked area")
	var cage_card: Button = page.card("cage")
	t.ok(not cage_card.disabled and cage_card.find_child("Go", true, false) != null, "the open cage has its >")
	t.eq((cage_card.find_child("Hist2", true, false) as Label).text, "BEST 31", "…and its history")
	t.eq((cage_card.find_child("Name", true, false) as Label).text, "ARCADE CAGE", "the name on the card")
	t.eq(cage_card.find_child("Stars", true, false).get_child_count(), 1, "one star on the cage")
	t.ok(cage_card.find_child("Snap", true, false) != null, "the snapshot on the card")
	t.ok(cage_card.find_child("NewBadge", true, false) == null, "no NEW badge once visited")
	var fresh := AreaArchivePage.new()
	fresh.build(AreaArchiveCopy.rows(5, [], {}, true, ["cage"]), "3/3 OPEN")
	t.ok(fresh.card("beach").find_child("NewBadge", true, false) != null, "an unvisited open area wears the NEW badge")
	t.ok(fresh.card("cage").find_child("NewBadge", true, false) == null, "the visited cage does not")
	fresh.free()
	_visits(t)
	var got := []
	page.picked.connect(func(id: String) -> void: got.push_back(id))
	page.pick("city")
	t.eq(got, [], "picking a locked area does nothing")
	page.pick("beach")
	page.pick("cage")
	t.eq(got, ["beach"], "picking an open area fires once")
	page.free()
	var hidden := AreaArchivePage.new()
	hidden.build(rows1, "1/3 OPEN", false)
	t.ok(not (hidden.page_root().find_child("Back", true, false) as Control).visible, "no < when there is nothing open behind")
	hidden.free()


func _visits(t) -> void:
	var app = _app()
	if app == null:
		return
	var before: Dictionary = SaveService.get_settings()
	var st := before.duplicate(true)
	st["visitedAreas"] = []
	SaveService.put_settings(st)
	t.eq(app.visited_areas(), [], "a fresh save has visited nothing")
	t.ok(app.area_unvisited("cage"), "the cage is open and new")
	app.mark_area_visited("cage")
	app.mark_area_visited("cage")
	t.eq(app.visited_areas(), ["cage"], "visiting records once")
	t.ok(not app.area_unvisited("cage"), "…and the cage is no longer new")
	SaveService.put_settings(before)
