class_name LeagueContext
extends Control
## The league, in context on the home page (docs/HOME.md, design "Home
## League Context v2"): fills the home's card area when LEAGUE is tapped.
## A tab row — "<" back, HEAT · TABLE · SCHED · CARDS · STATS — over one
## clip in which the panes slide sideways. Everything the old full-screen
## hub did lives here: the next heat (opponent card, PLAY HEAT, SIM DAY / SIM
## ALL, playoffs, advance, next season), the table / bracket, the schedule,
## this league's cards (loadout + shop, this league's coins), and the
## career / best heats / time-trial records. Built for one league from
## App.league_cfg / league_doc. `closed` = "<"; `changed` = the doc moved
## (the home refreshes its zone line and ticker).

signal closed
signal changed

const TABS := ["HEAT", "TABLE", "SCHED", "CARDS", "STATS"]
const PINE := Color("#3E7C4F")
const HI := Color("#FFCE8A")
const BLUE := Color("#7FAEC6")
const CREAM := RetroTheme.SCENE_TEXT
const TAB_H := 58.0
const SLIDE_S := 0.3

var league_id := ""
var cfg: Dictionary = {}
var doc: Dictionary = {}

var _tab := "HEAT"
var _card_sub := "LOADOUT"
var _tab_row: HBoxContainer
var _clip: Control
var _panes: Dictionary = {}
var _switching := false


func setup(id: String) -> void:
	league_id = id
	cfg = App.league_cfg(id)
	doc = App.league_doc(id)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = Control.new()
	_clip.name = "Panes"
	_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clip.offset_top = TAB_H + 16
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	for tab in TABS:
		var pane := _make_pane()
		pane.name = "Pane_" + tab
		pane.visible = tab == _tab
		_clip.add_child(pane)
		_panes[tab] = pane
	_build_tabs()
	_fill_all()


## The doc moved (a sim, a purchase, an equip): re-read and rebuild the panes.
func refresh() -> void:
	doc = App.league_doc(league_id)
	for tab in TABS:
		for c in _list(tab).get_children():
			_list(tab).remove_child(c)
			c.free()
	_fill_all()
	changed.emit()


# ---- chrome ----------------------------------------------------------------------


func _build_tabs() -> void:
	if _tab_row != null:
		_tab_row.queue_free()
	_tab_row = HBoxContainer.new()
	_tab_row.name = "Tabs"
	_tab_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tab_row.offset_bottom = TAB_H
	_tab_row.offset_right = -6
	_tab_row.add_theme_constant_override("separation", 10)
	add_child(_tab_row)
	var back := ShadowCard.new(CREAM)
	back.name = "Back"
	back.text = "<"
	back.custom_minimum_size = Vector2(52 + ShadowStyle.OFFSET, 52 + ShadowStyle.OFFSET)
	back.add_theme_font_override("font", UiFont.display())
	back.add_theme_font_size_override("font_size", UiFont.snap(24))
	RetroTheme.on_scene(back)
	back.pressed.connect(func() -> void: closed.emit())
	_tab_row.add_child(back)
	for tab in TABS:
		var b := _tab_button(tab, tab == _tab, 16)
		b.name = "Tab_" + tab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: String = tab
		b.pressed.connect(func() -> void: _show_tab(t))
		_tab_row.add_child(b)


## Active: a solid cream face with the ink shadow. Inactive: see-through cream.
func _tab_button(text: String, active: bool, size_: int, height := 52.0) -> Button:
	var b: Button
	if active:
		b = Button.new()
		RetroTheme.card_button(b, RetroTheme.c("panel"), RetroTheme.RADIUS, 0.0)
		b.add_theme_font_size_override("font_size", UiFont.snap(size_))
		b.disabled = true
		b.add_theme_color_override("font_disabled_color", RetroTheme.c("text"))
	else:
		b = ShadowCard.new(CREAM)
		b.add_theme_font_override("font", UiFont.display())
		b.add_theme_font_size_override("font_size", UiFont.snap(size_))
		RetroTheme.on_scene(b)
	b.text = text
	b.custom_minimum_size = Vector2(0, height + ShadowStyle.OFFSET)
	return b


func _make_pane() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.name = "List"
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 20)
	sc.add_child(vb)
	return sc


func _list(tab: String) -> VBoxContainer:
	return _panes[tab].get_node("List")


func current_tab() -> String:
	return _tab


## Slide the current pane out and the next one in (the design's translateX).
func _show_tab(tab: String) -> void:
	if tab == _tab or _switching or not _panes.has(tab):
		return
	var dir := 1 if TABS.find(tab) > TABS.find(_tab) else -1
	var old: ScrollContainer = _panes[_tab]
	var new_: ScrollContainer = _panes[tab]
	_tab = tab
	_build_tabs()
	if not is_inside_tree():
		old.visible = false
		new_.visible = true
		return
	_switching = true
	var w := _clip.size.x
	new_.visible = true
	new_.position.x = dir * w
	var tw := create_tween().set_parallel(true)
	tw.tween_property(new_, "position:x", 0.0, SLIDE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(old, "position:x", -dir * w, SLIDE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	old.visible = false
	old.position.x = 0.0
	_switching = false


# ---- text helpers ----------------------------------------------------------------


## Small caps over the court (cream + ink outline), or in a given colour.
func _caps(text: String, color := CREAM) -> Label:
	var l := RetroTheme.on_scene(RetroTheme.caps(text, 16)) as Label
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _display(text: String, size_: int, color := CREAM) -> Label:
	var l := RetroTheme.on_scene(UiFont.label(text, size_, color)) as Label
	l.add_theme_color_override("font_color", color)
	return l


## Ink text inside a cream panel (no outline).
func _ink(text: String, size_ := 16, muted := false, display := false) -> Label:
	var l := UiFont.label(text, size_, RetroTheme.c("muted") if muted else RetroTheme.c("text"), UiFont.display() if display else UiFont.body_bold())
	return l


## A cream panel with the solid ink shadow (the table, the lists).
func _cream(pad := 20.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", RetroTheme.face(RetroTheme.c("panel"), RetroTheme.RADIUS, pad))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A row inside a cream panel, optionally highlighted.
func _row(height: float, fill := Color.TRANSPARENT) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, height)
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill.a > 0.0:
		var bg := StyleBoxFlat.new()
		bg.bg_color = fill
		var wrap := PanelContainer.new()
		wrap.add_theme_stylebox_override("panel", bg)
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(h)
		h.set_meta("wrap", wrap)
	return h


func _wrapped(h: HBoxContainer) -> Control:
	return h.get_meta("wrap") if h.has_meta("wrap") else h


func _cell(l: Label, w: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _team_name(id: String) -> String:
	if id == Campaign.PLAYER:
		return "YOU"
	return str(LeagueData.shooter(id).get("name", id)).to_upper()


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


class DashedRule extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 3)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_dashed_line(Vector2(0, 1.5), Vector2(size.x, 1.5), RetroTheme.c("text"), 3.0, 10.0)


# ---- fill ------------------------------------------------------------------------


func _fill_all() -> void:
	_fill_heat()
	_fill_table()
	_fill_sched()
	_fill_cards()
	_fill_stats()


func _season_meta() -> Dictionary:
	var s: Dictionary = doc["season"]
	return {"s": s, "year": int(doc.get("year", 1)), "phase": str(s["phase"]), "day": int(s.get("currentDay", 1))}


# ---- HEAT ------------------------------------------------------------------------


func _fill_heat() -> void:
	var vb := _list("HEAT")
	var m := _season_meta()
	var s: Dictionary = m["s"]
	var opp_id := Campaign.next_opponent(doc)
	if m["phase"] == Season.PHASE_DONE:
		var champ := str(s.get("championId", ""))
		vb.add_child(_caps("SEASON %d · OVER" % m["year"]))
		vb.add_child(_display("CHAMPION: %s" % _team_name(champ), 24, HI))
		var summ := Campaign.season_summary(doc, cfg)
		vb.add_child(_caps("YOU FINISHED %s%s" % [TickerText.ordinal(int(summ["finish"])), _playoff_text(str(summ["playoffResult"]))]))
		var nxt := ModeCards.card("START SEASON %d" % (m["year"] + 1), "NEW SCHEDULE · SAME LEAGUE", RetroTheme.c("orange"), 24, true)
		nxt.name = "NextSeason"
		nxt.custom_minimum_size = Vector2(0, 136)
		nxt.pressed.connect(func() -> void:
			var d := App.league_doc(league_id)
			Campaign.start_next_season(d, cfg)
			App.save_league_doc(d, league_id)
			refresh()
		)
		vb.add_child(nxt)
		return
	if opp_id == "":
		vb.add_child(_caps("YOU ARE OUT OF THE PLAYOFFS THIS YEAR"))
		var adv := ModeCards.card("ADVANCE", "PLAY OUT THE BRACKET", RetroTheme.c("teal"), 24, true)
		adv.name = "Advance"
		adv.custom_minimum_size = Vector2(0, 116)
		adv.pressed.connect(func() -> void:
			var d := App.league_doc(league_id)
			var guard := 0
			while d["season"]["phase"] == Season.PHASE_PLAYOFFS and guard < 10:
				Campaign.sim_step(d, cfg)
				guard += 1
			App.save_league_doc(d, league_id)
			refresh()
		)
		vb.add_child(adv)
		return
	var shooter := LeagueData.shooter(opp_id)
	var playoffs: bool = m["phase"] == Season.PHASE_PLAYOFFS
	var play_sub := ""
	var play_title := "PLAY HEAT"
	if playoffs:
		var mine := Season.player_series(s, Campaign.PLAYER)
		var high: bool = mine["highSeedId"] == Campaign.PLAYER
		var yw := int(mine["highWins"] if high else mine["lowWins"])
		var tw := int(mine["lowWins"] if high else mine["highWins"])
		var round_ := "FINAL" if str(mine.get("round", "")) == "final" else "SEMI"
		vb.add_child(_caps("PLAYOFF HEAT · %s · GAME %d · SERIES %d-%d" % [round_, yw + tw + 1, yw, tw]))
		play_title = "PLAY GAME %d" % (yw + tw + 1)
		play_sub = "SERIES %d-%d · %s" % [yw, tw, "WINNER TAKES THE TITLE" if round_ == "FINAL" else "WINNER TO THE FINAL"]
	else:
		var g := Season.player_game_on(s, m["day"], Campaign.PLAYER)
		var home: bool = not g.is_empty() and g["homeId"] == Campaign.PLAYER
		var rec := _record_vs(opp_id)
		vb.add_child(_caps("NEXT HEAT · DAY %d · %s · YOU %d-%d VS THEM" % [m["day"], "HOME" if home else "AWAY", rec[0], rec[1]]))
		play_sub = "%d S · %d CARDS EQUIPPED" % [int(cfg.get("heat_seconds", 90)), App.loadout_hand(league_id).size()]
	vb.add_child(_shooter_card(shooter))
	var play := ModeCards.card(play_title, play_sub, RetroTheme.c("orange"), 32, true)
	play.name = "PlayHeat"
	play.custom_minimum_size = Vector2(0, 136)
	play.pressed.connect(func() -> void: App.start_league_heat())
	vb.add_child(play)
	if playoffs:
		vb.add_child(_caps("PLAYOFF HEATS ARE ALWAYS PLAYED LIVE"))
	else:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 26)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(pair)
		var sim := ModeCards.card("SIM DAY", "DAY %d ONLY" % m["day"], RetroTheme.c("teal"), 24)
		sim.name = "SimDay"
		sim.custom_minimum_size = Vector2(0, 116)
		sim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sim.pressed.connect(func() -> void:
			var d := App.league_doc(league_id)
			Campaign.sim_step(d, cfg)
			App.save_league_doc(d, league_id)
			refresh()
		)
		pair.add_child(sim)
		var sim_all := ModeCards.card("SIM ALL", "TO THE PLAYOFFS", BLUE, 24)
		sim_all.name = "SimAll"
		sim_all.custom_minimum_size = Vector2(0, 116)
		sim_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sim_all.pressed.connect(func() -> void:
			var d := App.league_doc(league_id)
			Campaign.sim_to_playoffs(d, cfg)
			App.save_league_doc(d, league_id)
			refresh()
		)
		pair.add_child(sim_all)


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


## The opponent card: pine, see-through — name, nickname · hometown, the
## number, five-segment ACCURACY / ARC, PACE, bio, signature.
func _shooter_card(sh: Dictionary) -> Control:
	var card := ShadowPanel.new(PINE, 24.0)
	card.name = "Opponent"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 12)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(names)
	var nm := _display(str(sh.get("name", "?")).to_upper(), 32)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	names.add_child(nm)
	names.add_child(_caps("\"%s\" · %s" % [str(sh.get("nickname", "")).to_upper(), str(sh.get("hometown", "")).to_upper()]))
	top.add_child(_display(str(int(sh.get("number", 0))), 64, HI))
	var r: Dictionary = sh.get("ratings", {})
	for spec in [["ACCURACY", float(r.get("accuracy", 0.5))], ["ARC", float(r.get("swishRate", 0.5))]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(_cell(_caps(spec[0]), 160))
		var segs := HBoxContainer.new()
		segs.add_theme_constant_override("separation", 6)
		segs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := clampi(roundi(float(spec[1]) * 5.0), 0, 5)
		for i in 5:
			var seg := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = HI if i < n else Color(RetroTheme.SCENE_OUTLINE, 0.55)
			sb.border_color = CREAM
			sb.set_border_width_all(2)
			seg.add_theme_stylebox_override("panel", sb)
			seg.custom_minimum_size = Vector2(32, 16)
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			segs.add_child(seg)
		line.add_child(segs)
		vb.add_child(line)
	var pace := HBoxContainer.new()
	pace.add_theme_constant_override("separation", 16)
	pace.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pace.add_child(_cell(_caps("PACE"), 160))
	pace.add_child(_display("%.1f S" % float(r.get("pace", 4.0)), 16))
	vb.add_child(pace)
	var bio := RetroTheme.on_scene(UiFont.label(str(sh.get("bio", "")), 16, CREAM, UiFont.body())) as Label
	bio.add_theme_constant_override("outline_size", 2)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(bio)
	var sig := _caps(str(sh.get("signature", "")), HI)
	vb.add_child(sig)
	return card


# ---- TABLE -----------------------------------------------------------------------


func _fill_table() -> void:
	var vb := _list("TABLE")
	var m := _season_meta()
	var s: Dictionary = m["s"]
	var spots := int(s.get("playoffTeams", 4))
	if m["phase"] == Season.PHASE_REGULAR or Array(s.get("series", [])).is_empty():
		vb.add_child(_caps("REGULAR SEASON · AFTER DAY %d" % maxi(int(m["day"]) - 1, 0)))
		var panel := _cream(16.0)
		panel.name = "Standings"
		vb.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(col)
		var head := _row(44)
		for spec in [["#", 48], ["SHOOTER", 0], ["W", 48], ["L", 48], ["GB", 72], ["STRK", 88]]:
			var l := _cell(_ink(spec[0], 16, true), spec[1])
			if spec[1] == 0:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head.add_child(l)
		col.add_child(head)
		var ids := LeagueData.team_ids(cfg)
		var table := Standings.table(ids, s["schedule"], int(s["seed"]))
		var leader: Dictionary = table[0]
		for i in table.size():
			var row: Dictionary = table[i]
			var id: String = row["teamId"]
			var mine := id == Campaign.PLAYER
			var r := _row(56, RetroTheme.c("orange") if mine else Color.TRANSPARENT)
			r.name = "Row_%d" % (i + 1)
			r.add_child(_cell(_ink(str(i + 1), 16, false, true), 48))
			var nm := _cell(_ink(_team_name(id), 24), 0)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.clip_text = true
			r.add_child(nm)
			r.add_child(_cell(_ink(str(row["w"]), 16, false, true), 48))
			r.add_child(_cell(_ink(str(row["l"]), 16, false, true), 48))
			r.add_child(_cell(_ink("%.1f" % Standings.games_behind(leader, row) if i > 0 else "-", 16, false, true), 72))
			var streak := Standings.current_streak(id, s["schedule"])
			var strk := HBoxContainer.new()
			strk.add_theme_constant_override("separation", 8)
			strk.custom_minimum_size = Vector2(88, 0)
			strk.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sq := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = (RetroTheme.c("orange") if streak.get("type", "") == "W" else BLUE) if not streak.is_empty() else Color.TRANSPARENT
			sb.border_color = RetroTheme.c("text")
			sb.set_border_width_all(3)
			sq.add_theme_stylebox_override("panel", sb)
			sq.custom_minimum_size = Vector2(14, 14)
			sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strk.add_child(sq)
			strk.add_child(_cell(_ink("%s%d" % [streak["type"], int(streak["count"])] if not streak.is_empty() else "-", 16, false, true), 40))
			r.add_child(strk)
			col.add_child(_wrapped(r))
			if i == spots - 1 and i < table.size() - 1:
				var cut := HBoxContainer.new()
				cut.custom_minimum_size = Vector2(0, 36)
				cut.add_theme_constant_override("separation", 12)
				cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cut.add_child(DashedRule.new())
				cut.add_child(_ink("PLAYOFF LINE", 16))
				cut.add_child(DashedRule.new())
				col.add_child(cut)
		vb.add_child(_caps("TOP %d MAKE THE PLAYOFFS · SEMIS BEST OF %d · FINAL BEST OF %d" % [spots, int(s.get("semisBestOf", 3)), int(s.get("finalBestOf", 5))]))
		return
	# Playoffs: the bracket.
	vb.add_child(_caps("PLAYOFFS · SEASON %d" % m["year"]))
	var n_semi := 0
	for series in s["series"]:
		if series["round"] != "semifinal":
			continue
		n_semi += 1
		var done: bool = series["winnerId"] != ""
		var g := int(series["highWins"]) + int(series["lowWins"])
		vb.add_child(_caps("SEMI %d · BO%d · %s" % [n_semi, int(series["bestOf"]), "DONE" if done else "GAME %d" % (g + 1)]))
		vb.add_child(_series_panel(series))
	var final_ := Playoffs.find(s["series"], "final")
	vb.add_child(_caps("FINAL · BO%d" % int(s.get("finalBestOf", 5))))
	if final_.is_empty():
		var panel := _cream(12.0)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(col)
		var r1 := _row(52)
		r1.add_child(_cell(_ink("?", 16, true, true), 24))
		r1.add_child(_ink("SEMI WINNERS", 16, true))
		col.add_child(r1)
		vb.add_child(panel)
	else:
		vb.add_child(_series_panel(final_))
	if str(s.get("championId", "")) != "":
		vb.add_child(_display("CHAMPION: %s" % _team_name(str(s["championId"])), 24, HI))
	vb.add_child(_caps("SEEDS FROM THE FINAL TABLE · 1 V 4 · 2 V 3"))


func _series_panel(series: Dictionary) -> Control:
	var panel := _cream(12.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	for side in [["highSeedId", "highWins"], ["lowSeedId", "lowWins"]]:
		var id := str(series[side[0]])
		var r := _row(52, RetroTheme.c("orange") if id == Campaign.PLAYER else Color.TRANSPARENT)
		r.add_child(_cell(_ink(str(int(series.get("seed_" + side[0], 0))) if series.has("seed_" + side[0]) else "", 16, false, true), 24))
		var nm := _ink(_team_name(id), 24)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nm)
		r.add_child(_cell(_ink(str(int(series[side[1]])), 24, false, true), 40, HORIZONTAL_ALIGNMENT_RIGHT))
		col.add_child(_wrapped(r))
	return panel


# ---- SCHED -----------------------------------------------------------------------


func _fill_sched() -> void:
	var vb := _list("SCHED")
	var m := _season_meta()
	var s: Dictionary = m["s"]
	var w := 0
	var l := 0
	for g in s["schedule"]:
		if g["played"] and (g["homeId"] == Campaign.PLAYER or g["awayId"] == Campaign.PLAYER):
			if Standings.winner_of(g) == Campaign.PLAYER:
				w += 1
			else:
				l += 1
	vb.add_child(_caps("%d DAYS · %d-%d SO FAR" % [Season.days(s), w, l]))
	var panel := _cream(12.0)
	panel.name = "Schedule"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	for g in s["schedule"]:
		if g["homeId"] != Campaign.PLAYER and g["awayId"] != Campaign.PLAYER:
			continue
		var home: bool = g["homeId"] == Campaign.PLAYER
		var opp: String = g["awayId"] if home else g["homeId"]
		var today: bool = int(g["day"]) == int(m["day"]) and m["phase"] == Season.PHASE_REGULAR
		var r := _row(52, RetroTheme.c("gold") if today else Color.TRANSPARENT)
		var muted: bool = not g["played"] and not today
		r.add_child(_cell(_ink("D%d" % int(g["day"]), 16, muted, true), 56))
		r.add_child(_cell(_ink("VS" if home else "@", 16, muted), 28))
		var nm := _ink(_team_name(opp), 24, muted)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		r.add_child(nm)
		var res := ""
		var tag := ""
		if g["played"]:
			var mine := int(g["homeScore"] if home else g["awayScore"])
			var theirs := int(g["awayScore"] if home else g["homeScore"])
			res = "%s %d-%d%s" % ["W" if mine > theirs else "L", mine, theirs, (" OT" if int(g.get("ot", 0)) > 0 else "")]
			tag = "LIVE" if g.get("playedLive", false) else "SIM"
		elif today:
			res = "TODAY"
		r.add_child(_cell(_ink(tag, 16, true), 44))
		r.add_child(_cell(_ink(res, 16, muted, true), 128, HORIZONTAL_ALIGNMENT_RIGHT))
		col.add_child(_wrapped(r))
	vb.add_child(panel)
	if not Array(s.get("series", [])).is_empty():
		vb.add_child(_caps("PLAYOFFS"))
		var pp := _cream(12.0)
		var pcol := VBoxContainer.new()
		pcol.add_theme_constant_override("separation", 0)
		pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pp.add_child(pcol)
		var any := false
		for series in s["series"]:
			if series["highSeedId"] != Campaign.PLAYER and series["lowSeedId"] != Campaign.PLAYER:
				continue
			var round_ := "FINAL" if str(series["round"]) == "final" else "SEMI"
			var n := 0
			for g in series["games"]:
				n += 1
				any = true
				var high: bool = g["homeId"] == Campaign.PLAYER
				var mine := int(g["homeScore"] if high else g["awayScore"])
				var theirs := int(g["awayScore"] if high else g["homeScore"])
				var r := _row(52)
				r.add_child(_cell(_ink("%s %d" % [round_, n], 16, false, true), 84))
				var nm := _ink("%s %s" % ["VS" if high else "@", _team_name(g["awayId"] if high else g["homeId"])], 24)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				r.add_child(nm)
				r.add_child(_cell(_ink("%s %d-%d" % ["W" if mine > theirs else "L", mine, theirs], 16, false, true), 128, HORIZONTAL_ALIGNMENT_RIGHT))
				pcol.add_child(_wrapped(r))
			if series["winnerId"] == "":
				var nxt := _row(52, RetroTheme.c("gold"))
				nxt.add_child(_cell(_ink("%s %d" % [round_, n + 1], 16, false, true), 84))
				var opp := str(series["lowSeedId"] if series["highSeedId"] == Campaign.PLAYER else series["highSeedId"])
				var nm2 := _ink("VS " + _team_name(opp), 24)
				nm2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nxt.add_child(nm2)
				nxt.add_child(_cell(_ink("NEXT", 16, false, true), 128, HORIZONTAL_ALIGNMENT_RIGHT))
				pcol.add_child(_wrapped(nxt))
				any = true
		if not any:
			pcol.add_child(_ink("YOU MISSED THE PLAYOFFS", 16, true))
		vb.add_child(pp)


# ---- CARDS -----------------------------------------------------------------------


func _fill_cards() -> void:
	var vb := _list("CARDS")
	var subs := HBoxContainer.new()
	subs.name = "CardSubs"
	subs.add_theme_constant_override("separation", 12)
	subs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(subs)
	for sub in ["LOADOUT", "SHOP"]:
		var b := _tab_button(sub, sub == _card_sub, 16, 46.0)
		b.name = "Sub_" + sub
		b.custom_minimum_size.x = 170
		var sname: String = sub
		b.pressed.connect(func() -> void:
			_card_sub = sname
			refresh()
		)
		subs.add_child(b)
	if _card_sub == "LOADOUT":
		_fill_loadout(vb)
	else:
		_fill_shop(vb)


func _art(card: Dictionary, size_: Vector2, button := true) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = size_ + Vector2(6, 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow := ColorRect.new()
	shadow.color = RetroTheme.c("shadow")
	shadow.position = Vector2(6, 6)
	shadow.size = size_
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(shadow)
	var path := str(card.get("art", "res://assets/textures/cards/card_back.png"))
	if button:
		var b := TextureButton.new()
		b.texture_normal = load(path)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.size = size_
		b.focus_mode = Control.FOCUS_NONE
		holder.add_child(b)
		holder.set_meta("button", b)
	else:
		var t := TextureRect.new()
		t.texture = load(path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.size = size_
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
	return holder


func _fill_loadout(vb: VBoxContainer) -> void:
	var cd := App.cards_bucket(league_id)
	vb.add_child(_caps("EQUIPPED · TAP A SLOT TO PUT IT BACK"))
	var slots := HBoxContainer.new()
	slots.name = "Slots"
	slots.add_theme_constant_override("separation", 24)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(slots)
	for i in CardDefs.SLOTS:
		var cell := VBoxContainer.new()
		cell.name = "Slot_%d" % i
		cell.add_theme_constant_override("separation", 14)
		cell.alignment = BoxContainer.ALIGNMENT_BEGIN
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var id: Variant = cd["loadout"][i]
		var card := CardDefs.get_card(str(id)) if id != null else {}
		if card.is_empty():
			var empty := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(RetroTheme.SCENE_OUTLINE, 0.4)
			sb.border_color = CREAM
			sb.set_border_width_all(3)
			empty.add_theme_stylebox_override("panel", sb)
			empty.custom_minimum_size = Vector2(192, 256)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var e := _display("EMPTY", 16)
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.add_child(e)
			cell.add_child(empty)
			var sl := _caps("SLOT %d" % (i + 1))
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(sl)
		else:
			var art := _art(card, Vector2(192, 256))
			var slot: int = i
			(art.get_meta("button") as TextureButton).pressed.connect(func() -> void:
				App.unequip_card(slot, league_id)
				refresh()
			)
			cell.add_child(art)
			var nm := _caps(str(card.get("name", id)).to_upper())
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(nm)
		slots.add_child(cell)
	vb.add_child(_caps("SPARES · TAP TO EQUIP"))
	var inv: Dictionary = cd.get("inventory", {})
	if inv.is_empty():
		vb.add_child(_caps("NO SPARE CARDS · WIN HEATS OR VISIT THE SHOP", RetroTheme.c("muted") if RetroTheme.current() == RetroTheme.DARK else CREAM))
	var spares := HBoxContainer.new()
	spares.name = "Spares"
	spares.add_theme_constant_override("separation", 24)
	spares.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spares)
	for id in inv:
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var holder := _art(card, Vector2(120, 160))
		var cid := str(id)
		(holder.get_meta("button") as TextureButton).pressed.connect(func() -> void:
			for slot in CardDefs.SLOTS:
				if App.cards_bucket(league_id)["loadout"][slot] == null:
					App.equip_card(slot, cid, league_id)
					break
			refresh()
		)
		var badge := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = RetroTheme.SCENE_OUTLINE
		sb.set_content_margin_all(6)
		badge.add_theme_stylebox_override("panel", sb)
		badge.position = Vector2(120 - 16, -10)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(UiFont.label("x%d" % int(inv[id]), 16, CREAM))
		holder.add_child(badge)
		spares.add_child(holder)
	vb.add_child(_caps("ONE-TIME USE · A PLAYED CARD IS GONE FOR GOOD"))


func _fill_shop(vb: VBoxContainer) -> void:
	vb.add_child(_caps("%d COINS · CARDS BOUGHT HERE PLAY IN THE %s ONLY" % [App.league_coins(league_id), str(cfg.get("name", "LEAGUE")).to_upper()]))
	var cd := App.cards_bucket(league_id)
	for card in CardDefs.all():
		var panel := ShadowPanel.new(CREAM, 20.0)
		panel.name = "Shop_" + str(card["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		row.add_child(_art(card, Vector2(120, 160), false))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 12)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_display(str(card.get("name", "")).to_upper(), 16))
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = BLUE if str(card.get("rarity", "")) == "rare" else (RetroTheme.LIGHT["gold"] if str(card.get("rarity", "")) == "epic" else CREAM)
		sb.set_content_margin_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		chip.add_theme_stylebox_override("panel", sb)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(UiFont.label(str(card.get("rarity", "")).to_upper(), 16, RetroTheme.SCENE_OUTLINE, UiFont.body_bold()))
		head.add_child(chip)
		col.add_child(head)
		var blurb := RetroTheme.on_scene(UiFont.label(str(card.get("blurb", "")), 16, CREAM, UiFont.body())) as Label
		blurb.add_theme_constant_override("outline_size", 2)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(blurb)
		var foot := HBoxContainer.new()
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(foot)
		var owned_n := CardDefs.owned(cd, str(card["id"]))
		var spare_n := CardDefs.count(cd, str(card["id"]))
		var owned_txt := "OWNED %d" % owned_n
		if owned_n > spare_n:
			owned_txt += " · %d EQUIPPED" % (owned_n - spare_n)
		var ol := _caps(owned_txt)
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		foot.add_child(ol)
		var buy := ShadowCard.new(RetroTheme.LIGHT["gold"])
		buy.name = "Buy_" + str(card["id"])
		buy.text = "%d" % int(card.get("price", 0))
		buy.custom_minimum_size = Vector2(136 + ShadowStyle.OFFSET, 50 + ShadowStyle.OFFSET)
		buy.add_theme_font_override("font", UiFont.display())
		buy.add_theme_font_size_override("font_size", UiFont.snap(16))
		RetroTheme.on_scene(buy)
		buy.disabled = App.league_coins(league_id) < int(card.get("price", 0))
		var cid := str(card["id"])
		buy.pressed.connect(func() -> void:
			if App.try_buy_card(cid, league_id):
				refresh()
		)
		foot.add_child(buy)
		vb.add_child(panel)


# ---- STATS -----------------------------------------------------------------------


func _fill_stats() -> void:
	var vb := _list("STATS")
	var tot: Dictionary = doc["career"]["totals"]
	var highs: Dictionary = doc["career"]["highs"]
	var seasons: Array = doc["career"]["seasons"]
	vb.add_child(_caps("CAREER · %d SEASON%s" % [seasons.size() + 1, "" if seasons.size() == 0 else "S"]))
	var panel := _cream(24.0)
	panel.name = "Career"
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 28)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(grid)
	var best_finish := 0
	for summ in seasons:
		var f := int(summ["finish"])
		if f > 0 and (best_finish == 0 or f < best_finish):
			best_finish = f
	for spec in [["%d-%d" % [int(tot["wins"]), int(tot["losses"])], "RECORD"], [str(int(doc["career"]["championships"])), "TITLES"],
			[str(int(highs["points"])), "HIGH PTS"], [str(int(highs["swishes"])), "SWISHES"], [str(int(highs["streak"])), "BEST STREAK"],
			[TickerText.ordinal(best_finish) if best_finish > 0 else "-", "BEST FINISH"]]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 12)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(_ink(spec[0], 32, false, true))
		cell.add_child(_ink(spec[1], 16, true))
		grid.add_child(cell)
	vb.add_child(panel)
	vb.add_child(_caps("SEASONS"))
	var sp := _cream(12.0)
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 0)
	scol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(scol)
	for summ in seasons:
		var r := _row(48)
		r.add_child(_cell(_ink("S%d" % int(summ["year"]), 16, false, true), 48))
		r.add_child(_cell(_ink("%d-%d" % [int(summ["w"]), int(summ["l"])], 16, false, true), 96))
		var res := _ink("%s%s" % [TickerText.ordinal(int(summ["finish"])), _playoff_text(str(summ["playoffResult"]))], 16)
		res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(res)
		scol.add_child(r)
	var cur := _row(48)
	var s: Dictionary = doc["season"]
	cur.add_child(_cell(_ink("S%d" % int(doc.get("year", 1)), 16, false, true), 48))
	cur.add_child(_cell(_ink("%d-%d" % _season_record(s), 16, false, true), 96))
	var ip := _ink("IN PROGRESS" if s["phase"] != Season.PHASE_DONE else "DONE", 16, true)
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur.add_child(ip)
	scol.add_child(cur)
	vb.add_child(sp)
	vb.add_child(_caps("BEST HEATS"))
	var hp := _cream(12.0)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 0)
	hcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.add_child(hcol)
	var games := SaveService.live_games(league_id, 5)
	if games.is_empty():
		hcol.add_child(_ink("NO HEATS YET", 16, true))
	for i in games.size():
		var g: Dictionary = games[i]
		var r := _row(48)
		r.add_child(_cell(_ink(str(i + 1), 16, false, true), 24))
		r.add_child(_cell(_ink("%d-%d %s" % [int(g["playerScore"]), int(g["oppScore"]), "W" if g.get("won", false) else "L"], 16, false, true), 132))
		var vs := _ink("VS " + _team_name(str(g.get("opponentId", ""))), 16)
		vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vs.clip_text = true
		r.add_child(vs)
		r.add_child(_ink("%d SW" % int(g.get("swishes", 0)), 16, true))
		hcol.add_child(r)
	vb.add_child(hp)
	var arena := CosmeticLibrary.get_arena(str(cfg.get("arena", cfg.get("location", "cage"))))
	vb.add_child(_caps("TIME TRIAL · %s" % (str(arena.display_name).to_upper() if arena != null else str(cfg.get("location", "")).to_upper())))
	var tp := _cream(12.0)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 0)
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.add_child(tcol)
	var top := SaveService.top_scores(5, str(cfg.get("location", "cage")))
	if top.is_empty():
		tcol.add_child(_ink("NO TIME TRIALS YET", 16, true))
	for i in top.size():
		var d: Dictionary = top[i]
		var r := _row(48)
		r.add_child(_cell(_ink(str(i + 1), 16, false, true), 24))
		r.add_child(_cell(_ink("%d PTS" % int(d["score"]), 16, false, true), 132))
		var sw := _ink("%d SWISHES · STREAK %d" % [int(d.get("swishes", 0)), int(d.get("bestStreak", 0))], 16, true)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(sw)
		tcol.add_child(r)
	vb.add_child(tp)


func _season_record(s: Dictionary) -> Array:
	var w := 0
	var l := 0
	for g in s.get("schedule", []):
		if g["played"] and (g["homeId"] == Campaign.PLAYER or g["awayId"] == Campaign.PLAYER):
			if Standings.winner_of(g) == Campaign.PLAYER:
				w += 1
			else:
				l += 1
	return [w, l]


func _playoff_text(result: String) -> String:
	match result:
		"champion":
			return " · CHAMPION"
		"runner_up":
			return " · RUNNER-UP"
		"semifinal":
			return " · SEMIFINALIST"
		_:
			return " · MISSED THE PLAYOFFS"
