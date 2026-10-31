class_name CoinsPill
extends PanelContainer
## The TICKET balance (docs/ECONOMY.md): a see-through gold element
## (ShadowStyle) with the pixel coin (icon_coin, 16 px) and the amount with
## thousands separators. Tickets are the locker money; the class keeps its
## old name. `tappable` makes it a button (the home's wallet → the Ticket
## Store, design 50a): `pressed` on a tap, the face dropping while held.

signal pressed

const TAP_PX := 18.0

## Takes taps (the face drops onto its shadow while held).
var tappable := false:
	set(v):
		tappable = v
		mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW
var _amount: Label
var _at := Vector2.INF
var _held := false


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
	ShadowStyle.draw(self, size, RetroTheme.LIGHT["gold"], _held, false, false)


func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if not tappable or mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_at = mb.position
		_hold(true)
	elif _at != Vector2.INF:
		var tap := mb.position.distance_to(_at) < TAP_PX
		_at = Vector2.INF
		_hold(false)
		if tap:
			pressed.emit()
		accept_event()


## Held: the row moves onto the shadow with the face (through the margins:
## the container re-sorts its child).
func _hold(down: bool) -> void:
	if down == _held:
		return
	_held = down
	var sb := (get_theme_stylebox("panel") as StyleBoxEmpty).duplicate() as StyleBoxEmpty
	var d := ShadowStyle.OFFSET * (1.0 if down else -1.0)
	sb.content_margin_left += d
	sb.content_margin_top += d
	sb.content_margin_right -= d
	sb.content_margin_bottom -= d
	add_theme_stylebox_override("panel", sb)
	queue_redraw()


func set_coins(n: int) -> void:
	_amount.text = RetroTheme.thousands(n)


func text() -> String:
	return _amount.text
