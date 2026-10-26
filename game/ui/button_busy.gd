class_name ButtonBusy
extends RefCounted
## The pressed-button loading state (design "Loading States" 39b,
## 2026-10-25): the button that started a load stays pushed in, its words
## swap to a spinning ball + LOADING… with its own name (or the load's line)
## underneath, and every other button on the page dims and stops taking taps.
## SceneLoader applies it to the button under the finger when a move starts.

const DIM := 0.45
const BUSY_NAME := "Busy"


## Put `b` in its loading state; `sub` is the line under LOADING ("" → the
## button's own words). Dims and disables every other button under `page`.
static func apply(b: BaseButton, sub: String, page: Node) -> void:
	if b == null or not is_instance_valid(b) or b.get_node_or_null(BUSY_NAME) != null:
		return
	var words := sub if sub != "" else label_of(b)
	if page != null:
		for other in page.find_children("*", "BaseButton", true, false):
			if other != b and is_instance_valid(other):
				(other as BaseButton).disabled = true
				(other as CanvasItem).modulate.a = DIM
	b.disabled = true   # no second tap; the face stays pressed below
	if b is ShadowCard:
		var card := b as ShadowCard
		card.toggle_mode = true
		card.set_pressed_no_signal(true)
		card._shift(true)
		card.queue_redraw()
	for c in b.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
	b.set_meta("busy_text", b.text)
	b.text = ""
	var h := b.size.y if b.size.y > 0.0 else b.custom_minimum_size.y
	var big := h >= 130.0
	var row := HBoxContainer.new()
	row.name = BUSY_NAME
	row.add_theme_constant_override("separation", 22 if big else 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(row)   # inside the button: fills it, no bleed
	row.offset_left = 32.0 if big else 24.0
	row.offset_right = -24.0
	row.offset_top = ShadowStyle.OFFSET
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	b.add_child(row)
	var spin := PixelSpinner.new(48.0 if big else (44.0 if h >= 100.0 else 32.0))
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14 if big else 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var title := Dots.new(28 if big else (22 if h >= 100.0 else 16))
	title.name = "BusyLoading"
	col.add_child(title)
	if h >= 100.0 and words != "":
		var s := UiFont.label(words, 16 if big else 15, RetroTheme.SCENE_TEXT, UiFont.body_bold())
		RetroTheme.on_scene(s)
		s.name = "BusySub"
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(s)


## Whether `b` is in its loading state.
static func is_busy(b: BaseButton) -> bool:
	return b != null and b.get_node_or_null(BUSY_NAME) != null


## A button's words: its text, else its labels joined (ModeCards put theirs in children).
static func label_of(b: BaseButton) -> String:
	if b.text.strip_edges() != "":
		return b.text.replace("\n", " ").strip_edges()
	for l in b.find_children("*", "Label", true, false):
		var t := (l as Label).text.replace("\n", " ").strip_edges()
		if t != "" and t != ">":
			return t
	return ""


## LOADING with the animated dots (LoadingCopy.dots), in display type.
class Dots extends Label:
	var _t := 0.0
	func _init(px: int) -> void:
		add_theme_font_override("font", UiFont.display())
		add_theme_font_size_override("font_size", UiFont.snap(px))
		RetroTheme.on_scene(self)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		text = "LOADING"
		custom_minimum_size = Vector2(px * 10, 0)
	func _process(dt: float) -> void:
		_t += dt
		text = "LOADING" + LoadingCopy.dots(_t)
