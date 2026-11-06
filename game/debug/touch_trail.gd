class_name TouchTrail
extends CanvasLayer
## The swipe, drawn (docs/TRAILER.md → Touch trail): a short white streak
## with the dithered shadow that follows the finger through a flick, so the
## trailer's App Store cut can show HOW the ball was thrown without a hand
## on screen (Apple allows touch marks as overlays; no hands or devices).
## Debug only: nothing in the game creates one — the trailer director does.
## It listens to a FlickInput, so it draws exactly what the estimator saw.

const KEEP_S := 0.14          # how much of the swipe stays lit
const FADE_S := 0.16          # the fade once the finger lifts
const HEAD_W := 20.0
const TAIL_W := 6.0
const PX := 4.0               # points snap to the UI's 4 px grid: a pixel streak, not a smooth one
const SHADOW_OFF := Vector2(6, 6)

var _points: Array = []       # [[t, pos], …] in design (band) px
var _t := 0.0
var _down := false
var _lift_t := -1.0
var _face: Control
var _shade: Control


func _init() -> void:
	name = "TouchTrail"
	layer = 8   # over the court and the shot help, under the HUD's toasts
	_shade = Control.new()
	_shade.name = "Shade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.material = RetroTheme.dither_material()
	_shade.draw.connect(_draw_streak.bind(_shade, SHADOW_OFF, RetroTheme.SCENE_SHADOW))
	add_child(_shade)
	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(_draw_streak.bind(_face, Vector2.ZERO, RetroTheme.SCENE_TEXT))
	add_child(_face)


func follow(input: FlickInput) -> void:
	input.grab_pressed.connect(_on_press)
	input.drag_moved.connect(_on_drag)
	input.flick_released.connect(func(_s: Dictionary) -> void: _on_lift())


func _on_press() -> void:
	_points.clear()
	_down = true
	_lift_t = -1.0


func _on_drag(pos: Vector2) -> void:
	if _down:
		_points.push_back([_t, (pos / PX).round() * PX])


func _on_lift() -> void:
	_down = false
	_lift_t = _t


func _process(dt: float) -> void:
	_t += dt
	while _points.size() > 1 and _t - float(_points[0][0]) > KEEP_S + (FADE_S if not _down else 0.0):
		_points.pop_front()
	if not _down and _lift_t >= 0.0 and _t - _lift_t > FADE_S:
		_points.clear()
	_shade.queue_redraw()
	_face.queue_redraw()


## How lit the streak is: full while the finger is down, fading after the lift.
func alpha() -> float:
	if _down or _lift_t < 0.0:
		return 1.0
	return clampf(1.0 - (_t - _lift_t) / FADE_S, 0.0, 1.0)


func point_count() -> int:
	return _points.size()


func _draw_streak(c: Control, off: Vector2, colour: Color) -> void:
	var n := _points.size()
	if n < 2:
		return
	var a := alpha()
	for i in range(1, n):
		var k := float(i) / float(n - 1)   # 0 at the tail, 1 at the finger
		var age := clampf((_t - float(_points[i][0])) / KEEP_S, 0.0, 1.0)
		var col := Color(colour, colour.a * a * (1.0 - age * 0.6))
		c.draw_line(Vector2(_points[i - 1][1]) + off, Vector2(_points[i][1]) + off, col, roundf(lerpf(TAIL_W, HEAD_W, k) / 2.0) * 2.0, false)
	# The finger's end: a square cap, as the UI's pixels are.
	var head: Vector2 = Vector2(_points[n - 1][1]) + off
	c.draw_rect(Rect2(head - Vector2.ONE * HEAD_W * 0.5, Vector2.ONE * HEAD_W), Color(colour, colour.a * a))
