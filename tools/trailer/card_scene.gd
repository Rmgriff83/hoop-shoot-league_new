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
## Trailer v2 (docs/TRAILER.md → v2): one position and size for every part,
## locked on part 1 — the appstore layout's card slot, a 32 px line (Press
## Start is 1 em a glyph: 18 glyphs fit the panel; a longer line wraps), from
## the part's "text card in" hit to its last frame.
const STORY_V2 := "res://tools/trailer/v2/storyboard.json"
const V2_Y := 1010.0
const V2_FONT := 32
const V2_LINE_W := CARD_W - 2.0 * CARD_PAD

var _vp: SubViewport


func render(layout: String) -> bool:
	if layout == "v2" or layout.begins_with("v2:"):   # "v2:1,7" renders those parts only (a part is minutes)
		var only: Array = []
		for s in layout.trim_prefix("v2:").trim_prefix("v2").split(",", false):
			only.push_back(int(s))
		return await render_v2(only)
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
	_make_viewport(LAYOUTS[layout])
	for c in cut.get("cards", []):
		var id := str(c["id"])
		var seconds := beat_time(edit, str(c["until"])) - beat_time(edit, str(c["at"]))
		var node := build_card(id, str(c.get("text", "")), edit, layout, float(c.get("y", DEFAULT_Y[layout])))
		var dir := ProjectSettings.globalize_path("%s/cards/%s/%s" % [OUT_ROOT, layout, id])
		var still := ProjectSettings.globalize_path("%s/checkpoint_a/cards/%s/%s.png" % [OUT_ROOT, layout, id])
		var frames := await _render_sequence(node, int(round(seconds * 60.0)), dir, still)
		print("TRAILER card: %s/%s %d frames" % [layout, id, frames])
	return true


## v2: every part with a `text` → marketing/trailer/v2/cards/partNN/f%04d.png
## (1440 x 3120, alpha), as long as the part has left after its "text card
## in" hit; a still of each in cards/stills/. Part 7's " · " is its line break.
func render_v2(only: Array = []) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORY_V2))
	if not (parsed is Dictionary) or not (parsed.get("parts") is Array):
		print("TRAILER cards: no v2 storyboard")
		return false
	_make_viewport(LAYOUTS["appstore"])
	for p in parsed["parts"]:
		if not only.is_empty() and not only.has(int(p["part"])):
			continue
		if p.get("end_card") is Dictionary:
			await _render_end_card("part%02d" % int(p["part"]), p["end_card"])
			continue
		if p.get("text") == null:
			continue
		var id := "part%02d" % int(p["part"])
		var card_in := 0
		for h in p.get("hits", []):
			if str(h.get("what", "")).to_lower().contains("text card in"):
				card_in = int(h["part_frame"])
		var frames := int(p["frames"]) - card_in
		# A part may move the card off the slot from a frame on (`card_y`: the
		# shot's action is under the slot there — part 4's loadout slots).
		var moves: Array = []
		for m in p.get("card_y", []):
			moves.push_back({"at": int(m["part_frame"]) - card_in, "y": float(m["y"])})
		var node := build_card_v2(id, str(p["text"]).replace(" · ", "\n"))
		var dir := ProjectSettings.globalize_path("%s/v2/cards/%s" % [OUT_ROOT, id])
		var still := ProjectSettings.globalize_path("%s/v2/cards/stills/%s.png" % [OUT_ROOT, id])
		await _render_sequence(node, frames, dir, still, moves)
		print("TRAILER card: v2/%s in at %d, %d frames%s" % [id, card_in, frames, "" if moves.is_empty() else ", moves " + str(moves)])
	return true


## v2's end card (part 8): one still, laid over the bare splash by v2_part.py
## (which fades the whole frame) — Apple's badge (`badge.file`, an .svg or
## .png under the project, drawn at `badge.w` design px wide at `badge.y`
## when the file is there; its space is left when not), the Android line
## under it in the game's face, the legal line and the music credit small at
## the bottom.
func _render_end_card(id: String, spec: Dictionary) -> void:
	var node := Control.new()
	node.name = "EndCard_" + id
	node.size = Vector2(LAYOUTS["appstore"])
	var badge_spec: Dictionary = spec.get("badge", {})
	var bw := float(badge_spec.get("w", 300))
	var by := float(badge_spec.get("y", 1010))
	var badge := _badge_texture(str(badge_spec.get("file", "")), bw)
	var badge_h := bw / 3.0   # Apple's badge is 3:1 (250 x 83)
	if badge != null:
		badge_h = bw * float(badge.get_height()) / float(badge.get_width())
		var tr := TextureRect.new()
		tr.name = "Badge"
		tr.texture = badge
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tr.position = Vector2(roundf((720.0 - bw) / 2.0), by)
		tr.size = Vector2(bw, badge_h)
		node.add_child(tr)
	var android := _title(str(spec.get("android", "")), int(spec.get("android_size", 22)), BUTTER)
	android.name = "Android"
	android.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	android.position = Vector2(0, by + badge_h + float(spec.get("android_gap", 44)))
	android.size = Vector2(720, 40)
	node.add_child(android)
	var legal := RetroTheme.caps(str(spec.get("legal", "")), int(spec.get("small_size", 11)), RetroTheme.SCENE_MUTED)
	legal.name = "Legal"
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legal.add_theme_constant_override("line_spacing", 4)
	legal.position = Vector2(CARD_X, float(spec.get("legal_y", 1380)))
	legal.size = Vector2(CARD_W, 60)
	node.add_child(legal)
	var credit := RetroTheme.caps(str(spec.get("credit", "")), int(spec.get("small_size", 11)), RetroTheme.SCENE_MUTED)
	credit.name = "Credit"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.position = Vector2(CARD_X, float(spec.get("credit_y", 1450)))
	credit.size = Vector2(CARD_W, 24)
	node.add_child(credit)
	_vp.add_child(node)
	var dir := ProjectSettings.globalize_path("%s/v2/cards/%s" % [OUT_ROOT, id])
	DirAccess.make_dir_recursive_absolute(dir)
	for old in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + old)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(dir + "/still.png")
	var still := ProjectSettings.globalize_path("%s/v2/cards/stills/%s.png" % [OUT_ROOT, id])
	DirAccess.make_dir_recursive_absolute(still.get_base_dir())
	img.save_png(still)
	_vp.remove_child(node)
	node.queue_free()
	print("TRAILER card: v2/%s end card still%s" % [id, "" if badge != null else " — NO BADGE at '%s' (its space is left)" % str(badge_spec.get("file", ""))])


## The badge image at `w` design px wide (2x in the frame): an .svg rasterised
## at that size, or a .png as it is.
func _badge_texture(file: String, w: float) -> Texture2D:
	if file == "":
		return null
	var path := file if file.begins_with("/") else ProjectSettings.globalize_path("res://" + file)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if path.ends_with(".svg"):
		var svg := FileAccess.get_file_as_string(path)
		if img.load_svg_from_string(svg, 1.0) != OK or img.get_width() == 0:
			return null
		img.load_svg_from_string(svg, w * SCALE / float(img.get_width()))
	elif img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _make_viewport(design: Vector2i) -> void:
	_vp = SubViewport.new()
	_vp.name = "CardViewport"
	_vp.transparent_bg = true
	_vp.size = design * SCALE
	_vp.size_2d_override = design
	_vp.size_2d_override_stretch = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)


## The card's frames: the tour card's rise and fade in, a short fade out that
## ends on the last frame; the settled frame saved as the still.
func _render_sequence(node: Control, frames: int, dir: String, still: String, moves: Array = []) -> int:
	_vp.add_child(node)
	DirAccess.make_dir_recursive_absolute(dir)
	for old in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + old)
	DirAccess.make_dir_recursive_absolute(still.get_base_dir())
	var home_y := node.position.y
	var seconds := float(frames) / 60.0
	for i in frames:
		var rest_y := home_y
		for m in moves:   # [{at, y}]: the card sits at y from frame `at` on (a cut's new placement)
			if i >= int(m["at"]):
				rest_y = float(m["y"])
		var k := pose(float(i) / 60.0, seconds)
		node.modulate.a = k.x
		node.position.y = rest_y + k.y
		await RenderingServer.frame_post_draw
		_vp.get_texture().get_image().save_png("%s/f%04d.png" % [dir, i])
		if i == mini(frames - 1, 45):   # settled: the storyboard's still
			_vp.get_texture().get_image().save_png(still)
	_vp.remove_child(node)
	node.queue_free()
	return frames


## v2's card: the tour panel at the locked slot, each line 32 px (white, then
## butter), a long line wrapped inside the panel's width.
func build_card_v2(id: String, text: String) -> Control:
	var panel := ShadowPanel.new(RetroTheme.SCENE_TEXT, CARD_PAD, 0.22)
	panel.name = "Card_" + id
	panel.ground = CARD_GROUND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var lines := text.split("\n")
	for i in lines.size():
		var l := _title(lines[i], V2_FONT, RetroTheme.SCENE_TEXT if i == 0 or lines.size() == 1 else BUTTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = V2_LINE_W
		col.add_child(l)
	panel.position = Vector2(CARD_X, V2_Y)
	panel.size = Vector2(CARD_W, 0)
	panel.reset_size()
	panel.size.x = CARD_W
	return panel


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
