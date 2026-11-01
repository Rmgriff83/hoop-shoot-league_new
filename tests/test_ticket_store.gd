extends RefCounted
## The Ticket Store (design "Ticket Store" 50a, docs/ECONOMY.md → Ticket
## packs): the packs from data/store.json, the page's rows, the price
## button's run, the success shown (+N, the flight, the count), the tkFly /
## donePop keys, the tappable ticket chips and where the store opens — and
## `Store`, the buying: RevenueCat's sheet (a FakeStoreBackend) then the
## Worker's credit (a scripted Net.transport: pending → claim → grant), with
## cancels, errors, the slow credit, the stub without a store, and the
## syncs at resume and after /v1/me.


var _calls: Array = []
var _srv := {"pending": [], "claims": [], "gets": 0, "appear_at": -1, "row": {}}
var _slept: Array = []


func _transport(method: int, path: String, body: Variant, headers: PackedStringArray) -> Dictionary:
	var names := {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_PUT: "PUT", HTTPClient.METHOD_DELETE: "DELETE", HTTPClient.METHOD_PATCH: "PATCH"}
	var key := "%s %s" % [str(names.get(method, str(method))), path]
	_calls.push_back({"key": key, "body": body, "headers": headers})
	match key:
		"GET /v1/store/pending":
			_srv["gets"] = int(_srv["gets"]) + 1
			if int(_srv["appear_at"]) >= 0 and int(_srv["gets"]) >= int(_srv["appear_at"]):
				_srv["pending"] = [_srv["row"]]
				_srv["appear_at"] = -1
			var sum := 0
			for r in _srv["pending"]:
				sum += int(r["tickets"])
			return {"code": 200, "json": {"pending": Array(_srv["pending"]).duplicate(true), "tickets": sum}}
		"POST /v1/store/claim":
			var ids: Array = Array(Dictionary(body).get("ids", []))
			_srv["claims"].push_back(ids.duplicate())
			var claimed: Array = []
			var left: Array = []
			for r in _srv["pending"]:
				if ids.has(int(r["id"])):
					claimed.push_back({"id": r["id"], "productId": r["productId"], "tickets": r["tickets"]})
				else:
					left.push_back(r)
			_srv["pending"] = left
			var sum := 0
			for r in claimed:
				sum += int(r["tickets"])
			return {"code": 200, "json": {"claimed": claimed, "tickets": sum}}
		"GET /v1/save":
			return {"code": 200, "json": {"parts": {}, "now": 0}}
	return {"code": 404, "json": {"error": "not_found"}}


func _row(id: int, product: String) -> Dictionary:
	return {"id": id, "productId": product, "tickets": int(TicketShop.pack(product)["tickets"]), "purchasedAt": 1}


func run(t) -> void:
	var root = Engine.get_main_loop().root
	var net: Node = root.get_node_or_null("Net")
	var store: Node = root.get_node_or_null("Store")
	var save: Node = root.get_node("SaveService")
	var app: Node = root.get_node("App")
	if net == null or store == null:
		t.ok(false, "Net and Store autoloads present")
		return
	# The world: a registered account, no HTTP, no timers, a fake store.
	var was_enabled: bool = net.enabled
	var was_account: Dictionary = save.get_account()
	var was_backend = store.backend
	net.enabled = true
	net.transport = _transport
	net._blocked_until = 0.0
	net._fails = 0
	save.put_account({"playerId": SaveService.uuid4(), "secret": "s".repeat(40), "name": "BRICK BARON", "tag": "42", "registered": true})
	StoreKeys.set_keys_for_test({"ios": "appl_test", "android": "goog_test"})
	var fake := FakeStoreBackend.new()
	store.use_backend(fake)
	store.sleep = func(s: float) -> void: _slept.push_back(s)

	_packs(t)
	_keys(t)
	_store(t, store, net, save, app, fake)
	await _plugin(t, store, save, app, fake)
	_page(t, store, app, fake)
	_chips(t)
	_wiring(t)

	# Put the world back.
	store.use_backend(was_backend)
	store.sleep = Callable()
	net.transport = Callable()
	net.enabled = was_enabled
	StoreKeys.set_keys_for_test({})
	save.wipe_all()
	if not was_account.is_empty():
		save.put_account(was_account)


func _packs(t) -> void:
	var packs := TicketShop.packs()
	t.eq(packs.size(), 2, "two packs, from data/store.json")
	t.eq(int(packs[0]["tickets"]), 300, "300 tickets…")
	t.eq(str(packs[0]["price"]), "$0.99", "…for $0.99 (the US tier)")
	t.eq(int(packs[1]["tickets"]), 1000, "1000 tickets…")
	t.eq(str(packs[1]["price"]), "$2.99", "…for $2.99")
	t.ok(not bool(packs[0]["best"]) and bool(packs[1]["best"]), "only the 1000 is BEST VALUE")
	t.eq(TicketShop.ids(), ["tickets_300", "tickets_1000"], "the store's product ids")
	t.ok(TicketShop.pack("nope").is_empty(), "an unknown pack is nothing")
	for ch in ["$", ".", "+", "'"]:
		t.ok(UiFont.display().has_char(ch.unicode_at(0)) and UiFont.body_bold().has_char(ch.unicode_at(0)), "both faces carry '%s'" % ch)
	for s in StoreCopy.strings():
		for ch in s:
			t.ok(UiFont.body_bold().has_char(ch.unicode_at(0)), "the bold face carries '%s' (%s)" % [ch, s])


func _keys(t) -> void:
	t.eq(StoreKeys.revenuecat_key("iOS"), "appl_test", "the iOS key")
	t.eq(StoreKeys.revenuecat_key("Android"), "goog_test", "the Android key")
	t.eq(StoreKeys.revenuecat_key("macOS"), "", "no key on the desktop")
	StoreKeys.set_keys_for_test({"ios": "appl_REPLACE_ME"})
	t.eq(StoreKeys.revenuecat_key("iOS"), "", "the example's placeholder is no key")
	StoreKeys.set_keys_for_test({"ios": "appl_test", "android": "goog_test"})
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


## Store: the buying, the bball_sim way — the phone never credits itself.
func _store(t, store, net, save, app, fake: FakeStoreBackend) -> void:
	var pid := str(save.get_account()["playerId"])
	store.ensure()
	t.eq(fake.configured.size(), 1, "ensure starts the SDK once…")
	t.eq(fake.configured[0][1], pid, "…as this player (the app user id is the player id)")
	store.ensure()
	t.eq(fake.configured.size(), 1, "…and not again")
	t.ok(store.live(), "a store and an account: live")
	# Prices: the store's own strings replace the US tiers.
	var changed := [0]
	store.prices_changed.connect(func() -> void: changed[0] += 1)
	store.fetch_prices()
	t.eq(fake.fetched, [["tickets_300", "tickets_1000"]], "fetch_prices asks for both packs")
	t.eq(changed[0], 1, "…and says so")
	t.eq(TicketShop.price("tickets_300"), "CA$1.39", "the pack shows the store's price…")
	t.eq(TicketShop.price("tickets_1000"), "CA$3.99", "…in the player's currency")
	var done: Array = []
	var credited: Array = []
	store.purchase_done.connect(func(id: String, ok: bool, reason: String) -> void: done.push_back([id, ok, reason]))
	store.tickets_credited.connect(func(n: int) -> void: credited.push_back(n))
	# A sale: the sheet, then pending at the Worker, claimed once, granted.
	var before: int = app.tickets()
	_srv["pending"] = [_row(7, "tickets_300")]
	_calls.clear()
	await store.purchase("tickets_300")
	t.eq(fake.bought, ["tickets_300"], "purchase opens the sheet for the pack")
	t.eq(done, [["tickets_300", true, ""]], "the credit landed: done, ok")
	t.eq(app.tickets(), before + 300, "…300 tickets granted, from the Worker's answer")
	t.eq(credited, [300], "…and tickets_credited said 300")
	t.eq(_srv["claims"], [[7]], "the phone claimed the row it was shown")
	t.ok(_calls[0]["headers"][0].begins_with("Authorization: Bearer "), "…authenticated")
	t.eq(_slept.size(), 0, "no waiting when the credit is already there")
	t.eq(store.buying(), "", "…and the store is free again")
	# A replay grants nothing: the Worker's answer is what gets granted.
	t.eq(await store.sync(), 0, "sync with nothing pending grants nothing")
	t.eq(app.tickets(), before + 300, "…the wallet is unchanged")
	# Cancelled: quiet, nothing asked of the Worker.
	_calls.clear()
	fake.outcome = "cancelled"
	await store.purchase("tickets_1000")
	t.eq(done.back(), ["tickets_1000", false, "cancelled"], "the player's cancel comes back as such")
	t.eq(_calls.size(), 0, "…and nothing was asked of the Worker")
	t.eq(app.tickets(), before + 300, "…nothing granted")
	# An error.
	fake.outcome = "error"
	await store.purchase("tickets_1000")
	t.eq(done.back(), ["tickets_1000", false, "error"], "a store error comes back as error")
	# Slow: the store sold it, the webhook is late — the page gets the word
	# after FAST_TRIES asks, the slow poll keeps asking and credits it.
	fake.outcome = "ok"
	_srv["pending"] = []
	_srv["gets"] = 0
	_srv["row"] = _row(8, "tickets_1000")
	_srv["appear_at"] = store.FAST_TRIES + 3
	_slept.clear()
	await store.purchase("tickets_1000")
	t.eq(done.back(), ["tickets_1000", false, "slow"], "no credit after the fast polls: slow")
	t.eq(_slept.slice(0, store.FAST_TRIES), [].duplicate() if false else _fill(store.FAST_GAP_S, store.FAST_TRIES), "…%d waits of %.1f s" % [store.FAST_TRIES, store.FAST_GAP_S])
	t.eq(credited.back(), 1000, "the slow poll found it and credited 1000")
	t.eq(app.tickets(), before + 1300, "…into the wallet")
	t.eq(_srv["claims"].back(), [8], "…claimed once")
	t.ok(_slept.size() > store.FAST_TRIES and float(_slept[store.FAST_TRIES]) == store.SLOW_GAP_S, "the slow poll waits %.0f s between asks" % store.SLOW_GAP_S)
	# Busy: one sale at a time; the sheet answers later.
	fake.auto = false
	await store.purchase("tickets_300")
	t.eq(store.buying(), "tickets_300", "a purchase is in flight")
	var n_bought := fake.bought.size()
	await store.purchase("tickets_1000")
	t.eq(fake.bought.size(), n_bought, "…a second one waits")
	fake.outcome = "cancelled"
	fake.settle()
	t.eq(store.buying(), "", "…until the sheet closes")
	fake.auto = true
	fake.outcome = "ok"
	# Resume and /v1/me bring a credit that landed while the app was away.
	_srv["pending"] = [_row(9, "tickets_300")]
	net.resumed.emit()
	await Engine.get_main_loop().process_frame
	t.eq(credited.back(), 300, "resume: a waiting purchase is claimed")
	t.eq(app.tickets(), before + 1600, "…and granted")
	_srv["pending"] = [_row(10, "tickets_1000")]
	net.store_pending_tickets.emit(1000)
	await Engine.get_main_loop().process_frame
	t.eq(credited.back(), 1000, "/v1/me's pendingTickets: claimed too")
	net.store_pending_tickets.emit(0)
	await Engine.get_main_loop().process_frame
	t.eq(credited.size(), 4, "…a zero asks nothing")
	# The player id changes (a restore): the SDK follows.
	var acc: Dictionary = save.get_account()
	acc["playerId"] = SaveService.uuid4()
	save.put_account(acc)
	store.ensure()
	t.eq(fake.users, [acc["playerId"]], "a new player id → login")
	# No store (the desktop, a gradle-free phone build): the stub, no sale.
	var nul := StoreBackend.new()
	t.ok(not nul.available(), "the base StoreBackend is the null backend")
	store.use_backend(nul)
	t.ok(not store.live(), "…not live")
	_slept.clear()
	await store.purchase("tickets_300")
	t.eq(done.back(), ["tickets_300", false, "unavailable"], "the stub: no sale")
	t.eq(_slept, [store.STUB_S], "…after the spinner's beat")
	t.eq(app.tickets(), before + 2600, "…nothing granted")
	store.use_backend(fake)
	store.ensure()
	store.fetch_prices()


## A stand-in for the plugin's GodotxRevenueCat singleton (its 2.6.0 shapes).
class FakeRc extends Object:
	signal products(data: Dictionary)
	signal purchase_result(data: Dictionary)
	var calls: Array = []

	func initialize(key: String, user: String, _debug: bool) -> void:
		calls.push_back(["initialize", key, user])

	func login(user: String) -> void:
		calls.push_back(["login", user])

	func fetch_products(ids: PackedStringArray) -> void:
		calls.push_back(["fetch_products", Array(ids)])

	func purchase(id: String) -> void:
		calls.push_back(["purchase", id])


## The plugin seam: RevenueCatBackend against a stand-in singleton. (The
## first TestFlight build ran the stub: available() waited on the key that
## only an available backend is given.)
func _plugin(t, store, save, app, fake: FakeStoreBackend) -> void:
	var pid := str(save.get_account()["playerId"])
	var done: Array = []
	var on_done := func(id: String, ok: bool, reason: String) -> void: done.push_back([id, ok, reason])
	store.purchase_done.connect(on_done)
	var rc := FakeRc.new()
	Engine.register_singleton(RevenueCatBackend.SINGLETON, rc)
	var be := RevenueCatBackend.new()
	t.ok(be.available(), "the singleton present: the backend is available before any key")
	t.ok(be.needs_key(), "…and wants the dashboard key")
	store.use_backend(be)
	StoreKeys.os_for_test = "iOS"
	store.ensure()
	t.eq(rc.calls, [["initialize", "appl_test", pid]], "ensure starts the SDK with the iOS key and the player id")
	t.ok(store.live(), "…live")
	store.fetch_prices()
	t.eq(rc.calls.back(), ["fetch_products", TicketShop.ids()], "prices are asked by product id")
	rc.products.emit({"error": "", "products": [{"id": "tickets_300", "title": "300 Tickets", "price": "€1.19", "amount": 1.19}]})
	t.eq(TicketShop.price("tickets_300"), "€1.19", "…and the store's own string lands")
	var before: int = app.tickets()
	store.purchase("tickets_300")
	t.eq(rc.calls.back(), ["purchase", "tickets_300"], "BUY opens the sheet by product id")
	t.eq(store.buying(), "tickets_300", "…and waits on it")
	rc.purchase_result.emit({"cancelled": true, "error": "Purchase was cancelled.", "product_id": "tickets_300", "transaction_id": "", "active_entitlements": []})
	t.eq(done.back(), ["tickets_300", false, "cancelled"], "a cancelled sheet: cancelled, the SDK's message dropped")
	store.purchase("tickets_300")
	rc.purchase_result.emit({"cancelled": false, "error": "The product is not available.", "product_id": "tickets_300", "transaction_id": "", "active_entitlements": []})
	t.eq(done.back(), ["tickets_300", false, "error"], "a refused sheet: error…")
	t.eq(store.last_error, "The product is not available.", "…with the SDK's message kept")
	t.eq(app.tickets(), before, "…nothing granted either way")
	# The plugin without a key (store_keys.json unfilled, a desktop OS): the stub.
	StoreKeys.os_for_test = "macOS"
	var bare := RevenueCatBackend.new()
	store.use_backend(bare)
	store.ensure()
	t.ok(bare.available() and not store.live(), "the plugin without a key: not live")
	_slept.clear()
	await store.purchase("tickets_300")
	t.eq(done.back(), ["tickets_300", false, "unavailable"], "…the stub, no sheet")
	t.eq(rc.calls.filter(func(c: Array) -> bool: return c[0] == "purchase").size(), 2, "…the SDK never asked")
	StoreKeys.os_for_test = ""
	store.purchase_done.disconnect(on_done)
	store.use_backend(fake)
	store.ensure()
	store.fetch_prices()
	Engine.unregister_singleton(RevenueCatBackend.SINGLETON)
	rc.free()


func _fill(v: float, n: int) -> Array:
	var out := []
	for i in n:
		out.push_back(v)
	return out


func _page(t, store, app, fake: FakeStoreBackend) -> void:
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
		t.eq(amount.text, str(int(TicketShop.packs()[i]["tickets"])), "…its amount")
		t.eq(amount.get_theme_color("font_color"), LeagueContext.HI, "…in butter")
		t.eq(pack.find_child("Art", true, false).get_child_count(), TicketStorePage.FAN[i].size(), "…its fan of tickets")
	t.eq(page.find_children("BestValue", "", true, false).size(), 1, "one BEST VALUE tag…")
	var tag: Control = page.find_child("BestValue", true, false)
	var pack1: Control = page.find_child("Pack1", true, false)
	t.close(tag.position.y, pack1.position.y - 16.0, 0.01, "…16 px over the 1000's top")
	t.close(tag.position.x + tag.size.x - CornerTag.DROP, pack1.size.x - ShadowStyle.OFFSET + 6.0, 0.01, "…6 px past its right edge")
	# The price button, with the store's own price.
	var area0: Control = page.find_child("Pack0", true, false).find_child("BuyArea", true, false)
	t.eq(page.state(0), "idle", "idle at first")
	t.eq((area0.find_child("Price", true, false) as Button).text, "CA$1.39", "…showing the store's price")
	(area0.find_child("Price", true, false) as Button).pressed.emit()
	t.eq(page.state(0), "ask", "a tap asks")
	_free_now(area0)
	t.ok(area0.find_child("Cancel", true, false) != null and area0.find_child("Confirm", true, false) != null, "…X and BUY")
	t.eq((area0.find_child("Confirm", true, false).find_child("Word", true, false) as Label).text, "BUY", "…BUY over…")
	t.eq((area0.find_child("Confirm", true, false).find_child("Price", true, false) as Label).text, "CA$1.39", "…the price")
	(area0.find_child("Cancel", true, false) as Button).pressed.emit()
	t.eq(page.state(0), "idle", "X goes back")
	page.tap(0)
	var before := App.tickets()
	fake.auto = false
	page.confirm(0)
	t.eq(page.state(0), "busy", "BUY waits on the store")
	t.eq(store.buying(), "tickets_300", "…which has the sheet up")
	_free_now(area0)
	t.ok(area0.find_child("Spinner", true, false) is PixelSpinner, "…with the spinner")
	t.eq(area0.find_children("*", "Button", true, false).size(), 0, "…and nothing to press")
	fake.outcome = "cancelled"
	fake.settle()
	t.eq(page.state(0), "idle", "the sheet closed without a sale: back to the price")
	t.eq(App.tickets(), before, "…and nothing granted")
	# A failed sale: PURCHASE FAILED with the SDK's own line under it.
	for c in page.get_children().filter(func(c: Node) -> bool: return c.name.begins_with("StoreToast")):
		c.free()   # earlier credits toasted too
	fake.auto = true
	fake.outcome = "error"
	page.tap(0)
	page.confirm(0)
	t.eq(page.state(0), "idle", "a failed sale goes back to the price")
	var toast: Node = page.find_child("StoreToast", true, false)
	t.ok(toast != null, "…and toasts")
	if toast != null:
		t.eq((toast.find_child("Title", true, false) as Label).text, StoreCopy.failed(), "…PURCHASE FAILED")
		t.ok(toast.mode == Toast.Mode.SIDE and toast.side == Hud.toast_side(), "…a match-style side toast from the HUD side")
		var sub: Label = toast.find_child("Sub", true, false)
		t.eq(sub.text if sub != null else "(no sub)", "STORE_PROBLEM", "…with the store's message")
		toast.free()
	t.eq(StoreCopy.detail("  Error fetching product: \u201cx\u201d\n(code 23) "), "ERROR FETCHING PRODUCT: X (CODE 23)", "the detail line: ASCII, upper, tidy")
	t.eq(StoreCopy.detail("a".repeat(60)).length(), StoreCopy.DETAIL_MAX, "…and capped")
	fake.outcome = "ok"
	# A sale through the page: the credit lands, the success plays from the old balance.
	_srv["pending"] = [_row(20, "tickets_300")]
	page.tap(0)
	page.confirm(0)
	t.eq(page.state(0), "done", "a credited sale shows done")
	t.eq(App.tickets(), before + 300, "…the tickets granted")
	t.eq(page.balance_text(), RetroTheme.thousands(before), "…and the chip counts up from the old balance")
	page._set_state(0, "idle")
	# The success, shown (visual only; QA calls it the same way).
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
	t.eq(App.tickets(), before + 300, "…still nothing more granted (visual only)")
	page._process(TicketStorePage.DONE_S + 0.1)
	t.eq(page.state(1), "idle", "done goes back to the price")
	var closed_ := [false]
	page.closed.connect(func() -> void: closed_[0] = true)
	(page.find_child("Back", true, false) as Button).pressed.emit()
	t.ok(closed_[0], "BACK closes the store")
	page.free()


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
	t.ok(src.contains("Store.tickets_credited.connect(_on_tickets_credited)"), "a credit landing on the home refreshes the wallet")
	var rc := RevenueCatBackend.new()
	t.ok(not rc.available(), "no plugin here: the RevenueCat backend is not available")
	t.eq(RevenueCatBackend.list_of([{"id": "a"}]), [{"id": "a"}], "an Array product list passes through")
	t.eq(RevenueCatBackend.list_of(null), [], "…nothing is an empty list")
