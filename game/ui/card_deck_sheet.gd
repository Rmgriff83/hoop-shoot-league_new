class_name CardDeckSheet
extends CanvasLayer
## A bucket's cards as a modal sheet (docs/BACKEND.md → Cards online): the
## three loadout slots (tap one to unequip), LOADOUT — the spares, tap one to
## equip — and SHOP — every card with its rarity, the level it plays from
## (gold once you have it), the blurb, OWNED n, and BUY at its price. Built
## for the `online` bucket (the lobby), where buying asks the server
## (App.buy_online_card) and the inventory is the ledger's cache; a league
## bucket works the same with the save as the ledger. The league hub keeps its
## own CARDS tab (game/ui/league_context.gd); this is the lobby's door.

signal closed
signal changed

const DIM := Color(0.02, 0.02, 0.05, 0.72)
const SHEET := Vector2(660, 1100)
const INK := RetroTheme.SCENE_OUTLINE
const CREAM := RetroTheme.SCENE_TEXT
const BLUE := Color("#7FAEC6")

var bucket := "online"
var title_text := "ONLINE CARDS"
var _sub := "LOADOUT"
var _body: VBoxContainer
var _status := ""


func _init() -> void:
	layer = 35


func build(p_bucket: String, p_title: String, sub := "LOADOUT") -> void:
	bucket = p_bucket
	title_text = p_title
	_sub = sub
	for c in get_children():
		remove_child(c)   # out of the tree now, so a rebuild never finds the old nodes
		c.queue_free()
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			close()
	)
	add_child(dim)
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.position = -SHEET / 2.0
	sheet.size = SHEET
	sheet.add_theme_stylebox_override("panel", RetroTheme.face(RetroTheme.c("bg"), RetroTheme.RADIUS, 24.0))
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	sheet.add_child(vbox)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vbox.add_child(head)
	var title := RetroTheme.display(title_text, 24)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var coins := RetroTheme.display("%d COINS" % App.league_coins(bucket), 16, RetroTheme.c("gold"))
	coins.name = "Coins"
	coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(coins)
	# The slots: tap one to send its card back to the spares.
	var slots := HBoxContainer.new()
	slots.name = "Slots"
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 14)
	vbox.add_child(slots)
	var loadout: Array = App.loadout_slots(bucket)
	for i in CardDefs.SLOTS:
		var id: Variant = loadout[i] if i < loadout.size() else null
		var card := CardDefs.get_card(str(id)) if id != null else {}
		var b := Button.new()
		b.name = "Slot%d" % i
		b.custom_minimum_size = Vector2(96 + 6, 128 + 6)
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.add_child(ModeCards.art(card, Vector2(96, 128), 6.0) if not card.is_empty() else ModeCards.empty_slot(Vector2(96, 128)))
		b.disabled = card.is_empty()
		var slot := i
		b.pressed.connect(func() -> void:
			App.unequip_card(slot, bucket)
			changed.emit()
			build(bucket, title_text, _sub)
		)
		slots.add_child(b)
	var hint := _caps("TAP A SLOT TO TAKE ITS CARD OUT" if not App.loadout_hand(bucket).is_empty() else "EMPTY SLOTS · EQUIP SPARES BELOW")
	hint.name = "SlotHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	# LOADOUT / SHOP.
	var subs := HBoxContainer.new()
	subs.name = "Subs"
	subs.add_theme_constant_override("separation", 12)
	vbox.add_child(subs)
	for name_v in ["LOADOUT", "SHOP"]:
		var name_: String = name_v
		var tb := ShadowCard.new(RetroTheme.c("ink"))
		tb.name = "Sub_" + name_
		tb.custom_minimum_size = Vector2(170 + ShadowStyle.OFFSET, 46 + ShadowStyle.OFFSET)
		var l := RetroTheme.display(name_, 16, RetroTheme.c("bg") if name_ == _sub else RetroTheme.c("text"))
		l.position = Vector2.ZERO
		l.size = Vector2(170, 46)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tb.add_child(l)
		if name_ == _sub:
			tb.fill = RetroTheme.c("ink")
			tb.dot = RetroTheme.c("ink")
			tb.shadow = Color(RetroTheme.c("orange"), ShadowStyle.SHADOW_ALPHA)
		var sname: String = name_
		tb.pressed.connect(func() -> void: build(bucket, title_text, sname))
		subs.add_child(tb)
	var status := _caps(_status, RetroTheme.c("orange"))
	status.name = "Status"
	status.visible = _status != ""
	vbox.add_child(status)
	_status = ""
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 18)
	scroll.add_child(_body)
	if _sub == "LOADOUT":
		_fill_loadout()
	else:
		_fill_shop()
	var close_btn := UiFont.flat_button("CLOSE", 24, RetroTheme.c("text"))
	close_btn.name = "Close"
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


## The spares: tap one to put it in the first empty slot.
func _fill_loadout() -> void:
	var cd := App.cards_bucket(bucket)
	var inv: Dictionary = cd.get("inventory", {})
	var free_slots := 0
	for slot in CardDefs.SLOTS:
		if cd["loadout"][slot] == null:
			free_slots += 1
	if inv.is_empty():
		_body.add_child(_caps("NO SPARE CARDS · VISIT THE SHOP" if bucket == Net.ONLINE_BUCKET else "NO SPARE CARDS · WIN MATCHES OR VISIT THE SHOP"))
	else:
		_body.add_child(_caps("SPARES · TAP ONE TO EQUIP IT" if free_slots > 0 else "SPARES · THE LOADOUT IS FULL"))
	var spares := HBoxContainer.new()
	spares.name = "Spares"
	spares.add_theme_constant_override("separation", 24)
	_body.add_child(spares)
	for id in inv:
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var holder := ModeCards.art(card, Vector2(120, 160), 6.0, true)
		holder.name = "Spare_" + str(id)
		var cid := str(id)
		(holder.get_meta("button") as TextureButton).pressed.connect(func() -> void:
			for slot in CardDefs.SLOTS:
				if App.cards_bucket(bucket)["loadout"][slot] == null:
					App.equip_card(slot, cid, bucket)
					break
			changed.emit()
			build(bucket, title_text, _sub)
		)
		var badge := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = INK
		sb.set_content_margin_all(6)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		badge.add_theme_stylebox_override("panel", sb)
		badge.position = Vector2(120 - 22, -10)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(UiFont.label("x%d" % int(inv[id]), 16, CREAM))
		holder.add_child(badge)
		spares.add_child(holder)
	_body.add_child(_caps("ONE-TIME USE · A PLAYED CARD IS GONE FOR GOOD"))


## Every card: rarity, the level it plays from, the blurb, OWNED, BUY.
func _fill_shop() -> void:
	var where := "ONLINE ONLY" if bucket == Net.ONLINE_BUCKET else "IN THIS LEAGUE ONLY"
	_body.add_child(_caps("%d COINS · CARDS BOUGHT HERE PLAY %s" % [App.league_coins(bucket), where]))
	var cd := App.cards_bucket(bucket)
	var level := App.level()
	for card in CardDefs.all():
		var cid := str(card["id"])
		var panel := ShadowPanel.new(RetroTheme.c("ink"), 16.0, 0.08)
		panel.name = "Shop_" + cid
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		panel.add_child(row)
		row.add_child(ModeCards.art(card, Vector2(96, 128)))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.add_child(RetroTheme.display(str(card.get("name", "")).to_upper(), 14))
		var rarity := str(card.get("rarity", ""))
		head.add_child(_chip(rarity.to_upper(), BLUE if rarity == "rare" else (RetroTheme.c("gold") if rarity == "epic" else RetroTheme.c("panel")), INK))
		var usable := Progression.can_use(level, card)
		var lvl := _chip("LVL %d" % Progression.card_level(card), Color(INK, 0.6), RetroTheme.c("gold") if usable else CREAM, RetroTheme.c("gold") if usable else CREAM)
		lvl.name = "Level_" + cid
		head.add_child(lvl)
		col.add_child(head)
		var blurb := _caps(str(card.get("blurb", "")), RetroTheme.c("muted"))
		col.add_child(blurb)
		var foot := HBoxContainer.new()
		foot.add_theme_constant_override("separation", 12)
		col.add_child(foot)
		var owned_n := CardDefs.owned(cd, cid)
		var spare_n := CardDefs.count(cd, cid)
		var owned_txt := "OWNED %d" % owned_n
		if owned_n > spare_n:
			owned_txt += " · %d EQUIPPED" % (owned_n - spare_n)
		var ol := _caps(owned_txt)
		ol.name = "Owned_" + cid
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		foot.add_child(ol)
		var buy := ShadowCard.new(RetroTheme.c("gold"))
		buy.name = "Buy_" + cid
		buy.custom_minimum_size = Vector2(130 + ShadowStyle.OFFSET, 46 + ShadowStyle.OFFSET)
		buy.disabled = App.league_coins(bucket) < int(card.get("price", 0)) or not usable
		var price := RetroTheme.display("%d" % int(card.get("price", 0)), 16, RetroTheme.c("text"))
		price.position = Vector2.ZERO
		price.size = Vector2(130, 46)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		buy.add_child(price)
		buy.pressed.connect(func() -> void: _buy(cid))
		foot.add_child(buy)
		_body.add_child(panel)


func _buy(cid: String) -> void:
	if bucket == Net.ONLINE_BUCKET:
		var r: Dictionary = await App.buy_online_card(cid)
		if not is_inside_tree():
			return
		if not bool(r.get("ok", false)):
			match str(r.get("why", "")):
				"coins": _status = "NOT ENOUGH ONLINE COINS"
				"level": _status = "YOUR LEVEL IS TOO LOW FOR THAT CARD"
				_: _status = "NO SIGNAL · TRY AGAIN LATER"
	elif not App.try_buy_card(cid, bucket):
		_status = "NOT ENOUGH COINS"
	changed.emit()
	build(bucket, title_text, _sub)


func _chip(text: String, fill: Color, fg: Color, border := Color.TRANSPARENT) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	sb.set_content_margin_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	chip.add_theme_stylebox_override("panel", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(UiFont.label(text, 14, fg, UiFont.body_bold()))
	return chip


func _caps(text: String, color := Color.TRANSPARENT) -> Label:
	var l := RetroTheme.caps(text, 14, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func sub() -> String:
	return _sub


func status_text() -> String:
	var s := get_node_or_null("Sheet/VBoxContainer/Status") as Label
	return s.text if s != null else ""


func close() -> void:
	closed.emit()
	queue_free()
