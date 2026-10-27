## The screen vs. the design (docs/HOME.md → Screen vs. design, 2026-10-24):
## the designed 720×1280 band centred on a taller canvas, the cameras framed
## by width so the band looks the same, full-screen controls over the bleed.


func run(t) -> void:
	t.eq(UiLayout.offset_for(Vector2(720, 1280)), Vector2.ZERO, "a 9:16 screen: no shift")
	t.eq(UiLayout.offset_for(Vector2(720, 1604)), Vector2(0, 162), "the moto (20:9): the band sits 162 px down")
	t.eq(UiLayout.offset_for(Vector2(720, 1561)), Vector2(0, 140), "an iPhone (19.5:9): 140 px, whole pixels")
	t.eq(UiLayout.offset_for(Vector2(720, 1000)), Vector2.ZERO, "a shorter canvas never shifts up")
	t.eq(UiLayout.offset_for(Vector2(900, 1280)), Vector2(90, 0), "a wider canvas centres sideways")
	t.ok(str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "expand", "the canvas expands to the screen (no letterbox)")
	# The band keeps its vertical view: at 720×1280 the horizontal fov shows exactly the old vertical one.
	var h := UiLayout.hfov(60.0)
	var back := rad_to_deg(2.0 * atan(tan(deg_to_rad(h) * 0.5) * 1280.0 / 720.0))
	t.close(back, 60.0, 1e-9, "hfov(60) at 9:16 is 60° tall again")
	t.ok(h < 60.0, "…and narrower than tall (%.1f°)" % h)
	var cam := Camera3D.new()
	UiLayout.frame_camera(cam, 55.0)
	t.eq(cam.keep_aspect, Camera3D.KEEP_WIDTH, "a framed camera keeps its width")
	t.close(cam.fov, UiLayout.hfov(55.0), 1e-4, "…at the equivalent horizontal fov")
	cam.free()
	# The flick never reads the canvas height.
	var src := FileAccess.get_file_as_string("res://game/input/flick_input.gd")
	t.ok(not src.contains("get_visible_rect().size.y"), "the flick input reads the design height, never the canvas")
	t.ok(src.contains("UiLayout.DESIGN.y"), "…through UiLayout.DESIGN")
	# Full rect: a layer-rooted control bleeds, a child of a control does not.
	var off := UiLayout.offset()
	var layer := CanvasLayer.new()
	var wash := ColorRect.new()
	layer.add_child(wash)
	UiLayout.full_rect(wash)
	UiLayout.bleed(wash)
	t.ok(wash.anchor_right == 1.0 and wash.anchor_bottom == 1.0, "full rect anchors")
	t.ok(wash.offset_top == -off.y and wash.offset_bottom == off.y, "a layer-rooted wash stretches over the bleed (%s)" % off)
	var box := Control.new()
	var inner := ColorRect.new()
	box.add_child(inner)
	UiLayout.full_rect(inner)
	UiLayout.bleed(inner)
	t.ok(inner.offset_top == 0.0 and inner.offset_bottom == 0.0, "a child of a control just fills it")
	var root_ := Control.new()
	layer.add_child(root_)
	root_.add_child(Label.new())
	UiLayout.full_rect(root_)
	UiLayout.bleed(root_)
	t.ok(root_.offset_top == 0.0 and root_.offset_bottom == 0.0, "a layout root keeps the band (its children sit in design px)")
	var drawn := Confetti.new()
	layer.add_child(drawn)
	UiLayout.bleed(drawn)
	t.ok(drawn.offset_top == 0.0, "a control that draws in its own coordinates keeps the band")
	var framed := ColorRect.new()
	layer.add_child(framed)
	UiLayout.full_rect(framed)
	framed.offset_top = 24.0
	UiLayout.bleed(framed)
	t.eq(framed.offset_top, 24.0, "margins set after the preset are respected")
	layer.free()
	box.free()
	# The screen in design space, and a root that fills it.
	t.ok(is_equal_approx(UiLayout.screen_top() + UiLayout.screen_height(), UiLayout.screen_bottom()), "top + height = bottom")
	t.eq(UiLayout.screen_rect().size, UiLayout.canvas(), "the screen rect is the canvas")
	var filled := Control.new()
	UiLayout.screen_fill(filled)
	t.ok(filled.anchor_right == 1.0 and filled.anchor_bottom == 1.0 and filled.offset_top == 0.0, "screen_fill anchors over the canvas, no bleed")
	filled.free()
	t.eq(UiLayout.screen_top(), 0.0, "an anchored layer's top is the screen's top")
	var anchored := CanvasLayer.new()
	UiLayout.anchor_layer(anchored)
	t.ok(anchored.has_meta(UiLayout.ANCHORED_META) and anchored.offset == Vector2.ZERO, "anchor_layer marks the layer and zeroes its offset")
	var fill := ColorRect.new()
	anchored.add_child(fill)
	UiLayout.full_rect(fill)
	UiLayout.bleed(fill)
	t.ok(UiLayout.is_anchored(fill), "a child of an anchored layer is anchored")
	t.eq(fill.offset_top, 0.0, "…and a fill in it never bleeds (the canvas is the screen)")
	anchored.free()
	# The top safe area: a header drops under it, never above its usual place.
	t.eq(UiLayout.header_top(32.0), 32.0, "no inset: a header at its usual place")
	UiLayout.set_safe_override(118.0)
	t.eq(UiLayout.safe_top(), 118.0, "a pretend notch")
	t.eq(UiLayout.header_top(32.0), 118.0, "…a header drops under it")
	t.eq(UiLayout.header_top(20.0, 10.0), 128.0, "…with a gap when asked")
	UiLayout.set_safe_override(-1.0)
	t.eq(UiLayout.header_top(32.0), 32.0, "…and comes back when it is gone")
	# Round trips.
	t.eq(UiLayout.from_screen(UiLayout.to_screen(Vector2(10, 20))), Vector2(10, 20), "to_screen / from_screen invert")
	# The match HUD pinned to the screen (designs 5a / 4a, Ross 2026-10-26):
	# on a 9:16 screen with no insets every band y is itself…
	for y in [32.0, 116.0, 376.0, 853.0, 1192.0]:
		t.eq(UiLayout.hud_map(y, 1280.0, 0.0, 0.0), y, "a 9:16 screen keeps the HUD's y %d" % int(y))
	# …on the design's iPhone (1560 tall, 108 over, 62 under) the rows pin and the rest spreads.
	t.eq(UiLayout.hud_map(32.0, 1560.0, 108.0, 62.0), 114.0, "the top row 6 px under the top safe area")
	t.eq(UiLayout.hud_map(116.0, 1560.0, 108.0, 62.0), 210.0, "the opponent window at 210")
	t.eq(UiLayout.hud_map(376.0, 1560.0, 108.0, 62.0), 506.0, "the tray centred at 506")
	t.eq(UiLayout.hud_map(853.0, 1560.0, 108.0, 62.0), 1050.0, "the toasts centred at 1050")
	t.eq(UiLayout.hud_map(1192.0, 1560.0, 108.0, 62.0) + 56.0, 1492.0, "the music row ends 6 px over the bottom inset")
	t.eq(UiLayout.hud_map(32.0, 1560.0, 0.0, 0.0), 32.0, "a tall screen without insets keeps the 32 px margins…")
	t.eq(UiLayout.hud_map(1192.0, 1560.0, 0.0, 0.0), 1472.0, "…and spreads the rest to the bottom")
	UiLayout.set_safe_bottom_override(62.0)
	t.eq(UiLayout.safe_bottom(), 62.0, "a pretend home bar")
	UiLayout.set_safe_bottom_override(-1.0)
	t.ok(UiLayout.hud_top() >= 32.0 and UiLayout.hud_y(32.0) == UiLayout.hud_top(), "hud_top is the top row's y on this screen")
	# No raw full-rect preset left in game/: every one goes through the helper.
	var raw := 0
	for dir_ in ["res://game/ui", "res://game/screens", "res://game/view", "res://game/court", "res://game/input"]:
		raw += _count_raw(dir_)
	t.eq(raw, 0, "no raw PRESET_FULL_RECT anchoring outside UiLayout")


func _count_raw(path: String) -> int:
	var n := 0
	var d := DirAccess.open(path)
	if d == null:
		return 0
	for f in d.get_files():
		if f.ends_with(".gd") and f != "ui_layout.gd":
			var s := FileAccess.get_file_as_string(path + "/" + f)
			if s.contains("PRESET_FULL_RECT"):
				n += 1
	for sub in d.get_directories():
		n += _count_raw(path + "/" + sub)
	return n
