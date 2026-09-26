extends Control
## Heat result: WIN / LOSS, the score line (with OT), a you/them table, then
## Rematch (same opponent, fresh seed) / Title — or Continue when a league
## sent us here (M2c).


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.17, 0.26)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-300, -480)
	vbox.size = Vector2(600, 960)
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var r := App.last_heat
	var won: bool = r.get("won", false)
	var opp: Dictionary = r.get("opponent", {})
	var you: Dictionary = r.get("sides", {}).get("player", {})
	var them: Dictionary = r.get("sides", {}).get("ai", {})
	vbox.add_child(_label("🏆 YOU WIN" if won else "😤 THEY TOOK IT", 56, Color(1.0, 0.85, 0.3) if won else Color(0.8, 0.83, 0.92)))
	var ot: int = int(r.get("ot", 0))
	vbox.add_child(_label("%d — %d%s" % [int(r.get("player_score", 0)), int(r.get("ai_score", 0)), ("   (%dOT)" % ot) if ot > 0 else ""], 64, Color(1.0, 0.81, 0.54)))
	vbox.add_child(_label("vs %s  #%d  ·  %s" % [opp.get("name", "?"), int(opp.get("number", 0)), opp.get("nickname", "")], 22, Color(0.62, 0.68, 0.85)))
	vbox.add_child(_spacer(18))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)
	_row(grid, "", "YOU", "THEM", Color(0.62, 0.68, 0.85))
	_row(grid, "makes", "%d/%d" % [int(you.get("makes", 0)), int(you.get("attempts", 0))], "%d/%d" % [int(them.get("makes", 0)), int(them.get("attempts", 0))])
	_row(grid, "shooting", _pct(you), _pct(them))
	_row(grid, "swishes", str(int(you.get("swishes", 0))), str(int(them.get("swishes", 0))))
	_row(grid, "best streak", str(int(you.get("bestStreak", 0))), str(int(them.get("bestStreak", 0))))
	_row(grid, "streak bonus", "+%d" % int(you.get("bonus", 0)), "+%d" % int(them.get("bonus", 0)))
	_row(grid, "iced over", str(int(you.get("iced", 0))), str(int(them.get("iced", 0))))
	vbox.add_child(_spacer(30))

	if r.get("league", null) != null:
		if int(r.get("coins", 0)) > 0:
			vbox.add_child(_label("🪙 +%d coins" % int(r["coins"]), 26, Color(1.0, 0.85, 0.3)))
		var drop := str(r.get("card_drop", ""))
		if drop != "":
			var card := CardDefs.get_card(drop)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 16)
			var art := TextureRect.new()
			art.texture = load(str(card.get("art", "res://assets/textures/cards/card_back.png")))
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_SCALE
			art.custom_minimum_size = Vector2(72, 96)
			row.add_child(art)
			row.add_child(_label("CARD DROP: %s" % str(card.get("name", drop)), 26, Color(0.72, 0.88, 1.0)))
			vbox.add_child(row)
		var cont := Button.new()
		cont.text = "  CONTINUE SEASON →  "
		cont.add_theme_font_size_override("font_size", 30)
		cont.custom_minimum_size = Vector2(0, 76)
		cont.pressed.connect(App.to_league_hub)
		vbox.add_child(cont)
	else:
		var again := Button.new()
		again.text = "  REMATCH 🏀  "
		again.add_theme_font_size_override("font_size", 32)
		again.custom_minimum_size = Vector2(0, 76)
		again.pressed.connect(func() -> void:
			var cfg := App.quick_heat_config(App.next_mode)
			App.start_heat(App.next_mode, cfg)
		)
		vbox.add_child(again)
	var title_btn := Button.new()
	title_btn.text = "Title"
	title_btn.add_theme_font_size_override("font_size", 24)
	title_btn.custom_minimum_size = Vector2(0, 56)
	title_btn.pressed.connect(App.to_title)
	vbox.add_child(title_btn)


func _pct(side: Dictionary) -> String:
	var a := int(side.get("attempts", 0))
	return "%d%%" % roundi(100.0 * int(side.get("makes", 0)) / a) if a > 0 else "–"


func _row(grid: GridContainer, name_: String, a: String, b: String, color := Color(0.85, 0.88, 0.95)) -> void:
	for text in [name_, a, b]:
		var l := _label(text, 24, color)
		l.custom_minimum_size = Vector2(150, 0)
		grid.add_child(l)


func _label(text: String, size_: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
