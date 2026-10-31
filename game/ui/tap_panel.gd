class_name TapPanel
extends ShadowPanel
## A ShadowPanel that takes a tap (the lobby's leaderboard, the pages' ticket
## panel → the Ticket Store): `pressed` on a release within TAP_PX of the
## press, unless `dragged` was set meanwhile (a scroll inside took the drag).
## `shift` drops the children onto the shadow while held, like ShadowCard.

signal pressed

const TAP_PX := 18.0

var dragged := false
var shift := false
var _at := Vector2.INF
var _shifted := false


func _init(p_color := Color.WHITE, pad := 20.0, p_tint := ShadowStyle.TINT, pad_h := -1.0) -> void:
	super(p_color, pad, p_tint, pad_h)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_at = mb.position
		dragged = false
		_shift(true)
	elif _at != Vector2.INF:
		var tap := not dragged and mb.position.distance_to(_at) < TAP_PX
		_at = Vector2.INF
		_shift(false)
		if tap:
			pressed.emit()
		accept_event()


func _shift(down: bool) -> void:
	if not shift or down == _shifted:
		return
	_shifted = down
	var sb := get_theme_stylebox("panel") as StyleBoxEmpty
	if sb != null:
		# The container re-sorts its children on every change: move them through the margins.
		var d := ShadowStyle.OFFSET * (1.0 if down else -1.0)
		sb = sb.duplicate()
		sb.content_margin_left += d
		sb.content_margin_top += d
		sb.content_margin_right -= d
		sb.content_margin_bottom -= d
		add_theme_stylebox_override("panel", sb)
	queue_redraw()


func is_held() -> bool:
	return _shifted


func _draw() -> void:
	if not _shifted:
		super()
		return
	# Held: the face sits on its shadow (ShadowStyle's pressed look).
	ShadowStyle.draw_ex(self, size, color, Color(color, ShadowStyle.face_alpha(tint)), Color(color, ShadowStyle.DOT_ALPHA), shadow if shadow.a > 0.0 else Color(color, ShadowStyle.SHADOW_ALPHA), true, false, false)
