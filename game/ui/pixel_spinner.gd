class_name PixelSpinner
extends Control
## The loading states' spinner (design "Loading States" 39a / 39b): eight
## cream squares on a ring, fading in toward the gold lead, turning in 45°
## steps (0.8 s a turn). Drawn, so it scales to any slot (28–48 px).

const TURN_S := 0.8
const GOLD := Color("#F0B84A")
## The ring at 48 px: [x, y] of each square, from the faintest to the lead.
const RING := [[20, 0], [34, 6], [40, 20], [34, 34], [20, 40], [6, 34], [0, 20], [6, 6]]

var _t := 0.0


func _init(px := 48.0) -> void:
	custom_minimum_size = Vector2(px, px)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


## Which ring position square `j` sits on at second `t` (one step per eighth of a turn).
static func slot_at(j: int, t: float) -> int:
	return (j + int(floor(fposmod(t, TURN_S) / TURN_S * 8.0))) % 8


func _draw() -> void:
	var k := size.x / 48.0
	var sq := maxf(2.0, roundf(8.0 * k))
	for j in 8:
		var p: Array = RING[slot_at(j, _t)]
		var at := Vector2(float(p[0]), float(p[1])) * k
		var a := 0.25 + 0.75 * float(j) / 7.0
		draw_rect(Rect2(at + Vector2(2, 2), Vector2(sq, sq)), Color(RetroTheme.SCENE_OUTLINE, a))
		draw_rect(Rect2(at, Vector2(sq, sq)), Color(GOLD if j == 7 else RetroTheme.SCENE_TEXT, a if j < 7 else 1.0))
