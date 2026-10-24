class_name ShotTutorial
extends CanvasLayer
## The first-shot tutorial (design "Shot Tutorial" 38a, 2026-10-24; docs/HOME.md
## → Shot tutorial): a five-step card at the top of the screen before the
## player's very first offline match — practice, time trial or league heat,
## never online. The hosting screen (time_trial_screen.gd) hides every other
## HUD layer, holds the real rules and lends the tutorial its court: steps 2
## and 3 play a looping demo with a drawn pixel finger on the REAL ball — it
## presses, pulls down (the preview dots and the arc number appear), flicks
## up and lets go (the ball swishes at ideal power) — step 4 cycles the
## readout's three verdict colours, and step 5 is live: the player's own
## flick, a make unlocking LET'S PLAY, a miss saying short, long or off the
## rim. Plays once (settings.shotTutorialSeen; SKIP sets it too), then the
## match's countdown runs as usual. Copy and the demo clock: ShotTutorialCopy.

signal closed(completed: bool)

const CREAM := RetroTheme.SCENE_TEXT
const CARD_X := 36.0
const CARD_Y := 24.0
const CARD_W := 720.0 - 36.0 - 42.0
const CARD_PAD := Vector2(24.0, 22.0)   # x, y
const CARD_GAP := 16.0
const CARD_IN_S := 0.3
const CARD_IN_PX := 16.0
const BUTTON_H := 60.0
const BACK_W := 60.0
const SKIP_W := 130.0
const LEGEND_H := 40.0
## The pixel hand: FINGER_PX cells, each FINGER_SCALE design px; the tip at TIP.
const FINGER_SCALE := 3.0
const FINGER_TIP := Vector2(27.0, 3.0)
const FINGER_SHADOW := Vector2(5.0, 6.0)
const FINGER_PRESS_SCALE := 0.9
## The pointing hand, 26 × 36 cells: `c` cream, `o` ink outline, `.` clear.
const FINGER_PX := [
	".........ooo..............",
	"........occco.............",
	"........occco.............",
	"........occco.............",
	"........occco.............",
	"........occco.............",
	"........occco.............",
	"........occco.............",
	"........occcoooo..........",
	"........occccccoooo.......",
	"........occccccccccoooo...",
	"....oooooccccccccccccccoo.",
	"...occcccccccccccccccccco.",
	"..occcccccccccccccccccccco",
	"..occcccccccccccccccccccco",
	"..occcccccccccccccccccccco",
	"..occcccccccccccccccccccco",
	"..occcccccccccccccccccccco",
	"..occcccccccccccccccccccco",
	"..occcccccccccccccccccccco",
	"...occccccccccccccccccccco",
	"...occcccccccccccccccccco.",
	"....occccccccccccccccccco.",
	"....occccccccccccccccccco.",
	".....occccccccccccccccco..",
	".....occccccccccccccccco..",
	"......occccccccccccccco...",
	"......occccccccccccccco...",
	".......occccccccccccco....",
	".......occccccccccccco....",
	"........occccccccccco.....",
	"........occccccccccco.....",
	".........occccccccco......",
	".........occccccccco......",
	"..........ooooooooo.......",
	"..........................",
]

var steps: Array = ShotTutorialCopy.STEPS
var _screen: Object
var _index := 0
var _t := 0.0
var _root: Control
var _card: ShadowPanel
var _card_tween: Tween
var _finger: Finger
var _hint: Label
## The demo's state on the real ball: pressed, and whether this loop's shot went.
var _demo_holding := false
var _demo_released := false
var _last_loop := 0.0
## The live step.
var _made := false
var _result := ""
var _live_grabbed := false


func _init() -> void:
	name = "ShotTutorial"
	layer = 50
	visible = false


## Does the tutorial play now? Never once seen, never online, never under a QA
## pass that did not ask for it.
static func due(seen: bool, online: bool, qa_skip: bool) -> bool:
	return not seen and not online and not qa_skip


## The screen lends its court through: ball_rest_point(), demo_press(),
## demo_drag(pos), demo_windup(pull_px), demo_shoot(angle_deg), demo_drop(),
## demo_readout(arc, pct), demo_readout_clear(), tutorial_grabbed(),
## tutorial_ball_flying().
func start(screen: Object) -> void:
	_screen = screen
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_finger = Finger.new()
	_finger.name = "Finger"
	_finger.visible = false
	_root.add_child(_finger)
	visible = true
	_show_step(0)


func step_index() -> int:
	return _index


func live() -> bool:
	return ShotTutorialCopy.is_live(_index)


func made() -> bool:
	return _made


func result() -> String:
	return _result


# ---- steps ---------------------------------------------------------------------


func _show_step(i: int) -> void:
	_stop_demo()
	_index = clampi(i, 0, steps.size() - 1)
	_t = 0.0
	_last_loop = 0.0
	_demo_released = false
	_result = ""
	_live_grabbed = false
	# Steps 1–4 own every touch (nothing under the card gets one); the live
	# step lets the court have the screen and keeps the card for itself.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE if live() else Control.MOUSE_FILTER_STOP
	if _screen != null and _screen.has_method("demo_readout_clear"):
		_screen.call("demo_readout_clear")
	_build_card()


func next() -> void:
	if live():
		if _made:
			_finish(true)
		return
	_show_step(_index + 1)


func back() -> void:
	if _index > 0:
		_show_step(_index - 1)


func skip() -> void:
	_finish(false)


func _finish(completed: bool) -> void:
	_stop_demo()
	App.mark_shot_tutorial_seen()
	closed.emit(completed)
	queue_free()


## A finished live shot: the verdict rewrites the card; a make unlocks LET'S PLAY.
func on_outcome(outcome: Dictionary, power_pct: float) -> void:
	if not live():
		return
	_result = ShotTutorialCopy.verdict(str(outcome.get("type", "")), power_pct)
	if ShotTutorialCopy.is_make(_result):
		_made = true
	_build_card()


# ---- the demo ------------------------------------------------------------------


func _process(dt: float) -> void:
	if _screen == null:
		return
	_t += dt
	if live():
		_process_live()
		return
	if _index == 3:
		var s: Array = ShotTutorialCopy.read_sample(_t)
		_screen.call("demo_readout", float(s[0]), float(s[1]))
		_finger.visible = false
		return
	var d := ShotTutorialCopy.demo(_index, _t)
	if float(d["loop"]) < _last_loop:
		_demo_released = false   # a new loop: the flick demo may shoot again
	_last_loop = float(d["loop"])
	var rest: Vector2 = _screen.call("ball_rest_point")
	_apply_finger(d, rest)
	var holding := bool(d["holding"])
	if holding and not _demo_holding:
		_demo_holding = bool(_screen.call("demo_press"))
	if holding and _demo_holding and d["finger"] != null:
		_screen.call("demo_drag", rest + (d["finger"] as Vector2))
		_screen.call("demo_windup", float(d["pull"]))
	elif not holding and _demo_holding:
		if bool(d["release"]) and not _demo_released:
			_screen.call("demo_shoot", ShotTutorialCopy.FLICK_ARC)
			_demo_released = true
		else:
			_screen.call("demo_drop")
		_demo_holding = false


func _process_live() -> void:
	if not _live_grabbed and bool(_screen.call("tutorial_grabbed")):
		_live_grabbed = true
	if _live_grabbed or _made:
		_finger.visible = false
	else:
		# The ghost of the aim demo on the finger alone: the ball is the player's now.
		var d := ShotTutorialCopy.demo(4, _t)
		_apply_finger(d, _screen.call("ball_rest_point"))
	if _hint != null:
		_hint.text = ShotTutorialCopy.HINT_FLYING if bool(_screen.call("tutorial_ball_flying")) else ShotTutorialCopy.HINT_WAITING


func _apply_finger(d: Dictionary, rest: Vector2) -> void:
	if d["finger"] == null:
		_finger.visible = false
		return
	_finger.visible = true
	_finger.tip = rest + (d["finger"] as Vector2)
	_finger.pressed = bool(d["press"])
	_finger.modulate.a = float(d["alpha"])
	_finger.ripple = d["ripple"] if d["ripple"] != null else {}
	_finger.rest = rest
	_finger.queue_redraw()


func _stop_demo() -> void:
	if _screen != null and _screen.has_method("demo_reset"):
		_screen.call("demo_reset")   # the ball in hand or in the air goes with the step
	elif _demo_holding and _screen != null:
		_screen.call("demo_drop")
	_demo_holding = false
	if _finger != null:
		_finger.visible = false


# ---- the card ------------------------------------------------------------------


func _build_card() -> void:
	if _card != null:
		if _card.get_parent() != null:
			_card.get_parent().remove_child(_card)
		_card.queue_free()
	_hint = null
	var st := ShotTutorialCopy.step(_index)
	var title := str(st["title"])
	var body := str(st["body"])
	var title_color := ShotTutorialCopy.GOLD
	if live() and _result != "":
		var r := ShotTutorialCopy.result(_result)
		title = str(r["title"])
		body = str(r["body"])
		title_color = r["color"]
	_card = ShadowPanel.new(CREAM, CARD_PAD.y, ShadowStyle.TINT, CARD_PAD.x)
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.position = Vector2(CARD_X, CARD_Y)
	_card.size = Vector2(CARD_W + ShadowStyle.OFFSET, 0)
	_root.add_child(_card)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", int(CARD_GAP))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)
	var row := HBoxContainer.new()
	row.name = "TitleRow"
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var tl := _words(title, 22, true)
	tl.name = "Title"
	tl.add_theme_color_override("font_color", title_color)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tl)
	var count := _words("%d / %d" % [_index + 1, steps.size()], 16)
	count.name = "Count"
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count)
	var bl := _words(body, 19)
	bl.name = "Body"
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size = Vector2(CARD_W - 2.0 * CARD_PAD.x - ShadowStyle.OFFSET, 0)
	col.add_child(bl)
	if bool(st.get("legend", false)):
		col.add_child(_legend())
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 18)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(buttons)
	var last := live()
	if _index > 0:
		var back_b := HomePage.button("<", CREAM, 22, BUTTON_H - ShadowStyle.OFFSET)
		back_b.name = "TourBack"
		back_b.custom_minimum_size = Vector2(BACK_W + ShadowStyle.OFFSET, BUTTON_H + ShadowStyle.OFFSET)
		back_b.pressed.connect(back)
		buttons.add_child(back_b)
	if not (last and _made):
		var skip_b := HomePage.button("SKIP", CREAM, 16, BUTTON_H - ShadowStyle.OFFSET)
		skip_b.name = "TourSkip"
		skip_b.custom_minimum_size = Vector2(SKIP_W + ShadowStyle.OFFSET, BUTTON_H + ShadowStyle.OFFSET)
		skip_b.pressed.connect(skip)
		buttons.add_child(skip_b)
	if not last or _made:
		var next_b := HomePage.button("", RetroTheme.c("orange"), 18, BUTTON_H - ShadowStyle.OFFSET)
		next_b.name = "TourNext"
		next_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		next_b.pressed.connect(next)
		var nrow := HBoxContainer.new()
		nrow.name = "Row"
		nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		nrow.offset_left = 22.0
		nrow.offset_right = -(22.0 + ShadowStyle.OFFSET)
		nrow.offset_bottom = -ShadowStyle.OFFSET
		next_b.add_child(nrow)
		var nl := _words(ShotTutorialCopy.CTA_PLAY if last else ShotTutorialCopy.CTA_NEXT, 18, true)
		nl.name = "Cta"
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nrow.add_child(nl)
		var arrow := _words(">", 22, true)
		arrow.name = "Arrow"
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nrow.add_child(arrow)
		buttons.add_child(next_b)
	else:
		# Waiting for the shot: a dashed box that says so (… while one is in the air).
		var wait := ModeCards.Dashed.new(Vector2(0, BUTTON_H), 2.0, 0.0)
		wait.name = "Waiting"
		wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hint = _words(ShotTutorialCopy.HINT_WAITING, 16)
		_hint.name = "Hint"
		_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wait.add_child(_hint)
		buttons.add_child(wait)
	# Slide in from 16 px above with a fade (design cardIn).
	_card.modulate.a = 0.0
	_card.position.y = CARD_Y - CARD_IN_PX
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	if is_inside_tree():
		_card_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_card_tween.tween_property(_card, "position:y", CARD_Y, CARD_IN_S)
		_card_tween.tween_property(_card, "modulate:a", 1.0, CARD_IN_S)
	else:
		_card.position.y = CARD_Y
		_card.modulate.a = 1.0


## IN / CLOSE / MISS: three boxes in the readout's verdict colours.
func _legend() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Legend"
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for item in ShotTutorialCopy.LEGEND:
		var box := PanelContainer.new()
		box.name = "Legend" + str(item[0]).capitalize()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1B1815", 0.6)
		sb.border_color = item[1]
		sb.set_border_width_all(2)
		sb.set_content_margin_all(0)
		box.add_theme_stylebox_override("panel", sb)
		box.custom_minimum_size = Vector2(0, LEGEND_H)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inner := HBoxContainer.new()
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_theme_constant_override("separation", 10)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(inner)
		var sw := Swatch.new(item[1])
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(sw)
		var l := _words(str(item[0]), 15)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inner.add_child(l)
		row.add_child(box)
	return row


## A 12 px colour square with the hard ink shadow.
class Swatch extends Control:
	var color := Color.WHITE
	func _init(p_color: Color) -> void:
		color = p_color
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2(12, 12)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, Vector2(12, 12)), color)


static func _words(text: String, size_: int, display := false) -> Label:
	var l := HomePage.words(text, size_, display)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The drawn pixel finger (design icon_finger at 78 × 108, the tip at (27, 3))
## and, on the first step, the fading ripple ring around the ball.
class Finger extends Control:
	var tip := Vector2.ZERO
	var rest := Vector2.ZERO
	var pressed := false
	var ripple: Dictionary = {}

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if not ripple.is_empty():
			var s := float(ripple.get("s", 60.0))
			draw_arc(rest, s / 2.0, 0.0, TAU, 48, Color(ShotTutorialCopy.GOLD, float(ripple.get("op", 1.0))), 3.0)
		var k := FINGER_SCALE * (FINGER_PRESS_SCALE if pressed else 1.0)
		var origin := tip - FINGER_TIP * (k / FINGER_SCALE)
		for y in FINGER_PX.size():
			var row: String = FINGER_PX[y]
			for x in row.length():
				var ch := row[x]
				if ch == ".":
					continue
				var r := Rect2(origin + Vector2(x, y) * k, Vector2.ONE * k)
				draw_rect(Rect2(r.position + FINGER_SHADOW, r.size), Color(0, 0, 0, 0.45))
		for y in FINGER_PX.size():
			var row: String = FINGER_PX[y]
			for x in row.length():
				var ch := row[x]
				if ch == ".":
					continue
				var r := Rect2(origin + Vector2(x, y) * k, Vector2.ONE * k)
				draw_rect(r, RetroTheme.SCENE_OUTLINE if ch == "o" else CREAM)
