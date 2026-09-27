extends Node3D
## Time-trial results (design "Time Trial Results", docs/HOME.md → Results):
## the run's numbers over the LIVE court you just played on (the area's
## home-page pan under a half scrim), in the home's retro style. Top to
## bottom: `★ ARCADE CAGE · TIME TRIAL`, a NEW BEST gold chip or the gap to
## your best, the score big with a dithered shadow (gold when best), the
## stat tiles (MAKES · SWISHES · STREAK · BONUS, ICED when it happened), the
## top-ten board on a see-through panel with this run's row in orange, then
## RUN IT BACK beside the tickets card (when tickets were earned) and HOME.
## Copy comes from ResultsCopy (pure); the run from App.last_run.

const MARGIN := 36.0
const RIGHT := 720.0 - 42.0
const SCRIM_ALPHA := 0.5
const HEAD_Y := 72.0
const TILES_Y := 362.0
const TILE_H := 92.0
const BOARD_Y := 484.0
const BOARD_W := 642.0
const ROW_H := 44.0
const BUTTONS_Y := 1030.0
const BUTTON_H := 120.0
const TICKETS_W := 196.0
const HOME_Y := 1172.0
const HOME_H := 60.0
const CREAM := RetroTheme.SCENE_TEXT
const HI := Color("#FFCE8A")
const GOLD := Color("#F0B84A")

var _t := 0.0
var _spec: Dictionary = {}
var _court: CourtGeometry
var _cam: Camera3D


func _ready() -> void:
	var run: Dictionary = App.last_run
	_build_court(str(run.get("location", "cage")))
	var ui := CanvasLayer.new()
	ui.name = "Ui"
	ui.layer = 10
	add_child(ui)
	ui.add_child(build_chrome(run, App.last_run_was_best))


func _process(dt: float) -> void:
	_t += dt
	if _court != null:
		var p := TitlePan.pose(_spec, _t)
		_cam.position = p["pos"]
		_cam.look_at(p["look"])
		_court.step_rim(dt)


# ---- the court behind (the home page's recipe) -----------------------------------


func _build_court(location: String) -> void:
	var arena := CosmeticLibrary.get_arena(location)
	if arena == null:
		arena = CosmeticLibrary.starter_arena()
	var mode := App.next_mode if App.MODES.has(App.next_mode) else "trial"
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
func build_chrome(run: Dictionary, is_best: bool) -> Control:
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
	var location := str(run.get("location", "cage"))
	var top := SaveService.top_scores(ResultsCopy.BOARD_SIZE, location)

	# Header: the area line, NEW BEST or the gap, the score.
	var head := _vbox(22)
	head.name = "Head"
	head.position = Vector2(MARGIN, HEAD_Y)
	head.size = Vector2(RIGHT - MARGIN, 0)
	head.alignment = BoxContainer.ALIGNMENT_BEGIN
	chrome.add_child(head)
	var area := _hbox(12)
	area.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(area)
	var star := PixelIcon.new("icon_star", Vector2(18, 18))
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	area.add_child(star)
	var title := _text(ResultsCopy.title(run))
	title.name = "Title"
	area.add_child(title)
	if is_best:
		var chip := ShadowPanel.new(GOLD, 0.0, 0.35, 14.0)
		chip.name = "NewBest"
		chip.custom_minimum_size = Vector2(0, 40 + ShadowStyle.OFFSET)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var nb := _text("NEW BEST", 16, CREAM, true)
		nb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(nb)
		head.add_child(chip)
	else:
		var best := int(top[0].get("score", 0)) if not top.is_empty() else int(run.get("score", 0))
		var bl := _text(ResultsCopy.best_line(best, int(run.get("score", 0))))
		bl.name = "BestLine"
		bl.custom_minimum_size = Vector2(0, 40)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(bl)
	var score_col := _vbox(16)
	head.add_child(score_col)
	var sl := _text("SCORE")
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_col.add_child(sl)
	var score := _text(str(int(run.get("score", 0))), 96, GOLD if is_best else CREAM, true)
	score.name = "Score"
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetroTheme.dithered(score)
	score_col.add_child(score)

	# The stat tiles.
	var tiles := _hbox(18 - int(ShadowStyle.OFFSET))
	tiles.name = "Tiles"
	tiles.position = Vector2(MARGIN, TILES_Y)
	tiles.size = Vector2(RIGHT - MARGIN + ShadowStyle.OFFSET, TILE_H + ShadowStyle.OFFSET)
	chrome.add_child(tiles)
	for k in ResultsCopy.tiles(run):
		var tile := ShadowPanel.new(CREAM, 0.0, 0.18, 0.0)
		tile.name = "Tile_" + str(k["l"])
		tile.custom_minimum_size = Vector2(0, TILE_H + ShadowStyle.OFFSET)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := _vbox(12)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var v := _text(str(k["v"]), 16, CREAM, true)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(v)
		var l := _text(str(k["l"]))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		tile.add_child(col)
		tiles.add_child(tile)

	# The board.
	var board := ShadowPanel.new(CREAM, 12.0, 0.14, 22.0)
	board.name = "Board"
	board.position = Vector2(MARGIN, BOARD_Y)
	board.size = Vector2(BOARD_W + ShadowStyle.OFFSET, 0)
	chrome.add_child(board)
	var bcol := _vbox(0)
	board.add_child(bcol)
	var bh := _hbox(0)
	bh.custom_minimum_size = Vector2(0, 40)
	var bt := _text("LEADERBOARD", 16, CREAM, true)
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bh.add_child(bt)
	var bn := _text(ResultsCopy.board_name(location))
	bn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bh.add_child(bn)
	bcol.add_child(bh)
	for r in ResultsCopy.board(top, str(run.get("id", ""))):
		bcol.add_child(_board_row(r))

	# RUN IT BACK beside the tickets card, then HOME.
	var buttons := _hbox(26 - int(ShadowStyle.OFFSET))
	buttons.name = "Buttons"
	buttons.position = Vector2(MARGIN, BUTTONS_Y)
	buttons.size = Vector2(RIGHT - MARGIN + ShadowStyle.OFFSET, BUTTON_H + ShadowStyle.OFFSET)
	chrome.add_child(buttons)
	var again := ShadowCard.new(RetroTheme.c("orange"))
	again.name = "RunItBack"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.custom_minimum_size = Vector2(0, BUTTON_H + ShadowStyle.OFFSET)
	var am := _margin(0, 24)
	again.add_child(am)
	var ar := _hbox(16)
	am.add_child(ar)
	var ac := _vbox(14)
	ac.alignment = BoxContainer.ALIGNMENT_CENTER
	ac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ac.add_child(_text("RUN IT BACK", 24, CREAM, true))
	ac.add_child(_text(ResultsCopy.run_sub(location)))
	ar.add_child(ac)
	var ch := _text(">", 32, CREAM, true)
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ar.add_child(ch)
	again.pressed.connect(func() -> void: App.start_mode(App.next_mode))
	buttons.add_child(again)
	var tk := ResultsCopy.tickets(run, is_best)
	if not tk.is_empty():
		var card := ShadowPanel.new(GOLD, 0.0, 0.22, 18.0)
		card.name = "Tickets"
		card.custom_minimum_size = Vector2(TICKETS_W + ShadowStyle.OFFSET, BUTTON_H + ShadowStyle.OFFSET)
		var tc := _vbox(12)
		tc.alignment = BoxContainer.ALIGNMENT_CENTER
		var big := _text(str(tk["big"]), 24, CREAM, true)
		big.name = "TicketsBig"
		tc.add_child(big)
		var sub := _text(str(tk["sub"]))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_constant_override("line_spacing", 5)
		tc.add_child(sub)
		card.add_child(tc)
		buttons.add_child(card)
	var home := ShadowCard.new(CREAM)
	home.name = "Home"
	home.position = Vector2(MARGIN, HOME_Y)
	home.size = Vector2(RIGHT - MARGIN + ShadowStyle.OFFSET, HOME_H + ShadowStyle.OFFSET)
	home.text = "HOME"
	home.add_theme_font_override("font", UiFont.display())
	home.add_theme_font_size_override("font_size", UiFont.snap(16))
	RetroTheme.on_scene(home)
	home.pressed.connect(App.to_title)
	chrome.add_child(home)
	return chrome


## A board row: grid 52 / fill / 96 / 96, a dashed rule on top, this run's in orange.
func _board_row(r: Dictionary) -> Control:
	var row := _hbox(0)
	row.name = "Row_" + str(r["n"])
	row.custom_minimum_size = Vector2(0, ROW_H)
	var n := _text(str(r["n"]), 16, CREAM, true)
	n.custom_minimum_size = Vector2(52, 0)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(n)
	var mid := _hbox(12)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pts := _text(str(r["pts"]), 16, CREAM, true)
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mid.add_child(pts)
	if bool(r["mine"]):
		var tag := _text("THIS RUN", 16, HI)
		tag.name = "ThisRun"
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mid.add_child(tag)
	row.add_child(mid)
	for spec in [["%s SW" % r["sw"], 96], ["%s STK" % r["st"], 96]]:
		var c := _text(spec[0])
		c.custom_minimum_size = Vector2(spec[1], 0)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(c)
	var wrap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(RetroTheme.c("orange"), 0.35) if bool(r["mine"]) else Color.TRANSPARENT
	sb.expand_margin_left = 12
	sb.expand_margin_right = 12
	wrap.add_theme_stylebox_override("panel", sb)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(RowRule.new())
	wrap.add_child(row)
	return wrap


## The dashed rule along a board row's top (cream at 30 %, 2 px, over the band).
class RowRule extends Control:
	func _init() -> void:
		set_anchors_preset(Control.PRESET_TOP_WIDE)
		offset_left = -12
		offset_right = 12
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_dashed_line(Vector2(0, 1), Vector2(size.x, 1), Color(RetroTheme.SCENE_TEXT, 0.3), 2.0, 8.0)


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
