class_name PauseMenu
extends CanvasLayer
## The pause menu every mode shares (design "Pause Menu" 43a, 2026-10-25):
## the dim over the frozen match, PAUSED with a line saying where you are,
## QUIT TO TITLE (two taps now, like DELETE ACCOUNT: the first arms it for
## QUIT_ARM_S with what quitting costs, the second quits), OPTIONS · TAP TO
## CHANGE over three tiles showing what you have on — SHOT HELP (its icon),
## BALL and NET (their thumbnails) — and the big orange RESUME with when the
## clock picks up. Tapping a tile opens a popover under it with every choice
## at once: the owned balls and nets as a scrolling grid of thumbnails, shot
## help as three rows; the current pick is gold, another one equips it
## (App.select / select_net — the ball is global, the net this court's,
## docs/LOCKER.md → NETS) and closes. The dim behind it, its X, or the tile
## again close it without a change; a tile with one owned option shows no
## caret and does not open. Keeps processing while the tree is paused so its
## buttons work. `resumed`, `quit`, `ball_changed` and `net_changed` are the
## screen's to wire (the screen swaps the live pool / court).

signal resumed
signal quit
signal ball_changed(id: String)
signal net_changed(id: String)

const DIM := Color("#1B1815", 0.78)
const POP_DIM := Color(14.0 / 255.0, 11.0 / 255.0, 9.0 / 255.0, 0.5)
const POP_BG := Color(27.0 / 255.0, 24.0 / 255.0, 21.0 / 255.0, 0.96)
const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")
const ORANGE := Color("#E8703A")
const MUTED := Color("#E6D9B8")
const HI := Color("#FFE45C")
const LEFT := 36.0
const RIGHT := 42.0
const COL_W := 720.0 - LEFT - RIGHT
const TITLE_Y := 150.0
const QUIT_Y := 290.0
const QUIT_H := 76.0
const OPTIONS_Y := 416.0
const TILES_Y := 456.0
const TILE_H := 210.0
const TILE_GAP := 20.0
const POP_Y := 694.0
const POP_GRID_H := 250.0
const GRID_COLS := 5
const RESUME_W := 428.0
const RESUME_H := 300.0
const RESUME_BOTTOM := 60.0
const QUIT_ARM_S := 4.0
const HELP_ICONS := ["icon_aim_off", "icon_aim_num", "icon_aim_arc"]
const HELP_SHORT := ["OFF", "NUMBERS", "NUM + ARC"]
const HELP_DESC := ["NO AIM HELP", "POWER + ANGLE", "POWER + ANGLE + PATH"]

var _area := "cage"
var _net_kind := "cotton"
var _info: Dictionary = {}
var _context: Label
var _quit: ShadowCard
var _quit_top: Label
var _quit_sub: Label
var _quit_armed_at := -1.0
var _resume_sub: Label
var _tiles: Dictionary = {}   # kind → {card, icon, value, caret}
var _pop_kind := ""
var _pop: Control
var _t := 0.0


func _init() -> void:
	name = "PauseUi"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	UiLayout.full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # no flicks through the menu
	add_child(dim)
	# PAUSED and where you are.
	var head := VBoxContainer.new()
	head.name = "Head"
	head.position = Vector2(LEFT, TITLE_Y)
	head.size = Vector2(COL_W, 110)
	head.add_theme_constant_override("separation", 22)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var title := _text("PAUSED", 64, GOLD, true)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetroTheme.dithered(title, Vector2(6, 6))
	head.add_child(title)
	_context = _text("", 18, MUTED)
	_context.name = "Context"
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_context)
	# QUIT TO TITLE (two taps).
	_quit = ShadowCard.new(CREAM)
	_quit.name = "Quit"
	_quit.position = Vector2(LEFT, QUIT_Y)
	_quit.size = Vector2(COL_W + ShadowStyle.OFFSET, QUIT_H + ShadowStyle.OFFSET)
	_quit.custom_minimum_size = _quit.size
	add_child(_quit)
	var qcol := VBoxContainer.new()
	qcol.alignment = BoxContainer.ALIGNMENT_CENTER
	qcol.add_theme_constant_override("separation", 10)
	qcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qcol.position = Vector2(26, 0)
	qcol.size = Vector2(COL_W - 52, QUIT_H)
	_quit.add_child(qcol)
	_quit_top = _text("QUIT TO TITLE", 17, CREAM, true)
	_quit_top.name = "QuitTop"
	qcol.add_child(_quit_top)
	_quit_sub = _text("", 14, CREAM)
	_quit_sub.name = "QuitSub"
	_quit_sub.visible = false
	qcol.add_child(_quit_sub)
	_quit.pressed.connect(_on_quit)
	# OPTIONS ———— TAP TO CHANGE
	var opt := HBoxContainer.new()
	opt.name = "OptionsHead"
	opt.position = Vector2(LEFT, OPTIONS_Y)
	opt.size = Vector2(COL_W, 20)
	opt.add_theme_constant_override("separation", 14)
	opt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(opt)
	opt.add_child(_text("OPTIONS", 15, CREAM, true))
	var rule := ColorRect.new()
	rule.color = Color(CREAM, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opt.add_child(rule)
	opt.add_child(_text("TAP TO CHANGE", 14, MUTED))
	# The three tiles.
	var tile_w := (COL_W - 2.0 * TILE_GAP) / 3.0
	var kinds := ["help", "ball", "net"]
	var names := {"help": "ShotHelp", "ball": "Ball", "net": "Net"}
	var labels := {"help": "SHOT HELP", "ball": "BALL", "net": "NET"}
	for i in kinds.size():
		var k: String = kinds[i]
		var t := _tile(str(names[k]), str(labels[k]), tile_w - ShadowStyle.OFFSET)
		t["card"].position = Vector2(LEFT + i * (tile_w + TILE_GAP), TILES_Y)
		(t["card"] as ShadowCard).pressed.connect(_toggle_pop.bind(k))
		_tiles[k] = t
	# RESUME, bottom right.
	var resume := ShadowCard.new(ORANGE)
	resume.name = "Resume"
	resume.position = Vector2(720.0 - RIGHT - RESUME_W, 1280.0 - RESUME_BOTTOM - RESUME_H)
	resume.size = Vector2(RESUME_W + ShadowStyle.OFFSET, RESUME_H + ShadowStyle.OFFSET)
	resume.custom_minimum_size = resume.size
	resume.clip_contents = true
	add_child(resume)
	var shine := PreMatchPage.Shine.new()
	shine.name = "Shine"
	shine.size = Vector2(RESUME_W, RESUME_H)
	resume.add_child(shine)
	var rcol := VBoxContainer.new()
	rcol.alignment = BoxContainer.ALIGNMENT_CENTER
	rcol.add_theme_constant_override("separation", 18)
	rcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rcol.position = Vector2(36, 0)
	rcol.size = Vector2(RESUME_W - 72, RESUME_H)
	resume.add_child(rcol)
	var rrow := HBoxContainer.new()
	rrow.alignment = BoxContainer.ALIGNMENT_CENTER
	rrow.add_theme_constant_override("separation", 18)
	rrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rcol.add_child(rrow)
	rrow.add_child(_text("RESUME", 40, CREAM, true))
	var rmark := _text(">", 32, CREAM, true)
	rmark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rrow.add_child(rmark)
	_resume_sub = _text("", 16, CREAM)
	_resume_sub.name = "ResumeSub"
	_resume_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resume_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resume_sub.add_theme_constant_override("line_spacing", 6)
	rcol.add_child(_resume_sub)
	resume.pressed.connect(func() -> void: resumed.emit())


## A tile: the label, the picture, the value with its caret.
func _tile(name_: String, label: String, face_w: float) -> Dictionary:
	var card := ShadowCard.new(CREAM)
	card.name = name_
	card.size = Vector2(face_w + ShadowStyle.OFFSET, TILE_H + ShadowStyle.OFFSET)
	card.custom_minimum_size = card.size
	add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2(12, 18)
	col.size = Vector2(face_w - 24, TILE_H - 34)
	card.add_child(col)
	var l := _text(label, 14, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	var icon := TextureRect.new()
	icon.name = name_ + "Icon"
	icon.custom_minimum_size = Vector2(84, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var value := _text("", 11, CREAM, true)
	value.name = name_ + "Value"
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value)
	var caret := Caret.new()
	caret.name = name_ + "Chevron"
	caret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caret)
	return {"card": card, "icon": icon, "value": value, "caret": caret, "face_w": face_w}


## The ▾ under a tile with choices (drawn: the pixel fonts have no ▾).
class Caret extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(12, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(12, 0), Vector2(6, 7)])
		draw_colored_polygon(PackedVector2Array([pts[0] + Vector2(2, 2), pts[1] + Vector2(2, 2), pts[2] + Vector2(2, 2)]), RetroTheme.SCENE_OUTLINE)
		draw_colored_polygon(pts, GOLD)


## `info` from the screen: {context, resume_sub, quit_note} (HudCopy.pause_*).
func open(info: Dictionary = {}) -> void:
	_area = str(App.mode_config(App.next_mode).get("location", "cage"))
	_net_kind = App.net_kind_for_mode(App.next_mode)
	_info = info.duplicate()
	if _context != null:
		_context.text = str(info.get("context", ""))
		_resume_sub.text = str(info.get("resume_sub", HudCopy.pause_resume_sub(-1.0)))
	_disarm()
	_close_pop()
	_refresh_values()
	visible = true


func close() -> void:
	_close_pop()
	_disarm()
	visible = false


func _process(dt: float) -> void:
	_t += dt
	if _quit_armed_at >= 0.0 and _t - _quit_armed_at > QUIT_ARM_S:
		_disarm()


# ---- QUIT (two taps) ----------------------------------------------------------------------


func _on_quit() -> void:
	if _quit_armed_at < 0.0:
		_quit_armed_at = _t
		_quit_top.text = "TAP AGAIN TO QUIT"
		var note := str(_info.get("quit_note", ""))
		_quit_sub.text = note
		_quit_sub.visible = note != ""
		_quit.color = ORANGE
		_quit.tint = 0.4
		_quit.queue_redraw()
		return
	_disarm()
	quit.emit()


func _disarm() -> void:
	_quit_armed_at = -1.0
	if _quit == null:
		return
	_quit_top.text = "QUIT TO TITLE"
	_quit_sub.visible = false
	_quit.color = CREAM
	_quit.tint = ShadowStyle.TINT
	_quit.queue_redraw()


func quit_armed() -> bool:
	return _quit_armed_at >= 0.0


# ---- the tiles ----------------------------------------------------------------------------


## The owned balls, in library order.
func _ball_ids() -> Array:
	var out: Array = []
	for b in CosmeticLibrary.balls():
		if App.owns("ball", b.id):
			out.push_back(b.id)
	return out


## The owned nets, in library order (any kind hangs on any court).
func _net_ids() -> Array:
	var out: Array = []
	for n in CosmeticLibrary.nets():
		if App.owns("net", n.id):
			out.push_back(n.id)
	return out


func _refresh_values() -> void:
	if _tiles.is_empty():
		return
	var help: Dictionary = _tiles["help"]
	(help["value"] as Label).text = str(HELP_SHORT[clampi(App.shot_help, 0, 2)])
	(help["icon"] as TextureRect).texture = PixelIcon.tex(str(HELP_ICONS[clampi(App.shot_help, 0, 2)]))
	var ball: Dictionary = _tiles["ball"]
	var bid := App.ball_set.id if App.ball_set != null else "classic"
	(ball["value"] as Label).text = str(App.ball_set.display_name).to_upper() if App.ball_set != null else ""
	(ball["icon"] as TextureRect).texture = _thumb("ball", bid)
	(ball["caret"] as Control).visible = _ball_ids().size() > 1
	var net: Dictionary = _tiles["net"]
	var ns := App.net_set_for(_area)
	(net["value"] as Label).text = str(ns.display_name).to_upper() if ns != null else ""
	(net["icon"] as TextureRect).texture = _thumb("net", ns.id if ns != null else "cotton")
	(net["caret"] as Control).visible = _net_ids().size() > 1
	for k in _tiles:
		var t: Dictionary = _tiles[k]
		var v := t["value"] as Label
		var room: float = float(t["face_w"]) - 24.0 - ((t["caret"] as Control).custom_minimum_size.x + 8.0 if (t["caret"] as Control).visible else 0.0)
		var w := UiFont.display().get_string_size(v.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(11)).x + 2.0 * RetroTheme.OUTLINE
		v.custom_minimum_size.x = minf(w, room)
		var on: bool = str(k) == _pop_kind
		(t["card"] as ShadowCard).color = GOLD if on else CREAM
		(t["card"] as ShadowCard).tint = 0.3 if on else 0.18
		(t["card"] as ShadowCard).queue_redraw()


static func _thumb(kind: String, id: String) -> Texture2D:
	var path := ("res://assets/textures/balls/thumbs/%s.png" % id) if kind == "ball" else NetSet.thumb_path(id)
	return load(path) if ResourceLoader.exists(path) else null


func shot_help_text() -> String:
	return HudCopy.shot_help_value(App.shot_help)


func ball_text() -> String:
	return (_tiles["ball"]["value"] as Label).text if _tiles.has("ball") else ""


func net_text() -> String:
	return (_tiles["net"]["value"] as Label).text if _tiles.has("net") else ""


# ---- the popover ------------------------------------------------------------------------


func _toggle_pop(kind: String) -> void:
	if _pop_kind == kind:
		_close_pop()
		return
	if kind == "ball" and _ball_ids().size() <= 1:
		return
	if kind == "net" and _net_ids().size() <= 1:
		return
	_open_pop(kind)


func pop_kind() -> String:
	return _pop_kind


func _close_pop() -> void:
	if _pop != null:
		_pop.queue_free()
		_pop = null
	_pop_kind = ""
	_refresh_values()


func _open_pop(kind: String) -> void:
	_close_pop()
	_pop_kind = kind
	_pop = Control.new()
	_pop.name = "Popover"
	UiLayout.full_rect(_pop)
	_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pop)
	# The dim behind it closes it.
	var shade := Button.new()
	shade.name = "PopDim"
	shade.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = POP_DIM
		shade.add_theme_stylebox_override(st, sb)
	shade.position = Vector2(-UiLayout.offset().x, -UiLayout.offset().y)
	shade.size = UiLayout.canvas()
	shade.pressed.connect(_close_pop)
	_pop.add_child(shade)
	# The open tile stays bright above the shade, in gold.
	var tile: ShadowCard = _tiles[kind]["card"]
	move_child(tile, get_child_count() - 1)
	_refresh_values()
	# The notch over the tile and the panel.
	var col := ["help", "ball", "net"].find(kind)
	var tile_w := (COL_W - 2.0 * TILE_GAP) / 3.0
	var notch := Notch.new()
	notch.position = Vector2(LEFT + col * (tile_w + TILE_GAP) + tile_w * 0.5 - 17.0, POP_Y - 14.0)
	_pop.add_child(notch)
	var panel := ShadowPanel.new(GOLD, 0.0, 0.0, 0.0)
	panel.name = "PopPanel"
	panel.position = Vector2(LEFT, POP_Y)
	panel.custom_minimum_size = Vector2(COL_W + ShadowStyle.OFFSET, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_pop.add_child(panel)
	var bg := ColorRect.new()
	bg.color = POP_BG
	bg.show_behind_parent = true   # the dark ground under the panel's gold dots
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_right", 20 + int(ShadowStyle.OFFSET))
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_bottom", 20 + int(ShadowStyle.OFFSET))
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(m)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(body)
	# BALL ........ 12 OWNED [X]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(head)
	head.add_child(_text({"help": "SHOT HELP", "ball": "BALL", "net": "NET"}[kind], 15, GOLD, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var note := ""
	match kind:
		"ball": note = "%d OWNED" % _ball_ids().size()
		"net": note = "%d OWNED · THIS COURT" % _net_ids().size()
		_: note = "WHAT SHOWS AS YOU AIM"
	head.add_child(_text(note, 14, MUTED))
	var x := HomePage.button("X", CREAM, 14, 36.0)
	x.name = "PopClose"
	x.custom_minimum_size = Vector2(36 + ShadowStyle.OFFSET, 36 + ShadowStyle.OFFSET)
	x.pressed.connect(_close_pop)
	head.add_child(x)
	if kind == "help":
		for i in 3:
			var row := ShadowCard.new(GOLD if i == App.shot_help else CREAM)
			row.name = "Help_%d" % i
			row.tint = 0.3 if i == App.shot_help else 0.18
			row.custom_minimum_size = Vector2(0, 64 + ShadowStyle.OFFSET)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 14)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.position = Vector2(18, 0)
			h.size = Vector2(COL_W - 40 - 36 - ShadowStyle.OFFSET, 64)
			row.add_child(h)
			var n := _text(str(App.SHOT_HELP_LABELS[i]), 15, CREAM, true)
			n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			n.size_flags_vertical = Control.SIZE_FILL
			h.add_child(n)
			var sp2 := Control.new()
			sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(sp2)
			var d := _text(str(HELP_DESC[i]), 14, MUTED)
			d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			d.size_flags_vertical = Control.SIZE_FILL
			h.add_child(d)
			row.pressed.connect(pick.bind("help", str(i)))
			body.add_child(row)
		return
	# The grid of thumbnails, scrolling past POP_GRID_H.
	var ids := _ball_ids() if kind == "ball" else _net_ids()
	var cur := (App.ball_set.id if App.ball_set != null else "") if kind == "ball" else (App.net_set_for(_area).id if App.net_set_for(_area) != null else "")
	var scroll := ScrollContainer.new()
	scroll.name = "PopScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "PopGrid"
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var cell := floorf((COL_W - 40.0 - 10.0 - 14.0 * (GRID_COLS - 1)) / GRID_COLS) - ShadowStyle.OFFSET
	for id in ids:
		var on := str(id) == cur
		var c := ShadowCard.new(GOLD if on else CREAM)
		c.name = "Opt_" + str(id)
		c.tint = 0.3 if on else 0.18
		c.custom_minimum_size = Vector2.ONE * (cell + ShadowStyle.OFFSET)
		var pic := TextureRect.new()
		pic.texture = _thumb(kind, str(id))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.position = Vector2.ONE * cell * 0.12
		pic.size = Vector2.ONE * cell * 0.76
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(pic)
		c.pressed.connect(pick.bind(kind, str(id)))
		grid.add_child(c)
	var rows := ceili(float(ids.size()) / GRID_COLS)
	scroll.custom_minimum_size = Vector2(0, minf(POP_GRID_H, rows * (cell + ShadowStyle.OFFSET) + (rows - 1) * 14.0 + 4.0))
	var sel := _text(_tiles[kind]["value"].text, 13, CREAM, true)
	sel.name = "PopSel"
	sel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sel)


## The notch over the popover, pointing up at its tile.
class Notch extends Control:
	func _init() -> void:
		size = Vector2(28, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(0, 14), Vector2(14, 0), Vector2(28, 14)]), GOLD)


## Pick from the open popover: equip it (the ball globally, the net on this
## court, shot help as a setting) and close.
func pick(kind: String, value: String) -> void:
	match kind:
		"help":
			App.set_shot_help(int(value))
		"ball":
			var was := App.ball_set.id if App.ball_set != null else ""
			if value != was and App.select("ball", value):
				ball_changed.emit(value)
		"net":
			var cur := App.net_set_for(_area)
			if (cur == null or value != cur.id) and App.select_net(_area, value):
				net_changed.emit(value)
	_close_pop()


func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
