class_name LeagueContext
extends Control
## The league, in context on the home page (docs/HOME.md, design "Home
## League Context v2", reworked 2026-10-30): fills the home's card area when
## LEAGUE is tapped. A tab row — MATCH · TABLE · SCHED · CARDS · STATS, a
## gold dot pulsing on MATCH while a game waits (BACK TO HOME lives on the
## home now, under the season chip) — over one clip in which the panes slide
## sideways, with a fade at the bottom while a pane still scrolls. MATCH:
## the opponent card (their record, ratings, PLAY with its shine, the cards
## they hold for the game) or the season-over card (the champion, your
## titles and numbers, START SEASON, your playoff run); TABLE: the standings
## or the bracket as a tree (the final over the semis); SCHED: every game;
## CARDS: this league's shop (ask → CONFIRM → +1 ADDED, the card flying into
## YOUR CARDS on the home); STATS: career, seasons, best matches, time
## trials — all on see-through panels in cream. Built for one league from
## App.league_cfg / league_doc. `changed` = the doc moved (the home refreshes
## its zone line, ticker and floating layer); `tab_changed` = a tab was
## picked; `card_bought(id, art_rect)` = a shop buy went through (the art's
## global rect, where the home's flight starts).

signal changed
signal tab_changed(tab: String)
signal new_season_requested   # START SEASON on the MATCH pane: the title rolls it and shows the NEW SEASON page (design 39d)
signal card_bought(id: String, from: Rect2)

const TABS := ["HEAT", "TABLE", "SCHED", "CARDS", "STATS"]
const TAB_LABELS := {"HEAT": "MATCH"}
const PINE := Color("#3E7C4F")
const HI := Color("#FFE45C")
const BLUE := Color("#7FAEC6")
const CREAM := RetroTheme.SCENE_TEXT
const MUTED := RetroTheme.SCENE_MUTED
const DIM := RetroTheme.SCENE_DIM
const INK := RetroTheme.SCENE_OUTLINE
const TAB_H := 72.0
const TAB_TOP := 14.0
const TAB_ROW := 92.0        # the tab row's box (14 above the tabs, room for their shadow)
const PANE_GAP := 16.0
const SLIDE_S := 0.3
const ASK_S := 4.0           # a buy's CONFIRM waits this long, then drops back
const ADDED_S := 1.6         # +1 ADDED shows this long
const FADE_H := 88.0
const PANEL_TINT := 0.24

var league_id := ""
var cfg: Dictionary = {}
var doc: Dictionary = {}

var _tab := "HEAT"
var _tab_row: HBoxContainer
var _tab_dot: Control
var _clock := 0.0
var _buy: Dictionary = {}   # card id → {state: "ask" | "done", until: _clock deadline}
var _clip: Control
var _fade: TextureRect
var _panes: Dictionary = {}
var _switching := false


func setup(id: String, p_tab := "HEAT") -> void:
	league_id = id
	_tab = p_tab
	cfg = App.league_cfg(id)
	doc = App.league_doc(id)
	UiLayout.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = Control.new()
	_clip.name = "Panes"
	UiLayout.full_rect(_clip)
	_clip.offset_top = TAB_ROW + PANE_GAP
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
## The old rows are queued, not freed: refresh() runs from inside their own
## buttons' `pressed` (START SEASON, ADVANCE, buy, equip), and freeing the
## emitter mid-signal aborted the rebuild — the MATCH pane came back blank
## after a season rollover until the league was re-entered (2026-10-03).
func refresh() -> void:
	doc = App.league_doc(league_id)
	for tab in TABS:
		for c in _list(tab).get_children():
			_list(tab).remove_child(c)
			c.queue_free()
	_fill_all()
	_build_tabs()   # the MATCH dot follows the season (a new season's first game)
	changed.emit()


func _process(dt: float) -> void:
	# The bottom fade shows only while the current pane can still scroll.
	var sc: ScrollContainer = _panes[_tab]
	var bar := sc.get_v_scroll_bar()
	_fade.visible = bar.max_value - bar.value - bar.page > 2.0
	_clock += dt
	if _tab_dot != null and is_instance_valid(_tab_dot):
		_tab_dot.scale = Vector2.ONE * CssEase.tab_dot(_clock)
	for id in _buy.keys():
		if _clock >= float(_buy[id]["until"]):
			_set_buy(id, "idle")


# ---- chrome ----------------------------------------------------------------------


func _build_tabs() -> void:
	if _tab_row != null:
		_tab_row.queue_free()
	_tab_row = HBoxContainer.new()
	_tab_row.name = "Tabs"
	_tab_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tab_row.offset_top = TAB_TOP
	_tab_row.offset_bottom = TAB_TOP + TAB_H + ShadowStyle.OFFSET
	_tab_row.add_theme_constant_override("separation", 10 - int(ShadowStyle.OFFSET))
	add_child(_tab_row)
	_tab_dot = null
	for tab in TABS:
		# The design's 20 snaps to 24, too wide for five tabs: 16.
		var b := _tab_button(str(TAB_LABELS.get(tab, tab)), tab == _tab, 16, TAB_H)
		b.name = "Tab_" + tab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: String = tab
		b.pressed.connect(func() -> void: _show_tab(t))
		_tab_row.add_child(b)
		if tab == "HEAT" and match_waiting():
			_tab_dot = TabDot.new()
			_tab_dot.name = "MatchDot"
			_tab_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			_tab_dot.offset_left = -ShadowStyle.OFFSET + 9.0 - TabDot.SIZE
			_tab_dot.offset_right = _tab_dot.offset_left + TabDot.SIZE + 2.0
			_tab_dot.offset_top = -11.0
			_tab_dot.offset_bottom = _tab_dot.offset_top + TabDot.SIZE + 2.0
			b.add_child(_tab_dot)


## Is a game waiting on the MATCH pane (the design's gold dot)?
func match_waiting() -> bool:
	if doc.is_empty():
		return false
	return str(doc["season"]["phase"]) != Season.PHASE_DONE and Campaign.next_opponent(doc) != ""


## The MATCH tab's waiting dot (the design's tabDot): a 24 px gold square in
## a 3 px ink frame with a 2 px ink shadow, pulsing 1 → .8 → 1 every 1.6 s.
class TabDot extends Control:
	const SIZE := 24.0
	func _init() -> void:
		pivot_offset = Vector2.ONE * SIZE * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2.ONE * SIZE), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * SIZE), RetroTheme.SCENE_OUTLINE)
		draw_rect(Rect2(Vector2(3, 3), Vector2.ONE * (SIZE - 6.0)), LeagueContext.HI)


## Active (design 3a, 2026-10-30): a solid white face with tan dots, an
## orange dithered shadow and ink text. Inactive: see-through cream, cream
## text with the ink outline.
func _tab_button(text: String, active: bool, size_: int, height := 52.0) -> Button:
	var b: ShadowCard
	if active:
		b = ShadowCard.solid(CREAM, RetroTheme.TAN, RetroTheme.c("orange"))
		b.color = CREAM
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The solid face is drawn over the button's own text, so the label is a child.
		var l := UiFont.label(text, size_, INK)
		l.name = "Label"
		UiLayout.full_rect(l)
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
	UiLayout.full_rect(sc)
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


## Land on CARDS (the shop; what you own floats above it on the home — the
## loadout itself is picked before each heat, on the pre-match page).
func go_loadout() -> void:
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
	var w := _clip.size.x * 1.1   # the design's translateX(±110%), 0.3 s on the snap curve
	new_.visible = true
	new_.position.x = dir * w
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void:
		var e := CssEase.bezier(CssEase.SNAP, x)
		new_.position.x = dir * w * (1.0 - e)
		old.position.x = -dir * w * e
	, 0.0, 1.0, SLIDE_S)
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
		vb.add_child(_season_over_card(m))
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
	var playoffs: bool = m["phase"] == Season.PHASE_PLAYOFFS
	if playoffs:
		var mine := Season.player_series(s, Campaign.PLAYER)
		var wl := LeagueSummary.series_record(mine)
		line = "%s · GAME %d · %s" % [LeagueSummary.series_label(s, mine), wl[0] + wl[1] + 1, "HOME" if mine["highSeedId"] == Campaign.PLAYER else "AWAY"]
	else:
		var g := Season.player_game_on(s, m["day"], Campaign.PLAYER)
		var home: bool = not g.is_empty() and g["homeId"] == Campaign.PLAYER
		line = "DAY %d · %s" % [m["day"], "HOME" if home else "AWAY"]
	vb.add_child(_shooter_card(opp_id, line, playoffs))


## A shooter's regular-season table row: {w, l, place} (place 0 when not in the table).
func _table_row(id: String) -> Dictionary:
	var s: Dictionary = doc["season"]
	var table := Standings.table(LeagueData.team_ids(cfg), s["schedule"], int(s["seed"]))
	for i in table.size():
		if table[i]["teamId"] == id:
			return {"w": int(table[i]["w"]), "l": int(table[i]["l"]), "place": i + 1}
	return {"w": 0, "l": 0, "place": 0}


## The opponent card (design 3a, 2026-10-30): pine, see-through — the match
## line, VS., the name and their record (`RECORD · 2ND`, `· 2ND SEED` in the
## playoffs) on the left, nickname over hometown on the right; ACC / ARC
## segments and PACE beside PLAY (its gold shine); under a dashed rule the
## cards they hold for this game.
func _shooter_card(opp_id: String, line: String, playoffs: bool) -> Control:
	var sh := LeagueData.shooter(opp_id)
	var card := ShadowPanel.new(PINE, 22.0, 0.4, 24.0)
	card.name = "Opponent"
	var vb := _vcol(16)
	card.add_child(vb)
	var top := _hrow(16)
	vb.add_child(_inset(top, 6, 8))
	var names := _vcol(16)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	names.add_child(_text(line, 22))
	names.add_child(_display("VS.", 22, HI))
	var nm := _display(str(sh.get("name", "?")).to_upper(), 34)
	nm.name = "OppName"
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	names.add_child(nm)
	var tr := _table_row(opp_id)
	var rec := _hrow(12)
	rec.name = "OppRecord"
	rec.add_child(_display("%d-%d" % [tr["w"], tr["l"]], 22))
	var place := TickerText.ordinal(int(tr["place"])) if int(tr["place"]) > 0 else "-"
	var rs := _text("RECORD · %s%s" % [place, " SEED" if playoffs else ""], 20, MUTED)
	rs.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	rec.add_child(rs)
	names.add_child(rec)
	var tags := _vcol(16)
	tags.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_child(tags)
	var nick := _display("\"%s\"" % str(sh.get("nickname", "")).to_upper(), 22, HI)
	nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tags.add_child(nick)
	var town := _text(str(sh.get("hometown", "")).to_upper(), 22)
	town.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tags.add_child(town)
	var mid := _hrow(20)
	vb.add_child(mid)
	var ratings := _vcol(18)
	ratings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ratings.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(ratings)
	var r: Dictionary = sh.get("ratings", {})
	for spec in [["ACC", float(r.get("accuracy", 0.5))], ["ARC", float(r.get("swishRate", 0.5))]]:
		var rl := _hrow(12)
		rl.add_child(_cell(_text(spec[0], 22), 96))
		var segs := _hrow(5)
		var n := clampi(roundi(float(spec[1]) * 5.0), 0, 5)
		for i in 5:
			var seg := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = HI if i < n else Color(INK, 0.55)
			sb.border_color = CREAM
			sb.set_border_width_all(2)
			seg.add_theme_stylebox_override("panel", sb)
			seg.custom_minimum_size = Vector2(30, 20)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			segs.add_child(seg)
		rl.add_child(segs)
		ratings.add_child(rl)
	var pace := _hrow(12)
	pace.add_child(_cell(_text("PACE", 22), 96))
	pace.add_child(_display("%.1f S" % float(r.get("pace", 4.0)), 22))
	ratings.add_child(pace)
	var play := _big_button("PlayHeat", "PLAY", "", 34)
	play.pressed.connect(func() -> void: App.start_league_heat())
	mid.add_child(play)
	# Their cards for this game: the season hand they will pick from.
	var foot := _hrow(16)
	foot.name = "OppCards"
	var fcol := _vcol(14)
	fcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fcol)
	fcol.add_child(_display("%s'S CARDS" % LeagueSummary.short_name(opp_id), 18))
	var hand := _opp_hand(opp_id)
	var fsub := _text("THEIR CARDS FOR THIS MATCH" if not hand.is_empty() else "NO CARDS THIS MATCH", 20)
	fsub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fcol.add_child(fsub)
	var chips := _hrow(12)
	chips.name = "OppChips"
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for id in hand:
		var c := CardDefs.get_card(str(id))
		if not c.is_empty():
			chips.add_child(_crop_chip(c))
	foot.add_child(chips)
	vb.add_child(_dashed_top(foot))
	return card


## The opponent's season hand (the deterministic deal App.league_pre_match_info uses).
func _opp_hand(opp_id: String) -> Array:
	var season: Dictionary = Dictionary(doc["season"]).duplicate(true)
	Season.ensure_card_hands(season, cfg)
	var out := []
	for id in Season.card_hand(season, opp_id):
		if str(id) != "":
			out.push_back(str(id))
	return out


## The season-over card (design 3a, 2026-10-30): gold — SEASON n · OVER,
## CHAMPION and their name and record, your titles on the right; your
## AVG PTS / HIGH / STREAK beside START SEASON n+1; your playoff run under a
## dashed rule.
func _season_over_card(m: Dictionary) -> Control:
	var s: Dictionary = m["s"]
	var champ := str(s.get("championId", ""))
	var card := ShadowPanel.new(RetroTheme.c("gold"), 22.0, 0.32, 24.0)
	card.name = "SeasonOver"
	var vb := _vcol(16)
	card.add_child(vb)
	var top := _hrow(16)
	vb.add_child(_inset(top, 6, 8))
	var left := _vcol(16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(left)
	left.add_child(_text("SEASON %d · OVER" % m["year"], 22))
	left.add_child(_display("CHAMPION", 22, HI))
	var you := FaceOffPage.you_record()
	var cn := _display(str(you.get("name", "YOU")).to_upper() if champ == Campaign.PLAYER else _team_name(champ), 34)
	cn.name = "Champion"
	cn.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(cn)
	var tr := _table_row(champ)
	var rec := _hrow(12)
	rec.add_child(_display("%d-%d" % [tr["w"], tr["l"]], 22))
	var rs := _text("RECORD · %s" % (TickerText.ordinal(int(tr["place"])) if int(tr["place"]) > 0 else "-"), 20, MUTED)
	rs.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	rec.add_child(rs)
	left.add_child(rec)
	var right := _vcol(16)
	top.add_child(right)
	var cups := _hrow(8)
	cups.alignment = BoxContainer.ALIGNMENT_END
	var cup := PixelIcon.new("icon_trophy", Vector2(30, 30))
	cup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cups.add_child(cup)
	var titles := _display("×%d" % int(doc["career"]["championships"]), 22, HI)
	titles.name = "TitleCount"
	cups.add_child(titles)
	right.add_child(cups)
	var tl := _text("TITLES", 22)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(tl)
	var mid := _hrow(20)
	vb.add_child(mid)
	var lines := _vcol(18)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(lines)
	for k in LeagueSummary.season_line_stats(doc):
		var row := _hrow(12)
		row.add_child(_cell(_text(str(k["l"]), 22), 150))
		row.add_child(_display(str(k["v"]), 22))
		lines.add_child(row)
	var nxt := _big_button("NextSeason", "START", "SEASON %d" % (m["year"] + 1), 24)
	nxt.pressed.connect(func() -> void: new_season_requested.emit())
	mid.add_child(nxt)
	var foot := _vcol(14)
	foot.name = "PlayoffRun"
	foot.add_child(_display("PLAYOFF RUN", 18))
	var run := _text(LeagueSummary.playoff_run(s), 20)
	run.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(run)
	vb.add_child(_dashed_top(foot))
	return card


## The 232×104 orange button with a gold dot sweep (PLAY, START SEASON):
## the word (and a bold sub-line), `>` on the right.
func _big_button(id: String, word: String, sub: String, size_: int) -> ShadowCard:
	var b := ShadowCard.new(RetroTheme.c("orange"))
	b.name = id
	b.tint = 0.42
	b.clip_contents = true
	b.custom_minimum_size = Vector2(232 + ShadowStyle.OFFSET, 104 + ShadowStyle.OFFSET)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var shine := PreMatchPage.Shine.new(2.0, 200.0, 0.75, HI)
	shine.name = "Shine"
	UiLayout.full_rect(shine)
	shine.offset_right = -ShadowStyle.OFFSET
	shine.offset_bottom = -ShadowStyle.OFFSET
	b.add_child(shine)
	var pm := MarginContainer.new()
	UiLayout.full_rect(pm)
	pm.add_theme_constant_override("margin_left", 18)
	pm.add_theme_constant_override("margin_right", 18 + int(ShadowStyle.OFFSET))
	pm.add_theme_constant_override("margin_bottom", int(ShadowStyle.OFFSET))
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pm)
	var pr := _hrow(12)
	pm.add_child(pr)
	var col := _vcol(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.add_child(col)
	var w := _display(word, size_)
	w.name = "Word"
	col.add_child(w)
	if sub != "":
		var sl := _text(sub, 18)
		sl.name = "Sub"
		col.add_child(sl)
	var pc := _display(">", 26)
	pc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(pc)
	return b


## A 48 px card chip (their cards): the art cropped in an ink frame, a 3 px shadow.
func _crop_chip(card: Dictionary) -> Control:
	var holder := Control.new()
	holder.name = "Chip_" + str(card.get("id", ""))
	holder.custom_minimum_size = Vector2(51, 51)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sh := ColorRect.new()
	sh.color = INK
	sh.position = Vector2(3, 3)
	sh.size = Vector2(48, 48)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sh)
	var frame := ColorRect.new()
	frame.color = INK
	frame.size = Vector2(48, 48)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var clip := Control.new()
	clip.position = Vector2(2, 2)
	clip.size = Vector2(44, 44)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(clip)
	var face := CardFace.new(card, Vector2(58, 77))
	face.position = Vector2(-7, -7)
	clip.add_child(face)
	return holder


## `c` under a dashed cream rule at 40 %, 14 px above it.
func _dashed_top(c: Control) -> VBoxContainer:
	var v := _vcol(14)
	var rule := ModeCards.DashedRule.new(2.0)
	rule.modulate.a = 0.4
	v.add_child(rule)
	v.add_child(c)
	return v


## `c` with `top` / `bottom` px of room around it.
func _inset(c: Control, top: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m


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
	# Playoffs: the bracket as a tree (design 3a, 2026-10-30) — the final on
	# top, a connector, the two semis side by side.
	vb.add_child(_caps("PLAYOFFS · SEASON %d" % m["year"]))
	var tree := _vcol(0)
	tree.name = "Bracket"
	vb.add_child(tree)
	var top := CenterContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.add_child(top)
	var fin := _vcol(12)
	fin.name = "Final"
	fin.custom_minimum_size = Vector2(380, 0)
	top.add_child(fin)
	var fhead := _hrow(10)
	fhead.alignment = BoxContainer.ALIGNMENT_CENTER
	var cup := PixelIcon.new("icon_trophy", Vector2(30, 30))
	cup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fhead.add_child(cup)
	fhead.add_child(_text("FINAL · BO%d" % int(s.get("finalBestOf", 5)), 20))
	fin.add_child(fhead)
	var final_ := Playoffs.find(s["series"], "final")
	if final_.is_empty():
		var panel := _panel(8.0, 0.0)
		var col := _vcol(0)
		panel.add_child(col)
		for series in s["series"]:
			if series["round"] != "semifinal":
				continue
			var w := str(series["winnerId"])
			var r1 := _row(54)
			r1.add_child(_cell(_display(_seed_of(w) if w != "" else "?", 18, CREAM if w != "" else MUTED), 22))
			var who := _text(_team_name(w) if w != "" else "%s VS %s WINNER" % [_seed_of(str(series["highSeedId"])), _seed_of(str(series["lowSeedId"]))],
				22, CREAM if w != "" else MUTED)
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			who.clip_text = true
			r1.add_child(who)
			col.add_child(_pad_row(r1, 16))
		fin.add_child(panel)
	else:
		fin.add_child(_series_panel(final_, 54, 18, 22, 16))
	var conn := Connector.new()
	conn.name = "Connector"
	conn.custom_minimum_size = Vector2(0, 44 + 16)
	tree.add_child(conn)
	var semis := _hrow(24)
	semis.name = "Semis"
	tree.add_child(semis)
	var n_semi := 0
	for series in s["series"]:
		if series["round"] != "semifinal":
			continue
		n_semi += 1
		var done: bool = series["winnerId"] != ""
		var g := int(series["highWins"]) + int(series["lowWins"])
		var block := _vcol(12)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := _text("SEMI %d · %s" % [n_semi, "DONE" if done else "GAME %d" % (g + 1)], 18)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(head)
		block.add_child(_series_panel(series, 52, 16, 20, 12))
		semis.add_child(block)
	if str(s.get("championId", "")) != "":
		vb.add_child(_display("CHAMPION: %s" % _team_name(str(s["championId"])), 26, HI))
	vb.add_child(_caps("SEEDS FROM THE FINAL TABLE · 1 V 4 · 2 V 3"))


## A shooter's regular-season seed as text ("" when unknown).
func _seed_of(id: String) -> String:
	var s: Dictionary = doc["season"]
	for row in Standings.table(LeagueData.team_ids(cfg), s["schedule"], int(s["seed"])):
		if row["teamId"] == id:
			return str(int(row["seed"]))
	return ""


## A series in a see-through panel: both sides (seed, name, wins), yours on orange.
func _series_panel(series: Dictionary, row_h := 52, seed_size := 16, name_size := 20, pad := 12) -> Control:
	var panel := _panel(8.0, 0.0)
	var col := _vcol(0)
	panel.add_child(col)
	for side in [["highSeedId", "highWins"], ["lowSeedId", "lowWins"]]:
		var id := str(series[side[0]])
		var r := _row(row_h)
		r.add_child(_cell(_display(_seed_of(id), seed_size), 22))
		var nm := _text(_team_name(id), name_size)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		r.add_child(nm)
		r.add_child(_cell(_display(str(int(series[side[1]])), name_size), 32, HORIZONTAL_ALIGNMENT_RIGHT))
		col.add_child(_pad_row(r, pad, RetroTheme.c("orange") if id == Campaign.PLAYER else Color.TRANSPARENT))
	return panel


## A bracket row inset `pad` px each side over an optional full-width band.
func _pad_row(r: HBoxContainer, pad: int, fill := Color.TRANSPARENT) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", pad)
	m.add_theme_constant_override("margin_right", pad)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill.a > 0.0:
		var bg := StyleBoxFlat.new()
		bg.bg_color = fill
		var wrap := PanelContainer.new()
		wrap.add_theme_stylebox_override("panel", bg)
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(m)
		m.add_child(r)
		return wrap
	m.add_child(r)
	return m


func _rule() -> Control:
	return ModeCards.DashedRule.new(3.0)


## The bracket's connector (the design's path, 4 px cream): down from the
## final's middle, across to the quarter points, down to each semi.
class Connector extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var y0 := 10.0
		var mid := y0 + 18.0
		var y1 := y0 + 44.0
		var c := RetroTheme.SCENE_TEXT
		draw_rect(Rect2(w * 0.5 - 2.0, y0, 4.0, mid - y0 + 2.0), c)
		draw_rect(Rect2(w * 0.25 - 2.0, mid - 2.0, w * 0.5 + 4.0, 4.0), c)
		draw_rect(Rect2(w * 0.25 - 2.0, mid - 2.0, 4.0, y1 - mid + 2.0), c)
		draw_rect(Rect2(w * 0.75 - 2.0, mid - 2.0, 4.0, y1 - mid + 2.0), c)


# ---- SCHED -----------------------------------------------------------------------


func _fill_sched() -> void:
	var vb := _list("SCHED")
	var m := _season_meta()
	var s: Dictionary = m["s"]
	var rec := LeagueSummary.record(s)
	vb.add_child(_caps(("%d DAYS · %d-%d" if m["phase"] == Season.PHASE_DONE else "%d DAYS · %d-%d SO FAR") % [Season.days(s), rec[0], rec[1]]))
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
	vb.add_theme_constant_override("separation", 24)
	var head := _vcol(14)
	head.name = "ShopHead"
	vb.add_child(head)
	head.add_child(_display("SHOP", 30))
	var arena := CosmeticLibrary.get_arena(str(cfg.get("arena", cfg.get("location", "cage"))))
	var where := str(arena.display_name).to_upper() if arena != null else str(cfg.get("name", "LEAGUE")).to_upper()
	var note := _text("CARDS BOUGHT IN THE %s SHOP CAN ONLY BE PLAYED IN %s MATCHES" % [where, where], 20, HI)
	note.name = "ShopNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_constant_override("line_spacing", 8)
	head.add_child(note)
	for card in CardDefs.all():
		vb.add_child(_shop_row(card))


## A shop row (design 3a, 2026-10-30): the art, the name, its LVL tag on the
## corner (gold edge once you can play it) and the buy button.
func _shop_row(card: Dictionary) -> Control:
	var cid := str(card["id"])
	var panel := ShadowPanel.new(CREAM, 20.0, 0.22)
	panel.name = "Shop_" + cid
	var row := _hrow(20)
	panel.add_child(row)
	var art := ModeCards.art(card, Vector2(120, 160), 6.0)
	art.name = "Art"
	row.add_child(art)
	var col := _vcol(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var above := Control.new()
	above.name = "Above"
	above.size_flags_vertical = Control.SIZE_EXPAND_FILL
	above.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(above)
	var nm := _display(str(card.get("name", "")).to_upper(), 24)
	nm.name = "Name"
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.add_theme_constant_override("line_spacing", 8)
	col.add_child(nm)
	var below := Control.new()
	below.size_flags_vertical = Control.SIZE_EXPAND_FILL
	below.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(below)
	var foot := _hrow(14)
	foot.name = "BuyArea_" + cid
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.custom_minimum_size = Vector2(0, 72 + ShadowStyle.OFFSET)
	col.add_child(foot)
	# The level it plays from (docs/PROGRESSION.md) on the panel's corner:
	# right −5, top −10 off the face — hung off the column's top-right.
	var usable := Progression.can_use(App.level(), card)
	var lvl := PanelContainer.new()
	lvl.name = "Level_" + cid
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(INK, 0.6)
	lsb.border_color = RetroTheme.c("gold") if usable else CREAM
	lsb.set_border_width_all(2)
	lsb.content_margin_left = 10
	lsb.content_margin_right = 10
	lsb.content_margin_top = 3
	lsb.content_margin_bottom = 3
	lvl.add_theme_stylebox_override("panel", lsb)
	lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lt := "LVL %d" % Progression.card_level(card)
	lvl.add_child(UiFont.label(lt, 20, RetroTheme.c("gold") if usable else CREAM, UiFont.body_bold()))
	var lw := UiFont.body_bold().get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(20)).x + 24.0
	lvl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lvl.offset_right = 20.0 + 5.0
	lvl.offset_left = lvl.offset_right - lw
	lvl.offset_top = -20.0 - 10.0
	above.add_child(lvl)
	_fill_buy(cid, foot)
	panel.set_meta("art", art)
	return panel


## The buy button's state for a card: idle (the gold price), ask (X and the
## orange CONFIRM, for ASK_S), done (+1 ADDED, for ADDED_S).
func buy_state(id: String) -> String:
	return str(_buy[id]["state"]) if _buy.has(id) else "idle"


## A tap on a card's buy button: idle → ask, ask → buy.
func tap_buy(id: String) -> void:
	match buy_state(id):
		"idle":
			_set_buy(id, "ask")
		"ask":
			_confirm_buy(id)


func cancel_buy(id: String) -> void:
	_set_buy(id, "idle")


func _confirm_buy(id: String) -> void:
	if not App.try_buy_card(id, league_id):
		_set_buy(id, "idle")
		return
	doc = App.league_doc(league_id)
	_set_buy(id, "done")
	for card in CardDefs.all():
		if str(card["id"]) != id and buy_state(str(card["id"])) == "idle":
			_fill_buy(str(card["id"]))   # the wallet moved: affordability
	var row: Control = _list("CARDS").get_node_or_null("Shop_" + id)
	var art: Control = row.get_meta("art") if row != null and row.has_meta("art") else null
	var from := Rect2(art.get_global_rect().position, Vector2(120, 160)) if art != null and art.is_inside_tree() else Rect2()
	card_bought.emit(id, from)


func _set_buy(id: String, state: String) -> void:
	if state == "idle":
		_buy.erase(id)
	else:
		_buy[id] = {"state": state, "until": _clock + (ASK_S if state == "ask" else ADDED_S)}
	_fill_buy(id)


func _fill_buy(id: String, foot: HBoxContainer = null) -> void:
	if foot == null:
		foot = _list("CARDS").find_child("BuyArea_" + id, true, false)
	if foot == null:
		return
	for c in foot.get_children():
		foot.remove_child(c)
		c.queue_free()
	var card := CardDefs.get_card(id)
	var price := int(card.get("price", 0))
	match buy_state(id):
		"ask":
			var x := HomePage.button("X", CREAM, 24, 72.0)
			x.name = "Cancel_" + id
			x.custom_minimum_size = Vector2(72, 72) + Vector2.ONE * ShadowStyle.OFFSET
			x.pressed.connect(func() -> void: cancel_buy(id))
			foot.add_child(x)
			var ok := ShadowCard.new(RetroTheme.c("orange"))
			ok.name = "Confirm_" + id
			ok.tint = 0.42
			ok.custom_minimum_size = Vector2(196, 72) + Vector2.ONE * ShadowStyle.OFFSET
			var oc := _vcol(8)
			oc.alignment = BoxContainer.ALIGNMENT_CENTER
			UiLayout.full_rect(oc)
			oc.offset_right = -ShadowStyle.OFFSET
			oc.offset_bottom = -ShadowStyle.OFFSET
			ok.add_child(oc)
			var cw := _display("CONFIRM", 20)
			cw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			oc.add_child(cw)
			var pr := _hrow(8)
			pr.alignment = BoxContainer.ALIGNMENT_CENTER
			var tk := PixelIcon.new("icon_ticket", Vector2(22, 14))
			tk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pr.add_child(tk)
			pr.add_child(_text(str(price), 16))
			oc.add_child(pr)
			ok.pressed.connect(func() -> void: tap_buy(id))
			foot.add_child(ok)
		"done":
			var done := AddedBox.new()
			done.name = "Added_" + id
			var dl := _display("+1 ADDED", 22, HI)
			UiLayout.full_rect(dl)
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			done.add_child(dl)
			foot.add_child(done)
		_:
			var buy := ShadowCard.new(RetroTheme.c("gold"))
			buy.name = "Buy_" + id
			buy.custom_minimum_size = Vector2(196, 72) + Vector2.ONE * ShadowStyle.OFFSET
			buy.disabled = App.tickets() < price or not Progression.can_use(App.level(), card)   # bought at level, too
			var br := _hrow(10)
			br.alignment = BoxContainer.ALIGNMENT_CENTER
			UiLayout.full_rect(br)
			br.offset_right = -ShadowStyle.OFFSET
			br.offset_bottom = -ShadowStyle.OFFSET
			buy.add_child(br)
			var ticket := PixelIcon.new("icon_ticket", Vector2(38, 24))
			ticket.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			br.add_child(ticket)
			var pl := _display(str(price), 26)
			pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			br.add_child(pl)
			buy.pressed.connect(func() -> void: tap_buy(id))
			foot.add_child(buy)


## +1 ADDED's box: a dashed gold border, 196 × 72, no face.
class AddedBox extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(196, 72) + Vector2.ONE * ShadowStyle.OFFSET
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var b := Rect2(Vector2.ONE, Vector2(196, 72) - Vector2.ONE * 2.0)
		var pts := [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y), b.position]
		for i in 4:
			draw_dashed_line(pts[i], pts[i + 1], LeagueContext.HI, 2.0, 8.0)


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
