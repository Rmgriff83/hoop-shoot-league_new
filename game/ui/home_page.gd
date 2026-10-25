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

var wash: ColorRect
var root: Control
var body: VBoxContainer
var balance: CoinsPill
var _slide: Tween


func _init() -> void:
	layer = 30


func _ready() -> void:
	wash = ColorRect.new()
	wash.name = "Wash"
	wash.color = WASH
	UiLayout.full_rect(wash)
	wash.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(wash)
	root = Control.new()
	root.name = "Frame"
	root.position = FRAME_POS
	root.size = FRAME_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	body = VBoxContainer.new()
	body.name = "Body"
	body.position = Vector2(PAD, PAD)
	body.size = FRAME_SIZE - Vector2(2.0 * PAD, 2.0 * PAD)
	body.add_theme_constant_override("separation", _row_gap())
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(body)
	_build()


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
func slide_in(from_left := false) -> void:
	visible = true
	set_view_active(true)
	if root == null or not is_inside_tree():
		return
	_stop()
	root.position.x = FRAME_POS.x + (-SLIDE if from_left else SLIDE)
	wash.color.a = 0.0
	_slide = create_tween().set_parallel(true)
	_slide.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slide.tween_property(root, "position:x", FRAME_POS.x, OPEN_S)
	_slide.tween_property(wash, "color:a", WASH.a, OPEN_S)


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
