class_name HomePage
extends CanvasLayer
## A page over the home screen (docs/HOME.md → Pages): the locker and PEGGY.
## It opens with the ENTER LEAGUE move — the title slides its chrome out to
## the left while the page's frame slides in from the right over the area,
## which stays visible under a light wash — and CLOSE runs it backwards.
## Pages stack: a page opened from another (PEGGY from the locker) slides
## the one under it out to the LEFT, and brings it back the same way.
##
## The frame is the design's 654 × 1234 at (30, 20) with a 20 px pad; the
## pieces inside are the see-through dotted style (ShadowCard / ShadowPanel)
## with cream outlined words, on every palette: the page sits over the court,
## so it wears the scene colours like the league context does. Subclasses
## build their rows into `body` from `_build()`.

signal closed

const OPEN_S := 0.3
const FRAME_POS := Vector2(30, 20)
const FRAME_SIZE := Vector2(654, 1234)
const PAD := 20.0
const WASH := Color(5.0 / 255.0, 5.0 / 255.0, 13.0 / 255.0, 0.34)
const SLIDE := 1.1 * 720.0
const CREAM := RetroTheme.SCENE_TEXT
const HEAD_H := 52.0
const CLOSE_H := 64.0
## The tall rows of the 2026-10-30 "Store and Locker" pass: BACK, PLAY PEGGY.
const TALL_H := 84.0
const TICKETS_SIZE := Vector2(150, 104)

var wash: ColorRect
var root: Control
var body: VBoxContainer
var balance: CoinsPill
var _ticket_count: Label
var _slide: Tween


func _init() -> void:
	layer = 30
	UiLayout.anchor_layer(self)   # the frame runs the full screen height (_layout_frame)


func _ready() -> void:
	wash = ColorRect.new()
	wash.name = "Wash"
	wash.color = WASH
	UiLayout.full_rect(wash)
	wash.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(wash)
	root = Control.new()
	root.name = "Frame"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	body = VBoxContainer.new()
	body.name = "Body"
	body.position = Vector2(PAD, PAD)
	_layout_frame()
	if is_inside_tree():
		get_tree().root.size_changed.connect(_layout_frame)
	body.add_theme_constant_override("separation", _row_gap())
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(body)
	_build()


## The frame on this screen (design "Store and Locker", 2026-10-24): 20 px
## under the screen's top edge to 26 px above its bottom, 654 wide, so the
## page runs the full height and CLOSE sits at the foot. A page that lays its
## block out in absolute 1234-tall coordinates (`_anchored()` false) keeps
## the centred band frame instead.
func _layout_frame() -> void:
	if root == null:
		return
	if _anchored():
		var top := UiLayout.header_top(FRAME_POS.y)   # under the top safe area (the notch)
		root.position = Vector2(FRAME_POS.x, top)
		root.size = Vector2(FRAME_SIZE.x, UiLayout.screen_height() - top - 26.0)
	else:
		root.position = FRAME_POS
		root.size = FRAME_SIZE
	body.size = root.size - Vector2(2.0 * PAD, 2.0 * PAD)
	if _anchored() and _flush_top():
		# The rows start at the top safe area itself (118 on an iPhone), or
		# at the usual 40 without a notch.
		body.position.y = UiLayout.header_top(FRAME_POS.y + PAD) - root.position.y
		body.size.y = root.size.y - body.position.y - PAD


## Whether the body's first row sits right at the top safe area instead of
## a pad under it (the locker and PEGGY since the 2026-10-30 redesign).
func _flush_top() -> bool:
	return false


## Whether the frame follows the screen's edges (most pages) or stays the 1234-tall band.
func _anchored() -> bool:
	return true


func frame_height() -> float:
	return root.size.y if root != null else FRAME_SIZE.y


## The space between the rows (the locker 28, PEGGY 24).
func _row_gap() -> int:
	return 24


## Subclasses fill `body` here.
func _build() -> void:
	pass


## A subclass with a live viewport pauses it while hidden under another page.
func set_view_active(_on: bool) -> void:
	pass


# ---- the pieces ----------------------------------------------------------------


## TITLE ............ [ticket chip] [extras]: the top row (`with_chip` false
## for a page with no money on it, like settings).
func head(title: String, with_chip := true) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Head"
	h.custom_minimum_size = Vector2(0, HEAD_H)
	h.add_theme_constant_override("separation", 16)
	body.add_child(h)
	var t := RetroTheme.display(title, 32, CREAM)
	t.name = "Title"
	RetroTheme.on_scene(t)
	RetroTheme.dithered(t)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	balance = CoinsPill.new()
	balance.name = "Balance"
	balance.custom_minimum_size = Vector2(120, 48 + ShadowStyle.OFFSET)
	var coin: PixelIcon = balance.find_child("Coin", true, false)
	if coin != null:
		coin.icon_name = "icon_ticket"
		coin.custom_minimum_size = Vector2(22, 14)
	balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	balance.visible = with_chip
	h.add_child(balance)
	set_tickets()
	return h


func set_tickets() -> void:
	if balance != null:
		balance.set_coins(App.tickets())
	if _ticket_count != null:
		_ticket_count.text = RetroTheme.thousands(App.tickets())


## The big ticket panel (design 31a / 30a, 2026-10-30): a 150 × 104 gold
## face, the ticket and the count over TICKETS.
func ticket_panel() -> ShadowPanel:
	var p := ShadowPanel.new(RetroTheme.LIGHT["gold"], 0.0, 0.35)
	p.name = "Tickets"
	p.custom_minimum_size = TICKETS_SIZE + Vector2.ONE * ShadowStyle.OFFSET
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := VBoxContainer.new()
	col.name = "Col"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	p.add_child(col)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var icon := PixelIcon.new("icon_ticket", Vector2(34, 22), 2.0)
	icon.name = "Icon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_ticket_count = words("", 24, true)
	_ticket_count.name = "Count"
	row.add_child(_ticket_count)
	var l := words("TICKETS", 14)
	l.name = "Label"
	col.add_child(l)
	set_tickets()
	return p


## `< BACK` (the locker's foot, PEGGY's head; design 31a / 30a, 2026-10-30):
## a cream face `height` tall, the chevron and the word centred on it.
func back_button(word_px: int, chevron_px: int, gap: int, height := TALL_H) -> ShadowCard:
	var b := ShadowCard.new(CREAM)
	b.name = "Back"
	b.custom_minimum_size = Vector2(0, height + ShadowStyle.OFFSET)
	var row := HBoxContainer.new()
	row.name = "Row"
	UiLayout.full_rect(row)
	row.offset_right = -ShadowStyle.OFFSET
	row.offset_bottom = -ShadowStyle.OFFSET
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", gap)
	b.add_child(row)
	var chev := words("<", chevron_px, true)
	chev.name = "Chevron"
	row.add_child(chev)
	var w := words("BACK", word_px, true)
	w.name = "Word"
	row.add_child(w)
	b.pressed.connect(close)
	return b


## A see-through dotted button with its words as its own text (the tabs,
## the sub-tabs, CLOSE, the card's buttons).
static func button(text: String, colour: Color, size_: int, height: float) -> ShadowCard:
	var b := ShadowCard.new(colour)
	b.text = text
	b.add_theme_font_override("font", UiFont.display())
	b.add_theme_font_size_override("font_size", UiFont.snap(size_))
	RetroTheme.on_scene(b)
	b.custom_minimum_size = Vector2(0, height + ShadowStyle.OFFSET)
	return b


## A see-through dotted chip with words that are not a button (the section
## heads): bold body text in a cream frame, hugging its words.
static func chip(text: String, size_ := 16, height := 40.0) -> ShadowPanel:
	var p := ShadowPanel.new(CREAM, 0.0, ShadowStyle.TINT, 14.0)
	p.custom_minimum_size = Vector2(0, height + ShadowStyle.OFFSET)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := RetroTheme.caps(text, size_, CREAM)
	l.name = "Text"
	RetroTheme.on_scene(l)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## A cream outlined label (every word on a page).
static func words(text: String, size_: int, display := false) -> Label:
	var l := RetroTheme.display(text, size_, CREAM) if display else RetroTheme.caps(text, size_, CREAM)
	RetroTheme.on_scene(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The full-width dotted CLOSE at the foot of the frame.
func close_button() -> ShadowCard:
	var b := button("CLOSE", CREAM, 24, CLOSE_H)
	b.name = "Close"
	b.pressed.connect(close)
	body.add_child(b)
	return b


# ---- the move ------------------------------------------------------------------


## Slide the frame in (from the right, or back from the left when a page
## over this one closes) and fade the wash up.
## `delay` holds the frame off-screen that long first (the season wrap-up
## follows the home out by 0.35 s, design 39c).
## How dark the wash over the area gets (NEW PLAYER keeps the splash's
## wall bare, design 35a 2026-10-30).
func wash_alpha() -> float:
	return WASH.a


func slide_in(from_left := false, delay := 0.0) -> void:
	visible = true
	set_view_active(true)
	if root == null or not is_inside_tree():
		return
	_stop()
	root.position.x = FRAME_POS.x + (-SLIDE if from_left else SLIDE)
	wash.color.a = 0.0
	_slide = create_tween()
	if delay > 0.0:
		_slide.tween_interval(delay)
	_slide.set_parallel(true)
	_slide.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slide.tween_property(root, "position:x", FRAME_POS.x, OPEN_S)
	_slide.tween_property(wash, "color:a", wash_alpha(), OPEN_S)


## Slide the frame out (to the right, or to the left under a page opening
## over this one) and fade the wash down. `free` ends the page: `closed`
## then queue_free; otherwise it hides and waits for slide_in(true).
func slide_out(to_left := false, free := true) -> void:
	if root == null or not is_inside_tree():
		_after_out(free)
		return
	_stop()
	_slide = create_tween().set_parallel(true)
	_slide.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slide.tween_property(root, "position:x", FRAME_POS.x + (-SLIDE if to_left else SLIDE), OPEN_S)
	_slide.tween_property(wash, "color:a", 0.0, OPEN_S)
	_slide.chain().tween_callback(_after_out.bind(free))


func _after_out(free: bool) -> void:
	if free:
		closed.emit()
		queue_free()
	else:
		set_view_active(false)
		visible = false


func _stop() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = null


func close() -> void:
	slide_out(false, true)
