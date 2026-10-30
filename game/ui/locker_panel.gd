class_name LockerPanel
extends HomePage
## The locker page (the top-left ball icon), docs/LOCKER.md: the collection
## (design "Store and Locker" 31a / 31b, Ross 2026-10-30). The head: LOCKER
## beside the big ticket panel, then PLAY PEGGY across the page (it shines
## while a drop is affordable) opening PEGGY's page. Two tabs, BALLS and
## NETS, each with an OWNED / ALL sub-tab and the count beside it, and the
## collection grouped in three-wide grids: balls by rarity (COMMON · LVL 1 …
## LEGEND · LVL 5, each with its owned/total), nets by kind (COTTON, CHAIN).
## ALL adds the rest as greyed ???? tiles. A ball: tap once to arm it
## (orange, EQUIP?; it disarms after ARM_S), again to use it everywhere; the
## one in use is gold. A net: dots along its top show which of your courts it
## hangs on (gold where it does), and a tap opens HANG IT ON under its row —
## one button per court you have reached, HANGING or TAP TO HANG; each court
## holds one net, so hanging it takes down the one there. `< BACK` at the
## foot. Opening the locker clears App.unseen_prizes(), which the title's
## locker icon badges.

signal peggy_requested

const TABS := ["BALLS", "NETS"]
const VIEWS := ["OWNED", "ALL"]
const KINDS := ["cotton", "chain"]
const SKIN_REGION := Rect2(64, 64, 128, 128)
const TILE_H := 200.0
const COLS := 3
const GAP := 12.0
const ARM_S := 4.0
const MUTED := Color("#D9D9D9")
const LOCKED_TEXT := Color("#8C8C8C")
const LOCKED_FILL := Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.6)
const DOT_OFF := Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.45)
const HANG_GROUND := Color("#1B1815")
const TIER_COLOR := {
	"common": Color("#8FC1E3"), "rare": Color("#3F8C7A"), "epic": Color("#E0457B"), "legend": Color("#F0B84A"),
}

var _tabs: HBoxContainer
var _content: Control
var _peggy: ShadowCard
var _shine: Control
var _tab := "BALLS"
var _ball_view := "OWNED"
var _net_view := "OWNED"
var _scroll_box: ScrollContainer
var _list: VBoxContainer
var _armed := ""
var _arm_timer: Tween
var _open_net := ""
static var _glows := {}


func _row_gap() -> int:
	return 28


func _flush_top() -> bool:
	return true


func _build() -> void:
	App.mark_prizes_seen()   # the collection is open: every won prize is seen
	# LOCKER · [tickets], PLAY PEGGY under them (16 more before the tabs).
	var top := MarginContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("margin_bottom", 16)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(top)
	var top_col := VBoxContainer.new()
	top_col.add_theme_constant_override("separation", 20)
	top_col.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(top_col)
	var h := HBoxContainer.new()
	h.name = "Head"
	h.add_theme_constant_override("separation", 28)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	top_col.add_child(h)
	var title := RetroTheme.display("LOCKER", 52, CREAM)
	title.name = "Title"
	RetroTheme.on_scene(title)
	RetroTheme.dithered(title, Vector2(4, 4))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title)
	h.add_child(ticket_panel())
	top_col.add_child(_peggy_button())
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 10)
	body.add_child(_tabs)
	_content = Control.new()
	_content.name = "Content"
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(_content)
	body.add_child(back_button(30, 32, 18))
	_fill()


## PLAY PEGGY · WIN BALLS + NETS · 300 TICKETS  >  — the way to the machine.
func _peggy_button() -> ShadowCard:
	_peggy = ShadowCard.new(RetroTheme.LIGHT["orange"])
	_peggy.name = "Peggy"
	_peggy.custom_minimum_size = Vector2(0, TALL_H + ShadowStyle.OFFSET)
	_peggy.pressed.connect(func() -> void: peggy_requested.emit())
	_shine = PreMatchPage.Shine.new(2.6, 200.0, 0.6)
	_shine.name = "Shine"
	_shine.position = Vector2.ZERO
	_peggy.add_child(_shine)
	_peggy.resized.connect(func() -> void:
		_shine.size = _peggy.size - Vector2.ONE * ShadowStyle.OFFSET)
	var row := HBoxContainer.new()
	row.name = "Row"
	UiLayout.full_rect(row)
	row.offset_left = 22
	row.offset_right = -22 - ShadowStyle.OFFSET
	row.offset_bottom = -ShadowStyle.OFFSET
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_peggy.add_child(row)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	row.add_child(col)
	var big := words("PLAY PEGGY", 26, true)
	big.name = "Word"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(big)
	var sub := words("WIN BALLS + NETS · %d TICKETS" % PeggyPrizes.DROP_COST, 15)
	sub.name = "Sub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(sub)
	var chev := words(">", 28, true)
	chev.name = "Chevron"
	chev.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chev.size_flags_vertical = Control.SIZE_FILL
	row.add_child(chev)
	return _peggy


## Rebuild the tabs and the current tab's content. Old nodes are removed at
## once and freed later: _fill runs from the tabs' own pressed signals, and
## freeing the emitter mid-signal left the page half built. `keep_scroll`
## puts the list back where it was (a tap on a tile restyles in place).
func _fill(keep_scroll := false) -> void:
	set_tickets()
	_shine.visible = App.tickets() >= PeggyPrizes.DROP_COST
	var was := _scroll_box.scroll_vertical if keep_scroll and _scroll_box != null else 0
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for tab in TABS:
		var label := "%s %d" % [tab, App.owned_count("ball" if tab == "BALLS" else "net")]
		var b := button(label, RetroTheme.LIGHT["gold"] if tab == _tab else CREAM, 16, 54)
		b.name = "Tab_" + tab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: String = tab
		b.pressed.connect(func() -> void: show_tab.call_deferred(t))
		_tabs.add_child(b)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_list = null
	_scroll_box = null
	if _tab == "NETS":
		_build_nets()
	else:
		_build_balls()
	if was > 0:
		_restore_scroll.call_deferred(_scroll_box, was)


func _restore_scroll(box: ScrollContainer, v: int) -> void:
	if is_instance_valid(box):
		box.scroll_vertical = v


func show_tab(tab: String) -> void:
	if not TABS.has(tab):
		return
	_tab = tab
	_disarm(false)
	_open_net = ""
	App.mark_prizes_seen()
	_fill()


func tab() -> String:
	return _tab


## The tab's OWNED / ALL sub-tab.
func show_view(view: String) -> void:
	if not VIEWS.has(view):
		return
	if _tab == "NETS":
		_net_view = view
	else:
		_ball_view = view
	_fill()


func view() -> String:
	return _net_view if _tab == "NETS" else _ball_view


# ---- the pieces ----------------------------------------------------------------


func _scroll() -> VBoxContainer:
	_scroll_box = ScrollContainer.new()
	_scroll_box.name = _tab.capitalize() + "Tab"
	UiLayout.full_rect(_scroll_box)
	_scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(_scroll_box)
	_list = VBoxContainer.new()
	_list.name = "Items"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 20)
	_scroll_box.add_child(_list)
	return _list


## OWNED · ALL ............ n OWNED (or n / total OWNED).
func _view_row(current: String, owned: int, total: int) -> void:
	var wrap := MarginContainer.new()
	wrap.name = "Views"
	wrap.add_theme_constant_override("margin_bottom", 14)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	_list.add_child(wrap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(row)
	for v in VIEWS:
		var b := button(v, RetroTheme.LIGHT["gold"] if v == current else CREAM, 16, 46)
		b.name = "View_" + str(v)
		b.custom_minimum_size.x = _text_w(str(v), 16) + 40.0 + ShadowStyle.OFFSET
		var vv: String = v
		b.pressed.connect(func() -> void: show_view.call_deferred(vv))
		row.add_child(b)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var meta := words("%d OWNED" % owned if current == "OWNED" else "%d / %d OWNED" % [owned, total], 16)
	meta.name = "Meta"
	meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(meta)


static func _text_w(text: String, px: int) -> float:
	return UiFont.display().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(px)).x


## A group: its head (the rarity swatch and LVL for balls), the rule, the
## count, then the tiles three to a row; `panel` goes in under the row
## holding tile `panel_at`.
func _group(id: String, title: String, count: String, tiles: Array, swatch := Color.TRANSPARENT,
		lvl := 0, panel: Control = null, panel_at := -1) -> void:
	var wrap := MarginContainer.new()
	wrap.name = "Group_" + id
	wrap.add_theme_constant_override("margin_top", 8)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	_list.add_child(wrap)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(col)
	var head_ := HBoxContainer.new()
	head_.name = "Head"
	head_.add_theme_constant_override("separation", 12)
	head_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head_)
	if swatch.a > 0.0:
		var sw := Swatch.new(swatch)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head_.add_child(sw)
	var name_ := words(title, 18, true)
	name_.name = "Name"
	name_.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head_.add_child(name_)
	if lvl > 0:
		var l := words("LVL %d" % lvl, 16)
		l.name = "Level"
		l.add_theme_color_override("font_color", MUTED)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head_.add_child(l)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(1, 1, 1, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_.add_child(rule)
	var c := words(count, 16)
	c.name = "Count"
	c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head_.add_child(c)
	var grid := VBoxContainer.new()
	grid.name = "Grid"
	grid.add_theme_constant_override("separation", int(GAP))
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(grid)
	var i := 0
	while i < tiles.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(GAP))
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(row)
		for k in COLS:
			if i + k < tiles.size():
				row.add_child(tiles[i + k])
			else:
				var pad := Control.new()
				pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(pad)
		if panel != null and panel_at >= i and panel_at < i + COLS:
			grid.add_child(panel)
		i += COLS


## A tile: a dotted card in `colour` with the soft glow behind its picture,
## and the stack the picture and the name go in (a child: it rides the press).
func _tile(name_: String, colour: Color, tint := ShadowStyle.TINT) -> Array:
	var tile := ShadowCard.new(colour)
	tile.name = name_
	tile.tint = tint
	tile.custom_minimum_size = Vector2(0, TILE_H + ShadowStyle.OFFSET)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.texture = _glow(colour)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(glow)
	glow.offset_right = -ShadowStyle.OFFSET
	glow.offset_bottom = -ShadowStyle.OFFSET
	tile.add_child(glow)
	var vb := VBoxContainer.new()
	vb.name = "Stack"
	UiLayout.full_rect(vb)
	vb.offset_left = 6
	vb.offset_right = -6 - ShadowStyle.OFFSET
	vb.offset_bottom = -ShadowStyle.OFFSET
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	tile.add_child(vb)
	return [tile, vb]


## The tile's glow: the design's radial ellipse at (50 %, 44 %), 75 % → 45 %
## at a third → clear by 72 %.
static func _glow(colour: Color) -> GradientTexture2D:
	var key := colour.to_html()
	if _glows.has(key):
		return _glows[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.32, 0.72])
	g.colors = PackedColorArray([Color(colour, 0.75), Color(colour, 0.45), Color(colour, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.44)
	t.fill_to = Vector2(0.5 + 0.75, 0.44)
	t.width = 64
	t.height = 64
	_glows[key] = t
	return t


## The tile's name: bold, one line, cut with an ellipsis.
func _name_line(vb: Control, text: String) -> Label:
	var l := words(text, 18)
	l.name = "Name"
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(l)
	return l


## An unowned slot under ALL: dim, no shadow, a faint ? over ????.
func _locked_tile(id: String) -> Control:
	var tile := Control.new()
	tile.name = "Locked_" + id
	tile.custom_minimum_size = Vector2(0, TILE_H + ShadowStyle.OFFSET)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var face := Panel.new()
	face.name = "Face"
	var sb := StyleBoxFlat.new()
	sb.bg_color = LOCKED_FILL
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	face.add_theme_stylebox_override("panel", sb)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(face)
	face.offset_right = -ShadowStyle.OFFSET
	face.offset_bottom = -ShadowStyle.OFFSET
	tile.add_child(face)
	var vb := VBoxContainer.new()
	UiLayout.full_rect(vb)
	vb.offset_right = -ShadowStyle.OFFSET
	vb.offset_bottom = -ShadowStyle.OFFSET
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	tile.add_child(vb)
	var q := RetroTheme.display("?", 44, Color(1, 1, 1, 0.28))
	q.name = "Mark"
	q.custom_minimum_size = Vector2(0, 128)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(q)
	var l := words("????", 18)
	l.name = "Name"
	l.add_theme_color_override("font_color", LOCKED_TEXT)
	vb.add_child(l)
	return tile


# ---- BALLS --------------------------------------------------------------------------


## The ball's shaded thumbnail (tools/blender/build_ball_lineup.py --thumbs),
## falling back to a crop of the wrap when a thumb is missing.
static func skin_rect(ball: BallSet, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if ball != null:
		var thumb := "res://assets/textures/balls/thumbs/%s.png" % ball.id
		if ResourceLoader.exists(thumb):
			tr.texture = load(thumb)
		elif ball.skin_path != "":
			var at := AtlasTexture.new()
			at.atlas = load(ball.skin_path)
			at.region = SKIN_REGION
			tr.texture = at
	return tr


## The balls by rarity: what you own (and the ball in use), plus ???? for
## the rest under ALL; a rarity you own nothing of is left out under OWNED.
func _build_balls() -> void:
	_scroll()
	var current := _current_id("ball")
	var owned_n := 0
	var all_n := 0
	var groups := []
	for rarity in PeggyPrizes.RARITIES:
		var tiles := []
		var locked := []
		var total := 0
		for cs in CosmeticLibrary.balls():
			var ball := cs as BallSet
			if ball.rarity != rarity:
				continue
			total += 1
			if App.owns("ball", ball.id) or ball.id == current:
				tiles.push_back(_ball_tile(ball, current))
			elif _ball_view == "ALL":
				locked.push_back(_locked_tile(ball.id))
		owned_n += tiles.size()
		all_n += total
		groups.push_back([rarity, tiles, locked, total])
	_view_row(_ball_view, owned_n, all_n)
	for g in groups:
		var rarity: String = g[0]
		var tiles: Array = g[1]
		var locked: Array = g[2]
		if tiles.is_empty() and locked.is_empty():
			continue
		_group(rarity, rarity.to_upper(), "%d/%d" % [tiles.size(), int(g[3])], tiles + locked,
				TIER_COLOR.get(rarity, CREAM), PeggyPrizes.rarity_level(rarity))


## A ball's tile: gold in use, orange EQUIP? while armed, cream otherwise.
func _ball_tile(ball: BallSet, current: String) -> ShadowCard:
	var in_use := ball.id == current
	var armed := not in_use and ball.id == _armed
	var colour: Color = RetroTheme.LIGHT["gold"] if in_use else (RetroTheme.LIGHT["orange"] if armed else CREAM)
	var parts := _tile("Ball_" + ball.id, colour, 0.45 if armed else ShadowStyle.TINT)
	var tile: ShadowCard = parts[0]
	var vb: Control = parts[1]
	var pic := skin_rect(ball, 128)
	pic.name = "Pic"
	if armed:
		pic.modulate.a = 0.55
	vb.add_child(pic)
	if armed:
		var ask := words("EQUIP?", 18, true)
		ask.name = "Name"
		ask.custom_minimum_size.y = 22
		ask.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vb.add_child(ask)
	else:
		_name_line(vb, str(ball.display_name).to_upper())
	var id := ball.id
	tile.pressed.connect(func() -> void: tap_ball.call_deferred(id))
	return tile


## A tap on a ball: the first arms it, the second (while armed) uses it.
func tap_ball(id: String) -> void:
	if id == _current_id("ball"):
		return
	if _armed == id:
		_disarm(false)
		App.select("ball", id)
	else:
		_armed = id
		_arm_timer = null
		if is_inside_tree():
			_arm_timer = create_tween()
			_arm_timer.tween_interval(ARM_S)
			_arm_timer.tween_callback(_disarm)
	_fill(true)


## Let an armed ball go (`refill` restyles the grid).
func _disarm(refill := true) -> void:
	if _arm_timer != null and _arm_timer.is_valid():
		_arm_timer.kill()
	_arm_timer = null
	if _armed == "":
		return
	_armed = ""
	if refill and _tab == "BALLS":
		_fill(true)


func armed() -> String:
	return _armed


# ---- NETS ---------------------------------------------------------------------------


## The net's thumbnail without its rim (tools/qa_driver.gd --qa-net-thumbs),
## a blank panel when it is missing.
static func net_rect(net: NetSet, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if net != null:
		var thumb := NetSet.thumb_path(net.id)
		if ResourceLoader.exists(thumb):
			tr.texture = load(thumb)
	if tr.texture == null:
		var blank := PlaceholderTexture2D.new()
		blank.size = Vector2(px, px)
		tr.texture = blank
		tr.self_modulate = Color(0, 0, 0, 0)
	return tr


## Every net by kind: what you own, plus ???? for the rest under ALL. The
## open net's HANG IT ON goes in under its row.
func _build_nets() -> void:
	_scroll()
	var areas: Array = App.unlocked_areas()
	var owned_n := 0
	var all_n := 0
	var groups := []
	for kind in KINDS:
		var tiles := []
		var locked := []
		var total := 0
		var open_at := -1
		var open_net: NetSet = null
		for cs in CosmeticLibrary.nets():
			var net := cs as NetSet
			if net.kind != kind:
				continue
			total += 1
			if App.owns("net", net.id):
				if net.id == _open_net:
					open_at = tiles.size()
					open_net = net
				tiles.push_back(_net_tile(net, areas))
			elif _net_view == "ALL":
				locked.push_back(_locked_tile(net.id))
		owned_n += tiles.size()
		all_n += total
		groups.push_back([kind, tiles, locked, total, open_at, open_net])
	_view_row(_net_view, owned_n, all_n)
	for g in groups:
		var tiles: Array = g[1]
		var locked: Array = g[2]
		if tiles.is_empty() and locked.is_empty():
			continue
		var open_at: int = g[4]
		var panel: Control = _hang_panel(g[5], open_at % COLS, areas) if open_at >= 0 else null
		_group(str(g[0]), str(g[0]).to_upper(), "%d/%d" % [tiles.size(), int(g[3])], tiles + locked,
				Color.TRANSPARENT, 0, panel, open_at)


## A net's tile: a dot per court you have reached along the top (gold where
## it hangs), the rimless net, its name; gold while it hangs anywhere,
## orange while its HANG IT ON is open.
func _net_tile(net: NetSet, areas: Array) -> ShadowCard:
	var hung: Array = App.net_in_use_areas(net.id)
	var open := net.id == _open_net
	var hangs := false
	for a in areas:
		hangs = hangs or hung.has(a)
	var colour: Color = RetroTheme.LIGHT["orange"] if open else (RetroTheme.LIGHT["gold"] if hangs else CREAM)
	var parts := _tile("Net_" + net.id, colour, 0.45 if open else ShadowStyle.TINT)
	var tile: ShadowCard = parts[0]
	var vb: Control = parts[1]
	var dots := HBoxContainer.new()
	dots.name = "Dots"
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.add_theme_constant_override("separation", 8)
	dots.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	dots.offset_top = 10
	dots.offset_right = -ShadowStyle.OFFSET
	dots.z_index = 1
	for a in areas:
		var d := AreaDot.new(hung.has(a))
		d.name = "Dot_" + str(a)
		dots.add_child(d)
	tile.add_child(dots)
	# The net drawn 176 tall, 30 of it above the stack's slot and 6 below.
	var slot := Control.new()
	slot.name = "Pic"
	slot.custom_minimum_size = Vector2(0, 140)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(slot)
	var pic := net_rect(net, 176)
	pic.name = "Net"
	pic.size = Vector2(176, 176)
	slot.add_child(pic)
	slot.resized.connect(func() -> void: pic.position = Vector2(roundf((slot.size.x - 176.0) * 0.5), -30.0))
	_name_line(vb, str(net.display_name).to_upper())
	var id := net.id
	tile.pressed.connect(func() -> void: tap_net.call_deferred(id))
	return tile


## A tap on a net opens its HANG IT ON (or closes it when it is open).
func tap_net(id: String) -> void:
	_open_net = "" if _open_net == id else id
	_fill(true)


func open_net() -> String:
	return _open_net


## HANG IT ON: under the open net's row, a notch up to its tile; the name,
## X, and a button per court you have reached.
func _hang_panel(net: NetSet, col: int, areas: Array) -> Control:
	var wrap := VBoxContainer.new()
	wrap.name = "HangPanel"
	wrap.add_theme_constant_override("separation", 0)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	var notch := Notch.new(col)
	notch.name = "Notch"
	wrap.add_child(notch)
	var panel := ShadowPanel.new(RetroTheme.LIGHT["orange"], 16.0, 0.0, 18.0)
	panel.name = "Panel"
	panel.ground = HANG_GROUND
	panel.add_theme_stylebox_override("panel", _hang_margins())
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(panel)
	var col_ := VBoxContainer.new()
	col_.add_theme_constant_override("separation", 16)
	col_.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(col_)
	var head_ := HBoxContainer.new()
	head_.add_theme_constant_override("separation", 14)
	head_.mouse_filter = Control.MOUSE_FILTER_PASS
	col_.add_child(head_)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_theme_constant_override("separation", 10)
	head_.add_child(names)
	var title := words(str(net.display_name).to_upper(), 18, true)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_color", RetroTheme.LIGHT["gold"])
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(title)
	var ask := words("HANG IT ON", 15)
	ask.name = "Ask"
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(ask)
	var x := button("X", CREAM, 24, 64)
	x.name = "Shut"
	x.custom_minimum_size.x = 64 + ShadowStyle.OFFSET
	x.pressed.connect(func() -> void: tap_net.call_deferred(net.id))
	head_.add_child(x)
	var grid := VBoxContainer.new()
	grid.name = "Areas"
	grid.add_theme_constant_override("separation", 14)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	col_.add_child(grid)
	var row: HBoxContainer = null
	for i in areas.size():
		if i % COLS == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			row.mouse_filter = Control.MOUSE_FILTER_PASS
			grid.add_child(row)
		row.add_child(_area_button(net.id, str(areas[i])))
	if row != null:
		for k in (COLS - row.get_child_count()) % COLS:
			var pad := Control.new()
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pad)
	return wrap


## The panel's margins: 16 / 18 / 20 round the face, clear of the shadow.
static func _hang_margins() -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 18
	sb.content_margin_top = 16
	sb.content_margin_right = 18 + ShadowStyle.OFFSET
	sb.content_margin_bottom = 20 + ShadowStyle.OFFSET
	return sb


## One court's button: gold HANGING where the net hangs, cream TAP TO HANG.
func _area_button(id: String, area: String) -> ShadowCard:
	var here := false
	var hung := App.net_set_for(area)
	here = hung != null and hung.id == id
	var b := ShadowCard.new(RetroTheme.LIGHT["gold"] if here else CREAM)
	b.name = "Area_" + area
	b.tint = 0.35
	b.custom_minimum_size = Vector2(0, 68 + ShadowStyle.OFFSET)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	UiLayout.full_rect(vb)
	vb.offset_right = -ShadowStyle.OFFSET
	vb.offset_bottom = -ShadowStyle.OFFSET
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 8)
	b.add_child(vb)
	var l := words(area.to_upper(), 16, true)
	l.name = "Label"
	vb.add_child(l)
	var s := words("HANGING" if here else "TAP TO HANG", 14)
	s.name = "Sub"
	vb.add_child(s)
	b.pressed.connect(func() -> void: hang.call_deferred(id, area))
	return b


## Hang the open net on a court (each court holds one: the one there comes
## down); HANG IT ON stays open and restyles.
func hang(id: String, area: String) -> void:
	if App.select_net(area, id):
		_fill(true)


## The id in use: the live set, else the starter.
func _current_id(kind: String) -> String:
	var live: CosmeticSet = App.ball_set if kind == "ball" else App.hoop_set
	if live != null:
		return live.id
	var starter: CosmeticSet = CosmeticLibrary.starter_ball() if kind == "ball" else CosmeticLibrary.starter_hoop()
	return starter.id if starter != null else ""


## Tile names on the tab, in order ("Ball_<id>" / "Net_<id>"), for tests.
func rows() -> Array:
	var out := []
	if _list == null:
		return out
	for c in _list.find_children("*", "Button", true, false):
		if str(c.name).begins_with("Ball_") or str(c.name).begins_with("Net_"):
			out.push_back(String(c.name))
	return out


## The ???? tiles on the tab (ALL), for tests.
func locked_count() -> int:
	return _list.find_children("Locked_*", "", true, false).size() if _list != null else 0


## The ball tile in use (gold), for tests.
func in_use_row(kind := "ball") -> String:
	var prefix := "Ball_" if kind == "ball" else "Net_"
	if _list == null:
		return ""
	for c in _list.find_children(prefix + "*", "Button", true, false):
		if c is ShadowCard and (c as ShadowCard).color == RetroTheme.LIGHT["gold"]:
			return String(c.name)
	return ""


## The rarity square beside a ball group's name: the colour, an ink edge,
## a hard ink shadow.
class Swatch extends Control:
	var colour := Color.WHITE

	func _init(c: Color) -> void:
		colour = c
		custom_minimum_size = Vector2(21, 21)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink := RetroTheme.SCENE_OUTLINE
		draw_rect(Rect2(Vector2(3, 3), Vector2(18, 18)), ink)
		draw_rect(Rect2(Vector2.ZERO, Vector2(18, 18)), ink)
		draw_rect(Rect2(Vector2(2, 2), Vector2(14, 14)), colour)


## A court's dot on a net tile: gold with an ink edge where the net hangs,
## a white edge on dark where it does not.
class AreaDot extends Control:
	var on := false

	func _init(p_on: bool) -> void:
		on = p_on
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink := RetroTheme.SCENE_OUTLINE
		draw_rect(Rect2(Vector2(2, 2), Vector2(14, 14)), ink)
		draw_rect(Rect2(Vector2.ZERO, Vector2(14, 14)), RetroTheme.LIGHT["gold"] if on else DOT_OFF)
		draw_rect(Rect2(Vector2(1, 1), Vector2(12, 12)), ink if on else Color.WHITE, false, 2.0)


## The orange notch on HANG IT ON's top edge, under the open tile's column.
class Notch extends Control:
	var col := 0

	func _init(p_col: int) -> void:
		col = p_col
		custom_minimum_size = Vector2(0, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := (size.x - GAP * (COLS - 1)) / COLS
		var cx := col * (w + GAP) + (w - ShadowStyle.OFFSET) * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 14, 14), Vector2(cx + 14, 14), Vector2(cx, 0)]),
				RetroTheme.LIGHT["orange"])
