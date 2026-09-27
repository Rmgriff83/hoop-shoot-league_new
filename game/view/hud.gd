class_name Hud
extends CanvasLayer
## The in-game HUD (design "Solo Modes HUD", docs/HOME.md → HUD): the top
## row — the clock card (the stopwatch and the seconds, gold in the last ten)
## or the PRACTICE card, the orange SCORE card with the springy count-up and,
## in a trial, the gold BEST chip under it (NEW BEST once you pass it) — the
## big dithered countdown, and the transient centre banners on two dithered
## lines (SWISH / +2, HEATING / UP, TIME!). Long messages draw as a small
## note. All Controls are decorative → mouse_filter IGNORE so flicks pass
## through; everything sits above the flick input's grab line. Heat mode
## keeps the same row: the score card reads YOU-OPP and the clock an OT tag.
## Copy from HudCopy (pure).

const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")
const CLOCK_POS := Vector2(106, 32)
const CLOCK_SIZE := Vector2(214, 50)
const SCORE_POS := Vector2(520, 32)
const SCORE_SIZE := Vector2(164, 132)
const BEST_POS := Vector2(520, 186)
const BEST_SIZE := Vector2(164, 40)
const COUNTDOWN_Y := 300.0
const BANNER_Y := 450.0
const BANNER_HOLD_S := 0.7

var _clock_card: ShadowPanel
var _clock: Label
var _practice_card: ShadowPanel
var _score: Label
var _score_caps: Label
var _best_chip: ShadowPanel
var _best_label: Label
var _best_val: Label
var _countdown: Label
var _banner: VBoxContainer
var _banner_top: Label
var _banner_bot: Label
var _note: Label
var _wait: Label
var _score_spring := JuiceSpring.new(0.0, 90.0, 0.75)
var _banner_tween: Tween
var _shown: Control
## Heat mode: the score line reads YOU-OPP, the clock can carry an OT tag,
## and a small wait readout shows when the next ball can be picked up.
var _heat := false
var _opp_spring := JuiceSpring.new(0.0, 90.0, 0.75)
var _ot := 0
var _practice := false
var _best := -1


func _ready() -> void:
	layer = 5
	# The clock card (a trial / heat) and the PRACTICE card share the slot.
	_clock_card = _card(CREAM, CLOCK_POS, CLOCK_SIZE, 0.22, 14.0)
	_clock_card.name = "Clock"
	var cr := _hbox(10)
	cr.add_child(_icon("icon_stopwatch"))
	_clock = _text("60.0", 24, CREAM, true)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cr.add_child(_clock)
	_clock_card.add_child(cr)
	_practice_card = _card(RetroTheme.c("teal"), CLOCK_POS, CLOCK_SIZE, 0.22, 14.0)
	_practice_card.name = "Practice"
	_practice_card.visible = false
	var pr := _hbox(12)
	pr.add_child(_icon("icon_jersey"))
	var pl := _text("PRACTICE", 16, CREAM, true)
	pl.name = "PracticeLabel"
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(pl)
	_practice_card.add_child(pr)
	# The score card.
	var sc := _card(RetroTheme.c("orange"), SCORE_POS, SCORE_SIZE, 0.22, 16.0)
	sc.name = "ScoreCard"
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_caps = _text("SCORE")
	_score_caps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_score_caps)
	_score = _text("0", 48, CREAM, true)
	_score.name = "Score"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_score)
	sc.add_child(col)
	# The BEST chip (trials: shown by set_best).
	_best_chip = _card(GOLD, BEST_POS, BEST_SIZE, 0.30, 12.0)
	_best_chip.name = "BestChip"
	_best_chip.visible = false
	var br := _hbox(10)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	_best_label = _text("BEST")
	_best_label.name = "BestLabel"
	_best_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	br.add_child(_best_label)
	_best_val = _text("-", 16, CREAM, true)
	_best_val.name = "BestVal"
	_best_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	br.add_child(_best_val)
	_best_chip.add_child(br)
	# The countdown.
	_countdown = _text("3", 160, CREAM, true)
	_countdown.name = "Countdown"
	_countdown.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_countdown.offset_top = COUNTDOWN_Y
	_countdown.offset_bottom = COUNTDOWN_Y + 180
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetroTheme.dithered(_countdown)
	_countdown.visible = false
	add_child(_countdown)
	# The banner: two dithered lines.
	_banner = VBoxContainer.new()
	_banner.name = "Banner"
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = BANNER_Y
	_banner.offset_bottom = BANNER_Y + 160
	_banner.alignment = BoxContainer.ALIGNMENT_BEGIN
	_banner.add_theme_constant_override("separation", 18)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)
	_banner_top = _text("", 48, GOLD, true)
	_banner_top.name = "BannerTop"
	_banner_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetroTheme.dithered(_banner_top)
	_banner.add_child(_banner_top)
	_banner_bot = _text("", 72, GOLD, true)
	_banner_bot.name = "BannerBot"
	_banner_bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetroTheme.dithered(_banner_bot)
	_banner.add_child(_banner_bot)
	# A note (a long message) in the banner's place, and the heat's ball-wait readout.
	_note = _text("", 16, CREAM, true)
	_note.name = "Note"
	_note.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_note.offset_top = BANNER_Y + 20
	_note.offset_bottom = BANNER_Y + 60
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.visible = false
	add_child(_note)
	_wait = _text("", 16, CREAM, true)
	_wait.name = "Wait"
	_wait.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_wait.offset_top = 790
	_wait.offset_bottom = 830
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.visible = false
	add_child(_wait)


func _process(dt: float) -> void:
	_score_spring.step(dt)
	if _heat:
		_opp_spring.step(dt)
		_score.text = "%d-%d" % [roundi(_score_spring.value), roundi(_opp_spring.value)]
	else:
		_score.text = str(roundi(_score_spring.value))


# ---- modes -----------------------------------------------------------------------


func set_heat(on: bool) -> void:
	_heat = on
	if on:
		_score.add_theme_font_size_override("font_size", UiFont.snap(32))
		_score_caps.text = "YOU-OPP"


func set_opponent_score(score: int) -> void:
	_opp_spring.target = float(score)


func set_ot(n: int) -> void:
	_ot = n


## Seconds until the next ball may be picked up (0 hides the readout).
func set_ball_wait(seconds: float) -> void:
	if seconds <= 0.0:
		_wait.visible = false
		return
	_wait.visible = true
	_wait.text = "NEXT BALL %.1f" % seconds


## Endless practice: the clock slot reads PRACTICE (or the area's label) and the countdown never shows.
func set_practice(on: bool, label := "PRACTICE") -> void:
	_practice = on
	_clock_card.visible = not on
	_practice_card.visible = on
	if on:
		(_practice_card.find_child("PracticeLabel", true, false) as Label).text = label.to_upper() if label != "" else "PRACTICE"
		_countdown.visible = false


## The saved best for this court (trials): shows the chip; -1 hides it.
func set_best(best: int) -> void:
	_best = best
	_best_chip.visible = best >= 0
	_refresh_best()


func _refresh_best() -> void:
	if _best < 0:
		return
	var chip := HudCopy.best_chip(_best, roundi(_score_spring.target))
	_best_label.text = str(chip["label"])
	_best_val.text = str(chip["val"])


# ---- updates ---------------------------------------------------------------------


func update_clock(time_left: float, countdown: float, phase: String) -> void:
	if _practice:
		return
	_clock.text = HudCopy.clock_text(time_left, _ot)
	_clock.add_theme_color_override("font_color", GOLD if HudCopy.clock_hot(time_left) and phase != TimeTrial.PHASE_COUNTDOWN else CREAM)
	if phase == TimeTrial.PHASE_COUNTDOWN:
		_countdown.text = str(ceili(countdown))
		_countdown.visible = true
	elif _countdown.visible and phase == TimeTrial.PHASE_RUNNING:
		# GO! flashes via banner; hide the big digits.
		_countdown.visible = false


func set_score(score: int) -> void:
	_score_spring.target = float(score)
	_refresh_best()


## A centre banner: two dithered lines from HudCopy.split_banner, scaled in
## and held; a message too long for the big lines draws as a note.
func banner(text: String, color := GOLD) -> void:
	if HudCopy.is_note(text):
		note(text, color)
		return
	var parts := HudCopy.split_banner(text)
	_banner_top.text = str(parts[0])
	_banner_bot.text = str(parts[1])
	_banner_bot.visible = str(parts[1]) != ""
	_banner_top.add_theme_color_override("font_color", color)
	_banner_bot.add_theme_color_override("font_color", color)
	_note.visible = false
	_show(_banner)


## A small one-line message where the banner goes (the spot shuffle, 30s mode).
func note(text: String, color := CREAM) -> void:
	_note.text = HudCopy.ascii(text).to_upper()
	_note.add_theme_color_override("font_color", color)
	_banner.visible = false
	_show(_note)


## Scale in, hold, then cut (a fade would dither the face through the shader).
func _show(node: Control) -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_shown = node
	node.visible = true
	node.pivot_offset = Vector2(node.size.x / 2.0, 0.0)
	node.scale = Vector2(0.6, 0.6)
	_banner_tween = create_tween()
	_banner_tween.tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(BANNER_HOLD_S + 0.35)
	# A method, not a lambda: a capture would outlive the node on a scene change.
	_banner_tween.tween_callback(_hide_shown)


func _hide_shown() -> void:
	if is_instance_valid(_shown):
		_shown.visible = false


func banner_text() -> String:
	if _note.visible:
		return _note.text
	return ("%s %s" % [_banner_top.text, _banner_bot.text]).strip_edges() if _banner.visible else ""


func clock_text() -> String:
	return _clock.text


func best_text() -> String:
	return "%s %s" % [_best_label.text, _best_val.text] if _best_chip.visible else ""


# ---- pieces ----------------------------------------------------------------------


func _card(color: Color, pos: Vector2, size_: Vector2, tint: float, pad_h: float) -> ShadowPanel:
	var p := ShadowPanel.new(color, 0.0, tint, pad_h)
	p.position = pos
	p.size = size_ + Vector2.ONE * ShadowStyle.OFFSET
	p.custom_minimum_size = p.size
	add_child(p)
	return p


func _icon(name_: String) -> PixelIcon:
	var i := PixelIcon.new(name_, Vector2(20, 20))
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return i


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l
