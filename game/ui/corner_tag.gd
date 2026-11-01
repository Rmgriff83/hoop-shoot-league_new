class_name CornerTag
extends Control
## A butter tag hung off a panel's corner: BEST VALUE on the Ticket Store
## (design 50a) and the match line on the league's opponent card (Home
## League Context v2, 2026-11-01). Ink display words at 16 on butter, a
## 2 px ink edge, a 4 px ink drop. `lift` moves the drawn tag off the
## control's own origin, for a tag a container lays out (a MarginContainer
## puts it at its content's top-left; the lift makes it overhang).

const PAD := 14.0
const DROP := 4.0
const BUTTER := Color("#FFE45C")

var lift := Vector2.ZERO
var face_h := 44.0


func _init(text: String, h := 44.0, p_lift := Vector2.ZERO) -> void:
	face_h = h
	lift = p_lift
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiFont.label(text, 16, RetroTheme.SCENE_OUTLINE, UiFont.display())
	l.name = "Word"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := UiFont.display().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(16)).x
	l.position = lift + Vector2(PAD, 0)
	l.size = Vector2(w, h)
	add_child(l)
	custom_minimum_size = Vector2(w + 2.0 * PAD + DROP, h + DROP)
	size = custom_minimum_size


func _draw() -> void:
	var face := Rect2(lift, custom_minimum_size - Vector2.ONE * DROP)
	draw_rect(Rect2(face.position + Vector2.ONE * DROP, face.size), RetroTheme.SCENE_OUTLINE)
	draw_rect(face, BUTTER)
	draw_rect(Rect2(face.position + Vector2.ONE, face.size - Vector2.ONE * 2.0), RetroTheme.SCENE_OUTLINE, false, 2.0)
