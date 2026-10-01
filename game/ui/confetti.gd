class_name Confetti
extends Control
## Falling confetti for the match-end page (docs/HOME.md → Results): N
## seeded pieces (DetRng, so a QA snap replays) each with its own width,
## height, colour, fall time and delay, dropping the page's height with two
## turns of spin and looping. Pure _draw; a 3 px ink shadow under each.

const FALL_H := 1380.0
const SHADOW := Vector2(3, 3)

var _pieces: Array = []
var _t := 0.0


func _init(n := 0, palette: Array = [], seed_value := 7) -> void:
	name = "Confetti"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	seed_pieces(n, palette, seed_value)


func seed_pieces(n: int, palette: Array, seed_value := 7) -> void:
	_pieces.clear()
	if palette.is_empty():
		return
	var rng := DetRng.new(seed_value)
	for i in n:
		var s := 8.0 + float(int(rng.next() * 3.0)) * 3.0
		_pieces.push_back({
			"x": rng.next() * 700.0, "w": s, "h": s if rng.next() < 0.5 else roundf(s * 1.8),
			"col": palette[i % palette.size()], "d": 2.6 + rng.next() * 2.2, "dl": 0.35 + rng.next() * 2.6,
		})


func count() -> int:
	return _pieces.size()


func step(dt: float) -> void:
	_t += dt
	queue_redraw()


func _process(delta: float) -> void:
	step(delta)


func _draw() -> void:
	for p in _pieces:
		var local := _t - float(p["dl"])
		if local < 0.0:
			continue
		var f := fmod(local, float(p["d"])) / float(p["d"])
		var y := -80.0 + FALL_H * f
		var a := TAU * 2.0 * f
		var c := Vector2(float(p["x"]), y)
		var half := Vector2(float(p["w"]), float(p["h"])) * 0.5
		var rot := Transform2D(a, c)
		var pts := PackedVector2Array([rot * (-half), rot * Vector2(half.x, -half.y), rot * half, rot * Vector2(-half.x, half.y)])
		var shadow := PackedVector2Array()
		for q in pts:
			shadow.push_back(q + SHADOW)
		draw_colored_polygon(shadow, RetroTheme.SCENE_OUTLINE)
		draw_colored_polygon(pts, p["col"])
