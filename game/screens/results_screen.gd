extends Node3D
## Time-trial results (design "Time Trial Results" 7a, 2026-10-24; docs/HOME.md
## → Results): the run's numbers over the LIVE court you just played on (the
## area's home-page pan under a half scrim), in the home's retro style. The
## area name is the page title top-left under a TIME TRIAL kicker; the score
## sits on the left with a NEW BEST chip or the gap to your best over it, and
## the gold tickets box beside it on the same row — on arrival a stream of
## tickets arcs from the score into the box (TicketStream: one per two
## tickets, fifteen at most) and the count ticks up as each lands. The stat
## row sits plain under the score (MAKES · SWISHES · STREAK · BONUS, ICED
## when it happened), the TOP 5 board shows this run's row in orange — or
## the run as a sixth row under a break when it is lower — and RUN IT BACK
## and HOME share one row. Copy from ResultsCopy (pure); the run from
## App.last_run.

const MARGIN := 36.0
const RIGHT := 720.0 - 42.0
const SCRIM_ALPHA := 0.5
const HEAD_POS := Vector2(36, 48)
const SCORE_POS := Vector2(92, 190)
const TICKETS_RECT := Rect2(720 - 42 - 240, 212, 240, 124)
const STATS_Y := 446.0
const STATS_X := Vector2(56, 720 - 62)
const BOARD_Y := 556.0
const BOARD_W := 642.0
const ROW_H := 64.0
const BUTTONS_Y := 1110.0
const BUTTON_H := 120.0
const HOME_W := 200.0
## The stream (design 7a): from the score into the box, after this long.
const STREAM_START := 0.45
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
	_start_stream.call_deferred()


## The tickets stream, once the chrome has laid out: from the score's centre
## into the box's icon; the box counts up as the flyers land.
var _stream: TicketStream
var _box: TicketBox
var _score_label: Label


func _start_stream() -> void:
	if _box == null or _stream == null:
		return
	var tk := int(_stream.tickets)
	if tk <= 0:
		return
	_box.set_count(0)
	var from := _score_label.get_global_rect().get_center() if _score_label != null else Vector2(150, 320)
	_stream.count_changed.connect(func(n: int) -> void:
		_box.set_count(n)
		_box.bump()
	)
	_stream.play(from, _box.icon_center(), tk, STREAM_START)


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
	_court.net_set = App.net_for_mode(mode)
	add_child(_court)
	_court.led.set_text("HOOP SHOOT", _court.led.accent_color)
	_spec = TitlePan.spec_of(arena)
	UiLayout.frame_camera(_cam, float(_spec["fov"]))
	var p := TitlePan.pose(_spec, 0.0)
	_cam.position = p["pos"]
	_cam.look_at(p["look"])


# ---- the chrome ------------------------------------------------------------------


## Everything over the court, as one Control (also built off-tree by tests).
func build_chrome(run: Dictionary, is_best: bool) -> Control:
	var chrome := Control.new()
	chrome.name = "Chrome"
	UiLayout.full_rect(chrome)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(RetroTheme.SCENE_OUTLINE, SCRIM_ALPHA)
	UiLayout.full_rect(scrim)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(scrim)
	var location := str(run.get("location", "cage"))
	var top := SaveService.top_scores(RanksCopy.BOARD_SIZE, location)

	# The title block: the TIME TRIAL kicker, the area name big with the dithered shadow.
	var head := _vbox(16)
	head.name = "Head"
	head.position = HEAD_POS
	chrome.add_child(head)
	var kicker := _hbox(12)
	var star := PixelIcon.new("icon_star", Vector2(22, 22))
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kicker.add_child(star)
	var kl := _text(ResultsCopy.KICKER, 18)
	kl.name = "Kicker"
	kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kicker.add_child(kl)
	head.add_child(kicker)
	var title := _text(ResultsCopy.title(run), 36, CREAM, true)
	title.name = "Title"
	RetroTheme.dithered(title, Vector2(6, 6))
	head.add_child(title)

	# The score block: NEW BEST or the gap, then the score.
	var score_col := _vbox(18)
	score_col.name = "ScoreBlock"
	score_col.position = SCORE_POS
	chrome.add_child(score_col)
	if is_best:
		var chip := ShadowPanel.new(GOLD, 0.0, 0.35, 14.0)
		chip.name = "NewBest"
		chip.custom_minimum_size = Vector2(0, 42 + ShadowStyle.OFFSET)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var nb := _text("NEW BEST", 16, CREAM, true)
		nb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(nb)
		score_col.add_child(chip)
	else:
		var best := int(top[0].get("score", 0)) if not top.is_empty() else int(run.get("score", 0))
		var bl := _text(ResultsCopy.best_line(best, int(run.get("score", 0))), 18)
		bl.name = "BestLine"
		bl.custom_minimum_size = Vector2(0, 42)
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_col.add_child(bl)
	var score := _text(str(int(run.get("score", 0))), 96, GOLD if is_best else CREAM, true)
	score.name = "Score"
	RetroTheme.dithered(score, Vector2(7, 7))
	score_col.add_child(score)
	_score_label = score

	# The tickets box beside the score (dim with nothing earned; the stream lands in it).
	var tk := ResultsCopy.tickets(run, is_best)
	_box = TicketBox.new(TICKETS_RECT.size.y, 64.0, 32, 14, 20.0, 18.0, 52.0, 0.0, TICKETS_RECT.size.x)
	_box.position = TICKETS_RECT.position
	_box.size = TICKETS_RECT.size + Vector2.ONE * ShadowStyle.OFFSET
	_box.set_count(int(tk["n"]))
	_box.set_sub(str(tk["sub"]))
	if bool(tk["none"]):
		_box.modulate.a = 0.5
	chrome.add_child(_box)

	# The stat row.
	var stats := _hbox(0)
	stats.name = "Stats"
	stats.position = Vector2(STATS_X.x, STATS_Y)
	stats.size = Vector2(STATS_X.y - STATS_X.x, 0)
	chrome.add_child(stats)
	for k in ResultsCopy.tiles(run):
		var col := _vbox(14)
		col.name = "Stat_" + str(k["l"])
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := _text(str(k["v"]), 26, CREAM, true)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(v)
		var l := _text(str(k["l"]), 17)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		stats.add_child(col)

	# The TOP 5 board, this run as a sixth row under a break when it is lower.
	var board := ShadowPanel.new(CREAM, 14.0, 0.14, 26.0)
	board.name = "Board"
	board.position = Vector2(MARGIN, BOARD_Y)
	board.size = Vector2(BOARD_W + ShadowStyle.OFFSET, 0)
	chrome.add_child(board)
	var bcol := _vbox(0)
	board.add_child(bcol)
	var bh := _hbox(0)
	bh.custom_minimum_size = Vector2(0, 48)
	var bt := _text("TOP %d" % ResultsCopy.BOARD_SIZE, 20, CREAM, true)
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bh.add_child(bt)
	var bn := _text(ResultsCopy.title(run), 18)
	bn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bh.add_child(bn)
	bcol.add_child(bh)
	var rows := ResultsCopy.board_rows(top, str(run.get("id", "")))
	for r in rows["top"]:
		bcol.add_child(_board_row(r))
	for r in rows["out"]:
		var gap := Control.new()
		gap.name = "Break"
		gap.custom_minimum_size = Vector2(0, 14)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.add_child(RowRule.new())
		bcol.add_child(gap)
		bcol.add_child(_board_row(r))

	# RUN IT BACK and HOME on one row.
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
	var home := ShadowCard.new(CREAM)
	home.name = "Home"
	home.custom_minimum_size = Vector2(HOME_W + ShadowStyle.OFFSET, BUTTON_H + ShadowStyle.OFFSET)
	home.text = "HOME"
	home.add_theme_font_override("font", UiFont.display())
	home.add_theme_font_size_override("font_size", UiFont.snap(22))
	RetroTheme.on_scene(home)
	home.pressed.connect(App.to_title)
	buttons.add_child(home)

	# The stream, over everything.
	_stream = TicketStream.new()
	_stream.name = "Stream"
	_stream.tickets = int(tk["n"])
	chrome.add_child(_stream)
	return chrome


## A board row (design 7a): grid 64 / fill / 112 / 120, 64 tall, a dashed rule
## on top, this run's in orange with THIS RUN beside its points.
func _board_row(r: Dictionary) -> Control:
	var row := _hbox(0)
	row.name = "Row_" + str(r["n"])
	row.custom_minimum_size = Vector2(0, ROW_H)
	var n := _text(str(r["n"]), 22, CREAM, true)
	n.custom_minimum_size = Vector2(64, 0)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(n)
	var mid := _hbox(14)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pts := _text(str(r["pts"]), 22, CREAM, true)
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mid.add_child(pts)
	if bool(r["mine"]):
		var tag := _text("THIS RUN", 18, HI)
		tag.name = "ThisRun"
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mid.add_child(tag)
	row.add_child(mid)
	for spec in [["%s SW" % r["sw"], 112], ["%s STK" % r["st"], 120]]:
		var c := _text(spec[0], 20)
		c.custom_minimum_size = Vector2(spec[1], 0)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(c)
	var wrap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(RetroTheme.c("orange"), 0.35) if bool(r["mine"]) else Color.TRANSPARENT
	sb.expand_margin_left = 14
	sb.expand_margin_right = 14
	wrap.add_theme_stylebox_override("panel", sb)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(RowRule.new())
	wrap.add_child(row)
	return wrap


## The dashed rule along a board row's top (cream at 30 %, 2 px, over the band).
class RowRule extends Control:
	func _init() -> void:
		set_anchors_preset(Control.PRESET_TOP_WIDE)
		offset_left = -14
		offset_right = 14
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
	UiLayout.full_rect(m)
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v + int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m
