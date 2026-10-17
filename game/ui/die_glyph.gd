class_name DieGlyph
extends Control
## The re-roll die (design 35a's icon_dice): a 40 px cream rounded square
## with an ink outline and five pips, drawn, that spins a full turn on every
## roll (`spin()`, 0.3 s, the design's ease-out).

const SIZE := 40.0
const SPIN_S := 0.3

var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = RetroTheme.SCENE_OUTLINE
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r.grow(0.0))
	var face := StyleBoxFlat.new()
	face.bg_color = RetroTheme.SCENE_TEXT
	face.set_corner_radius_all(6)
	draw_style_box(face, r.grow(-3.0))
	var c := size / 2.0
	for p in [Vector2(-10, -10), Vector2(10, -10), Vector2(0, 0), Vector2(-10, 10), Vector2(10, 10)]:
		draw_circle(c + p, 3.5, RetroTheme.SCENE_OUTLINE)


func spin() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation", rotation + TAU, SPIN_S)
