class_name MatchEndOverlay
extends CanvasLayer
## The league match-end page (design "League Match End", docs/HOME.md →
## Results): plays between the final buzzer and the post-match page. One
## clock (`_t`) drives a schedule of small animations — the tag rises, the
## headline slams in on a win (with a white flash, rays and confetti) or
## sinks and shakes on a loss, the score rises, then the stakes block: the
## record flips and the place chip pops (regular season), the bracket — the
## final over both semis — pops this game's number and strikes the beaten
## (playoffs), or the champions page (39b) drops the trophy. The rewards row pops last; from READY_S a blinking
## TAP TO CONTINUE accepts a tap anywhere → `continued`. Built from
## MatchEndCopy.state() so tests step it off-tree.

signal continued

const W := 720.0
const H := 1280.0
const READY_S := 3.0
## Design 15a's rows (2026-10-30, drawn on the 720×1560 screen; minus the
## 140 px the centred 1280 band sits below its top): the tag, the headline,
## the score, the record panel, the sub line under it, the rewards; the
## rays turn about RAYS_Y. TAP TO CONTINUE pins CONTINUE_UP above the
## screen's bottom edge instead (continue_y).
const TAG_Y := 212.0
const HEAD_Y := 362.0
const SCORE_Y := 475.0
const RECORD_Y := 643.0
const SUB_Y := 896.0
const REWARDS_Y := 970.0
const RAYS_Y := 437.0
const CONTINUE_UP := 130.0
const GOLD := MatchEndCopy.GOLD
const ORANGE := MatchEndCopy.ORANGE
const CREAM := MatchEndCopy.CREAM
const INK := Color("#221C18")
const DARK := Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0)
const CARD_COLORS := {"fire": MatchEndCopy.ORANGE, "ice": MatchEndCopy.BLUE, "magnet": Color("#D0443A")}

var _t := 0.0
var _v: Dictionary = {}
var _root: Control
var _anims: Array = []
var _rays: PrizeRays
var _confetti: Confetti
var _flash: ColorRect
var _continue: Label
var _sound_done := false
var _sound_at := 0.35
var _ready_s := READY_S
var _done := false
var _button: Control          # the CONTINUE button (design 39a/39b), else the blinking label
var _meter: XpMeter           # 39b's champions-bonus bar


func _init() -> void:
	layer = 40


# ---- build ----------------------------------------------------------------------


func build(v: Dictionary) -> Control:
	_v = v
	_t = 0.0
	_anims.clear()
	_rows.clear()
	_button = null
	_meter = null
	_ready_s = float(v.get("ready_s", READY_S))
	_sound_at = float(Dictionary(v.get("sound", {})).get("at", 0.35)) if v.get("sound", null) is Dictionary else 0.35
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "MatchEndPage"
	UiLayout.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_input)
	add_child(_root)
	_backdrop(float(v.get("scrim", 0.6)))
	# Rays and confetti sit under everything else.
	var rays_col: Color = v.get("rays", Color.TRANSPARENT)
	if rays_col.a > 0.0:
		_rays = PrizeRays.new(rays_col)
		_rays.name = "Rays"
		_rays.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_rays.position = Vector2(W * 0.5 - 800.0, float(v.get("rays_y", RAYS_Y)) - 800.0)
		_rays.size = Vector2(1600, 1600)
		_rays.speed_deg = 360.0 / maxf(float(v.get("spin_s", 30.0)), 1.0)
		_rays.alpha = 0.32
		_root.add_child(_rays)
		_anim(_rays, "fadein", float(v.get("rays_at", 0.3)), 0.6)
	_confetti = Confetti.new(int(v.get("confetti_n", 0)), Array(v.get("palette", [])), 7)
	_root.add_child(_confetti)
	_tag(str(v.get("tag", "")), v.get("tag_color", CREAM), float(v.get("tag_y", TAG_Y)))
	_head(str(v.get("head", "")), int(v.get("head_size", 64)), v.get("head_color", CREAM), bool(v.get("win_anim", false)),
		float(v.get("head_y", HEAD_Y)), float(v.get("head_at", 0.35)))
	if not bool(v.get("no_score", false)):
		_score(v)
	var sub_y := SUB_Y
	match str(v.get("block", "record")):
		"record":
			_record_block(Dictionary(v.get("record", {})))
		"bracket":
			_bracket_block(Dictionary(v.get("bracket", {})))
		"standings":
			_standings_block(Dictionary(v.get("standings", {})))
			_matchup_block(Dictionary(v.get("matchup", {})))
		"champion":
			_champion_block(v)
	if str(v.get("sub", "")) != "":
		var sub := _label(str(v["sub"]), 16, CREAM, false)
		sub.name = "Sub"
		_centre(sub, float(v.get("sub_y", sub_y)))
		_anim(sub, "rise", float(v.get("sub_at", 2.1)), 0.4)
	if not bool(v.get("no_rewards", false)):
		_rewards(int(v.get("ticket_count", 0)), str(v.get("drop", "")))
	if v.get("button", null) is Dictionary:
		_continue_button(Dictionary(v["button"]))
	else:
		_continue = _label("TAP TO CONTINUE", 16, CREAM, true)
		_continue.name = "Continue"
		_centre(_continue, continue_y())
		_continue.visible = false
		_anim(_continue, "blink", _ready_s, 1.0)
	if bool(v.get("flash", false)):
		_flash = ColorRect.new()
		_flash.name = "Flash"
		_flash.color = Color.WHITE
		UiLayout.full_screen_fill(_flash)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.modulate.a = 0.0
		_root.add_child(_flash)
		_anim(_flash, "flash", float(v.get("flash_at", 0.35)), 0.45)
	step(0.0)
	return _root


func _backdrop(scrim: float) -> void:
	var base := ColorRect.new()
	base.name = "Base"
	base.color = Color("#171311")
	# Past the band to the screen's edges (the root keeps the band's coordinates
	# for everything placed on it), and a tap out there still reaches the root.
	UiLayout.full_screen_fill(base)
	base.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(base)
	for spec in [["Hall", "cage_hall.png", 330.0, 180.0, Vector2(720, 180)], ["Carpet", "cage_carpet.png", 510.0, H - 510.0, Vector2(192, 192)]]:
		var path := "res://assets/textures/%s" % spec[1]
		if not ResourceLoader.exists(path):
			continue
		var tr := TextureRect.new()
		tr.name = spec[0]
		tr.texture = load(path)
		tr.position = Vector2(-UiLayout.offset().x, spec[2])
		# The carpet runs on under the band to the screen's bottom edge.
		tr.size = Vector2(UiLayout.canvas().x if UiLayout.canvas().x > 0.0 else W, spec[3] + (UiLayout.offset().y if spec[0] == "Carpet" else 0.0))
		tr.stretch_mode = TextureRect.STRETCH_TILE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(tr)
	var sc := ColorRect.new()
	sc.name = "Scrim"
	sc.color = Color(DARK, scrim)
	UiLayout.full_screen_fill(sc)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(sc)


func _label(text: String, size_: int, color: Color, display := true) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", RetroTheme.OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A bordered pixel box: 2 px border, a fill, an optional hard shadow.
static func _box(border: Color, fill: Color, shadow := true, shadow_color := INK) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	if shadow:
		sb.shadow_color = shadow_color
		sb.shadow_size = 0
		sb.shadow_offset = Vector2(5, 5)
		sb.shadow_size = 1
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	return sb


## Place a control's centre on the page's vertical axis at `y`.
func _centre(c: Control, y: float, w := W, h := 40.0) -> void:
	c.position = Vector2((W - w) * 0.5, y)
	c.size = Vector2(w, h)
	_root.add_child(c)


func _tag(text: String, color: Color, y := TAG_Y) -> void:
	var pill := PanelContainer.new()
	pill.name = "Tag"
	pill.add_theme_stylebox_override("panel", _box(color, Color(DARK, 0.6)))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var star := PixelIcon.new("icon_star", Vector2(18, 18))
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(star)
	var l := _label(text, 16, CREAM, false)
	l.name = "TagText"
	row.add_child(l)
	var holder := CenterContainer.new()
	holder.name = "TagRow"
	holder.position = Vector2(0, y)
	holder.size = Vector2(W, 44)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill)
	_root.add_child(holder)
	_anim(holder, "rise", 0.1, 0.4)


func _head(text: String, size_: int, color: Color, win: bool, y := HEAD_Y, at := 0.35) -> void:
	var box := Control.new()
	box.name = "HeadBox"
	box.position = Vector2(0, y)
	box.size = Vector2(W, 80)
	box.pivot_offset = Vector2(W * 0.5, 40)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, size_, color, true)
	l.name = "Head"
	UiLayout.full_rect(l)
	RetroTheme.dithered(l, Vector2(8, 8))
	box.add_child(l)
	_root.add_child(box)
	if win:
		_anim(box, "slam", at, 0.6)
	else:
		_anim(box, "sink", at, 0.55)
		_anim(box, "shake", at + 0.6, 0.4)


func _score(v: Dictionary) -> void:
	var row := Control.new()
	row.name = "ScoreRow"
	row.position = Vector2(0, SCORE_Y)
	row.size = Vector2(W, 110)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	UiLayout.full_rect(h)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 22)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var won := bool(v.get("won", false))
	for side in [["ScoreYou", str(v.get("score_you", 0)), "YOU", GOLD if won else CREAM], ["dash", "-", "", CREAM],
			["ScoreOpp", str(v.get("score_opp", 0)), str(v.get("opp_first", "")), CREAM]]:
		if side[0] == "dash":
			var d := _label("-", 40, CREAM, true)
			d.name = "Dash"
			d.custom_minimum_size = Vector2(60, 80)
			h.add_child(d)
			continue
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 12)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := _label(side[1], 64, side[3], true)
		n.name = side[0]
		col.add_child(n)
		var who := _label(side[2], 16, CREAM, false)
		who.name = side[0] + "Name"
		col.add_child(who)
		h.add_child(col)
	_root.add_child(row)
	_anim(row, "rise", 0.95, 0.45)


func _record_block(r: Dictionary) -> void:
	var panel := Face.new(CREAM, Color(CREAM, 0.20), true, 2.0, 6.0)
	panel.name = "Record"
	panel.position = Vector2(96, RECORD_Y)
	panel.size = Vector2(528, 220)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var label := _label(str(r.get("label", "")), 16, CREAM, false)
	label.name = "RecordLabel"
	col.add_child(label)
	var clip := Control.new()
	clip.name = "RecordFlip"
	clip.custom_minimum_size = Vector2(300, 64)
	clip.clip_contents = true
	clip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var old := _label(str(r.get("old", "")), 48, CREAM, true)
	old.name = "RecordOld"
	old.position = Vector2.ZERO
	old.size = Vector2(300, 64)
	clip.add_child(old)
	var new_ := _label(str(r.get("new", "")), 48, GOLD if bool(r.get("gold", false)) else CREAM, true)
	new_.name = "RecordNew"
	new_.position = Vector2(0, 64)
	new_.size = Vector2(300, 64)
	clip.add_child(new_)
	col.add_child(clip)
	_anim(old, "outup", 1.9, 0.35, 64.0)
	_anim(new_, "infrom", 1.9, 0.35, 64.0)
	var place := str(r.get("place", ""))
	if place != "":
		var chip := PanelContainer.new()
		chip.name = "Place"
		chip.add_theme_stylebox_override("panel", _box(GOLD if bool(r.get("gold", false)) else Color(CREAM, 0.6), Color(DARK, 0.5), false))
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pl := _label(place, 16, CREAM, false)
		pl.name = "PlaceText"
		chip.add_child(pl)
		col.add_child(chip)
		_anim(chip, "pop", 2.3, 0.35)
	_root.add_child(panel)
	_anim(panel, "rise", 1.3, 0.45)


## The bracket block (design 15a, 2026-10-30): a dotted cream panel holding
## the final over both semis. In the semifinal round the FINAL box sits on
## top (`? VS ?` until a semi is decided) with a stepped line up from each
## semi; in the final round the final's own two rows sit on top under the
## trophy and the semis shrink below. Each row: name, season record, series
## wins; this game's winner pops its number at 1.7 s, a decided series
## strikes its loser at 2.1 s and fades it at 2.3 s.
func _bracket_block(b: Dictionary) -> void:
	var final_style := str(b.get("style", "semis")) == "final"
	var panel := Face.new(CREAM, Color(CREAM, 0.20), true, 2.0, 6.0)
	panel.name = "Bracket"
	panel.position = Vector2(54, 572.0 if final_style else 574.0)
	panel.size = Vector2(W - 54.0 - 60.0, 0)
	panel.pad = Vector4(16, 22, 16, 22)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var fin: Dictionary = b.get("final", {})
	var semis: Array = b.get("semis", [])
	if final_style:
		col.add_child(_final_rows(fin))
	else:
		col.add_child(_final_box(fin))
	# The stepped lines from each semi up into the final.
	var lines := StepLines.new()
	lines.name = "Lines"
	lines.custom_minimum_size = Vector2(0, 20.0 if final_style else 28.0)
	for i in semis.size():
		var sm: Dictionary = semis[i]
		var pts: Array
		if final_style:
			pts = [Vector2(150, 20), Vector2(150, 14), Vector2(170, 14), Vector2(170, 7), Vector2(190, 7), Vector2(190, 0)]
		else:
			pts = [Vector2(170, 28), Vector2(170, 21), Vector2(180, 21), Vector2(180, 14), Vector2(190, 14), Vector2(190, 7), Vector2(200, 7), Vector2(200, 0)]
		if i == 1:
			for k in pts.size():
				pts[k] = Vector2(550.0 - pts[k].x, pts[k].y)
		lines.add_path(pts, sm.get("path", Color(CREAM, 0.35)))
	col.add_child(lines)
	var row := HBoxContainer.new()
	row.name = "Semis"
	row.add_theme_constant_override("separation", 16 if final_style else 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in semis.size():
		var sm: Dictionary = semis[i]
		var box := _semi_small(sm) if final_style else _semi_box(sm)
		box.name = "Semi%d" % (i + 1)
		row.add_child(box)
		if not final_style and bool(sm.get("mine", false)) and bool(sm.get("decided", false)):
			_anim_path(lines, i, 2.3)
	col.add_child(row)
	_root.add_child(panel)
	_anim(panel, "rise", 1.3, 0.45)


## The line's 4 px are centred on the path, 10 px in from the panel's padding
## the way the design's 550-wide svg sits in its 570-wide column.
func _anim_path(lines: StepLines, i: int, at: float) -> void:
	lines.set_progress(i, 0.0)
	_anims.push_back({"node": lines, "kind": "draw", "delay": at, "dur": 0.35, "base": Vector2.ZERO, "extra": float(i)})


static var _grey: ShaderMaterial


## The design's `filter:grayscale(1); opacity:.75` for a trophy nobody holds yet.
static func grey_material() -> ShaderMaterial:
	if _grey == null:
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(vec3(dot(c.rgb, vec3(0.2126, 0.7152, 0.0722))), c.a * 0.75);
}
"""
		_grey = ShaderMaterial.new()
		_grey.shader = sh
	return _grey


## Semifinal round: the FINAL box — a grey trophy, FINAL, `YOU VS ?`.
func _final_box(fin: Dictionary) -> Control:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Face.new(fin.get("line", Color(CREAM, 0.5)), Color(DARK, 0.5), false, 3.0, 5.0)
	box.name = "Final"
	box.custom_minimum_size = Vector2(300, 116)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cup := PixelIcon.new("icon_trophy", Vector2(34, 34))
	cup.name = "FinalCup"
	cup.material = grey_material()
	cup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cup)
	head.add_child(_label(str(fin.get("label", "FINAL")), 20, CREAM, false))
	col.add_child(head)
	var text := _label(str(fin.get("text", "? VS ?")), 22, fin.get("color", CREAM), true)
	text.name = "FinalText"
	text.pivot_offset_ratio = Vector2(0.5, 0.5)
	col.add_child(text)
	if bool(fin.get("pop", false)):
		_anim(text, "pop", 2.6, 0.35)
	holder.add_child(box)
	return holder


## Final round: the gold (or faint) panel with the trophy, FINAL, the game,
## and the final's two rows.
func _final_rows(fin: Dictionary) -> Control:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold := bool(fin.get("gold", false))
	var box := Face.new(GOLD if gold else Color(CREAM, 0.5), Color(GOLD, 0.28) if gold else Color(DARK, 0.5), gold, 3.0, 5.0)
	box.name = "Final"
	box.custom_minimum_size = Vector2(440, 0)
	box.pad = Vector4(18, 8, 18, 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 60)
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(56, 56)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cup := PixelIcon.new("icon_trophy", Vector2(56, 56), 4.0)
	cup.name = "FinalCup"
	cup.pivot_offset = Vector2(28, 28)
	slot.add_child(cup)
	if gold:
		_anim(cup, "pop", 2.6, 0.5)
		_anim(cup, "bob", 3.1, 1.6)
	else:
		cup.material = grey_material()
	head.add_child(slot)
	var fl := _label(str(fin.get("label", "FINAL")), 18, CREAM, false)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fl)
	var game := _label(str(fin.get("game", "")), 16, CREAM, false)
	game.name = "FinalGame"
	head.add_child(game)
	col.add_child(head)
	for r in fin.get("rows", []):
		col.add_child(_team_row(r, 50.0, 24, 36, 400.0 - 6.0))
	holder.add_child(box)
	return holder


## Semifinal round: one semi — its head, its two rows.
func _semi_box(sm: Dictionary) -> Control:
	var gold := bool(sm.get("gold", false))
	var box := Face.new(sm.get("line", Color(CREAM, 0.35)), Color(GOLD, 0.22) if gold else Color(DARK, 0.5), gold, 2.0, 5.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.pad = Vector4(16, 10, 16, 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var head := _label("%s · %s" % [sm.get("head", ""), sm.get("note", "")], 16, CREAM, false)
	head.name = "SemiHead"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(head)
	for r in sm.get("rows", []):
		col.add_child(_team_row(r, 56.0, 24, 36, (W - 54.0 - 60.0 - 32.0 - 24.0) * 0.5 - 32.0))
	return box


## Final round: a small semi — the head, two faint rows.
func _semi_small(sm: Dictionary) -> Control:
	var box := Face.new(sm.get("line", Color(CREAM, 0.5)), Color(DARK, 0.5), false, 2.0, 4.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.pad = Vector4(12, 8, 12, 8)
	box.modulate.a = 0.9
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var head := _label(str(sm.get("head", "")), 14, CREAM, false)
	head.name = "SemiHead"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(head)
	for r in sm.get("rows", []):
		var won := bool(r.get("won", false))
		var c := GOLD if won else CREAM
		var line := Control.new()
		line.name = "Row_" + str(r.get("id", ""))
		line.custom_minimum_size = Vector2(0, 28)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.modulate.a = 1.0 if won or not bool(r.get("struck", false)) else 0.6
		var h := HBoxContainer.new()
		UiLayout.full_rect(h)
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(h)
		var nm := _label(str(r.get("name", "")), 14, c, true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(_label(str(r.get("wins", 0)), 16, c, true))
		if bool(r.get("struck", false)):
			var st := StrikeLine.new(2.0, false)
			st.name = "Strike"
			st.anchor_right = 1.0
			st.offset_left = -3.0
			st.offset_right = 3.0
			st.offset_top = 13.0
			st.offset_bottom = 15.0
			line.add_child(st)
		col.add_child(line)
	return box


## One team's row: the name (shrunk to fit), its record, the series wins.
func _team_row(r: Dictionary, h_px: float, name_px: int, wins_px: int, width: float) -> Control:
	var won := bool(r.get("won", false))
	var c := GOLD if won else CREAM
	var line := Control.new()
	line.name = "Row_" + str(r.get("id", ""))
	line.custom_minimum_size = Vector2(0, h_px)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	UiLayout.full_rect(h)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(h)
	var left := HBoxContainer.new()
	left.name = "Who"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	var name_ := str(r.get("name", ""))
	var rec := str(r.get("rec", ""))
	# Press Start is monospaced: a glyph is as wide as the size. Long first
	# names shrink so the name, record and wins stay on the row.
	var room := width - float(wins_px) * str(r.get("wins", 0)).length() - 10.0 - (rec.length() * 10.0 + 10.0 if rec != "" else 0.0)
	var px := mini(name_px, int(floor(room / maxf(float(name_.length()), 1.0))))
	var nm := _label(name_, maxi(px, 12), c, true)
	nm.name = "Name"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(nm)
	if rec != "":
		var rl := _label(rec, 14, Color("#D9D9D9"), false)
		rl.name = "Rec"
		left.add_child(rl)
	var wins := _label(str(r.get("wins", 0)), wins_px, c, true)
	wins.name = "Wins"
	wins.pivot_offset_ratio = Vector2(0.5, 0.5)
	h.add_child(wins)
	if bool(r.get("pop", false)):
		_anim(wins, "pop", 1.7, 0.35)
	if bool(r.get("struck", false)):
		_anim(left, "fade_to", 2.3, 0.4, 0.65)
		var st := StrikeLine.new(3.0, true)
		st.name = "Strike"
		st.position = Vector2(-4, h_px * 0.5 - 2.0)
		st.size = Vector2(0, 3)
		line.add_child(st)
		_anim(st, "strike", 2.1, 0.35, width + 8.0)
	return line


# ---- 39a CLINCHED: the standings climb, the matchup card ----------------------------

const ROW_H := 50.0
const PANEL_X := 60.0
const PANEL_W := 600.0

var _rows := {}   # team id → its row Control (the clinch standings)


## The standings panel: 8 rows at their pre-match order; at 1.0 s your
## record flips, at 1.4 s the rows slide to the post-match order (yours on
## top of the others), at 2.1 s your row turns gold and the IN chip pops.
## A dashed gold line under the last playoff spot.
func _standings_block(st: Dictionary) -> void:
	var before: Array = st.get("rows_before", [])
	var after: Array = st.get("rows_after", [])
	var n := before.size()
	var pad := 16.0
	var head_h := 36.0
	var panel := PanelContainer.new()
	panel.name = "Standings"
	panel.position = Vector2(PANEL_X, 284)
	panel.size = Vector2(PANEL_W, pad * 2.0 + head_h + 10.0 + ROW_H * n)
	panel.add_theme_stylebox_override("panel", _box(CREAM, Color(CREAM, 0.12)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := Control.new()
	inner.name = "Inner"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)
	var hd := _label(str(st.get("head", "STANDINGS")), 18, CREAM, true)
	hd.name = "StandingsHead"
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hd.position = Vector2(0, 0)
	hd.size = Vector2(300, head_h)
	inner.add_child(hd)
	var note := _label(str(st.get("note", "")), 16, CREAM, false)
	note.name = "StandingsNote"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.position = Vector2(PANEL_W - 32.0 - 300.0, 0)
	note.size = Vector2(300, head_h)
	inner.add_child(note)
	var rows := Control.new()
	rows.name = "Rows"
	rows.position = Vector2(-12.0, head_h + 10.0)
	rows.size = Vector2(PANEL_W - 32.0 + 24.0, ROW_H * n)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(rows)
	var after_index := {}
	for i in after.size():
		after_index[str(after[i]["id"])] = i
	for i in n:
		var r: Dictionary = before[i]
		var id := str(r["id"])
		var you := bool(r.get("you", false))
		var row := Control.new()
		row.name = "Row_%s" % id
		row.position = Vector2(0, ROW_H * i)
		row.size = Vector2(rows.size.x, ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i % 2 == 1 and not you:
			var stripe := ColorRect.new()
			stripe.color = Color(CREAM, 0.05)
			UiLayout.full_rect(stripe)
			stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(stripe)
		if you:
			var orange := Panel.new()
			orange.name = "RowOrange"
			orange.add_theme_stylebox_override("panel", _box(ORANGE, Color(ORANGE, 0.3), false))
			UiLayout.full_rect(orange)
			orange.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(orange)
			var gold := Panel.new()
			gold.name = "RowGold"
			gold.add_theme_stylebox_override("panel", _box(GOLD, Color(GOLD, 0.35), false))
			UiLayout.full_rect(gold)
			gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gold)
			_anim(gold, "fadein", 2.1, 0.2)
		var rank := _label(str(i + 1), 16, CREAM, true)
		rank.name = "Rank"
		rank.position = Vector2(12, 0)
		rank.size = Vector2(40, ROW_H)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(rank)
		var after_i: int = int(after_index.get(id, i))
		if after_i != i:
			# The rank renumbers as the rows move.
			var rank2 := _label(str(after_i + 1), 16, CREAM, true)
			rank2.name = "RankAfter"
			rank2.position = Vector2(12, 0)
			rank2.size = Vector2(40, ROW_H)
			rank2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			rank2.modulate.a = 0.0
			row.add_child(rank2)
			_anim(rank, "hide", 1.4, 0.01)
			_anim(rank2, "show", 1.4, 0.01)
		var nm := _label(str(r.get("name", "")), 16, GOLD if you else CREAM, true)
		nm.name = "Name"
		nm.position = Vector2(64, 0)
		nm.size = Vector2(300, ROW_H)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(nm)
		if you:
			var chip := PanelContainer.new()
			chip.name = "In"
			chip.add_theme_stylebox_override("panel", _box(GOLD, GOLD, true))
			chip.position = Vector2(64.0 + 8.0 + str(r.get("name", "")).length() * 16.0 + 12.0, 10)
			chip.size = Vector2(60, 30)
			chip.pivot_offset = Vector2(30, 15)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cl := UiFont.label(str(st.get("chip", "IN")), 14, INK, UiFont.display())
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			chip.add_child(cl)
			row.add_child(chip)
			_anim(chip, "pop", 2.1, 0.35)
		# The record: yours flips from before to after at 1.0 s in a clip.
		var rec_w := 110.0
		var clip := Control.new()
		clip.name = "RecordClip"
		clip.position = Vector2(rows.size.x - 12.0 - rec_w, 0)
		clip.size = Vector2(rec_w, ROW_H)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(clip)
		var rec := _label(str(r.get("record", "")), 16, CREAM, true)
		rec.name = "Record"
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rec.position = Vector2.ZERO
		rec.size = Vector2(rec_w, ROW_H)
		clip.add_child(rec)
		if you:
			var rec2 := _label(str(st.get("record_after", "")), 16, CREAM, true)
			rec2.name = "RecordAfter"
			rec2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rec2.position = Vector2(0, ROW_H)
			rec2.size = Vector2(rec_w, ROW_H)
			clip.add_child(rec2)
			_anim(rec, "outup", 1.0, 0.35, ROW_H)
			_anim(rec2, "infrom", 1.0, 0.35, ROW_H)
		rows.add_child(row)
		_rows[id] = row
		var target: int = int(after_index.get(id, i))
		if target != i:
			_anim(row, "moveto", 1.4, 0.55, ROW_H * target)
		if you:
			rows.move_child(row, -1)   # yours passes over the others
	var spots := int(st.get("spots", 4))
	var label_w := 12.0 * str(st.get("line_label", "PLAYOFF LINE")).length() * 0.62 + 8.0
	var line := DashLine.new(GOLD)
	line.name = "PlayoffLine"
	line.position = Vector2(0, ROW_H * spots - 2.0)
	line.size = Vector2(rows.size.x - 12.0 - label_w - 8.0, 4)
	rows.add_child(line)
	rows.move_child(line, -1)
	# The label at the line's right end, centred on it (between the rows'
	# records, which sit mid-row).
	var ll := _label(str(st.get("line_label", "PLAYOFF LINE")), 12, GOLD, false)
	ll.name = "PlayoffLineLabel"
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ll.position = Vector2(rows.size.x - 12.0 - label_w, ROW_H * spots - 8.0)
	ll.size = Vector2(label_w, 16)
	rows.add_child(ll)
	_root.add_child(panel)
	_anim(panel, "rise", 0.3, 0.45)
	_anim(panel, "dim", 2.5, 0.4)


## The gold matchup card: SEMIFINAL · BEST OF 3 / GAME 1 · AWAY, NO. 3 YOU
## VS NO. 2 OLLIE.
func _matchup_block(m: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "Matchup"
	panel.position = Vector2(PANEL_X, 920)
	panel.size = Vector2(PANEL_W, 150)
	panel.add_theme_stylebox_override("panel", _box(GOLD, Color(GOLD, 0.2)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)
	var w := PANEL_W - 32.0
	for spec in [["MatchupTitle", m.get("title", ""), 0.0, 20.0, HORIZONTAL_ALIGNMENT_LEFT, false],
			["MatchupLine", m.get("line", ""), 0.0, 20.0, HORIZONTAL_ALIGNMENT_RIGHT, false],
			["MatchupYou", m.get("you", ""), 44.0, 16.0, HORIZONTAL_ALIGNMENT_LEFT, false],
			["MatchupYouName", m.get("you_name", "YOU"), 70.0, 26.0, HORIZONTAL_ALIGNMENT_LEFT, true],
			["MatchupVs", m.get("vs", "VS"), 60.0, 24.0, HORIZONTAL_ALIGNMENT_CENTER, true],
			["MatchupOpp", m.get("opp", ""), 44.0, 16.0, HORIZONTAL_ALIGNMENT_RIGHT, false],
			["MatchupOppName", m.get("opp_name", ""), 70.0, 26.0, HORIZONTAL_ALIGNMENT_RIGHT, true]]:
		var gold: bool = spec[0] == "MatchupYouName"
		var l := _label(str(spec[1]), int(spec[3]) if bool(spec[5]) else 16, GOLD if gold else CREAM, bool(spec[5]))
		l.name = spec[0]
		l.horizontal_alignment = spec[4]
		l.position = Vector2(0, float(spec[2]))
		l.size = Vector2(w, 26.0 if bool(spec[5]) else 20.0)
		inner.add_child(l)
	_root.add_child(panel)
	_anim(panel, "rise", 3.2, 0.4)


# ---- 39b CHAMPIONS: the trophy drops, the titles row, the bonus cards -------------

const CUP_PX := 240.0
const CUP_Y := 250.0


func _champion_block(v: Dictionary) -> void:
	# The trophy sinks in from above (0.3–0.9 s) and the whole page quakes.
	var holder := Control.new()
	holder.name = "Cup"
	holder.position = Vector2((W - CUP_PX) * 0.5, CUP_Y)
	holder.size = Vector2(CUP_PX, CUP_PX)
	holder.pivot_offset = Vector2(CUP_PX * 0.5, CUP_PX * 0.5)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cup := PixelIcon.new("icon_trophy", Vector2(CUP_PX, CUP_PX), 10.0)
	cup.name = "CupIcon"
	cup.size = Vector2(CUP_PX, CUP_PX)
	holder.add_child(cup)
	_root.add_child(holder)
	_anim(holder, "sinkfrom", 0.3, 0.6, 320.0)
	_anim(holder, "bob", 1.6, 1.6)
	_anim(_root, "quake", 0.85, 0.4)
	var line := _label(str(v.get("line", "")), 16, CREAM, false)
	line.name = "Line"
	_centre(line, 612.0)
	_anim(line, "rise", 1.4, 0.4)
	_titles_row(int(Dictionary(v.get("trophy", {})).get("titles", 1)), 660.0, 1.7, 2.2)
	# The two cards: the champions bonus XP with its bar, the ticket haul.
	var cards: Dictionary = v.get("cards", {}) if v.get("cards", null) is Dictionary else {}
	var xp: Dictionary = cards.get("xp", {}) if cards.get("xp", null) is Dictionary else {}
	var card_w := 316.0
	var card_h := 150.0
	var xp_card := PanelContainer.new()
	xp_card.name = "XpCard"
	xp_card.position = Vector2(36, 760)
	xp_card.size = Vector2(card_w, card_h)
	xp_card.pivot_offset = Vector2(card_w * 0.5, card_h * 0.5)
	xp_card.add_theme_stylebox_override("panel", _box(CREAM, Color(CREAM, 0.12)))
	xp_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_card.add_child(col)
	var amount := _label(str(xp.get("label", "")), 24, GOLD, true)
	amount.name = "XpAmount"
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(amount)
	var m: Dictionary = xp.get("meter", {}) if xp.get("meter", null) is Dictionary else {}
	if not m.is_empty():
		_meter = XpMeter.new(m, card_w - 32.0)
		_meter.manual = true
		_meter.fill_s = 1.1
		var row: Control = _meter.get_node_or_null("Row")
		if row != null:
			row.visible = false   # the card says it in words; the bar is the meter
		var bar: Control = _meter.get_node_or_null("Bar")
		if bar != null:
			bar.position.y = 0.0
		_meter.custom_minimum_size = Vector2(card_w - 32.0, XpMeter.BAR_H + 4.0)
		_meter.size = _meter.custom_minimum_size
		_meter.play(2.6)
		col.add_child(_meter)
	var sub := _label(str(xp.get("sub", "")), 14, CREAM, false)
	sub.name = "XpSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(sub)
	_root.add_child(xp_card)
	_anim(xp_card, "pop", 2.5, 0.4)
	var tickets := int(cards.get("tickets_n", 0))
	_ticket_box = TicketBox.new(card_h - ShadowStyle.OFFSET, 64.0, 32, 14, 18.0, 14.0, 60.0, 0.0, card_w - ShadowStyle.OFFSET)
	_ticket_box.name = "TicketsCard"
	_ticket_box.position = Vector2(368, 760)
	_ticket_box.pivot_offset = Vector2(card_w * 0.5, card_h * 0.5)
	_ticket_box.set_count(0)
	_root.add_child(_ticket_box)
	var amt: Label = _ticket_box.find_child("TicketsBig", true, false)
	if amt != null:
		amt.name = "TicketsText"
	_anim(_ticket_box, "pop", 2.5, 0.4)
	_stream = TicketStream.new()
	_stream.name = "Stream"
	_stream.manual = true
	_stream.max_flyers = 12
	_stream.spread = Vector2(160, 60)
	_stream.lift = 120.0
	_stream.wobble = 30.0
	_stream.count_changed.connect(func(n: int) -> void:
		_ticket_box.set_count(n)
		_ticket_box.bump()
	)
	_root.add_child(_stream)
	var from := Vector2(W * 0.5, CUP_Y + CUP_PX * 0.5)
	_stream.play(from, from, tickets, 2.7)


## TITLES · cups · xN: the newest cup pops in at `pop_at`.
func _titles_row(titles: int, y: float, at: float, pop_at: float) -> void:
	var row := HBoxContainer.new()
	row.name = "Titles"
	row.position = Vector2(0, y)
	row.size = Vector2(W, 44)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := _label("TITLES", 18, CREAM, false)
	row.add_child(tl)
	var cups := HBoxContainer.new()
	cups.add_theme_constant_override("separation", 8)
	cups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in mini(titles, 6):
		var small := Control.new()
		small.name = "Title%d" % i
		small.custom_minimum_size = Vector2(44, 44)
		small.pivot_offset = Vector2(22, 22)
		small.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := PixelIcon.new("icon_trophy", Vector2(44, 44), 3.0)
		ic.size = Vector2(44, 44)
		small.add_child(ic)
		cups.add_child(small)
		if i == mini(titles, 6) - 1:
			_anim(small, "pop", pop_at, 0.45)
	row.add_child(cups)
	var count := _label("X%d" % titles, 24, GOLD, true)
	count.name = "TitleCount"
	count.pivot_offset = Vector2(24, 14)
	row.add_child(count)
	_anim(count, "pop", pop_at, 0.35)
	_root.add_child(row)
	_anim(row, "rise", at, 0.4)


## The orange CONTINUE · TO THE POST-MATCH button (design 39a/39b): rises at
## `at`, takes taps only once risen.
func _continue_button(b: Dictionary) -> void:
	var card := ShadowCard.new(RetroTheme.c("orange"))
	card.name = "ContinueButton"
	card.position = Vector2(36, 1100)
	card.size = Vector2(648, 120)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(inner)
	card.add_child(inner)
	var title := _label(str(b.get("title", "CONTINUE")), 28, CREAM, true)
	title.name = "ButtonTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.position = Vector2(30, 24)
	title.size = Vector2(500, 32)
	inner.add_child(title)
	var sub := _label(str(b.get("sub", "")), 16, CREAM, false)
	sub.name = "ButtonSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.position = Vector2(30, 70)
	sub.size = Vector2(500, 20)
	inner.add_child(sub)
	var chev := _label(">", 32, CREAM, true)
	chev.position = Vector2(648 - 30 - 40, 40)
	chev.size = Vector2(40, 40)
	inner.add_child(chev)
	card.pressed.connect(skip)
	_root.add_child(card)
	_button = card
	_anim(card, "rise", float(b.get("at", _ready_s)), 0.4)


func continue_button() -> Control:
	return _button


## The clinch standings: a row's current y (tests).
func row_y(id: String) -> float:
	var row: Control = _rows.get(id, null)
	return row.position.y if row != null else -1.0


func meter_frac() -> float:
	return _meter.fill_frac() if _meter != null else 0.0


## TAP TO CONTINUE's top in band coordinates: CONTINUE_UP above the
## screen's bottom edge (1430 on the 1560 design; 1150 on a 9:16 screen).
func continue_y() -> float:
	return H + UiLayout.offset().y - CONTINUE_UP


func ready_s() -> float:
	return _ready_s


## The tickets box (design 15a, 2026-10-24: the gold box with the ticket icon,
## `+N` over TICKETS) pops in with the card drop; then the stream arcs from
## the score into it — one flyer per two tickets, fifteen at most — and the
## count ticks up from +0 as each lands (TicketStream, stepped by this clock).
const STREAM_START := 2.75
const STREAM_FROM := Vector2(360, 470)

var _ticket_box: TicketBox
var _stream: TicketStream
var _stream_aimed := false


func _rewards(tickets: int, drop: String) -> void:
	var row := Control.new()
	row.name = "Rewards"
	row.position = Vector2(0, REWARDS_Y)
	row.size = Vector2(W, 84)
	row.pivot_offset = Vector2(W * 0.5, 42)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	UiLayout.full_rect(h)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	_ticket_box = TicketBox.new(84.0 - ShadowStyle.OFFSET, 52.0, 26, 14, 18.0, 14.0, 52.0, float(str(tickets).length() + 1) * 26.0)
	_ticket_box.set_count(0 if tickets > 0 else 0)
	_ticket_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_ticket_box)
	var amount: Label = _ticket_box.find_child("TicketsBig", true, false)
	amount.name = "TicketsText"
	if drop != "":
		var card := CardDefs.get_card(drop)
		var kind := str(Dictionary(card.get("effect", {})).get("kind", ""))
		var col: Color = CARD_COLORS.get(kind, GOLD)
		var tile := Control.new()
		tile.name = "Drop"
		tile.custom_minimum_size = Vector2(300, 84)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := Panel.new()
		bg.name = "DropBg"
		bg.add_theme_stylebox_override("panel", _box(col, Color(col, 0.35)))
		UiLayout.full_rect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(bg)
		var tv := VBoxContainer.new()
		tv.position = Vector2(96, 0)
		tv.size = Vector2(190, 84)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.add_theme_constant_override("separation", 8)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(tv)
		var nm := _label(str(card.get("name", drop)).to_upper(), 16, CREAM, true)
		nm.name = "DropName"
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tv.add_child(nm)
		var nc := _label("NEW CARD", 16, CREAM, false)
		nc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tv.add_child(nc)
		if not card.is_empty():
			var art := ModeCards.art(card, Vector2(66, 88), 4.0)
			art.name = "DropArt"
			art.position = Vector2(14, 84.0 - 8.0 - 88.0)
			art.rotation = deg_to_rad(-6.0)
			art.pivot_offset = Vector2(33, 44)
			tile.add_child(art)
			_anim(art, "pop", 2.75, 0.4)
		h.add_child(tile)
	_root.add_child(row)
	_anim(row, "pop", 2.5, 0.4)
	# The stream: aimed at the box's icon once the row has laid out (the first step past the pop).
	_stream = TicketStream.new()
	_stream.name = "Stream"
	_stream.manual = true
	_stream.spread = Vector2(160, 50)
	_stream.lift = 90.0
	_stream.wobble = 30.0
	_stream.count_changed.connect(func(n: int) -> void:
		_ticket_box.set_count(n)
		_ticket_box.bump()
	)
	_root.add_child(_stream)
	_stream.play(STREAM_FROM, STREAM_FROM, tickets, STREAM_START)


func tickets_text() -> String:
	return _ticket_box.count_text() if _ticket_box != null else ""


# ---- the clock ------------------------------------------------------------------


func _anim(node: CanvasItem, kind: String, delay: float, dur: float, extra := 0.0) -> void:
	var base := Vector2.ZERO
	if node is Control:
		base = (node as Control).position
	_anims.push_back({"node": node, "kind": kind, "delay": delay, "dur": dur, "base": base, "extra": extra})
	if kind in ["rise", "pop", "slam", "sink", "fadein", "slidein", "infrom", "sinkfrom"]:
		node.modulate.a = 0.0


static func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 3.0)


static func _ease_in(p: float) -> float:
	return p * p * p


## Advance the page by dt and lay every animated element where it belongs.
func step(dt: float) -> void:
	_t += dt
	if not _sound_done and _t >= _sound_at:
		_sound_done = true
		_play_sound()
	if _meter != null:
		_meter.step(dt)
	if _button != null:
		_button.mouse_filter = Control.MOUSE_FILTER_STOP if ready_to_continue() else Control.MOUSE_FILTER_IGNORE
	if _stream != null:
		if not _stream_aimed and _t >= 2.5 and _ticket_box != null and _ticket_box.is_inside_tree():
			_stream.to = _ticket_box.icon_center()
			_stream_aimed = true
		_stream.step(dt)
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
			"sink":
				node.modulate.a = p
				if c != null:
					var y := 0.0
					if p < 0.7:
						y = lerpf(-60.0, 8.0, _ease_out(p / 0.7))
					else:
						y = lerpf(8.0, 0.0, (p - 0.7) / 0.3)
					c.position = Vector2(c.position.x, base.y + y)
			"shake":
				if c != null and _t >= delay:
					var keys := [0.0, -10.0, 9.0, -6.0, 4.0, 0.0]
					var f := p * 5.0
					var i := mini(int(f), 4)
					c.position.x = base.x + lerpf(float(keys[i]), float(keys[i + 1]), f - i)
			"slidein":
				node.modulate.a = p
				if c != null:
					c.position = base + Vector2(-120.0 * (1.0 - _ease_out(p)), 0)
			"strike":
				if c != null:
					c.size.x = float(a["extra"]) * _ease_out(p)
			"outup":
				if c != null:
					c.position = base + Vector2(0, -float(a["extra"]) * _ease_in(p))
			"infrom":
				node.modulate.a = 1.0 if p > 0.0 else 0.0
				if c != null:
					c.position = base + Vector2(0, -float(a["extra"]) * _ease_out(p))
			"bob":
				if c != null and _t >= delay:
					c.position = base + Vector2(0, -10.0 * (0.5 - 0.5 * cos(TAU * (_t - delay) / dur)))
			"moveto":
				if c != null:
					c.position = Vector2(base.x, lerpf(base.y, float(a["extra"]), _ease_out(p)))
			"sinkfrom":
				node.modulate.a = minf(1.0, p * 3.0) if p > 0.0 else 0.0
				if c != null:
					var y := lerpf(-float(a["extra"]), 10.0, _ease_in(p / 0.8)) if p < 0.8 else lerpf(10.0, 0.0, (p - 0.8) / 0.2)
					c.position = Vector2(c.position.x, base.y + y)
			"quake":
				if c != null:
					var k := (1.0 - p) if (_t >= delay and p < 1.0) else 0.0
					c.position = base + Vector2(sin(p * TAU * 4.0) * 10.0 * k, cos(p * TAU * 3.0) * 6.0 * k)
			"hide":
				node.modulate.a = 0.0 if _t >= delay else 1.0
			"show":
				node.modulate.a = 1.0 if _t >= delay else 0.0
			"dim":
				node.modulate = Color.WHITE.lerp(Color(0.55, 0.55, 0.55), p)
			"fade_to":
				node.modulate.a = lerpf(1.0, float(a["extra"]), p)
			"draw":
				# steps(8): the stepped line draws itself in eight ticks.
				(node as StepLines).set_progress(int(a["extra"]), floor(p * 8.0) / 8.0)
			"blink":
				node.visible = _t >= delay and fmod(_t - delay, dur) < dur * 0.5
			"flash":
				node.modulate.a = 0.9 * (1.0 - p) if _t >= delay else 0.0


func _process(delta: float) -> void:
	step(delta)


## A match won chimes (the small chime); the championship gets the big one
## (Ross, 2026-10-26); every loss is the loss sting.
func _play_sound() -> void:
	if _v.get("sound", null) is Dictionary:
		match str(Dictionary(_v["sound"]).get("name", "")):
			"chime_win":
				Sfx.chime_win()
				return
			"chime_big":
				Sfx.chime_big()
				return
	match str(_v.get("kind", "")):
		"win", "advance":
			Sfx.chime_win()
		"champion":
			Sfx.chime_big()
		"series":
			if bool(_v.get("won", false)):
				Sfx.chime_win()
			else:
				Sfx.match_loss()
		_:
			Sfx.match_loss()


func ready_to_continue() -> bool:
	return _t >= _ready_s


func _on_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed and ready_to_continue():
		skip()


## Go on to the post-match page (a tap, or the QA driver).
func skip() -> void:
	if _done:
		return
	_done = true
	continued.emit()


func clock() -> float:
	return _t


func page() -> Control:
	return _root


func confetti_count() -> int:
	return _confetti.count() if _confetti != null else 0


func has_rays() -> bool:
	return _rays != null


## A dashed horizontal rule (the playoff line).
class DashLine extends Control:
	var colour := Color.WHITE

	func _init(p_colour: Color) -> void:
		colour = p_colour
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, 0, minf(14.0, size.x - x), size.y), colour)
			x += 22.0


## A design box drawn in code: a solid ink drop shadow, the fill, the
## cream dot texture (dot_cream / dot_gold) when `dots`, a flat edge of
## `border` px. `pad` (left, top, right, bottom) sits inside the edge.
class Face extends PanelContainer:
	var edge := Color.WHITE
	var fill := Color.TRANSPARENT
	var dots := false
	var border := 2.0
	var shadow := 5.0
	var pad := Vector4.ZERO:
		set(value):
			pad = value
			_margins()

	func _init(p_edge: Color, p_fill: Color, p_dots: bool, p_border: float, p_shadow: float) -> void:
		edge = p_edge
		fill = p_fill
		dots = p_dots
		border = p_border
		shadow = p_shadow
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_margins()

	func _margins() -> void:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = pad.x + border
		sb.content_margin_top = pad.y + border
		sb.content_margin_right = pad.z + border
		sb.content_margin_bottom = pad.w + border
		add_theme_stylebox_override("panel", sb)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if shadow > 0.0:
			draw_rect(Rect2(Vector2.ONE * shadow, size), INK)
		draw_rect(r, fill)
		if dots:
			draw_texture_rect(ShadowStyle.dot_tex(), r, true, Color(edge, ShadowStyle.DOT_ALPHA))
		draw_rect(r.grow(-border * 0.5), edge, false, border)


## The orange strike through a beaten team (2 px ink shadow on the big rows).
class StrikeLine extends Control:
	var thick := 3.0
	var inked := true

	func _init(p_thick: float, p_inked: bool) -> void:
		thick = p_thick
		inked = p_inked
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0.0:
			return
		if inked:
			draw_rect(Rect2(Vector2(2, 2), Vector2(size.x, thick)), INK)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, thick)), ORANGE)


## The bracket's stepped lines (the design's 550-wide svg, centred): one
## 4 px path per semi up into the final; `set_progress` draws a path in.
class StepLines extends Control:
	const SVG_W := 550.0
	var _paths: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add_path(pts: Array, colour: Color) -> void:
		_paths.push_back({"pts": pts, "colour": colour, "p": 1.0})
		queue_redraw()

	func set_progress(i: int, p: float) -> void:
		if i < _paths.size() and not is_equal_approx(float(_paths[i]["p"]), p):
			_paths[i]["p"] = p
			queue_redraw()

	func progress(i: int) -> float:
		return float(_paths[i]["p"]) if i < _paths.size() else 0.0

	func _draw() -> void:
		var ox := (size.x - SVG_W) * 0.5
		for path in _paths:
			var pts: Array = path["pts"]
			var total := 0.0
			for k in range(1, pts.size()):
				total += (pts[k] - pts[k - 1]).length()
			var left := total * float(path["p"])
			for k in range(1, pts.size()):
				if left <= 0.0:
					break
				var a: Vector2 = pts[k - 1]
				var b: Vector2 = pts[k]
				var seg := (b - a).length()
				var end := a + (b - a) * minf(1.0, left / seg)
				left -= seg
				# A square-capped 4 px stroke: the box around the segment, grown by 2.
				var r := Rect2(Vector2(minf(a.x, end.x), minf(a.y, end.y)), (end - a).abs()).grow(2.0)
				r.position.x += ox
				draw_rect(r, path["colour"])
