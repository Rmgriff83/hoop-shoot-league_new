extends Control
## The league dashboard: a full-screen home for one location's league with its
## own nav. Header (league, season, day / round, EXIT), a tab bar, one panel at
## a time: HEAT (next opponent's card + play / sim), STANDINGS, SCHEDULE,
## BRACKET, RECORDS (leaderboards + career). LOADOUT and SHOP arrive with the
## cards (M3). Everything is code-built like the other screens.

const PALETTES := {
	"cage": {"bg": Color(0.11, 0.1, 0.12), "panel": Color(0.17, 0.15, 0.17), "accent": Color(0.95, 0.45, 0.2), "text": Color(0.95, 0.93, 0.88), "muted": Color(0.7, 0.66, 0.62)},
	"beach": {"bg": Color(0.13, 0.12, 0.2), "panel": Color(0.2, 0.17, 0.26), "accent": Color(1.0, 0.6, 0.45), "text": Color(0.97, 0.93, 0.9), "muted": Color(0.72, 0.68, 0.76)},
}
const TABS := ["HEAT", "STANDINGS", "SCHEDULE", "BRACKET", "LOADOUT", "SHOP", "RECORDS"]

var cfg: Dictionary
var doc: Dictionary
var pal: Dictionary
var _tab_buttons: Dictionary = {}
var _panels: Dictionary = {}
var _header_sub: Label
var _body: Control


func _ready() -> void:
	cfg = App.league_cfg()
	doc = App.league_doc()
	if cfg.is_empty() or doc.is_empty():
		App.to_title()
		return
	pal = PALETTES.get(cfg.get("location", "cage"), PALETTES["cage"])
	set_anchors_preset(Control.PRESET_FULL_RECT)   # also fills when built without the .tscn
	# The area's ambience plays on its dashboard too (and carries into its heats).
	var arena: ArenaSet = CosmeticLibrary.get_arena(str(cfg.get("arena", cfg.get("location", "cage"))))
	Sfx.start_ambience(arena)
	var bg := ColorRect.new()
	bg.color = pal["bg"]
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_header()
	_build_tabs()
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_top = 210.0
	_body.offset_bottom = -16.0
	_body.offset_left = 16.0
	_body.offset_right = -16.0
	add_child(_body)
	for tab in TABS:
		var p := _make_panel()
		_body.add_child(p)
		_panels[tab] = p
	_fill_all()
	_show_tab("HEAT")


func _exit_tree() -> void:
	Sfx.stop_ambience()   # a heat of the same area cancels this fade when it starts


# ---- chrome ----

func _build_header() -> void:
	var exit := Button.new()
	exit.text = "◀ EXIT"
	exit.add_theme_font_size_override("font_size", 22)
	exit.position = Vector2(16, 14)
	exit.custom_minimum_size = Vector2(130, 52)
	exit.focus_mode = Control.FOCUS_NONE
	exit.pressed.connect(App.to_title)
	add_child(exit)
	var title := _label(str(cfg.get("name", "LEAGUE")).to_upper(), 36, pal["accent"])
	title.position = Vector2(160, 12)
	title.size = Vector2(544, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(title)
	_header_sub = _label("", 20, pal["muted"])
	_header_sub.position = Vector2(160, 62)
	_header_sub.size = Vector2(544, 30)
	_header_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_header_sub)


func _season_line() -> String:
	var s: Dictionary = doc["season"]
	match s["phase"]:
		Season.PHASE_REGULAR:
			return "Season %d · Day %d / %d" % [int(doc["year"]), int(s["currentDay"]), Season.days(s)]
		Season.PHASE_PLAYOFFS:
			var mine := Season.player_series(s, Campaign.PLAYER)
			var round_: String = ("FINAL" if mine["round"] == "final" else "SEMIFINAL") if not mine.is_empty() else "PLAYOFFS"
			return "Season %d · %s" % [int(doc["year"]), round_]
		_:
			var champ := _team_name(str(s.get("championId", "")))
			return "Season %d · 🏆 %s" % [int(doc["year"]), champ]


func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(16, 110)
	row.size = Vector2(688, 56)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for tab in TABS:
		var b := Button.new()
		b.text = tab
		b.add_theme_font_size_override("font_size", 17)
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_show_tab.bind(tab))
		row.add_child(b)
		_tab_buttons[tab] = b


func _show_tab(tab: String) -> void:
	for k in _panels:
		_panels[k].visible = k == tab
		_tab_buttons[k].disabled = k == tab


func _make_panel() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.name = "List"
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	sc.add_child(vb)
	return sc


func _list(tab: String) -> VBoxContainer:
	return _panels[tab].get_node("List")


func _clear(tab: String) -> void:
	for c in _list(tab).get_children():
		c.queue_free()


func _fill_all() -> void:
	_header_sub.text = _season_line()
	_fill_heat()
	_fill_standings()
	_fill_schedule()
	_fill_bracket()
	_fill_loadout()
	_fill_shop()
	_fill_records()


func _refresh() -> void:
	doc = App.league_doc()
	for tab in TABS:
		_clear(tab)
	# Clear runs at end of frame; rebuild next frame so children don't double up.
	await get_tree().process_frame
	_fill_all()


# ---- HEAT ----

func _fill_heat() -> void:
	var vb := _list("HEAT")
	var s: Dictionary = doc["season"]
	var opp_id := Campaign.next_opponent(doc)
	if s["phase"] == Season.PHASE_DONE:
		var champ := str(s.get("championId", ""))
		vb.add_child(_label("🏆 CHAMPION: %s" % _team_name(champ), 34, pal["accent"]))
		var summ := Campaign.season_summary(doc, cfg)
		vb.add_child(_label("You finished %s%s" % [_ordinal(int(summ["finish"])), _playoff_text(summ["playoffResult"])], 22, pal["text"]))
		var nxt := _big_button("START SEASON %d →" % (int(doc["year"]) + 1))
		nxt.pressed.connect(func() -> void:
			var d := App.league_doc()
			Campaign.start_next_season(d, cfg)
			App.save_league_doc(d)
			_refresh()
		)
		vb.add_child(nxt)
		return
	if opp_id == "":
		vb.add_child(_label("You're out of the playoffs this year.", 22, pal["text"]))
		var adv := _big_button("ADVANCE LEAGUE ⏩")
		adv.pressed.connect(func() -> void:
			var d := App.league_doc()
			var guard := 0
			while d["season"]["phase"] == Season.PHASE_PLAYOFFS and guard < 10:
				Campaign.sim_step(d, cfg)
				guard += 1
			App.save_league_doc(d)
			_refresh()
		)
		vb.add_child(adv)
		return
	var shooter := LeagueData.shooter(opp_id)
	vb.add_child(_label("NEXT HEAT" if s["phase"] == Season.PHASE_REGULAR else "PLAYOFF HEAT", 20, pal["muted"]))
	vb.add_child(_shooter_card(shooter))
	if s["phase"] == Season.PHASE_PLAYOFFS:
		var mine := Season.player_series(s, Campaign.PLAYER)
		var high: bool = mine["highSeedId"] == Campaign.PLAYER
		var yw: int = mine["highWins"] if high else mine["lowWins"]
		var tw: int = mine["lowWins"] if high else mine["highWins"]
		vb.add_child(_label("Series %d–%d · best of %d · game %d" % [yw, tw, int(mine["bestOf"]), yw + tw + 1], 22, pal["text"]))
		vb.add_child(_label("Playoff heats are always played live.", 18, pal["muted"]))
	else:
		var rec := _record_vs(opp_id)
		vb.add_child(_label("Your record vs them: %d–%d" % [rec[0], rec[1]], 20, pal["muted"]))
	var play := _big_button("PLAY HEAT 🏀")
	play.pressed.connect(App.start_league_heat)
	vb.add_child(play)
	if s["phase"] == Season.PHASE_REGULAR:
		var sim := _small_button("SIM THIS DAY")
		sim.pressed.connect(func() -> void:
			var d := App.league_doc()
			Campaign.sim_step(d, cfg)
			App.save_league_doc(d)
			_refresh()
		)
		vb.add_child(sim)
		var sim_all := _small_button("SIM TO PLAYOFFS ⏩")
		sim_all.pressed.connect(func() -> void:
			var d := App.league_doc()
			Campaign.sim_to_playoffs(d, cfg)
			App.save_league_doc(d)
			_refresh()
		)
		vb.add_child(sim_all)


func _record_vs(opp_id: String) -> Array:
	var w := 0
	var l := 0
	for g in doc["season"]["schedule"]:
		if not g["played"]:
			continue
		var mine: bool = (g["homeId"] == Campaign.PLAYER and g["awayId"] == opp_id) or (g["awayId"] == Campaign.PLAYER and g["homeId"] == opp_id)
		if not mine:
			continue
		if Standings.winner_of(g) == Campaign.PLAYER:
			w += 1
		else:
			l += 1
	return [w, l]


## A shooter card: colours, number, name, nickname, hometown, stars, bio.
func _shooter_card(sh: Dictionary) -> Control:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.html(str(sh.get("colors", {}).get("secondary", "#333")))
	style.border_color = Color.html(str(sh.get("colors", {}).get("accent", "#fff")))
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	vb.add_child(top)
	var num := _label("#%d" % int(sh.get("number", 0)), 44, Color.html(str(sh.get("colors", {}).get("accent", "#fff"))))
	num.custom_minimum_size = Vector2(110, 0)
	top.add_child(num)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	names.add_child(_label(str(sh.get("name", "?")), 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT))
	names.add_child(_label("\"%s\" · %s" % [sh.get("nickname", ""), sh.get("hometown", "")], 18, Color(0.85, 0.85, 0.9), HORIZONTAL_ALIGNMENT_LEFT))
	var r: Dictionary = sh.get("ratings", {})
	vb.add_child(_label("accuracy %s   arc %s   pace %.1fs" % [_stars(float(r.get("accuracy", 0.5))), _stars(float(r.get("swishRate", 0.5))), float(r.get("pace", 4.0))], 18, Color(0.9, 0.9, 0.95), HORIZONTAL_ALIGNMENT_LEFT))
	var bio := _label(str(sh.get("bio", "")), 17, Color(0.8, 0.8, 0.86), HORIZONTAL_ALIGNMENT_LEFT)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(bio)
	var sig := _label(str(sh.get("signature", "")), 16, Color.html(str(sh.get("colors", {}).get("accent", "#fff"))), HORIZONTAL_ALIGNMENT_LEFT)
	sig.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sig)
	return card


func _stars(v: float) -> String:
	var n := clampi(roundi(v * 5.0), 0, 5)
	return "●".repeat(n) + "○".repeat(5 - n)


# ---- STANDINGS ----

func _fill_standings() -> void:
	var vb := _list("STANDINGS")
	var s: Dictionary = doc["season"]
	var ids := LeagueData.team_ids(cfg)
	var table := Standings.table(ids, s["schedule"], int(s["seed"]))
	var clinches := Standings.compute_clinches(ids, s["schedule"], int(s.get("playoffTeams", 4)))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for h in ["#", "team", "W", "L", "pct", "GB", "strk"]:
		grid.add_child(_label(h, 17, pal["muted"]))
	var leader: Dictionary = table[0]
	for i in table.size():
		var row: Dictionary = table[i]
		var id: String = row["teamId"]
		var mine := id == Campaign.PLAYER
		var color: Color = pal["accent"] if mine else pal["text"]
		var badge := ""
		var c: Dictionary = clinches.get(id, {})
		if c.get("topSeed", false):
			badge = " ★1"
		elif c.get("playoffs", false):
			badge = " ✓"
		elif c.get("eliminated", false):
			badge = " ✗"
		var streak := Standings.current_streak(id, s["schedule"])
		var strk := "%s%d" % [streak["type"], streak["count"]] if not streak.is_empty() else "–"
		if not streak.is_empty() and int(streak["count"]) >= 3:
			strk += " 🔥" if streak["type"] == "W" else " 🧊"
		var cells := [str(i + 1), _team_name(id) + badge, str(row["w"]), str(row["l"]), "%.3f" % float(row["pct"]),
			"%.1f" % Standings.games_behind(leader, row), strk]
		for k in cells.size():
			var l := _label(cells[k], 18, color, HORIZONTAL_ALIGNMENT_LEFT if k == 1 else HORIZONTAL_ALIGNMENT_CENTER)
			if k == 1:
				l.custom_minimum_size = Vector2(230, 0)
			grid.add_child(l)
		if i == int(s.get("playoffTeams", 4)) - 1:
			for k in 7:
				grid.add_child(_label("· · ·" if k == 1 else "", 12, pal["muted"]))
	vb.add_child(_label("top %d make the playoffs · ★1 top seed · ✓ clinched · ✗ eliminated" % int(s.get("playoffTeams", 4)), 15, pal["muted"]))


# ---- SCHEDULE ----

func _fill_schedule() -> void:
	var vb := _list("SCHEDULE")
	var s: Dictionary = doc["season"]
	var today := int(s["currentDay"])
	for g in s["schedule"]:
		if g["homeId"] != Campaign.PLAYER and g["awayId"] != Campaign.PLAYER:
			continue
		var home: bool = g["homeId"] == Campaign.PLAYER
		var opp: String = g["awayId"] if home else g["homeId"]
		var text := "Day %2d  %s %s" % [int(g["day"]), "vs" if home else "@ ", _team_name(opp)]
		var color: Color = pal["text"]
		if g["played"]:
			var mine := int(g["homeScore"] if home else g["awayScore"])
			var theirs := int(g["awayScore"] if home else g["homeScore"])
			var won := mine > theirs
			text += "   %s %d–%d%s%s" % ["W" if won else "L", mine, theirs, (" (%dOT)" % int(g["ot"])) if int(g["ot"]) > 0 else "", "" if g["playedLive"] else " · sim"]
			color = Color(0.6, 0.9, 0.7) if won else Color(0.95, 0.6, 0.6)
		elif int(g["day"]) == today and s["phase"] == Season.PHASE_REGULAR:
			text += "   ◀ today"
			color = pal["accent"]
		vb.add_child(_label(text, 19, color, HORIZONTAL_ALIGNMENT_LEFT))
	if not s["series"].is_empty():
		vb.add_child(_label("— PLAYOFFS —", 20, pal["muted"]))
		for series in s["series"]:
			if series["highSeedId"] != Campaign.PLAYER and series["lowSeedId"] != Campaign.PLAYER:
				continue
			for g in series["games"]:
				var high: bool = g["homeId"] == Campaign.PLAYER
				var mine := int(g["homeScore"] if high else g["awayScore"])
				var theirs := int(g["awayScore"] if high else g["homeScore"])
				vb.add_child(_label("%s  %s %d–%d vs %s" % [series["round"].to_upper(), "W" if mine > theirs else "L", mine, theirs,
					_team_name(g["awayId"] if high else g["homeId"])], 19, Color(0.6, 0.9, 0.7) if mine > theirs else Color(0.95, 0.6, 0.6), HORIZONTAL_ALIGNMENT_LEFT))


# ---- BRACKET ----

func _fill_bracket() -> void:
	var vb := _list("BRACKET")
	var s: Dictionary = doc["season"]
	if s["series"].is_empty():
		vb.add_child(_label("The bracket forms after day %d." % Season.days(s), 20, pal["muted"]))
		return
	for round_name in ["semifinal", "final"]:
		vb.add_child(_label("SEMIFINALS" if round_name == "semifinal" else "FINAL", 22, pal["accent"]))
		var any := false
		for series in s["series"]:
			if series["round"] != round_name:
				continue
			any = true
			var hw := int(series["highWins"])
			var lw := int(series["lowWins"])
			var done: bool = series["winnerId"] != ""
			vb.add_child(_label("%s  %d – %d  %s   (Bo%d)%s" % [_team_name(series["highSeedId"]), hw, lw, _team_name(series["lowSeedId"]), int(series["bestOf"]),
				("  → " + _team_name(series["winnerId"])) if done else ""], 19, pal["text"], HORIZONTAL_ALIGNMENT_LEFT))
		if not any:
			vb.add_child(_label("TBD", 19, pal["muted"], HORIZONTAL_ALIGNMENT_LEFT))
	if s.get("championId", "") != "":
		vb.add_child(_label("🏆 %s" % _team_name(str(s["championId"])), 26, pal["accent"]))


# ---- LOADOUT ----

func _card_button(card: Dictionary, size_: Vector2) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = load(str(card.get("art", "res://assets/textures/cards/card_back.png")))
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = size_
	b.focus_mode = Control.FOCUS_NONE
	return b


func _fill_loadout() -> void:
	var vb := _list("LOADOUT")
	var cd := App.cards_bucket(cfg["id"])
	vb.add_child(_label("EQUIPPED · %d slots · one-time use · tap a slot to put it back" % CardDefs.SLOTS, 18, pal["muted"]))
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 18)
	vb.add_child(slots)
	for i in CardDefs.SLOTS:
		var id: Variant = cd["loadout"][i]
		var card := CardDefs.get_card(str(id)) if id != null else {}
		var b := _card_button(card if not card.is_empty() else {"art": "res://assets/textures/cards/card_back.png"}, Vector2(132, 176))
		if card.is_empty():
			b.modulate = Color(0.6, 0.6, 0.7)
		b.pressed.connect(func() -> void:
			App.unequip_card(i, cfg["id"])
			_refresh()
		)
		slots.add_child(b)
	vb.add_child(_label("SPARES · tap a card to equip a copy in the first free slot", 18, pal["muted"]))
	var inv: Dictionary = cd.get("inventory", {})
	if inv.is_empty():
		var any_equipped := not CardDefs.loadout_ids(cd).is_empty()
		vb.add_child(_label("no spare cards — win heats or visit the shop" if any_equipped else "no cards yet — win heats or visit the shop", 18, pal["text"]))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	for id in inv:
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var cell := VBoxContainer.new()
		var b := _card_button(card, Vector2(120, 160))
		b.pressed.connect(func() -> void:
			for slot in CardDefs.SLOTS:
				if App.cards_bucket(cfg["id"])["loadout"][slot] == null:
					App.equip_card(slot, str(id), cfg["id"])
					break
			_refresh()
		)
		cell.add_child(b)
		cell.add_child(_label("%s ×%d" % [card.get("name", id), int(inv[id])], 16, pal["text"]))
		grid.add_child(cell)
	for card in CardDefs.all():
		var line := _label("%s — %s" % [card["name"], card["blurb"]], 15, pal["muted"], HORIZONTAL_ALIGNMENT_LEFT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(line)


# ---- SHOP ----

func _fill_shop() -> void:
	var vb := _list("SHOP")
	vb.add_child(_label("%d COINS · %s" % [App.league_coins(cfg["id"]), str(cfg.get("name", "")).to_upper()], 26, pal["accent"]))
	vb.add_child(_label("coins are earned and spent in this league; its cards play only here", 15, pal["muted"]))
	vb.add_child(_label("— CARDS —", 20, pal["muted"]))
	for card in CardDefs.all():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var b := _card_button(card, Vector2(84, 112))
		row.add_child(b)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label("%s · %s" % [card["name"], card["rarity"]], 22, pal["text"], HORIZONTAL_ALIGNMENT_LEFT))
		var blurb := _label(str(card["blurb"]), 15, pal["muted"], HORIZONTAL_ALIGNMENT_LEFT)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(blurb)
		var cdoc := App.cards_bucket(cfg["id"])
		var owned_n := CardDefs.owned(cdoc, str(card["id"]))
		var spare_n := CardDefs.count(cdoc, str(card["id"]))
		var owned_txt := "owned ×%d" % owned_n
		if owned_n > spare_n:
			owned_txt += " · %d equipped" % (owned_n - spare_n)
		col.add_child(_label(owned_txt, 15, pal["muted"], HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(col)
		var buy := _small_button("BUY %d" % int(card["price"]))
		buy.custom_minimum_size = Vector2(150, 52)
		buy.disabled = App.league_coins(cfg["id"]) < int(card["price"])
		buy.pressed.connect(func() -> void:
			if App.try_buy_card(card["id"], cfg["id"]):
				_refresh()
		)
		row.add_child(buy)
		vb.add_child(row)
	vb.add_child(_label("balls and hoops are in the LOCKER on the home page, for tickets", 15, pal["muted"]))


# ---- RECORDS ----

func _fill_records() -> void:
	var vb := _list("RECORDS")
	var tot: Dictionary = doc["career"]["totals"]
	var highs: Dictionary = doc["career"]["highs"]
	vb.add_child(_label("CAREER · %s" % cfg.get("name", ""), 22, pal["accent"]))
	vb.add_child(_label("%d–%d · 💍 %d · high %d pts · %d✨ · 🔥%d" % [int(tot["wins"]), int(tot["losses"]), int(doc["career"]["championships"]),
		int(highs["points"]), int(highs["swishes"]), int(highs["streak"])], 19, pal["text"]))
	for summ in doc["career"]["seasons"]:
		vb.add_child(_label("Season %d: %d–%d, %s%s" % [int(summ["year"]), int(summ["w"]), int(summ["l"]), _ordinal(int(summ["finish"])), _playoff_text(summ["playoffResult"])], 17, pal["muted"], HORIZONTAL_ALIGNMENT_LEFT))
	vb.add_child(_label("— BEST HEATS —", 20, pal["accent"]))
	var games := SaveService.live_games(cfg["id"], 10)
	if games.is_empty():
		vb.add_child(_label("no heats yet", 17, pal["muted"]))
	for i in games.size():
		var g: Dictionary = games[i]
		vb.add_child(_label("%2d.  %3d–%-3d %s vs %s   %d✨ 🔥%d" % [i + 1, int(g["playerScore"]), int(g["oppScore"]), "W" if g.get("won", false) else "L",
			_team_name(str(g.get("opponentId", ""))), int(g.get("swishes", 0)), int(g.get("bestStreak", 0))], 17, pal["text"], HORIZONTAL_ALIGNMENT_LEFT))
	vb.add_child(_label("— TIME TRIAL · %s —" % str(cfg.get("location", "")).to_upper(), 20, pal["accent"]))
	var top := SaveService.top_scores(5, str(cfg.get("location", "cage")))
	if top.is_empty():
		vb.add_child(_label("no time trials yet", 17, pal["muted"]))
	for i in top.size():
		var d: Dictionary = top[i]
		vb.add_child(_label("%2d.  %3d pts   %d✨  🔥%d" % [i + 1, int(d["score"]), int(d.get("swishes", 0)), int(d.get("bestStreak", 0))], 17, pal["text"], HORIZONTAL_ALIGNMENT_LEFT))


# ---- helpers ----

func _team_name(id: String) -> String:
	if id == Campaign.PLAYER:
		return "You"
	var sh := LeagueData.shooter(id)
	return str(sh.get("name", id))


func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]


func _playoff_text(result: String) -> String:
	match result:
		"champion":
			return " · 🏆 champion"
		"runner_up":
			return " · runner-up"
		"semifinal":
			return " · semifinalist"
		_:
			return " · missed the playoffs"


func _label(text: String, size_: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.add_theme_font_size_override("font_size", 30)
	b.custom_minimum_size = Vector2(0, 76)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(0, 52)
	b.focus_mode = Control.FOCUS_NONE
	return b
