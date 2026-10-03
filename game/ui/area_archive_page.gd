class_name AreaArchivePage
extends CanvasLayer
## The area archive (design "Area Archive" 17a, docs/HOME.md → Area
## archive): the page you see before an area's home. A cream sheet with
## `<` AREAS `2/3 OPEN`, then a tall card per area — a snapshot of the real
## court (assets/ui/areas/area_<id>.png, tools/qa_driver.gd --qa-area-snaps)
## under a bottom gradient, its stars, its name, a `>` and the history line
## (titles · seasons · best) when it is open; a locked area sits under a
## dark overlay with the lock and the level that opens it, and does nothing
## when tapped. Picking an open area presses the card, covers the page in
## ink and emits `picked(id)`; the home page takes over the fade from there.

signal closed
signal picked(id: String)

const CARD_H := 320.0
const CARD_W := 664.0
const PAD := Vector2(28, 44)
const GAP := 22.0
const INK := Color("#221C18")
const CREAM := Color("#F1E8D0")
const LOCK_ALPHA := 0.84
const SLIDE_S := 0.22
const COVER_S := 0.2

var _root: Control
var _sheet: Control
var _cover: ColorRect
var _cards: Dictionary = {}
var _done := false
var _back: Button


func _init() -> void:
	layer = 30


func build(rows: Array, open_text: String, can_close := true) -> Control:
	_cards.clear()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "ArchivePage"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_sheet = Control.new()
	_sheet.name = "Sheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_sheet)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = RetroTheme.c("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(bg)
	# The header: < AREAS n/3 OPEN.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.position = PAD
	head.size = Vector2(720 - PAD.x * 2, 56)
	head.add_theme_constant_override("separation", 20)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(head)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "<"
	_back.custom_minimum_size = Vector2(56 + ShadowStyle.OFFSET, 56 + ShadowStyle.OFFSET)
	RetroTheme.card_button(_back, RetroTheme.c("panel"), RetroTheme.RADIUS, 0.0)
	_back.add_theme_font_size_override("font_size", UiFont.snap(24))
	_back.add_theme_color_override("font_color", RetroTheme.c("text"))
	_back.add_theme_color_override("font_pressed_color", RetroTheme.c("text"))
	_back.add_theme_color_override("font_hover_color", RetroTheme.c("text"))
	_back.pressed.connect(close)
	_back.visible = can_close
	head.add_child(_back)
	var title := RetroTheme.display("AREAS", 32)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var count := RetroTheme.caps(open_text, 16, RetroTheme.c("muted"))
	count.name = "OpenCount"
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(count)
	# The cards.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = Vector2(PAD.x, PAD.y + 56 + 20)
	scroll.size = Vector2(720 - PAD.x * 2, 1280 - PAD.y - 56 - 20 - PAD.x)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", int(GAP))
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(list)
	for r in rows:
		var card := _card(r)
		list.add_child(card)
		_cards[str(r["id"])] = card
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 10)
	list.add_child(tail)
	# The ink cover for the hand-off to the home page.
	_cover = ColorRect.new()
	_cover.name = "Cover"
	_cover.color = Color(RetroTheme.c("ink"), 0.0)
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cover)
	return _root


func _label(text: String, size_: int, display := true) -> Label:
	var l := UiFont.label(text, size_, CREAM, UiFont.display() if display else UiFont.body_bold())
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	return l


## One area's card: the snapshot, the gradient, stars + name (+ `>` and
## the history when open), the lock overlay when locked.
func _card(r: Dictionary) -> Button:
	var id := str(r["id"])
	var locked := bool(r.get("locked", false))
	var b := ShadowCard.solid(INK, INK, INK)
	b.name = "Area_" + id
	b.custom_minimum_size = Vector2(CARD_W + ShadowStyle.OFFSET, CARD_H + ShadowStyle.OFFSET)
	b.disabled = locked
	b.focus_mode = Control.FOCUS_NONE
	var face := Control.new()
	face.name = "Face"
	face.position = Vector2.ZERO
	face.size = Vector2(CARD_W, CARD_H)
	face.clip_contents = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	var snap := TextureRect.new()
	snap.name = "Snap"
	var path := "res://assets/ui/areas/area_%s.png" % id
	if ResourceLoader.exists(path):
		snap.texture = load(path)
	snap.set_anchors_preset(Control.PRESET_FULL_RECT)
	snap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	snap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	snap.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	snap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(snap)
	var grad := TextureRect.new()
	grad.name = "Gradient"
	var g := Gradient.new()
	g.set_color(0, Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.0))
	g.set_color(1, Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.78))
	g.set_offset(0, 0.3)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(grad)
	if locked:
		var lock := ColorRect.new()
		lock.name = "Lock"
		lock.color = Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, LOCK_ALPHA)
		lock.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(lock)
		var col := VBoxContainer.new()
		col.name = "LockCol"
		col.position = Vector2(0, 56)
		col.size = Vector2(CARD_W, 120)
		col.alignment = BoxContainer.ALIGNMENT_BEGIN
		col.add_theme_constant_override("separation", 18)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := PixelIcon.new("icon_lock", Vector2(60, 72), 5.0)
		icon.name = "LockIcon"
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(icon)
		var line := _label(AreaArchiveCopy.lock_line(int(r["lvl"])), 16, false)
		line.name = "LockLine"
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(line)
		face.add_child(col)
	# The bottom block: stars, name + >, history.
	var block := VBoxContainer.new()
	block.name = "Block"
	block.position = Vector2(24, 0)
	block.size = Vector2(CARD_W - 48, CARD_H - 24)
	block.alignment = BoxContainer.ALIGNMENT_END
	block.add_theme_constant_override("separation", 14)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(block)
	var stars := HBoxContainer.new()
	stars.name = "Stars"
	stars.add_theme_constant_override("separation", 6)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in int(r.get("stars", 1)):
		stars.add_child(PixelIcon.new("icon_star", Vector2(22, 22), 2.0))
	block.add_child(stars)
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 16)
	name_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := _label(str(r["name"]), 30, true)
	nm.name = "Name"
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.add_theme_constant_override("line_spacing", 8)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_row.add_child(nm)
	if not locked:
		var go := _label(">", 32, true)
		go.name = "Go"
		go.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		name_row.add_child(go)
	block.add_child(name_row)
	if not locked:
		var hist := HBoxContainer.new()
		hist.name = "History"
		hist.add_theme_constant_override("separation", 12)
		hist.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parts: Array = r.get("history", [])
		for i in parts.size():
			if i > 0:
				var dot := ColorRect.new()
				dot.color = CREAM
				dot.custom_minimum_size = Vector2(4, 4)
				dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hist.add_child(dot)
			if i == 0 or i == 2:
				var ic := PixelIcon.new("icon_trophy" if i == 0 else "icon_stopwatch", Vector2(20, 20), 2.0)
				ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				hist.add_child(ic)
			var l := _label(str(parts[i]), 16, false)
			l.name = "Hist%d" % i
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			hist.add_child(l)
		block.add_child(hist)
	if not locked:
		b.pressed.connect(func() -> void: pick(id))
	return b


func page_root() -> Control:
	return _root


func card(id: String) -> Button:
	return _cards.get(id)


func cards() -> Array:
	return _cards.keys()


## Slide the sheet in (only once in the tree).
func slide_in() -> void:
	if _sheet == null or not is_inside_tree():
		return
	_sheet.position.x = 60.0
	_sheet.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_sheet, "position:x", 0.0, SLIDE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sheet, "modulate:a", 1.0, SLIDE_S)


## An open area was tapped: ink over the page, then hand it to the home.
func pick(id: String) -> void:
	if _done or not _cards.has(id) or (_cards[id] as Button).disabled:
		return
	_done = true
	if is_inside_tree() and _cover != null:
		var tw := create_tween()
		tw.tween_property(_cover, "color:a", 1.0, COVER_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
	picked.emit(id)


func close() -> void:
	if _done:
		return
	_done = true
	closed.emit()
	queue_free()
