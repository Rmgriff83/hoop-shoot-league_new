class_name CoinsPill
extends PanelContainer
## The coin balance: a see-through gold element (ShadowStyle) with a small
## orange square (drawn — no coin glyph in the pixel faces) and the amount
## with thousands separators. Will link to the shop once that lives in the
## league view.

var _amount: Label


class Square extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(20, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2(16, 16)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2(5, 5), Vector2(10, 10)), RetroTheme.LIGHT["orange"])


func _init() -> void:
	name = "CoinsPill"
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	custom_minimum_size = Vector2(150, 56)
	add_theme_stylebox_override("panel", ShadowStyle.margins(12.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var sq := Square.new()
	sq.name = "Square"
	row.add_child(sq)
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
