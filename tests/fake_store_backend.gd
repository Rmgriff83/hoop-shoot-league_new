class_name FakeStoreBackend
extends StoreBackend
## A scriptable platform store for tests and QA: the prices it answers, what
## a purchase comes back as ("ok" | "cancelled" | "error"), and a record of
## every call. `purchase` answers on the next call to `settle()` (or at once
## when `auto` is true), so a test can look at the busy state first.

var available_ := true
var auto := true
var prices := {"tickets_300": "CA$1.39", "tickets_1000": "CA$3.99"}
var outcome := "ok"
var configured: Array = []   # [api_key, user_id] per configure
var users: Array = []        # set_user calls
var fetched: Array = []
var bought: Array = []
var _pending := ""
var _tx := 0


func available() -> bool:
	return available_


func configure(api_key: String, user_id: String) -> void:
	configured.push_back([api_key, user_id])


func set_user(user_id: String) -> void:
	users.push_back(user_id)


func fetch_products(ids: Array) -> void:
	fetched.push_back(ids.duplicate())
	var items: Array = []
	for id in ids:
		if prices.has(id):
			items.push_back({"id": str(id), "price": str(prices[id])})
	products.emit(items, "")


func purchase(id: String) -> void:
	bought.push_back(id)
	_pending = id
	if auto:
		settle()


## The store sheet closes with `outcome`.
func settle() -> void:
	if _pending == "":
		return
	var id := _pending
	_pending = ""
	_tx += 1
	match outcome:
		"cancelled":
			purchased.emit({"product_id": id, "transaction_id": "", "cancelled": true, "error": ""})
		"error":
			purchased.emit({"product_id": id, "transaction_id": "", "cancelled": false, "error": "STORE_PROBLEM"})
		_:
			purchased.emit({"product_id": id, "transaction_id": "fake-%d" % _tx, "cancelled": false, "error": ""})
