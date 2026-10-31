class_name FloatCards
extends Control
## YOUR CARDS on the home while the league's CARDS tab is open (design "Home
## League Context v2", 2026-10-30): `YOUR CARDS · n AVAILABLE` over every
## card you own in this league — 96×128 with its ×n badge off the top-right
## corner — in a row that scrolls sideways out to the screen's right edge,
## with a fade at whichever end has more. A card bought in the shop flies
## into it (the title runs the flight): an owned kind's badge bumps
## (`bump`), a new kind's slot grows open (`grow`).

const CARD := Vector2(96, 128)
const SHADOW := 6.0
const GAP := 28.0           # between faces (the art's shadow sits inside it)
const PAD_TOP := 16.0
const PAD_BOTTOM := 14.0
const PAD_END := 36.0       # the row's end clears the screen edge
const WIDTH := 720.0 - 36.0  # from the margin out to the screen's edge
const FADE_L := 56.0
const FADE_R := 96.0
const BG := Color("#1B1815")

var league_id := ""
var _count: Label
var _scroll: ScrollContainer
var _row: HBoxContainer
var _fade_l: TextureRect
var _fade_r: TextureRect
var _slots: Dictionary = {}   # card id → its slot Control
var _anim: Dictionary = {}    # card id → {kind: "bump" | "grow", t}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func build(id: String) -> void:
	league_id = id
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_slots.clear()
	size = Vector2(WIDTH, 0)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	head.add_child(_text("YOUR CARDS", 22, RetroTheme.SCENE_TEXT, true))
	_count = _text("", 18, RetroTheme.SCENE_MUTED)
	_count.name = "Count"
	_count.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_count)
	head.position = Vector2.ZERO
	head.size = Vector2(WIDTH, UiFont.snap(22) + 2.0 * RetroTheme.OUTLINE)
	var strip_y := head.size.y + 14.0 - PAD_TOP + 2.0
	var strip_h := PAD_TOP + CARD.y + SHADOW + PAD_BOTTOM
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.position = Vector2(0, strip_y)
	_scroll.size = Vector2(WIDTH, strip_h)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", int(PAD_TOP))
	pad.add_theme_constant_override("margin_bottom", int(PAD_BOTTOM))
	pad.add_theme_constant_override("margin_right", int(PAD_END))
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(pad)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", int(GAP - SHADOW))
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(_row)
	var cd := App.cards_bucket(league_id)
	for card in CardDefs.all():
		var n := CardDefs.owned(cd, str(card["id"]))
		if n > 0:
			_row.add_child(_slot(card, n))
	if _row.get_child_count() == 0:
		var none := _text("NONE YET · THE SHOP IS BELOW", 18, RetroTheme.SCENE_MUTED)
		none.name = "None"
		none.custom_minimum_size = Vector2(0, CARD.y)
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_row.add_child(none)
	_fade_l = _fade(FADE_L, true)
	_fade_l.position = Vector2(0, strip_y)
	_fade_r = _fade(FADE_R, false)
	_fade_r.position = Vector2(WIDTH - FADE_R, strip_y)
	size.y = strip_y + strip_h
	_recount()


## Every card id in the row, in order.
func ids() -> Array:
	var out := []
	for c in _row.get_children():
		if c.has_meta("card"):
			out.push_back(str(c.get_meta("card")))
	return out


func count_of(id: String) -> int:
	return int(_slots[id].get_meta("n")) if _slots.has(id) else 0


## The face of `id`'s slot in global coordinates (Rect2() when not in the row).
func slot_rect(id: String) -> Rect2:
	if not _slots.has(id):
		return Rect2()
	var c: Control = _slots[id]
	return Rect2(c.get_global_rect().position, CARD)


func has(id: String) -> bool:
	return _slots.has(id)


## A new kind's slot, open at 0 width (it grows when the flying card lands),
## scrolled into view; returns its eventual face rect (global).
func make_room(id: String) -> Rect2:
	var card := CardDefs.get_card(id)
	if card.is_empty() or _slots.has(id):
		return slot_rect(id)
	var order := []
	for c in CardDefs.all():
		order.push_back(str(c["id"]))
	var at := 0
	for i in _row.get_child_count():
		var other := str(_row.get_child(i).get_meta("card", ""))
		if other != "" and order.find(other) < order.find(id):
			at = i + 1
	var none := _row.get_node_or_null("None")
	if none != null:
		_row.remove_child(none)
		none.queue_free()
	var s := _slot(card, 1)
	s.modulate.a = 0.0
	_row.add_child(s)
	_row.move_child(s, at)
	_set_grow(s, 0.0)
	# Where it will sit once open: scroll so that spot is in view.
	var x := at * (CARD.x + GAP)
	if x < _scroll.scroll_horizontal or x + CARD.x > _scroll.scroll_horizontal + WIDTH - PAD_END:
		_scroll.scroll_horizontal = maxi(0, int(x - (WIDTH - CARD.x) * 0.5))
	var origin := _scroll.get_global_rect().position + Vector2(x - _scroll.scroll_horizontal, PAD_TOP)
	return Rect2(origin, CARD)


## The flying card landed on an owned kind: one more, the badge bumps.
func bump(id: String) -> void:
	if not _slots.has(id):
		return
	var s: Control = _slots[id]
	s.set_meta("n", int(s.get_meta("n")) + 1)
	(s.get_node("Badge/Text") as Label).text = "×%d" % int(s.get_meta("n"))
	_anim[id] = {"kind": "bump", "t": 0.0}
	_recount()


## …or on a new kind: its slot grows open and shows.
func grow(id: String) -> void:
	if not _slots.has(id):
		return
	(_slots[id] as Control).modulate.a = 1.0
	_anim[id] = {"kind": "grow", "t": 0.0}
	_recount()


func _process(dt: float) -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_h_scroll_bar()
	_fade_l.visible = _scroll.scroll_horizontal > 4
	_fade_r.visible = bar.max_value - bar.page - _scroll.scroll_horizontal > 4.0
	for id in _anim.keys():
		var a: Dictionary = _anim[id]
		a["t"] = float(a["t"]) + dt
		if not _slots.has(id):
			_anim.erase(id)
			continue
		var s: Control = _slots[id]
		if a["kind"] == "bump":
			var badge: Control = s.get_node("Badge")
			badge.pivot_offset = badge.size * 0.5
			badge.scale = Vector2.ONE * CssEase.cnt_bump(float(a["t"]))
			if float(a["t"]) >= CssEase.BUMP_S:
				_anim.erase(id)
		else:
			_set_grow(s, float(a["t"]))
			if float(a["t"]) >= CssEase.GROW_S:
				_anim.erase(id)


## slotGrow: the slot's width 0 → 96 on the snap curve (the design also
## pulls the gap in; a box's gap here is fixed, so the slot grows alone).
func _set_grow(s: Control, t: float) -> void:
	var g := CssEase.slot_grow(t)
	s.custom_minimum_size.x = (CARD.x + SHADOW) * g.x / CARD.x
	s.clip_contents = g.x < CARD.x


func _recount() -> void:
	var n := 0
	for id in _slots:
		if (_slots[id] as Control).modulate.a > 0.0:
			n += int(_slots[id].get_meta("n"))
	_count.text = "%d AVAILABLE" % n


func _slot(card: Dictionary, n: int) -> Control:
	var id := str(card["id"])
	var holder := Control.new()
	holder.name = "Own_" + id
	holder.set_meta("card", id)
	holder.set_meta("n", n)
	holder.custom_minimum_size = CARD + Vector2.ONE * SHADOW
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var art := ModeCards.art(card, CARD, SHADOW)
	art.name = "Art"
	holder.add_child(art)
	if not Progression.can_use(App.level(), card):
		# Owned early (docs/PROGRESSION.md): it waits, dimmed, with its level.
		(art.get_node("Face") as Control).modulate = Color(0.55, 0.55, 0.6, 1.0)
		var lock := PanelContainer.new()
		lock.name = "Lock"
		var lsb := StyleBoxFlat.new()
		lsb.bg_color = Color(RetroTheme.SCENE_OUTLINE, 0.85)
		lsb.border_color = RetroTheme.SCENE_TEXT
		lsb.set_border_width_all(2)
		lsb.set_content_margin_all(4)
		lsb.content_margin_left = 8
		lsb.content_margin_right = 8
		lock.add_theme_stylebox_override("panel", lsb)
		lock.position = Vector2(6, CARD.y - 34)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.add_child(UiFont.label("LVL %d" % Progression.card_level(card), 14, RetroTheme.SCENE_TEXT, UiFont.body_bold()))
		holder.add_child(lock)
	var badge := PanelContainer.new()
	badge.name = "Badge"
	var sb := StyleBoxFlat.new()
	sb.bg_color = RetroTheme.SCENE_OUTLINE
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	badge.add_theme_stylebox_override("panel", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var txt := UiFont.label("×%d" % n, 18, RetroTheme.SCENE_TEXT)
	txt.name = "Text"
	badge.add_child(txt)
	var bw := UiFont.display().get_string_size("×%d" % maxi(n, 9), HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(18)).x + 16.0
	badge.position = Vector2(CARD.x + 10.0 - bw, -10.0)
	holder.add_child(badge)
	_slots[id] = holder
	return holder


func _fade(w: float, left: bool) -> TextureRect:
	var r := TextureRect.new()
	r.name = "FadeL" if left else "FadeR"
	var grad := Gradient.new()
	grad.set_color(0, Color(BG, 0.85) if left else Color(BG, 0.0))
	grad.set_color(1, Color(BG, 0.0) if left else Color(BG, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = Vector2(w, PAD_TOP + CARD.y + SHADOW + PAD_BOTTOM)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	add_child(r)
	return r


func _text(text: String, size_: int, color: Color, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l
