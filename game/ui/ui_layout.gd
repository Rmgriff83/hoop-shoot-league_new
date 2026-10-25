class_name UiLayout
extends RefCounted
## The screen vs. the design (2026-10-24; docs/HOME.md → Screen vs. design).
## The game is laid out at 720×1280. The window stretches to the phone's
## width and the canvas EXPANDS to its height (project.godot
## window/stretch/aspect=expand), so a 20:9 phone gets a 720×1604 canvas
## instead of black letterbox bars. Every 2D layer is shifted down by half
## the extra height through the root's global canvas transform, so the
## designed band sits centred and every page lands where it was drawn; the
## 3D court fills the rest (frame_camera keeps the band's framing and shows
## more floor and sky). Input events arrive in the shifted (design) space.
## Camera3D.project_ray_* / project_position take that same space (the
## engine runs the point through the canvas transform, Viewport.
## get_camera_coords) — but unproject_position returns the RAW viewport
## point, so it goes through from_screen before any 2D use. Full-screen
## washes stretch over the bleed with full_rect.

const DESIGN := Vector2(720, 1280)

static var _offset := Vector2.ZERO
static var _root: Window


## App._ready: follow the window from now on.
static func install(root: Window) -> void:
	_root = root
	root.size_changed.connect(_apply)
	_apply()


static func _apply() -> void:
	if _root == null:
		return
	_offset = offset_for(_root.get_visible_rect().size)
	_root.global_canvas_transform = Transform2D(0.0, _offset)


## Half the canvas's excess over the design, whole pixels, never negative.
static func offset_for(canvas: Vector2) -> Vector2:
	return ((canvas - DESIGN) * 0.5).max(Vector2.ZERO).floor()


static func offset() -> Vector2:
	return _offset


## A raw viewport point (Camera3D.unproject_position) → the design space 2D draws in.
static func from_screen(p: Vector2) -> Vector2:
	return p - _offset


## A design-space point → the raw viewport. NOT for project_ray_* (they
## convert themselves); for anything that wants raw window-space pixels.
static func to_screen(p: Vector2) -> Vector2:
	return p + _offset


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


## Anchor `c` over the whole canvas. A layer-rooted FILL (a ColorRect, a
## TextureRect or a Panel with no children, its parent not a Control) also
## stretches over the bleed above and below the band, so a wash or a
## backdrop covers the real screen. Anything else keeps the band: a root
## that positions children in design px, or a control that draws in its own
## coordinates, would have its origin pulled up by the offset and cancel the
## shift (the first attempt did exactly that, 2026-10-24).
static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if c.is_inside_tree():
		bleed(c)
	else:
		c.tree_entered.connect(bleed.bind(c), CONNECT_ONE_SHOT)


static func bleed(c: Control) -> void:
	if c.get_parent() is Control:
		return
	if not (c is ColorRect or c is TextureRect or c is Panel) or c.get_child_count() > 0:
		return
	if c.offset_top != 0.0 or c.offset_bottom != 0.0 or c.offset_left != 0.0 or c.offset_right != 0.0:
		return   # someone set margins after the preset: not a plain full rect
	c.offset_left = -_offset.x
	c.offset_right = _offset.x
	c.offset_top = -_offset.y
	c.offset_bottom = _offset.y
