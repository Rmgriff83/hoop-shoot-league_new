extends Node3D
## Home: Ross's retro card chrome over a FULL-SCREEN live view of the current
## area (docs/HOME.md). The court (a real CourtGeometry, panned by TitlePan)
## is the page background under a mild scrim; on a CanvasLayer above it sit
## the top bar (LVL01 + meter, the locker icon, the coins pill, the menu),
## the AREA ZONE — the top two thirds: the difficulty and the area's name
## (with the ranks icon) at its top, big chevrons at the screen edges to page
## — the LEAGUE card with its status line, the TIME TRIAL / PRACTICE pair,
## and the ticker at the very bottom. No bottom nav (the phone's safe area
## would push one up). Cards are flat and sharp-cornered. Two palettes (RetroTheme,
## App.dark_mode) over one layout; the chrome rebuilds in place when the
## setting flips. One court lives at a time: a page turn covers the screen,
## rebuilds the court and refreshes the chrome.

const CARDS := [{"area": "cage", "mode": "practice"}, {"area": "beach", "mode": "beach"}]
const MARGIN := 36.0
const COLUMN_W := 648.0
const SCRIM_ALPHA := 0.25
const FADE_S := 0.2
const SWIPE_PX := 60.0
## The chrome's rows (design px). The area zone is the top two thirds over the
## court: the name under the top bar, the chevrons at mid-height.
const ZONE_Y := 160.0
const ZONE_H := 110.0
const CHEVRON_SIZE := Vector2(112, 176)
## Cards grow into the space the bottom nav used to take; the ticker sits at
## the very bottom. Chevrons centre in the gap between the zone and the cards.
const LEAGUE_H := 148.0
const PAIR_H := 176.0
const CARDS_Y := 1280.0 - HomeTicker.HEIGHT - 32.0 - (LEAGUE_H + 20.0 + PAIR_H)
const CHEVRON_Y := (ZONE_Y + ZONE_H + CARDS_Y) / 2.0 - CHEVRON_SIZE.y / 2.0

var _index := 0
var _t := 0.0
var _spec: Dictionary = {}
var _court: CourtGeometry
var _cam: Camera3D
var _ui: CanvasLayer
var _chrome: Control
var _cover: ColorRect
var _area_caps: Label
var _area_name: Label
var _cards_row: VBoxContainer
var _ticker: HomeTicker
var _settings: SettingsPanel
var _switching := false
var _drag_x := NAN


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
	rebuild_chrome()
	_ui.add_child(_cover)
	_build_court(_index)


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
	_court.set_ticker(TickerText.arcade_items(_best(card["area"])))
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
	var t := RetroTheme.current()
	_chrome = Control.new()
	_chrome.name = "Chrome"
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_chrome)
	_ui.move_child(_chrome, 0)

	# The scrim over the court; it also takes the horizontal swipe.
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(RetroTheme.LIGHT["ink"], SCRIM_ALPHA)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_swipe)
	_chrome.add_child(scrim)

	# Top bar.
	var badge := LevelBadge.new()
	badge.position = Vector2(MARGIN, 32)
	badge.set_level(1, 0.0)
	_chrome.add_child(badge)
	var locker := IconButton.new("locker")
	locker.name = "Locker"
	locker.position = Vector2(MARGIN + 170 + 12, 32)
	locker.pressed.connect(_open_locker)
	_chrome.add_child(locker)
	var menu := HamburgerButton.new()
	menu.name = "Menu"
	menu.position = Vector2(720 - MARGIN - HamburgerButton.SIZE, 32)
	menu.pressed.connect(_open_settings)
	_chrome.add_child(menu)
	var coins := CoinsPill.new()
	coins.set_coins(App.coins())
	coins.position = Vector2(720 - MARGIN - HamburgerButton.SIZE - 16 - 170, 32)
	coins.custom_minimum_size = Vector2(170, 56)
	_chrome.add_child(coins)

	# The area zone: the top two thirds over the court. The name and its
	# difficulty at the top, big chevrons at the screen edges to page.
	var zone := VBoxContainer.new()
	zone.name = "Zone"
	zone.position = Vector2(MARGIN, ZONE_Y)
	zone.size = Vector2(COLUMN_W, ZONE_H)
	zone.alignment = BoxContainer.ALIGNMENT_BEGIN
	zone.add_theme_constant_override("separation", 6)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(zone)
	# Left-aligned: the difficulty on top, the name big under it.
	_area_caps = RetroTheme.on_scene(RetroTheme.caps("", 16))
	_area_caps.name = "AreaTier"
	_area_caps.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	zone.add_child(_area_caps)
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 20)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(name_row)
	_area_name = RetroTheme.on_scene(RetroTheme.display("", 48))
	_area_name.name = "AreaName"
	_area_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_area_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(_area_name)
	var ranks := IconButton.new("ranks")
	ranks.name = "Ranks"
	ranks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(ranks)
	var soon := RetroTheme.on_scene(RetroTheme.caps("SOON", 16))
	soon.name = "RanksSoon"
	soon.visible = false
	soon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(soon)
	ranks.pressed.connect(func() -> void:
		soon.visible = true
		var tw := create_tween()
		tw.tween_interval(0.8)
		tw.tween_callback(func() -> void: soon.visible = false)
	)
	var prev := _chevron("<", -1)
	prev.position = Vector2(8, CHEVRON_Y)
	_chrome.add_child(prev)
	var next := _chevron(">", 1)
	next.position = Vector2(720 - 8 - CHEVRON_SIZE.x, CHEVRON_Y)
	_chrome.add_child(next)

	# The cards.
	_cards_row = VBoxContainer.new()
	_cards_row.name = "Cards"
	_cards_row.position = Vector2(MARGIN, CARDS_Y)
	_cards_row.size = Vector2(COLUMN_W, LEAGUE_H + 20 + PAIR_H)
	_cards_row.add_theme_constant_override("separation", 20)
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(_cards_row)
	_fill_cards()

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
		c.queue_free()
	var area := str(CARDS[_index]["area"])
	var league := ModeCards.league_card(_league_state(area))
	league.custom_minimum_size = Vector2(0, LEAGUE_H)
	league.pressed.connect(func() -> void: _pick("league"))
	_cards_row.add_child(league)
	var pair := HBoxContainer.new()
	pair.name = "Pair"
	pair.add_theme_constant_override("separation", 20)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_row.add_child(pair)
	var trial := ModeCards.trial_card(_best(area))
	trial.custom_minimum_size = Vector2(0, PAIR_H)
	trial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trial.pressed.connect(func() -> void: _pick("trial"))
	pair.add_child(trial)
	var practice := ModeCards.practice_card()
	practice.custom_minimum_size = Vector2(0, PAIR_H)
	practice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice.pressed.connect(func() -> void: _pick("practice"))
	pair.add_child(practice)


## A big edge chevron over the court: no panel, cream with an ink outline.
func _chevron(text: String, dir: int) -> Button:
	var b := Button.new()
	b.name = "Prev" if dir < 0 else "Next"
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = CHEVRON_SIZE
	b.add_theme_font_override("font", UiFont.display())
	b.add_theme_font_size_override("font_size", UiFont.snap(72))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	RetroTheme.on_scene(b)
	b.pressed.connect(func() -> void: _switch(dir))
	return b


func _update_zone() -> void:
	var arena := CosmeticLibrary.get_arena(str(CARDS[_index]["area"]))
	_area_name.text = (arena.display_name if arena != null else str(CARDS[_index]["area"])).to_upper()
	_area_caps.text = str(arena.title_tier).to_upper() if arena != null else ""


func headline() -> String:
	return _area_name.text


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
	_ticker.set_items(HomeTicker.items_from(bests, App.league_states(), App.coins(), next_up))


# ---- actions ---------------------------------------------------------------------


func _pick(mode: String) -> void:
	if _switching:
		return
	App.home_card = _index
	var area := str(CARDS[_index]["area"])
	if mode == "league":
		App.start_league(area)
	else:
		App.start_area(mode, area)


var _locker: LockerPanel


func _open_locker() -> void:
	if _locker != null or _settings != null or _switching:
		return
	_locker = LockerPanel.new()
	_locker.name = "LockerPanel"
	_locker.closed.connect(func() -> void: _locker = null)
	add_child(_locker)


func _open_settings() -> void:
	if _settings != null or _switching:
		return
	_settings = SettingsPanel.new()
	_settings.name = "SettingsPanel"
	_settings.closed.connect(func() -> void: _settings = null)
	_settings.dark_mode_changed.connect(func(_on: bool) -> void: rebuild_chrome())
	add_child(_settings)


## A horizontal drag on the scrim turns the page (cards above it take their taps).
func _on_swipe(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		if ev.pressed:
			_drag_x = ev.position.x
		elif not is_nan(_drag_x):
			var dx: float = ev.position.x - _drag_x
			_drag_x = NAN
			if dx <= -SWIPE_PX:
				_switch(1)
			elif dx >= SWIPE_PX:
				_switch(-1)


## Page turn: cover the screen, rebuild the court, refresh the chrome, uncover.
func _switch(dir: int) -> void:
	if _switching or CARDS.size() < 2:
		return
	_switching = true
	_cover.color = Color(RetroTheme.c("ink"), 0.0)
	var fade := create_tween()
	fade.tween_property(_cover, "color:a", 1.0, FADE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fade.finished
	_index = posmod(_index + dir, CARDS.size())
	App.home_card = _index
	_build_court(_index)
	_update_zone()
	_fill_cards()
	_refresh_ticker()
	var back := create_tween()
	back.tween_property(_cover, "color:a", 0.0, FADE_S * 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await back.finished
	_switching = false
