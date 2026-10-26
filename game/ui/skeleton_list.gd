class_name SkeletonList
extends Control
## A list that is still loading (design "Loading States" 39b → LISTS): a
## head row with the spinner (alone since 2026-10-25: no LOADING words), then four
## skeleton rows under dashed rules — a short bar for the rank, a name bar
## of the design's width, a score bar on the right — pulsing 0.35 ↔ 0.6
## over 1.2 s, each row a beat behind the one above. Drawn in `ink` (cream
## on a scene, the theme's text on a page); the list swaps it out when the
## rows arrive.

const HEAD_H := 50.0
const ROW_H := 54.0
const BAR_H := 16.0
const RANK_W := 40.0
const SCORE_W := 70.0
const GAP := 20.0
const PULSE_S := 1.2
## The four rows: [name bar width, delay s] (the design's).
const ROWS := [[220.0, 0.0], [180.0, 0.15], [250.0, 0.3], [200.0, 0.45]]

var ink := RetroTheme.SCENE_TEXT
var _word := ""
var _t := 0.0


func _init(word: String, ink_ := RetroTheme.SCENE_TEXT, _on_scene := false) -> void:
	name = "Skeleton"
	ink = ink_
	_word = word
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEAD_H + ROW_H * ROWS.size())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin := PixelSpinner.new(28.0)
	spin.name = "Spinner"
	spin.color = ink
	spin.position = Vector2(0, (HEAD_H - 28.0) * 0.5)
	add_child(spin)   # the spinner alone: no LOADING words (2026-10-25)


## A row's bar opacity at second `t`: 0.35 at rest, 0.6 at the pulse's top.
static func pulse(t: float, delay: float) -> float:
	var k := fposmod(t - delay, PULSE_S) / PULSE_S
	return 0.35 + 0.25 * (0.5 - 0.5 * cos(TAU * k))


## What the head says: nothing (the spinner stands for it since 2026-10-25).
func text() -> String:
	return ""


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _draw() -> void:
	for i in ROWS.size():
		var y := HEAD_H + ROW_H * i
		# The dashed rule on the row's top.
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, y, minf(8.0, size.x - x), 2.0), Color(ink, 0.3))
			x += 14.0
		var c := Color(ink, pulse(_t, float(ROWS[i][1])))
		var by := y + (ROW_H - BAR_H) * 0.5
		draw_rect(Rect2(0, by, RANK_W, BAR_H), c)
		draw_rect(Rect2(RANK_W + GAP, by, minf(float(ROWS[i][0]), size.x - RANK_W - SCORE_W - GAP * 3.0), BAR_H), c)
		draw_rect(Rect2(size.x - SCORE_W, by, SCORE_W, BAR_H), c)
