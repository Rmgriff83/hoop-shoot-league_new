class_name Hud
extends CanvasLayer
## The in-game HUD (design "Solo Modes HUD", docs/HOME.md → HUD): the top
## row — the clock card (the stopwatch and the seconds, gold in the last ten)
## or the PRACTICE card, the orange SCORE card with the springy count-up and,
## in a trial, the gold BEST chip under it (NEW BEST once you pass it) — the
## countdown in the big toast chip (STARTS IN over the digit, then GO), and
## every mid-play call (TIME!, 30S MODE, the spot shuffle's NEXT SPOT / NEW
## SPOT) as the small toast chip sliding in from the screen's edge a third
## of the way up (designs 4a / 5a, 2026-10-24; App.hud_side picks the edge;
## nothing big in the middle of the screen while shooting; the scoring
## calls are rim pops off the hoop). All Controls are decorative →
## mouse_filter IGNORE so flicks pass
## through; everything sits above the flick input's grab line. Heat mode
## (design "League Match HUD") swaps the score card for two 162×50 cards —
## YOU in orange, the opponent's first name in their shooter colour — puts
## a gold OT tag in the clock card in overtime, and shows the ball-return
## wait as the mini toast (the ball and `0.8S`, 2026-10-25). Every toast
## leaves by fading where it is (design 4a's latest pass). Copy from HudCopy (pure).
## An ANCHORED layer since Ross's 2026-10-26 pass: every position here is a
## band design position mapped through UiLayout.hud_pos — the top row under
## the notch, the toasts and the rest spread to the real screen.

const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")
const CLOCK_POS := Vector2(106, 32)
const CLOCK_SIZE := Vector2(214, 50)
const SCORE_POS := Vector2(520, 32)
const SCORE_SIZE := Vector2(164, 132)
const BEST_POS := Vector2(520, 186)
const BEST_SIZE := Vector2(164, 40)
const YOU_POS := Vector2(340, 32)
const OPP_POS := Vector2(522, 32)
const SIDE_SIZE := Vector2(162, 50)
## The toasts (designs 4a / 5a, 2026-10-24): the countdown chip and the
## notice chip both hang off the screen's edge (App.hud_side) with their
## centre a third of the way up — clear of the opponent window and the hoop.
const TOAST_Y := 853.0
const GO_TOAST_S := 0.9

var _clock_card: ShadowPanel
var _toast_big: Toast
var _toast_small: Toast
var _clock: Label
var _ot_tag: Label
var _score_card: ShadowPanel
var _you_score: Label
var _opp_score: Label
var _practice_card: ShadowPanel
var _score: Label
var _score_caps: Label
var _best_chip: ShadowPanel
var _best_label: Label
var _best_val: Label
## The NEXT BALL toast is up (it yields the slot to any other notice and
## comes back when the screen asks again).
var _wait_shown := false
var _score_spring := JuiceSpring.new(0.0, 90.0, 0.75)
## Heat mode: the score line reads YOU-OPP, the clock can carry an OT tag,
## and a small wait readout shows when the next ball can be picked up.
var _heat := false
var _opp_spring := JuiceSpring.new(0.0, 90.0, 0.75)
var _ot := 0
var _practice := false
var _best := -1
var _top_wash: TextureRect


func _init() -> void:
	UiLayout.anchor_layer(self)


## A bright sky (ArenaSet.top_wash): an ink gradient behind the top cards.
func set_top_wash(alpha: float) -> void:
	if _top_wash != null:
		_top_wash.queue_free()
		_top_wash = null
	if alpha <= 0.0:
		return
	_top_wash = ShadowStyle.top_wash(alpha)
	# An anchored layer: the wash starts at the screen's very top edge and
	# keeps its depth below where the band's top would be (Ross, 2026-10-25:
	# the park's gradient began just under the safe area).
	var lift := UiLayout.offset().y
	_top_wash.position = Vector2.ZERO
	_top_wash.size = Vector2(UiLayout.canvas().x, ShadowStyle.TOP_WASH_H + lift)
	add_child(_top_wash)
	move_child(_top_wash, 0)


func has_top_wash() -> bool:
	return _top_wash != null


func _ready() -> void:
	layer = 5
	# The clock card (a trial / heat) and the PRACTICE card share the slot.
	_clock_card = _card(CREAM, CLOCK_POS, CLOCK_SIZE, 0.22, 14.0)
	_clock_card.name = "Clock"
	var cr := _hbox(10)
	cr.add_child(_icon("icon_stopwatch"))
	_ot_tag = _text("OT1", 16, GOLD, true)
	_ot_tag.name = "OtTag"
	_ot_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ot_tag.visible = false
	cr.add_child(_ot_tag)
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
	_score_card = sc
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
	# The toasts (designs 4a / 5a): the countdown / GO chip and the notice
	# chip, from the side the setting says (read once: settings change at home).
	_toast_big = Toast.new(CREAM, UiLayout.hud_y(TOAST_Y), Toast.Mode.SIDE, toast_side())
	_toast_big.name = "CountdownToast"
	add_child(_toast_big)
	_toast_small = Toast.new(GOLD, UiLayout.hud_y(TOAST_Y), Toast.Mode.SIDE, toast_side())
	_toast_small.name = "Toast"
	add_child(_toast_small)


## Which edge the toasts hang off: App.hud_side (left unless the setting says right).
static func toast_side() -> String:
	return "right" if str(App.hud_side) == "right" else "left"


func _process(dt: float) -> void:
	_score_spring.step(dt)
	if _heat:
		_opp_spring.step(dt)
		_you_score.text = str(roundi(_score_spring.value))
		_opp_score.text = str(roundi(_opp_spring.value))
	else:
		_score.text = str(roundi(_score_spring.value))


# ---- modes -----------------------------------------------------------------------


## A heat: two score cards on the row — YOU (orange) and the opponent's first
## name in their shooter colour — in place of the SCORE card.
func set_heat(on: bool, opp_label := "OPP", opp_color := LeagueContext.PINE) -> void:
	_heat = on
	if not on:
		return
	_score_card.visible = false
	_best_chip.visible = false
	var you := _card(RetroTheme.c("orange"), YOU_POS, SIDE_SIZE, 0.22, 14.0)
	you.name = "YouCard"
	_you_score = _side(you, "YOU")
	var opp := _card(opp_color, OPP_POS, SIDE_SIZE, 0.32, 14.0)
	opp.name = "OppCard"
	_opp_score = _side(opp, opp_label.to_upper())


func _side(card: ShadowPanel, label: String) -> Label:
	var row := _hbox(8)
	var l := _text(label)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	row.add_child(l)
	var v := _text("0", 24, CREAM, true)
	v.name = "Value"
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(v)
	card.add_child(row)
	return v


func set_opponent_score(score: int) -> void:
	_opp_spring.target = float(score)


## The overtime period (0 = regulation): a gold OT tag in the clock card.
func set_ot(n: int) -> void:
	_ot = n
	_ot_tag.visible = n > 0
	_ot_tag.text = "OT%d" % n


## Seconds until the next ball may be picked up, every frame (design 4a,
## 2026-10-25): a wait starting slides in the mini toast — the ball and
## `0.8S` ticking down — which lives HudCopy.WAIT_TOAST_S and fades by
## itself (reading 0.0S once the ball is ready). Any other notice takes the
## slot; a wait still running when the mini toast has gone brings it back.
func set_ball_wait(seconds: float) -> void:
	var mini_up := _toast_small.visible and _toast_small.is_mini()
	if seconds <= 0.0:
		if mini_up:
			_toast_small.set_mini(HudCopy.wait_title(0.0), "icon_ball")
		_wait_shown = false
		return
	var title := HudCopy.wait_title(seconds)
	if _wait_shown and mini_up:
		_toast_small.set_mini(title, "icon_ball")
		return
	if toast_shown() and not mini_up:
		return   # another notice has the slot
	_toast_small.color = CREAM
	_toast_small.set_mini(title, "icon_ball")
	_toast_small.show_once(HudCopy.WAIT_TOAST_S)
	_wait_shown = true


func wait_shown() -> bool:
	return _wait_shown and _toast_small.visible and _toast_small.is_mini()


## Endless practice: the clock slot reads PRACTICE (or the area's label) and the countdown never shows.
func set_practice(on: bool, label := "PRACTICE") -> void:
	_practice = on
	_clock_card.visible = not on
	_practice_card.visible = on
	if on:
		(_practice_card.find_child("PracticeLabel", true, false) as Label).text = label.to_upper() if label != "" else "PRACTICE"


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
	_clock.text = HudCopy.clock_text(time_left)
	_clock.add_theme_color_override("font_color", GOLD if HudCopy.clock_hot(time_left) and phase != TimeTrial.PHASE_COUNTDOWN else CREAM)
	if phase == TimeTrial.PHASE_COUNTDOWN:
		# Every mode counts down in the toast chip: STARTS IN over the digit.
		countdown_toast(str(ceili(countdown)), HudCopy.countdown_pre(), CREAM)
	elif phase == TimeTrial.PHASE_RUNNING:
		# GO replaces the digits (go_toast / banner("GO!")); a stale digit fades.
		if _toast_big.visible and _toast_big.title_text() != "GO" and not _toast_big.leaving():
			_toast_big.fade_out()


func set_score(score: int) -> void:
	_score_spring.target = float(score)
	_refresh_best()


# ---- toasts (league HUD, design 4a) --------------------------------------------------


## The big chip: `pre` (may be "") over the digit/word; slides in once and
## then only swaps its text (the digit pops) while it stays up.
func countdown_toast(title: String, pre: String, color: Color) -> void:
	var fresh := not _toast_big.visible or _toast_big.color != color
	_toast_big.color = color
	_toast_big.set_big(pre, title)
	if fresh:
		_toast_big.show_stay()


func hide_countdown_toast() -> void:
	_toast_big.hide_now()


## GO in orange (design 4a `toastSlideOut`): the countdown's chip turns
## over to GO where it is — the word pops — holds 0.6 s and fades over
## 0.45 s. With no countdown up it slides in first.
func go_toast() -> void:
	var up := _toast_big.visible and not _toast_big.leaving()
	_toast_big.color = RetroTheme.LIGHT["orange"]
	_toast_big.set_big("", "GO")
	if not up:
		_toast_big.show_stay()
	_toast_big.fade_out(Toast.GO_HOLD_S, Toast.GO_FADE_S)


## The small notice chip (OVERTIME · 20S ON THE CLOCK with the stopwatch); stays until hidden.
func toast(title: String, sub := "", icon_name := "", color := GOLD) -> void:
	_wait_shown = false
	_toast_small.color = color
	_toast_small.set_small(title, sub, icon_name)
	_toast_small.show_stay()


## A card played (design 4a): the card's thumb, its name over PLAYED ON …,
## the target badge; blue for your plays, orange for theirs; gone by itself.
func card_toast(title: String, sub: String, card: Dictionary, target: String, color: Color) -> void:
	_wait_shown = false
	_toast_small.color = color
	_toast_small.set_card(title, sub, card, target)
	_toast_small.show_once(HudCopy.TOAST_S)


## The buzzer (design 5a): TIME! over SCORE n (· NEW BEST when it is), orange, the stopwatch.
func time_toast(score: int, new_best: bool) -> void:
	var t := HudCopy.time_toast(score, new_best)
	_wait_shown = false
	_toast_small.color = t["color"]
	_toast_small.set_small(str(t["title"]), str(t["sub"]), str(t["icon"]))
	_toast_small.show_once(float(t["seconds"]))


## Take the notice down (the OT break is over…): it fades where it is.
func hide_toast() -> void:
	_wait_shown = false
	_toast_small.fade_out()


## A notice is up (not on its way out).
func toast_shown() -> bool:
	return _toast_small.visible and not _toast_small.leaving()


func countdown_toast_text() -> String:
	return _toast_big.title_text() if _toast_big.visible else ""


## A mid-play call, as the toast chip HudCopy.toast_for maps it to: GO in
## the big chip, everything else in the small one at the top. The signature
## stays so every screen call site reads as it did.
func banner(text: String, color := GOLD) -> void:
	var t := HudCopy.toast_for(text, color)
	if str(t["kind"]) == "big":
		go_toast()
		return
	var same_stay := bool(t["stay"]) and _toast_small.visible and _toast_small.staying() and not _wait_shown
	_wait_shown = false
	_toast_small.color = t["color"]
	_toast_small.set_small(str(t["title"]), str(t["sub"]), str(t["icon"]), str(t["pre"]))
	if bool(t["stay"]):
		if not same_stay:
			_toast_small.show_stay()   # the next second only swaps the text
	else:
		_toast_small.show_once(float(t["seconds"]))


## The same call (kept for the older callers' name).
func note(text: String, color := CREAM) -> void:
	banner(text, color)


## What the chips read right now, for tests: the small one's title, else the big one's.
func banner_text() -> String:
	if _toast_small.visible:
		return ("%s %s %s" % [_toast_small.pre_text(), _toast_small.title_text(), _toast_small.sub_text()]).strip_edges()
	return _toast_big.title_text() if _toast_big.visible else ""


func clock_text() -> String:
	return _clock.text


func side_texts() -> Array:
	return [_you_score.text, _opp_score.text] if _heat else []


func best_text() -> String:
	return "%s %s" % [_best_label.text, _best_val.text] if _best_chip.visible else ""


# ---- pieces ----------------------------------------------------------------------


func _card(color: Color, pos: Vector2, size_: Vector2, tint: float, pad_h: float) -> ShadowPanel:
	var p := ShadowPanel.new(color, 0.0, tint, pad_h)
	p.position = UiLayout.hud_pos(pos)
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
