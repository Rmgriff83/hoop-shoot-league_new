class_name AreaUnlockPage
extends CanvasLayer
## The Area Unlock page (design "Area Unlock" 18a, 2026-10-05; docs/HOME.md
## → Area unlock): plays the moment a league match's XP reaches an area's
## level, after the match-end page and before the post-match page. Over a
## snapshot of the real 3D area (darkened): a LEVEL n REACHED chip, the area's
## picture in a cream frame under a near-opaque dotted veil with the gold
## lock in its centre; the lock rattles, the shackle springs open on a flash
## and a ring, the veil fades off the picture, the lock flies away and rays
## in the area's colour turn behind it; NEW AREA slams in, then the stars
## and the name, then chips for what opens there, then GO THERE (that area's
## home) or LATER. One clock (`step(dt)`) lays every element, as the match-end
## page does, so the timeline is tested headless.

signal go_there(area: String)
signal later

const W := 720.0
const H := 1280.0
const INK := Color("#221C18")
const DARK := Color("#14100E")
const CREAM := Color("#F1E8D0")
const GOLD := Color("#F0B84A")
const FLASH := Color("#FFF3D0")
const FRAME_POS := Vector2(60, 300)
const FRAME_SIZE := Vector2(600, 340)
const LOCK_SIZE := Vector2(168, 204)
const LOCK_PIVOT := Vector2(84, 41)   # the shackle: 20 % down
const CHIP_Y := 120.0
const TITLE_Y := 688.0
const NAME_Y := 784.0
const OPENS_Y := 910.0
const BUTTONS_Y := 1030.0
const BUTTON_H := 110.0
const LATER_W := 200.0
const BUTTONS_AT := 3.2
const T_OPEN := 1.55
const T_SNAP := 0.0

var _v := {}
var _root: Control
var _t := 0.0
var _anims: Array[Dictionary] = []
var _rays: PrizeRays
var _confetti: Confetti
var _lock: Control
var _lock_closed: PixelIcon
var _lock_open: PixelIcon
var _buttons: Array[Control] = []
var _sound_done := false


func _init() -> void:
	layer = 45


# ---- build ----------------------------------------------------------------------


func build(v: Dictionary) -> Control:
	_v = v
	_t = 0.0
	_anims.clear()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "AreaUnlockPage"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# The real area behind everything (the tall render, else the card's), darkened.
	var bg := TextureRect.new()
	bg.name = "Bg"
	bg.texture = _snap(str(v.get("snap_tall", "")), str(v.get("snap", "")))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(DARK, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	# Rays in the area's colour, behind the frame, from the reveal on.
	_rays = PrizeRays.new(v.get("ray", GOLD))
	_rays.name = "Rays"
	_rays.position = Vector2(W * 0.5 - 800.0, 470.0 - 800.0)
	_rays.size = Vector2(1600, 1600)
	_rays.speed_deg = 360.0 / 22.0
	_rays.alpha = 0.32
	_root.add_child(_rays)
	_anim(_rays, "fadein", 1.6, 0.6)
	_confetti = Confetti.new(60, Array(v.get("palette", [])), 5 if str(v.get("id", "")) == "beach" else 9)
	_confetti.name = "Confetti"
	_confetti.visible = false
	_root.add_child(_confetti)
	_anim(_confetti, "show", 1.7, 0.0)
	# LEVEL n REACHED.
	var chip := _chip(str(v.get("level_text", "")), GOLD, "", 0.6)
	chip.name = "LevelChip"
	_centre_min(chip, CHIP_Y)
	_anim(chip, "rise", 0.15, 0.4)
	# The frame: ink shadow, the picture, the veil, the flash, the border.
	var frame := Control.new()
	frame.name = "Frame"
	frame.position = FRAME_POS
	frame.size = FRAME_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)
	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = INK
	shadow.position = Vector2(8, 8)
	shadow.size = FRAME_SIZE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(shadow)
	var face := Control.new()
	face.name = "Face"
	face.size = FRAME_SIZE
	face.clip_contents = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(face)
	var snap := TextureRect.new()
	snap.name = "Snap"
	snap.texture = _snap(str(v.get("snap", "")), str(v.get("snap_tall", "")))
	snap.set_anchors_preset(Control.PRESET_FULL_RECT)
	snap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	snap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	snap.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	snap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(snap)
	var veil := TextureRect.new()
	veil.name = "Veil"
	veil.texture = ShadowStyle.dot_tex()
	veil.stretch_mode = TextureRect.STRETCH_TILE
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.self_modulate = Color(CREAM, 0.3)
	var veil_fill := ColorRect.new()
	veil_fill.name = "VeilFill"
	veil_fill.color = Color(DARK, 0.9)
	veil_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(veil_fill)
	face.add_child(veil)
	_anim(veil_fill, "fadeout", 1.6, 0.5)
	_anim(veil, "fadeout", 1.6, 0.5)
	var frame_flash := ColorRect.new()
	frame_flash.name = "FrameFlash"
	frame_flash.color = FLASH
	frame_flash.modulate.a = 0.0
	frame_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(frame_flash)
	_anim(frame_flash, "flash", T_OPEN, 0.5, 1.0)
	var border := PanelContainer.new()
	border.name = "Border"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = CREAM
	sb.set_border_width_all(3)
	border.add_theme_stylebox_override("panel", sb)
	border.size = FRAME_SIZE
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(border)
	_anim(frame, "rise", 0.1, 0.4)
	_anim(frame, "bump", 1.55, 0.35)
	# The ring and the lock, centred on the frame.
	var centre := FRAME_POS + FRAME_SIZE * 0.5
	var ring := Ring.new()
	ring.name = "Ring"
	ring.position = centre - Vector2(100, 100)
	ring.size = Vector2(200, 200)
	ring.pivot_offset = Vector2(100, 100)
	ring.modulate.a = 0.0
	_root.add_child(ring)
	_anim(ring, "ring", T_OPEN, 0.6)
	_lock = Control.new()
	_lock.name = "Lock"
	_lock.position = centre - LOCK_SIZE * 0.5
	_lock.size = LOCK_SIZE
	_lock.pivot_offset = LOCK_PIVOT
	_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lock)
	_lock_closed = PixelIcon.new("lock_closed", LOCK_SIZE, 8.0)
	_lock_closed.name = "LockClosed"
	_lock.add_child(_lock_closed)
	_lock_open = PixelIcon.new("lock_open", LOCK_SIZE, 8.0)
	_lock_open.name = "LockOpen"
	_lock_open.visible = false
	_lock.add_child(_lock_open)
	_anim(_lock, "pop", 0.45, 0.45)
	_anim(_lock, "rattle", 0.95, 0.6)
	_anim(_lock_closed, "hide", T_OPEN, 0.0)
	_anim(_lock_open, "show", T_OPEN, 0.0)
	_anim(_lock_open, "spring", T_OPEN, 0.25)
	_anim(_lock, "away", 1.75, 0.45)
	# NEW AREA.
	var title := _label(str(v.get("title", "NEW AREA")), 52, GOLD)
	title.name = "Title"
	RetroTheme.dithered(title, Vector2(8, 8))
	_centre(title, TITLE_Y, W, 60.0)
	title.pivot_offset = Vector2(W * 0.5, 30.0)
	_anim(title, "slam", 2.05, 0.6)
	# Stars + the name.
	var col := VBoxContainer.new()
	col.name = "NameBlock"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stars := HBoxContainer.new()
	stars.name = "Stars"
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.add_theme_constant_override("separation", 8)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in int(v.get("stars", 1)):
		stars.add_child(PixelIcon.new("icon_star", Vector2(28, 28), 3.0))
	col.add_child(stars)
	var name_l := _label(str(v.get("name", "")), 36, CREAM)
	name_l.name = "Name"
	col.add_child(name_l)
	_centre(col, NAME_Y, W, 100.0)
	_anim(col, "rise", 2.45, 0.4)
	# What opens there.
	var opens := HBoxContainer.new()
	opens.name = "Opens"
	opens.alignment = BoxContainer.ALIGNMENT_CENTER
	opens.add_theme_constant_override("separation", 14)
	opens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := 0
	for o in v.get("opens", []):
		var c := _chip(str(o["text"]), o["color"], str(o["icon"]), 0.55)
		c.name = "Open_%s" % str(o["text"]).replace(" ", "_")
		c.pivot_offset = Vector2(40, 22)
		opens.add_child(c)
		_anim(c, "pop", 2.75 + 0.15 * k, 0.35)
		k += 1
	_centre(opens, OPENS_Y, W, 44.0)
	# GO THERE / LATER.
	var go := ShadowCard.new(RetroTheme.LIGHT["orange"])
	go.name = "GoThere"
	go.position = Vector2(36, BUTTONS_Y)
	go.size = Vector2(W - 36 - 42 - 26 - LATER_W, BUTTON_H) + Vector2.ONE * ShadowStyle.OFFSET
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 26
	row.offset_right = -(26 + ShadowStyle.OFFSET)
	row.offset_bottom = -ShadowStyle.OFFSET
	row.add_theme_constant_override("separation", 16)
	go.add_child(row)
	var gcol := VBoxContainer.new()
	gcol.alignment = BoxContainer.ALIGNMENT_CENTER
	gcol.add_theme_constant_override("separation", 14)
	gcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gt := _label(str(v.get("go", "GO THERE")), 24, CREAM)
	gt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gt.name = "GoTitle"
	gcol.add_child(gt)
	var gs := _label(str(v.get("go_sub", "")), 16, CREAM, false)
	gs.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gs.name = "GoSub"
	gcol.add_child(gs)
	row.add_child(gcol)
	var chev := _label(">", 32, CREAM)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chev)
	go.pressed.connect(func() -> void: go_there.emit(str(_v.get("id", ""))))
	_root.add_child(go)
	var lt := ShadowCard.new(CREAM)
	lt.name = "Later"
	lt.tint = 0.14
	lt.position = Vector2(W - 42 - LATER_W, BUTTONS_Y)
	lt.size = Vector2(LATER_W, BUTTON_H) + Vector2.ONE * ShadowStyle.OFFSET
	lt.text = str(v.get("later", "LATER"))
	lt.add_theme_font_override("font", UiFont.display())
	lt.add_theme_font_size_override("font_size", UiFont.snap(20))
	RetroTheme.on_scene(lt)
	lt.pressed.connect(func() -> void: later.emit())
	_root.add_child(lt)
	_buttons = [go, lt]
	for b in _buttons:
		_anim(b, "rise", BUTTONS_AT, 0.4)
	# The whole-screen flash at the moment the shackle springs.
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.color = FLASH
	flash.modulate.a = 0.0
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(flash)
	_anim(flash, "flash", T_OPEN, 0.3, 0.35)
	step(0.0)
	return _root


func _snap(first: String, second: String) -> Texture2D:
	for p in [first, second]:
		if p != "" and ResourceLoader.exists(p):
			return load(p)
	return null


func _label(text: String, size_: int, color: Color, display := true) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A 44 px chip: 2 px border in the colour, dark fill, a 5 px ink shadow, an optional 20 px icon.
func _chip(text: String, color: Color, icon: String, fill_alpha: float) -> PanelContainer:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DARK, fill_alpha)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.shadow_color = INK
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(5, 5)
	sb.content_margin_left = 14 if icon != "" else 16
	sb.content_margin_right = 14 if icon != "" else 16
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	pill.add_theme_stylebox_override("panel", sb)
	pill.custom_minimum_size = Vector2(0, 44)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10 if icon != "" else 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != "":
		var ic := PixelIcon.new(icon, Vector2(20, 20))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := _label(text, 16, CREAM, false)
	row.add_child(l)
	pill.add_child(row)
	return pill


func _centre(c: Control, y: float, w: float, h: float) -> void:
	c.position = Vector2((W - w) * 0.5, y)
	c.size = Vector2(w, h)
	_root.add_child(c)


## Centre a container by its minimum width.
func _centre_min(c: Control, y: float) -> void:
	_root.add_child(c)
	var w := c.get_combined_minimum_size().x
	c.position = Vector2((W - w) * 0.5, y)


# ---- the clock ------------------------------------------------------------------


func _anim(node: CanvasItem, kind: String, delay: float, dur: float, extra := 0.0) -> void:
	var base := Vector2.ZERO
	if node is Control:
		base = (node as Control).position
	_anims.push_back({"node": node, "kind": kind, "delay": delay, "dur": dur, "base": base, "extra": extra})
	if kind in ["rise", "pop", "slam", "fadein"]:
		node.modulate.a = 0.0


static func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 3.0)


static func _ease_in(p: float) -> float:
	return p * p * p


func step(dt: float) -> void:
	_t += dt
	if not _sound_done and _t >= T_OPEN:
		_sound_done = true
		Sfx.score_pop(true)
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
				node.modulate.a = p
			"fadeout":
				node.modulate.a = 1.0 - p
			"show":
				if _t >= delay:
					node.visible = true
			"hide":
				if _t >= delay:
					node.visible = false
			"pop":
				node.modulate.a = 1.0 if p > 0.0 else 0.0
				if c != null:
					var s := 0.0
					if p < 0.65:
						s = 1.18 * (p / 0.65)
					else:
						s = 1.18 - 0.18 * ((p - 0.65) / 0.35)
					c.scale = Vector2.ONE * s
			"slam":
				node.modulate.a = 1.0 if p > 0.0 else 0.0
				if c != null:
					var s := 1.0
					if p < 0.55:
						s = lerpf(2.8, 0.9, _ease_out(p / 0.55))
					elif p < 0.75:
						s = lerpf(0.9, 1.06, (p - 0.55) / 0.2)
					else:
						s = lerpf(1.06, 1.0, (p - 0.75) / 0.25)
					c.scale = Vector2.ONE * s
			"bump":
				if c != null and _t >= delay:
					c.scale = Vector2.ONE * (1.0 + 0.04 * sin(p * PI))
			"rattle":
				if c != null and _t >= delay and p < 1.0:
					var keys := [0.0, -9.0, 8.0, -7.0, 6.0, -4.0, 3.0, 0.0]
					var f := p * 7.0
					var i := mini(int(f), 6)
					c.rotation_degrees = lerpf(float(keys[i]), float(keys[i + 1]), f - i)
				elif c != null and p >= 1.0 and _t < 1.75:
					c.rotation_degrees = 0.0
			"spring":
				if c != null and _t >= delay:
					var y := 0.0
					if p < 0.6:
						y = lerpf(24.0, -10.0, _ease_out(p / 0.6))
					else:
						y = lerpf(-10.0, 0.0, (p - 0.6) / 0.4)
					c.position = base + Vector2(0, y)
			"away":
				if c != null and _t >= delay:
					node.modulate.a = 1.0 - p
					c.position = base + Vector2(0, -120.0 * _ease_in(p))
					c.scale = Vector2.ONE * lerpf(1.0, 0.6, p)
					c.rotation_degrees = lerpf(0.0, -14.0, p)
			"ring":
				if c != null and _t >= delay:
					node.modulate.a = 0.9 * (1.0 - p) if p < 1.0 else 0.0
					c.scale = Vector2.ONE * lerpf(0.3, 2.4, _ease_out(p))
			"flash":
				var peak := float(a["extra"]) if float(a["extra"]) > 0.0 else 0.9
				node.modulate.a = peak * (1.0 - p) if _t >= delay else 0.0


func _process(delta: float) -> void:
	step(delta)


# ---- probes ---------------------------------------------------------------------


func clock() -> float:
	return _t


func lock_open() -> bool:
	return _lock_open != null and _lock_open.visible


func lock_gone() -> bool:
	return _lock != null and _lock.modulate.a < 0.05


func buttons_shown() -> bool:
	for b in _buttons:
		if b.modulate.a < 0.99:
			return false
	return not _buttons.is_empty()


func page() -> Control:
	return _root


func confetti_count() -> int:
	return _confetti.count() if _confetti != null else 0


func rays_alpha() -> float:
	return _rays.modulate.a if _rays != null else 0.0


## The gold ring that bursts out when the shackle springs.
class Ring extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_arc(size * 0.5, size.x * 0.5 - 3.0, 0.0, TAU, 48, AreaUnlockPage.GOLD, 6.0, false)
