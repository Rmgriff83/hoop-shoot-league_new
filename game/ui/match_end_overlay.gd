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
const CARD_COLORS := {"fire": MatchEndCopy.ORANGE, "ice": MatchEndCopy.BLUE, "vortex": Color("#A47FC6")}

var _t := 0.0
var _v: Dictionary = {}
var _root: Control
var _anims: Array = []
var _rays: PrizeRays
var _confetti: Confetti
var _flash: ColorRect
var _continue: Label
var _sound_done := false
var _done := false


func _init() -> void:
	layer = 40


# ---- build ----------------------------------------------------------------------


func build(v: Dictionary) -> Control:
	_v = v
	_t = 0.0
	_anims.clear()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "MatchEndPage"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		_anim(_rays, "fadein", 0.3, 0.6)
	_confetti = Confetti.new(int(v.get("confetti_n", 0)), Array(v.get("palette", [])), 7)
	_root.add_child(_confetti)
	_tag(str(v.get("tag", "")), v.get("tag_color", CREAM))
	_head(str(v.get("head", "")), int(v.get("head_size", 64)), v.get("head_color", CREAM), bool(v.get("win_anim", false)))
	_score(v)
	var sub_y := 850.0
	match str(v.get("block", "record")):
		"record":
			_record_block(Dictionary(v.get("record", {})))
		"bracket":
			_bracket_block(Dictionary(v.get("bracket", {})))
			sub_y = 856.0
		"trophy":
			_trophy_block(int(Dictionary(v.get("trophy", {})).get("titles", 1)))
			sub_y = 856.0
	if str(v.get("sub", "")) != "":
		var sub := _label(str(v["sub"]), 16, CREAM, false)
		sub.name = "Sub"
		_centre(sub, sub_y)
		_anim(sub, "rise", 2.1, 0.4)
	_rewards(str(v.get("coins", "+0")), str(v.get("drop", "")))
	_continue = _label("TAP TO CONTINUE", 16, CREAM, true)
	_continue.name = "Continue"
	_centre(_continue, 1150.0)
	_continue.visible = false
	_anim(_continue, "blink", READY_S, 1.0)
	if bool(v.get("flash", false)):
		_flash = ColorRect.new()
		_flash.name = "Flash"
		_flash.color = Color("#FFF3D0")
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.modulate.a = 0.0
		_root.add_child(_flash)
		_anim(_flash, "flash", 0.35, 0.45)
	step(0.0)
	return _root


func _backdrop(scrim: float) -> void:
	var base := ColorRect.new()
	base.name = "Base"
	base.color = Color("#171311")
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(base)
	for spec in [["Hall", "cage_hall.png", 330.0, 180.0, Vector2(720, 180)], ["Carpet", "cage_carpet.png", 510.0, H - 510.0, Vector2(192, 192)]]:
		var path := "res://assets/textures/%s" % spec[1]
		if not ResourceLoader.exists(path):
			continue
		var tr := TextureRect.new()
		tr.name = spec[0]
		tr.texture = load(path)
		tr.position = Vector2(0, spec[2])
		tr.size = Vector2(W, spec[3])
		tr.stretch_mode = TextureRect.STRETCH_TILE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(tr)
	var sc := ColorRect.new()
	sc.name = "Scrim"
	sc.color = Color(DARK, scrim)
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
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


func _head(text: String, size_: int, color: Color, win: bool) -> void:
	var box := Control.new()
	box.name = "HeadBox"
	box.position = Vector2(0, 300)
	box.size = Vector2(W, 80)
	box.pivot_offset = Vector2(W * 0.5, 40)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, size_, color, true)
	l.name = "Head"
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	RetroTheme.dithered(l, Vector2(8, 8))
	box.add_child(l)
	_root.add_child(box)
	if win:
		_anim(box, "slam", 0.35, 0.6)
	else:
		_anim(box, "sink", 0.35, 0.55)
		_anim(box, "shake", 0.95, 0.4)


func _score(v: Dictionary) -> void:
	var row := Control.new()
	row.name = "ScoreRow"
	row.position = Vector2(0, 420)
	row.size = Vector2(W, 110)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
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


func _trophy_block(titles: int) -> void:
	var block := Control.new()
	block.name = "Trophy"
	block.position = Vector2(0, 560)
	block.size = Vector2(W, 280)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.name = "Cup"
	holder.position = Vector2((W - 176.0) * 0.5, 0)
	holder.size = Vector2(176, 176)
	holder.pivot_offset = Vector2(88, 88)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cup := PixelIcon.new("icon_trophy", Vector2(176, 176), 8.0)
	cup.name = "CupIcon"
	cup.size = Vector2(176, 176)
	holder.add_child(cup)
	block.add_child(holder)
	_anim(holder, "pop", 1.3, 0.5)
	_anim(holder, "bob", 2.0, 1.6)
	var row := HBoxContainer.new()
	row.name = "Titles"
	row.position = Vector2(0, 202)
	row.size = Vector2(W, 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := _label("TITLES", 16, CREAM, false)
	row.add_child(tl)
	var cups := HBoxContainer.new()
	cups.add_theme_constant_override("separation", 8)
	cups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in mini(titles, 8):
		var small := Control.new()
		small.name = "Title%d" % i
		small.custom_minimum_size = Vector2(32, 32)
		small.pivot_offset = Vector2(16, 16)
		small.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := PixelIcon.new("icon_trophy", Vector2(32, 32), 3.0)
		ic.size = Vector2(32, 32)
		small.add_child(ic)
		cups.add_child(small)
		if i == titles - 1:
			_anim(small, "pop", 2.3, 0.35)
	row.add_child(cups)
	var count := _label("X%d" % titles, 20, GOLD, true)
	count.name = "TitleCount"
	count.pivot_offset = Vector2(20, 12)
	row.add_child(count)
	_anim(count, "pop", 2.3, 0.35)
	block.add_child(row)
	_root.add_child(block)
	_anim(row, "rise", 1.8, 0.4)


func _rewards(coins: String, drop: String) -> void:
	var row := Control.new()
	row.name = "Rewards"
	row.position = Vector2(0, 920)
	row.size = Vector2(W, 64)
	row.pivot_offset = Vector2(W * 0.5, 32)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var pill := PanelContainer.new()
	pill.name = "Coins"
	pill.custom_minimum_size = Vector2(0, 64)
	pill.add_theme_stylebox_override("panel", _box(GOLD, Color(GOLD, 0.25), true, Color(GOLD, 0.5)))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph := HBoxContainer.new()
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	ph.add_theme_constant_override("separation", 14)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(ph)
	var coin := PixelIcon.new("icon_coin", Vector2(28, 28))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(coin)
	var amount := _label(coins, 24, CREAM, true)
	amount.name = "CoinsText"
	ph.add_child(amount)
	h.add_child(pill)
	if drop != "":
		var card := CardDefs.get_card(drop)
		var kind := str(Dictionary(card.get("effect", {})).get("kind", ""))
		var col: Color = CARD_COLORS.get(kind, GOLD)
		var tile := Control.new()
		tile.name = "Drop"
		tile.custom_minimum_size = Vector2(300, 64)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := Panel.new()
		bg.name = "DropBg"
		bg.add_theme_stylebox_override("panel", _box(col, Color(col, 0.25)))
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
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


# ---- the clock ------------------------------------------------------------------


func _anim(node: CanvasItem, kind: String, delay: float, dur: float, extra := 0.0) -> void:
	var base := Vector2.ZERO
	if node is Control:
		base = (node as Control).position
	_anims.push_back({"node": node, "kind": kind, "delay": delay, "dur": dur, "base": base, "extra": extra})
	if kind in ["rise", "pop", "slam", "sink", "fadein", "slidein", "infrom"]:
		node.modulate.a = 0.0


static func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 3.0)


static func _ease_in(p: float) -> float:
	return p * p * p


## Advance the page by dt and lay every animated element where it belongs.
func step(dt: float) -> void:
	_t += dt
	if not _sound_done and _t >= 0.35:
		_sound_done = true
		_play_sound()
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
			"dim":
				node.modulate = Color.WHITE.lerp(Color(0.55, 0.55, 0.55), p)
			"blink":
				node.visible = _t >= delay and fmod(_t - delay, dur) < dur * 0.5
			"flash":
				node.modulate.a = 0.9 * (1.0 - p) if _t >= delay else 0.0


func _process(delta: float) -> void:
	step(delta)


func _play_sound() -> void:
	match str(_v.get("kind", "")):
		"win":
			Sfx.peggy_win()
		"advance", "champion":
			Sfx.peggy_jackpot()
		"series":
			if bool(_v.get("won", false)):
				Sfx.peggy_win()
			else:
				Sfx.match_loss()
		_:
			Sfx.match_loss()


func ready_to_continue() -> bool:
	return _t >= READY_S


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
