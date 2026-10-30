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
## (design "League Match HUD" 4a, 2026-10-30 pass) swaps the score card for
## one 344×120 box beside the pause — YOU on an orange band over the
## opponent's first name under a rule, each with its score (gold for the
## one ahead) and a tag: ICED (the snowflake) while their rim is iced, else
## the flame and their streak from 2 makes — moves the clock card to the
## row's right end, puts a gold OT tag in it in overtime, and shows the
## ball-return wait as the mini toast (the ball and `0.8S`, 2026-10-25). Every toast
## leaves by fading where it is (design 4a's latest pass). Copy from HudCopy (pure).
## An ANCHORED layer since Ross's 2026-10-26 pass: every position here is a
## band design position mapped through UiLayout.hud_pos — the top row under
## the notch, the toasts and the rest spread to the real screen.

const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")
## The top row (designs 5a / 4a, Ross's 2026-10-26 pass): a 120-tall row —
## the 120 px pause, the 150×120 clock / PRACTICE card (icon over the
## figure), the 164×120 SCORE card or the two 162×60 side cards — with, in
## a trial, the 164×60 BEST and TOP chips stacked under the score card
## (22 and 14 px gaps, hung off the top row: they never scale away from it).
const ROW_H := 120.0
const CLOCK_POS := Vector2(172, 32)
const CLOCK_SIZE := Vector2(150, 120)
const SCORE_POS := Vector2(520, 32)
const SCORE_SIZE := Vector2(164, 120)
const BEST_POS := Vector2(520, 32 + 120 + 22)
const BEST_SIZE := Vector2(164, 60)
const TOP_POS := Vector2(520, 32 + 120 + 22 + 60 + 14)
const TOP_SIZE := Vector2(164, 60)
## A heat's row (4a, 2026-10-30): the score box beside the pause, the clock
## card at the right end.
const BOX_POS := Vector2(172, 32)
const BOX_SIZE := Vector2(344, 120)
const BOX_ROW_H := 52.0
const HEAT_CLOCK_POS := Vector2(534, 32)
const ICED_C := Color("#A9E4FF")
const STREAK_C := Color("#FFB070")
## A streak shows from this many makes in a row.
const STREAK_SHOWN := 2
## The toasts (designs 4a / 5a; 2026-10-30: centred at 1090 on the
## design's iPhone, under the lower opponent window): the countdown chip and
## the notice chip both hang off the screen's edge (App.hud_side).
const TOAST_Y := 888.0
const GO_TOAST_S := 0.9

var _clock_card: ShadowPanel
var _toast_big: Toast
var _toast_small: Toast
var _clock: Label
var _ot_tag: Label
var _score_card: ShadowPanel
var _box: ShadowPanel
var _you_score: Label
var _opp_score: Label
var _you_tag: Dictionary = {}   # {box, icon, text} — ICED or the streak
var _opp_tag: Dictionary = {}
var _practice_card: ShadowPanel
var _score: Label
var _score_caps: Label
var _best_chip: ShadowPanel
var _best_label: Label
var _best_val: Label
## The TOP chip (5a, 2026-10-26): the area's all-time global top score under BEST.
var _top_chip: ShadowPanel
var _top_val: Label
var _top := -1
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
	_clock_card = _card(CREAM, CLOCK_POS, CLOCK_SIZE, 0.32, 12.0)
	_clock_card.name = "Clock"
	var ccol := _vbox(16)
	var cr := _hbox(10)
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	cr.custom_minimum_size = Vector2(0, 28)
	cr.add_child(_icon("icon_stopwatch", 28))
	_ot_tag = _text("OT1", 16, GOLD, true)
	_ot_tag.name = "OtTag"
	_ot_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ot_tag.visible = false
	cr.add_child(_ot_tag)
	ccol.add_child(cr)
	_clock = _text("60.0", 28, CREAM, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ccol.add_child(_clock)
	_clock_card.add_child(ccol)
	_practice_card = _card(RetroTheme.c("teal"), CLOCK_POS, CLOCK_SIZE, 0.32, 12.0)
	_practice_card.name = "Practice"
	_practice_card.visible = false
	var pr := _vbox(16)
	pr.add_child(_icon("icon_jersey", 32))
	var pl := _text("PRACTICE", 16, CREAM, true)
	pl.name = "PracticeLabel"
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.add_child(pl)
	_practice_card.add_child(pr)
	# The score card.
	var sc := _card(RetroTheme.c("orange"), SCORE_POS, SCORE_SIZE, 0.32, 16.0)
	sc.name = "ScoreCard"
	_score_card = sc
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_caps = _text("SCORE", 20)
	_score_caps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_score_caps)
	_score = _text("0", 52, CREAM, true)
	_score.name = "Score"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_score)
	sc.add_child(col)
	# The BEST chip (trials: shown by set_best).
	_best_chip = _card(GOLD, BEST_POS, BEST_SIZE, 0.40, 12.0, true)
	_best_chip.name = "BestChip"
	_best_chip.visible = false
	var br := _hbox(10)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	_best_label = _text("BEST", 20)
	_best_label.name = "BestLabel"
	_best_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	br.add_child(_best_label)
	_best_val = _text("-", 24, CREAM, true)
	_best_val.name = "BestVal"
	_best_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	br.add_child(_best_val)
	_best_chip.add_child(br)
	# The TOP chip (trials, with BEST): the area's all-time global top score.
	_top_chip = _card(CREAM, TOP_POS, TOP_SIZE, 0.30, 12.0, true)
	_top_chip.name = "TopChip"
	_top_chip.visible = false
	var tr := _hbox(10)
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	var tl := _text("TOP", 20)
	tl.name = "TopLabel"
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tr.add_child(tl)
	_top_val = _text("-", 24, CREAM, true)
	_top_val.name = "TopVal"
	_top_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tr.add_child(_top_val)
	_top_chip.add_child(tr)
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
		# Gold for whoever is ahead (by the real scores, not the springs).
		var you := roundi(_score_spring.target)
		var opp := roundi(_opp_spring.target)
		_you_score.add_theme_color_override("font_color", GOLD if you > opp else CREAM)
		_opp_score.add_theme_color_override("font_color", GOLD if opp > you else CREAM)
	else:
		_score.text = str(roundi(_score_spring.value))


# ---- modes -----------------------------------------------------------------------


## A heat: the score box on the row in place of the SCORE card — YOU on
## the orange band over the opponent's first name — and the clock card at
## the row's right end. Called again when the heat is restaged (an online
## room's real config after the pre-match page, a rematch): the old box goes
## first, or its stale "0" would show through the new see-through face
## (Ross, 2026-10-27). `_opp_color` is no longer worn on the row (the
## opponent window keeps it).
func set_heat(on: bool, opp_label := "OPP", _opp_color := LeagueContext.PINE) -> void:
	_heat = on
	if not on:
		return
	_score_card.visible = false
	_best_chip.visible = false
	_top_chip.visible = false
	_clock_card.position.x = HEAT_CLOCK_POS.x
	if is_instance_valid(_box):
		_box.free()
	_box = _card(CREAM, BOX_POS, BOX_SIZE, 0.32, 18.0)
	_box.name = "ScoreBox"
	var rows := _vbox(0)
	rows.name = "Rows"
	_box.add_child(rows)
	var you := _box_row("You", "YOU", true)
	rows.add_child(you["row"])
	_you_score = you["score"]
	_you_tag = you["tag"]
	var opp := _box_row("Opp", opp_label.to_upper(), false)
	rows.add_child(opp["row"])
	_opp_score = opp["score"]
	_opp_tag = opp["tag"]


## One line of the box: the name, its tag, the score; YOU on the orange band
## (reaching the box's edges), the opponent under a rule.
func _box_row(name_: String, label: String, band: bool) -> Dictionary:
	var row := BoxRow.new(band)
	row.name = name_ + "Row"
	row.custom_minimum_size = Vector2(0, BOX_ROW_H)
	var h := _hbox(12)
	UiLayout.full_rect(h)
	row.add_child(h)
	var n := _text(label, 20, CREAM, true)
	n.name = "Side"
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.size_flags_vertical = Control.SIZE_FILL
	h.add_child(n)
	var tag := _hbox(4)
	tag.name = "Tag"
	tag.visible = false
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := TextureRect.new()
	icon.name = "TagIcon"
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_END
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(icon)
	var tt := _text("", 14, CREAM, true)
	tt.name = "TagText"
	tt.size_flags_vertical = Control.SIZE_SHRINK_END
	tag.add_child(tt)
	h.add_child(tag)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	var v := _text("0", 32, CREAM, true)
	v.name = "Value"
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_FILL
	h.add_child(v)
	return {"row": row, "score": v, "tag": {"box": tag, "icon": icon, "text": tt}}


## Each side's tag (design 4a, 2026-10-30): ICED with the snowflake while
## their rim is iced, else the flame and their streak once it reaches
## STREAK_SHOWN. Cheap to call every frame: it only touches what changed.
func set_side_tags(you_streak: int, you_iced: bool, opp_streak: int, opp_iced: bool) -> void:
	if not _heat:
		return
	_set_tag(_you_tag, you_streak, you_iced)
	_set_tag(_opp_tag, opp_streak, opp_iced)


static func tag_text(streak: int, iced: bool) -> String:
	if iced:
		return "ICED"
	return str(streak) if streak >= STREAK_SHOWN else ""


func _set_tag(tag: Dictionary, streak: int, iced: bool) -> void:
	if tag.is_empty():
		return
	var text := tag_text(streak, iced)
	var box: Control = tag["box"]
	var label: Label = tag["text"]
	if label.text == text and box.visible == (text != ""):
		return
	box.visible = text != ""
	label.text = text
	label.add_theme_color_override("font_color", ICED_C if iced else STREAK_C)
	(tag["icon"] as TextureRect).texture = load("res://assets/ui/cards/%s.png" % ("snow_a" if iced else "flame_a"))


## The tags as they read: [you, opponent] ("" when hidden), for tests.
func tag_texts() -> Array:
	var out := []
	for tag in [_you_tag, _opp_tag]:
		out.push_back((tag["text"] as Label).text if not tag.is_empty() and (tag["box"] as Control).visible else "")
	return out


## The box's line under the YOU row, or YOU's orange band, drawn past the
## row to the box's inner edges (the design's margin 0 -16px).
class BoxRow extends Control:
	var band := false

	func _init(p_band: bool) -> void:
		band = p_band
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _draw() -> void:
		if band:
			var r := Rect2(Vector2(-16, 0), Vector2(size.x + 32, size.y))
			var o := RetroTheme.LIGHT["orange"] as Color
			draw_rect(r, Color(o, 0.55))
			draw_texture_rect(ShadowStyle.dot_tex(), r, true, Color(o, ShadowStyle.DOT_ALPHA))
		else:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 2)), Color(1, 1, 1, 0.3))


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


## The area's all-time global top score (the TOP chip under BEST, 5a
## 2026-10-26): shown with the BEST chip; -1 reads "-" (no board in hand).
func set_top(top: int) -> void:
	_top = top
	_top_chip.visible = _best_chip.visible
	_top_val.text = str(top) if top >= 0 else "-"


func top_text() -> String:
	return "TOP %s" % _top_val.text if _top_chip.visible else ""


func _refresh_best() -> void:
	if _best < 0:
		return
	var chip := HudCopy.best_chip(_best, roundi(_score_spring.target))
	_best_label.text = str(chip["label"])
	_best_val.text = str(chip["val"])
	# NEW BEST 31 is wider than the 164 chip; a panel grows from its left
	# edge, so it ran off the right of the screen (Ross, 2026-10-28). The
	# chip keeps its right edge under the score card and grows left instead.
	var right := BEST_POS.x + BEST_SIZE.x + ShadowStyle.OFFSET
	var w := maxf(BEST_SIZE.x + ShadowStyle.OFFSET, _best_chip.get_combined_minimum_size().x)
	_best_chip.size.x = w
	_best_chip.position.x = right - w


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


## The BEST chip's [left, right] edges in band x (the right one never moves).
func best_edges() -> Array:
	return [_best_chip.position.x, _best_chip.position.x + _best_chip.size.x]


# ---- pieces ----------------------------------------------------------------------


## A card at a band design position, on the real screen: through hud_pos,
## or (under_row) hung off the top row at the design's gap — the chip stack
## under the score card keeps its spacing on every screen.
func _card(color: Color, pos: Vector2, size_: Vector2, tint: float, pad_h: float, under_row := false) -> ShadowPanel:
	var p := ShadowPanel.new(color, 0.0, tint, pad_h)
	p.position = Vector2(pos.x, UiLayout.hud_top() + (pos.y - UiLayout.HUD_TOP)) if under_row else UiLayout.hud_pos(pos)
	p.size = size_ + Vector2.ONE * ShadowStyle.OFFSET
	p.custom_minimum_size = p.size
	add_child(p)
	return p


func _icon(name_: String, px := 20) -> PixelIcon:
	var i := PixelIcon.new(name_, Vector2(px, px))
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return i


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l
