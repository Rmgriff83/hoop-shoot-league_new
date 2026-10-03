class_name RimPop
extends Node3D
## A scoring pop that rises off the hoop (design "Solo Modes HUD" 5a,
## docs/HOME.md → HUD): `+2` under a small word (SWISH, HEATING UP, BUZZER
## BEATER, ON FIRE, IN AND OUT), billboarded 3D text at the rim's centre
## that pops in just above it, drifts up about 110 design px with a slight
## sway and fades within about a second — the mock's rimFloat/rimSway
## keyframes. It is world geometry with depth, so the ball and the rim draw
## over it. Each pop is its own node and frees itself when done.

const LIFE := 1.1
## One design px at the hoop from the key (~5.9 m at fov 60): 5.3 mm.
const PX := 0.0053
const RISE_PX := 110.0
const SWAY_PX := 10.0
const NUMBER_SIZE := 32
const WORD_SIZE := 16
const OUTLINE := 6
const INK := Color("#221C18")
const CREAM := Color("#F1E8D0")
const GOLD := Color("#F0B84A")
const ORANGE := Color("#E8703A")
const SHADOW := Color("#221C18", 0.55)

var _t := 0.0
var _scale_mul := 1.0
## A pop spawned in the same breath as another waits this long so the two
## read in sequence instead of on top of each other (`CourtGeometry.rim_pop`).
var delay := 0.0
var _labels: Array[Label3D] = []
var _rig: Node3D


func setup(number: String, word: String, color: Color, scale_mul := 1.0) -> void:
	_scale_mul = scale_mul
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	var px := PX * scale_mul
	# The word sits above the number; the shadow copies draw first, offset
	# (+4, -4) px, in the ink at half strength.
	var y_number := 0.0
	var y_word := (NUMBER_SIZE * 0.5 + 8.0 + WORD_SIZE * 0.5) * px
	for spec in [[number, NUMBER_SIZE, UiFont.display(), y_number], [word, WORD_SIZE, UiFont.body_bold(), y_word]]:
		if str(spec[0]) == "":
			continue
		var shadow := _label(str(spec[0]), int(spec[1]), spec[2], SHADOW, px, false)
		shadow.name = "Shadow"
		shadow.position = Vector3(4.0 * px, float(spec[3]) - 4.0 * px, -0.002)
		_rig.add_child(shadow)
		var l := _label(str(spec[0]), int(spec[1]), spec[2], color, px, true)
		l.name = "Number" if spec[1] == NUMBER_SIZE else "Word"
		l.position = Vector3(0, float(spec[3]), 0)
		_rig.add_child(l)
		_labels.push_back(l)
		_labels.push_back(shadow)
	step(0.0)


func _label(text: String, size_: int, font: Font, color: Color, px: float, outline: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size_
	l.pixel_size = px
	l.modulate = color
	l.outline_size = OUTLINE if outline else 0
	l.outline_modulate = INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD   # writes depth: pops occlude each other, the ball occludes them
	l.no_depth_test = false
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## The mock's keyframes: rimFloat (opacity/scale/rise) + rimSway (x).
static func keyframes(p: float) -> Dictionary:
	var alpha := 0.0
	var scale := 0.5
	var rise := 0.0
	if p < 0.12:
		var k := p / 0.12
		alpha = k
		scale = lerpf(0.5, 1.12, k)
		rise = lerpf(0.0, 14.0, k)
	elif p < 0.22:
		var k := (p - 0.12) / 0.10
		alpha = 1.0
		scale = lerpf(1.12, 1.0, k)
		rise = lerpf(14.0, 22.0, k)
	elif p < 0.70:
		var k := (p - 0.22) / 0.48
		alpha = 1.0
		scale = 1.0
		rise = lerpf(22.0, 22.0 + (110.0 - 22.0) * (0.48 / 0.78), k)
	else:
		var k := (p - 0.70) / 0.30
		alpha = 1.0 - k
		scale = lerpf(1.0, 0.94, k)
		rise = lerpf(22.0 + (110.0 - 22.0) * (0.48 / 0.78), 110.0, k)
	return {"alpha": alpha, "scale": scale, "rise": rise, "sway": SWAY_PX * sin(p * PI)}


func progress() -> float:
	return clampf((_t - delay) / LIFE, 0.0, 1.0)


## Seconds since the pop started (negative while it waits its turn).
func age() -> float:
	return _t - delay


func alpha() -> float:
	return float(keyframes(progress())["alpha"])


## The rig's offset from the rim, metres (x the sway, y the rise).
func offset() -> Vector3:
	return _rig.position if _rig != null else Vector3.ZERO


func step(dt: float) -> void:
	_t += dt
	var p := progress()
	var k := keyframes(p)
	var px := PX * _scale_mul
	if _rig != null:
		_rig.position = Vector3(float(k["sway"]) * px, float(k["rise"]) * px, 0.0)
		_rig.scale = Vector3.ONE * float(k["scale"])
	for l in _labels:
		var c := l.modulate
		c.a = float(k["alpha"]) * (SHADOW.a if l.name == "Shadow" else 1.0)
		l.modulate = c
		l.visible = c.a > 0.01
	if _t >= delay + LIFE and is_inside_tree():
		queue_free()


func _process(delta: float) -> void:
	step(delta)
