class_name LockerPanel
extends CanvasLayer
## The locker sheet (the top-left locker icon), docs/LOCKER.md. Two tabs:
## PEGGY — the drop machine (PeggyMachine) that wins balls for tickets — and
## BALLS — the collection grid (owned balls equip on tap, the rest show their
## rarity). The hoop counter under it (buy for tickets, swap) is closed for
## now (App.HOOPS_IN_LOCKER). A win pops the prize card over the sheet: SET AS YOUR BALL?
## EQUIP / KEEP, AGAIN; an epic or legend pull gets the rays. Opening BALLS
## clears App.unseen_balls(), which the title's locker icon badges.

signal closed

const DIM := Color(0.02, 0.02, 0.05, 0.72)
const TABS := ["PEGGY", "BALLS"]
const TIER_COLOR := PeggyMachine.TIER_COLOR
const SKIN_REGION := Rect2(64, 64, 128, 128)

var _sheet: PanelContainer
var _vbox: VBoxContainer
var _balance: CoinsPill
var _tabs: HBoxContainer
var _content: Control
var _tab := "PEGGY"
var _machine: PeggyMachine
var _level_line: Label
var _meter: Meter
var _stick: PeggyStick
var _hint: Label
var _list: VBoxContainer
var _card: Control
var _rays: PrizeRays


func _init() -> void:
	layer = 30


func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed and _card == null:
			close()
	)
	add_child(dim)

	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_sheet.position = Vector2(-330, -620)
	_sheet.size = Vector2(660, 1240)
	_sheet.add_theme_stylebox_override("panel", RetroTheme.face(RetroTheme.c("bg"), RetroTheme.RADIUS, 20.0))
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sheet)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 10)
	_sheet.add_child(_vbox)

	var head := HBoxContainer.new()
	head.name = "Head"
	_vbox.add_child(head)
	var title := RetroTheme.display("LOCKER", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	_balance = CoinsPill.new()
	_balance.name = "Balance"
	var coin: PixelIcon = _balance.find_child("Coin", true, false)
	if coin != null:
		coin.icon_name = "icon_ticket"
		coin.custom_minimum_size = Vector2(22, 14)
	head.add_child(_balance)

	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 10)
	_vbox.add_child(_tabs)
	_content = Control.new()
	_content.name = "Content"
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_vbox.add_child(_content)

	var close_btn := UiFont.flat_button("CLOSE", 24, RetroTheme.c("text"))
	close_btn.name = "Close"
	close_btn.custom_minimum_size = Vector2(0, 60)
	close_btn.pressed.connect(close)
	_vbox.add_child(close_btn)
	_fill()


## A card button whose words stay readable on BOTH palettes: card_button's
## ink is for the gold/orange faces; on a panel/bg face in dark mode that ink
## is dark on dark, so those take the theme's text colour instead.
static func _face(b: Button, fill: Color, margin: float) -> Button:
	RetroTheme.card_button(b, fill, RetroTheme.RADIUS, margin)
	if fill == RetroTheme.c("panel") or fill == RetroTheme.c("bg"):
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, RetroTheme.c("text"))
		b.add_theme_color_override("font_disabled_color", RetroTheme.c("muted"))
	return b


## Rebuild the tabs and the current tab's content. Old nodes are removed at
## once and freed later: _fill runs from the tabs' own pressed signals, and
## freeing the emitter mid-signal left the sheet half built.
func _fill() -> void:
	_balance.set_coins(App.tickets())
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for tab in TABS:
		var label: String = tab
		if tab == "BALLS":
			label = "BALLS %d/%d" % [App.owned_count("ball"), CosmeticLibrary.balls().size()]
		var b := Button.new()
		b.name = "Tab_" + tab
		b.text = label
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_face(b, RetroTheme.c("gold") if tab == _tab else RetroTheme.c("panel"), 10.0)
		b.add_theme_font_size_override("font_size", UiFont.snap(16))
		var t: String = tab
		b.pressed.connect(func() -> void: show_tab.call_deferred(t))
		_tabs.add_child(b)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_machine = null
	_stick = null
	_meter = null
	_list = null
	if _tab == "PEGGY":
		_build_peggy()
	else:
		_build_balls()


func show_tab(tab: String) -> void:
	if not TABS.has(tab):
		return
	_tab = tab
	if tab == "BALLS":
		App.mark_balls_seen()
	_fill()


func tab() -> String:
	return _tab


# ---- PEGGY ------------------------------------------------------------------------


func _build_peggy() -> void:
	var col := VBoxContainer.new()
	col.name = "PeggyTab"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	_content.add_child(col)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(center)
	_machine = PeggyMachine.new()
	_machine.dropped.connect(_on_dropped)
	_machine.feeding.connect(_on_feeding)
	center.add_child(_machine)
	_level_line = RetroTheme.caps("", 16, RetroTheme.c("muted"))
	_level_line.name = "LevelLine"
	_level_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_level_line)
	_meter = Meter.new()
	col.add_child(_meter)
	_hint = RetroTheme.caps("", 16, RetroTheme.c("text"))
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)
	var deck := CenterContainer.new()
	deck.name = "Deck"
	col.add_child(deck)
	_stick = PeggyStick.new()
	deck.add_child(_stick)
	_refresh_machine()


func _refresh_machine() -> void:
	if _machine == null:
		return
	_machine.set_slots(App.peggy_slots())
	var level := App.level()
	var top := PeggyPrizes.top_rarity(level)
	var line := "LVL %02d · PRIZES UP TO %s" % [level, top.to_upper()]
	if level < PeggyPrizes.EPIC_LEVEL:
		line += " · EPIC AT LVL %d" % PeggyPrizes.EPIC_LEVEL
	elif level < PeggyPrizes.LEGEND_LEVEL:
		line += " · LEGEND AT LVL %d" % PeggyPrizes.LEGEND_LEVEL
	_level_line.text = line
	_meter.set_progress(App.xp(), level)
	var short := PeggyPrizes.DROP_COST - App.tickets()
	_machine.can_drop = short <= 0
	if short > 0:
		_hint.text = "NEED %s MORE" % RetroTheme.thousands(short)
		_hint.add_theme_color_override("font_color", RetroTheme.c("muted"))
	else:
		_hint.text = "HOLD TO DROP · %d" % PeggyPrizes.DROP_COST
		_hint.add_theme_color_override("font_color", RetroTheme.c("text"))
	_balance.set_coins(App.tickets())


const STICK_RATE := 3.0   # board units a second at full deflection


func _process(delta: float) -> void:
	if _stick != null and _machine != null and _stick.deflection() != 0.0 and not _machine.playing():
		_machine.nudge(_stick.deflection() * STICK_RATE * delta)


func stick() -> PeggyStick:
	return _stick


func meter() -> Meter:
	return _meter


## The level meter under the machine: how far to the next rarity's plates.
class Meter extends Control:
	const H := 18.0
	var frac := 0.0
	var label := ""
	var fill := Color.WHITE

	func _init() -> void:
		name = "RarityMeter"
		custom_minimum_size = Vector2(0, H + 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## XP and level → the bar from the last rarity gate to the next.
	func set_progress(xp: int, level: int) -> void:
		var per := Progression.xp_per_level()
		var next := 0
		var prev := 1
		for gate in [PeggyPrizes.EPIC_LEVEL, PeggyPrizes.LEGEND_LEVEL]:
			if level >= gate:
				prev = gate
			elif next == 0:
				next = gate
		if next == 0:
			frac = 1.0
			label = "EVERY RARITY OPEN"
			fill = PeggyMachine.TIER_COLOR["legend"]
		else:
			var start := (prev - 1) * per
			var end := (next - 1) * per
			frac = clampf(float(xp - start) / float(maxi(end - start, 1)), 0.0, 1.0)
			var rarity := "epic" if next == PeggyPrizes.EPIC_LEVEL else "legend"
			label = "%d/%d XP TO %s PLATES" % [xp - start, end - start, rarity.to_upper()]
			fill = PeggyMachine.TIER_COLOR[rarity]
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var y := 0.0
		draw_rect(Rect2(Vector2(3, y + 3), Vector2(w - 3, H)), RetroTheme.c("shadow"))
		draw_rect(Rect2(Vector2(0, y), Vector2(w - 3, H)), RetroTheme.c("ink"))
		draw_rect(Rect2(Vector2(3, y + 3), Vector2(maxf((w - 9) * frac, 0.0), H - 6)), fill)
		var font := UiFont.body_bold()
		var fs := UiFont.snap(12)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((w - tw) * 0.5, y + H + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RetroTheme.c("muted"))


func _on_feeding(frac: float) -> void:
	if _hint == null:
		return
	if frac > 0.0:
		_hint.text = "FEEDING " + "▮".repeat(int(ceil(frac * 6))) + "▯".repeat(6 - int(ceil(frac * 6)))
	else:
		_refresh_machine()


func _on_dropped(prize: Dictionary) -> void:
	_balance.set_coins(App.tickets())
	_show_card(prize)


# ---- the prize card -------------------------------------------------------------------


func _show_card(prize: Dictionary) -> void:
	_dismiss_card()
	var rarity := str(prize.get("rarity", ""))
	var id := str(prize.get("ball_id", ""))
	var big := rarity == "epic" or rarity == "legend"
	_card = Control.new()
	_card.name = "PrizeCard"
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, 0.6 if not big else 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_child(shade)
	if big:
		_rays = PrizeRays.new(TIER_COLOR.get(rarity, Color.WHITE))
		_card.add_child(_rays)
	var panel := PanelContainer.new()
	panel.name = "Card"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-270, -250)
	panel.size = Vector2(540, 500)
	panel.add_theme_stylebox_override("panel", RetroTheme.face(RetroTheme.c("panel"), RetroTheme.RADIUS, 24.0))
	_card.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var ball := CosmeticLibrary.get_ball(id)
	if id == "":
		_card_text(col, "EMPTY SLOT", 18, RetroTheme.c("muted"))
		_card_text(col, "+%d TICKETS BACK" % int(prize.get("refund", 0)), 30, RetroTheme.c("text"), true)
	else:
		_card_text(col, "EPIC PULL!" if big else "NEW BALL", 18, TIER_COLOR.get(rarity, RetroTheme.c("muted")))
		if big:
			_card_text(col, "TOP PRIZE AT LVL %02d" % App.level(), 14, RetroTheme.c("muted"))
		var skin := _skin_rect(ball, 128)
		skin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(skin)
		_card_text(col, str(ball.display_name).to_upper() if ball != null else id.to_upper(), 30, RetroTheme.c("text"), true)
		_card_text(col, "%s · %d/%d BALLS" % [rarity.to_upper(), int(prize.get("owned_after", 0)), CosmeticLibrary.balls().size()],
			14, RetroTheme.c("muted"))
		_card_text(col, "ADDED TO YOUR LOCKER" if big else "SET AS YOUR BALL?", 16, RetroTheme.c("text"))
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		col.add_child(row)
		var equip := _card_button("EQUIP", RetroTheme.c("gold"))
		equip.name = "Equip"
		equip.pressed.connect(func() -> void:
			App.select("ball", id)
			_dismiss_card()
			_fill()
		)
		row.add_child(equip)
		var keep := _card_button("KEEP", RetroTheme.c("panel"))
		keep.name = "Keep"
		keep.pressed.connect(func() -> void:
			_dismiss_card()
			_fill()
		)
		row.add_child(keep)
	var again := _card_button("AGAIN · %d" % PeggyPrizes.DROP_COST, RetroTheme.c("orange"))
	again.name = "Again"
	again.custom_minimum_size = Vector2(300, 60)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if App.tickets() < PeggyPrizes.DROP_COST:
		again.text = "NEED %s MORE" % RetroTheme.thousands(PeggyPrizes.DROP_COST - App.tickets())
		again.disabled = true
	again.pressed.connect(func() -> void:
		_dismiss_card()
		_refresh_machine()
	)
	col.add_child(again)


func _card_text(col: Control, text: String, size_: int, color: Color, display := false) -> Label:
	var l := RetroTheme.display(text, size_, color) if display else RetroTheme.caps(text, size_, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return l


func _card_button(text: String, fill: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 56)
	_face(b, fill, 10.0)
	b.add_theme_font_size_override("font_size", UiFont.snap(16))
	return b


func _dismiss_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
		_rays = null


func prize_card() -> Control:
	return _card


func machine() -> PeggyMachine:
	return _machine


# ---- BALLS --------------------------------------------------------------------------


## The ball's shaded thumbnail (tools/blender/build_ball_lineup.py --thumbs),
## falling back to a crop of the wrap when a thumb is missing.
func _skin_rect(ball: BallSet, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if ball != null:
		var thumb := "res://assets/textures/balls/thumbs/%s.png" % ball.id
		if ResourceLoader.exists(thumb):
			tr.texture = load(thumb)
		elif ball.skin_path != "":
			var at := AtlasTexture.new()
			at.atlas = load(ball.skin_path)
			at.region = SKIN_REGION
			tr.texture = at
	return tr


func _build_balls() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "BallsTab"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "Items"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var head := RetroTheme.caps("BALLS · WON ON PEGGY", 16, RetroTheme.c("muted"))
	head.name = "Head_ball"
	_list.add_child(head)
	var grid := GridContainer.new()
	grid.name = "BallGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_list.add_child(grid)
	var current := _current_id("ball")
	for cs in CosmeticLibrary.balls():
		var ball := cs as BallSet
		var owned: bool = App.owns("ball", ball.id) or ball.id == current
		var in_use: bool = owned and ball.id == current
		var tile := Button.new()
		tile.name = "Ball_" + ball.id
		tile.custom_minimum_size = Vector2(148, 176)
		tile.text = ""
		var fill := RetroTheme.c("gold") if in_use else (RetroTheme.c("panel") if owned else RetroTheme.c("bg"))
		_face(tile, fill, 6.0)
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_right = -ShadowStyle.OFFSET
		vb.offset_bottom = -ShadowStyle.OFFSET
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 4)
		tile.add_child(vb)
		var skin := _skin_rect(ball, 96)
		skin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not owned:
			skin.modulate = Color(0.25, 0.25, 0.28, 1.0)
		vb.add_child(skin)
		var nm := RetroTheme.caps(str(ball.display_name).to_upper(), 11,
			RetroTheme.c("card_text") if in_use else (RetroTheme.c("text") if owned else RetroTheme.c("muted")))
		nm.name = "Name"
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)
		var tag_text := "IN USE" if in_use else ("EQUIP" if owned else ball.rarity.to_upper())
		var tag := RetroTheme.caps(tag_text, 11,
			TIER_COLOR.get(ball.rarity, RetroTheme.c("muted")) if not owned else (RetroTheme.c("card_text") if in_use else RetroTheme.c("muted")))
		tag.name = "Tag"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tag)
		tile.disabled = not owned
		var id := ball.id
		tile.pressed.connect(func() -> void:
			if App.select("ball", id):
				_fill()
		)
		grid.add_child(tile)
	if not App.HOOPS_IN_LOCKER:
		return
	var hhead := RetroTheme.caps("HOOPS", 16, RetroTheme.c("muted"))
	hhead.name = "Head_hoop"
	_list.add_child(hhead)
	var hcur := _current_id("hoop")
	for cs in CosmeticLibrary.hoops():
		var owned: bool = App.owns("hoop", cs.id) or cs.id == hcur
		var in_use: bool = owned and cs.id == hcur
		var row := Button.new()
		row.name = "Hoop_" + cs.id
		var label := str(cs.display_name).to_upper()
		if in_use:
			label += "   -  IN USE"
		elif not owned:
			label += "   -  %s TICKETS" % RetroTheme.thousands(int(cs.price_coins))
		row.text = label
		row.custom_minimum_size = Vector2(0, 60)
		var fill := RetroTheme.c("gold") if in_use else (RetroTheme.c("panel") if owned else RetroTheme.c("bg"))
		_face(row, fill, 12.0)
		row.add_theme_font_size_override("font_size", UiFont.snap(16))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not owned and App.tickets() < int(cs.price_coins):
			row.disabled = true
		var id := str(cs.id)
		var was_owned := owned
		row.pressed.connect(func() -> void:
			if was_owned:
				if App.select("hoop", id):
					_fill()
			elif App.try_buy("hoop", id):
				App.select("hoop", id)
				_fill()
		)
		_list.add_child(row)


## The id in use: the live set, else the starter.
func _current_id(kind: String) -> String:
	var live: CosmeticSet = App.ball_set if kind == "ball" else App.hoop_set
	if live != null:
		return live.id
	var starter: CosmeticSet = CosmeticLibrary.starter_ball() if kind == "ball" else CosmeticLibrary.starter_hoop()
	return starter.id if starter != null else ""


## Button names on the BALLS tab, in order ("Ball_<id>" / "Hoop_<id>"), for tests.
func rows() -> Array:
	var out := []
	if _list == null:
		return out
	for c in BeachFx._descendants(_list):
		if c is Button:
			out.push_back(c.name)
	return out


func in_use_row(kind := "ball") -> String:
	var prefix := "Ball_" if kind == "ball" else "Hoop_"
	if _list == null:
		return ""
	for c in BeachFx._descendants(_list):
		if c is Button and str(c.name).begins_with(prefix):
			var words: String = c.text
			for l in c.find_children("*", "Label", true, false):
				words += " " + str(l.text)
			if words.contains("IN USE"):
				return c.name
	return ""


func close() -> void:
	closed.emit()
	queue_free()
