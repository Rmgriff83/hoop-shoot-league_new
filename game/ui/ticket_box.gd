class_name TicketBox
extends ShadowPanel
## The gold ticket box the stream lands in (designs 7a / 15a): the ticket icon
## in a square slot on the left — it bumps (×1.28, a tilt) as each flyer
## lands — then `+N` in gold display type over a bold sub line. `set_count`
## writes the number; the results page and the match-end page size it their
## own way (the slot, the type sizes, the height, the padding).

const GOLD := Color("#F0B84A")
const BUMP_S := 0.22

var _icon: PixelIcon
var _slot: Control
var _big: Label
var _sub: Label
var _bump_t := -1.0


## `width` > 0 fixes the box's width and wraps the sub line inside it; 0 hugs the words.
func _init(height: float, slot: float, big_px: int, sub_px: int, pad_x: float, gap: float, icon_w := 52.0, min_big_w := 0.0, width := 0.0) -> void:
	super(GOLD, 0.0, ShadowStyle.TINT, pad_x)
	name = "Tickets"
	custom_minimum_size = Vector2(0, height + ShadowStyle.OFFSET)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", int(gap))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_slot = Control.new()
	_slot.name = "Slot"
	_slot.custom_minimum_size = Vector2(slot, slot)
	_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_slot)
	var icon_size := Vector2(icon_w, icon_w * 14.0 / 22.0)
	_icon = PixelIcon.new("icon_ticket", icon_size, 3.0)
	_icon.name = "Icon"
	_icon.position = (Vector2(slot, slot) - icon_size) * 0.5
	_icon.pivot_offset = icon_size * 0.5
	_slot.add_child(_icon)
	var col := VBoxContainer.new()
	col.name = "Lines"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_big = UiFont.label("+0", big_px, GOLD, UiFont.display())
	RetroTheme.on_scene(_big)
	_big.add_theme_color_override("font_color", GOLD)
	_big.name = "TicketsBig"
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_big.custom_minimum_size = Vector2(min_big_w, 0)
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_big)
	_sub = UiFont.label("TICKETS", sub_px, RetroTheme.SCENE_TEXT, UiFont.body_bold())
	RetroTheme.on_scene(_sub)
	_sub.name = "TicketsSub"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if width > 0.0:
		custom_minimum_size.x = width + ShadowStyle.OFFSET
		var col_w := width - 2.0 * pad_x - slot - gap
		col.custom_minimum_size = Vector2(col_w, 0)
		_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sub.custom_minimum_size = Vector2(col_w, 0)
	_sub.add_theme_constant_override("line_spacing", 3)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_sub)


func set_count(n: int) -> void:
	_big.text = "+%d" % n


func set_sub(text: String) -> void:
	_sub.text = text


func count_text() -> String:
	return _big.text


## The icon's centre on screen — where the stream lands.
func icon_center() -> Vector2:
	return _icon.get_global_rect().get_center()


## The landing bump (design tkBump): ×1.28 with an 8° tilt, back over 0.22 s.
func bump() -> void:
	_bump_t = 0.0


func _process(dt: float) -> void:
	if _bump_t < 0.0:
		return
	_bump_t += dt
	var p := clampf(_bump_t / BUMP_S, 0.0, 1.0)
	var k := (p / 0.35) if p < 0.35 else (1.0 - (p - 0.35) / 0.65)
	_icon.scale = Vector2.ONE * (1.0 + 0.28 * k)
	_icon.rotation = deg_to_rad(-8.0 * k)
	if p >= 1.0:
		_bump_t = -1.0
		_icon.scale = Vector2.ONE
		_icon.rotation = 0.0
