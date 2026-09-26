class_name Hud
extends CanvasLayer
## Time Trial HUD: clock, springy score count-up, countdown, and the transient
## center banners (GO!, +1, SWISH +2, streaks, BUZZER BEATER, TIME!).
## All Controls are decorative → mouse_filter IGNORE so flicks pass through.

var _clock: Label
var _score: Label
var _countdown: Label
var _banner: Label
var _score_spring := JuiceSpring.new(0.0, 90.0, 0.75)
var _banner_tween: Tween
## Heat mode: the score line reads YOU · OPP, the clock can carry an OT tag,
## and a small wait readout shows when the next ball can be picked up.
var _heat := false
var _opp_spring := JuiceSpring.new(0.0, 90.0, 0.75)
var _ot := 0
var _wait: Label


func _ready() -> void:
	layer = 5
	_clock = _make_label(28, Color(1, 1, 1))
	_clock.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_clock.position = Vector2(24, 20)

	# Anchor presets + explicit offsets — setting `position` after a preset
	# places the control at absolute parent coords and breaks non-top-left
	# anchors (learned the hard way: labels ended up off-screen).
	_score = _make_label(34, Color(1, 0.95, 0.8))
	_score.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score.offset_left = -300.0
	_score.offset_right = -24.0
	_score.offset_top = 20.0
	_score.offset_bottom = 66.0
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_countdown = _make_label(110, Color(1, 1, 1))
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.offset_left = -120.0
	_countdown.offset_right = 120.0
	_countdown.offset_top = -420.0
	_countdown.offset_bottom = -280.0
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_wait = _make_label(26, Color(0.85, 0.9, 1.0))
	_wait.set_anchors_preset(Control.PRESET_CENTER)
	_wait.offset_left = -160.0
	_wait.offset_right = 160.0
	_wait.offset_top = 150.0
	_wait.offset_bottom = 190.0
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.visible = false

	_banner = _make_label(44, Color(0.98, 0.85, 0.3))
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -340.0
	_banner.offset_right = 340.0
	_banner.offset_top = -260.0
	_banner.offset_bottom = -190.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(dt: float) -> void:
	_score_spring.step(dt)
	if _heat:
		_opp_spring.step(dt)
		_score.text = "YOU %d · OPP %d" % [roundi(_score_spring.value), roundi(_opp_spring.value)]
	else:
		_score.text = "SCORE %d" % roundi(_score_spring.value)


func set_heat(on: bool) -> void:
	_heat = on
	if on:
		_score.offset_left = -420.0


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
	_wait.text = "next ball %.1f" % seconds


var _practice := false


## Endless practice: the clock slot reads PRACTICE and the countdown never shows.
func set_practice(on: bool, label := "PRACTICE") -> void:
	_practice = on
	if on:
		_clock.text = label
		_countdown.visible = false


func update_clock(time_left: float, countdown: float, phase: String) -> void:
	if _practice:
		return
	_clock.text = ("OT%d ⏱ %04.1f" % [_ot, maxf(time_left, 0.0)]) if _ot > 0 else ("⏱ %04.1f" % maxf(time_left, 0.0))
	if phase == TimeTrial.PHASE_COUNTDOWN:
		_countdown.text = str(ceili(countdown))
		_countdown.visible = true
	elif _countdown.visible and phase == TimeTrial.PHASE_RUNNING:
		# GO! flashes via banner; hide the big digits.
		_countdown.visible = false


func set_score(score: int) -> void:
	_score_spring.target = float(score)


func banner(text: String, color := Color(0.98, 0.85, 0.3)) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(0.6, 0.6)
	_banner.pivot_offset = _banner.size / 2.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.22)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(0.7)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.35)
