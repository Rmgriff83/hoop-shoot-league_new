class_name NetAreaSheet
extends CanvasLayer
## "Hang it where?" — the locker's popup for a net (docs/LOCKER.md → NETS,
## 2026-10-16): any net, cotton or chain, hangs on any area's hoop. A dim
## over the locker, a cream dotted card with the net's name and thumbnail,
## one row per area in App.AREA_MODES order — the area's name, what hangs
## there now; gold with HANGING when it is this net; a locked area reads
## LOCKED · LVL n and does nothing — EVERYWHERE, and CLOSE. Tapping a row
## hangs the net on that area (App.select_net) and the rows restyle in place;
## `closed` fires on CLOSE or a tap on the dim, and the locker refills.

signal closed

const DIM := Color(0.02, 0.02, 0.05, 0.6)
const CARD_POS := Vector2(90, 300)
const CARD_SIZE := Vector2(540, 690)
const CREAM := RetroTheme.SCENE_TEXT
const ROW_H := 60.0

var net_id := ""
var _rows := {}   # area → {card: ShadowCard, value: Label, locked: bool}
var _root: Control


func _init() -> void:
	layer = 35


## Build the sheet for an owned net. False (nothing built) for an unknown net.
func build(id: String) -> bool:
	var net := CosmeticLibrary.get_net(id)
	if net == null:
		return false
	net_id = id
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows = {}
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			close()
	)
	_root.add_child(dim)
	var card := ShadowPanel.new(CREAM, 24.0)
	card.name = "Card"
	card.position = CARD_POS
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(card)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_top = 24
	col.offset_right = -24 - ShadowStyle.OFFSET
	col.offset_bottom = -24 - ShadowStyle.OFFSET
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var title := HomePage.words("HANG %s" % str(net.display_name).to_upper(), 18, true)
	title.name = "Title"
	col.add_child(title)
	var thumb := LockerPanel.net_rect(net, 88)
	thumb.name = "Thumb"
	col.add_child(thumb)
	var ask := HomePage.words("ON WHICH COURT?", 12)
	ask.name = "Ask"
	col.add_child(ask)
	for area in App.AREA_MODES["practice"]:
		col.add_child(_row(str(area)))
	var every := HomePage.button("EVERYWHERE", RetroTheme.LIGHT["gold"], 16, 56)
	every.name = "Everywhere"
	every.pressed.connect(func() -> void:
		if App.select_net_everywhere(net_id):
			_restyle()
	)
	col.add_child(every)
	var close_ := HomePage.button("CLOSE", CREAM, 16, 56)
	close_.name = "Close"
	close_.pressed.connect(close)
	col.add_child(close_)
	_restyle()
	return true


## One area's row: the name left, what hangs there right.
func _row(area: String) -> ShadowCard:
	var card := ShadowCard.new(CREAM)
	card.name = "Area_" + area
	card.custom_minimum_size = Vector2(0, ROW_H + ShadowStyle.OFFSET)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -18 - ShadowStyle.OFFSET
	row.offset_bottom = -ShadowStyle.OFFSET
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var name_ := HomePage.words(ResultsCopy.area_name(area), 14)
	name_.name = "Name"
	name_.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_)
	var value := HomePage.words("", 13)
	value.name = "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var locked := not App.area_unlocked(area)
	card.disabled = locked
	card.pressed.connect(func() -> void:
		if not locked and App.select_net(area, net_id):
			_restyle()
	)
	_rows[area] = {"card": card, "value": value, "locked": locked}
	return card


## Gold + HANGING where this net hangs, the hung net's name elsewhere,
## LOCKED · LVL n on an area not yet reached.
func _restyle() -> void:
	for area in _rows:
		var r: Dictionary = _rows[area]
		var card: ShadowCard = r["card"]
		var value: Label = r["value"]
		if r["locked"]:
			value.text = "LOCKED · LVL %d" % Progression.area_level(str(area))
			card.color = CREAM
			card.tint = ShadowStyle.TINT * 0.5
		else:
			var hung := App.net_set_for(str(area))
			var mine := hung != null and hung.id == net_id
			value.text = "HANGING" if mine else (str(hung.display_name).to_upper() if hung != null else "")
			card.color = RetroTheme.LIGHT["gold"] if mine else CREAM
		card.queue_redraw()


func close() -> void:
	closed.emit()


# ---- for tests and QA -------------------------------------------------------------


## The area rows' names, in order ("Area_<id>").
func rows() -> Array:
	var out := []
	for area in App.AREA_MODES["practice"]:
		if _rows.has(area):
			out.push_back("Area_" + str(area))
	return out


## The right-hand text of an area's row.
func value(area: String) -> String:
	return (_rows[area]["value"] as Label).text if _rows.has(area) else ""


func is_locked(area: String) -> bool:
	return bool(_rows[area]["locked"]) if _rows.has(area) else false
