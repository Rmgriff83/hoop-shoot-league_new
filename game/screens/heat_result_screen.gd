extends Node3D
## League post-match (design "League Post-Match", docs/HOME.md → Results):
## the heat's numbers over the LIVE court you just played on (the area's
## home pan under a half scrim), in the home's retro style. Top to bottom:
## `ARCADE LEAGUE · SEASON 2 · DAY 4`, the result big with the dithered
## shadow (YOU WIN in gold), the score with an OT chip when it went there,
## `VS NAME · "NICKNAME"`; the box score on a see-through panel with a YOU
## chip and the opponent's chip in their colour, the better number in gold;
## the coins card (with the tickets) beside the card drop; CONTINUE SEASON
## back to the home with the league open, and HOME. A heat outside a league
## (test-only) gets the header QUICK HEAT and only HOME. Copy from HeatCopy
## (pure); the heat from App.last_heat, the doc from App.league_doc.

const MARGIN := 36.0
const RIGHT := 720.0 - 42.0
const SCRIM_ALPHA := 0.5
const HEAD_Y := 80.0
const BOX_Y := 392.0
const BOX_W := 642.0
const CARDS_Y := 814.0
const CARD_H := 150.0
const CONT_Y := 1002.0
const CONT_H := 128.0
const HOME_Y := 1158.0
const HOME_H := 64.0
const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")

var _t := 0.0
var _spec: Dictionary = {}
var _court: CourtGeometry
var _cam: Camera3D


func _ready() -> void:
	var heat: Dictionary = App.last_heat
	_build_court(str(heat.get("location", "cage")), str(heat.get("mode", "heat")))
	var ui := CanvasLayer.new()
	ui.name = "Ui"
	ui.layer = 10
	add_child(ui)
	var league := HeatCopy.league_of(heat)
	var lid := str(league.get("id", ""))
	ui.add_child(build_chrome(heat, App.league_doc(lid) if lid != "" else {}, LeagueData.league(lid) if lid != "" else {}))


func _process(dt: float) -> void:
	_t += dt
	if _court != null:
		var p := TitlePan.pose(_spec, _t)
		_cam.position = p["pos"]
		_cam.look_at(p["look"])
		_court.step_rim(dt)


# ---- the court behind (the home page's recipe) -----------------------------------


func _build_court(location: String, mode: String) -> void:
	var arena := CosmeticLibrary.get_arena(location)
	if arena == null:
		arena = CosmeticLibrary.starter_arena()
	if not App.MODES.has(mode):
		mode = "heat"
	_cam = Camera3D.new()
	_cam.name = "Camera"
	add_child(_cam)
	_court = CourtGeometry.new()
	_court.name = "Court"
	_court.geo = App.geo_for_mode(mode)
	_court.arena_set = arena
	_court.hoop_set = App.hoop_for_mode(mode)
	add_child(_court)
	_court.led.set_text("HOOP SHOOT", _court.led.accent_color)
	_spec = TitlePan.spec_of(arena)
	_cam.fov = float(_spec["fov"])
	var p := TitlePan.pose(_spec, 0.0)
	_cam.position = p["pos"]
	_cam.look_at(p["look"])


# ---- the chrome ------------------------------------------------------------------


## Everything over the court, as one Control (also built off-tree by tests).
func build_chrome(heat: Dictionary, doc: Dictionary, cfg: Dictionary) -> Control:
	var chrome := Control.new()
	chrome.name = "Chrome"
	chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(RetroTheme.SCENE_OUTLINE, SCRIM_ALPHA)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(scrim)
	var in_league := not HeatCopy.league_of(heat).is_empty()

	# Header: the league line, the result, the score (+ OT), the opponent.
	var head := _vbox(26)
	head.name = "Head"
	head.position = Vector2(MARGIN, HEAD_Y)
	head.size = Vector2(720 - 2 * MARGIN, 0)
	chrome.add_child(head)
	var hl := _text(HeatCopy.header(heat, doc))
	hl.name = "Header"
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(hl)
	var res := HeatCopy.result(heat)
	var rl := _text(str(res["text"]), int(res["size"]), GOLD if bool(res["gold"]) else CREAM, true)
	rl.name = "Result"
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetroTheme.dithered(rl)
	head.add_child(rl)
	var score_row := _hbox(20)
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(score_row)
	var sl := _text(HeatCopy.score_line(heat), 88, CREAM, true)
	sl.name = "ScoreLine"
	RetroTheme.dithered(sl)
	score_row.add_child(sl)
	if HeatCopy.ot(heat):
		var chip := ShadowPanel.new(GOLD, 0.0, 0.30, 12.0)
		chip.name = "OT"
		chip.custom_minimum_size = Vector2(0, 40 + ShadowStyle.OFFSET)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ot := _text("OT", 16, CREAM, true)
		ot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(ot)
		score_row.add_child(chip)
	var vs := _text(HeatCopy.vs_line(heat), 20)
	vs.name = "Vs"
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(vs)
	# The level line (docs/PROGRESSION.md) adds a row: everything below drops with it.
	var lv := HeatCopy.level_line(heat, App.xp())
	var shift := 0.0
	if not lv.is_empty():
		var ll := _text(str(lv["text"]), 16, GOLD if bool(lv["gold"]) else CREAM, true)
		ll.name = "LevelLine"
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(ll)
		shift = 42.0

	# The box score.
	var box := ShadowPanel.new(CREAM, 14.0, 0.14, 24.0)
	box.name = "Box"
	box.position = Vector2(MARGIN, BOX_Y + shift)
	box.size = Vector2(BOX_W + ShadowStyle.OFFSET, 0)
	chrome.add_child(box)
	var bcol := _vbox(0)
	box.add_child(bcol)
	var bh := _hbox(0)
	bh.custom_minimum_size = Vector2(0, 52)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bh.add_child(spacer)
	var oc := HeatCopy.opponent_chip(heat)
	for spec in [["YOU", RetroTheme.c("orange"), 0.30, "YouChip"], [str(oc["text"]), oc["color"], 0.40, "ThemChip"]]:
		var cell := _hbox(0)
		cell.custom_minimum_size = Vector2(150, 0)
		cell.alignment = BoxContainer.ALIGNMENT_END
		var chip := ShadowPanel.new(spec[1], 0.0, float(spec[2]), 12.0)
		chip.name = str(spec[3])
		chip.custom_minimum_size = Vector2(0, 36 + ShadowStyle.OFFSET)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var l := _text(str(spec[0]), 16, CREAM, true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(l)
		cell.add_child(chip)
		bh.add_child(cell)
	bcol.add_child(bh)
	for r in HeatCopy.box(heat):
		bcol.add_child(_box_row(r))

	# Coins beside the card drop, CONTINUE SEASON, HOME.
	if in_league:
		var cards := _hbox(26 - int(ShadowStyle.OFFSET))
		cards.name = "Cards"
		cards.position = Vector2(MARGIN, CARDS_Y + shift)
		cards.size = Vector2(RIGHT - MARGIN + ShadowStyle.OFFSET, CARD_H + ShadowStyle.OFFSET)
		chrome.add_child(cards)
		var ck := HeatCopy.coins(heat)
		var coins := ShadowPanel.new(GOLD, 0.0, 0.22, 22.0)
		coins.name = "Coins"
		coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		coins.custom_minimum_size = Vector2(0, CARD_H + ShadowStyle.OFFSET)
		var cr := _hbox(18)
		cr.alignment = BoxContainer.ALIGNMENT_BEGIN
		var coin := PixelIcon.new("icon_coin", Vector2(48, 48), 3.0)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cr.add_child(coin)
		var cc := _vbox(12)
		cc.alignment = BoxContainer.ALIGNMENT_CENTER
		var big := _text(str(ck.get("big", "+0")), 32, CREAM, true)
		big.name = "CoinsBig"
		cc.add_child(big)
		cc.add_child(_text(str(ck.get("sub", ""))))
		if str(ck.get("sub2", "")) != "":
			var t2 := _text(str(ck["sub2"]))
			t2.name = "TicketsLine"
			cc.add_child(t2)
		cr.add_child(cc)
		coins.add_child(cr)
		cards.add_child(coins)
		var card := HeatCopy.drop(heat)
		if not card.is_empty():
			var dp := ShadowPanel.new(RetroTheme.c("teal"), 0.0, 0.22, 20.0)
			dp.name = "Drop"
			dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dp.custom_minimum_size = Vector2(0, CARD_H + ShadowStyle.OFFSET)
			var dr := _hbox(18)
			var art := ModeCards.art(card, Vector2(84, 112), 4.0)
			art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dr.add_child(art)
			var dc := _vbox(12)
			dc.alignment = BoxContainer.ALIGNMENT_CENTER
			dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dc.add_child(_text("CARD DROP"))
			var nm := _text(str(card.get("name", "")).to_upper().replace(" ", "\n"), 16, CREAM, true)
			nm.name = "DropName"
			nm.add_theme_constant_override("line_spacing", 6)
			dc.add_child(nm)
			dr.add_child(dc)
			dp.add_child(dr)
			cards.add_child(dp)
		var cont := ShadowCard.new(RetroTheme.c("orange"))
		cont.name = "ContinueSeason"
		cont.position = Vector2(MARGIN, CONT_Y + shift)
		cont.size = Vector2(RIGHT - MARGIN + ShadowStyle.OFFSET, CONT_H + ShadowStyle.OFFSET)
		var cm := _margin(0, 24)
		cont.add_child(cm)
		var crow := _hbox(16)
		cm.add_child(crow)
		var ccol := _vbox(14)
		ccol.alignment = BoxContainer.ALIGNMENT_CENTER
		ccol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ccol.add_child(_text("CONTINUE SEASON", 24, CREAM, true))
		var sub := _text(HeatCopy.continue_sub(doc, cfg))
		sub.name = "ContinueSub"
		ccol.add_child(sub)
		crow.add_child(ccol)
		var ch := _text(">", 32, CREAM, true)
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crow.add_child(ch)
		cont.pressed.connect(App.to_league_hub)
		chrome.add_child(cont)
	var home := ShadowCard.new(CREAM)
	home.name = "Home"
	home.position = Vector2(MARGIN, HOME_Y + shift)
	home.size = Vector2(RIGHT - MARGIN + ShadowStyle.OFFSET, HOME_H + ShadowStyle.OFFSET)
	home.text = "HOME"
	home.add_theme_font_override("font", UiFont.display())
	home.add_theme_font_size_override("font_size", UiFont.snap(16))
	RetroTheme.on_scene(home)
	home.pressed.connect(App.to_title)
	chrome.add_child(home)
	return chrome


## A box row: the label, then you / them in 150-px columns, the better in gold.
func _box_row(r: Dictionary) -> Control:
	var row := _hbox(0)
	row.name = "Row_" + str(r["l"]).replace(" ", "_")
	row.custom_minimum_size = Vector2(0, 50)
	var l := _text(str(r["l"]))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	for spec in [[str(r["a"]), r["hi"] == "a"], [str(r["b"]), r["hi"] == "b"]]:
		var c := _text(spec[0], 16, GOLD if bool(spec[1]) else CREAM, true)
		c.custom_minimum_size = Vector2(150, 0)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(c)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 50)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := RowRule.new()
	wrap.add_child(rule)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(row)
	return wrap


## The dashed rule along a box row's top (cream at 35 %, 2 px).
class RowRule extends Control:
	func _init() -> void:
		set_anchors_preset(Control.PRESET_TOP_WIDE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_dashed_line(Vector2(0, 1), Vector2(size.x, 1), Color(RetroTheme.SCENE_TEXT, 0.35), 2.0, 8.0)


# ---- helpers ---------------------------------------------------------------------


func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _margin(v: int, h: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v + int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m
