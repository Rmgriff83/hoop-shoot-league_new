class_name NeonSign
extends Control
## The splash's neon sign (design "Splash Screen" 29a + "Neon Sign.html",
## rebuilt in 2D pixel style): HOOP / SHOOT / LEAGUE as single-stroke tube
## letters — the design's stroke table, drawn as crisp pixel polylines in
## three passes (a wide halo, the orange glass, the cream core) — with the
## pull chain hanging under the last E. The only motion is the design's:
## the chain tug (0.35–1.2 s), then the tubes buzz on with four uneven blinks,
## swell to full over 2.6 s and breathe. No board, no background: it hangs on
## the frosted glass behind it. `step(dt)` / `level_at` / `chain_at` are
## pure, so the timeline is tested headless.

const W := 0.6         # letter width in units of the cap height
const ADV := 0.92      # advance per letter
const ROWH := 1.42     # row pitch
const ROWS := ["HOOP", "SHOOT", "LEAGUE"]
## One continuous stroke per entry: points in [0, W] × [0, 1], y up.
const STROKES := {
	"H": [[[0, 0], [0, 1]], [[0, 0.5], [W, 0.5]], [[W, 1], [W, 0]]],
	"O": [[[W / 2, 0], [0, 0], [0, 1], [W, 1], [W, 0], [W / 2, 0]]],
	"P": [[[0, 0], [0, 1], [W, 1], [W, 0.46], [0, 0.46]]],
	"S": [[[W, 0.8], [W, 1], [0, 1], [0, 0.5], [W, 0.5], [W, 0], [0, 0], [0, 0.2]]],
	"T": [[[0, 1], [W, 1]], [[W / 2, 1], [W / 2, 0]]],
	"L": [[[0, 1], [0, 0], [W, 0]]],
	"E": [[[W, 1], [0, 1], [0, 0], [W, 0]], [[0, 0.5], [W * 0.8, 0.5]]],
	"A": [[[0, 0], [W / 2, 1], [W, 0]], [[W * 0.21, 0.42], [W * 0.79, 0.42]]],
	"G": [[[W, 0.78], [W, 1], [0, 1], [0, 0], [W, 0], [W, 0.46], [W * 0.5, 0.46]]],
	"U": [[[0, 1], [0, 0], [W, 0], [W, 1]]],
}
## Pixels per unit (the cap height) and the tube widths, px.
const CAP := 96.0
const TUBE := 8.0
const CORE := 4.0
const HALO := 18.0
const HALO_WIDE := 32.0
const PAD := 20.0
## The design's colours: lit core / glass / halo, and the dark glass when off.
const ON_CORE := Color("#FFF1E2")
const ON_GLASS := Color("#FF7A3D")
const HALO_COLOR := Color("#FF6A2A")
const OFF_CORE := Color("#15110F")
const OFF_GLASS := Color("#1E1714")
const HALO_ALPHA := 0.32
const HALO_WIDE_ALPHA := 0.12
## The pull chain: beads under the last E, the tug's travel in px.
const CHAIN_BEADS := 16
const BEAD := 4.0
const BEAD_GAP := 5.0
const CHAIN_PX := 40.0
const STEEL := Color("#C9C4BA")
const STEEL_DARK := Color("#8E8880")
## When the buttons may rise (the sign is near full).
const DONE_S := 4.6

signal tapped

var _t := 0.0


func _init() -> void:
	custom_minimum_size = sign_size()
	size = sign_size()
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		tapped.emit()


## The drawn area: the widest word plus the halo's padding, three rows, and
## the chain hanging below.
static func sign_size() -> Vector2:
	var cols := 0
	for w in ROWS:
		cols = maxi(cols, w.length())
	var w := (cols * ADV - (ADV - W)) * CAP
	var h := ((ROWS.size() - 1) * ROWH + 1.0) * CAP
	return Vector2(w + 2.0 * PAD, h + 2.0 * PAD + CHAIN_BEADS * BEAD_GAP + 30.0 + CHAIN_PX)


# ---- the timeline (Neon Sign.html frame()/level()) --------------------------------


static func _ease(x: float) -> float:
	return 2.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0


## How lit the tubes are at t: dark until 1.3 s, four uneven blinks, a slow
## swell to full by 3.9 s, then a gentle breath.
static func level_at(t: float) -> float:
	if t < 1.3:
		return 0.0
	var u := t - 1.3
	if u < 0.12:
		return 0.3
	if u < 0.3:
		return 0.04
	if u < 0.42:
		return 0.4
	if u < 0.6:
		return 0.18
	if u < 3.2:
		return 0.18 + 0.82 * _ease((u - 0.6) / 2.6)
	return 1.0 - 0.07 * (0.5 - 0.5 * cos((u - 3.2) * 1.3))


## The chain's downward travel at t (px): tugged 0.35–0.75 s, eased back by 1.2 s.
static func chain_at(t: float) -> float:
	var c := 0.0
	if t >= 0.35 and t < 0.75:
		c = (t - 0.35) / 0.4
	elif t >= 0.75 and t < 1.2:
		c = 1.0 - _ease((t - 0.75) / 0.45)
	return CHAIN_PX * sin(minf(1.0, c) * PI / 2.0)


static func tube_color(level: float) -> Color:
	return OFF_GLASS.lerp(ON_GLASS, level)


static func core_color(level: float) -> Color:
	return OFF_CORE.lerp(ON_CORE, level)


func level() -> float:
	return level_at(_t)


func chain_offset() -> float:
	return chain_at(_t)


func time() -> float:
	return _t


func done() -> bool:
	return _t >= DONE_S


func replay() -> void:
	_t = 0.0
	queue_redraw()


func step(dt: float) -> void:
	_t += dt
	queue_redraw()


func _process(dt: float) -> void:
	step(dt)


# ---- drawing ----------------------------------------------------------------------


## Every stroke as pixel-snapped polylines, plus the chain's anchor (the end
## of the last E's bar).
func _polylines() -> Array:
	var out := []
	for ri in ROWS.size():
		var word: String = ROWS[ri]
		var y0 := PAD + ri * ROWH * CAP
		for ci in word.length():
			var lx := PAD + ci * ADV * CAP
			for stroke in STROKES[word[ci]]:
				var pts := PackedVector2Array()
				for p in stroke:
					pts.push_back(Vector2(round(lx + float(p[0]) * CAP), round(y0 + (1.0 - float(p[1])) * CAP)))
				out.push_back(pts)
	return out


func chain_anchor() -> Vector2:
	var lines := _polylines()
	var last: PackedVector2Array = lines[lines.size() - 1]
	return last[last.size() - 1]


func _draw() -> void:
	var k := level()
	var lines := _polylines()
	# Halo passes only once there is light.
	if k > 0.0:
		for pts in lines:
			draw_polyline(pts, Color(HALO_COLOR, HALO_WIDE_ALPHA * k), HALO_WIDE, false)
		for pts in lines:
			draw_polyline(pts, Color(HALO_COLOR, HALO_ALPHA * k), HALO, false)
	var glass := tube_color(k)
	var core := core_color(k)
	for pts in lines:
		draw_polyline(pts, glass, TUBE, false)
	for pts in lines:
		draw_polyline(pts, core, CORE, false)
	# The pull chain under the last E, tugged by the timeline.
	var a := chain_anchor() + Vector2(0.0, TUBE / 2.0 + 6.0 + chain_offset())
	for i in CHAIN_BEADS:
		var at := Vector2(a.x - BEAD / 2.0, a.y + i * BEAD_GAP)
		draw_rect(Rect2(at + Vector2(1, 1), Vector2(BEAD, BEAD)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(at, Vector2(BEAD, BEAD)), STEEL)
	var pull := Vector2(a.x - 5.0, a.y + CHAIN_BEADS * BEAD_GAP + 2.0)
	draw_rect(Rect2(pull + Vector2(2, 2), Vector2(10, 18)), RetroTheme.SCENE_OUTLINE)
	draw_rect(Rect2(pull, Vector2(10, 18)), STEEL)
	draw_rect(Rect2(pull + Vector2(0, 12), Vector2(10, 6)), STEEL_DARK)
