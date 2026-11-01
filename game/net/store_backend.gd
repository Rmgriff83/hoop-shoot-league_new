class_name StoreBackend
extends RefCounted
## The platform store behind `Store` (docs/ECONOMY.md → Ticket packs): the
## App Store and Play through RevenueCat (RevenueCatBackend) once its plugin
## is in the build. This base class IS the null backend — never available —
## and is what desktop, headless, QA and the gradle-free phone builds run.
## A real backend answers `products` with the store's own price strings and
## `purchased` once the store sheet closes; it never credits anything (the
## Worker does, from RevenueCat's webhook).

## The store's prices: `items` = [{id, price}], `error` "" when it answered.
signal products(items: Array, error: String)
## A purchase ended: {product_id, transaction_id, cancelled, error} —
## `error` "" and `cancelled` false is a sale the store took.
signal purchased(result: Dictionary)


## The plugin is present on this device (before any key: `Store.ensure`
## hands the key over only to an available backend).
func available() -> bool:
	return false


## Does `configure` need the dashboard's SDK key (store_keys.json)? The
## plugin does; the fakes and the null backend do not.
func needs_key() -> bool:
	return false


## Start the SDK for this player (RevenueCat's app user id = the player id).
func configure(_api_key: String, _user_id: String) -> void:
	pass


## The player id changed (a restore, a transfer claim): the SDK follows.
func set_user(_user_id: String) -> void:
	pass


## Ask the store for these products; answered with `products`.
func fetch_products(_ids: Array) -> void:
	pass


## Open the store sheet for a product; answered with `purchased`.
func purchase(_id: String) -> void:
	pass
