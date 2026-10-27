class_name MatchEndOverlay
extends CanvasLayer
## The league match-end page (design "League Match End", docs/HOME.md →
## Results): plays between the final buzzer and the post-match page. One
## clock (`_t`) drives a schedule of small animations — the tag rises, the
## headline slams in on a win (with a cream flash, rays and confetti) or
## sinks and shakes on a loss, the score rises, then the stakes block: the
## record flips and the place chip pops (regular season), the bracket
## advances or strikes you out (playoffs), or the trophy pops with your
## titles (the final). The rewards row pops last; from READY_S a blinking
## TAP TO CONTINUE accepts a tap anywhere → `continued`. Built from
## MatchEndCopy.state() so tests step it off-tree.

signal continued

const W := 720.0
const H := 1280.0
const READY_S := 3.0
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
		_rays.position = Vector2(W * 0.5 - 800.0, 380.0 - 800.0)
		_rays.size = Vector2(1600, 1600)
		_rays.speed_deg = 360.0 / maxf(float(v.get("spin_s", 30.0)), 1.0)
		_rays.alpha = 0.32
		_root.add_child(_rays)
		_anim(_rays, "fadein", float(v.get("rays_at", 0.3)), 0.6)
	_confetti = Confetti.new(int(v.get("confetti_n", 0)), Array(v.get("palette", [])), 7)
	_root.add_child(_confetti)
	_tag(str(v.get("tag", "")), v.get("tag_color", CREAM))
	_head(str(v.get("head", "")), int(v.get("head_size", 64)), v.get("head_color", CREAM), bool(v.get("win_anim", false)),
		float(v.get("head_y", 300.0)), float(v.get("head_at", 0.35)))
	if not bool(v.get("no_score", false)):
		_score(v)
	var sub_y := 850.0
	match str(v.get("block", "record")):
		"record":
			_record_block(Dictionary(v.get("record", {})))
		"bracket":
			_bracket_block(Dictionary(v.get("bracket", {})))
			sub_y = 856.0
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
		_centre(_continue, 1150.0)
		_continue.visible = false
		_anim(_continue, "blink", _ready_s, 1.0)
	if bool(v.get("flash", false)):
		_flash = ColorRect.new()
		_flash.name = "Flash"
		_flash.color = Color("#FFF3D0")
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


func _tag(text: String, color: Color) -> void:
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
	holder.position = Vector2(0, 220)
	holder.size = Vector2(W, 44)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill)
	_root.add_child(holder)
	_anim(holder, "rise", 0.1, 0.4)


func _head(text: String, size_: int, color: Color, win: bool, y := 300.0, at := 0.35) -> void:
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
	row.position = Vector2(0, 420)
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
	var panel := PanelContainer.new()
	panel.name = "Record"
	panel.position = Vector2(96, 600)
	panel.size = Vector2(528, 220)
	panel.add_theme_stylebox_override("panel", _box(CREAM, Color(CREAM, 0.1)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _bracket_row(name_: String, text: String, score: String, border: Color, fill: Color) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = name_
	row.custom_minimum_size = Vector2(0, 64)
	row.add_theme_stylebox_override("panel", _box(border, fill))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var l := _label(text, 20, CREAM, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if score != "":
		var sc := _label(score, 20, CREAM, true)
		sc.name = "Score"
		h.add_child(sc)
	return row


func _bracket_block(b: Dictionary) -> void:
	var block := Control.new()
	block.name = "Bracket"
	block.position = Vector2(48, 596)
	block.size = Vector2(618, 236)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var won := bool(_v.get("won", false))
	var lost := bool(b.get("lost", false))
	var decided := bool(b.get("decided", false))
	var top_c := GOLD if won else Color(CREAM, 0.4)
	var top_bg := Color(GOLD, 0.25) if won else Color(DARK, 0.5)
	var bot_c := Color(CREAM, 0.4) if won else CREAM
	var bot_bg := Color(DARK, 0.5) if won else Color(CREAM, 0.15)
	# Left: this round's pair, the game's score — the series score when it
	# is not decided yet.
	var left := VBoxContainer.new()
	left.name = "Round"
	left.position = Vector2.ZERO
	left.size = Vector2(270, 236)
	left.add_theme_constant_override("separation", 12)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rl := _label(str(b.get("round_label", "")), 16, CREAM, false)
	rl.name = "RoundLabel"
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(rl)
	var you_row := _bracket_row("YouRow", "YOU", str(b.get("you", 0)), top_c, top_bg)
	left.add_child(you_row)
	var opp_row := _bracket_row("OppRow", str(b.get("opp_first", "")), str(b.get("opp", 0)), bot_c, bot_bg)
	left.add_child(opp_row)
	block.add_child(left)
	if lost:
		_anim(you_row, "dim", 2.0, 0.4)
		var strike := ColorRect.new()
		strike.name = "Strike"
		strike.color = ORANGE
		strike.position = Vector2(10, 32 + 30)   # the label row, a gap, half the row
		strike.size = Vector2(0, 4)
		strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(strike)
		_anim(strike, "strike", 2.0, 0.35, 250.0)
	# The connector.
	if lost:
		block.move_child(block.get_node("Strike"), -1)
	var lines := BracketLines.new(GOLD if won else CREAM)
	lines.name = "Lines"
	lines.position = Vector2(270, 30)
	lines.size = Vector2(60, 160)
	block.add_child(lines)
	# Right: the next round.
	var right := VBoxContainer.new()
	right.name = "Next"
	right.position = Vector2(330, 0)
	right.size = Vector2(288, 236)
	right.add_theme_constant_override("separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := _label(str(b.get("next_label", "FINAL")), 16, CREAM, false)
	nl.name = "NextLabel"
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(nl)
	var next_name := str(b.get("next_name", ""))
	if decided:
		var fin := _bracket_row("NextRow", next_name, "", GOLD if won else CREAM, Color(GOLD, 0.25) if won else Color(CREAM, 0.12))
		right.add_child(fin)
		_anim(fin, "slidein", 2.0, 0.4)
	else:
		var series := _bracket_row("SeriesRow", "SERIES", str(b.get("series", "0 - 0")), CREAM, Color(CREAM, 0.12))
		right.add_child(series)
		_anim(series, "slidein", 2.0, 0.4)
	var opp_box := PanelContainer.new()
	opp_box.name = "NextOpp"
	opp_box.custom_minimum_size = Vector2(0, 64)
	var dashed := _box(Color(CREAM, 0.4), Color(0, 0, 0, 0), false)
	opp_box.add_theme_stylebox_override("panel", dashed)
	opp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ol := _label(str(b.get("next_opp", "")), 16, CREAM, false)
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	opp_box.add_child(ol)
	right.add_child(opp_box)
	block.add_child(right)
	_root.add_child(block)
	_anim(block, "rise", 1.3, 0.45)


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
	row.position = Vector2(0, 910)
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
		tile.custom_minimum_size = Vector2(300, 64)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := Panel.new()
		bg.name = "DropBg"
		bg.add_theme_stylebox_override("panel", _box(col, Color(col, 0.25)))
		UiLayout.full_rect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(bg)
		var tv := VBoxContainer.new()
		tv.position = Vector2(96, 0)
		tv.size = Vector2(190, 64)
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
			art.position = Vector2(14, -30)
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


## The bracket's connector: a stub from each semifinal row, a riser, a stub
## into the final; the winner's path in the accent colour.
class BracketLines extends Control:
	var accent := Color.WHITE

	func _init(p_accent: Color) -> void:
		accent = p_accent
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var faint := Color(MatchEndCopy.CREAM, 0.35)
		draw_rect(Rect2(0, 38, 30, 4), accent)
		draw_rect(Rect2(0, 114, 30, 4), faint)
		draw_rect(Rect2(26, 38, 4, 80), faint)
		draw_rect(Rect2(26, 76, 34, 4), accent)
