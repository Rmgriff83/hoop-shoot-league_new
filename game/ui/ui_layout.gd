class_name UiLayout
extends RefCounted
## The screen vs. the design (2026-10-24; docs/HOME.md → Screen vs. design).
## The game is laid out at 720×1280. The window stretches to the phone's
## width and the canvas EXPANDS to its height (project.godot
## window/stretch/aspect=expand), so a 20:9 phone gets a 720×1604 canvas
## instead of black letterbox bars. Two kinds of 2D layer sit on it:
##
##  • CENTRED layers (the default — the match HUD, toasts, results, match
##    end, the tutorial…): their 1280 band sits centred. Every CanvasLayer
##    that enters the tree gets `offset` = half the excess, and the
##    viewport's own canvas gets the same through canvas_transform, so
##    every design position lands where it was drawn.
##  • ANCHORED layers (anchor_layer: the home screen's chrome and every
##    HomePage frame, the ranks / archive pages, the walkthrough): no
##    offset — they lay out in SCREEN coordinates (0 = the top edge,
##    screen_height() = the bottom), against the real screen.
##
## Why layer offsets and not the viewport's global canvas transform: the
## engine only picks controls at points inside the design rect, so anything
## a global shift pushed above the band's top could be drawn but never
## tapped (found 2026-10-24: the home's top row at 32 px from the screen
## top took no taps on a tall phone). A layer offset moves the picking
## along with the drawing.
##
## Camera3D: project_ray_* / project_position take screen coordinates and
## unproject_position returns them, so a centred layer crosses with
## from_screen / to_screen; an anchored layer uses them as they are. A
## full-screen wash in a centred layer stretches over the bleed with
## full_rect.

const DESIGN := Vector2(720, 1280)
const ANCHORED_META := "ui_anchored"

static var _offset := Vector2.ZERO
static var _canvas := DESIGN
static var _root: Window
## The top safe-area inset in design px (a notch, the Dynamic Island, a
## camera cutout): what DisplayServer.get_display_safe_area reports, or
## `safe_override` when set (QA: --qa-safe-top=118 plays an iPhone).
static var _safe_top := 0.0
static var safe_override := -1.0
## The bottom inset (the home indicator bar) the same way; QA: --qa-safe-bottom=62.
static var _safe_bottom := 0.0
static var safe_bottom_override := -1.0
## The match HUD's band (designs "Solo Modes HUD" 5a / "League Match HUD"
## 4a, Ross's 2026-10-26 pass): the HUD was drawn in the 720×1280 band with
## its top row 32 px from the top and the music note's row ending 32 px from
## the bottom (the note at 1192, 56 tall). On the phone it pins to the real
## screen instead of the centred band: the top row 6 px under the top safe
## area, the music row 6 px above the bottom one, and everything between
## keeps its size and spreads to the same proportions (hud_y). A 9:16 screen
## with no insets maps every y to itself.
const HUD_TOP := 32.0
const HUD_BOTTOM := 32.0
const HUD_GAP := 6.0
const HUD_NOTE_Y := 1192.0


## App._ready: follow the window from now on, and every layer that enters the tree.
static func install(root: Window) -> void:
	_root = root
	root.size_changed.connect(_apply)
	var tree := root.get_tree()
	if tree != null:
		tree.node_added.connect(_on_node_added)
	_apply()


static func _apply() -> void:
	if _root == null:
		return
	_canvas = _root.get_visible_rect().size
	_offset = offset_for(_canvas)
	_safe_top = _measure_safe_top()
	_safe_bottom = _measure_safe_bottom()
	_root.global_canvas_transform = Transform2D.IDENTITY
	_root.canvas_transform = Transform2D(0.0, _offset)
	for layer in _root.find_children("*", "CanvasLayer", true, false):
		_place_layer(layer)


static func _on_node_added(node: Node) -> void:
	if node is CanvasLayer:
		_place_layer(node)


static func _place_layer(layer: CanvasLayer) -> void:
	layer.offset = Vector2.ZERO if layer.has_meta(ANCHORED_META) else _offset


## The display's top inset, in design px: the safe area's top edge over the
## window's physical height, scaled to the canvas.
static func _measure_safe_top() -> float:
	if safe_override >= 0.0:
		return safe_override
	var win := Vector2(DisplayServer.window_get_size())
	if win.y <= 0.0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var inset := float(safe.position.y) - float(DisplayServer.window_get_position().y)
	return maxf(0.0, roundf(inset * _canvas.y / win.y))


static func safe_top() -> float:
	return _safe_top


## The display's bottom inset, in design px: the window's bottom edge over
## the safe area's, scaled to the canvas.
static func _measure_safe_bottom() -> float:
	if safe_bottom_override >= 0.0:
		return safe_bottom_override
	var win := Vector2(DisplayServer.window_get_size())
	if win.y <= 0.0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var inset := float(DisplayServer.window_get_position().y) + win.y - float(safe.position.y + safe.size.y)
	return maxf(0.0, roundf(inset * _canvas.y / win.y))


static func safe_bottom() -> float:
	return _safe_bottom


## QA / tests: pretend the display has this bottom inset (design px); < 0 = measure.
static func set_safe_bottom_override(v: float) -> void:
	safe_bottom_override = v
	if _root != null:
		_apply()
	else:
		_safe_bottom = maxf(v, 0.0)


## The match HUD's rows on this screen (anchored layers, screen px): the top
## row's y, the margin under the music row, and a band y mapped between them.
static func hud_top() -> float:
	return hud_map(HUD_TOP, _canvas.y, _safe_top, _safe_bottom)


static func hud_y(y: float) -> float:
	return hud_map(y, _canvas.y, _safe_top, _safe_bottom)


static func hud_pos(p: Vector2) -> Vector2:
	return Vector2(p.x, hud_y(p.y))


## Pure: a HUD band y on a `canvas_h`-tall screen with these insets. The top
## row sits at max(32, top inset + 6); the music row's foot at
## max(32, bottom inset + 6) above the bottom edge; the rest is linear
## between the two (whole pixels).
static func hud_map(y: float, canvas_h: float, top_inset: float, bottom_inset: float) -> float:
	var top := maxf(HUD_TOP, top_inset + HUD_GAP)
	var foot := maxf(HUD_BOTTOM, bottom_inset + HUD_GAP)
	var note_h := DESIGN.y - HUD_BOTTOM - HUD_NOTE_Y
	var k := (canvas_h - foot - note_h - top) / (HUD_NOTE_Y - HUD_TOP)
	return roundf(top + (y - HUD_TOP) * k)


## QA / tests: pretend the display has this top inset (design px); < 0 = measure.
static func set_safe_override(v: float) -> void:
	safe_override = v
	if _root != null:
		_apply()
	else:
		_safe_top = maxf(v, 0.0)


## Where a header row goes (design "Home League Context v2", 2026-10-25): its
## usual `base` from the top, or `gap` under the top safe area when that is
## lower — the row clears the notch, the wash behind it still runs to the edge.
static func header_top(base: float, gap := 0.0) -> float:
	return maxf(base, _safe_top + gap)


## Half the canvas's excess over the design, whole pixels, never negative.
static func offset_for(canvas: Vector2) -> Vector2:
	return ((canvas - DESIGN) * 0.5).max(Vector2.ZERO).floor()


static func offset() -> Vector2:
	return _offset


## The canvas (the whole screen) in design px: 720 × 1280 on a 9:16 screen,
## 720 × 1604 on the moto, 720 × 1560 on an iPhone.
static func canvas() -> Vector2:
	return _canvas


## A layer that lays out against the real screen (no centring offset). Call
## it in the layer's _init, before it enters the tree.
static func anchor_layer(layer: CanvasLayer) -> void:
	layer.set_meta(ANCHORED_META, true)
	layer.offset = Vector2.ZERO


## Whether `node` draws in an anchored layer (screen coordinates).
static func is_anchored(node: Node) -> bool:
	var n := node
	while n != null:
		if n is CanvasLayer:
			return n.has_meta(ANCHORED_META)
		n = n.get_parent()
	return false


## The screen's edges, for anchored layers: screen coordinates run 0 … canvas.
static func screen_top() -> float:
	return 0.0


static func screen_height() -> float:
	return _canvas.y


static func screen_bottom() -> float:
	return _canvas.y


static func screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _canvas)


## An anchored root: it covers the real screen (an anchored layer's canvas
## IS the screen), and its children lay out in screen coordinates.
static func screen_fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## A raw screen point (Camera3D.unproject_position, an input event in
## _input) → a centred layer's design space.
static func from_screen(p: Vector2) -> Vector2:
	return p - _offset


## A centred layer's design point → the raw screen (project_ray_*).
static func to_screen(p: Vector2) -> Vector2:
	return p + _offset


## Where a control sits on the real screen (any layer): its canvas transform
## carries the layer's offset.
static func screen_rect_of(c: Control) -> Rect2:
	return Rect2(c.get_global_transform_with_canvas().origin, c.size)


## The horizontal field of view that shows exactly `vfov_deg` of vertical
## view across the 720×1280 band, so a taller canvas reveals more floor and
## sky instead of cropping the sides (as KEEP_HEIGHT would).
static func hfov(vfov_deg: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(vfov_deg) * 0.5) * DESIGN.x / DESIGN.y))


## A main-viewport camera framed for the design band: `vfov_deg` is the
## vertical field of view the area was tuned at (ArenaSet.camera_fov, TitlePan).
static func frame_camera(cam: Camera3D, vfov_deg: float) -> void:
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = hfov(vfov_deg)


## Anchor `c` over the whole canvas. In a CENTRED layer a layer-rooted FILL
## (a ColorRect, a TextureRect or a Panel with no children, its parent not
## a Control) also stretches over the bleed above and below the band, so a
## wash or a backdrop covers the real screen. Anything else keeps the band:
## a root that positions children in design px, or a control that draws in
## its own coordinates, would have its origin pulled up by the offset and
## cancel the centring. In an anchored layer the canvas is the screen, so
## nothing bleeds.
static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if c.is_inside_tree():
		bleed(c)
	else:
		c.tree_entered.connect(bleed.bind(c), CONNECT_ONE_SHOT)


## A full-screen fill NESTED in a centred layer's band (a scrim inside a
## screen's chrome Control): anchored to its parent's full rect and pushed
## out by the band's offset on every side, so it covers the real screen —
## full_rect only bleeds a fill rooted at the layer (Ross, 2026-10-25: the
## post-match scrim began under the notch).
static func full_screen_fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = -_offset.x
	c.offset_right = _offset.x
	c.offset_top = -_offset.y
	c.offset_bottom = _offset.y


static func bleed(c: Control) -> void:
	if c.get_parent() is Control:
		return
	if not (c is ColorRect or c is TextureRect or c is Panel) or c.get_child_count() > 0:
		return
	if c.offset_top != 0.0 or c.offset_bottom != 0.0 or c.offset_left != 0.0 or c.offset_right != 0.0:
		return   # someone set margins after the preset: not a plain full rect
	if is_anchored(c):
		return
	c.offset_left = -_offset.x
	c.offset_right = _offset.x
	c.offset_top = -_offset.y
	c.offset_bottom = _offset.y
