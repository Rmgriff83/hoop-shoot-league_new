extends Node
## Automated visual-QA driver. Inert unless launched with `-- --qa`:
##   Godot --path . --resolution 360x640 -- --qa
## Plays the real game through the real input pipeline: clicks the title
## button, performs a spread of flick gestures, saves viewport screenshots to
## user://qa/, prints every outcome, and quits from the results screen.
## Assumes the window is exactly 360x640 (canvas_items stretch → viewport
## 720x1280, scale 0.5), so gesture math lives in window coordinates.

const WIN := Vector2(360, 640)

var _outcomes: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not (args.has("--qa") or args.has("--qa-aim") or args.has("--qa-beach") or args.has("--qa-title") or args.has("--qa-results") or args.has("--qa-heat-result") or args.has("--qa-hud") or args.has("--qa-heat") or args.has("--qa-cards") or args.has("--qa-city") or args.has("--qa-peggy")):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa"))
	if args.has("--qa-title"):
		_run_title.call_deferred()
	elif args.has("--qa-results"):
		_run_results.call_deferred()
	elif args.has("--qa-heat-result"):
		_run_heat_result.call_deferred()
	elif args.has("--qa-hud"):
		_run_hud.call_deferred()
	elif args.has("--qa-heat"):
		_run_heat.call_deferred()
	elif args.has("--qa-cards"):
		_run_cards.call_deferred()
	elif args.has("--qa-beach"):
		_run_beach.call_deferred()
	elif args.has("--qa-city"):
		_run_city.call_deferred()
	elif args.has("--qa-peggy"):
		_run_peggy.call_deferred()
	elif args.has("--qa-aim"):
		_run_aim.call_deferred()
	else:
		_run.call_deferred()


func _run() -> void:
	await _sleep(1.2)
	await _snap("01_title")
	await _click_button_named("TIME TRIAL")   # the cage card is the first page
	await _sleep(1.2)
	await _snap("02_countdown")
	await _sleep(2.2)  # countdown ends, GO fires

	_hook_trial()

	# Gesture spread: [speed_sh, travel_frac_of_window_h, tilt_px_per_step].
	# speed_sh ≈ window px/s ÷ window height (see header math).
	var specs := [
		[1.8, 0.28, 0.0], [1.9, 0.30, 0.0], [1.6, 0.26, 0.0], [2.1, 0.33, 0.0],
		[1.8, 0.29, 6.0], [1.85, 0.30, -6.0], [1.2, 0.18, 0.0], [2.8, 0.42, 0.0],
		[1.9, 0.31, 0.0], [1.75, 0.28, 0.0], [1.95, 0.32, 12.0], [1.8, 0.30, 0.0],
		[1.7, 0.27, 0.0], [2.0, 0.31, 0.0],
	]
	for i in specs.size():
		var s: Array = specs[i]
		await _flick(s[0], s[1], s[2])
		if i == 1:
			await _sleep(0.6)  # ~arc apex
			await _snap("03_flight")
		if i == 7:
			await _sleep(0.9)
			await _snap("04_action")
		if i == 11:  # ~40 s in — board mid-slide in the moving phase
			await _sleep(0.8)
			await _snap("06_moving")
		await _sleep(3.2)

	# Ride out the rest of the clock (~60s total run).
	var waited := 0.0
	while waited < 70.0 and not (get_tree().current_scene != null
			and get_tree().current_scene.scene_file_path.ends_with("results_screen.tscn")):
		await _sleep(1.0)
		waited += 1.0
	await _sleep(0.5)
	await _snap("05_results")
	print("QA stats: %s" % JSON.stringify(_stats))
	print("QA last_run: %s" % JSON.stringify(App.last_run))
	get_tree().quit(0)


## Results QA: the time-trial results page in two states without playing a
## run — a NEW BEST with tickets (the board's top row as this run), then a
## mid-board run that was iced (no tickets). Seeds App.last_run from the
## saved board (writes one score only when the board is empty).
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-results
func _run_results() -> void:
	await _sleep(0.6)
	var top := SaveService.top_scores(10, "cage")
	if top.is_empty():
		SaveService.put_score({"score": 24, "makes": 14, "attempts": 24, "swishes": 4, "bestStreak": 6, "bonus": 5, "iced": 0, "location": "cage"})
		top = SaveService.top_scores(10, "cage")
	App.next_mode = "trial"
	var best: Dictionary = top[0].duplicate()
	best["tickets"] = 30
	App.last_run = best
	App.last_run_was_best = true
	get_tree().change_scene_to_file(App.RESULTS_SCENE)
	await _sleep(1.2)
	await _snap("results_best")
	var mid: Dictionary = top[mini(3, top.size() - 1)].duplicate()
	mid["iced"] = 2
	mid["tickets"] = 0
	App.last_run = mid
	App.last_run_was_best = false
	get_tree().change_scene_to_file(App.RESULTS_SCENE)
	await _sleep(1.2)
	await _snap("results_iced")
	await _click_button_named("HOME")
	await _sleep(1.0)
	await _snap("results_home")
	print("QA results: done")
	get_tree().quit(0)


## Match QA: the league match HUD (design "League Match HUD") on a real cage
## league heat — the countdown, live play, the opponent's window minimized
## and back, then the pause menu and out.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-heat
func _run_heat() -> void:
	await _sleep(0.8)
	App.enter_league("cage")
	# Cards in the tray (design "Card Icons"): a Deep Freeze and a Heat Check
	# in the first two slots when they are empty (this touches the dev save).
	var loadout: Array = App.cards_bucket("cage").get("loadout", [null, null, null])
	for pair in [[0, "ice"], [1, "fire7"], [2, "vortex6"]]:
		if loadout[pair[0]] == null:
			App.add_card(str(pair[1]), 1, "cage")
			App.equip_card(int(pair[0]), str(pair[1]), "cage")
	App.start_league_heat()
	await _sleep(1.0)
	await _snap("heat_countdown")
	await _sleep(3.2)
	_hook_trial()
	await _flick(1.9, 0.30, 0.0)
	await _sleep(1.4)
	await _snap("heat_live")
	# Deal the first card: the face flies out under its caption.
	var card0: Control = get_tree().root.find_child("Card0", true, false)
	if card0 != null and card0.is_visible_in_tree():
		var c := (card0.global_position + Vector2(42, 56)) * 0.5
		_mouse_button(c, true)
		await _sleep(0.08)
		_mouse_button(c, false)
		await _sleep(0.45)
		await _snap("heat_deal")
	await _sleep(2.0)
	await _click_named("PipMin")
	await _sleep(0.5)
	await _snap("heat_pipmin")
	await _click_named("PipChip")
	await _sleep(0.5)
	await _click_named("PauseButton")
	await _sleep(0.5)
	await _snap("heat_pause")
	await _click_button_named("QUIT TO TITLE")
	await _sleep(1.2)
	print("QA heat: done")
	get_tree().quit(0)


## Click a button by node name (icon buttons carry no text).
func _click_named(node_name: String) -> void:
	var b: Button = get_tree().root.find_child(node_name, true, false)
	if b == null or not b.is_visible_in_tree():
		print("QA: no visible button named '%s'" % node_name)
		return
	var c := (b.global_position + b.size / 2.0) * 0.5
	_mouse_button(c, true)
	await _sleep(0.08)
	_mouse_button(c, false)
	print("QA click: %s" % node_name)


## HUD QA: the solo-mode HUD (design "Solo Modes HUD") — a trial's
## countdown, a live banner after a flick, the pause menu, then practice
## with the 30S MODE toggle off and on.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-hud
func _run_hud() -> void:
	await _sleep(1.2)
	await _click_button_named("TIME TRIAL")
	await _sleep(0.5)
	await _snap("hud_countdown")
	await _sleep(3.0)
	_hook_trial()
	await _flick(1.9, 0.30, 0.0)
	await _sleep(1.6)
	await _snap("hud_live")
	await _sleep(1.5)
	var pause: Button = get_tree().root.find_child("PauseButton", true, false)
	if pause != null:
		var c := (pause.global_position + pause.size / 2.0) * 0.5
		_mouse_button(c, true)
		await _sleep(0.08)
		_mouse_button(c, false)
		await _sleep(0.5)
		await _snap("hud_pause")
		await _click_button_named("QUIT TO TITLE")
		await _sleep(1.5)
	await _click_button_named("PRACTICE")
	await _sleep(1.2)
	await _snap("hud_practice")
	var thirty: Button = get_tree().root.find_child("ThirtyButton", true, false)
	if thirty != null:
		var c2 := (thirty.global_position + thirty.size / 2.0) * 0.5
		_mouse_button(c2, true)
		await _sleep(0.08)
		_mouse_button(c2, false)
		await _sleep(0.4)
		await _snap("hud_practice30")
	print("QA hud: done")
	get_tree().quit(0)


## Post-match QA: the league post-match page in three states without
## playing a heat — a win in overtime with a card drop, a loss without one,
## and a heat outside a league (HOME only). Seeds App.last_heat against the
## cage campaign (created if missing).
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-heat-result
func _run_heat_result() -> void:
	await _sleep(0.6)
	App.enter_league("cage")
	var opp := LeagueData.shooter("brickport")
	var base := {"won": true, "player_score": 44, "ai_score": 42, "ot": 1, "opponent": opp, "mode": "heat", "location": "cage",
		"league": {"id": "cage", "game": "d1", "playoff": false}, "coins": 50, "tickets": 28, "card_drop": "fire7",
		"xp": {"gained": 30, "level_before": 1, "level_after": 2},
		"sides": {"player": {"makes": 19, "attempts": 30, "swishes": 7, "bestStreak": 6, "bonus": 7, "iced": 0},
			"ai": {"makes": 18, "attempts": 31, "swishes": 6, "bestStreak": 6, "bonus": 7, "iced": 0}}}
	App.last_heat = base
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(1.2)
	await _snap("heat_win")
	var loss := base.duplicate(true)
	loss["won"] = false
	loss["player_score"] = 33
	loss["ai_score"] = 36
	loss["ot"] = 0
	loss["coins"] = 15
	loss["tickets"] = 11
	loss["card_drop"] = ""
	loss["xp"] = {"gained": 4, "level_before": 2, "level_after": 2}
	loss["sides"]["player"] = {"makes": 14, "attempts": 25, "swishes": 5, "bestStreak": 4, "bonus": 3, "iced": 1}
	loss["sides"]["ai"] = {"makes": 16, "attempts": 26, "swishes": 5, "bestStreak": 8, "bonus": 9, "iced": 0}
	App.last_heat = loss
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(1.2)
	await _snap("heat_loss")
	var quick := base.duplicate(true)
	quick["league"] = null
	quick["card_drop"] = ""
	App.last_heat = quick
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(1.2)
	await _snap("heat_quick")
	print("QA heat result: done")
	get_tree().quit(0)


## Card icons QA (design "Card Icons" 9a / 10a): the animated faces at every
## size the game uses, the chips, the tray tags and the deal caption, on the
## cage carpet. Snaps frame 0, frame 5 (pinned) and the live loop.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-cards
## (Vortex is a real card now — data/cards.json.)


func _run_cards() -> void:
	await _sleep(0.6)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/textures/cage_carpet.png")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(28, 40)
	col.add_theme_constant_override("separation", 26)
	layer.add_child(col)
	var faces: Array[CardFace] = []
	for card in [CardDefs.get_card("ice"), CardDefs.get_card("fire7"), CardDefs.get_card("vortex6")]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 24)
		for sz in [Vector2(84, 112), Vector2(96, 128), Vector2(120, 160), Vector2(168, 224)]:
			var holder := ModeCards.art(card, sz, 6.0)
			holder.size_flags_vertical = Control.SIZE_SHRINK_END
			row.add_child(holder)
			faces.push_back(holder.get_node("Face") as CardFace)
		col.add_child(row)
	# The chips, the tray tags, the deal caption.
	var last := HBoxContainer.new()
	last.add_theme_constant_override("separation", 28)
	last.alignment = BoxContainer.ALIGNMENT_CENTER
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for card in [CardDefs.get_card("ice"), CardDefs.get_card("fire7"), CardDefs.get_card("vortex6"), {}]:
		var chip := ModeCards.chip(card)
		chips.add_child(chip)
		if chip is ModeCards.Chip:
			faces.push_back(chip.get_node("Sprite") as CardFace)
	last.add_child(chips)
	var heat_script: GDScript = load("res://game/screens/heat_screen.gd")
	var wait_card: Control = heat_script.TrayCard.new(CardDefs.get_card("ice"), Vector2(84, 112))
	wait_card.set_state("wait", "WAIT")
	last.add_child(wait_card)
	faces.push_back(wait_card.face)
	var fire_card: Control = heat_script.TrayCard.new(CardDefs.get_card("fire7"), Vector2(84, 112))
	fire_card.set_state("fire", "5S")
	last.add_child(fire_card)
	faces.push_back(fire_card.face)
	col.add_child(last)
	var cap := ShadowPanel.new(LeagueContext.BLUE, 0.0, 0.30, 18.0)
	cap.custom_minimum_size = Vector2(0, 50 + ShadowStyle.OFFSET)
	cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 14)
	var glyph := TextureRect.new()
	glyph.texture = load("res://assets/ui/cards/glyph_ice.png")
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_SCALE
	glyph.custom_minimum_size = Vector2(42, 42)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crow.add_child(glyph)
	for part in [["DEEP FREEZE", 16], [">", 24], ["OLLIE", 16]]:
		var l := RetroTheme.on_scene(UiFont.label(str(part[0]), int(part[1]), RetroTheme.SCENE_TEXT, UiFont.display())) as Label
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crow.add_child(l)
	cap.add_child(crow)
	col.add_child(cap)
	await _sleep(0.5)
	for f in faces:
		f.set_frame(0)
	await _sleep(0.2)
	await _snap("cards_f0")
	for f in faces:
		f.set_frame(5)
	await _sleep(0.2)
	await _snap("cards_f5")
	for f in faces:
		f.set_frame(-1)
	await _sleep(0.7)
	await _snap("cards_live")
	print("QA cards: done")
	get_tree().quit(0)


## Beach QA: stand on the beach court and snapshot it over ~40 s.
##
## The beach had NO qa mode at all before this — `--qa` and `--qa-aim` both go
## to the cage — so there was no way to review the arena without a phone. The
## long dwell is the point: the ambient life (passers-by, gulls, the ship, the
## plane) is on timers of 10-140 s, so a single frame proves nothing.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-beach
func _run_beach() -> void:
	await _sleep(1.2)
	await _click_button_named(">")           # page to the beach card
	await _sleep(1.0)                         # the page turn (fade + slide)
	await _click_button_named("TIME TRIAL")
	await _sleep(4.4)             # countdown, then GO
	for i in 9:
		await _snap("beach_%02d" % i)
		await _sleep(4.5)
	await _snap("beach_last")
	print("QA beach: done")
	get_tree().quit(0)


## City QA: the third home page (the city card, stars, the lock or the league),
## then the city time trial over ~45 s so cars cross the street, the trees
## and windows show, and the spot shuffle lands.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-city
func _run_city() -> void:
	await _sleep(1.2)
	await _click_button_named(">")
	await _sleep(1.0)
	await _click_button_named(">")           # page to the city card
	await _sleep(1.0)
	await _snap("city_home")
	App.start_mode("trial_city")             # straight in (the dev save may be under level 5)
	await _sleep(4.4)
	for i in 10:
		await _snap("city_%02d" % i)
		await _sleep(4.5)
	await _snap("city_last")
	var fx: Node = get_tree().root.find_child("CityFx", true, false)
	if fx != null:
		print("QA city: cars sent %d, on the road %d, windows %d" % [fx.sent(), fx.car_count(), fx.window_count()])
	print("QA city: done")
	get_tree().quit(0)


## Home QA: the cage card over its slow pan (frames at 0 / 5 / 10 / 14 s of a
## 28 s truck), then a page turn to the beach card.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-title
## PEGGY (docs/LOCKER.md): open the locker from the title, aim, hold the
## button through a drop, the prize card, the BALLS tab, the badge. Grants
## tickets first and restores the save's cosmetics/settings after.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-peggy
func _run_peggy() -> void:
	await _sleep(1.0)
	var cos_before: Dictionary = SaveService.get_cosmetics()
	var set_before: Dictionary = SaveService.get_settings()
	App.grant_tickets(1200)
	var locker: Button = get_tree().root.find_child("Locker", true, false)
	if locker == null:
		print("QA: no Locker button")
		return
	var lc := (locker.global_position + locker.size / 2.0) * 0.5
	_mouse_button(lc, true)
	await _sleep(0.08)
	_mouse_button(lc, false)
	await _sleep(0.8)
	await _snap("peggy_open")
	var panel: LockerPanel = get_tree().root.find_child("LockerPanel", true, false)
	var m: PeggyMachine = panel.machine() if panel != null else null
	if m == null:
		print("QA: no machine")
		return
	m.set_aim(-0.8)
	await _sleep(0.6)
	await _snap("peggy_aim")
	m.press()
	await _sleep(0.35)
	await _snap("peggy_hold")
	await _sleep(0.5)
	await _snap("peggy_drop_a")
	await _sleep(0.9)
	await _snap("peggy_drop_b")
	var waited := 0.0
	while panel.prize_card() == null and waited < 8.0:
		await _sleep(0.2)
		waited += 0.2
	await _sleep(0.3)
	await _snap("peggy_card")
	var again: Button = get_tree().root.find_child("Again", true, false)
	if again != null:
		again.pressed.emit()
	await _sleep(0.4)
	# A second drop from the centre, then the BALLS tab and the title badge.
	m.set_aim(0.0)
	m.press()
	waited = 0.0
	while panel.prize_card() == null and waited < 8.0:
		await _sleep(0.2)
		waited += 0.2
	await _snap("peggy_card_2")
	var keep: Button = get_tree().root.find_child("Keep", true, false)
	if keep != null:
		keep.pressed.emit()
	await _sleep(0.3)
	# The epic page, staged (a real epic needs level 3 and luck).
	panel._show_card({"slot": 0, "base": "epic", "rarity": "epic", "ball_id": "tiger", "refund": 0,
		"owned_after": 4, "result": {}})
	await _sleep(0.6)
	await _snap("peggy_epic")
	panel._dismiss_card()
	await _sleep(0.2)
	await _click_button_named("CLOSE")
	await _sleep(0.5)
	await _snap("peggy_badge")
	_mouse_button(lc, true)
	await _sleep(0.08)
	_mouse_button(lc, false)
	await _sleep(0.6)
	panel = get_tree().root.find_child("LockerPanel", true, false)
	if panel != null:
		panel.show_tab("BALLS")
	await _sleep(0.5)
	await _snap("peggy_balls")
	await _click_button_named("CLOSE")
	await _sleep(0.3)
	# Dark mode: both tabs must stay readable.
	var was_dark: bool = App.dark_mode
	App.set_dark_mode(true)
	await _sleep(0.6)
	locker = get_tree().root.find_child("Locker", true, false)
	if locker != null:
		lc = (locker.global_position + locker.size / 2.0) * 0.5
		_mouse_button(lc, true)
		await _sleep(0.08)
		_mouse_button(lc, false)
		await _sleep(0.6)
		await _snap("peggy_dark")
		panel = get_tree().root.find_child("LockerPanel", true, false)
		if panel != null:
			panel.show_tab("BALLS")
		await _sleep(0.4)
		await _snap("peggy_dark_balls")
		await _click_button_named("CLOSE")
		await _sleep(0.3)
	App.set_dark_mode(was_dark)
	SaveService.put_cosmetics(cos_before)
	SaveService.put_settings(set_before)
	get_tree().quit()


func _run_title() -> void:
	await _sleep(1.0)
	for i in 4:
		await _snap("title_cage_%02d" % i)
		if i < 3:
			await _sleep(5.0 if i < 2 else 4.0)
	# The press state: hold the LEAGUE card, snap, release off it (no open).
	var card: Button = get_tree().root.find_child("LeagueCard", true, false)
	if card != null:
		var pc := (card.global_position + Vector2(160, 60)) * 0.5
		_mouse_button(pc, true)
		await _sleep(0.25)
		await _snap("title_press")
		_mouse_move(Vector2(2, 2), Vector2(2, 2) - pc)   # drag off the card: releasing there does not open it
		await _sleep(0.1)
		_mouse_button(Vector2(2, 2), false)
		await _sleep(0.4)
	await _click_button_named(">")
	await _sleep(1.2)
	await _snap("title_beach_00")
	await _sleep(6.0)
	await _snap("title_beach_01")
	await _click_button_named("<")
	await _sleep(1.2)
	await _snap("title_cage_back")
	# The league in context: open it, walk the tabs, close it.
	await _click_button_named("LEAGUE")
	await _sleep(0.8)
	await _snap("title_league_heat")
	for tab in ["TABLE", "SCHED", "CARDS", "STATS"]:
		await _click_button_named(tab)
		await _sleep(0.6)
		await _snap("title_league_" + tab.to_lower())
	await _click_button_named("<")
	await _sleep(0.8)
	# The locker (an IconButton has no text: click it by name).
	var locker: Button = get_tree().root.find_child("Locker", true, false)
	if locker != null:
		var lc := (locker.global_position + locker.size / 2.0) * 0.5
		_mouse_button(lc, true)
		await _sleep(0.08)
		_mouse_button(lc, false)
		await _sleep(0.5)
		await _snap("title_locker")
		await _click_button_named("CLOSE")
		await _sleep(0.3)
	# The menu (a HamburgerButton has no text: click it by name).
	var menu: Button = get_tree().root.find_child("Menu", true, false)
	if menu != null:
		var c := (menu.global_position + menu.size / 2.0) * 0.5
		_mouse_button(c, true)
		await _sleep(0.08)
		_mouse_button(c, false)
		await _sleep(0.5)
		await _snap("title_settings")
		await _click_button_named("CLOSE")
		await _sleep(0.3)
	# Dark mode: flip the setting and rebuild the chrome in place.
	App.set_dark_mode(true)
	var home := get_tree().current_scene
	if home != null and home.has_method("rebuild_chrome"):
		home.call("rebuild_chrome")
	await _sleep(0.6)
	await _snap("title_dark")
	# The league in the dark palette (its tabs rebuild with the chrome).
	await _click_button_named("ENTER")
	await _sleep(0.8)
	await _snap("title_dark_league")
	await _click_button_named("TABLE")
	await _sleep(0.6)
	await _snap("title_dark_table")
	await _click_button_named("<")
	await _sleep(0.8)
	App.set_dark_mode(false)
	if home != null and home.has_method("rebuild_chrome"):
		home.call("rebuild_chrome")
	print("QA title: done")
	get_tree().quit(0)


## Aim QA: one REAL wind-up — press, pull DOWN in steps snapshotting at
## each depth, then flick up.
##
## The main --qa spread cannot do this: its _flick() drags straight up from the
## press, so `_charge` never accumulates and every one of its gestures fires at
## the minimum arc (19°), which no flick strength can make. This mode is the
## only thing that exercises the wind-up, and therefore the aim arrow.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-aim
func _run_aim() -> void:
	App.set_shot_help(App.SHOT_HELP_FULL)   # the whole point of this pass
	await _sleep(1.2)
	await _click_button_named("TIME TRIAL")   # on the cage card
	await _sleep(4.4)             # countdown, then GO

	# A full wind-up is FlickTuning.pull_full_frac (0.32) of the VIEWPORT
	# height; this window is half the viewport, so the same fraction of WIN.y.
	var full := 0.32 * WIN.y
	var start := Vector2(WIN.x / 2.0, WIN.y * 0.58)  # inside the grab zone
	_mouse_button(start, true)
	await _sleep(0.12)
	var pos := start
	var steps := 8
	for i in steps:
		var f := float(i + 1) / float(steps)
		var next := start + Vector2(0.0, full * f)
		_mouse_move(next, next - pos)
		pos = next
		await _sleep(0.06)
		if i in [0, 1, 3, 5, 7]:
			await _snap("aim_pull%03d" % int(round(f * 100.0)))
	# Flick up and release.
	for s in 6:
		await _sleep(0.02)
		var next := pos + Vector2(0.0, -0.30 * WIN.y / 6.0)
		_mouse_move(next, next - pos)
		pos = next
	_mouse_button(pos, false)
	await _sleep(0.9)
	await _snap("aim_flight")
	print("QA aim: done")
	get_tree().quit(0)


var _stats := {}


## Snapshot the trial's stats on a poll — drain_events belongs to the screen.
func _hook_trial() -> void:
	var screen := get_tree().current_scene
	if screen == null or not "trial" in screen:
		print("QA: no trial on current scene!")
		return
	var input := screen.find_child("FlickInput", true, false)
	if input == null:
		print("QA: FlickInput not found!")
	else:
		input.grab_pressed.connect(func() -> void: print("QA sig: grab"))
		input.flick_released.connect(func(s: Dictionary) -> void:
			print("QA sig: release vel=(%.0f,%.0f) travel=(%.0f,%.0f)" % [
				s["vel_x"], s["vel_y"], s["travel_x"], s["travel_y"]]))
	var timer := Timer.new()
	timer.wait_time = 0.25
	# A weak ref: a captured node would log "lambda capture freed" when the
	# screen leaves the tree before the timer's last tick.
	var ref: WeakRef = weakref(screen)
	timer.timeout.connect(func() -> void:
		var live: Node = ref.get_ref()
		if live == null or not live.is_inside_tree():
			timer.stop()
			return
		var trial: TimeTrial = live.get("trial")
		_stats = {
			"attempts": trial.attempts, "makes": trial.makes,
			"swishes": trial.swishes, "score": trial.score,
			"best_streak": trial.best_streak, "phase": trial.phase,
		}
	)
	add_child(timer)
	timer.start()


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://qa/%s.png" % name_)
	print("QA snap " + name_)


func _click_first_button() -> void:
	var buttons := get_tree().root.find_children("*", "Button", true, false)
	if buttons.is_empty():
		print("QA: no button found!")
		return
	var b: Button = buttons[0]
	var center := (b.global_position + b.size / 2.0) * 0.5  # viewport → window coords
	_mouse_button(center, true)
	await _sleep(0.08)
	_mouse_button(center, false)


## Click the visible Button whose text contains `want` (case-insensitive).
## Matching by label rather than tree order, because "the first Button" is
## whatever the scene happens to build first — on the arena picker that is not
## the one you want.
func _click_button_named(want: String) -> void:
	var seen: Array[String] = []
	for node in get_tree().root.find_children("*", "Button", true, false):
		var b: Button = node
		if not b.is_visible_in_tree():
			continue
		# A card button carries its words in child Labels ("TIME\nTRIAL").
		var words := b.text
		for l in b.find_children("*", "Label", true, false):
			words += " " + str(l.text)
		words = words.replace("\n", " ")
		seen.append(words.strip_edges())
		if words.to_upper().contains(want.to_upper()):
			var center := (b.global_position + b.size / 2.0) * 0.5  # viewport → window
			_mouse_button(center, true)
			await _sleep(0.08)
			_mouse_button(center, false)
			print("QA click: %s" % words.strip_edges())
			return
	print("QA: no button matching '%s'; visible: %s" % [want, seen])


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)


func _mouse_move(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	# Touch emulation only synthesizes ScreenDrag from motion that reports a
	# held button — real drags set this automatically, injected ones must too.
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)


## One flick gesture in window coords: press low-center, drag up over several
## motion events at real-time cadence, release. speed_sh sets the drag rate;
## travel_frac the total length; tilt_step adds lateral px per motion step.
func _flick(speed_sh: float, travel_frac: float, tilt_step: float) -> void:
	var start := Vector2(WIN.x / 2.0, WIN.y * 0.88)
	var travel := travel_frac * WIN.y
	var px_per_s := speed_sh * WIN.y
	var dur := travel / px_per_s
	var steps := 6
	_mouse_button(start, true)
	var pos := start
	for s in steps:
		await _sleep(dur / steps)
		var next := start + Vector2(tilt_step * (s + 1), -travel * (s + 1) / steps)
		_mouse_move(next, next - pos)
		pos = next
	_mouse_button(pos, false)
