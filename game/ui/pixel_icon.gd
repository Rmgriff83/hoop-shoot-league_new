class_name PixelIcon
extends Control
## A pixel icon from assets/ui (the design project's icon_*.png) drawn at a
## design size, nearest-filtered, with an optional hard ink drop shadow (the
## design's drop-shadow(2px 2px 0 ink)). Sized for containers.

static var _cache := {}

var icon_name := ""
var shadow := 0.0
var tint := Color.WHITE


func _init(p_name: String, px: Vector2, p_shadow := 0.0) -> void:
	icon_name = p_name
	shadow = p_shadow
	custom_minimum_size = px
	size = px
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func tex(name_: String) -> Texture2D:
	if not _cache.has(name_):
		var path := "res://assets/ui/%s.png" % name_
		_cache[name_] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name_]


func _draw() -> void:
	var t := tex(icon_name)
	if t == null:
		return
	if shadow > 0.0:
		draw_texture_rect(t, Rect2(Vector2.ONE * shadow, size), false, RetroTheme.SCENE_OUTLINE)
	draw_texture_rect(t, Rect2(Vector2.ZERO, size), false, tint)
