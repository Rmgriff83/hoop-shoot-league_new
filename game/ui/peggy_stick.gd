class_name PeggyStick
extends Control
## The locker's joystick (docs/LOCKER.md): a horizontal stick that drives
## the carriage along PEGGY's rail. Drag the knob left or right and the aim
## moves at a rate proportional to the deflection; let go and the knob
## springs back to centre and the carriage stays put. Pure _draw.

signal moved(deflection: float)

const TRACK := Vector2(260, 72)
const KNOB := 30.0
const SPRING := 14.0

var _deflection := 0.0
var _held := false


func _init() -> void:
	name = "Stick"
	custom_minimum_size = TRACK + Vector2(ShadowStyle.OFFSET, ShadowStyle.OFFSET)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func deflection() -> float:
	return _deflection


func held() -> bool:
	return _held


func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
			return
		_held = ev.pressed
		if _held:
			_set_from_px(ev.position.x)
	elif ev is InputEventScreenTouch:
		_held = ev.pressed
		if _held:
			_set_from_px(ev.position.x)
	elif (ev is InputEventMouseMotion or ev is InputEventScreenDrag) and _held:
		_set_from_px(ev.position.x)


func _set_from_px(px: float) -> void:
	var half := (TRACK.x - KNOB * 2.0 - 12.0) * 0.5
	_deflection = clampf((px - TRACK.x * 0.5) / half, -1.0, 1.0)
	moved.emit(_deflection)
	queue_redraw()


func _process(delta: float) -> void:
	if _held or _deflection == 0.0:
		return
	_deflection = lerpf(_deflection, 0.0, minf(1.0, SPRING * delta))
	if absf(_deflection) < 0.01:
		_deflection = 0.0
	moved.emit(_deflection)
	queue_redraw()


func _draw() -> void:
	var ink := RetroTheme.c("ink")
	var cream := RetroTheme.c("bg")
	var gold := RetroTheme.LIGHT["gold"]
	# The track: an ink slot with a cream rim and its drop shadow.
	draw_rect(Rect2(Vector2(ShadowStyle.OFFSET, ShadowStyle.OFFSET), TRACK), RetroTheme.c("shadow"))
	draw_rect(Rect2(Vector2.ZERO, TRACK), cream)
	draw_rect(Rect2(Vector2(10, TRACK.y * 0.5 - 8), Vector2(TRACK.x - 20, 16)), ink)
	for i in 5:
		var x := 24.0 + i * (TRACK.x - 48.0) / 4.0
		draw_rect(Rect2(Vector2(x - 2, TRACK.y * 0.5 - 14), Vector2(4, 28)), ink)
	# The knob.
	var half := (TRACK.x - KNOB * 2.0 - 12.0) * 0.5
	var kx := TRACK.x * 0.5 + _deflection * half
	var ky := TRACK.y * 0.5
	draw_circle(Vector2(kx + 3, ky + 3), KNOB, ink)
	draw_circle(Vector2(kx, ky), KNOB, gold if _held else cream)
	draw_circle(Vector2(kx, ky), KNOB - 5.0, ink)
	draw_circle(Vector2(kx, ky), KNOB - 9.0, gold if _held else cream)
