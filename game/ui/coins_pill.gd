class_name CoinsPill
extends PanelContainer
## The TICKET balance (docs/ECONOMY.md): a see-through gold element
## (ShadowStyle) with the pixel coin (icon_coin, 16 px) and the amount with
## thousands separators. Tickets are the locker money; the class keeps its
## old name.

var _amount: Label


func _init() -> void:
	name = "CoinsPill"
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	custom_minimum_size = Vector2(170, 56)
	add_theme_stylebox_override("panel", ShadowStyle.margins(12.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var coin := PixelIcon.new("icon_coin", Vector2(16, 16))
	coin.name = "Coin"
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	_amount = RetroTheme.on_scene(UiFont.label("0", 16, RetroTheme.SCENE_TEXT))
	_amount.name = "Amount"
	_amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_amount)


func _draw() -> void:
	ShadowStyle.draw(self, size, RetroTheme.LIGHT["gold"], false, false, false)


func set_coins(n: int) -> void:
	_amount.text = RetroTheme.thousands(n)


func text() -> String:
	return _amount.text
