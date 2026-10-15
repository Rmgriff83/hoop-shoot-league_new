class_name PeggyPage
extends HomePage
## The PEGGY page (docs/LOCKER.md), opened from the locker's PEGGY button:
## the drop machine (PeggyMachine) in a cream dotted frame, the ticket chip,
## CLOSE. Drag the top band of the machine to aim and hold the red button to
## feed a ticket and drop. The level line, the XP meter and the drop hint
## are gone from the page — they move into the cabinet model — so the only
## words under the frame are NEED n MORE while you are short of a drop (and
## the feed bar while a ticket goes in). A win pops the prize card over the
## page: SET AS YOUR BALL? EQUIP / KEEP, AGAIN; an epic or legend pull dims
## harder and turns the rays.

const TIER_COLOR := PeggyMachine.TIER_COLOR
const FRAME_PAD := 7.0

var _machine: PeggyMachine
var _hint: Label
var _card: Control
var _rays: PrizeRays


func _build() -> void:
	head("PEGGY")
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(centre)
	var col := VBoxContainer.new()
	col.name = "Machine"
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	centre.add_child(col)
	var frame := ShadowPanel.new(CREAM, FRAME_PAD)
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(frame)
	_machine = PeggyMachine.new()
	_machine.dropped.connect(_on_dropped)
	_machine.feeding.connect(_on_feeding)
	frame.add_child(_machine)
	_hint = words("", 16)
	_hint.name = "Hint"
	_hint.visible = false
	col.add_child(_hint)
	close_button()
	_refresh_machine()


func set_view_active(on: bool) -> void:
	if _machine != null:
		_machine.set_view_active(on)


func _refresh_machine() -> void:
	if _machine == null:
		return
	_machine.set_slots(App.peggy_slots())
	var short := PeggyPrizes.DROP_COST - App.tickets()
	_machine.can_drop = short <= 0
	_hint.visible = short > 0
	if short > 0:
		_hint.text = "NEED %s MORE" % RetroTheme.thousands(short)
	set_tickets()


func _on_feeding(frac: float) -> void:
	if _hint == null:
		return
	if frac > 0.0:
		_hint.text = "FEEDING " + "▮".repeat(int(ceil(frac * 6))) + "▯".repeat(6 - int(ceil(frac * 6)))
		_hint.visible = true
	else:
		_refresh_machine()


func _on_dropped(prize: Dictionary) -> void:
	_refresh_machine()   # the feed bar is done; the hint goes back to its own words
	_show_card(prize)


func machine() -> PeggyMachine:
	return _machine


func hint() -> Label:
	return _hint


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
	var panel := ShadowPanel.new(CREAM, 24.0)
	panel.name = "Card"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.position = Vector2(90, 390)
	panel.size = Vector2(540, 500)
	_card.add_child(panel)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var ball := CosmeticLibrary.get_ball(id)
	if id == "":
		_card_text(col, "EMPTY SLOT", 18)
		_card_text(col, "+%d TICKETS BACK" % int(prize.get("refund", 0)), 30, true)
	else:
		var top := _card_text(col, "EPIC PULL!" if big else "NEW BALL", 18)
		if big:
			top.add_theme_color_override("font_color", TIER_COLOR.get(rarity, CREAM))
			_card_text(col, "TOP PRIZE AT LVL %02d" % App.level(), 14)
		col.add_child(LockerPanel.skin_rect(ball, 128))
		_card_text(col, str(ball.display_name).to_upper() if ball != null else id.to_upper(), 30, true)
		_card_text(col, "%s · %d/%d BALLS" % [rarity.to_upper(), int(prize.get("owned_after", 0)), CosmeticLibrary.balls().size()], 14)
		_card_text(col, "ADDED TO YOUR LOCKER" if big else "SET AS YOUR BALL?", 16)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		col.add_child(row)
		var equip := _card_button("EQUIP", RetroTheme.LIGHT["gold"])
		equip.name = "Equip"
		equip.pressed.connect(func() -> void:
			App.select("ball", id)
			_dismiss_card()
		)
		row.add_child(equip)
		var keep := _card_button("KEEP", CREAM)
		keep.name = "Keep"
		keep.pressed.connect(_dismiss_card)
		row.add_child(keep)
	var again := _card_button("AGAIN · %d" % PeggyPrizes.DROP_COST, RetroTheme.LIGHT["orange"])
	again.name = "Again"
	again.custom_minimum_size = Vector2(300, 60 + ShadowStyle.OFFSET)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if App.tickets() < PeggyPrizes.DROP_COST:
		again.text = "NEED %s MORE" % RetroTheme.thousands(PeggyPrizes.DROP_COST - App.tickets())
		again.disabled = true
	again.pressed.connect(func() -> void:
		_dismiss_card()
		_refresh_machine()
	)
	col.add_child(again)


func _card_text(col: Control, text: String, size_: int, display := false) -> Label:
	var l := words(text, size_, display)
	col.add_child(l)
	return l


func _card_button(text: String, fill: Color) -> ShadowCard:
	var b := button(text, fill, 16, 56)
	b.custom_minimum_size.x = 140
	return b


func _dismiss_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
		_rays = null


func prize_card() -> Control:
	return _card
