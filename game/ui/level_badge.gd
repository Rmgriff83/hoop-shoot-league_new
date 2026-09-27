class_name LevelBadge
extends PanelContainer
## The compact top-left level element: "LVL01" over its progress meter, in
## the see-through dithered-shadow style (ShadowStyle, cream). A placeholder
## for now — the home passes (1, 0.0); there is no progression system yet.

const BAR_W := 150.0
const BAR_H := 12.0
const COLOR := RetroTheme.SCENE_TEXT

var _caps: Label
var _fill: ColorRect
var _bar: PanelContainer


func _init() -> void:
	name = "Level"
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_theme_stylebox_override("panel", ShadowStyle.margins(10.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	# `LVL · 01`: the word, a small cream square, the number (design "Home
	# League Context v2").
	var row := HBoxContainer.new()
	row.name = "Caps"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var word := RetroTheme.on_scene(UiFont.label("LVL", 16, COLOR)) as Label
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(word)
	var dot := Dot.new()
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	_caps = RetroTheme.on_scene(UiFont.label("01", 16, COLOR))
	_caps.name = "Number"
	_caps.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_caps)
	_bar = PanelContainer.new()
	_bar.name = "Bar"
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(RetroTheme.SCENE_OUTLINE, 0.55)
	track.border_color = COLOR
	track.set_border_width_all(2)
	_bar.add_theme_stylebox_override("panel", track)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_bar)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.color = RetroTheme.LIGHT["orange"]
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_fill)
	set_level(1, 0.0)


func _draw() -> void:
	ShadowStyle.draw(self, size, COLOR, false, false, false)


func set_level(level: int, frac: float) -> void:
	_caps.text = "%02d" % level
	_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_fill.offset_left = 2
	_fill.offset_top = 2
	_fill.offset_bottom = -2
	_fill.offset_right = 2 + clampf(frac, 0.0, 1.0) * (BAR_W - 4)
	_fill.visible = frac > 0.0


func level_text() -> String:
	return "LVL" + _caps.text


## The 4 px cream square between LVL and the number, with a 2 px ink shadow.
class Dot extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(6, 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2(4, 4)), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, Vector2(4, 4)), RetroTheme.SCENE_TEXT)
