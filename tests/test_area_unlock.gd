extends RefCounted
## The Area Unlock page (design "Area Unlock" 18a): which level rise opens
## which area, the page's copy, its timeline (the lock, the shackle, NEW
## AREA, the buttons) and App's once-only bookkeeping.


func run(t) -> void:
	_crossing(t)
	_copy(t)
	_page(t)
	_app(t)


func _crossing(t) -> void:
	t.eq(AreaUnlockCopy.crossed(2, 3), "beach", "reaching 3 opens the beach")
	t.eq(AreaUnlockCopy.crossed(4, 5), "city", "reaching 5 opens the city")
	t.eq(AreaUnlockCopy.crossed(2, 5), "beach", "a jump across both opens the beach first")
	t.eq(AreaUnlockCopy.crossed(3, 4), "", "3 → 4 opens nothing")
	t.eq(AreaUnlockCopy.crossed(1, 1), "", "no rise, nothing")
	t.eq(AreaUnlockCopy.crossed(0, 1), "", "the cage is never an unlock")


func _copy(t) -> void:
	var b := AreaUnlockCopy.state("beach", 3)
	t.eq(b["level_text"], "LEVEL 03 REACHED", "the level chip")
	t.eq(b["name"], "BEACH", "the beach's name")
	t.eq(b["go_sub"], "BEACH HOME", "where GO THERE goes")
	t.ok(int(b["stars"]) >= 1, "its stars")
	t.eq(b["opens"].size(), 3, "LEAGUE / TIME TRIAL / PRACTICE chips")
	t.ok(str(b["snap"]).ends_with("area_beach.png") and str(b["snap_tall"]).ends_with("area_beach_tall.png"), "its real renders")
	var c := AreaUnlockCopy.state("city", 5)
	t.eq(c["name"], "CITY COURT", "the city's name")
	t.ok(c["ray"] != b["ray"], "each area has its own ray colour")
	for v in [b, c]:
		for s in AreaUnlockCopy.strings(v):
			for ch in str(s):
				t.ok(UiFont.display().has_char(ch.unicode_at(0)) and UiFont.body_bold().has_char(ch.unicode_at(0)), "'%s' glyph in both faces" % ch)
	t.ok(FileAccess.file_exists("res://assets/ui/lock_closed.png") and FileAccess.file_exists("res://assets/ui/lock_open.png"), "the lock sprites ship")


func _page(t) -> void:
	var page := AreaUnlockPage.new()
	var root := page.build(AreaUnlockCopy.state("beach", 3))
	for n in ["Bg", "Dim", "Rays", "Confetti", "LevelChip", "Frame", "Snap", "Veil", "Lock", "LockClosed", "LockOpen", "Ring", "Title", "Stars", "Name", "Opens", "GoThere", "Later", "Flash"]:
		t.ok(root.find_child(n, true, false) != null, "%s on the page" % n)
	t.eq(root.find_child("Stars", true, false).get_child_count(), int(AreaUnlockCopy.state("beach", 3)["stars"]), "a star per level star")
	t.eq(page.confetti_count(), 60, "sixty pieces of confetti")
	var lock: Control = root.find_child("Lock", true, false)
	t.close(lock.modulate.a, 0.0, 1e-9, "the lock is not there at 0")
	page.step(1.0)
	t.ok(lock.modulate.a > 0.99 and not page.lock_open(), "at 1 s the closed lock is up")
	t.ok(root.find_child("LockClosed", true, false).visible, "…closed")
	t.close(page.rays_alpha(), 0.0, 1e-9, "…no rays yet")
	page.step(0.3)
	t.ok(absf(lock.rotation_degrees) > 0.0, "…rattling at 1.3 s")
	page.step(0.35)
	t.ok(page.lock_open(), "at 1.65 s the shackle has sprung")
	t.ok(not root.find_child("LockClosed", true, false).visible, "…the closed sprite is gone")
	page.step(0.65)
	t.ok(page.lock_gone(), "by 2.3 s the lock has flown away")
	t.ok(page.rays_alpha() > 0.9, "…and the rays are up")
	t.ok(root.find_child("Confetti", true, false).visible, "…confetti falling")
	var title: Control = root.find_child("Title", true, false)
	page.step(0.3)
	t.ok(title.modulate.a > 0.0, "NEW AREA is in by 2.6 s")
	t.ok(not page.buttons_shown(), "…buttons not yet")
	page.step(1.1)
	t.ok(page.buttons_shown(), "the buttons are up by 3.7 s")
	var went := []
	page.go_there.connect(func(id: String) -> void: went.push_back(id))
	var later_n := [0]
	page.later.connect(func() -> void: later_n[0] += 1)
	(root.find_child("GoThere", true, false) as Button).pressed.emit()
	(root.find_child("Later", true, false) as Button).pressed.emit()
	t.eq(went, ["beach"], "GO THERE says where")
	t.eq(later_n[0], 1, "LATER")
	page.free()


func _app(t) -> void:
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		return
	var kept: Dictionary = SaveService.get_settings().duplicate(true)
	var st := SaveService.get_settings()
	st["unlocksSeen"] = []
	SaveService.put_settings(st)
	t.ok(not app.unlock_seen("beach"), "fresh: the beach unlock is unseen")
	app.pending_unlock = "beach"
	t.eq(app.take_pending_unlock(), "beach", "the pending unlock is handed over once")
	t.eq(app.take_pending_unlock(), "", "…then empty")
	app.mark_unlock_seen("beach")
	t.ok(app.unlock_seen("beach") and not app.unlock_seen("city"), "seen is per area and persists")
	t.ok(SaveService.default_settings().has("unlocksSeen"), "the settings schema carries it")
	SaveService.put_settings(kept)
