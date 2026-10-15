class_name LockerPanel
extends HomePage
## The locker page (the top-left ball icon), docs/LOCKER.md: the collection.
## Two tabs — BALLS, the balls you own (tap to equip, everywhere) — and
## NETS, the nets you own, split by a COTTON / CHAIN sub-tab since each kind
## hangs on different courts (tap to hang it on every court of its kind;
## the pause menu swaps per court). Nothing unowned is listed: balls are won
## on PEGGY (the PEGGY button beside the ticket chip opens its page) and the
## net store is a later page. The hoop counter is closed
## (App.HOOPS_IN_LOCKER). Opening BALLS clears App.unseen_balls(), which the
## title's locker icon badges.

signal peggy_requested

const TABS := ["BALLS", "NETS"]
const KINDS := ["cotton", "chain"]
const SKIN_REGION := Rect2(64, 64, 128, 128)
const TILE_W := 140.0

var _tabs: HBoxContainer
var _content: Control
var _tab := "BALLS"
var _net_kind := "cotton"
var _list: VBoxContainer


func _row_gap() -> int:
	return 28


func _build() -> void:
	var h := head("LOCKER")
	var peggy := button("PEGGY", RetroTheme.LIGHT["orange"], 16, 48)
	peggy.name = "Peggy"
	peggy.custom_minimum_size.x = 120
	peggy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	peggy.pressed.connect(func() -> void: peggy_requested.emit())
	h.add_child(peggy)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 10)
	body.add_child(_tabs)
	_content = Control.new()
	_content.name = "Content"
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(_content)
	close_button()
	_fill()


## Rebuild the tabs and the current tab's content. Old nodes are removed at
## once and freed later: _fill runs from the tabs' own pressed signals, and
## freeing the emitter mid-signal left the page half built.
func _fill() -> void:
	set_tickets()
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
	if _tab == "NETS":
		_build_nets()
	else:
		_build_balls()


func show_tab(tab: String) -> void:
	if not TABS.has(tab):
		return
	_tab = tab
	if tab == "BALLS":
		App.mark_balls_seen()
	_fill()


func tab() -> String:
	return _tab


## The NETS sub-tab ("cotton" | "chain").
func show_kind(kind: String) -> void:
	if not KINDS.has(kind):
		return
	_net_kind = kind
	_fill()


func net_kind() -> String:
	return _net_kind


# ---- the pieces ----------------------------------------------------------------


func _scroll() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = _tab.capitalize() + "Tab"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "Items"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 20)
	scroll.add_child(_list)
	return _list


func _grid(name_: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = name_
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_list.add_child(grid)
	return grid


## A tile: a gold (in use) or cream dotted card with its picture and lines
## stacked inside; the stack is a child so it rides the press.
func _tile(name_: String, height: float, in_use: bool) -> Array:
	var tile := ShadowCard.new(RetroTheme.LIGHT["gold"] if in_use else CREAM)
	tile.name = name_
	tile.custom_minimum_size = Vector2(TILE_W, height + ShadowStyle.OFFSET)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_right = -ShadowStyle.OFFSET
	vb.offset_bottom = -ShadowStyle.OFFSET
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	tile.add_child(vb)
	return [tile, vb]


func _line(vb: Control, name_: String, text: String, size_: int) -> Label:
	var l := words(text, size_)
	l.name = name_
	vb.add_child(l)
	return l


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


## The balls you own, in library order; the one in use is gold.
func _build_balls() -> void:
	_scroll()
	var head_ := chip("BALLS · OWNED")
	head_.name = "Head_ball"
	_list.add_child(head_)
	var grid := _grid("BallGrid")
	var current := _current_id("ball")
	for cs in CosmeticLibrary.balls():
		var ball := cs as BallSet
		if not (App.owns("ball", ball.id) or ball.id == current):
			continue
		var in_use: bool = ball.id == current
		var parts := _tile("Ball_" + ball.id, 176, in_use)
		var tile: ShadowCard = parts[0]
		var vb: Control = parts[1]
		vb.add_child(skin_rect(ball, 96))
		_line(vb, "Name", str(ball.display_name).to_upper(), 11)
		_line(vb, "Tag", "IN USE" if in_use else "EQUIP", 11)
		var id := ball.id
		tile.pressed.connect(func() -> void:
			if App.select("ball", id):
				_fill()
		)
		grid.add_child(tile)


# ---- NETS ---------------------------------------------------------------------------


## The net's thumbnail (tools/qa_driver.gd --qa-net-thumbs), a blank panel
## when it is missing.
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


static func _upper(areas: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for a in areas:
		out.push_back(str(a).to_upper())
	return out


## The nets you own of the sub-tab's kind; the one hanging is gold.
func _build_nets() -> void:
	_scroll()
	var subs := HBoxContainer.new()
	subs.name = "NetSubs"
	subs.add_theme_constant_override("separation", 12)
	_list.add_child(subs)
	for kind in KINDS:
		var b := button(str(kind).to_upper(), RetroTheme.LIGHT["gold"] if kind == _net_kind else CREAM, 16, 46)
		b.name = "Sub_" + str(kind).to_upper()
		b.custom_minimum_size.x = 170
		var k: String = kind
		b.pressed.connect(func() -> void: show_kind.call_deferred(k))
		subs.add_child(b)
	var hangs := _upper(App.net_areas(_net_kind))
	var head_ := chip("%s · HANGS ON %s" % [_net_kind.to_upper(), " + ".join(hangs)])
	head_.name = "Head_net"
	_list.add_child(head_)
	var grid := _grid("NetGrid")
	for cs in CosmeticLibrary.nets():
		var net := cs as NetSet
		if net.kind != _net_kind or not App.owns("net", net.id):
			continue
		var used: Array = App.net_in_use_areas(net.id)
		var in_use := not used.is_empty()
		var parts := _tile("Net_" + net.id, 196, in_use)
		var tile: ShadowCard = parts[0]
		var vb: Control = parts[1]
		vb.add_child(net_rect(net, 96))
		_line(vb, "Name", str(net.display_name).to_upper(), 11)
		_line(vb, "Kind", "%s · %s" % [net.kind.to_upper(), ", ".join(_upper(App.net_areas(net.kind)))], 9)
		_line(vb, "Tag", "IN USE ON %s" % " + ".join(_upper(used)) if in_use else "EQUIP", 11)
		var id := net.id
		tile.pressed.connect(func() -> void:
			if App.select_net_everywhere(id):
				_fill()
		)
		grid.add_child(tile)


## The id in use: the live set, else the starter.
func _current_id(kind: String) -> String:
	var live: CosmeticSet = App.ball_set if kind == "ball" else App.hoop_set
	if live != null:
		return live.id
	var starter: CosmeticSet = CosmeticLibrary.starter_ball() if kind == "ball" else CosmeticLibrary.starter_hoop()
	return starter.id if starter != null else ""


## Button names on the BALLS / NETS tab, in order ("Ball_<id>" / "Net_<id>"), for tests.
func rows() -> Array:
	var out := []
	if _list == null:
		return out
	for c in BeachFx._descendants(_list):
		if c is Button and (str(c.name).begins_with("Ball_") or str(c.name).begins_with("Net_")):
			out.push_back(String(c.name))
	return out


func in_use_row(kind := "ball") -> String:
	var prefix := "Ball_" if kind == "ball" else "Net_"
	if _list == null:
		return ""
	for c in BeachFx._descendants(_list):
		if c is Button and str(c.name).begins_with(prefix):
			var words_: String = c.text
			for l in c.find_children("*", "Label", true, false):
				words_ += " " + str(l.text)
			if words_.contains("IN USE"):
				return String(c.name)
	return ""
