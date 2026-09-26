class_name LeagueBanner
extends Node3D
## A league-only banner hung in the environment: a quad textured by a 2D
## SubViewport whose Controls are rebuilt on every content change (the viewport
## renders once, then sleeps). Three looks:
##   show_standings(...)  white cloth, the table (beach, regular season)
##   show_bracket(...)    white cloth, the playoff bracket (beach, playoffs)
##   show_label(text)     small dark cloth with cream text
## Placement comes from the ArenaSet's league_banner_* fields via set_layout().

const TABLE_SIZE := Vector2i(512, 320)
## Chalkboard style (the beach): slate texture, a handwriting font (Caveat,
## OFL — credited), chalk colours, a little jitter and tilt per line, hand-drawn
## underlines. The label style (the cage) stays cloth.
const CHALKBOARD_TEX := "res://assets/textures/chalkboard.png"
const CHALK_FONT := "res://assets/fonts/caveat/Caveat.ttf"
## Handwriting palette per board style (only chalk today; a future board can
## add a row). Keys: tex, title, text, dim, mine, glow, dusty.
const STYLES := {
	"chalk": {
		"tex": CHALKBOARD_TEX, "title": Color(0.98, 0.9, 0.55), "text": Color(0.93, 0.92, 0.85),
		"dim": Color(0.78, 0.8, 0.74), "mine": Color(1.0, 0.72, 0.72), "glow": 0.45, "dusty": true,
	},
}
const LABEL_SIZE := Vector2i(512, 160)
## Cloth banner palette (show_label). CLOTH/HEM were lost with the sash block
## they happened to sit beside; they belong to the label, which still ships.
const CLOTH := Color(0.94, 0.90, 0.82)
const HEM := Color(0.78, 0.20, 0.14)
const DARK_CLOTH := Color(0.42, 0.13, 0.08)
const CREAM := Color(1.0, 0.93, 0.78)

var mesh_instance: MeshInstance3D
var viewport: SubViewport
var material: StandardMaterial3D
var kind := ""
## Board style for standings/bracket: "chalk" (default) or "marker".
var style := "chalk"
var _root: Control
var _rows: Array[String] = []   # the text lines currently shown (tests read these)
var _chalk_font: Font
var _seed := 7   # deterministic hand jitter


func _ready() -> void:
	if viewport == null:
		_build(TABLE_SIZE, true)


func _build(size_px: Vector2i, lit: bool) -> void:
	if viewport != null:
		viewport.queue_free()
	viewport = SubViewport.new()
	viewport.name = "BannerViewport"
	viewport.size = size_px
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	_root = Control.new()
	_root.name = "Face"
	_root.size = Vector2(size_px)
	viewport.add_child(_root)
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Cloth"
		mesh_instance.mesh = QuadMesh.new()
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_instance)
	material = StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	if lit:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	else:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission_texture = viewport.get_texture()
		material.emission_energy_multiplier = 0.35
		material.disable_fog = true
	mesh_instance.material_override = material


## Place and size the cloth (sim metres; yaw about y in degrees).
func set_layout(pos: Vector3, size_m: Vector2, yaw_deg: float, lit: bool) -> void:
	if viewport == null:
		_build(TABLE_SIZE, lit)
	position = pos
	rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	(mesh_instance.mesh as QuadMesh).size = size_m


func _clear() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.free()
	_rows.clear()


func _redraw() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _cloth(bg: Color, hem: Color) -> void:
	var back := ColorRect.new()
	back.color = hem
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(back)
	var face := ColorRect.new()
	face.color = bg
	face.position = Vector2(10, 10)
	face.size = Vector2(viewport.size) - Vector2(20, 20)
	_root.add_child(face)
	# Grommets in the corners.
	for corner in [Vector2(22, 22), Vector2(viewport.size.x - 22, 22), Vector2(22, viewport.size.y - 22), Vector2(viewport.size.x - 22, viewport.size.y - 22)]:
		var g := ColorRect.new()
		g.color = Color(0.55, 0.55, 0.6)
		g.size = Vector2(10, 10)
		g.position = corner - Vector2(5, 5)
		_root.add_child(g)


func set_style(s: String) -> void:
	style = s if STYLES.has(s) else "chalk"


func _pal(key: String) -> Variant:
	return STYLES[style][key]


func _chalkboard() -> void:
	# Handwriting reads better at dusk / in the dark hall with a little
	# self-light (still lit, so the frame keeps its shading).
	if material != null:
		material.emission_enabled = true
		material.emission_texture = viewport.get_texture()
		material.emission_energy_multiplier = float(_pal("glow"))
	var back := TextureRect.new()
	back.texture = load(str(_pal("tex")))
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(back)
	if _chalk_font == null:
		_chalk_font = load(CHALK_FONT)


func _jit(i: int, amp: float) -> float:
	_seed = (_seed * 1103515245 + 12345 + i * 97) & 0x7FFFFFFF
	return (float(_seed % 1000) / 999.0 - 0.5) * 2.0 * amp


## A line of chalk handwriting: nudged and tilted a touch so no two rows sit
## perfectly straight, with a slightly uneven opacity like real chalk.
func _chalk_text(text: String, pos: Vector2, size_px: int, color: Color, width := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT, i := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos + Vector2(_jit(i, 3.0), _jit(i + 1, 2.0))
	if width > 0.0:
		l.size = Vector2(width, size_px + 10)
	l.horizontal_alignment = align
	l.rotation_degrees = _jit(i + 2, 1.4)
	l.pivot_offset = Vector2(0.0, size_px * 0.5)
	if _chalk_font != null:
		l.add_theme_font_override("font", _chalk_font)
	l.add_theme_font_size_override("font_size", size_px)
	var c := color
	if bool(_pal("dusty")):
		c.a = 0.86 + _jit(i + 3, 0.1)
	else:
		_jit(i + 3, 0.1)   # keep the jitter sequence identical across styles
	l.add_theme_color_override("font_color", c)
	_root.add_child(l)
	_rows.push_back(text)
	return l


## A hand-drawn chalk line (a few wobbly segments).
func _chalk_line(from: Vector2, to: Vector2, color: Color, i := 0) -> void:
	var line := Line2D.new()
	line.width = 2.5
	line.default_color = Color(color, 0.8)
	var n := 6
	for k in n + 1:
		var f := float(k) / n
		line.add_point(from.lerp(to, f) + Vector2(0.0, _jit(i + k, 1.6)))
	_root.add_child(line)


func _text(text: String, pos: Vector2, size_px: int, color: Color, width := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if width > 0.0:
		l.size = Vector2(width, size_px + 8)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	_root.add_child(l)
	_rows.push_back(text)
	return l


func _title(text: String) -> void:
	var band := ColorRect.new()
	band.color = HEM
	band.position = Vector2(10, 10)
	band.size = Vector2(viewport.size.x - 20, 46)
	_root.add_child(band)
	_text(text, Vector2(10, 16), 26, CLOTH, viewport.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)


## Regular season: the table. `table` = Standings.table rows, `clinches` =
## Standings.compute_clinches, `names` = id → display name.
func show_standings(league_name: String, table: Array, clinches: Dictionary, names: Dictionary, player_id: String, playoff_spots := 4) -> void:
	kind = "standings"
	if viewport == null or viewport.size != TABLE_SIZE:
		_build(TABLE_SIZE, material == null or material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	_clear()
	_seed = 7
	_chalkboard()
	_chalk_text("%s · standings" % league_name, Vector2(30, 20), 34, _pal("title"), viewport.size.x - 60, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_chalk_line(Vector2(120, 62), Vector2(viewport.size.x - 120, 62), _pal("title"), 1)
	var y := 70.0
	var row_h := 27.0
	for i in table.size():
		var row: Dictionary = table[i]
		var id: String = row["teamId"]
		var mine := id == player_id
		var color: Color = _pal("mine") if mine else _pal("text")
		var c: Dictionary = clinches.get(id, {})
		var mark := ""
		if c.get("topSeed", false):
			mark = " ★"
		elif c.get("playoffs", false):
			mark = " ✓"
		elif c.get("eliminated", false):
			mark = " ✗"
		var k := 10 + i * 5
		_chalk_text("%d." % (i + 1), Vector2(36, y), 26, _pal("dim"), 36, HORIZONTAL_ALIGNMENT_RIGHT, k)
		_chalk_text(str(names.get(id, id)) + mark, Vector2(84, y), 26, color, 290, HORIZONTAL_ALIGNMENT_LEFT, k + 1)
		_chalk_text("%d - %d" % [int(row["w"]), int(row["l"])], Vector2(372, y), 26, color, 100, HORIZONTAL_ALIGNMENT_RIGHT, k + 2)
		y += row_h
		if i == playoff_spots - 1:
			_chalk_line(Vector2(36, y + 1), Vector2(viewport.size.x - 40, y + 1), _pal("dim"), k + 3)
			y += 4.0
	_redraw()


## Playoffs: the bracket. `series` = season["series"].
func show_bracket(league_name: String, series: Array, names: Dictionary, champion_id: String, days := 14) -> void:
	kind = "bracket"
	if viewport == null or viewport.size != TABLE_SIZE:
		_build(TABLE_SIZE, material == null or material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	_clear()
	_seed = 11
	_chalkboard()
	_chalk_text("%s · playoffs" % league_name, Vector2(30, 20), 34, _pal("title"), viewport.size.x - 60, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_chalk_line(Vector2(120, 62), Vector2(viewport.size.x - 120, 62), _pal("title"), 1)
	var y := 78.0
	if series.is_empty():
		_chalk_text("bracket forms after day %d" % days, Vector2(20, y + 50), 30, _pal("dim"), viewport.size.x - 40, HORIZONTAL_ALIGNMENT_CENTER, 4)
		_redraw()
		return
	var k := 10
	for round_name in ["semifinal", "final"]:
		_chalk_text("semifinals" if round_name == "semifinal" else "final", Vector2(36, y), 24, _pal("dim"), 200, HORIZONTAL_ALIGNMENT_LEFT, k)
		k += 3
		y += 28.0
		var any := false
		for s in series:
			if s["round"] != round_name:
				continue
			any = true
			var done: bool = s["winnerId"] != ""
			var hi := str(names.get(s["highSeedId"], s["highSeedId"]))
			var lo := str(names.get(s["lowSeedId"], s["lowSeedId"]))
			var line := "%s  %d - %d  %s" % [hi, int(s["highWins"]), int(s["lowWins"]), lo]
			if done:
				line += "   → " + str(names.get(s["winnerId"], s["winnerId"]))
			_chalk_text(line, Vector2(56, y), 26, _pal("text"), viewport.size.x - 80, HORIZONTAL_ALIGNMENT_LEFT, k)
			k += 3
			y += 30.0
		if not any:
			_chalk_text("tbd", Vector2(56, y), 26, _pal("dim"), 200, HORIZONTAL_ALIGNMENT_LEFT, k)
			k += 3
			y += 30.0
		y += 4.0
	if champion_id != "":
		_chalk_text("champs: %s" % str(names.get(champion_id, champion_id)), Vector2(20, y), 30, _pal("mine"), viewport.size.x - 40, HORIZONTAL_ALIGNMENT_CENTER, k)
	_redraw()


## The small cage banner: dark cloth, cream text.
func show_label(text: String) -> void:
	kind = "label"
	if viewport == null or viewport.size != LABEL_SIZE:
		_build(LABEL_SIZE, false)
	_clear()
	_cloth(DARK_CLOTH, HEM)
	var rule := ColorRect.new()
	rule.color = CREAM
	rule.position = Vector2(40, 118)
	rule.size = Vector2(viewport.size.x - 80, 3)
	_root.add_child(rule)
	_text(text, Vector2(10, 44), 54, CREAM, viewport.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	_redraw()


## Every text line currently drawn — what the tests snapshot.
func rows() -> Array[String]:
	return _rows
