class_name CosmeticSet
extends Resource
## A purchasable, swappable bundle (a hoop or a ball): everything it needs —
## model, sounds, feel, skin — lives in its own assets/<kind>/<id>/ folder and
## is referenced by PATH so nothing loads until the set is selected.

@export var id := ""
@export var display_name := ""
## 0 = starter (owned by every save).
@export var price_coins := 0
## glTF binary honouring the kind's node-name contract.
@export var model_path := ""


## Paths this set references (subclasses extend). Used by validate().
func referenced_paths() -> PackedStringArray:
	return PackedStringArray([model_path])


## Missing files, empty when the set is complete.
func validate() -> PackedStringArray:
	var missing := PackedStringArray()
	for p in referenced_paths():
		if p != "" and not FileAccess.file_exists(p):
			missing.push_back(p)
	if id == "":
		missing.push_back("<id>")
	return missing
