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
## buttons work. `resumed`, `quit`, `ball_changed`, `net_changed` and
## `hud_side_changed` are the screen's to wire (the screen swaps the live
## pool / court, moves its music note).
##
## 2026-10-27 update of 43a: an info row under PAUSED (your score, theirs
## and the time left in a match; score, time left and your best in a trial)
## instead of the wide QUIT bar; QUIT is the small square left of RESUME
## (two taps: SURE? in orange with TAP AGAIN + what it costs over it); a HUD
## SIDE row (LEFT / RIGHT, toasts + music note) under the tiles; RESUME
## carries no sub-line.
##
## Later on 2026-10-27: HUD SIDE and SOUND share that row, half width each,
## and each opens a small menu ABOVE it like the tiles' popovers: HUD SIDE
## picks LEFT / RIGHT and closes; SOUND turns MUSIC and SOUND FX on or off
## (App.set_music_sound / set_sfx_sound, gold = on) and stays open, the row
## summing it up (ALL ON, MUSIC ONLY, FX ONLY, ALL OFF).

signal resumed
signal quit
signal ball_changed(id: String)
signal net_changed(id: String)
signal hud_side_changed(side: String)

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
const INFO_Y := 282.0
const INFO_H := 108.0
const SEP_W := 64.0
const OPTIONS_Y := 416.0
const HUD_ROW_Y := 690.0
const HUD_ROW_H := 88.0
const ROW2_GAP := 20.0
const POP2_BOTTOM := 604.0   # the small menu's foot, from the frame's bottom
const POP2_NOTCH := {"hud": 138.0, "sound": 466.0}   # its notch's left, from LEFT
const QUIT_SIZE := 150.0
const QUIT_BOTTOM := 60.0
const WARN := Color("#FFB08A")
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
var _quit_sub: Label        # the TAP AGAIN warning over the square
var _quit_armed_at := -1.0
var _info_row: HBoxContainer
var _rows2: Dictionary = {}   # "hud" / "sound" → {card, value}
var _pop_rows: Dictionary = {}   # the open small menu's rows: key → {card, tag}
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
	# The info row: where things stand (filled by open()).
	_info_row = HBoxContainer.new()
	_info_row.name = "Info"
	_info_row.position = Vector2(LEFT, INFO_Y)
	_info_row.size = Vector2(COL_W, INFO_H)
	_info_row.add_theme_constant_override("separation", 8)
	_info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info_row)
	# QUIT: the small square left of RESUME (two taps), the warning over it.
	_quit = ShadowCard.new(CREAM)
	_quit.name = "Quit"
	_quit.position = Vector2(LEFT, 1280.0 - QUIT_BOTTOM - QUIT_SIZE)
	_quit.size = Vector2(QUIT_SIZE + ShadowStyle.OFFSET, QUIT_SIZE + ShadowStyle.OFFSET)
	_quit.custom_minimum_size = _quit.size
	add_child(_quit)
	var qcol := VBoxContainer.new()
	qcol.alignment = BoxContainer.ALIGNMENT_CENTER
	qcol.add_theme_constant_override("separation", 14)
	qcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qcol.position = Vector2(0, 0)
	qcol.size = Vector2(QUIT_SIZE, QUIT_SIZE)
	_quit.add_child(qcol)
	var qmark := _text("<", 40, CREAM, true)
	qmark.name = "QuitMark"
	qmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qcol.add_child(qmark)
	_quit_top = _text("QUIT", 16, CREAM, true)
	_quit_top.name = "QuitTop"
	_quit_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qcol.add_child(_quit_top)
	# The warning wraps in the column left of RESUME.
	_quit_sub = _text("", 15, WARN)
	_quit_sub.name = "QuitSub"
	_quit_sub.add_theme_constant_override("line_spacing", 6)
	_quit_sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	var warn_w := 720.0 - RIGHT - RESUME_W - 16.0 - LEFT
	_quit_sub.position = Vector2(LEFT, 1280.0 - QUIT_BOTTOM - QUIT_SIZE - 14.0 - 96.0)
	_quit_sub.size = Vector2(warn_w, 96)
	_quit_sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_quit_sub.visible = false
	add_child(_quit_sub)
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
	# HUD SIDE and SOUND: half-width rows under the tiles, each opening a
	# small menu above it.
	var row_w := (COL_W - ROW2_GAP) / 2.0 - 6.0
	var r2 := [["hud", "HudSide", "HUD SIDE"], ["sound", "Sound", "SOUND"]]
	for i in r2.size():
		var k: String = r2[i][0]
		var r := _row2(str(r2[i][1]), str(r2[i][2]), row_w)
		(r["card"] as ShadowCard).position = Vector2(LEFT + i * (row_w + 6.0 + ROW2_GAP), HUD_ROW_Y)
		(r["card"] as ShadowCard).pressed.connect(_toggle_pop.bind(k))
		_rows2[k] = r
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
	resume.pressed.connect(func() -> void: resumed.emit())


## The info row from `stats`: {v, l, gold} cells, a {sep} is the VS. between.
func _fill_info(stats: Array) -> void:
	if _info_row == null:
		return
	for c in _info_row.get_children():
		_info_row.remove_child(c)
		c.queue_free()
	for m in stats:
		if bool(Dictionary(m).get("sep", false)):
			var sep := _text("VS.", 18, MUTED, true)
			sep.name = "InfoSep"
			sep.custom_minimum_size = Vector2(SEP_W, INFO_H - 30.0)
			sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			sep.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			_info_row.add_child(sep)
			continue
		var cell := VBoxContainer.new()
		cell.name = "Info_%s" % str(m.get("l", "")).to_lower().replace(" ", "_")
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 14)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(0, INFO_H)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := _text(str(m.get("v", "")), 40, GOLD if bool(m.get("gold", false)) else CREAM, true)
		v.name = "Value"
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.clip_text = true
		cell.add_child(v)
		var l := _text(str(m.get("l", "")), 16, MUTED)
		l.name = "Label"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		cell.add_child(l)
		_info_row.add_child(cell)


func info_texts() -> Array:
	var out := []
	if _info_row == null:
		return out
	for c in _info_row.get_children():
		if c is Label:
			out.push_back((c as Label).text)
		else:
			out.push_back("%s %s" % [(c.get_node("Value") as Label).text, (c.get_node("Label") as Label).text])
	return out


# ---- HUD SIDE -----------------------------------------------------------------------------


func hud_side_text() -> String:
	return str(App.hud_side).to_upper()


## The SOUND row's summary of the two settings switches.
func sound_text() -> String:
	if App.music_sound and App.sfx_sound:
		return "ALL ON"
	if App.music_sound:
		return "MUSIC ONLY"
	if App.sfx_sound:
		return "FX ONLY"
	return "ALL OFF"


## A half-width row: the label over the value, a gold caret on the right.
func _row2(name_: String, label: String, face_w: float) -> Dictionary:
	var card := ShadowCard.new(CREAM)
	card.name = name_
	card.size = Vector2(face_w + ShadowStyle.OFFSET, HUD_ROW_H + ShadowStyle.OFFSET)
	card.custom_minimum_size = card.size
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(18, 0)
	row.size = Vector2(face_w - 36, HUD_ROW_H)
	card.add_child(row)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(_text(label, 17, MUTED))
	var value := _text("", 14, CREAM, true)
	value.name = name_ + "Value"
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(value)
	var caret := Caret.new()
	caret.name = name_ + "Chevron"
	caret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caret)
	return {"card": card, "value": value}


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
	_fill_info(Array(info.get("stats", [])))
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
		_quit_top.text = "SURE?"
		_quit_sub.text = HudCopy.pause_quit_warning(str(_info.get("quit_note", "")))
		_quit_sub.visible = true
		_quit.color = ORANGE
		_quit.tint = 0.5
		_quit.queue_redraw()
		return
	_disarm()
	quit.emit()


func _disarm() -> void:
	_quit_armed_at = -1.0
	if _quit == null:
		return
	_quit_top.text = "QUIT"
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
		(t["card"] as ShadowCard).tint = 0.40 if on else 0.28
		(t["card"] as ShadowCard).queue_redraw()
	for k in _rows2:
		var r: Dictionary = _rows2[k]
		(r["value"] as Label).text = hud_side_text() if str(k) == "hud" else sound_text()
		var on2: bool = str(k) == _pop_kind
		(r["card"] as ShadowCard).color = GOLD if on2 else CREAM
		(r["card"] as ShadowCard).tint = 0.38 if on2 else 0.28
		(r["card"] as ShadowCard).queue_redraw()


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
	_pop_rows.clear()
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
	# The open tile (or row) stays bright above the shade, in gold.
	var opener: ShadowCard = _tiles[kind]["card"] if _tiles.has(kind) else _rows2[kind]["card"]
	move_child(opener, get_child_count() - 1)
	_refresh_values()
	if _rows2.has(kind):
		_open_pop2(kind)
		return
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
			row.tint = 0.40 if i == App.shot_help else 0.28
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
		c.tint = 0.40 if on else 0.28
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


## The small menu above HUD SIDE / SOUND (its notch under it points down at
## the row). HUD SIDE's rows pick and close; SOUND's flip a switch and stay,
## their ON / OFF tags and the row's summary following.
func _open_pop2(kind: String) -> void:
	var items: Array = [["left", "LEFT", "ON THE LEFT"], ["right", "RIGHT", "ON THE RIGHT"]] if kind == "hud" \
		else [["music", "MUSIC", "BACKGROUND TRACKS"], ["sfx", "SOUND FX", "SHOTS + CROWD"]]
	var h := 18.0 + 36.0 + ShadowStyle.OFFSET + 16.0 + items.size() * (64.0 + ShadowStyle.OFFSET) + (items.size() - 1) * 12.0 + 20.0 + ShadowStyle.OFFSET
	var top := 1280.0 - POP2_BOTTOM - h
	var panel := ShadowPanel.new(GOLD, 0.0, 0.0, 0.0)
	panel.name = "PopPanel"
	panel.position = Vector2(LEFT, top)
	panel.custom_minimum_size = Vector2(COL_W + ShadowStyle.OFFSET, h)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_pop.add_child(panel)
	var bg := ColorRect.new()
	bg.color = POP_BG
	bg.show_behind_parent = true
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)
	var notch := Notch.new(true)
	notch.position = Vector2(LEFT + float(POP2_NOTCH[kind]), 1280.0 - POP2_BOTTOM)
	_pop.add_child(notch)
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
	# HUD SIDE ........ TOASTS + MUSIC NOTE [X]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(head)
	head.add_child(_text("HUD SIDE" if kind == "hud" else "SOUND", 15, GOLD, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	head.add_child(_text("TOASTS + MUSIC NOTE" if kind == "hud" else "TAP TO TURN ON / OFF", 14, MUTED))
	var x := HomePage.button("X", CREAM, 14, 36.0)
	x.name = "PopClose"
	x.custom_minimum_size = Vector2(36 + ShadowStyle.OFFSET, 36 + ShadowStyle.OFFSET)
	x.pressed.connect(_close_pop)
	head.add_child(x)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(rows)
	for it in items:
		var key := str(it[0])
		var row := ShadowCard.new(CREAM)
		row.name = ("Hud_" if kind == "hud" else "Sound_") + key
		row.custom_minimum_size = Vector2(0, 64 + ShadowStyle.OFFSET)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.position = Vector2(18, 0)
		hb.size = Vector2(COL_W - 40 - 36 - ShadowStyle.OFFSET, 64)
		row.add_child(hb)
		var n := _text(str(it[1]), 15, CREAM, true)
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.size_flags_vertical = Control.SIZE_FILL
		hb.add_child(n)
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(sp2)
		var d := _text(str(it[2]), 14, MUTED)
		d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		d.size_flags_vertical = Control.SIZE_FILL
		hb.add_child(d)
		var tag := _text("", 14, GOLD, true)
		tag.name = "Tag"
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.size_flags_vertical = Control.SIZE_FILL
		hb.add_child(tag)
		row.pressed.connect(pick.bind(kind, key))
		rows.add_child(row)
		_pop_rows[key] = {"card": row, "tag": tag}
	_refresh_pop2()


## The small menu's rows as the settings stand: the active side / an ON
## switch gold, the SOUND tags ON / OFF; the row under it follows.
func _refresh_pop2() -> void:
	for key in _pop_rows:
		var on := false
		match str(key):
			"left", "right": on = str(App.hud_side) == str(key)
			"music": on = App.music_sound
			"sfx": on = App.sfx_sound
		var card := _pop_rows[key]["card"] as ShadowCard
		card.color = GOLD if on else CREAM
		card.tint = 0.38 if on else 0.28
		card.queue_redraw()
		var tag := _pop_rows[key]["tag"] as Label
		if str(key) == "music" or str(key) == "sfx":
			tag.text = "ON" if on else "OFF"
			tag.add_theme_color_override("font_color", GOLD if on else CREAM)
	_refresh_values()


## The notch over a popover pointing up at its tile, or (`down`) under the
## small menu pointing at its row.
class Notch extends Control:
	var _down := false

	func _init(down := false) -> void:
		_down = down
		size = Vector2(28, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if _down:
			draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(28, 0), Vector2(14, 14)]), GOLD)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(0, 14), Vector2(14, 0), Vector2(28, 14)]), GOLD)


## Pick from the open popover: equip it (the ball globally, the net on this
## court, shot help and HUD SIDE as settings) and close; a SOUND switch flips
## and the menu stays.
func pick(kind: String, value: String) -> void:
	match kind:
		"hud":
			if value != str(App.hud_side):
				App.set_hud_side(value)
				hud_side_changed.emit(value)
		"sound":
			if value == "music":
				App.set_music_sound(not App.music_sound)
			else:
				App.set_sfx_sound(not App.sfx_sound)
			_refresh_pop2()
			return
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
