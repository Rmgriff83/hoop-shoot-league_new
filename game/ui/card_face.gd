class_name CardFace
extends Control
## A power-up card's face (design "Card Icons" 9a, docs/CARDS.md → Art): the
## static base — frame, target badge, name plate (`art`) — with the card's
## looping pixel sprite drawn on top from its `fx` row in data/cards.json
## ({sheet, frames, fps, rect: [x, y, w, h] in face pixels at 96×128, chip,
## chip_bg, glyph}). Draws to its `size`, so every scale the game uses
## (tray 84×112 … deal 168×224) is the same node; every face on screen runs
## in step because the frame comes from the engine clock. `sprite_only`
## draws just the loop (the 40 px chips). `set_frame` pins a frame (QA).

const FACE := Vector2(96, 128)
const BACK := "res://assets/textures/cards/card_back.png"

static var _cache := {}

var card: Dictionary = {}
var sprite_only := false
var base: Texture2D
var sheet: Texture2D
var frames := 1
var fps := 0.0
var rect := Rect2(Vector2.ZERO, FACE)
## A pinned frame (QA / tests); -1 follows the clock.
var forced := -1
var _frame := 0


func _init(p_card: Dictionary, size_: Vector2, p_sprite_only := false) -> void:
	sprite_only = p_sprite_only
	custom_minimum_size = size_
	size = size_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_card(p_card)


## Re-target the face (the deal card reuses one node).
func set_card(p_card: Dictionary) -> void:
	card = p_card
	base = tex(str(card.get("art", BACK)))
	var fx: Dictionary = card["fx"] if card.get("fx", null) is Dictionary else {}
	sheet = tex(str(fx.get("sheet", "")))
	frames = maxi(int(fx.get("frames", 1)), 1)
	fps = float(fx.get("fps", 0.0))
	var r: Array = fx["rect"] if fx.get("rect", null) is Array else []
	rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])) if r.size() == 4 else Rect2(Vector2.ZERO, FACE)
	_frame = frame_now()
	queue_redraw()


static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## The frame showing at `msec` on the clock: floor(t × fps) mod frames.
static func frame_at(msec: int, p_frames: int, p_fps: float) -> int:
	if p_frames <= 1 or p_fps <= 0.0:
		return 0
	return int(floor(msec * 0.001 * p_fps)) % p_frames


func frame_now() -> int:
	return forced if forced >= 0 else frame_at(Time.get_ticks_msec(), frames, fps)


func set_frame(i: int) -> void:
	forced = i
	_frame = frame_now()
	queue_redraw()


func _process(_dt: float) -> void:
	var f := frame_now()
	if f != _frame:
		_frame = f
		queue_redraw()


func _draw() -> void:
	if sprite_only:
		_draw_sprite(Rect2(Vector2.ZERO, size))
		return
	if base != null:
		draw_texture_rect(base, Rect2(Vector2.ZERO, size), false)
	var k := size / FACE
	_draw_sprite(Rect2(rect.position * k, rect.size * k))


func _draw_sprite(dst: Rect2) -> void:
	if sheet == null:
		return
	var fw := sheet.get_width() / float(frames)
	draw_texture_rect_region(sheet, dst, Rect2(_frame * fw, 0.0, fw, float(sheet.get_height())))
