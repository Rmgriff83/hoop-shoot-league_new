class_name NewSeasonPage
extends SeasonPage
## NEW SEASON (design 39d, docs/HOME.md → Season wrap-up and new season):
## after START SEASON. The season number rolls from the old to the new in
## its orange box, DEFENDING CHAMPS pops for a champion, the old record
## strikes out to 0-0, the opening week's three games deal in from the
## right, then PLAY DAY 1 (to the pre-match page) or LATER. Built from
## SeasonCopy.new_season(doc, cfg).

signal play
signal later

const LEAGUE_Y := 150.0
const ROLL_Y := 210.0
const BOX_W := 120.0
const BOX_H := 124.0
const CHIP_Y := 384.0
const RECORD_Y := 480.0
const WEEK_Y := 580.0
const CARD_H := 112.0
const CARD_GAP := 18.0
const BUTTONS_Y := 1280.0
const PLAY_AT := 3.4
const ROLL_AT := 1.0

var _old: Label
var _new: Label
var _strike: ColorRect
var _play: Button
var _later: ShadowCard


func _fill() -> void:
	var v := _v
	# The orange rays behind everything, fading in by 1 s.
	var rays := PrizeRays.new(ORANGE)
	rays.name = "Rays"
	rays.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rays.position = Vector2(W * 0.5 - 800.0, 310.0 - 800.0)
	rays.size = Vector2(1600, 1600)
	rays.speed_deg = 360.0 / 30.0
	rays.alpha = 0.32
	_sheet.add_child(rays)
	_anim(rays, "fadein", 1.0, 0.6)
	var league := _label(str(v.get("league", "")), 20, CREAM, false)
	league.name = "League"
	_centred(league, LEAGUE_Y, 24.0)
	_anim(league, "rise", 0.1, 0.4)
	# SEASON [2 → 3]
	var roll := Control.new()
	roll.name = "SeasonRow"
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var word_w := 48.0 * 6.0
	var row_w := word_w + 28.0 + BOX_W
	_put(roll, (W - row_w) * 0.5, ROLL_Y, row_w, BOX_H)
	var word := _label("SEASON", 48, CREAM, true)
	word.name = "SeasonWord"
	RetroTheme.dithered(word, Vector2(6, 6))
	_put(word, 0.0, 0.0, word_w, BOX_H, roll)
	var box := ShadowPanel.new(ORANGE, 0.0, 0.3, 0.0)
	box.name = "SeasonBox"
	_put(box, word_w + 28.0, 0.0, BOX_W, BOX_H, roll)
	var clip := _inner(box)
	clip.clip_contents = true
	clip.position = Vector2(2, 2)
	clip.size = Vector2(BOX_W - ShadowStyle.OFFSET - 4.0, BOX_H - ShadowStyle.OFFSET - 4.0)
	clip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_old = _label(str(v.get("old_year", "")), 80, CREAM, true)
	_old.name = "Old"
	_old.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_put(_old, 0.0, 0.0, clip.size.x, clip.size.y, box)
	_new = _label(str(v.get("new_year", "")), 80, GOLD, true)
	_new.name = "New"
	_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_put(_new, 0.0, BOX_H, clip.size.x, clip.size.y, box)
	_anim(_old, "outup", ROLL_AT, 0.35, BOX_H)
	_anim(_new, "infrom", ROLL_AT, 0.35, BOX_H)
	_anim(roll, "rise", 0.3, 0.4)
	# DEFENDING CHAMPS.
	if bool(v.get("defending", false)):
		var chip := _panel(GOLD, 0.0, CHIP_Y, 0.0, 48.0, 16.0, 0.35)
		chip.name = "Defending"
		chip.ground = Color(DARK, 0.5)
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 12)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := PixelIcon.new("icon_trophy", Vector2(26, 26))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(ic)
		var dl := _label(str(v.get("defending_text", "DEFENDING CHAMPS")), 16, CREAM, true)
		inner.add_child(dl)
		chip.add_child(inner)
		var chip_w := 16.0 * 2.0 + 26.0 + 12.0 + 16.0 * str(v.get("defending_text", "DEFENDING CHAMPS")).length() + ShadowStyle.OFFSET
		chip.position = Vector2((W - chip_w) * 0.5, CHIP_Y)
		chip.size = Vector2(chip_w, 48.0 + ShadowStyle.OFFSET)
		chip.pivot_offset = chip.size * 0.5
		_anim(chip, "pop", 1.5, 0.4)
	# RECORD 10-4 > 0-0 (the old struck through, the new popping).
	var rec := Control.new()
	rec.name = "RecordRow"
	rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var old_text := str(v.get("record_old", ""))
	var old_w := 30.0 * maxf(old_text.length(), 1) + 8.0
	var rec_w := 18.0 * 6.0 + 22.0 + old_w + 22.0 + 30.0 + 22.0 + 30.0 * 3.0
	_put(rec, (W - rec_w) * 0.5, RECORD_Y, rec_w, 40.0)
	var rl := _label("RECORD", 18, CREAM, false)
	rl.name = "RecordLabel"
	_put(rl, 0.0, 0.0, 18.0 * 6.0, 40.0, rec)
	var x := 18.0 * 6.0 + 22.0
	var old := _label(old_text, 30, CREAM, true)
	old.name = "RecordOld"
	old.modulate.a = 0.6
	_put(old, x, 0.0, old_w, 40.0, rec)
	_strike = ColorRect.new()
	_strike.name = "Strike"
	_strike.color = ORANGE
	_strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(_strike, x - 4.0, 18.0, 0.0, 4.0, rec)
	_anim(_strike, "strike", 2.0, 0.3, old_w + 8.0)
	x += old_w + 22.0
	var chev := _label(">", 30, CREAM, true)
	_put(chev, x, 0.0, 30.0, 40.0, rec)
	x += 30.0 + 22.0
	var nw := _label(str(v.get("record_new", "0-0")), 30, GOLD, true)
	nw.name = "RecordNew"
	nw.pivot_offset = Vector2(45.0, 20.0)
	_put(nw, x, 0.0, 30.0 * 3.0, 40.0, rec)
	_anim(nw, "pop", 2.25, 0.35)
	_anim(rec, "rise", 1.7, 0.4)
	if old_text == "":
		old.visible = false
		_strike.visible = false
	# OPENING WEEK · 14 DAYS · 8 TEAMS, then the three cards dealing in.
	var wk: Dictionary = v.get("week", {})
	var week := Control.new()
	week.name = "Week"
	week.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(week, 0.0, WEEK_Y, W, 20.0)
	var wt := _label(str(wk.get("title", "")), 16, CREAM, false)
	wt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_put(wt, 0.0, 0.0, W * 0.5, 20.0, week)
	var ws := _label(str(wk.get("sub", "")), 16, CREAM, false)
	ws.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_put(ws, W * 0.5, 0.0, W * 0.5, 20.0, week)
	_anim(week, "rise", 2.4, 0.4)
	var cards: Array = v.get("cards", [])
	var cy := WEEK_Y + 20.0 + CARD_GAP
	for i in cards.size():
		var c: Dictionary = cards[i]
		var colour := ORANGE if i == 0 else CREAM
		var card := _panel(colour, 0.0, cy, W, CARD_H, 24.0, 0.25 if i == 0 else 0.16)
		card.name = "DayCard_%d" % i
		card.ground = Color(DARK, 0.55)
		var day := _label(str(c.get("day", "")), 18, CREAM, true)
		day.name = "Day"
		day.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_put(day, 24.0, 0.0, 100.0, CARD_H - ShadowStyle.OFFSET, card)
		var nm := _label(str(c.get("name", "")), 20, CREAM, true)
		nm.name = "Name"
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.clip_text = true
		_put(nm, 144.0, 26.0, W - 144.0 - 24.0 - 80.0, 24.0, card)
		var h2h := _label(str(c.get("h2h", "")), 15, CREAM, false)
		h2h.name = "H2h"
		h2h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_put(h2h, 144.0, 62.0, W - 144.0 - 24.0 - 80.0, 20.0, card)
		var side := _label(str(c.get("side", "")), 16, CREAM, false)
		side.name = "Side"
		side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(side, W - 24.0 - 80.0 - ShadowStyle.OFFSET, 0.0, 80.0, CARD_H - ShadowStyle.OFFSET, card)
		_anim(card, "dealin", 2.6 + 0.2 * i, 0.4, 360.0)
		cy += CARD_H + CARD_GAP
	var more := _label(str(v.get("more", "")), 16, CREAM, false)
	more.name = "More"
	_centred(more, cy + 6.0, 20.0)
	_anim(more, "rise", 3.2, 0.4)
	# PLAY DAY 1 / VS … · HOME, and LATER.
	var pl: Dictionary = v.get("play", {})
	_play = _card_button(str(pl.get("title", "")), str(pl.get("sub", "")), RetroTheme.c("orange"), 0.0, BUTTONS_Y, W - 160.0 - 24.0, 120.0, PLAY_AT, true, 28)
	_play.name = "Play"
	_play.pressed.connect(func() -> void: play.emit())
	_later = _word_button(str(v.get("later", "LATER")), W - 160.0, BUTTONS_Y, 160.0, 120.0, PLAY_AT)
	_later.name = "Later"
	_later.pressed.connect(func() -> void:
		later.emit()
		close()
	)


func _tick() -> void:
	_sound_once("chime", ROLL_AT, Sfx.chime_win)


func strike_width() -> float:
	return _strike.size.x if _strike != null else 0.0
