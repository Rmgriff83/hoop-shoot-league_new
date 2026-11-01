class_name RevenueCatBackend
extends StoreBackend
## RevenueCat on the phone through godot-x/revenuecat (docs/BUILD.md → The
## store plugin): the `GodotxRevenueCat` singleton its Android .aar and iOS
## .xcframework register. Only present in the Play (gradle) and iOS builds
## that tools/build.sh staged the plugin into; `available()` is false
## everywhere else and `Store` runs the null backend.
##
## The plugin's shapes (2.6.0): `purchase_result` always carries `cancelled`,
## `error` ("" on success — but also the SDK's message when cancelled),
## `product_id`, `transaction_id`; `products` is {error, products} where on
## Android `products` is a JavaObject list (size / get), on iOS an Array.

const SINGLETON := "GodotxRevenueCat"

var _rc: Object
var _key := ""


func _init() -> void:
	if Engine.has_singleton(SINGLETON):
		_rc = Engine.get_singleton(SINGLETON)
		_rc.connect("products", _on_products)
		_rc.connect("purchase_result", _on_purchase_result)


func available() -> bool:
	return _rc != null


func needs_key() -> bool:
	return true


func configure(api_key: String, user_id: String) -> void:
	_key = api_key
	if _rc != null and api_key != "":
		_rc.call("initialize", api_key, user_id, OS.is_debug_build())


func set_user(user_id: String) -> void:
	if available() and user_id != "":
		_rc.call("login", user_id)


func fetch_products(ids: Array) -> void:
	if not available() or _key == "":
		products.emit([], "unavailable")
		return
	_rc.call("fetch_products", PackedStringArray(ids))


func purchase(id: String) -> void:
	if not available() or _key == "":
		purchased.emit({"product_id": id, "transaction_id": "", "cancelled": false, "error": "unavailable"})
		return
	_rc.call("purchase", id)


func _on_products(data: Dictionary) -> void:
	var items: Array = []
	for p in list_of(data.get("products")):
		if p is Dictionary and p.has("id"):
			items.push_back({"id": str(p["id"]), "price": str(p.get("price", ""))})
	products.emit(items, str(data.get("error", "")))


func _on_purchase_result(data: Dictionary) -> void:
	var cancelled := bool(data.get("cancelled", false))
	purchased.emit({
		"product_id": str(data.get("product_id", "")),
		"transaction_id": str(data.get("transaction_id", "")),
		"cancelled": cancelled,
		"error": "" if cancelled else str(data.get("error", "")),
	})


## The plugin's product list as an Array: iOS hands one over, Android a
## Java list that only answers size() / get(i).
static func list_of(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Object and v.has_method("call"):
		var out: Array = []
		var n: int = int(v.call("size"))
		for i in n:
			out.push_back(v.call("get", i))
		return out
	return []
