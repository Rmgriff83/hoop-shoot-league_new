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
## Something owned changed hands: `key` (remove_ads) is now owned, or not (a refund).
signal entitlement_changed(key: String, owned: bool)
## RESTORE PURCHASES ended (always deferred): ok, whether anything is owned
## now, and why not — "" | error | unavailable.
signal restore_done(ok: bool, found: bool, reason: String)

## The null backend's stub: the spinner, then no sale (desktop, QA).
const STUB_S := 1.4
const FAST_TRIES := 8
const FAST_GAP_S := 1.5
const SLOW_TRIES := 20
const SLOW_GAP_S := 5.0
## The SDK's own answer after a sheet / a restore is awaited this long.
const ANSWER_WAIT_S := 8.0
const REMOVE_ADS := "remove_ads"

var backend: StoreBackend = StoreBackend.new()
var prices: Dictionary = {}
var _user := ""
var _configured := false
var _buying := ""
var _slow_polling := false
var _syncing := false
## What the player owns: the union of the store SDK's last answer and the
## Worker's (/v1/me), cached in the synced settings part so an owner never
## sees ads offline (Ross, 2026-11-01: a hand-edited cache is accepted).
var _rc_keys: Array = []
var _srv_keys: Array = []
var _owned: Dictionary = {}
var _buying_key := ""
var _restoring := false
## The SDK's message from the last failed purchase (the page's toast shows it).
var last_error := ""
## Tests: `_sleep` is a coroutine the suite can stub (no timers off-tree).
var sleep: Callable = Callable()


func _ready() -> void:
	backend = RevenueCatBackend.new()
	_connect_backend()
	_load_owned()
	Net.account_ready.connect(func(_n: String, _t: String) -> void: ensure())
	Net.resumed.connect(func() -> void: sync())
	Net.store_pending_tickets.connect(func(n: int) -> void:
		if n > 0:
			sync()
	)
	Net.store_entitlements.connect(_on_server_entitlements)
	ensure.call_deferred()


func _connect_backend() -> void:
	backend.products.connect(_on_products)
	backend.purchased.connect(_on_purchased)
	backend.entitlements.connect(_on_entitlements)
	backend.restored.connect(_on_restored)


func _disconnect_backend() -> void:
	for pair in [[backend.products, _on_products], [backend.purchased, _on_purchased], [backend.entitlements, _on_entitlements], [backend.restored, _on_restored]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


## A fake backend (tests, QA) in place of the plugin.
func use_backend(b: StoreBackend) -> void:
	if backend != null:
		_disconnect_backend()
	backend = b
	_connect_backend()
	_configured = false
	_user = ""
	_buying_key = ""
	_restoring = false
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
		backend.fetch_entitlements()   # what this player owns, the SDK's word
	elif id != _user:
		backend.set_user(id)
		_user = id
		backend.fetch_entitlements()


## Can a pack be bought here (the plugin, started with its key, an account)?
func live() -> bool:
	return backend.available() and Net.registered() and _configured


func fetch_prices() -> void:
	ensure()
	if live():
		backend.fetch_products(TicketShop.product_ids())


func _on_products(items: Array, error: String) -> void:
	if error != "":
		return
	for it in items:
		if it is Dictionary and str(it.get("price", "")) != "":
			prices[str(it["id"])] = str(it["price"])
	prices_changed.emit()


func buying() -> String:
	return _buying


## Buy a pack (the store sheet, then the wait for the Worker's credit) or
## an entitlement (the sheet, then the SDK's own word that it is owned).
func purchase(id: String) -> void:
	if _buying != "" or (TicketShop.pack(id).is_empty() and not TicketShop.is_entitlement(id)):
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
	elif TicketShop.is_entitlement(id):
		_await_entitlement(id)
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
## Also asks the SDK again what is owned (a purchase or refund made elsewhere).
func sync() -> int:
	if live():
		backend.fetch_entitlements()
	return await _claim_pending()


# ---- entitlements (remove_ads): owned, not credited ----------------------------------


## Does the player own `key` (remove_ads)? The cache: the SDK's and the Worker's last words, united.
func owns(key: String) -> bool:
	return _owned.has(key)


func owned_keys() -> Array:
	var out := _owned.keys()
	out.sort()
	return out


## The sheet took the money: the SDK's customer info says whether the key is
## active now (instant, before the webhook). No answer in ANSWER_WAIT_S, or
## an answer without the key → "slow": the Worker's books land it on the
## next /v1/me, and `sync()` asks the SDK again.
func _await_entitlement(id: String) -> void:
	_buying_key = str(TicketShop.entitlement(id).get("key", id))
	backend.fetch_entitlements()
	await _sleep(ANSWER_WAIT_S)
	if _buying == id and _buying_key != "":
		_buying_key = ""
		_end(id, false, "slow")


func _on_entitlements(ids: Array, error: String) -> void:
	if error == "":
		_rc_keys = ids.duplicate()
		_merge_owned()
	if _buying_key != "" and _buying != "":
		var id := _buying
		var key := _buying_key
		_buying_key = ""
		if error == "" and ids.has(key):
			_end(id, true, "")
		else:
			if error != "":
				last_error = error
			_end(id, false, "slow")
	if _restoring:
		_restoring = false
		if error == "":
			restore_done.emit.call_deferred(true, not ids.is_empty(), "")
		else:
			last_error = error
			restore_done.emit.call_deferred(false, false, "error")


func _on_server_entitlements(keys: Array) -> void:
	_srv_keys = keys.duplicate()
	_merge_owned()


## The union of the two sources, with a word for every key that came or went,
## written to the synced settings when it changed.
func _merge_owned() -> void:
	var next := {}
	for k in _rc_keys + _srv_keys:
		next[str(k)] = true
	var changed: Array = []
	for k in next.keys():
		if not _owned.has(k):
			changed.push_back([k, true])
	for k in _owned.keys():
		if not next.has(k):
			changed.push_back([k, false])
	if changed.is_empty():
		return
	_owned = next
	var s := SaveService.get_settings()
	s["entitlements"] = owned_keys()
	SaveService.put_settings(s)
	for c in changed:
		entitlement_changed.emit(c[0], c[1])


func _load_owned() -> void:
	_owned.clear()
	for k in Array(SaveService.get_settings().get("entitlements", [])):
		_owned[str(k)] = true
	_srv_keys = _owned.keys()   # the cache stands in for the Worker's word until it speaks


## RESTORE PURCHASES (from a tap only: the OS may ask for a sign-in). False
## when it cannot start (no live store, or one in flight); otherwise
## `restore_done` follows, always deferred.
func restore() -> bool:
	ensure()
	if _restoring or not live():
		return false
	_restoring = true
	backend.restore_purchases()
	_restore_guard()
	return true


func _restore_guard() -> void:
	await _sleep(ANSWER_WAIT_S)
	if _restoring:
		_restoring = false
		restore_done.emit.call_deferred(false, false, "error")


func _on_restored(r: Dictionary) -> void:
	if not _restoring:
		return
	if not bool(r.get("success", false)):
		_restoring = false
		last_error = str(r.get("error", ""))
		restore_done.emit.call_deferred(false, false, "unavailable" if last_error == "unavailable" else "error")
		return
	backend.fetch_entitlements()   # the keys: answered on `entitlements`, which ends the restore


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
