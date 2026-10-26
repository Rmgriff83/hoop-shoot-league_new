class_name ButtonBusy
extends RefCounted
## The pressed-button loading state (design "Loading States" 39b,
## 2026-10-25): the button that started a load stays pushed in, its words
## give way to the pixel spinner alone (no LOADING words since 2026-10-25:
## they overflowed small buttons), and every other button on the page dims
## and stops taking taps.
## SceneLoader applies it to the button under the finger when a move starts.

const DIM := 0.45
const BUSY_NAME := "Busy"


## Put `b` in its loading state (`_sub` is kept for the callers; nothing
## prints it now). Dims and disables every other button under `page`.
static func apply(b: BaseButton, _sub: String, page: Node) -> void:
	if b == null or not is_instance_valid(b) or b.get_node_or_null(BUSY_NAME) != null:
		return
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
	# Just the spinner, centred on the pressed face and sized to the button
	# (Ross, 2026-10-25: words overflowed small buttons; the icon keeps the
	# button's size).
	var h := b.size.y if b.size.y > 0.0 else b.custom_minimum_size.y
	var box := CenterContainer.new()
	box.name = BUSY_NAME
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(box)   # inside the button: fills it, no bleed
	box.offset_left = ShadowStyle.OFFSET
	box.offset_top = ShadowStyle.OFFSET
	b.add_child(box)
	var spin := PixelSpinner.new(spinner_px(h))
	spin.name = "BusySpinner"
	box.add_child(spin)


## The spinner's size for a button `h` px tall: 40 % of it, 20–48 px.
static func spinner_px(h: float) -> float:
	return clampf(roundf((h - ShadowStyle.OFFSET) * 0.4), 20.0, 48.0)


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
