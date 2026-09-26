class_name PropIcons
extends Control
## Minimal on-screen hints for an area's tappable props: a small disc that
## floats above each prop (drawn here, projected from the camera every frame).
## Idle: a music-note "tap me" disc that breathes softly. Playing (the radio):
## a "next" disc and, beside it, a smaller "off" disc. Taps on the discs are
## resolved by the screen through hit_icon(); this control never eats input.

const R_MAIN := 19.0
const R_SMALL := 14.0
const GAP := 48.0
const DISC := Color(0.08, 0.09, 0.13, 0.62)
const RIM := Color(1.0, 0.95, 0.85, 0.55)
const INK := Color(1.0, 0.97, 0.9, 0.95)
const INK_RED := Color(1.0, 0.45, 0.4, 0.95)

var _court: Node
var _cam: Camera3D
var _t := 0.0
var _hits: Array[Dictionary] = []   # {it, id, center, r} from the last draw


func setup(court: Node, cam: Camera3D) -> void:
	_court = court
	_cam = cam
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


## The icon under a screen point, or {} — checked before the prop's own body.
func hit_icon(pos: Vector2) -> Dictionary:
	for h in _hits:
		if pos.distance_to(h["center"]) <= float(h["r"]) + 6.0:
			return h
	return {}


## Lay the discs out for one prop around its projected anchor (also used by
## tests without a camera).
static func layout(anchor: Vector2, icons: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := icons.size()
	var widths: Array[float] = []
	var total := 0.0
	for ic in icons:
		var r := R_SMALL if str(ic.get("id", "")) == "off" else R_MAIN
		widths.push_back(r)
		total += 2.0 * r
	total += GAP * 0.35 * maxf(n - 1, 0)
	var x := anchor.x - total * 0.5
	for i in n:
		var r: float = widths[i]
		out.push_back({"id": str(icons[i].get("id", "")), "center": Vector2(x + r, anchor.y), "r": r})
		x += 2.0 * r + GAP * 0.35
	return out


func _draw() -> void:
	_hits.clear()
	if _court == null or _cam == null or not _cam.is_inside_tree() or not _court.has_method("interactables"):
		return
	for it in _court.interactables():
		var world: Vector3 = it.anchor()
		if _cam.is_position_behind(world):
			continue
		var p := _cam.unproject_position(world)
		var icons: Array = it.icons()
		for h in layout(p, icons):
			h["it"] = it
			_hits.push_back(h)
			_draw_icon(str(h["id"]), h["center"], float(h["r"]))


func _draw_icon(id: String, c: Vector2, r: float) -> void:
	var breathe := 1.0
	if id == "tap":
		breathe = 0.75 + 0.25 * sin(_t * 2.4)
	var disc := DISC
	var rim := RIM
	rim.a *= breathe
	draw_circle(c, r, disc)
	draw_arc(c, r, 0.0, TAU, 40, rim, 1.5, true)
	match id:
		"tap":
			# A music note: stem with a flag and a head.
			var ink := INK
			ink.a *= 0.6 + 0.4 * breathe
			var stem_top := c + Vector2(3.0, -8.0)
			var stem_bot := c + Vector2(3.0, 5.0)
			draw_line(stem_top, stem_bot, ink, 2.0, true)
			draw_line(stem_top, stem_top + Vector2(5.0, 3.0), ink, 2.0, true)
			draw_circle(c + Vector2(0.0, 5.5), 3.4, ink)
		"next":
			# Skip-forward: two triangles and a bar.
			var ink := INK
			for k in 2:
				var ox := -8.0 + 7.0 * k
				draw_colored_polygon(PackedVector2Array([c + Vector2(ox, -6.0), c + Vector2(ox + 7.0, 0.0), c + Vector2(ox, 6.0)]), ink)
			draw_line(c + Vector2(7.5, -6.0), c + Vector2(7.5, 6.0), ink, 2.0, true)
		"off":
			# Power symbol: an open arc with a tick.
			draw_arc(c, 6.0, -PI * 0.5 + 0.55, TAU - PI * 0.5 - 0.55, 24, INK_RED, 2.0, true)
			draw_line(c + Vector2(0.0, -7.5), c + Vector2(0.0, -1.5), INK_RED, 2.0, true)
