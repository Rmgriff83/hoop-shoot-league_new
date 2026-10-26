class_name PixelSwitch
extends Control
## The settings page's on/off switch (design "Settings v2" 42a, 2026-10-25):
## a 96×48 well with a 2 px edge, a 36 px knob with a 3 px ink shadow and
## ON / OFF on the free side. Off: a cream edge and knob over a dark well;
## on: gold, the knob at the right. Decorative: the row that holds it takes
## the tap.

const SIZE := Vector2(96, 48)
const KNOB := 36.0
const GOLD := Color("#F0B84A")
const WELL_OFF := Color(34.0 / 255.0, 28.0 / 255.0, 24.0 / 255.0, 0.6)

var on := false


func _init(p_on := false) -> void:
	on = p_on
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_on(p_on: bool) -> void:
	on = p_on
	queue_redraw()


func _draw() -> void:
	var edge := GOLD if on else RetroTheme.SCENE_TEXT
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(GOLD, 0.3) if on else WELL_OFF)
	draw_rect(Rect2(Vector2(1, 1), SIZE - Vector2(2, 2)), edge, false, 2.0)
	var x := 52.0 if on else 4.0
	var at := Vector2(x, 4.0)
	draw_rect(Rect2(at + Vector2(3, 3), Vector2.ONE * KNOB), RetroTheme.SCENE_OUTLINE)
	draw_rect(Rect2(at, Vector2.ONE * KNOB), edge)
	var font := UiFont.display()
	var fs := UiFont.snap(11)
	var word := "ON" if on else "OFF"
	var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := 10.0 if on else SIZE.x - 10.0 - w
	var ty := SIZE.y * 0.5 + font.get_ascent(fs) * 0.5 - 1.0
	draw_string_outline(font, Vector2(tx, ty), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RetroTheme.OUTLINE, RetroTheme.SCENE_OUTLINE)
	draw_string(font, Vector2(tx, ty), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RetroTheme.SCENE_TEXT)
