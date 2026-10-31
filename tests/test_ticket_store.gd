extends RefCounted
## The Ticket Store (design "Ticket Store" 50a, docs/ECONOMY.md → Ticket
## packs): the two packs and their prices, the page's rows, the price
## button's idle → ask → busy → idle run (the store is a stub: no sale,
## nothing granted), the success shown (+N, the flight, the count), the
## tkFly / donePop keys, the tappable ticket chips and where the store opens.


func run(t) -> void:
	_packs(t)
	_keys(t)
	_page(t)
	_chips(t)
	_wiring(t)


func _packs(t) -> void:
	t.eq(TicketShop.PACKS.size(), 2, "two packs")
	t.eq(int(TicketShop.PACKS[0]["tickets"]), 300, "300 tickets…")
	t.eq(TicketShop.price("tickets_300"), "$0.99", "…for $0.99")
	t.eq(int(TicketShop.PACKS[1]["tickets"]), 1000, "1000 tickets…")
	t.eq(TicketShop.price("tickets_1000"), "$2.99", "…for $2.99")
	t.ok(not bool(TicketShop.PACKS[0].get("best", false)) and bool(TicketShop.PACKS[1].get("best", false)), "only the 1000 is BEST VALUE")
	t.ok(TicketShop.pack("nope").is_empty(), "an unknown pack is nothing")
	for ch in ["$", ".", "+", "'"]:
		t.ok(UiFont.display().has_char(ch.unicode_at(0)) and UiFont.body_bold().has_char(ch.unicode_at(0)), "both faces carry '%s'" % ch)


func _keys(t) -> void:
	var s := Vector2(500, 400)
	var m := Vector2(300, 200)
	var e := Vector2(560, 150)
	var a := CssEase.tk_fly(0.0, s, m, e, -18.0, 12.0)
	t.ok(a["pos"] == s and is_equal_approx(float(a["scale"]), 1.3) and float(a["alpha"]) == 0.0, "tkFly: starts at the pack, ×1.3, unseen")
	t.close(float(CssEase.tk_fly(0.12, s, m, e, -18.0, 12.0)["alpha"]), 1.0, 1e-6, "…up by 12 %")
	var mid := CssEase.tk_fly(0.55, s, m, e, -18.0, 12.0)
	t.ok(mid["pos"] == m and is_equal_approx(float(mid["scale"]), 1.05) and is_equal_approx(float(mid["rot"]), 12.0), "…the midpoint at 55 %, ×1.05, counter-tilted")
	var end := CssEase.tk_fly(1.0, s, m, e, -18.0, 12.0)
	t.ok(end["pos"] == e and is_equal_approx(float(end["scale"]), 0.55) and float(end["alpha"]) == 0.0, "…lands in the chip ×.55 and gone")
	t.close(CssEase.done_pop(0.0).x, 0.7, 1e-6, "donePop: from ×.7…")
	t.close(CssEase.done_pop(0.6 * CssEase.DONE_POP_S).x, 1.08, 1e-4, "…×1.08 at 60 %…")
	t.close(CssEase.done_pop(0.6 * CssEase.DONE_POP_S).y, 1.0, 1e-4, "…fully up there…")
	t.close(CssEase.done_pop(CssEase.DONE_POP_S).x, 1.0, 1e-6, "…settling at ×1")
	t.close(CssEase.cnt_bump(0.35 * 0.2, 0.2, 1.25), 1.25, 1e-4, "the chip's ticket bumps ×1.25 at 35 % of 0.2 s")


func _page(t) -> void:
	var page := TicketStorePage.new()
	page._ready()
	t.eq((page.find_child("Title", true, false) as Label).text, "TICKETS", "TICKETS heads the page")
	var chip: Control = page.find_child("Balance", true, false)
	t.ok(chip != null and chip.custom_minimum_size == TicketStorePage.CHIP + Vector2.ONE * ShadowStyle.OFFSET, "the balance chip is 170 × 104")
	t.eq(page.balance_text(), RetroTheme.thousands(App.tickets()), "…showing the balance")
	t.eq((page.find_child("Line", true, false) as Label).text, TicketStorePage.LINE, "the line on what tickets buy")
	for i in 2:
		var pack: Control = page.find_child("Pack%d" % i, true, false)
		t.ok(pack != null and is_equal_approx(pack.size.y, TicketStorePage.PACK_H + ShadowStyle.OFFSET), "pack %d is 250 tall" % i)
		var amount := pack.find_child("Amount", true, false) as Label
		t.eq(amount.text, str(int(TicketShop.PACKS[i]["tickets"])), "…its amount")
		t.eq(amount.get_theme_color("font_color"), LeagueContext.HI, "…in butter")
		t.eq(pack.find_child("Art", true, false).get_child_count(), TicketStorePage.FAN[i].size(), "…its fan of tickets")
	t.eq(page.find_children("BestValue", "", true, false).size(), 1, "one BEST VALUE tag…")
	var tag: Control = page.find_child("BestValue", true, false)
	var pack1: Control = page.find_child("Pack1", true, false)
	t.close(tag.position.y, pack1.position.y - 16.0, 0.01, "…16 px over the 1000's top")
	t.close(tag.position.x + tag.size.x - TicketStorePage.BestTag.DROP, pack1.size.x - ShadowStyle.OFFSET + 6.0, 0.01, "…6 px past its right edge")
	# The price button.
	var area0: Control = page.find_child("Pack0", true, false).find_child("BuyArea", true, false)
	t.eq(page.state(0), "idle", "idle at first")
	t.eq((area0.find_child("Price", true, false) as Button).text, "$0.99", "…showing the price")
	(area0.find_child("Price", true, false) as Button).pressed.emit()
	t.eq(page.state(0), "ask", "a tap asks")
	_free_now(area0)
	t.ok(area0.find_child("Cancel", true, false) != null and area0.find_child("Confirm", true, false) != null, "…X and BUY")
	t.eq((area0.find_child("Confirm", true, false).find_child("Word", true, false) as Label).text, "BUY", "…BUY over…")
	t.eq((area0.find_child("Confirm", true, false).find_child("Price", true, false) as Label).text, "$0.99", "…the price")
	(area0.find_child("Cancel", true, false) as Button).pressed.emit()
	t.eq(page.state(0), "idle", "X goes back")
	page.tap(0)
	var before := App.tickets()
	page.confirm(0)
	t.eq(page.state(0), "busy", "BUY waits on the store")
	_free_now(area0)
	t.ok(area0.find_child("Spinner", true, false) is PixelSpinner, "…with the spinner")
	t.eq(area0.find_children("*", "Button", true, false).size(), 0, "…and nothing to press")
	page._on_result(false, 0)
	t.eq(page.state(0), "idle", "no sale: back to the price")
	t.eq(App.tickets(), before, "…and nothing granted")
	# The success, shown.
	page.show_bought(1, 340)
	t.eq(page.state(1), "done", "a sale shows done")
	var area1: Control = pack1.find_child("BuyArea", true, false)
	_free_now(area1)
	t.eq((area1.find_child("Word", true, false) as Label).text, "+1000", "…+1000")
	t.eq(page.balance_text(), "340", "the chip counts from the old balance")
	var fl := page.flight()
	t.eq(fl.flyers_for(1000), 12, "12 tickets fly for the 1000…")
	t.eq(fl.flyers_for(300), 6, "…6 for the 300")
	fl.manual = true
	for k in 60:
		fl.step(1.0 / 30.0)
	t.eq(fl.shown(), 1000, "every flyer down: the whole pack")
	page._on_count(fl.shown())
	t.eq(page.balance_text(), "1,340", "…the chip reads old + 1000")
	t.eq(App.tickets(), before, "…still nothing granted (visual only)")
	page._process(TicketStorePage.DONE_S + 0.1)
	t.eq(page.state(1), "idle", "done goes back to the price")
	var closed_ := [false]
	page.closed.connect(func() -> void: closed_[0] = true)
	(page.find_child("Back", true, false) as Button).pressed.emit()
	t.ok(closed_[0], "BACK closes the store")


## Children replaced by _fill wait for queue_free; drop them so find_child sees the new ones.
func _free_now(area: Control) -> void:
	for c in area.get_children():
		if c.is_queued_for_deletion():
			area.remove_child(c)


func _chips(t) -> void:
	var pill := CoinsPill.new()
	t.eq(pill.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the pill ignores taps by default")
	pill.tappable = true
	t.eq(pill.mouse_filter, Control.MOUSE_FILTER_STOP, "…a tappable one takes them")
	var hits := [0]
	pill.pressed.connect(func() -> void: hits[0] += 1)
	pill._gui_input(_click(Vector2(20, 20), true))
	pill._gui_input(_click(Vector2(24, 22), false))
	t.eq(hits[0], 1, "…a tap presses it")
	pill._gui_input(_click(Vector2(20, 20), true))
	pill._gui_input(_click(Vector2(80, 20), false))
	t.eq(hits[0], 1, "…a drag doesn't")
	pill.free()
	var panel := TapPanel.new()
	var taps := [0]
	panel.pressed.connect(func() -> void: taps[0] += 1)
	panel._gui_input(_click(Vector2(10, 10), true))
	panel._gui_input(_click(Vector2(10, 12), false))
	panel._gui_input(_click(Vector2(10, 10), true))
	panel._gui_input(_click(Vector2(10, 40), false))
	t.eq(taps[0], 1, "a TapPanel: a tap presses, a drag past 18 px doesn't")
	panel.free()
	# The pages' ticket panel asks for the store.
	var page := HomePage.new()
	page.body = VBoxContainer.new()
	var tp := page.ticket_panel()
	var asked := [false]
	page.store_requested.connect(func() -> void: asked[0] = true)
	tp.pressed.emit()
	t.ok(asked[0], "the locker / PEGGY ticket panel asks for the store")
	page.body.free()
	tp.free()
	page.free()


func _click(at: Vector2, down: bool) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.position = at
	return mb


func _wiring(t) -> void:
	var src := FileAccess.get_file_as_string("res://game/screens/title_screen.gd")
	t.ok(src.contains("_wallet.pressed.connect(_open_store)"), "the home's ticket chip opens the store")
	t.ok(src.contains("_locker.store_requested.connect(_open_store)"), "…the locker's ticket panel")
	t.ok(src.contains("_peggy.store_requested.connect(_open_store)"), "…PEGGY's")
	t.ok(src.contains("lc.store_requested.connect(_open_store)"), "…and a league card you can't afford")
	t.ok(src.contains("under.slide_out(true, false)"), "the page under it slides out to the left")
	t.ok(src.contains("under.slide_in(true)"), "…and comes back on BACK")
