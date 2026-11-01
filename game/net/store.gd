extends Node
## `Store` (autoload; docs/ECONOMY.md → Ticket packs, docs/BACKEND.md →
## Ticket store): buying a ticket pack, the bball_sim way. The phone only
## shows the store's prices and opens its sheet (StoreBackend →
## RevenueCat); it never credits itself. RevenueCat's webhook tells the
## Worker, which books a pending purchase; the phone polls for it, CLAIMs
## it (once, atomically) and only then grants the tickets locally — the
## wallet lives in the save, so the credit travels the /v1/rewards/claim
## road. A purchase that finishes after the sheet closes (the app killed,
## a slow webhook) is picked up by `sync()` at launch, on resume and when
## the store page opens.

## The store's price strings arrived (TicketShop.price reads `prices`).
signal prices_changed
## A purchase ended: ok with the tickets granted, or not — `reason` is
## "" | cancelled | error | slow (the store sold it, the credit is still coming) | unavailable.
signal purchase_done(product_id: String, ok: bool, reason: String)
## Bought tickets were granted (a claim landed), `n` of them.
signal tickets_credited(n: int)

## The null backend's stub: the spinner, then no sale (desktop, QA).
const STUB_S := 1.4
const FAST_TRIES := 8
const FAST_GAP_S := 1.5
const SLOW_TRIES := 20
const SLOW_GAP_S := 5.0

var backend: StoreBackend = StoreBackend.new()
var prices: Dictionary = {}
var _user := ""
var _configured := false
var _buying := ""
var _slow_polling := false
var _syncing := false
## The SDK's message from the last failed purchase (the page's toast shows it).
var last_error := ""
## Tests: `_sleep` is a coroutine the suite can stub (no timers off-tree).
var sleep: Callable = Callable()


func _ready() -> void:
	backend = RevenueCatBackend.new()
	backend.products.connect(_on_products)
	backend.purchased.connect(_on_purchased)
	Net.account_ready.connect(func(_n: String, _t: String) -> void: ensure())
	Net.resumed.connect(func() -> void: sync())
	Net.store_pending_tickets.connect(func(n: int) -> void:
		if n > 0:
			sync()
	)
	ensure.call_deferred()


## A fake backend (tests, QA) in place of the plugin.
func use_backend(b: StoreBackend) -> void:
	if backend != null:
		if backend.products.is_connected(_on_products):
			backend.products.disconnect(_on_products)
		if backend.purchased.is_connected(_on_purchased):
			backend.purchased.disconnect(_on_purchased)
	backend = b
	backend.products.connect(_on_products)
	backend.purchased.connect(_on_purchased)
	_configured = false
	_user = ""
	prices.clear()


## The SDK knows this player (the app user id is the player id): started
## once the account exists, and told when the id changes (a restore, a
## transfer claim). A backend that needs the dashboard key and has none
## (store_keys.json unfilled) is never started: the store stays the stub.
func ensure() -> void:
	if not backend.available() or not Net.registered():
		return
	var id := str(Net.account().get("playerId", ""))
	if id == "":
		return
	if not _configured:
		var key := StoreKeys.revenuecat_key()
		if key == "" and backend.needs_key():
			return
		backend.configure(key, id)
		_configured = true
		_user = id
	elif id != _user:
		backend.set_user(id)
		_user = id


## Can a pack be bought here (the plugin, started with its key, an account)?
func live() -> bool:
	return backend.available() and Net.registered() and _configured


func fetch_prices() -> void:
	ensure()
	if live():
		backend.fetch_products(TicketShop.ids())


func _on_products(items: Array, error: String) -> void:
	if error != "":
		return
	for it in items:
		if it is Dictionary and str(it.get("price", "")) != "":
			prices[str(it["id"])] = str(it["price"])
	prices_changed.emit()


func buying() -> String:
	return _buying


## Buy a pack: the store sheet, then the wait for the Worker's credit.
func purchase(id: String) -> void:
	if _buying != "" or TicketShop.pack(id).is_empty():
		return
	_buying = id
	ensure()
	if not live():
		await _sleep(STUB_S)
		_end(id, false, "unavailable")
		return
	backend.purchase(id)


func _on_purchased(r: Dictionary) -> void:
	var id := str(r.get("product_id", ""))
	if _buying == "" or (id != "" and id != _buying):
		return
	id = _buying
	last_error = ""
	if bool(r.get("cancelled", false)):
		_end(id, false, "cancelled")
	elif str(r.get("error", "")) != "":
		last_error = str(r["error"])
		push_warning("store: purchase failed: %s" % last_error)
		_end(id, false, "error")
	else:
		_await_credit(id)


## The store took the money; the credit comes through RevenueCat → the
## Worker → pending. Ask every FAST_GAP_S, FAST_TRIES times; then give the
## page back and keep asking slowly in the background (Apple's sandbox
## webhooks can take 30 s and more).
func _await_credit(id: String) -> void:
	for i in FAST_TRIES:
		var n := await _claim_pending()
		if n > 0:
			_end(id, true, "")
			return
		await _sleep(FAST_GAP_S)
	_end(id, false, "slow")
	_slow_poll()


func _slow_poll() -> void:
	if _slow_polling:
		return
	_slow_polling = true
	for i in SLOW_TRIES:
		await _sleep(SLOW_GAP_S)
		if await _claim_pending() > 0:
			break
	_slow_polling = false


## Anything waiting at the Worker → claimed → granted. Returns the tickets granted.
func sync() -> int:
	return await _claim_pending()


func _claim_pending() -> int:
	if _syncing or not Net.registered():
		return 0
	_syncing = true
	var pending := await Net.store_pending()
	var ids: Array = []
	for row in pending:
		ids.push_back(int(Dictionary(row).get("id", 0)))
	var n := 0
	if not ids.is_empty():
		var claimed := await Net.store_claim(ids)
		for row in claimed:
			n += int(Dictionary(row).get("tickets", 0))
		if n > 0:
			App.grant_tickets(n)   # only what the Worker turned in THIS call: a replay grants nothing
	_syncing = false
	if n > 0:
		tickets_credited.emit(n)
	return n


func _end(id: String, ok: bool, reason: String) -> void:
	_buying = ""
	purchase_done.emit(id, ok, reason)


func _sleep(s: float) -> void:
	if sleep.is_valid():
		await sleep.call(s)
	elif is_inside_tree():
		await get_tree().create_timer(s).timeout
