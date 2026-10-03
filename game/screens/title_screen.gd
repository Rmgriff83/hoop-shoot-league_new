extends Node3D
## Home: Ross's retro card chrome over a FULL-SCREEN live view of the current
## area (docs/HOME.md, design "Home League Context v2"). The court (a real
## CourtGeometry, panned by TitlePan) is the page background under a mild
## scrim; on a CanvasLayer above it sit the top bar (LVL01 + meter, the
## locker ball, the ticket pill, the menu), the AREA ZONE — the difficulty
## stars over the area's name (a dithered drop shadow) with the ranks and
## multiplayer icons, and the `▾ ALL AREAS · n/3 OPEN` line that opens the
## AREA ARCHIVE (AreaArchivePage, docs/HOME.md → Area archive: the page you
## see before any area's home, the only way between areas, so a locked
## area's home is never shown; it opens on every cold launch) — the CARD
## AREA (the big LEAGUE card with its season numbers, trophies and loadout
## chips, and the TIME TRIAL / PRACTICE pair; tapping LEAGUE slides the
## cards out and the league in context in: LeagueContext), a FLOATING LAYER
## over the court above the area that shows data for the open tab (the
## loadout, your spot, what's coming up, this season), and the ticker at the
## very bottom. No bottom nav. Two palettes (RetroTheme, App.dark_mode) over
## one layout; the chrome rebuilds in place when the setting flips. One
## court lives at a time: a page turn covers the screen, rebuilds the court
## and refreshes the chrome.

## The areas in page order live in AreaArchiveCopy.AREAS (the archive and
## the snapshot tool read the same list).
const CARDS := AreaArchiveCopy.AREAS
const MARGIN := 36.0
const COLUMN_W := 648.0
const SCRIM_ALPHA := 0.25
const FADE_S := 0.2
## The chrome's rows (design px). The zone: the stars over the name under the
## top bar, the ALL AREAS line under the name; the chevrons at mid-height
## between the zone and the card area — `<` to the area before, `>` to the
## next only when it is open, with a NEW badge until it has been visited.
const ZONE_Y := 180.0
const NAME_W := 430.0
const CHEVRON_SIZE := Vector2(112, 176)
const CHEVRON_Y := 520.0 - (CHEVRON_SIZE.y - 72.0) / 2.0
## The card area: a fixed box above the ticker that holds the home block
## (LEAGUE + the pair) or the league in context. Cards carry their shadow in
## their size, so the gaps are the design's less the 6 px strip.
const AREA_W := 654.0
const AREA_TOP := 781.0
const AREA_BOTTOM := 1280.0 - HomeTicker.HEIGHT - 26.0
const CARD_GAP := 20.0 - ShadowStyle.OFFSET
const LEAGUE_H := ModeCards.LEAGUE_H + ShadowStyle.OFFSET
const PAIR_H := ModeCards.PAIR_H + ShadowStyle.OFFSET
const CARDS_H := LEAGUE_H + CARD_GAP + PAIR_H
const OPEN_S := 0.3
## The wash under the card area: transparent at the area's top, easing to a
## slightly opaque dark gray where the ticker starts, so the cards read over
## the court's floor.
const WASH_COLOR := Color("#1B1815")
const WASH_ALPHA := 0.72
## The floating layer's rows: the compact loadout strip on MATCH, the full
## loadout on CARDS a little higher, the rest.
const FLOAT_Y := 612.0
const LOADOUT_Y := 584.0
const STRIP_Y := 700.0
## The season chip under the area name while the league is open.
const CHIP_POS := Vector2(36, 362)
const CHIP_H := 46.0

var _index := 0
var _t := 0.0
var _spec: Dictionary = {}
var _court: CourtGeometry
var _cam: Camera3D
var _ui: CanvasLayer
var _chrome: Control
var _cover: ColorRect
var _stars: HBoxContainer
var _area_name: Label
var _cards_row: VBoxContainer
var _area: Control
var _float: Control
var _league: LeagueContext
var _open := false
var _open_frac := 0.0
var _archive: AreaArchivePage
var _all_areas: Button
var _prev: Button
var _next: Button
var _ticker: HomeTicker
var _badge: LevelBadge
var _season_chip: ShadowPanel
var _chip_a: Label
var _chip_b: Label
var _settings: SettingsPanel
var _switching := false


func _ready() -> void:
	Sfx.start_music(App.TITLE_MUSIC["id"], App.TITLE_MUSIC["clip"], App.TITLE_MUSIC["gain_db"])
	_index = clampi(App.home_card, 0, CARDS.size() - 1)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	add_child(_cam)
	_ui = CanvasLayer.new()
	_ui.name = "Ui"
	_ui.layer = 10
	add_child(_ui)
	_cover = ColorRect.new()
	_cover.name = "Cover"
	_cover.color = Color(RetroTheme.c("ink"), 0.0)
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CONTINUE SEASON (and start_league) land here with a league to open.
	var deep := App.home_open_league
	if deep != "":
		App.home_open_league = ""
		for i in CARDS.size():
			if LeagueData.league(deep).get("location", "") == CARDS[i]["area"]:
				_index = i
	# A stale card for a locked area (the gate rose, or a new save): the
	# first open area, and the archive in front.
	var stale := not App.area_unlocked(str(CARDS[_index]["area"]))
	if stale:
		for i in CARDS.size():
			if App.area_unlocked(str(CARDS[i]["area"])):
				_index = i
				break
		App.home_card = _index
	rebuild_chrome()
	_ui.add_child(_cover)
	_build_court(_index)
	if deep != "" and App.enter_league(deep):
		_open_league(true)
	elif App.show_archive or stale:
		App.show_archive = false
		_open_archive(true)


func _process(dt: float) -> void:
	_t += dt
	if _court != null:
		var p := TitlePan.pose(_spec, _t)
		_cam.position = p["pos"]
		_cam.look_at(p["look"])
		_court.step_rim(dt)


# ---- the live court (the page background) ----------------------------------------


func _build_court(i: int) -> void:
	if _court != null:
		_court.queue_free()
		_court = null
	var card: Dictionary = CARDS[i]
	var arena := CosmeticLibrary.get_arena(card["area"])
	if arena == null:
		arena = CosmeticLibrary.starter_arena()
	_court = CourtGeometry.new()
	_court.name = "Court"
	_court.geo = App.geo_for_mode(card["mode"])
	_court.arena_set = arena
	_court.hoop_set = App.hoop_for_mode(card["mode"])
	add_child(_court)
	_court.led.set_text("HOOP SHOOT", _court.led.accent_color)
	App.mark_area_visited(str(card["area"]))
	_spec = TitlePan.spec_of(arena)
	_cam.fov = float(_spec["fov"])
	_t = 0.0
	var p := TitlePan.pose(_spec, 0.0)
	_cam.position = p["pos"]
	_cam.look_at(p["look"])


# ---- the chrome ------------------------------------------------------------------


## Build (or rebuild, on a theme flip) everything on the CanvasLayer but the cover.
func rebuild_chrome() -> void:
	if _chrome != null:
		_chrome.queue_free()
	_chrome = Control.new()
	_chrome.name = "Chrome"
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_chrome)
	_ui.move_child(_chrome, 0)

	# The scrim over the court.
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(RetroTheme.LIGHT["ink"], SCRIM_ALPHA)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_chrome.add_child(scrim)

	# Top bar.
	_badge = LevelBadge.new()
	_badge.position = Vector2(MARGIN, 32)
	_badge.set_level(App.level(), Progression.frac_for(App.xp()))
	_chrome.add_child(_badge)
	var locker := IconButton.new("locker")
	locker.name = "Locker"
	locker.position = Vector2(230, 32)
	locker.badge = not App.unseen_balls().is_empty()
	locker.pressed.connect(_open_locker)
	_chrome.add_child(locker)
	var menu := HamburgerButton.new()
	menu.name = "Menu"
	menu.position = Vector2(720 - MARGIN - HamburgerButton.SIZE, 32)
	menu.pressed.connect(_open_settings)
	_chrome.add_child(menu)
	var coins := CoinsPill.new()
	coins.set_coins(App.tickets())
	coins.position = Vector2(720 - MARGIN - HamburgerButton.SIZE - 16 - 170, 32)
	_chrome.add_child(coins)

	# The area zone: the stars on top, the name big under them with the
	# ranks and multiplayer icons to its right, chevrons at the screen edges.
	var zone := VBoxContainer.new()
	zone.name = "Zone"
	zone.position = Vector2(MARGIN, ZONE_Y)
	zone.size = Vector2(COLUMN_W, 0)
	zone.add_theme_constant_override("separation", 14)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(zone)
	_stars = HBoxContainer.new()
	_stars.name = "Stars"
	_stars.custom_minimum_size = Vector2(0, 27)
	_stars.add_theme_constant_override("separation", 6)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(_stars)
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 20)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(name_row)
	_area_name = RetroTheme.on_scene(RetroTheme.display("", 52))
	_area_name.name = "AreaName"
	_area_name.custom_minimum_size = Vector2(NAME_W, 0)
	_area_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_area_name.add_theme_constant_override("line_spacing", 8)
	_area_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_area_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	RetroTheme.dithered(_area_name)
	_area_name.mouse_filter = Control.MOUSE_FILTER_STOP
	_area_name.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			_open_archive()
	)
	name_row.add_child(_area_name)
	var ranks := IconButton.new("ranks")
	ranks.name = "Ranks"
	ranks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(ranks)
	var multi := IconButton.new("multi")
	multi.name = "Multi"
	multi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(multi)
	var soon := RetroTheme.on_scene(RetroTheme.caps("SOON", 16))
	soon.name = "Soon"
	soon.visible = false
	soon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(soon)
	var flash := func() -> void:
		soon.visible = true
		var tw := create_tween()
		tw.tween_interval(0.8)
		tw.tween_callback(func() -> void: soon.visible = false)
	ranks.pressed.connect(flash)
	multi.pressed.connect(flash)
	# `▾ ALL AREAS · 2/3 OPEN`: the archive's door.
	_all_areas = Button.new()
	_all_areas.name = "AllAreas"
	_all_areas.flat = true
	_all_areas.focus_mode = Control.FOCUS_NONE
	_all_areas.custom_minimum_size = Vector2(0, 34)
	_all_areas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_all_areas.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.name = "AllAreasRow"
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_all_areas.add_child(row)
	var tri := DownTriangle.new()
	tri.name = "Triangle"
	tri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tri)
	var all_label := _float_text("", 16, RetroTheme.SCENE_TEXT, false)
	all_label.name = "AllAreasText"
	all_label.add_theme_color_override("font_shadow_color", RetroTheme.SCENE_OUTLINE)
	all_label.add_theme_constant_override("shadow_offset_x", 2)
	all_label.add_theme_constant_override("shadow_offset_y", 2)
	all_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(all_label)
	_all_areas.pressed.connect(func() -> void: _open_archive())
	zone.add_child(_all_areas)
	_prev = _chevron("<", -1)
	_prev.position = Vector2(8, CHEVRON_Y)
	_chrome.add_child(_prev)
	_next = _chevron(">", 1)
	_next.position = Vector2(720 - 8 - CHEVRON_SIZE.x, CHEVRON_Y)
	_chrome.add_child(_next)
	# The season chip: `SEASON 2 - 2-1`, slid in from the left while the league is open.
	_season_chip = ShadowPanel.new(RetroTheme.c("orange"), 0.0, 0.30, 16.0)
	_season_chip.name = "SeasonChip"
	_season_chip.position = CHIP_POS
	_season_chip.custom_minimum_size = Vector2(0, CHIP_H + ShadowStyle.OFFSET)
	_season_chip.visible = false
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 14)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_season_chip.add_child(chip_row)
	_chip_a = _float_text("", 16, RetroTheme.SCENE_TEXT, true)
	_chip_a.name = "ChipA"
	_chip_a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_row.add_child(_chip_a)
	var dash := ModeCards.Dash.new()
	dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(dash)
	_chip_b = _float_text("", 16, LeagueContext.HI, true)
	_chip_b.name = "ChipB"
	_chip_b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_row.add_child(_chip_b)
	_chrome.add_child(_season_chip)
	# The wash under the card area: a vertical gradient from nothing at the
	# area's top to a dark gray at the ticker.
	var wash := TextureRect.new()
	wash.name = "Wash"
	var grad := Gradient.new()
	grad.set_color(0, Color(WASH_COLOR, 0.0))
	grad.set_color(1, Color(WASH_COLOR, WASH_ALPHA))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	wash.texture = gt
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.position = Vector2(0, AREA_TOP)
	wash.size = Vector2(720, 1280 - HomeTicker.HEIGHT - AREA_TOP)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(wash)

	# The card area: the home cards, and the league in context when open.
	_area = Control.new()
	_area.name = "Area"
	_area.position = Vector2(MARGIN, AREA_TOP)
	_area.size = Vector2(AREA_W, AREA_BOTTOM - AREA_TOP)
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(_area)
	_cards_row = VBoxContainer.new()
	_cards_row.name = "Cards"
	_cards_row.size = Vector2(COLUMN_W, CARDS_H)
	_cards_row.add_theme_constant_override("separation", int(CARD_GAP))
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(_cards_row)
	_fill_cards()
	# The floating layer over the court, above the area (the open tab's data).
	_float = Control.new()
	_float.name = "Float"
	_float.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(_float)
	# The league panel is built in the palette too: rebuild it on a flip,
	# keeping its tab.
	if _league != null:
		var tab := _league.current_tab()
		var sub := _league.card_sub()
		_league.queue_free()
		_league = _make_league(tab, sub)
	elif _open:
		_league = _make_league()
	_apply_area(_open_frac)
	_rebuild_float()

	# The ticker sits at the very bottom (no bottom nav: the safe area would
	# push one up on the phone).
	_ticker = HomeTicker.new()
	_ticker.position = Vector2(-RetroTheme.BORDER, 1280 - HomeTicker.HEIGHT + RetroTheme.BORDER)
	_ticker.size = Vector2(720 + 2 * RetroTheme.BORDER, HomeTicker.HEIGHT)
	_chrome.add_child(_ticker)
	_refresh_ticker()
	_update_zone()


func _fill_cards() -> void:
	for c in _cards_row.get_children():
		_cards_row.remove_child(c)
		c.free()
	var area := str(CARDS[_index]["area"])
	var st := _league_state(area)
	var league_id := str(st["league"]["id"]) if not st.is_empty() else ""
	var slots: Array = App.loadout_slots(league_id) if league_id != "" else []
	# A locked area (docs/PROGRESSION.md): every card disabled, the level it needs on each.
	var lock := 0 if App.area_unlocked(area) else Progression.area_level(area)
	var league := ModeCards.league_card(st, slots)
	league.custom_minimum_size = Vector2(0, LEAGUE_H)
	league.pressed.connect(func() -> void: _pick("league"))
	var enter := ModeCards.enter_button(league)
	if enter != null:
		enter.pressed.connect(func() -> void: _pick("league"))
	_cards_row.add_child(league)
	var pair := HBoxContainer.new()
	pair.name = "Pair"
	pair.add_theme_constant_override("separation", 26 - int(ShadowStyle.OFFSET))
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_row.add_child(pair)
	var trial := ModeCards.trial_card(_best(area), lock)
	trial.custom_minimum_size = Vector2(0, PAIR_H)
	trial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trial.pressed.connect(func() -> void: _pick("trial"))
	pair.add_child(trial)
	var practice := ModeCards.practice_card(lock)
	practice.custom_minimum_size = Vector2(0, PAIR_H)
	practice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice.pressed.connect(func() -> void: _pick("practice"))
	pair.add_child(practice)


## Lay the area out for an openness fraction: 0 = home cards, 1 = league.
## The box stays put; the home block slides out left, the league in from
## the right; the chevrons show at home, the float once the league is in.
func _apply_area(f: float) -> void:
	_open_frac = f
	_cards_row.position = Vector2(-1.1 * AREA_W * f, _area.size.y - CARDS_H)
	if _league != null:
		_league.position = Vector2(1.1 * AREA_W * (1.0 - f), 0)
		_league.size = _area.size
	var home := f < 0.5
	if _all_areas != null:
		_all_areas.visible = home
	if _prev != null:
		_prev.visible = home and _chevron_ok(-1)
		_next.visible = home and _chevron_ok(1)
	if _float != null:
		_float.visible = not home
	if _season_chip != null:
		_season_chip.visible = f > 0.0 and _chip_a.text != ""
		_season_chip.position = Vector2(lerpf(-1.3 * maxf(_season_chip.size.x, 1.0), CHIP_POS.x, f), CHIP_POS.y)
		_season_chip.modulate.a = f


func _make_league(tab := "HEAT", sub := "LOADOUT") -> LeagueContext:
	var lc := LeagueContext.new()
	lc.name = "League"
	lc.setup(str(CARDS[_index]["area"]), tab, sub)
	lc.closed.connect(_close_league)
	lc.changed.connect(func() -> void:
		_update_zone()
		_refresh_ticker()
		_rebuild_float()
	)
	lc.tab_changed.connect(func(_tab: String) -> void: _rebuild_float())
	_area.add_child(lc)
	return lc


## LEAGUE tapped: slide the home block out and the league in context in.
func _open_league(instant := false) -> void:
	if _open or _switching:
		return
	if not App.enter_league(str(CARDS[_index]["area"])):
		return
	_open = true
	if _league == null:
		_league = _make_league()
	_update_zone()   # the campaign exists now: the season chip has its copy
	_rebuild_float()
	if instant:
		_apply_area(1.0)
		return
	var tw := create_tween()
	tw.tween_method(_apply_area, _open_frac, 1.0, OPEN_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## "<" in the league: slide it out and the home block back in.
func _close_league() -> void:
	if not _open:
		return
	_open = false
	_fill_cards()
	var tw := create_tween()
	tw.tween_method(_apply_area, _open_frac, 0.0, OPEN_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	if _league != null and not _open:
		_league.queue_free()
		_league = null
	_rebuild_float()
	_refresh_ticker()


func is_league_open() -> bool:
	return _open


## A big edge chevron over the court: a dithered-shadow glyph on a bare
## button, with a NEW badge the next chevron shows for an unvisited area.
func _chevron(text: String, dir: int) -> Button:
	var b := Button.new()
	b.name = "Prev" if dir < 0 else "Next"
	b.custom_minimum_size = CHEVRON_SIZE
	b.size = CHEVRON_SIZE
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var glyph := _float_text(text, 72, RetroTheme.SCENE_TEXT, true)
	glyph.name = "Glyph"
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	RetroTheme.dithered(glyph)
	b.add_child(glyph)
	var badge := ChevronBadge.new()
	badge.name = "Badge"
	badge.position = Vector2(CHEVRON_SIZE.x - 40, 40)
	badge.visible = false
	b.add_child(badge)
	b.button_down.connect(func() -> void: glyph.add_theme_color_override("font_color", RetroTheme.LIGHT["orange"]))
	b.button_up.connect(func() -> void: glyph.add_theme_color_override("font_color", RetroTheme.SCENE_TEXT))
	b.pressed.connect(func() -> void: _switch(dir))
	return b


## Is there an open area in that direction?
func _chevron_ok(dir: int) -> bool:
	var i := _index + dir
	return i >= 0 and i < CARDS.size() and App.area_unlocked(str(CARDS[i]["area"]))


func _update_chevrons() -> void:
	if _prev == null:
		return
	var home := _open_frac < 0.5
	_prev.visible = home and _chevron_ok(-1)
	_next.visible = home and _chevron_ok(1)
	var badge: Control = _next.get_node_or_null("Badge")
	if badge != null:
		badge.visible = _chevron_ok(1) and App.area_unvisited(str(CARDS[_index + 1]["area"]))


func next_badge_visible() -> bool:
	var badge: Control = _next.get_node_or_null("Badge") if _next != null else null
	return badge != null and badge.visible and _next.visible


## Page turn: cover the screen, rebuild the court, refresh the chrome, uncover.
func _switch(dir: int) -> void:
	if _switching or _open or not _chevron_ok(dir):
		return
	_switching = true
	_cover.color = Color(RetroTheme.c("ink"), 0.0)
	var fade := create_tween()
	fade.tween_property(_cover, "color:a", 1.0, FADE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fade.finished
	_index = _index + dir
	App.home_card = _index
	_build_court(_index)
	_update_zone()
	_fill_cards()
	_refresh_ticker()
	var back := create_tween()
	back.tween_property(_cover, "color:a", 0.0, FADE_S * 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await back.finished
	_switching = false


## The gold NEW dot on the next chevron.
class ChevronBadge extends Control:
	func _init() -> void:
		size = Vector2(28, 28)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(14, 14), 12.0, RetroTheme.SCENE_OUTLINE)
		draw_circle(Vector2(14, 14), 8.5, RetroTheme.LIGHT["gold"])


## The little bordered down-triangle on the ALL AREAS line.
class DownTriangle extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), Vector2(28, 28)), RetroTheme.SCENE_OUTLINE, false, 2.0)
		draw_rect(Rect2(Vector2(0, 0), Vector2(28, 28)), RetroTheme.SCENE_TEXT, false, 2.0)
		var pts := PackedVector2Array([Vector2(8, 11), Vector2(20, 11), Vector2(14, 19)])
		draw_colored_polygon(pts, RetroTheme.SCENE_TEXT)


func _update_zone() -> void:
	var arena := CosmeticLibrary.get_arena(str(CARDS[_index]["area"]))
	_area_name.text = (arena.display_name if arena != null else str(CARDS[_index]["area"])).to_upper()
	if _chip_a != null:
		var chip: Array = LeagueSummary.card(_league_state(str(CARDS[_index]["area"])))["chip"]
		_chip_a.text = str(chip[0])
		_chip_b.text = str(chip[1])
		_chip_b.visible = str(chip[1]) != ""
		_season_chip.visible = _open and _chip_a.text != ""
	for c in _stars.get_children():
		_stars.remove_child(c)
		c.free()
	var n := int(arena.title_stars) if arena != null else 1
	for i in maxi(n, 1):
		_stars.add_child(PixelIcon.new("icon_star", Vector2(27, 27)))
	var all_label: Label = _all_areas.find_child("AllAreasText", true, false) if _all_areas != null else null
	if all_label != null:
		all_label.text = "ALL AREAS · " + AreaArchiveCopy.open_count(App.level(), _archive_rows())
	_update_chevrons()
	_update_top_wash(arena)


## A bright sky (ArenaSet.top_wash): an ink gradient over the top of the
## chrome, right above the scrim, so the top bar and the zone stay legible.
func _update_top_wash(arena: ArenaSet) -> void:
	if _chrome == null:
		return
	var old: Node = _chrome.get_node_or_null("TopWash")
	if old != null:
		_chrome.remove_child(old)
		old.queue_free()
	var alpha := float(arena.top_wash) if arena != null else 0.0
	if alpha <= 0.0:
		return
	var wash := ShadowStyle.top_wash(alpha)
	_chrome.add_child(wash)
	var scrim: Node = _chrome.get_node_or_null("Scrim")
	_chrome.move_child(wash, scrim.get_index() + 1 if scrim != null else 0)


func has_top_wash() -> bool:
	return _chrome != null and _chrome.get_node_or_null("TopWash") != null


func headline() -> String:
	return _area_name.text


func star_count() -> int:
	return _stars.get_child_count()


# ---- the floating layer ----------------------------------------------------------


## Rebuild the float for the open tab: MATCH → the compact loadout strip;
## CARDS → the full loadout; TABLE → your spot; SCHED → coming up; STATS →
## this season. Nothing while the home block shows.
func _rebuild_float() -> void:
	if _float == null:
		return
	for c in _float.get_children():
		_float.remove_child(c)
		c.free()
	if not _open or _league == null:
		return
	var doc := App.league_doc(_league.league_id)
	if doc.is_empty():
		return
	match _league.current_tab():
		"HEAT":
			_float_strip()
		"CARDS":
			_float_loadout()
		"TABLE":
			_float_spot(doc)
		"SCHED":
			_float_upcoming(doc)
		"STATS":
			_float_season(doc)


func _float_box(y: float, gap: int, right := MARGIN) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "FloatBox"
	box.position = Vector2(MARGIN, y)
	box.size = Vector2(720 - MARGIN - right, 0)
	box.add_theme_constant_override("separation", gap)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float.add_child(box)
	return box


func _float_text(text: String, size_ := 16, color := RetroTheme.SCENE_TEXT, display := false) -> Label:
	var l := UiFont.label(text, size_, color, UiFont.display() if display else UiFont.body_bold())
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	return l


## MATCH: three thumbnails and "LOADOUT · n OF 3 SET"; tap → CARDS · LOADOUT.
func _float_strip() -> void:
	var slots: Array = App.loadout_slots(_league.league_id)
	var b := Button.new()
	b.name = "LoadoutStrip"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = Vector2(MARGIN, STRIP_Y)
	b.size = Vector2(720 - 2 * MARGIN, 60)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: _league.go_loadout())
	_float.add_child(b)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var set_n := 0
	for id in slots:
		var card := CardDefs.get_card(str(id)) if id != null else {}
		if card.is_empty():
			row.add_child(ModeCards.empty_slot(Vector2(42, 56), 16, 2.0))
		else:
			set_n += 1
			row.add_child(ModeCards.art(card, Vector2(42, 56), 4.0))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(_float_text("LOADOUT", 16, RetroTheme.SCENE_TEXT, true))
	var set_l := _float_text("%d OF %d SET" % [set_n, slots.size()])
	set_l.name = "SetLine"
	col.add_child(set_l)


## CARDS: the equipped cards full size with their names; tap one to unequip it.
func _float_loadout() -> void:
	var slots: Array = App.loadout_slots(_league.league_id)
	var box := _float_box(LOADOUT_Y, 14)
	box.name = "Loadout"
	var set_n := 0
	for id in slots:
		if id != null:
			set_n += 1
	box.add_child(_float_text("LEAGUE LOADOUT · %d OF %d" % [set_n, slots.size()]))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 12)
	names.size_flags_vertical = Control.SIZE_SHRINK_END
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in slots.size():
		var id: Variant = slots[i]
		var card := CardDefs.get_card(str(id)) if id != null else {}
		if card.is_empty():
			row.add_child(ModeCards.empty_slot(Vector2(96, 128), 24, 3.0))
			names.add_child(_float_text("SLOT %d EMPTY" % (i + 1), 16, RetroTheme.SCENE_MUTED))
		else:
			var art := ModeCards.art(card, Vector2(96, 128), 6.0, true)
			art.name = "Slot_%d" % i
			var slot: int = i
			var lid := _league.league_id
			(art.get_meta("button") as TextureButton).pressed.connect(func() -> void:
				App.unequip_card(slot, lid)
				_league.refresh()
			)
			row.add_child(art)
			var usable := Progression.can_use(App.level(), card)
			var nm := str(card.get("name", id)).to_upper() + ("" if usable else " · LVL %d" % Progression.card_level(card))
			names.add_child(_float_text(nm, 16, RetroTheme.SCENE_TEXT if usable else RetroTheme.SCENE_MUTED))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(10, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)
	row.add_child(names)


## TABLE: YOUR SPOT — the big ordinal, the record and games back, the line.
func _float_spot(doc: Dictionary) -> void:
	var sp := LeagueSummary.spot(doc, _league.cfg)
	var box := _float_box(FLOAT_Y, 14)
	box.name = "Spot"
	box.add_child(_float_text(str(sp["cap"])))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var big := _float_text(str(sp["big"]), 80, RetroTheme.SCENE_TEXT, true)
	big.name = "Big"
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(big)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(_float_text(str(sp["line1"]), 16, RetroTheme.SCENE_TEXT, true))
	col.add_child(_float_text(str(sp["line2"]), 16, LeagueContext.HI))


## SCHED: COMING UP — the next three games as cards, today's in gold.
func _float_upcoming(doc: Dictionary) -> void:
	var box := _float_box(FLOAT_Y, 14, 42)
	box.name = "Upcoming"
	box.add_child(_float_text("COMING UP"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18 - int(ShadowStyle.OFFSET))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var games := LeagueSummary.upcoming(doc, _league.cfg, 3)
	for i in games.size():
		var u: Dictionary = games[i]
		var first := i == 0 and str(u["day"]) != ""
		var line := RetroTheme.c("gold") if first else RetroTheme.SCENE_TEXT
		var card := ShadowPanel.new(line, 0.0, 0.30 if first else 0.18, 16.0)
		card.name = "Up_%d" % i
		card.shadow = Color(RetroTheme.SCENE_TEXT, ShadowStyle.SHADOW_ALPHA)
		card.custom_minimum_size = Vector2(0, 112 + ShadowStyle.OFFSET)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 12)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(col)
		col.add_child(_float_text(str(u["day"]), 16, RetroTheme.SCENE_TEXT, true))
		col.add_child(_float_text(str(u["name"])))
		col.add_child(_float_text(str(u["tag"]), 16, LeagueContext.HI))
		row.add_child(card)


## STATS: THIS SEASON — record, high points, streak.
func _float_season(doc: Dictionary) -> void:
	var box := _float_box(FLOAT_Y, 18)
	box.name = "Season"
	box.add_child(_float_text("THIS SEASON"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 56)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	for k in LeagueSummary.season_stats(doc):
		row.add_child(ModeCards.stat(str(k["v"]), str(k["l"]), 48, 14))


# ---- data ------------------------------------------------------------------------


func _best(area: String) -> int:
	var best := SaveService.top_scores(1, area)
	return int(best[0]["score"]) if not best.is_empty() else 0


func _league_state(area: String) -> Dictionary:
	for st in App.league_states():
		if st["league"]["location"] == area:
			return st
	return {}


func _refresh_ticker() -> void:
	var bests := []
	for card in CARDS:
		var arena := CosmeticLibrary.get_arena(str(card["area"]))
		bests.push_back({"name": arena.display_name if arena != null else str(card["area"]), "best": _best(str(card["area"]))})
	var next_up := ""
	var st := _league_state(str(CARDS[_index]["area"]))
	if not st.is_empty() and not Dictionary(st["doc"]).is_empty():
		var opp := Campaign.next_opponent(st["doc"])
		if opp != "":
			next_up = str(LeagueData.shooter(opp).get("name", ""))
	_ticker.set_items(HomeTicker.items_from(bests, App.league_states(), App.tickets(), next_up, App.xp()))
	if _badge != null:
		_badge.set_level(App.level(), Progression.frac_for(App.xp()))


# ---- actions ---------------------------------------------------------------------


func _pick(mode: String) -> void:
	if _switching:
		return
	App.home_card = _index
	var area := str(CARDS[_index]["area"])
	if not App.area_unlocked(area):
		return
	if mode == "league":
		_open_league()
	else:
		App.start_area(mode, area)


var _locker: LockerPanel


func _open_locker() -> void:
	if _locker != null or _settings != null or _switching:
		return
	_locker = LockerPanel.new()
	_locker.name = "LockerPanel"
	_locker.closed.connect(func() -> void:
		_locker = null
		var icon: IconButton = _chrome.find_child("Locker", true, false) if _chrome != null else null
		if icon != null:
			icon.badge = not App.unseen_balls().is_empty()
	)
	add_child(_locker)


func _open_settings() -> void:
	if _settings != null or _switching:
		return
	_settings = SettingsPanel.new()
	_settings.name = "SettingsPanel"
	_settings.closed.connect(func() -> void: _settings = null)
	_settings.dark_mode_changed.connect(func(_on: bool) -> void: rebuild_chrome())
	add_child(_settings)


# ---- the area archive --------------------------------------------------------------


func _archive_rows() -> Array:
	return AreaArchiveCopy.rows(App.level(), App.league_states(), AreaArchiveCopy.bests(), App.league_gating, App.visited_areas())


## The page before an area's home (docs/HOME.md → Area archive). `instant`
## on a cold launch: no slide, and no `<` when the area behind is locked.
func _open_archive(instant := false) -> void:
	if _archive != null or _locker != null or _settings != null or _switching:
		return
	var rows := _archive_rows()
	_archive = AreaArchivePage.new()
	_archive.name = "AreaArchive"
	var here := str(CARDS[_index]["area"])
	_archive.build(rows, AreaArchiveCopy.open_count(App.level(), rows), App.area_unlocked(here))
	_archive.closed.connect(func() -> void: _archive = null)
	_archive.picked.connect(_go_area)
	add_child(_archive)
	if not instant:
		_archive.slide_in()


func archive() -> AreaArchivePage:
	return _archive


## Land on an area's home from the archive: the page's ink hands over to
## the title's cover, the court rebuilds underneath, the cover lifts.
func _go_area(id: String) -> void:
	var i := AreaArchiveCopy.index_of(id)
	if i < 0 or not App.area_unlocked(id) or _switching:
		return
	_switching = true
	_cover.color = Color(RetroTheme.c("ink"), 1.0)
	if _archive != null:
		_archive.queue_free()
		_archive = null
	if i != _index:
		_index = i
		App.home_card = _index
		_build_court(_index)
		_update_zone()
		_fill_cards()
		_refresh_ticker()
	var back := create_tween()
	back.tween_property(_cover, "color:a", 0.0, FADE_S * 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await back.finished
	_switching = false
