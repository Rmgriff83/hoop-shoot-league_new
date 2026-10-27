class_name SeasonPage
extends HomePage
## The base of the two season pages (design "Season Moments" 39c/e/f and
## 39d, docs/HOME.md → Season wrap-up and new season): a HomePage whose
## content is laid out in absolute design coordinates on a 642 × PAGE_H
## sheet (the design's 36 … 678 column), inside a scroll for a short screen,
## and whose elements are scheduled by one clock (`step(dt)`, the match-end
## page's recipe) — rise, pop, fade, deal, roll, strike, count.

const W := 642.0
const PAGE_H := 1440.0
const INK := Color("#221C18")
const DARK := Color("#14100E")
const GOLD := SeasonCopy.GOLD
const ORANGE := SeasonCopy.ORANGE

var _v: Dictionary = {}
var _t := 0.0
var _anims: Array = []
var _sheet: Control
var _buttons: Array = []   # [{node, at}]: a button takes taps once risen
var _sound_done := {}


func build(v: Dictionary) -> Control:
	_v = v.duplicate(true)
	if root == null:
		_ready()
	else:
		_build()
	return root


func _ready() -> void:
	if root != null:
		return
	super()


func _build() -> void:
	_t = 0.0
	_anims.clear()
	_buttons.clear()
	_sound_done.clear()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	body.position = Vector2(6.0, 0.0)
	body.size = root.size - Vector2(12.0, 0.0)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(scroll)
	_sheet = Control.new()
	_sheet.name = "Sheet"
	_sheet.custom_minimum_size = Vector2(W, PAGE_H)
	_sheet.size = _sheet.custom_minimum_size
	_sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(_sheet)
	_fill()
	step(0.0)


## The frame's pad is the sheet's own margin.
func _layout_frame() -> void:
	super()
	if body != null and _sheet != null:
		body.position = Vector2(6.0, 0.0)
		body.size = root.size - Vector2(12.0, 0.0)


## Subclasses lay their elements on `_sheet` here.
func _fill() -> void:
	pass


# ---- the pieces ----------------------------------------------------------------


func _label(text: String, size_: int, color: Color, display := true) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A control on the sheet (or inside a panel's inner layout) at a rect.
func _put(l: Control, x: float, y: float, w: float, h: float, parent: Control = null) -> Control:
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	var into := parent if parent != null else _sheet
	if into is PanelContainer:
		into = _inner(into)
	into.add_child(l)
	return l


## A panel's free-layout child (a PanelContainer lays its own children over
## its whole rect, so absolute positions go on this one).
func _inner(panel: Control) -> Control:
	var inner: Control = panel.get_node_or_null("Inner")
	if inner == null:
		inner = Control.new()
		inner.name = "Inner"
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(inner)
	return inner


## A centred label across the sheet.
func _centred(l: Control, y: float, h := 40.0, parent: Control = null) -> Control:
	return _put(l, 0.0, y, W, h, parent)


## A see-through dotted panel in a colour, at a rect, pivot centred.
## (`pad` is the design's inset; the children are placed in absolute
## coordinates that already include it, so the stylebox carries none.)
func _panel(colour: Color, x: float, y: float, w: float, h: float, _pad := 0.0, tint := ShadowStyle.TINT) -> ShadowPanel:
	var p := ShadowPanel.new(colour, 0.0, tint, 0.0)
	p.position = Vector2(x, y)
	p.size = Vector2(w, h)
	p.pivot_offset = Vector2(w * 0.5, h * 0.5)
	_sheet.add_child(p)
	_inner(p)
	return p


## A title-and-sub card button (ModeCards.text_card) at a rect; it takes
## taps once risen at `at`.
func _card_button(title: String, sub: String, colour: Color, x: float, y: float, w: float, h: float, at: float, chevron := true, title_size := 22) -> Button:
	var b := ModeCards.text_card(title, sub, colour, title_size, chevron)
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.custom_minimum_size = Vector2(w, h)
	b.pivot_offset = Vector2(w * 0.5, h * 0.5)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(b)
	_buttons.push_back({"node": b, "at": at})
	_anim(b, "rise", at, 0.4)
	return b


## A plain dotted button with one word (LATER, X).
func _word_button(text: String, x: float, y: float, w: float, h: float, at: float, size_ := 20) -> ShadowCard:
	var b := HomePage.button(text, CREAM, size_, h - ShadowStyle.OFFSET)
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.custom_minimum_size = Vector2(w, h)
	b.pivot_offset = Vector2(w * 0.5, h * 0.5)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(b)
	_buttons.push_back({"node": b, "at": at})
	if at > 0.0:
		_anim(b, "rise", at, 0.4)
	return b


# ---- the clock ------------------------------------------------------------------


func _anim(node: CanvasItem, kind: String, delay: float, dur: float, extra := 0.0) -> void:
	var base := Vector2.ZERO
	if node is Control:
		base = (node as Control).position
	_anims.push_back({"node": node, "kind": kind, "delay": delay, "dur": dur, "base": base, "extra": extra})
	if kind in ["rise", "pop", "fadein", "dealin", "infrom"]:
		node.modulate.a = 0.0


static func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 3.0)


static func _ease_in(p: float) -> float:
	return p * p * p


## Advance the page by dt and lay every scheduled element where it belongs.
func step(dt: float) -> void:
	_t += dt
	for b in _buttons:
		var node: Control = b["node"]
		if is_instance_valid(node):
			node.mouse_filter = Control.MOUSE_FILTER_STOP if _t >= float(b["at"]) else Control.MOUSE_FILTER_IGNORE
	for a in _anims:
		var node: CanvasItem = a["node"]
		if not is_instance_valid(node):
			continue
		var delay := float(a["delay"])
		var dur := maxf(float(a["dur"]), 1e-4)
		var p := clampf((_t - delay) / dur, 0.0, 1.0)
		var base: Vector2 = a["base"]
		var c := node as Control
		match str(a["kind"]):
			"rise":
				node.modulate.a = p
				if c != null:
					c.position = base + Vector2(0, 36.0 * (1.0 - _ease_out(p)))
			"fadein":
				node.modulate.a = p * (float(a["extra"]) if float(a["extra"]) > 0.0 else 1.0)
			"pop":
				node.modulate.a = 1.0 if p > 0.0 else 0.0
				if c != null:
					var s := 0.0
					if p < 0.65:
						s = 1.18 * (p / 0.65)
					else:
						s = 1.18 - 0.18 * ((p - 0.65) / 0.35)
					c.scale = Vector2.ONE * s
			"dealin":
				node.modulate.a = p
				if c != null:
					c.position = base + Vector2(float(a["extra"]) * (1.0 - _ease_out(p)), 0)
					c.rotation = deg_to_rad(5.0 * (1.0 - _ease_out(p)))
			"strike":
				if c != null:
					c.size.x = float(a["extra"]) * _ease_out(p)
			"outup":
				if c != null:
					c.position = base + Vector2(0, -float(a["extra"]) * _ease_in(p))
			"infrom":
				node.modulate.a = 1.0 if p > 0.0 else 0.0
				if c != null:
					# Ease out with a small overshoot past the mark (the design's 1.3 back-ease).
					var k := _ease_out(p) + 0.12 * sin(p * PI) * p
					c.position = base + Vector2(0, -float(a["extra"]) * k)
	_tick()


## Subclasses count and chime here.
func _tick() -> void:
	pass


func _sound_once(key: String, at: float, fn: Callable) -> void:
	if _t >= at and not _sound_done.has(key):
		_sound_done[key] = true
		fn.call()


func _process(delta: float) -> void:
	step(delta)


func clock() -> float:
	return _t


func sheet() -> Control:
	return _sheet


func buttons_shown() -> bool:
	for b in _buttons:
		if _t < float(b["at"]):
			return false
	return not _buttons.is_empty()
