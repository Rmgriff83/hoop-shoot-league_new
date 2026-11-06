extends Node
## The trailer's text cards, rendered by the game (docs/TRAILER.md → Text
## cards): each card of a cut in tools/trailer/edit.json becomes a PNG
## sequence with alpha, drawn with the game's own parts — the tour cards'
## panel (ShadowPanel: white frame, dotted face, checker shadow), Press
## Start for the words with the ink outline and the dithered shadow, white
## and butter. ffmpeg only lays the frames over the footage; it draws no
## type of its own. The motion is the game's too: the tour card's rise and
## fade in (16 px, 0.35 s), a short fade out.
##   Godot --path . -- --qa-trailer-cards=<appstore|social> --no-net
## writes marketing/trailer/cards/<layout>/<id>/f0000.png … at 60 fps, and
## one still per card in marketing/trailer/checkpoint_a/cards/<layout>/.

const EDIT := "res://tools/trailer/edit.json"
const OUT_ROOT := "res://marketing/trailer"
const LAYOUTS := {"appstore": Vector2i(720, 1560), "social": Vector2i(720, 1280)}
const SCALE := 2                    # frames are 2x the layout, as the footage is
const BUTTER := Color("#FFE45C")
const CARD_X := 36.0
const CARD_W := 648.0
const CARD_PAD := 28.0
const CARD_GROUND := Color(27.0 / 255.0, 24.0 / 255.0, 21.0 / 255.0, 0.88)   # the tour card's ground
const RISE_PX := 16.0
const IN_DELAY_S := 0.1
const IN_S := 0.35
const OUT_S := 0.2
## Where a card sits by default (design px from the top of the layout): over
## the court's floor in the shooting view, clear of the hoop and the HUD.
const DEFAULT_Y := {"appstore": 1010.0, "social": 820.0}

var _vp: SubViewport


func render(layout: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EDIT))
	if not (parsed is Dictionary) or not LAYOUTS.has(layout):
		print("TRAILER cards: no edit, or no layout '%s'" % layout)
		return false
	var edit: Dictionary = parsed
	var cut := {}
	for name in edit["cuts"]:
		if str(edit["cuts"][name]["layout"]) == layout:
			cut = edit["cuts"][name]
	if cut.is_empty():
		return false
	var design: Vector2i = LAYOUTS[layout]
	_vp = SubViewport.new()
	_vp.name = "CardViewport"
	_vp.transparent_bg = true
	_vp.size = design * SCALE
	_vp.size_2d_override = design
	_vp.size_2d_override_stretch = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	for c in cut.get("cards", []):
		var id := str(c["id"])
		var seconds := beat_time(edit, str(c["until"])) - beat_time(edit, str(c["at"]))
		var node := build_card(id, str(c.get("text", "")), edit, layout, float(c.get("y", DEFAULT_Y[layout])))
		_vp.add_child(node)
		var dir := ProjectSettings.globalize_path("%s/cards/%s/%s" % [OUT_ROOT, layout, id])
		DirAccess.make_dir_recursive_absolute(dir)
		for old in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + "/" + old)
		var rest_y := node.position.y
		var frames := int(round(seconds * 60.0))
		for i in frames:
			var k := pose(float(i) / 60.0, seconds)
			node.modulate.a = k.x
			node.position.y = rest_y + k.y
			await RenderingServer.frame_post_draw
			_vp.get_texture().get_image().save_png("%s/f%04d.png" % [dir, i])
			if i == mini(frames - 1, 45):   # settled: the storyboard's still
				var still_dir := ProjectSettings.globalize_path("%s/checkpoint_a/cards/%s" % [OUT_ROOT, layout])
				DirAccess.make_dir_recursive_absolute(still_dir)
				_vp.get_texture().get_image().save_png("%s/%s.png" % [still_dir, id])
		_vp.remove_child(node)
		node.queue_free()
		print("TRAILER card: %s/%s %d frames" % [layout, id, frames])
	return true


## Seconds at "bar.beat" (both from 1; "4.2.5" is bar 4, beat 2.5), as build_cut.py counts.
static func beat_time(edit: Dictionary, pos: String) -> float:
	var dot := pos.find(".")
	var bar := int(pos.substr(0, dot)) if dot > 0 else int(pos)
	var beat := float(pos.substr(dot + 1)) if dot > 0 else 1.0
	return ((bar - 1) * 4 + (beat - 1.0)) * 60.0 / float(edit["bpm"])


## A card's opacity (x) and its offset below rest (y) at `t` of `seconds`:
## the tour card's entrance, a short fade out.
static func pose(t: float, seconds: float) -> Vector2:
	var k := clampf((t - IN_DELAY_S) / IN_S, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)   # quad out
	var out := clampf((seconds - t) / OUT_S, 0.0, 1.0)
	return Vector2(e * out, RISE_PX * (1.0 - e))


## The card's node for the layout (design px). "credit" and "free" are the
## end card's lines; anything else is a worded card on the tour panel.
func build_card(id: String, text: String, edit: Dictionary, layout: String, y: float) -> Control:
	var design: Vector2i = LAYOUTS[layout]
	if id == "credit":
		var l := RetroTheme.caps(str(edit.get("music_credit", "")), 16, RetroTheme.SCENE_TEXT)
		RetroTheme.on_scene(l)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(0, design.y - 132.0)
		l.size = Vector2(design.x, 24)
		return l
	if id == "free":
		var f := _title("FREE ON THE\nAPP STORE", 32, BUTTER)
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.position = Vector2(0, design.y - 330.0)
		f.size = Vector2(design.x, 100)
		return f
	var panel := ShadowPanel.new(RetroTheme.SCENE_TEXT, CARD_PAD, 0.22)
	panel.name = "Card_" + id
	panel.ground = CARD_GROUND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var lines := text.split("\n")
	for i in lines.size():
		# The first line white, the second butter: the game's two light tones.
		col.add_child(_title(lines[i], 46, RetroTheme.SCENE_TEXT if i == 0 or lines.size() == 1 else BUTTER))
	panel.position = Vector2(CARD_X, y)
	panel.size = Vector2(CARD_W, 0)
	panel.reset_size()
	panel.size.x = CARD_W
	return panel


## Big words as the game writes them over a scene: Press Start, the ink
## outline, the dithered shadow (walkthrough.gd's _big_gold, in another tone).
static func _title(text: String, size_: int, colour: Color) -> Label:
	var l := RetroTheme.display(text, size_, colour)
	l.add_theme_color_override("font_outline_color", RetroTheme.SCENE_OUTLINE)
	l.add_theme_constant_override("outline_size", RetroTheme.OUTLINE_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RetroTheme.dithered(l, Vector2(6, 6))
	return l
