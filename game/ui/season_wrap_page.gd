class_name SeasonWrapPage
extends SeasonPage
## SEASON WRAP-UP (design 39c CHAMPIONS / 39e OUT IN THE PLAYOFFS / 39f
## MISSED THE PLAYOFFS, docs/HOME.md → Season wrap-up): shown once on the
## league home after the season's last game. The head (league, SEASON N,
## X), the result banner (gold with the trophy / orange / cream), the
## CHAMPION and RUNNER-UP cards, six season stats, three highlights, the
## SEASON EARNINGS counting up, then START SEASON N+1 or LATER. Built from
## SeasonCopy.wrap(doc, cfg).

signal start_season
signal later

const HEAD_Y := 94.0
const BANNER_Y := 250.0
const CARDS_Y := 450.0
const STATS_Y := 580.0
const HL_Y := 872.0
const EARN_Y := 1108.0
const BUTTONS_Y := 1280.0
const BUTTONS_AT := 2.6
const COUNT_FROM := 2.2
const COUNT_S := 1.0

var _xp_label: Label
var _ticket_box: TicketBox
var _start: Button
var _later: ShadowCard


func _fill() -> void:
	var v := _v
	# The dark band behind the head.
	var band := ColorRect.new()
	band.name = "Band"
	band.color = Color(DARK, 0.55)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(band, -6.0, -PAD, W + 12.0, 216.0 + PAD)
	# League over SEASON N, the X at the right.
	var league := _label(str(v.get("league", "")), 16, CREAM, false)
	league.name = "League"
	league.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_put(league, 0.0, HEAD_Y, 440.0, 20.0)
	var season := _label(str(v.get("season", "")), 30, CREAM, true)
	season.name = "Season"
	season.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	RetroTheme.dithered(season, Vector2(6, 6))
	_put(season, 0.0, HEAD_Y + 34.0, 440.0, 36.0)
	var x := _word_button("X", W - 84.0, HEAD_Y, 84.0, 84.0, 0.0, 28)
	x.name = "Close"
	x.pressed.connect(close)
	# The banner: headline and line, the trophy for champions.
	var banner := _panel(v.get("banner_color", CREAM), 0.0, BANNER_Y, W, 170.0, 26.0, 0.25)
	banner.name = "Banner"
	banner.ground = Color(DARK, 0.6)
	var text_x := 26.0
	if bool(v.get("trophy", false)):
		var cup := PixelIcon.new("icon_trophy", Vector2(96, 96), 5.0)
		cup.name = "BannerCup"
		_put(cup, 26.0, 37.0, 96.0, 96.0, banner)
		text_x = 26.0 + 96.0 + 22.0
	var head := _label(str(v.get("head", "")), 26, v.get("head_color", CREAM), true)
	head.name = "Head"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	_put(head, text_x, 34.0, W - text_x - 26.0, 64.0, banner)
	var line := _label(str(v.get("line", "")), 16, CREAM, false)
	line.name = "Line"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_put(line, text_x, 104.0, W - text_x - 26.0, 40.0, banner)
	_anim(banner, "pop", 0.5, 0.4)
	# CHAMPION · 2-1 / name and RUNNER-UP / name.
	var card_w := (W - 24.0) * 0.5
	var ch: Dictionary = v.get("champion", {})
	var champ := _panel(GOLD, 0.0, CARDS_Y, card_w, 104.0, 18.0, 0.22)
	champ.name = "Champion"
	champ.ground = Color(DARK, 0.6)
	var ccup := PixelIcon.new("icon_trophy", Vector2(44, 44), 3.0)
	_put(ccup, 18.0, 30.0, 44.0, 44.0, champ)
	var ct := _label(str(ch.get("title", "")), 15, CREAM, false)
	ct.name = "ChampionTitle"
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_put(ct, 76.0, 26.0, card_w - 90.0, 20.0, champ)
	var cn := _label(str(ch.get("name", "")), 18, GOLD, true)
	cn.name = "ChampionName"
	cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cn.clip_text = true
	_put(cn, 76.0, 56.0, card_w - 90.0, 24.0, champ)
	_anim(champ, "rise", 0.8, 0.4)
	var ru: Dictionary = v.get("runner_up", {})
	var runner := _panel(CREAM, card_w + 24.0, CARDS_Y, card_w, 104.0, 18.0, 0.16)
	runner.name = "RunnerUp"
	runner.ground = Color(DARK, 0.6)
	var rt := _label(str(ru.get("title", "")), 15, CREAM, false)
	rt.name = "RunnerUpTitle"
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_put(rt, 18.0, 26.0, card_w - 36.0, 20.0, runner)
	var rn := _label(str(ru.get("name", "")), 18, CREAM, true)
	rn.name = "RunnerUpName"
	rn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rn.clip_text = true
	_put(rn, 18.0, 56.0, card_w - 36.0, 24.0, runner)
	_anim(runner, "rise", 0.8, 0.4)
	# Six stats in three columns.
	var stats: Array = v.get("stats", [])
	var grid := _panel(CREAM, 0.0, STATS_Y, W, 26.0 * 2.0 + 2.0 * 64.0 + 34.0, 26.0, 0.14)
	grid.name = "Stats"
	var col_w := (W - 52.0) / 3.0
	for i in stats.size():
		var cell := Control.new()
		cell.name = "Stat%d" % i
		var cx := 26.0 + col_w * (i % 3)
		var cy := 26.0 + (64.0 + 34.0) * (i / 3)
		cell.position = Vector2(cx, cy)
		cell.size = Vector2(col_w, 64.0)
		cell.pivot_offset = Vector2(col_w * 0.5, 32.0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var val := _label(str(stats[i].get("v", "")), 30, CREAM, true)
		val.name = "Value"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_put(val, 0.0, 0.0, col_w, 34.0, cell)
		var lab := _label(str(stats[i].get("l", "")), 15, CREAM, false)
		lab.name = "Label"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_put(lab, 0.0, 46.0, col_w, 18.0, cell)
		_inner(grid).add_child(cell)
		_anim(cell, "pop", 1.2 + 0.1 * i, 0.3)
	_anim(grid, "rise", 0.9, 0.4)
	# Three highlight rows with dashed rules.
	var hl: Array = v.get("highlights", [])
	var rows := Control.new()
	rows.name = "Highlights"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(rows, 0.0, HL_Y, W, 68.0 * hl.size())
	for i in hl.size():
		var row := Control.new()
		row.name = "Highlight_%d" % i
		row.position = Vector2(0, 68.0 * i)
		row.size = Vector2(W, 68.0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _label(str(hl[i].get("l", "")), 17, CREAM, false)
		l.name = "Label"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_put(l, 0.0, 0.0, W * 0.5, 68.0, row)
		var val := _label(str(hl[i].get("v", "")), 18, CREAM, true)
		val.name = "Value"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(val, W * 0.5, 0.0, W * 0.5, 68.0, row)
		var rule := MatchEndOverlay.DashLine.new(Color(CREAM, 0.35))
		rule.name = "Rule"
		_put(rule, 0.0, 66.0, W, 2.0, row)
		rows.add_child(row)
	_anim(rows, "rise", 1.8, 0.4)
	# SEASON EARNINGS: the XP card and the gold tickets card, counting up.
	var e: Dictionary = v.get("earned", {})
	var earn := Control.new()
	earn.name = "Earnings"
	earn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(earn, 0.0, EARN_Y, W, 16.0 + 16.0 + 92.0)
	var eh := _label(str(e.get("head", "SEASON EARNINGS")), 16, CREAM, false)
	eh.name = "EarningsHead"
	eh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_put(eh, 0.0, 0.0, W, 20.0, earn)
	var xp_card := ShadowPanel.new(CREAM, 0.0, 0.16, 0.0)
	xp_card.name = "XpCard"
	xp_card.ground = Color(DARK, 0.5)
	_put(xp_card, 0.0, 32.0, card_w, 92.0, earn)
	_xp_label = _label("+0 XP", 24, CREAM, true)
	_xp_label.name = "XpText"
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_put(_xp_label, 20.0, 0.0, card_w - 40.0, 92.0 - ShadowStyle.OFFSET, xp_card)
	_ticket_box = TicketBox.new(92.0 - ShadowStyle.OFFSET, 44.0, 24, 14, 20.0, 14.0, 44.0, 0.0, card_w - ShadowStyle.OFFSET)
	_ticket_box.name = "Tickets"
	_ticket_box.set_count(0)
	_ticket_box.set_sub("")
	_put(_ticket_box, card_w + 24.0, 32.0, card_w, 92.0, earn)
	_anim(earn, "rise", 2.1, 0.4)
	# START SEASON N+1 / NEW SCHEDULE and LATER.
	var st: Dictionary = v.get("start", {})
	_start = _card_button(str(st.get("title", "")), str(st.get("sub", "")), RetroTheme.c("orange"), 0.0, BUTTONS_Y, W - 160.0 - 24.0, 150.0, BUTTONS_AT)
	_start.name = "Start"
	_start.pressed.connect(func() -> void: start_season.emit())
	_later = _word_button(str(v.get("later", "LATER")), W - 160.0, BUTTONS_Y, 160.0, 150.0, BUTTONS_AT)
	_later.name = "Later"
	_later.pressed.connect(func() -> void:
		later.emit()
		close()
	)


## The earnings count up 2.2 → 3.2 s; the chimes.
func _tick() -> void:
	var e: Dictionary = _v.get("earned", {})
	var p := clampf((_t - COUNT_FROM) / COUNT_S, 0.0, 1.0)
	var k := _ease_out(p)
	if _xp_label != null:
		_xp_label.text = "+%s XP" % SeasonCopy.thousands(roundi(float(int(e.get("xp_n", 0))) * k))
	if _ticket_box != null:
		var n := roundi(float(int(e.get("tickets_n", 0))) * k)
		if n != int(_ticket_box.count_text().replace(",", "").replace("+", "").to_int()):
			_ticket_box.set_count(n)
	if str(_v.get("variant", "")) == "champs":
		_sound_once("chime", 0.5, Sfx.chime_big)
	_sound_once("shuffle", COUNT_FROM, Sfx.ticket_shuffle)


func earned_text() -> String:
	return _xp_label.text if _xp_label != null else ""


func tickets_text() -> String:
	return _ticket_box.count_text() if _ticket_box != null else ""


func stat_count() -> int:
	var grid: Control = _sheet.find_child("Stats", true, false) if _sheet != null else null
	return _inner(grid).get_child_count() if grid != null else 0
