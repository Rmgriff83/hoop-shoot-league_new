class_name LeagueContext
extends Control
## The league, in context on the home page (docs/HOME.md, design "Home
## League Context v2"): fills the home's card area when LEAGUE is tapped.
## A tab row — "<" back, MATCH · TABLE · SCHED · CARDS · STATS — over one
## clip in which the panes slide sideways, with a fade at the bottom while a
## pane still scrolls. Everything the old full-screen hub did lives here:
## the next match (the opponent card with PLAY, playoffs, advance, next
## season — every game is played live, there is no sim), the table /
## bracket, the schedule, this league's cards (spares + shop, this league's
## coins; the equipped slots float above the panel on the home) and the
## career / best matches / time-trial records, all on see-through panels
## in cream. Built for one league from App.league_cfg / league_doc.
## `closed` = "<"; `changed` = the doc moved (the home refreshes its zone
## line, ticker and floating layer); `tab_changed` = a tab was picked.

signal closed
signal changed
signal tab_changed(tab: String)

const TABS := ["HEAT", "TABLE", "SCHED", "CARDS", "STATS"]
const TAB_LABELS := {"HEAT": "MATCH"}
const PINE := Color("#3E7C4F")
const HI := Color("#FFCE8A")
const BLUE := Color("#7FAEC6")
const CREAM := RetroTheme.SCENE_TEXT
const MUTED := RetroTheme.SCENE_MUTED
const DIM := RetroTheme.SCENE_DIM
const INK := RetroTheme.SCENE_OUTLINE
const TAB_H := 58.0
const SLIDE_S := 0.3
const FADE_H := 88.0
const PANEL_TINT := 0.14

var league_id := ""
var cfg: Dictionary = {}
var doc: Dictionary = {}

var _tab := "HEAT"
var _card_sub := "LOADOUT"
var _tab_row: HBoxContainer
var _clip: Control
var _fade: TextureRect
var _panes: Dictionary = {}
var _switching := false


func setup(id: String, p_tab := "HEAT", p_sub := "LOADOUT") -> void:
	league_id = id
	_tab = p_tab
	_card_sub = p_sub
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
	_fade = TextureRect.new()
	_fade.name = "Fade"
	var grad := Gradient.new()
	grad.set_color(0, Color(RetroTheme.DARK["bg"], 0.0))
	grad.set_color(1, Color(RetroTheme.DARK["bg"], 0.92))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	_fade.texture = gt
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_fade.offset_top = -FADE_H
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	_clip.add_child(_fade)
	_build_tabs()
	_fill_all()


## The doc moved (a purchase, an equip, a season step): re-read and rebuild the panes.
func refresh() -> void:
	doc = App.league_doc(league_id)
	for tab in TABS:
		for c in _list(tab).get_children():
			_list(tab).remove_child(c)
			c.free()
	_fill_all()
	changed.emit()


func _process(_dt: float) -> void:
	# The bottom fade shows only while the current pane can still scroll.
	var sc: ScrollContainer = _panes[_tab]
	var bar := sc.get_v_scroll_bar()
	_fade.visible = bar.max_value - bar.value - bar.page > 2.0


# ---- chrome ----------------------------------------------------------------------


func _build_tabs() -> void:
	if _tab_row != null:
		_tab_row.queue_free()
	_tab_row = HBoxContainer.new()
	_tab_row.name = "Tabs"
	_tab_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tab_row.offset_bottom = TAB_H
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
		var b := _tab_button(str(TAB_LABELS.get(tab, tab)), tab == _tab, 16)
		b.name = "Tab_" + tab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: String = tab
		b.pressed.connect(func() -> void: _show_tab(t))
		_tab_row.add_child(b)


## Active: a solid face in the palette's panel colour (cream with tan dots
## on the cream page, the dark panel with muted dots in dark mode) with an
## orange dithered shadow and the palette's text. Inactive: see-through
## cream, cream text with the ink outline.
func _tab_button(text: String, active: bool, size_: int, height := 52.0) -> Button:
	var b: ShadowCard
	if active:
		var dark := RetroTheme.current() == RetroTheme.DARK
		b = ShadowCard.solid(RetroTheme.c("panel"), Color(RetroTheme.c("muted"), 0.35) if dark else RetroTheme.TAN, RetroTheme.c("orange"))
		b.color = CREAM if dark else RetroTheme.c("panel")
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The solid face is drawn over the button's own text, so the label is a child.
		var l := UiFont.label(text, size_, RetroTheme.c("text"))
		l.name = "Label"
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.offset_right = -ShadowStyle.OFFSET
		l.offset_bottom = -ShadowStyle.OFFSET
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
	else:
		b = ShadowCard.new(CREAM)
		RetroTheme.on_scene(b)
		b.add_theme_font_override("font", UiFont.display())
		b.add_theme_font_size_override("font_size", UiFont.snap(size_))
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


func card_sub() -> String:
	return _card_sub


## The home's loadout float tapped: land on CARDS · LOADOUT.
func go_loadout() -> void:
	if _card_sub != "LOADOUT":
		_card_sub = "LOADOUT"
		refresh()
	_show_tab("CARDS")


## Slide the current pane out and the next one in (the design's translateX).
func _show_tab(tab: String) -> void:
	if tab == _tab or _switching or not _panes.has(tab):
		return
	var dir := 1 if TABS.find(tab) > TABS.find(_tab) else -1
	var old: ScrollContainer = _panes[_tab]
	var new_: ScrollContainer = _panes[tab]
	_tab = tab
	_build_tabs()
	tab_changed.emit(tab)
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
	var l := _text(text, 16, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", 6)
	return l


func _display(text: String, size_: int, color := CREAM) -> Label:
	return _text(text, size_, color, true)


## Text over the court: the body-bold face (or the display face), cream with
## the ink outline; `color` for the muted / dim / highlight tones.
func _text(text: String, size_ := 16, color := CREAM, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


## Body copy (the bio, a blurb): the regular face, a thinner outline, wrapped.
func _body(text: String) -> Label:
	var l := RetroTheme.on_scene(UiFont.label(text, 16, CREAM, UiFont.body())) as Label
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_constant_override("line_spacing", 8)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A see-through cream panel (the table, the lists) at the list tint.
func _panel(pad_v := 16.0, pad_h := 24.0, tint := PANEL_TINT) -> ShadowPanel:
	return ShadowPanel.new(CREAM, pad_v, tint, pad_h)


## A row inside a panel, optionally highlighted (the band runs 12 px into the padding).
func _row(height: float, fill := Color.TRANSPARENT, sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, height)
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill.a > 0.0:
		var bg := StyleBoxFlat.new()
		bg.bg_color = fill
		bg.expand_margin_left = 12
		bg.expand_margin_right = 12
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
	return LeagueSummary.team_name(id)


func _vcol(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _hrow(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


# ---- fill ------------------------------------------------------------------------


func _fill_all() -> void:
	_fill_heat()
	_fill_table()
	_fill_sched()
	_fill_cards()
	_fill_stats()


func _season_meta() -> Dictionary:
	var s: Dictionary = doc["season"]
	return {"s": s, "year": LeagueSummary.year_of(doc), "phase": str(s["phase"]), "day": int(s.get("currentDay", 1))}


# ---- MATCH -----------------------------------------------------------------------


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
		vb.add_child(_caps("YOU FINISHED %s · %s" % [TickerText.ordinal(int(summ["finish"])), LeagueSummary.playoff_long(str(summ["playoffResult"]))]))
		var nxt := ModeCards.text_card("START SEASON %d" % (m["year"] + 1), "NEW SCHEDULE · SAME LEAGUE", RetroTheme.c("orange"), 24)
		nxt.name = "NextSeason"
		nxt.custom_minimum_size = Vector2(0, 116)
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
		var adv := ModeCards.text_card("ADVANCE", "PLAY OUT THE BRACKET", RetroTheme.c("teal"), 24)
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
	var line := ""
	if m["phase"] == Season.PHASE_PLAYOFFS:
		var mine := Season.player_series(s, Campaign.PLAYER)
		var wl := LeagueSummary.series_record(mine)
		line = "%s · GAME %d · %s" % [LeagueSummary.series_label(s, mine), wl[0] + wl[1] + 1, "HOME" if mine["highSeedId"] == Campaign.PLAYER else "AWAY"]
	else:
		var g := Season.player_game_on(s, m["day"], Campaign.PLAYER)
		var home: bool = not g.is_empty() and g["homeId"] == Campaign.PLAYER
		line = "DAY %d · %s" % [m["day"], "HOME" if home else "AWAY"]
	vb.add_child(_shooter_card(LeagueData.shooter(opp_id), line))


## The opponent card: pine, see-through — the match line over the name,
## nickname over hometown, ACC / ARC segments and PACE beside the PLAY
## button (the equipped cards as chips on its corner), then the bio.
func _shooter_card(sh: Dictionary, line: String) -> Control:
	var card := ShadowPanel.new(PINE, 14.0, 0.3, 22.0)
	card.name = "Opponent"
	var vb := _vcol(14)
	card.add_child(vb)
	var top := _hrow(16)
	vb.add_child(top)
	var names := _vcol(12)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	names.add_child(_text(line))
	var nm := _display(str(sh.get("name", "?")).to_upper(), 32)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	names.add_child(nm)
	var tags := _vcol(12)
	tags.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_child(tags)
	var nick := _display("\"%s\"" % str(sh.get("nickname", "")).to_upper(), 16, HI)
	nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tags.add_child(nick)
	var town := _text(str(sh.get("hometown", "")).to_upper())
	town.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tags.add_child(town)
	var mid := _hrow(20)
	vb.add_child(mid)
	var ratings := _vcol(14)
	ratings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ratings.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(ratings)
	var r: Dictionary = sh.get("ratings", {})
	for spec in [["ACC", float(r.get("accuracy", 0.5))], ["ARC", float(r.get("swishRate", 0.5))]]:
		var rl := _hrow(12)
		rl.add_child(_cell(_text(spec[0]), 84))
		var segs := _hrow(5)
		var n := clampi(roundi(float(spec[1]) * 5.0), 0, 5)
		for i in 5:
			var seg := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = HI if i < n else Color(INK, 0.55)
			sb.border_color = CREAM
			sb.set_border_width_all(2)
			seg.add_theme_stylebox_override("panel", sb)
			seg.custom_minimum_size = Vector2(28, 16)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			segs.add_child(seg)
		rl.add_child(segs)
		ratings.add_child(rl)
	var pace := _hrow(12)
	pace.add_child(_cell(_text("PACE"), 84))
	pace.add_child(_display("%.1f S" % float(r.get("pace", 4.0)), 16))
	ratings.add_child(pace)
	var play := ShadowCard.new(RetroTheme.c("orange"))
	play.name = "PlayHeat"
	play.tint = 0.32
	play.custom_minimum_size = Vector2(232 + ShadowStyle.OFFSET, 104 + ShadowStyle.OFFSET)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(func() -> void: App.start_league_heat())
	var pm := MarginContainer.new()
	pm.set_anchors_preset(Control.PRESET_FULL_RECT)
	pm.add_theme_constant_override("margin_left", 18)
	pm.add_theme_constant_override("margin_right", 18 + int(ShadowStyle.OFFSET))
	pm.add_theme_constant_override("margin_bottom", int(ShadowStyle.OFFSET))
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play.add_child(pm)
	var pr := _hrow(12)
	pm.add_child(pr)
	var pl := _display("PLAY", 32)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(pl)
	var pc := _display(">", 24)
	pc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(pc)
	var equipped := App.loadout_hand(league_id)
	if not equipped.is_empty():
		var chips := ModeCards.chip_row(equipped, false)
		chips.name = "PlayChips"
		var w := equipped.size() * ModeCards.CHIP + (equipped.size() - 1) * ModeCards.CHIP_GAP
		chips.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		chips.offset_right = -(14 + ShadowStyle.OFFSET)
		chips.offset_left = chips.offset_right - w
		chips.offset_bottom = 20 - ShadowStyle.OFFSET
		chips.offset_top = chips.offset_bottom - ModeCards.CHIP
		play.add_child(chips)
	mid.add_child(play)
	var bio := _body(str(sh.get("bio", "")))
	vb.add_child(bio)
	return card


# ---- TABLE -----------------------------------------------------------------------


func _fill_table() -> void:
	var vb := _list("TABLE")
	var m := _season_meta()
	var s: Dictionary = m["s"]
	var spots := int(s.get("playoffTeams", 4))
	if m["phase"] == Season.PHASE_REGULAR or Array(s.get("series", [])).is_empty():
		vb.add_child(_caps("REGULAR SEASON · AFTER DAY %d" % maxi(int(m["day"]) - 1, 0)))
		var panel := _panel(16.0, 24.0)
		panel.name = "Standings"
		vb.add_child(panel)
		var col := _vcol(0)
		panel.add_child(col)
		var head := _row(44, Color.TRANSPARENT, 0)
		for spec in [["#", 48], ["SHOOTER", 0], ["W", 48], ["L", 48], ["GB", 72], ["STRK", 88]]:
			var l := _cell(_text(spec[0], 16, MUTED), spec[1])
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
			var r := _row(56, RetroTheme.c("orange") if mine else Color.TRANSPARENT, 0)
			r.name = "Row_%d" % (i + 1)
			r.add_child(_cell(_display(str(i + 1), 16), 48))
			var nm := _cell(_text(_team_name(id), 24), 0)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.clip_text = true
			r.add_child(nm)
			r.add_child(_cell(_display(str(row["w"]), 16), 48))
			r.add_child(_cell(_display(str(row["l"]), 16), 48))
			r.add_child(_cell(_display("%.1f" % Standings.games_behind(leader, row) if i > 0 else "-", 16), 72))
			var streak := Standings.current_streak(id, s["schedule"])
			var strk := _hrow(8)
			strk.custom_minimum_size = Vector2(88, 0)
			var sq := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = (RetroTheme.c("orange") if streak.get("type", "") == "W" else BLUE) if not streak.is_empty() else Color.TRANSPARENT
			sb.border_color = INK
			sb.set_border_width_all(3)
			sq.add_theme_stylebox_override("panel", sb)
			sq.custom_minimum_size = Vector2(14, 14)
			sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strk.add_child(sq)
			strk.add_child(_cell(_display("%s%d" % [streak["type"], int(streak["count"])] if not streak.is_empty() else "-", 16), 40))
			r.add_child(strk)
			col.add_child(_wrapped(r))
			if i == spots - 1 and i < table.size() - 1:
				var cut := _hrow(12)
				cut.custom_minimum_size = Vector2(0, 36)
				cut.add_child(_rule())
				cut.add_child(_text("PLAYOFF LINE"))
				cut.add_child(_rule())
				col.add_child(cut)
		vb.add_child(_caps("TOP %d MAKE THE PLAYOFFS · SEMIS BEST OF %d · FINAL BEST OF %d" % [spots, int(s.get("semisBestOf", 3)), int(s.get("finalBestOf", 5))]))
		return
	# Playoffs: the bracket — the semis, a connector, the final.
	vb.add_child(_caps("PLAYOFFS · SEASON %d" % m["year"]))
	var grid := _hrow(0)
	vb.add_child(grid)
	var semis := _vcol(28)
	semis.custom_minimum_size = Vector2(360, 0)
	grid.add_child(semis)
	var n_semi := 0
	for series in s["series"]:
		if series["round"] != "semifinal":
			continue
		n_semi += 1
		var done: bool = series["winnerId"] != ""
		var g := int(series["highWins"]) + int(series["lowWins"])
		var block := _vcol(12)
		block.add_child(_text("SEMI %d · BO%d · %s" % [n_semi, int(series["bestOf"]), "DONE" if done else "GAME %d" % (g + 1)]))
		block.add_child(_series_panel(series))
		semis.add_child(block)
	var conn := Bracket.new()
	conn.custom_minimum_size = Vector2(36, 0)
	conn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_child(conn)
	var fin := _vcol(12)
	fin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fin.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_child(fin)
	fin.add_child(_text("FINAL · BO%d" % int(s.get("finalBestOf", 5))))
	var final_ := Playoffs.find(s["series"], "final")
	if final_.is_empty():
		var panel := _panel(8.0, 14.0)
		var col := _vcol(0)
		panel.add_child(col)
		for series in s["series"]:
			if series["round"] != "semifinal":
				continue
			var r1 := _row(52)
			var w := str(series["winnerId"])
			r1.add_child(_cell(_display(_seed_of(w) if w != "" else "?", 16, CREAM if w != "" else MUTED), 24))
			var who := _text(_team_name(w) if w != "" else "%s VS %s WINNER" % [_seed_of(str(series["highSeedId"])), _seed_of(str(series["lowSeedId"]))],
				16, CREAM if w != "" else MUTED)
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			who.clip_text = true
			r1.add_child(who)
			col.add_child(r1)
		fin.add_child(panel)
	else:
		fin.add_child(_series_panel(final_, 16))
	if str(s.get("championId", "")) != "":
		vb.add_child(_display("CHAMPION: %s" % _team_name(str(s["championId"])), 24, HI))
	vb.add_child(_caps("SEEDS FROM THE FINAL TABLE · 1 V 4 · 2 V 3"))


## A shooter's regular-season seed as text ("" when unknown).
func _seed_of(id: String) -> String:
	var s: Dictionary = doc["season"]
	for row in Standings.table(LeagueData.team_ids(cfg), s["schedule"], int(s["seed"])):
		if row["teamId"] == id:
			return str(int(row["seed"]))
	return ""


func _series_panel(series: Dictionary, name_size := 24) -> Control:
	var panel := _panel(8.0, 16.0)
	var col := _vcol(0)
	panel.add_child(col)
	for side in [["highSeedId", "highWins"], ["lowSeedId", "lowWins"]]:
		var id := str(series[side[0]])
		var r := _row(52, RetroTheme.c("orange") if id == Campaign.PLAYER else Color.TRANSPARENT)
		r.add_child(_cell(_display(_seed_of(id), 16), 24))
		var nm := _text(_team_name(id), name_size)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		r.add_child(nm)
		r.add_child(_cell(_display(str(int(series[side[1]])), 24), 40, HORIZONTAL_ALIGNMENT_RIGHT))
		col.add_child(_wrapped(r))
	return panel


func _rule() -> Control:
	return ModeCards.DashedRule.new(3.0)


## The bracket's connector: a cream bracket (top, right, bottom) with an ink shadow.
class Bracket extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var h := minf(220.0, size.y)
		var top := (size.y - h) / 2.0
		for spec in [[Vector2(3, 3), RetroTheme.SCENE_OUTLINE], [Vector2.ZERO, RetroTheme.SCENE_TEXT]]:
			var o: Vector2 = spec[0]
			var c: Color = spec[1]
			draw_rect(Rect2(o + Vector2(0, top), Vector2(size.x, 3)), c)
			draw_rect(Rect2(o + Vector2(size.x - 3, top), Vector2(3, h)), c)
			draw_rect(Rect2(o + Vector2(0, top + h - 3), Vector2(size.x, 3)), c)


# ---- SCHED -----------------------------------------------------------------------


func _fill_sched() -> void:
	var vb := _list("SCHED")
	var m := _season_meta()
	var s: Dictionary = m["s"]
	var rec := LeagueSummary.record(s)
	vb.add_child(_caps("%d DAYS · %d-%d SO FAR" % [Season.days(s), rec[0], rec[1]]))
	var panel := _panel(10.0, 24.0)
	panel.name = "Schedule"
	var col := _vcol(0)
	panel.add_child(col)
	for g in s["schedule"]:
		if g["homeId"] != Campaign.PLAYER and g["awayId"] != Campaign.PLAYER:
			continue
		var home: bool = g["homeId"] == Campaign.PLAYER
		var opp: String = g["awayId"] if home else g["homeId"]
		var today: bool = int(g["day"]) == int(m["day"]) and m["phase"] == Season.PHASE_REGULAR
		var r := _row(52, RetroTheme.c("gold") if today else Color.TRANSPARENT)
		var tone: Color = CREAM if (g["played"] or today) else DIM
		r.add_child(_cell(_display("D%d" % int(g["day"]), 16, tone), 56))
		r.add_child(_cell(_text("VS" if home else "@", 16, tone), 28))
		var nm := _text(_team_name(opp), 24, tone)
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
		r.add_child(_cell(_text(tag, 16, MUTED), 44))
		r.add_child(_cell(_display(res, 16, tone), 128, HORIZONTAL_ALIGNMENT_RIGHT))
		col.add_child(_wrapped(r))
	vb.add_child(panel)
	if not Array(s.get("series", [])).is_empty():
		vb.add_child(_caps("PLAYOFFS"))
		var pp := _panel(10.0, 24.0)
		var pcol := _vcol(0)
		pp.add_child(pcol)
		var any := false
		for series in s["series"]:
			if series["highSeedId"] != Campaign.PLAYER and series["lowSeedId"] != Campaign.PLAYER:
				continue
			var round_ := LeagueSummary.round_name(series)
			var n := 0
			for g in series["games"]:
				n += 1
				any = true
				var high: bool = g["homeId"] == Campaign.PLAYER
				var mine := int(g["homeScore"] if high else g["awayScore"])
				var theirs := int(g["awayScore"] if high else g["homeScore"])
				var r := _row(52)
				r.add_child(_cell(_display("%s %d" % [round_, n], 16), 84))
				var nm := _text("%s %s" % ["VS" if high else "@", _team_name(g["awayId"] if high else g["homeId"])], 24)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nm.clip_text = true
				r.add_child(nm)
				r.add_child(_cell(_display("%s %d-%d" % ["W" if mine > theirs else "L", mine, theirs], 16), 128, HORIZONTAL_ALIGNMENT_RIGHT))
				pcol.add_child(_wrapped(r))
			if series["winnerId"] == "":
				var nxt := _row(52, RetroTheme.c("gold"))
				nxt.add_child(_cell(_display("%s %d" % [round_, n + 1], 16), 84))
				var high2: bool = series["highSeedId"] == Campaign.PLAYER
				var nm2 := _text("%s %s" % ["VS" if high2 else "@", _team_name(LeagueSummary.opponent_in(series))], 24)
				nm2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nm2.clip_text = true
				nxt.add_child(nm2)
				nxt.add_child(_cell(_display("NEXT", 16), 128, HORIZONTAL_ALIGNMENT_RIGHT))
				pcol.add_child(_wrapped(nxt))
				any = true
		if not any:
			pcol.add_child(_text("YOU MISSED THE PLAYOFFS", 16, MUTED))
		vb.add_child(pp)


# ---- CARDS -----------------------------------------------------------------------


func _fill_cards() -> void:
	var vb := _list("CARDS")
	var subs := _hrow(12)
	subs.name = "CardSubs"
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


## The spares (the equipped slots float above the panel on the home page):
## tap one to put it in the first empty slot.
func _fill_loadout(vb: VBoxContainer) -> void:
	var cd := App.cards_bucket(league_id)
	var inv: Dictionary = cd.get("inventory", {})
	var free_slots := 0
	for slot in CardDefs.SLOTS:
		if cd["loadout"][slot] == null:
			free_slots += 1
	if inv.is_empty():
		vb.add_child(_caps("NO SPARE CARDS · WIN MATCHES OR VISIT THE SHOP"))
	else:
		vb.add_child(_caps("SPARES · TAP ONE TO EQUIP IT" if free_slots > 0 else "SPARES · THE LOADOUT IS FULL"))
	var spares := _hrow(24)
	spares.name = "Spares"
	vb.add_child(spares)
	for id in inv:
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var holder := ModeCards.art(card, Vector2(120, 160), 6.0, true)
		holder.name = "Spare_" + str(id)
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
	vb.add_child(_caps("ONE-TIME USE · A PLAYED CARD IS GONE FOR GOOD"))


func _fill_shop(vb: VBoxContainer) -> void:
	vb.add_child(_caps("%d COINS · CARDS BOUGHT HERE PLAY IN THE %s ONLY" % [App.league_coins(league_id), str(cfg.get("name", "LEAGUE")).to_upper()]))
	var cd := App.cards_bucket(league_id)
	for card in CardDefs.all():
		var panel := ShadowPanel.new(CREAM, 20.0, 0.12)
		panel.name = "Shop_" + str(card["id"])
		var row := _hrow(20)
		panel.add_child(row)
		row.add_child(ModeCards.art(card, Vector2(120, 160)))
		var col := _vcol(12)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var head := _hrow(12)
		head.add_child(_display(str(card.get("name", "")).to_upper(), 16))
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = BLUE if str(card.get("rarity", "")) == "rare" else (RetroTheme.c("gold") if str(card.get("rarity", "")) == "epic" else CREAM)
		sb.set_content_margin_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		chip.add_theme_stylebox_override("panel", sb)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(UiFont.label(str(card.get("rarity", "")).to_upper(), 16, INK, UiFont.body_bold()))
		head.add_child(chip)
		col.add_child(head)
		col.add_child(_body(str(card.get("blurb", ""))))
		var foot := _hrow(12)
		foot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		foot.alignment = BoxContainer.ALIGNMENT_END
		col.add_child(foot)
		var owned_n := CardDefs.owned(cd, str(card["id"]))
		var spare_n := CardDefs.count(cd, str(card["id"]))
		var owned_txt := "OWNED %d" % owned_n
		if owned_n > spare_n:
			owned_txt += " · %d EQUIPPED" % (owned_n - spare_n)
		var ol := _text(owned_txt)
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		foot.add_child(ol)
		var buy := ShadowCard.new(RetroTheme.c("gold"))
		buy.name = "Buy_" + str(card["id"])
		buy.custom_minimum_size = Vector2(136 + ShadowStyle.OFFSET, 50 + ShadowStyle.OFFSET)
		buy.disabled = App.league_coins(league_id) < int(card.get("price", 0))
		var bm := MarginContainer.new()
		bm.set_anchors_preset(Control.PRESET_FULL_RECT)
		bm.add_theme_constant_override("margin_right", int(ShadowStyle.OFFSET))
		bm.add_theme_constant_override("margin_bottom", int(ShadowStyle.OFFSET))
		bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		buy.add_child(bm)
		var br := _hrow(10)
		br.alignment = BoxContainer.ALIGNMENT_CENTER
		bm.add_child(br)
		var coin := PixelIcon.new("icon_coin", Vector2(16, 16))
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		br.add_child(coin)
		var price := _display("%d" % int(card.get("price", 0)), 16)
		price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		br.add_child(price)
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
	var panel := _panel(24.0, 24.0)
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
		var cell := _vcol(12)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(_display(spec[0], 32))
		cell.add_child(_text(spec[1], 16, MUTED))
		grid.add_child(cell)
	vb.add_child(panel)
	vb.add_child(_caps("SEASONS"))
	var sp := _panel(8.0, 24.0)
	var scol := _vcol(0)
	sp.add_child(scol)
	for summ in seasons:
		var r := _row(48)
		r.add_child(_cell(_display("S%d" % int(summ["year"]), 16), 48))
		r.add_child(_cell(_display("%d-%d" % [int(summ["w"]), int(summ["l"])], 16), 96))
		var res := _text("%s · %s" % [TickerText.ordinal(int(summ["finish"])), LeagueSummary.playoff_long(str(summ["playoffResult"]))])
		res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		res.clip_text = true
		r.add_child(res)
		scol.add_child(r)
	var cur := _row(48)
	var s: Dictionary = doc["season"]
	cur.add_child(_cell(_display("S%d" % LeagueSummary.year_of(doc), 16), 48))
	cur.add_child(_cell(_display("%d-%d" % LeagueSummary.record(s), 16), 96))
	var ip := _text("IN PROGRESS" if s["phase"] != Season.PHASE_DONE else "DONE", 16, MUTED)
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur.add_child(ip)
	scol.add_child(cur)
	vb.add_child(sp)
	vb.add_child(_caps("BEST MATCHES"))
	var hp := _panel(8.0, 24.0)
	var hcol := _vcol(0)
	hp.add_child(hcol)
	var games := SaveService.live_games(league_id, 5)
	if games.is_empty():
		hcol.add_child(_text("NO MATCHES YET", 16, MUTED))
	for i in games.size():
		var g: Dictionary = games[i]
		var r := _row(48)
		r.add_child(_cell(_display(str(i + 1), 16), 24))
		r.add_child(_cell(_display("%d-%d %s" % [int(g["playerScore"]), int(g["oppScore"]), "W" if g.get("won", false) else "L"], 16), 132))
		var vs := _text("VS " + _team_name(str(g.get("opponentId", ""))))
		vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vs.clip_text = true
		r.add_child(vs)
		r.add_child(_text("%d SW" % int(g.get("swishes", 0)), 16, MUTED))
		hcol.add_child(r)
	vb.add_child(hp)
	var arena := CosmeticLibrary.get_arena(str(cfg.get("arena", cfg.get("location", "cage"))))
	vb.add_child(_caps("TIME TRIAL · %s" % (str(arena.display_name).to_upper() if arena != null else str(cfg.get("location", "")).to_upper())))
	var tp := _panel(8.0, 24.0)
	var tcol := _vcol(0)
	tp.add_child(tcol)
	var top := SaveService.top_scores(5, str(cfg.get("location", "cage")))
	if top.is_empty():
		tcol.add_child(_text("NO TIME TRIALS YET", 16, MUTED))
	for i in top.size():
		var d: Dictionary = top[i]
		var r := _row(48)
		r.add_child(_cell(_display(str(i + 1), 16), 24))
		r.add_child(_cell(_display("%d PTS" % int(d["score"]), 16), 132))
		var sw := _text("%d SWISHES · STREAK %d" % [int(d.get("swishes", 0)), int(d.get("bestStreak", 0))], 16, MUTED)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(sw)
		tcol.add_child(r)
	vb.add_child(tp)
