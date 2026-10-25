class_name PeggyPage
extends HomePage
## The PEGGY page (docs/LOCKER.md), opened from the locker's PEGGY button:
## the carnival drop machine (PeggyMachine) filling the frame under a head
## of `<` · the level chip with its XP meter · the ticket chip. Tickets only
## ever buy plays: the PLAY (300) overlay over the machine feeds a ticket
## (the flight) and credits it — the credit is saved, so leaving and coming
## back keeps the ticket in and DROP flashing — then the joystick aims and
## DROP drops. Short of tickets with no credit, PLAY is greyed with NEED n
## MORE and the cap shows its red X; the joystick still moves the crane. A
## win pops the prize card over the page: NEW BALL (SET AS YOUR BALL?) or
## NEW NET (HANG IT ON YOUR COURTS?), EQUIP / KEEP, AGAIN · 300; an epic or
## legend plate dims harder and turns the rays. `<` returns to the locker.

const TIER_COLOR := PeggyMachine.TIER_COLOR
const PLAY_Y := 0.34
const PLAY_BACK_S := 2.4
const GREY_EDGE := Color("#7A706A")
const GREY_TEXT := Color("#A89E94")

var _machine: PeggyMachine
var _badge: LevelBadge
var _play: ShadowCard
var _play_need: Label
var _card: Control
var _rays: PrizeRays
var _play_back: Tween


func _build() -> void:
	# `<` · LVL chip · ....... · tickets
	var h := head("PEGGY")
	var title: Label = h.get_node("Title")
	title.visible = false
	var back := button("<", CREAM, 24, 52)
	back.name = "Back"
	back.custom_minimum_size.x = 52 + ShadowStyle.OFFSET
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	h.add_child(back)
	h.move_child(back, 0)
	_badge = LevelBadge.new()
	_badge.set_level(App.level(), Progression.frac_for(App.xp()))
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_badge)
	h.move_child(_badge, 1)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	h.move_child(spacer, 2)
	# The stage: the body's expanding row reserves the room; the machine
	# itself sits UNDER the body in the frame (so the head's `<` and chip
	# take their taps) and spills past the stage on every side. The body
	# must IGNORE the mouse: HomePage's PASS swallowed every tap over the
	# stage and handed it up to the frame, never down to the joystick/DROP.
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stage := Control.new()
	stage.name = "Stage"
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stage)
	_machine = PeggyMachine.new()
	_machine.dropped.connect(_on_dropped)
	_machine.credited.connect(_refresh_play)
	root.add_child(_machine)
	root.move_child(_machine, 0)
	stage.item_rect_changed.connect(_fit_machine.bind(stage))
	_fit_machine(stage)
	# PLAY (300), over the machine.
	_play = ShadowCard.new(RetroTheme.LIGHT["orange"])
	_play.name = "Play"
	_play.tint = 0.3
	var col := VBoxContainer.new()
	col.name = "Col"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	col.position = Vector2(28, 18)
	_play.add_child(col)
	var big := words("PLAY", 32, true)
	big.name = "Word"
	col.add_child(big)
	var cost := HBoxContainer.new()
	cost.name = "Cost"
	cost.alignment = BoxContainer.ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_theme_constant_override("separation", 8)
	col.add_child(cost)
	cost.add_child(words("(", 16, true))
	var icon := PixelIcon.new("icon_ticket", Vector2(22, 14))
	icon.name = "Icon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_child(icon)
	var price := words("%d)" % PeggyPrizes.DROP_COST, 16, true)
	price.name = "Price"
	cost.add_child(price)
	_play_need = words("", 16)
	_play_need.name = "Need"
	_play_need.visible = false
	col.add_child(_play_need)
	_play.pressed.connect(_on_play)
	root.add_child(_play)
	_layout_play()
	_refresh_machine()


## The machine over the stage's rect, 50 px past each side, 96 up, 20 down.
func _fit_machine(stage: Control) -> void:
	if _machine == null:
		return
	var top_left := body.position + stage.position
	_machine.position = top_left + Vector2(-50.0, -96.0)
	_machine.size = stage.size + Vector2(100.0, 116.0)


func _layout_play() -> void:
	var col: Control = _play.get_node("Col")
	var w := 230.0
	var hgt := 110.0 + (34.0 if _play_need.visible else 0.0)
	_play.custom_minimum_size = Vector2(w + ShadowStyle.OFFSET, hgt + ShadowStyle.OFFSET)
	_play.size = _play.custom_minimum_size
	col.size = Vector2(w - 56.0, hgt - 36.0)
	_play.position = Vector2((FRAME_SIZE.x - w) * 0.5, FRAME_SIZE.y * PLAY_Y)


func set_view_active(on: bool) -> void:
	if _machine != null:
		_machine.set_view_active(on)


func _refresh_machine() -> void:
	if _machine == null:
		return
	_machine.set_slots(App.peggy_slots())
	_machine.refresh_state()
	_badge.set_level(App.level(), Progression.frac_for(App.xp()))
	set_tickets()
	_refresh_play()


## PLAY shows while no ticket is in and the machine is idle; greyed with
## NEED n MORE while short. Hidden under the card and for a beat after a drop.
func _refresh_play() -> void:
	if _play == null:
		return
	var short := PeggyPrizes.DROP_COST - App.tickets()
	var busy := _machine.is_busy() or _machine.credit()
	_play.visible = not busy and _card == null
	_play.disabled = short > 0
	_play_need.visible = short > 0
	if short > 0:
		_play_need.text = "NEED %s MORE" % RetroTheme.thousands(short)
	var grey := short > 0
	_play.color = GREY_EDGE if grey else RetroTheme.LIGHT["orange"]
	_play.tint = 0.45 if grey else 0.3
	for l in _play.find_children("*", "Label", true, false):
		(l as Label).add_theme_color_override("font_color", GREY_TEXT if grey else CREAM)
	var icon: PixelIcon = _play.find_child("Icon", true, false)
	if icon != null:
		icon.modulate.a = 0.5 if grey else 1.0
	_layout_play()
	_play.queue_redraw()


## PLAY: spend the tickets, credit the machine, fly the ticket in.
func _on_play() -> void:
	if _card != null or _machine.is_busy() or _machine.credit():
		return
	if not App.peggy_insert_ticket():
		_refresh_play()
		return
	set_tickets()
	_machine.insert_ticket()
	_refresh_play()


func _on_dropped(prize: Dictionary) -> void:
	set_tickets()
	_badge.set_level(App.level(), Progression.frac_for(App.xp()))
	_show_card(prize)
	if _play_back != null and _play_back.is_valid():
		_play_back.kill()
	if is_inside_tree():
		_play_back = create_tween()
		_play_back.tween_interval(PLAY_BACK_S)
		_play_back.tween_callback(_refresh_play)


func machine() -> PeggyMachine:
	return _machine


func play_button() -> ShadowCard:
	return _play


func badge() -> LevelBadge:
	return _badge


# ---- the prize card -------------------------------------------------------------------


func _show_card(prize: Dictionary) -> void:
	_dismiss_card()
	var rarity := str(prize.get("rarity", ""))
	var kind := str(prize.get("kind", "ball"))
	var id := str(prize.get("id", ""))
	var big := rarity == "epic" or rarity == "legend"
	_card = Control.new()
	_card.name = "PrizeCard"
	UiLayout.full_rect(_card)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, 0.6 if not big else 0.82)
	UiLayout.full_rect(shade)
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
	if id == "":
		_card_text(col, "EMPTY SLOT", 18)
		_card_text(col, "+%d TICKETS BACK" % int(prize.get("refund", 0)), 30, true)
	else:
		var is_net := kind == "net"
		var top := _card_text(col, "EPIC PULL!" if big else ("NEW NET" if is_net else "NEW BALL"), 18)
		if big:
			top.add_theme_color_override("font_color", TIER_COLOR.get(rarity, CREAM))
			_card_text(col, "TOP PRIZE AT LVL %02d" % App.level(), 14)
		var name_ := id.to_upper()
		if is_net:
			var net := CosmeticLibrary.get_net(id)
			col.add_child(LockerPanel.net_rect(net, 128))
			if net != null:
				name_ = str(net.display_name).to_upper()
		else:
			var ball := CosmeticLibrary.get_ball(id)
			col.add_child(LockerPanel.skin_rect(ball, 128))
			if ball != null:
				name_ = str(ball.display_name).to_upper()
		_card_text(col, name_, 30, true)
		var total := int(prize.get("roster_size", CosmeticLibrary.nets().size() if is_net else CosmeticLibrary.balls().size()))
		_card_text(col, "%s · %d/%d %s" % [rarity.to_upper(), int(prize.get("owned_after", 0)), total, "NETS" if is_net else "BALLS"], 14)
		_card_text(col, "ADDED TO YOUR LOCKER" if big else ("HANG IT ON YOUR COURTS?" if is_net else "SET AS YOUR BALL?"), 16)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		col.add_child(row)
		var equip := _card_button("EQUIP", RetroTheme.LIGHT["gold"])
		equip.name = "Equip"
		equip.pressed.connect(func() -> void:
			if is_net:
				App.select_net_everywhere(id)
			else:
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
		_on_play()
	)
	col.add_child(again)
	_refresh_play()


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
	_refresh_machine()


func prize_card() -> Control:
	return _card
