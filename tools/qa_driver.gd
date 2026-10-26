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
var _snap_suffix := ""   # --qa-ab=<levers> tags every snap of the run (beach_02@no_shadows)


func _ready() -> void:
	var args := _args()
	# `--qa-ab=no_shadows,no_fill` runs any QA pass with those CourtGeometry.ab levers on
	# (the perf A/B levers, docs/PERFORMANCE.md) — the before/after shots of a proposal.
	var ab := _arg_value(args, "--qa-ab=", "")
	if ab != "":
		for lever in ab.split(",", false):
			# `name` is a switch; `name=a:b` carries a value (the sky's cover thresholds, its tile offset).
			if "=" in str(lever):
				CourtGeometry.ab[str(lever).get_slice("=", 0)] = str(lever).get_slice("=", 1)
			else:
				CourtGeometry.ab[str(lever)] = true
		_snap_suffix = "@" + ab.replace(",", "+").replace("=", "_").replace(":", "-")
	# `--net=<id>` hangs that net everywhere for the run (any net on any hoop):
	# --qa-park-chain is --qa-park with the jack chain.
	for a in args:
		if str(a).begins_with("--net="):
			App.net_override = CosmeticLibrary.get_net(str(a).trim_prefix("--net="))
	if args.has("--qa-park-chain") and App.net_override == null:
		App.net_override = CosmeticLibrary.get_net("jack")
	if args.has("--qa-perf") or _has_prefixed(args, "--qa-perf="):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa"))
		App.to_title.call_deferred()
		_run_perf.call_deferred(args)
		return
	# --qa-hud-side: the HUD pass with HUD SIDE: RIGHT (the toasts and the note mirrored), then back.
	if args.has("--qa-hud-side"):
		App.set_hud_side("right")
	# `--qa-safe-top=118` plays a phone with a notch: every header drops under it.
	var safe := _arg_value(args, "--qa-safe-top=", "")
	if safe != "":
		UiLayout.set_safe_override(float(safe))
	# The first-shot tutorial (design 38a) would sit over every match a QA pass
	# enters: only --qa-tutorial wants it. A normal launch (no --qa flag at all)
	# keeps it — this autoload runs in every build, so the skip must not be the
	# default (Ross's phone never saw the tutorial, 2026-10-24).
	App.qa_skip_tutorial = skips_tutorial(args)
	# QA passes keep instant scene moves (their sleeps assume them); --qa-loading
	# exercises the loader and raises the screen at once.
	if App.loader != null:
		App.loader.instant = _has_prefixed(args, "--qa") and not args.has("--qa-loading")
		App.loader.force_show = args.has("--qa-loading")
	if not (args.has("--qa") or args.has("--qa-splash") or args.has("--qa-hud-side") or args.has("--qa-best") or args.has("--qa-tutorial") or args.has("--qa-unlock") or args.has("--qa-spots") or args.has("--qa-aim") or args.has("--qa-beach") or args.has("--qa-title") or args.has("--qa-results") or args.has("--qa-heat-result") or args.has("--qa-hud") or args.has("--qa-heat") or args.has("--qa-cards") or args.has("--qa-city") or args.has("--qa-park") or args.has("--qa-peggy") or args.has("--qa-match-end") or args.has("--qa-area-snaps") or args.has("--qa-archive") or args.has("--qa-net") or args.has("--qa-chain") or args.has("--qa-jack") or args.has("--qa-ladder") or args.has("--qa-wool") or args.has("--qa-rwb") or args.has("--qa-tattered") or args.has("--qa-loading") or args.has("--qa-net-thumbs") or args.has("--qa-ranks") or args.has("--qa-multi")):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa"))
	# The splash is the main scene now: every other pass starts from the title.
	if not args.has("--qa-splash"):
		App.to_title.call_deferred()
	if args.has("--qa-splash"):
		App.qa_fresh = true   # before the splash builds: NEW GAME, not CONTINUE
		_run_splash.call_deferred()
	elif args.has("--qa-unlock"):
		_run_unlock.call_deferred()
	elif args.has("--qa-spots"):
		_run_spots.call_deferred()
	elif args.has("--qa-title"):
		_run_title.call_deferred()
	elif args.has("--qa-results"):
		_run_results.call_deferred()
	elif args.has("--qa-heat-result"):
		_run_heat_result.call_deferred()
	elif args.has("--qa-hud-side"):
		_run_hud_side.call_deferred()
	elif args.has("--qa-best"):
		_run_best.call_deferred()
	elif args.has("--qa-tutorial"):
		_run_tutorial.call_deferred()
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
	elif args.has("--qa-park-chain"):
		_run_park.call_deferred()
	elif args.has("--qa-park"):
		_run_park.call_deferred()
	elif args.has("--qa-peggy"):
		_run_peggy.call_deferred()
	elif args.has("--qa-match-end"):
		_run_match_end.call_deferred()
	elif args.has("--qa-area-snaps"):
		_run_area_snaps.call_deferred()
	elif args.has("--qa-archive"):
		_run_archive.call_deferred()
	elif args.has("--qa-net"):
		_run_net.call_deferred()
	elif args.has("--qa-chain"):
		_run_chain.call_deferred()
	elif args.has("--qa-jack"):
		_run_net_style.call_deferred("jack")
	elif args.has("--qa-ladder"):
		_run_net_style.call_deferred("ladder")
	elif args.has("--qa-wool"):
		_run_net_style.call_deferred("wool")
	elif args.has("--qa-rwb"):
		_run_net_style.call_deferred("rwb")
	elif args.has("--qa-tattered"):
		_run_net_style.call_deferred("tattered")
	elif args.has("--qa-loading"):
		_run_loading.call_deferred()
	elif args.has("--qa-net-thumbs"):
		_run_net_thumbs.call_deferred()
	elif args.has("--qa-ranks"):
		_run_ranks.call_deferred()
	elif args.has("--qa-multi"):
		_run_multi.call_deferred()
	elif args.has("--qa-aim"):
		_run_aim.call_deferred()
	else:
		_run.call_deferred()


func _run() -> void:
	await _sleep(1.2)
	await _close_archive()
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
	await _snap("results_best")   # mid-stream: the tickets arcing into the box
	await _sleep(2.0)
	await _snap("results_best_done")   # the stream landed, the count full
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
	for pair in [[0, "ice"], [1, "fire7"], [2, "magnet6"]]:
		if loadout[pair[0]] == null:
			App.add_card(str(pair[1]), 1, "cage")
			App.equip_card(int(pair[0]), str(pair[1]), "cage")
	App.start_league_heat()
	await _sleep(0.9)
	await _click_button_named("READY")   # the pre-match pick (docs/CARDS.md § Drops) sits before the heat
	# The pre-match page counts down (design 37a) before the heat screen comes up: wait for it.
	for i in 40:
		var sc := get_tree().current_scene
		if sc != null and "heat" in sc:
			break
		await _sleep(0.5)
	await _sleep(0.6)
	await _snap("heat_countdown")
	await _sleep(3.2)
	_hook_trial()
	await _flick(1.9, 0.30, 0.0)
	await _sleep(1.4)
	await _snap("heat_live")
	await _pop_snaps("_ai_court", "heat_pop")
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
	# The Magnet (design "Magnet Card FX" 38b): deploy it from the tray (the
	# horseshoe pops up, the tag counts down), then a scripted near miss so
	# the bolt grabs the ball and drops it in.
	var hs: Node = get_tree().current_scene
	if hs != null and "heat" in hs:
		var heat: Heat = hs.heat
		# A level-1 dev save is not dealt the level-5 card: hand it over for the show.
		if not heat.hands[Heat.PLAYER].has("magnet6"):
			heat.hands[Heat.PLAYER].push_back("magnet6")
		if hs.has_method("_deploy"):
			hs.call("_deploy", 2, "magnet6")
		elif not heat.play_card(Heat.PLAYER, "magnet6"):
			print("QA: magnet refused")
		await _sleep(0.7)
		await _snap("heat_magnet_up")
		var near := _near_miss_launch(heat.player.geo)
		if not near.is_empty() and heat.player.pickup() and heat.player.release(near):
			var balls := heat.player.balls()
			var grab := float(balls[balls.size() - 1].magnet_grab_t) if not balls.is_empty() else -1.0
			print("QA magnet: near miss released, grab at %.2f s" % grab)
			await _sleep(maxf(grab, 0.0) + 0.2)
			await _snap("heat_magnet_pull")
			await _sleep(1.2)
			await _snap("heat_magnet_in")
		else:
			print("QA: no near-miss launch, or the pickup was refused")
	# The OVERTIME toast (design 4a), shown by hand: the pass never reaches OT.
	var hud_n: Hud = get_tree().root.find_child("Hud", true, false)
	if hud_n != null:
		var otc := HudCopy.ot_toast(1, 20)
		hud_n.toast(str(otc["title"]), str(otc["sub"]), "icon_stopwatch", Hud.GOLD)
		await _sleep(0.5)
		await _snap("heat_ot_toast")
		hud_n.hide_toast()
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


## A launch the magnet pulls: a miss that reaches the rim within 0.35 m of
## its centre on this geometry (the sweep the tests use).
func _near_miss_launch(g: SimGeometry) -> Dictionary:
	var plain := g.with_magnet(false)
	for a in range(48, 57, 2):
		var ideal: float = Ballistics.speed_for_angle(a, g.hoop_x, g.rise)
		for k in range(-8, 9):
			var launch := {"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k)}
			var p := ShotSim.run_shot(launch, true, plain)
			var reach := ShotSim.first_reach(p)
			if not p.made and float(reach["t"]) >= 0.0 and float(reach["hd"]) <= 0.35:
				return launch
	return {}


## Click a button by node name (icon buttons carry no text).
func _click_named(node_name: String) -> void:
	var b: Button = get_tree().root.find_child(node_name, true, false)
	if b == null or not b.is_visible_in_tree():
		print("QA: no visible button named '%s'" % node_name)
		return
	var c := _win_of(b)
	_mouse_button(c, true)
	await _sleep(0.08)
	_mouse_button(c, false)
	print("QA click: %s" % node_name)


## HUD QA: the solo-mode HUD (design "Solo Modes HUD") — a trial's
## countdown, a live banner after a flick, the pause menu, then practice
## with the 30S MODE toggle off and on.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-hud
## The net's swish (docs/BLENDER_101.md): a practice shot on the cage, then
## a burst of frames from the moment the net wakes — the wrap, the snap
## down, the whip back, the ring-down.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-net
## The chain net in the city (§29), the same burst: --qa-chain → chain_*.
func _run_net() -> void:
	await _run_net_in("net", false)


func _run_chain() -> void:
	await _run_net_in("chain", true)


## A bought chain style hung on the city through App.net_override (no save
## change): --qa-jack / --qa-ladder → jack_* / ladder_* snaps.
## The loading states (design "Loading States" 39a / 39b): from the splash,
## CONTINUE → the pressed button's LOADING state, the loading screen, home;
## then TIME TRIAL from home → the screen again on the way to the court.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-loading
func _run_loading() -> void:
	while App.loader != null and App.loader.busy():   # the driver's own startup move home
		await get_tree().process_frame
	await _sleep(1.0)
	get_tree().change_scene_to_file(App.SPLASH_SCENE)
	await _sleep(5.6)   # the neon sign lights, the buttons rise
	var primary: BaseButton = get_tree().root.find_child("Primary", true, false)
	if primary != null:
		var c := _win_of(primary)
		_mouse_move(c, Vector2.ZERO)
		_mouse_button(c, true)
		await _sleep(0.06)
		_mouse_button(c, false)
	await _sleep(0.05)
	await _snap("loading_button")
	await _sleep(0.6)
	await _snap("loading_screen")
	await _sleep(1.6)
	await _snap("loading_screen_tip")
	await _sleep(2.0)
	await _snap("loading_home")
	if App.loader != null:
		App.loader.instant = false
	App.start_area("trial", "beach")
	await _sleep(0.9)
	await _snap("loading_match")
	await _sleep(3.0)
	await _snap("loading_court")
	get_tree().quit()


func _run_net_style(style: String) -> void:
	var ns := CosmeticLibrary.get_net(style)
	App.net_override = ns
	await _run_net_in(style, ns != null and ns.kind == "chain")


## The locker's net thumbnails (docs/LOCKER.md → NETS): every style hung,
## a rim in its own viewport, saved to assets/textures/nets/thumbs/<id>.png
## (run --import afterwards so the locker can load them).
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-net-thumbs
func _run_net_thumbs() -> void:
	await _sleep(0.5)
	var out_dir := ProjectSettings.globalize_path("res://assets/textures/nets/thumbs")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for ns in CosmeticLibrary.nets():
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 256)
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		add_child(vp)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0, 0, 0, 0)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.85, 0.82, 0.78)
		e.ambient_light_energy = 0.55
		env.environment = e
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 35, 0)
		sun.light_energy = 1.3
		vp.add_child(sun)
		var rig := Node3D.new()
		vp.add_child(rig)
		# No rim: the locker shows the net alone (docs/LOCKER.md → NETS).
		var body := NetBodies.for_set(ns)
		rig.add_child(body)
		var sim := NetSim.new()
		rig.add_child(sim)
		sim.configure(CosmeticLibrary.get_hoop("chain") if ns.kind == "chain" else HoopSet.new())
		var lay := NetBodies.layout(ns.body_style())
		sim.setup_layout(body, lay, ns.kind)
		body.call("build", lay)
		body.sync(sim)
		var cam := Camera3D.new()
		cam.fov = 38.0
		vp.add_child(cam)
		cam.position = Vector3(0.16, 0.06, 0.88)
		cam.look_at(Vector3(0.0, -0.2, 0.0))
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, ns.id])
		img.save_png("user://qa/net_thumb_%s.png" % ns.id)
		print("QA net thumb %s (%d bones)" % [ns.id, body.bone_count()])
		vp.queue_free()
		await get_tree().process_frame
	print("QA net thumbs: done")
	get_tree().quit(0)


func _run_net_in(prefix: String, city: bool) -> void:
	await _sleep(1.2)
	var was_tuning: bool = App.tuning_mode
	if city:
		await _pick_area("city")
		App.start_mode("trial_city")
		await _sleep(3.0)
	else:
		await _close_archive()
		App.set_tuning_mode(true)   # the strip, with its NET page
		await _click_button_named("PRACTICE")
		await _sleep(1.5)
		await _snap("net_strip_flick")
		await _click_button_named("NET")
		await _sleep(0.3)
		await _snap("net_strip_net")
		await _click_button_named("+")
		await _sleep(0.2)
		await _snap("net_strip_plus")
		await _click_button_named("RESET")
		await _sleep(0.2)
		App.set_tuning_mode(was_tuning)
	# A synthetic swish: a ball dropped straight through the hoop's axis,
	# driven into the net sim beside the court's own stepping (no view ball;
	# this is about the cords), the kick at the rim plane, then a burst.
	var court: Node = get_tree().root.find_child("Court", true, false)
	var net: NetSim = court.net_sim if court != null else null
	if net == null:
		print("QA net: no net sim")
		get_tree().quit(1)
		return
	var geo: SimGeometry = court.geo
	var hoop := Vector3(geo.hoop_x, geo.hoop_y, geo.hoop_z)
	var y := hoop.y + 0.5
	var vy := -5.0
	var kicked := false
	var snapped := 0
	var t := 0.0
	var next_snap := 0.0
	while t < 1.6:
		var dt := 1.0 / 60.0
		if y > hoop.y - 0.7:
			var desc := {"pos": Vector3(hoop.x, y, hoop.z), "vel": Vector3(0, vy, 0), "spin": 12.0, "axis": Vector3(0, 0, 1), "radius": SimConstants.R_BALL}
			net.step(dt, [desc])
			if not kicked and y <= hoop.y:
				net.kick(Vector3(hoop.x, hoop.y, hoop.z), Vector3(0, vy, 0))
				kicked = true
		vy -= 9.81 * dt
		y += vy * dt
		t += dt
		if t >= next_snap and snapped < 14:
			await _snap("%s_%02d" % [prefix, snapped])
			snapped += 1
			next_snap = t + 0.08
		await get_tree().process_frame
	# Close-ups of the cotton net at rest: the hook loops from just above and
	# in front of the rim (nothing may show above the tube), then the diamonds
	# and knots from the player's side.
	for i in 120:
		net.step(1.0 / 60.0, [])
		await get_tree().process_frame
	var ccam: Camera3D = get_viewport().get_camera_3d()
	if ccam != null:
		ccam.global_position = hoop + Vector3(-0.62, 0.16, 0.30)
		ccam.look_at(hoop + Vector3(0.0, -0.03, 0.0))
		await _sleep(0.3)
		await _snap(prefix + "_hooks")
		ccam.global_position = hoop + Vector3(-0.75, -0.08, 0.45)
		ccam.look_at(hoop + Vector3(0.0, -0.2, 0.0))
		await _sleep(0.3)
		await _snap(prefix + "_close")
	var body: Node = get_tree().root.find_child("NetBody", true, false)
	if body != null:
		var extra := " %d links" % body.link_count() if body is ChainNet else ""
		print("QA %s: %s %d bones, %d surfaces, %d tris%s" % [prefix, body.name, body.bone_count(), body.surface_count(), body.tri_count(), extra])
	print("QA %s: done" % prefix)
	get_tree().quit(0)


## The first-shot tutorial (design 38a) over a cage time trial: every step
## mid-demo (tutorial_00..04), a live flick and its verdict (tutorial_result),
## LET'S PLAY and the countdown that follows (tutorial_countdown); the seen
## flag is put back as it was.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-tutorial
func _run_tutorial() -> void:
	var was_settings: Dictionary = SaveService.get_settings()
	var st := was_settings.duplicate(true)
	st["shotTutorialSeen"] = false
	SaveService.put_settings(st)
	await _sleep(1.2)
	for attempt in 3:
		await _close_archive()
		await _click_button_named("TIME TRIAL")
		await _sleep(0.5)
		var sc := get_tree().current_scene
		if sc != null and "trial" in sc:
			break
		await _sleep(0.8)
	await _sleep(1.0)
	await _snap("tutorial_00")
	var waits := [1.3, 1.95, 0.6, 1.2]   # mid-pull, the demo shot in the air, the legend, the ghost
	for i in 4:
		await _click_button_named("NEXT" if i < 3 else "NEXT")
		await _sleep(waits[i])
		await _snap("tutorial_%02d" % (i + 1))
	var tut: ShotTutorial = get_tree().root.find_child("ShotTutorial", true, false)
	print("QA tutorial: step %d live %s" % [tut.step_index() if tut != null else -1, str(tut != null and tut.live())])
	_hook_trial()
	# The flick reads honestly now (2026-10-25): shoot at the ideal for the pull's arc.
	var ideal := _ideal_sh(0.28)
	await _flick_windup(0.28, ideal)
	await _sleep(2.2)
	await _snap("tutorial_result")
	print("QA tutorial: verdict '%s' made %s (flick %.2f sh)" % [tut.result() if tut != null else "?", str(tut != null and tut.made()), ideal])
	if tut != null and not tut.made():
		# A miss: shoot again, a little either side of the ideal, until it drops.
		for k in 4:
			await _flick_windup(0.28, ideal * [0.95, 1.05, 0.9, 1.1][k])
			await _sleep(2.2)
			print("QA tutorial: retry %d verdict '%s'" % [k + 1, tut.result()])
			if tut.made():
				break
	await _click_button_named("LET'S PLAY")
	await _sleep(0.7)
	await _snap("tutorial_countdown")
	print("QA tutorial: seen after = %s" % str(App.shot_tutorial_seen()))
	SaveService.put_settings(was_settings)
	print("QA tutorial: done")
	get_tree().quit(0)


## The home's TIME TRIAL card after every way of leaving and coming back
## (Ross, 2026-10-24: "BEST n" showed on the first load and was gone after
## navigating away and back): prints the card's sub-line at each step.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-best
func _run_best() -> void:
	await _sleep(1.2)
	await _close_archive()
	_print_best("first load")
	var scene := get_tree().current_scene
	var menu: Button = get_tree().root.find_child("Menu", true, false)
	if menu != null:
		menu.pressed.emit()
		await _sleep(0.8)
		_print_best("settings open")
		await _click_button_named("CLOSE")
		await _sleep(0.8)
		_print_best("settings closed")
	var locker: Button = get_tree().root.find_child("Locker", true, false)
	if locker != null:
		locker.pressed.emit()
		await _sleep(0.8)
		await _click_button_named("CLOSE")
		await _sleep(0.8)
		_print_best("locker closed")
	# A whole scene away and back: practice, then QUIT TO TITLE's path.
	if scene != null and scene.has_method("_pick"):
		scene.call("_pick", "practice")
		await _sleep(2.5)
		App.to_title()
		await _sleep(2.0)
		await _close_archive()
		_print_best("back from practice")
	print("QA best: done")
	get_tree().quit(0)


func _print_best(when: String) -> void:
	var card: Button = get_tree().root.find_child("TrialCard", true, false)
	var top := SaveService.top_scores(1, "cage")
	print("QA best [%s]: card '%s' · top_scores(cage) %s · docs in memory %d" % [when, ModeCards.sub_text(card) if card != null else "(no TrialCard)", str(top[0]["score"]) if not top.is_empty() else "none", SaveService.score_count()])


## HUD SIDE: RIGHT (Ross, 2026-10-24): a cage trial with a toast up and the
## note at the bottom-right — hud_right_live, hud_right_toast — then the
## setting goes back to LEFT.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-hud-side
func _run_hud_side() -> void:
	await _sleep(1.2)
	for attempt in 3:
		await _close_archive()
		await _click_button_named("TIME TRIAL")
		await _sleep(0.5)
		var sc := get_tree().current_scene
		if sc != null and "trial" in sc:
			break
		await _sleep(0.8)
	await _snap("hud_right_countdown")
	await _sleep(3.3)
	_hook_trial()
	await _flick(1.9, 0.30, 0.0)
	await _sleep(1.6)
	await _snap("hud_right_live")
	var sc_t := get_tree().current_scene
	if sc_t != null and "_hud" in sc_t:
		(sc_t.get("_hud") as Hud).banner("NEXT: L ELBOW IN 3", Color.WHITE)
		await _sleep(0.6)
		await _snap("hud_right_toast")
	App.set_hud_side("left")
	print("QA hud-side: done")
	get_tree().quit(0)


func _run_hud() -> void:
	await _sleep(1.2)
	# The archive's slide-out can still be in flight on a cold launch: tap
	# TIME TRIAL until the trial screen is actually up (three tries).
	for attempt in 3:
		await _close_archive()
		await _click_button_named("TIME TRIAL")
		await _sleep(0.5)
		var sc := get_tree().current_scene
		if sc != null and "trial" in sc:
			break
		print("QA: TIME TRIAL tap %d did not open the trial, retrying" % (attempt + 1))
		await _sleep(0.8)
	await _snap("hud_countdown")
	await _sleep(3.0)
	_hook_trial()
	# GO: the cage's return arrows run their chase (ArcadeFx.chase()). hud_go
	# catches the real one; chase_00..02 restart it so the snaps land at known
	# moments (ramp steps lit, then down the deck).
	await _sleep(0.25)
	await _snap("hud_go")
	var screen_c := get_tree().current_scene
	if screen_c != null and "_court" in screen_c:
		(screen_c.get("_court") as CourtGeometry).arcade_chase()
		var afx_q: Node = get_tree().root.find_child("ArcadeFx", true, false)
		for i in 3:
			await _sleep([0.05, 0.45, 0.5][i])
			await _snap("chase_%02d" % i)
			if afx_q != null:
				var lits := []
				for st in afx_q.arrow_steps():
					lits.push_back("%.2f" % afx_q.arrow_lit(st))
				print("QA chase_%02d: lit per step %s" % [i, " ".join(lits)])
	await _flick(1.9, 0.30, 0.0)
	await _sleep(1.6)
	await _snap("hud_live")
	print("QA hud: " + _render_stats())
	# The level music note (bottom-left): on, then off again.
	var note: Button = get_tree().root.find_child("MusicButton", true, false)
	if note != null:
		note.pressed.emit()
	await _sleep(0.3)
	print("QA hud: music on = %s, track %s" % [str(App.music_on), Sfx.track_id()])
	await _snap("hud_music")
	if note != null:
		note.pressed.emit()
	await _sleep(0.3)
	print("QA hud: music off = %s, track '%s'" % [str(not App.music_on), Sfx.track_id()])
	# The TIME! chip (design 5a), shown by hand: the small toast at the top.
	var sc_t := get_tree().current_scene
	if sc_t != null and "_hud" in sc_t:
		(sc_t.get("_hud") as Hud).banner("TIME!", RetroTheme.LIGHT["orange"])
		await _sleep(0.5)
		await _snap("hud_toast")
	await _sleep(1.0)
	# Rim pops (design "Solo Modes HUD" 5a): a swish and an ON FIRE pop at
	# the rim, snapped through their 1.1 s life.
	await _pop_snaps("_court", "hud_pop")
	await _ramp_snaps()
	# The ball gate and the deck funnel up close (design 32a): the camera
	# parked beside the gate, then put back.
	var gcam: Camera3D = get_viewport().get_camera_3d()
	if gcam != null:
		var was := gcam.global_transform
		gcam.global_position = Vector3(3.6, 1.3, 0.9)
		gcam.look_at(Vector3(1.25, 0.3, 0.0))
		await _sleep(0.3)
		await _snap("cage_gate")
		gcam.global_transform = was
		await _sleep(0.2)
	var pause: Button = get_tree().root.find_child("PauseButton", true, false)
	if pause != null:
		var c := _win_of(pause)
		_mouse_button(c, true)
		await _sleep(0.08)
		_mouse_button(c, false)
		await _sleep(0.5)
		await _snap("hud_pause")
		await _click_button_named("QUIT TO TITLE")
		await _sleep(1.5)
	# The locker page (docs/LOCKER.md): the slide, BALLS, NETS by kind.
	var cos_before: Dictionary = SaveService.get_cosmetics()
	App.grant_cosmetic("net", "jack")
	App.grant_cosmetic("net", "wool")
	var locker_btn: Button = get_tree().root.find_child("Locker", true, false)
	if locker_btn != null:
		var lc := _win_of(locker_btn)
		_mouse_button(lc, true)
		await _sleep(0.08)
		_mouse_button(lc, false)
		await _sleep(0.15)
		await _snap("locker_slide")
		await _sleep(0.7)
		await _snap("locker_balls")
		var panel: LockerPanel = get_tree().root.find_child("LockerPanel", true, false)
		if panel != null:
			panel.show_tab("NETS")
			await _sleep(0.4)
			await _snap("locker_nets")
			panel.show_kind("chain")
			await _sleep(0.4)
			await _snap("locker_nets_chain")
			# The hang-it-where sheet for the jack chain, the park row tapped.
			panel.open_area_sheet("jack")
			await _sleep(0.3)
			var park_row: Button = panel.area_sheet().find_child("Area_park", true, false) if panel.area_sheet() != null else null
			if park_row != null:
				park_row.pressed.emit()
			await _sleep(0.3)
			await _snap("locker_net_sheet")
			panel.close_area_sheet()
			panel.close()
			await _sleep(0.6)
	SaveService.put_cosmetics(cos_before)
	await _click_button_named("PRACTICE")
	await _sleep(1.2)
	await _snap("hud_practice")
	var thirty: Button = get_tree().root.find_child("ThirtyButton", true, false)
	if thirty != null:
		var c2 := _win_of(thirty)
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
		"league": {"id": "cage", "game": "d1", "playoff": false}, "tickets": 36, "card_drop": "fire7",
		"xp": {"gained": 30, "level_before": 1, "level_after": 2},
		"sides": {"player": {"makes": 19, "attempts": 30, "swishes": 7, "bestStreak": 6, "bonus": 7, "iced": 0},
			"ai": {"makes": 18, "attempts": 31, "swishes": 6, "bestStreak": 6, "bonus": 7, "iced": 0}}}
	App.last_heat = base
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(0.9)
	await _snap("heat_win_stream")   # the tickets mid-flight (design 6b)
	await _sleep(3.4)   # past the stream and the XP fill: LEVEL UP in gold
	await _snap("heat_win")
	var loss := base.duplicate(true)
	loss["won"] = false
	loss["player_score"] = 33
	loss["ai_score"] = 36
	loss["ot"] = 0
	loss["tickets"] = 16
	loss["card_drop"] = ""
	loss["xp"] = {"gained": 4, "level_before": 2, "level_after": 2}
	loss["sides"]["player"] = {"makes": 14, "attempts": 25, "swishes": 5, "bestStreak": 4, "bonus": 3, "iced": 1}
	loss["sides"]["ai"] = {"makes": 16, "attempts": 26, "swishes": 5, "bestStreak": 8, "bonus": 9, "iced": 0}
	loss["bright"] = ["NEW BEST STREAK · 4", "SHOOTING 56% · UP FROM 48% · LAST 5"]
	App.last_heat = loss
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(1.2)
	await _snap("heat_loss")
	# A close loss (by 2) rolls a card: CLOSE ONE over the drop.
	var close := loss.duplicate(true)
	close["player_score"] = 34
	close["card_drop"] = "ice"
	close["drop_reason"] = "close_loss"
	close["bright"] = ["5 SWISHES · YOUR MOST"]
	App.last_heat = close
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(1.2)
	await _snap("heat_close")
	# The 4th straight loss: the guaranteed Ice and its caption.
	var streak := loss.duplicate(true)
	streak["player_score"] = 24
	streak["card_drop"] = "ice"
	streak["drop_reason"] = "loss_streak"
	streak["bright"] = []
	App.last_heat = streak
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(1.2)
	await _snap("heat_streak")
	var quick := base.duplicate(true)
	quick["league"] = null
	quick["card_drop"] = ""
	App.last_heat = quick
	get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
	await _sleep(1.2)
	await _snap("heat_quick")
	# The online page (docs/BACKEND.md → Ranked → Stage B): a rated win with
	# SPOILS, tickets and a full meter; a rated loss with the lost card, the
	# insured one, the streak Ice, bright spots and SHOOT AROUND? beside
	# REMATCH?. The settle is staged the way the room sends it.
	var peer := QaFakePeer.new()
	peer.name = "Match"
	App.add_child(peer)
	App.room = peer
	App.match_how = "ranked"
	for won in [true, false]:
		var on := base.duplicate(true)
		on["league"] = null
		on["card_drop"] = ""
		on["online"] = true
		on["ranked"] = true
		on["won"] = won
		on["location"] = "beach"
		on["opponent"] = peer.peer
		if not won:
			on["player_score"] = 34
			on["ai_score"] = 36
			on["ot"] = 0
			on["bright"] = ["NEW BEST STREAK · 6", "7 SWISHES · YOUR MOST"]
		on.erase("tickets")
		on.erase("xp")
		App.online_settle = {}
		App.last_heat = on
		# The page first, the room's decision a beat later — the live order.
		get_tree().change_scene_to_file(App.HEAT_RESULT_SCENE)
		await _sleep(0.6)
		App.settled_online(peer.settle_message(won))
		await _sleep(0.8)
		await _snap("online_result_win" if won else "online_result_loss")
		print("QA heat result: online %s rank='%s' spoils='%s' meter='%s' shoot=%s" % ["win" if won else "loss", MatchCopy.rank_delta_line(App.last_heat),
			str(MatchCopy.spoils_panel(App.last_heat).get("caption", "")), MatchCopy.meter_line(App.last_heat), App.shoot_around_offered()])
	App.online_settle = {}
	App.room = null
	peer.queue_free()
	print("QA heat result: done")
	get_tree().quit(0)


## Card icons QA (design "Card Icons" 9a / 10a): the animated faces at every
## size the game uses, the chips, the tray tags and the deal caption, on the
## cage carpet. Snaps frame 0, frame 5 (pinned) and the live loop.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-cards
## (Magnet is a real card now — data/cards.json.)


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
	for card in [CardDefs.get_card("ice"), CardDefs.get_card("fire7"), CardDefs.get_card("magnet6")]:
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
	for card in [CardDefs.get_card("ice"), CardDefs.get_card("fire7"), CardDefs.get_card("magnet6"), {}]:
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
	await _pick_area("beach")
	await _click_button_named("TIME TRIAL")
	await _sleep(4.4)             # countdown, then GO
	for i in 9:
		await _snap("beach_%02d" % i)
		await _sleep(4.5)
	await _snap("beach_last")
	print("QA beach: " + _render_stats())
	# The pelican, forced over the water and placed mid-view for the snap.
	var bfx: BeachFx = get_tree().root.find_child("BeachFx", true, false)
	if bfx != null:
		bfx.spawn_pelican()
		# Parked 20 m ahead of whichever spot the pass ended on, up in the sky
		# (the spots face different ways, so a fixed point can be off-frame).
		var pcam: Camera3D = get_viewport().get_camera_3d()
		if pcam != null:
			var ahead := pcam.global_position - pcam.global_transform.basis.z * 20.0 - pcam.global_transform.basis.x * 5.0 + Vector3(0.0, 8.0, 0.0)
			bfx._pelican.global_position = ahead
			bfx._pelican_base_y = bfx._pelican.position.y
		await _sleep(0.6)
		await _snap("beach_pelican")
	print("QA beach: done")
	get_tree().quit(0)


## Spot rail QA (design "Solo Modes HUD" 5a): beach practice with its column
## of spot chips, a different spot picked, then the rail slid away.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-spots
func _run_spots() -> void:
	await _sleep(1.2)
	await _pick_area("beach")
	await _click_button_named("PRACTICE")
	await _sleep(1.4)
	await _snap("spots_00")
	var second: Button = get_tree().root.find_child("Spot1", true, false)
	if second != null:
		var c := _win_of(second)
		_mouse_button(c, true)
		await _sleep(0.08)
		_mouse_button(c, false)
		await _sleep(0.6)
		await _snap("spots_01")
	var chev: Button = get_tree().root.find_child("SpotChevron", true, false)
	if chev != null:
		var c2 := _win_of(chev)
		_mouse_button(c2, true)
		await _sleep(0.08)
		_mouse_button(c2, false)
		await _sleep(0.5)
		await _snap("spots_02")
	print("QA spots: done")
	get_tree().quit(0)


## City QA: the third home page (the city card, stars, the lock or the league),
## then the city time trial over ~45 s so cars cross the street, the trees
## and windows show, and the spot shuffle lands.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-city
func _run_city() -> void:
	await _sleep(1.2)
	await _pick_area("city")
	await _snap("city_home")
	App.start_mode("trial_city")             # straight in (the dev save may be under level 5)
	await _sleep(4.4)
	# A bunch of pigeons forced over the street, snapped as it crosses the view.
	var birds: CityFx = get_tree().root.find_child("CityFx", true, false)
	if birds != null:
		birds.spawn_pigeons()
		await _sleep(CityFx.PIGEON_EDGE / CityFx.PIGEON_SPEED)   # the bunch is mid-view
		await _snap("city_pigeons")
	for i in 10:
		await _snap("city_%02d" % i)
		if i == 3:
			print("QA city (play): " + _render_stats())
		await _sleep(4.5)
	await _snap("city_last")
	# The fence scoreboard up close, then the floor speakers (the camera
	# parked in front of each).
	var ccam: Camera3D = get_viewport().get_camera_3d()
	var rig: Node3D = get_tree().root.find_child("ReaderRig", true, false)
	if rig != null and ccam != null:
		var at := rig.global_position + Vector3(0.0, 0.25, 0.0)
		ccam.global_position = at + Vector3(-1.5, 0.35, -0.45)
		ccam.look_at(at)
		await _sleep(0.3)
		await _snap("city_scoreboard")
	var spk: Node3D = get_tree().root.find_child("Speakers", true, false)
	if spk != null and ccam != null:
		var at := spk.global_position + Vector3(0.0, 0.46, 0.0)
		ccam.global_position = at + Vector3(-1.35, 0.35, 0.25)
		ccam.look_at(at)
		await _sleep(0.3)
		await _snap("city_speakers")
	var fx: Node = get_tree().root.find_child("CityFx", true, false)
	if fx != null:
		print("QA city: cars sent %d, on the road %d, facades %d" % [fx.sent(), fx.car_count(), fx.facade_count()])
	print("QA city: " + _render_stats())
	print("QA city: done")
	get_tree().quit(0)


## Park QA (docs/HOME.md → the park): the park's home page, then the park
## time trial over ~45 s so the flurries fall, the trees and the parked
## cars show, and the spot shuffle lands.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-park
func _run_park() -> void:
	await _sleep(1.2)
	await _pick_area("park")
	await _snap("park_home")
	App.start_mode("trial_park")
	await _sleep(4.4)
	# The rim on fire against the pale sky (the flames must read; the ice too).
	var pcourt: CourtGeometry = get_tree().root.find_child("Court", true, false)
	if pcourt != null:
		pcourt.set_fire(true, 2)
		await _sleep(2.5)
		await _snap("park_fire")
		pcourt.set_fire(false)
		pcourt.set_ice(true, "qa")
		await _sleep(1.5)
		await _snap("park_ice")
		pcourt.set_ice(false, "qa")
		await _sleep(0.5)
		# The flip-card scoreboard on the fence: a card mid-swing, then settled.
		pcourt.show_score(12)
		pcourt.set_visitor(7)
		await _sleep(0.12)
		print("QA park: flipping at the park_flip snap = %s" % str(pcourt.flip_board() != null and pcourt.flip_board().flipping()))
		await _snap("park_flip")
		await _sleep(0.4)
		await _snap("park_score")
	for i in 8:
		await _snap("park_%02d" % i)
		print("QA park: %d fps at snap %d" % [int(Engine.get_frames_per_second()), i])
		await _sleep(4.5)
	await _snap("park_last")
	var fxs := get_tree().root.find_children("*", "ParkFx", true, false)
	if not fxs.is_empty():
		var fx: ParkFx = fxs[0]
		print("QA park: %d instances in %d draws, %d cars, %d flakes, sky %s, %d shadow casters, 3D scale %.2f" % [fx.instance_count(), fx.draw_count(), fx.car_count(), fx.snow_count(), str(fx.has_sky()), fx.shadow_caster_count(), get_viewport().scaling_3d_scale])
	print("QA park: " + _render_stats())
	print("QA park: done")
	get_tree().quit(0)


## Home QA: the cage card over its slow pan (frames at 0 / 5 / 10 / 14 s of a
## 28 s truck), then a page turn to the beach card.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-title
## PEGGY (docs/LOCKER.md): open the locker from the title, PEGGY from the
## locker, PLAY (the ticket flight, the credit), the joystick, DROP, the
## prize card, AGAIN, the staged epic and net cards, the short state, `<`
## back to the locker, the badge, the NETS tab. Grants tickets first and
## restores the save's cosmetics/settings after.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-peggy
func _run_peggy() -> void:
	await _sleep(1.0)
	await _close_archive()
	var cos_before: Dictionary = SaveService.get_cosmetics()
	var set_before: Dictionary = SaveService.get_settings()
	App.grant_tickets(1200)
	var locker: Button = get_tree().root.find_child("Locker", true, false)
	if locker == null:
		print("QA: no Locker button")
		return
	var lc := _win_of(locker)
	_mouse_button(lc, true)
	await _sleep(0.08)
	_mouse_button(lc, false)
	await _sleep(0.8)
	var ts := get_tree().current_scene
	if ts.call("locker") == null:
		print("QA peggy: locker tap missed (home mid-transition); opening directly")
		ts.call("_open_locker")
		await _sleep(0.8)
	await _snap("locker_open")
	await _sleep(0.4)
	await _click_button_named("PEGGY")
	await _sleep(0.15)
	await _snap("peggy_slide")
	await _sleep(0.7)
	await _snap("peggy_open")
	var panel: PeggyPage = get_tree().root.find_child("PeggyPage", true, false)
	var m: PeggyMachine = panel.machine() if panel != null else null
	if m == null:
		print("QA: no machine")
		return
	# PLAY: the ticket flies in and credits the machine.
	await _click_button_named("PLAY")
	await _sleep(0.5)
	await _snap("peggy_feed_a")
	await _sleep(0.9)
	await _snap("peggy_feed_b")
	await _sleep(1.0)
	await _snap("peggy_credited")
	# Real taps: drag the knob, then press the cap (window coords at 360x640).
	var knob_px := m.debug_screen_pos("knob")
	var cap_px := m.debug_screen_pos("cap")
	print("QA peggy: knob ", knob_px, " cap ", cap_px, " aim ", m.aim())
	_mouse_button(knob_px * 0.5, true)
	await _sleep(0.05)
	for i in 10:
		_mouse_move(knob_px * 0.5 + Vector2(6.0 * (i + 1), 0.0), Vector2(6.0, 0.0))
		await _sleep(0.05)
	await _sleep(0.4)
	_mouse_button(knob_px * 0.5 + Vector2(60.0, 0.0), false)
	print("QA peggy: aim after drag ", m.aim(), " hovered ", get_viewport().gui_get_hovered_control())
	await _sleep(0.2)
	_mouse_button(cap_px * 0.5, true)
	await _sleep(0.05)
	_mouse_button(cap_px * 0.5, false)
	await _sleep(0.1)
	print("QA peggy: DROP tapped, playing ", m.playing())
	while m.playing() or panel.prize_card() == null:
		await _sleep(0.2)
		if panel.prize_card() != null:
			break
	var keep0: Button = get_tree().root.find_child("Keep", true, false)
	if keep0 != null:
		keep0.pressed.emit()
	else:
		panel._dismiss_card()
	await _sleep(0.3)
	await _click_button_named("PLAY")
	await _sleep(PeggyMachine.FEED_S + 0.4)
	# The joystick drives the crane to the left wall.
	m.tilt = -1.0
	await _sleep(0.7)
	m.tilt = 0.0
	await _sleep(0.3)
	await _snap("peggy_aim")
	m.press()
	await _sleep(0.6)
	await _snap("peggy_drop_a")
	await _sleep(1.2)
	await _snap("peggy_drop_b")
	var waited := 0.0
	while panel.prize_card() == null and waited < 10.0:
		await _sleep(0.2)
		waited += 0.2
	await _sleep(0.3)
	await _snap("peggy_card")
	# AGAIN: another ticket in, a drop from the centre.
	var again: Button = get_tree().root.find_child("Again", true, false)
	if again != null:
		again.pressed.emit()
	await _sleep(PeggyMachine.FEED_S + 0.4)
	m.set_aim(0.0)
	m.press()
	waited = 0.0
	while panel.prize_card() == null and waited < 10.0:
		await _sleep(0.2)
		waited += 0.2
	await _snap("peggy_card_2")
	var keep: Button = get_tree().root.find_child("Keep", true, false)
	if keep != null:
		keep.pressed.emit()
	await _sleep(0.3)
	# The epic page and a net card, staged (a real one needs luck).
	panel._show_card({"slot": 0, "base": "epic", "rarity": "epic", "kind": "ball", "id": "tiger", "refund": 0,
		"owned_after": 4, "roster_size": 47, "result": {}})
	await _sleep(0.6)
	await _snap("peggy_epic")
	panel._dismiss_card()
	panel._show_card({"slot": 2, "base": "common", "rarity": "common", "kind": "net", "id": "wool", "refund": 0,
		"owned_after": 3, "roster_size": 8, "result": {}})
	await _sleep(0.4)
	await _snap("peggy_net_card")
	panel._dismiss_card()
	await _sleep(0.2)
	# Short of a drop: PLAY greyed, the cap's X.
	var cos_rich: Dictionary = SaveService.get_cosmetics()
	var cos_poor: Dictionary = cos_rich.duplicate(true)
	cos_poor["tickets"] = 180
	SaveService.put_cosmetics(cos_poor)
	panel._refresh_machine()
	await _sleep(0.5)
	await _snap("peggy_short")
	SaveService.put_cosmetics(cos_rich)
	panel._refresh_machine()
	# `<`: back to the locker, then CLOSE: home with the badge.
	var back: Button = panel.find_child("Back", true, false)
	if back != null:
		var bc := _win_of(back)
		_mouse_button(bc, true)
		await _sleep(0.08)
		_mouse_button(bc, false)
	await _sleep(0.8)
	await _snap("peggy_back_locker")
	await _click_button_named("CLOSE")
	await _sleep(0.8)
	await _snap("peggy_badge")
	_mouse_button(lc, true)
	await _sleep(0.08)
	_mouse_button(lc, false)
	await _sleep(0.8)
	var locker_page: LockerPanel = get_tree().root.find_child("LockerPanel", true, false)
	if locker_page != null:
		locker_page.show_tab("NETS")
	await _sleep(0.5)
	await _snap("peggy_nets")
	await _click_button_named("CLOSE")
	await _sleep(0.6)
	# Dark mode: both tabs must stay readable.
	var was_dark: bool = App.dark_mode
	App.set_dark_mode(true)
	await _sleep(0.6)
	locker = get_tree().root.find_child("Locker", true, false)
	if locker != null:
		lc = _win_of(locker)
		_mouse_button(lc, true)
		await _sleep(0.08)
		_mouse_button(lc, false)
		await _sleep(0.8)
		await _snap("peggy_dark_balls")
		await _click_button_named("PEGGY")
		await _sleep(0.8)
		await _snap("peggy_dark")
		var pg: PeggyPage = get_tree().root.find_child("PeggyPage", true, false)
		if pg != null:
			pg.close()
		await _sleep(0.6)
		await _click_button_named("CLOSE")
		await _sleep(0.6)
	App.set_dark_mode(was_dark)
	SaveService.put_cosmetics(cos_before)
	SaveService.put_settings(set_before)
	get_tree().quit()


## The area archive's snapshots (docs/HOME.md → Area archive): each area's
## REAL court — its glb, hoop, lights and ambient life — rendered offscreen
## at twice the card's size from the area's own title pose, saved into the
## project as assets/ui/areas/area_<id>.png (re-run after an area changes).
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-area-snaps
const SNAP_SIZE := Vector2i(1328, 640)
const SNAP_FOV_SCALE := 0.78
const SNAP_TALL := Vector2i(720, 1280)
const SNAP_SETTLE_S := 1.4


func _run_area_snaps() -> void:
	await _sleep(0.6)
	var out_dir := ProjectSettings.globalize_path("res://assets/ui/areas")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for card in AreaArchiveCopy.AREAS:
		var area := str(card["area"])
		var arena := CosmeticLibrary.get_arena(area)
		if arena == null:
			continue
		var vp := SubViewport.new()
		vp.size = SNAP_SIZE
		vp.own_world_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var court := CourtGeometry.new()
		court.name = "Court"
		court.geo = App.geo_for_mode(str(card["mode"]))
		court.arena_set = arena
		court.hoop_set = App.hoop_for_mode(str(card["mode"]))
		vp.add_child(court)
		court.led.set_text("HOOP SHOOT", court.led.accent_color)
		var cam := Camera3D.new()
		var spec := TitlePan.spec_of(arena)
		cam.fov = float(spec["fov"]) * SNAP_FOV_SCALE
		var p := TitlePan.pose(spec, 0.0)
		vp.add_child(cam)
		cam.position = p["pos"]
		cam.look_at(p["look"])
		var t := 0.0
		while t < SNAP_SETTLE_S:
			var dt: float = get_process_delta_time()
			court.step_rim(dt)
			t += dt
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(out_dir + "/area_%s.png" % area)
		img.save_png("user://qa/area_%s.png" % area)
		print("QA area snap %s (%dx%d)" % [area, img.get_width(), img.get_height()])
		# The portrait render behind the Area Unlock page (the full title pose).
		vp.size = SNAP_TALL
		cam.fov = float(spec["fov"])
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var tall := vp.get_texture().get_image()
		tall.save_png(out_dir + "/area_%s_tall.png" % area)
		print("QA area snap %s tall (%dx%d)" % [area, tall.get_width(), tall.get_height()])
		vp.queue_free()
		await _sleep(0.2)
	print("QA area snaps: done")
	get_tree().quit()


## The area archive page (docs/HOME.md → Area archive): the page as the
## player sees it, then staged at level 1 and level 5, then a pressed card.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-archive
func _run_archive() -> void:
	await _sleep(1.2)
	await _snap("archive_open")
	var page: AreaArchivePage = get_tree().root.find_child("AreaArchive", true, false)
	if page != null:
		page.close()
		await _sleep(0.5)
	for level in [1, 5]:
		var rows := AreaArchiveCopy.rows(level, App.league_states(), AreaArchiveCopy.bests(), true)
		var staged := AreaArchivePage.new()
		staged.build(rows, AreaArchiveCopy.open_count(level, rows))
		add_child(staged)
		await _sleep(0.5)
		await _snap("archive_lvl%d" % level)
		if level == 5:
			var card: Button = staged.card("beach")
			if card != null:
				var c := (card.global_position + Vector2(100, 100)) * 0.5
				_mouse_button(c, true)
				await _sleep(0.15)
				await _snap("archive_press")
				_mouse_button(c, false)
				await _sleep(0.3)
		staged.queue_free()
		await _sleep(0.3)
	print("QA archive: done")
	get_tree().quit()


## Online 1v1 (docs/BACKEND.md → Phase 3) with the net off: the lobby's
## menu, the code to pass on, FOUND and NOBODY CAME; then a staged online
## heat on the beach against QaFakePeer (a seeded bot behind the wire),
## snapped early, mid-way and at the post-match page.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-multi
func _run_multi() -> void:
	Net.enabled = false
	await _sleep(1.2)
	var archive: AreaArchivePage = get_tree().root.find_child("AreaArchive", true, false)
	if archive != null:
		archive.pick("beach")
		await _sleep(1.0)
	await _click_named("Online")
	await _sleep(0.5)
	var lobby: MatchLobbyPage = get_tree().root.find_child("MatchLobby", true, false)
	if lobby == null:
		print("QA multi: no lobby")
		get_tree().quit()
		return
	await _snap("multi_menu")
	lobby.show_waiting("create", "ABCDE")
	await _sleep(0.2)
	await _snap("multi_code")
	lobby.show_failed("expired")
	await _sleep(0.2)
	await _snap("multi_failed")
	# The face-off (design 37a, 2026-10-18): the reel spins, then the pop.
	lobby.show_waiting("quick")
	await _sleep(0.2)
	await _snap("multi_finding")
	var first := lobby.reel_name()
	await _sleep(0.35)
	await _snap("multi_finding_b")
	print("QA multi: reel %s -> %s" % [first, lobby.reel_name()])
	lobby.show_found({"name": "GLASS WIZARD", "tag": "07", "level": 9, "town": "SALT HARBOR", "area": "beach"})
	await _sleep(0.12)
	await _snap("multi_found_a")
	await _sleep(0.8)
	await _snap("multi_found")
	print("QA multi: found popped=%s vs=%.2f court=%s" % [lobby.found_popped(), lobby.vs_scale(), lobby.court_text()])
	lobby.show_menu()
	# The rewards page (Stage B): opened over the lobby, then fed the fixture
	# answer the way Net.rewards_loaded would (the net is off here).
	var ts: Node = get_tree().current_scene
	if ts != null and ts.has_method("_open_rewards"):
		ts.call("_open_rewards")
		await _sleep(0.6)
		var rp: RewardsPage = ts.call("rewards_page") if ts.has_method("rewards_page") else null
		if rp != null:
			var fx: Variant = JSON.parse_string(FileAccess.open("res://tests/fixtures/rewards.json", FileAccess.READ).get_as_text())
			rp.set_data(fx)
			await _sleep(0.4)
			await _snap("multi_rewards")
			print("QA multi: rewards pending=%s meter='%s'" % [rp.pending_count(), rp.meter_text()])
			rp.close()
			await _sleep(0.5)
	# The pre-match pick (docs/BACKEND.md → Ranked): a seeded cache (a spare
	# ice, a Heat Check set, a Magnet above the cap), the opponent's badge,
	# the cap line, the timer; READY goes gold.
	var cd: Dictionary = SaveService.get_cards()
	var ob := CardDefs.league_doc(cd, "online")
	ob["inventory"] = {"ice": 1, "magnet6": 1}
	ob["loadout"] = ["fire7", null, null]
	SaveService.put_cards(cd)
	var staged := QaFakePeer.new()
	var title_screen: Node = get_tree().current_scene
	var matched: Dictionary = staged.matched_message()
	matched["side"] = "a"
	title_screen.call("_open_pre_match", matched)
	staged.free()
	await _sleep(0.5)
	var pre: PreMatchPage = get_tree().root.find_child("PreMatch", true, false)
	await _snap("multi_prematch")
	if pre != null:
		pre.press_ready()
		pre.set_peer_loadout(["ice", "", ""], true)   # the room's peer_loadout: they picked an ice and readied
		await _sleep(0.4)
		await _snap("multi_prematch_ready")
		print("QA multi: prematch cap=%s opp=%s / %s %s %s ready=%s top=%s" % [pre.cap_text(), pre.opp_name(), pre.opp_stat(0), pre.opp_stat(1), pre.opp_stat(2), pre.is_ready(), pre.ready_top()])
	title_screen.call("_close_pre_match")
	await _sleep(0.3)
	lobby.close()
	await _sleep(0.4)
	# The staged match: a 20 s beach heat against the fake peer, hands dealt
	# both ways (ours from the cache above; theirs an ice they play on us).
	var start := {"t": "start", "seed": 4242, "area": "beach", "seconds": 20.0, "ot_seconds": 6.0, "ball_return_s": 1.0,
		"hands": {"a": ["fire7", "", "ice"], "b": ["ice", "", ""]}, "levels": {"a": 1, "b": 4}, "ranked": true, "cap": 1,
		"tiers": {"a": {"tier": "rookie", "division": 3}, "b": {"tier": "pro", "division": 2}},
		"kits": {"a": null, "b": QaFakePeer.KIT}}
	var fake := QaFakePeer.new()
	fake.name = "Match"
	App.add_child(fake)
	App.room = fake
	App.match_how = "create"
	# App's room handler is wired in _open_room; the staged peer gets the one
	# line of it the rematch card needs.
	fake.message.connect(func(m: Dictionary) -> void:
		if str(m.get("t", "")) == MatchProtocol.REMATCH:
			App._set_rematch("both" if App.rematch_state in ["offered", "both"] else "wanted")
		elif str(m.get("t", "")) == MatchProtocol.SETTLED:
			App.settled_online(m)   # the real router does this; the staged peer needs the line
	)
	var cfg := MatchProtocol.heat_cfg(start, fake.peer, "a")
	App.start_heat(str(cfg["mode"]), cfg)
	await _sleep(1.0)
	var screen := get_tree().current_scene
	var spots := []
	if screen != null and screen.get("heat") != null:
		spots = (screen.get("heat") as Heat).spots
	fake.stage(start, App.geo_for_mode(str(cfg["mode"])), spots, true)
	await _sleep(7.0)
	await _snap("online_heat_early")
	# The opponent's window up close: their galaxy ball and red-white-blue net (the kit), no shadows, frozen fx.
	if screen != null and screen.get("_pip_frame") != null:
		var frame: Control = screen.get("_pip_frame")
		await _snap_rect("pip_kit", Rect2(frame.position, frame.size))
	await _sleep(9.0)
	await _snap("online_heat_late")
	await _sleep(9.0)
	await _snap("online_result")
	print("QA multi: settle rank line '%s' tickets=%s" % [MatchCopy.rank_delta_line(App.online_settle), str(App.last_heat.get("tickets", "-"))])
	# The rematch card: they ask (gold), we accept (teal).
	if is_instance_valid(fake):
		fake.ask_rematch()
		await _sleep(0.3)
		await _snap("online_rematch_wanted")
		App.offer_rematch()
		await _sleep(0.3)
		await _snap("online_rematch_both")
	print("QA multi: done (rematch %s)" % App.rematch_state)
	get_tree().quit()


## The Ranks page (docs/HOME.md → Ranks) with the net off: LOADING, a
## fixture board (THIS WEEK), the no-signal fallback after a period switch,
## the fixture again as ALL TIME, then the city tab.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-ranks
func _run_ranks() -> void:
	Net.enabled = false
	await _sleep(1.2)
	var archive: AreaArchivePage = get_tree().root.find_child("AreaArchive", true, false)
	if archive != null:
		archive.pick("cage")   # closing the front door leads back to the splash
		await _sleep(1.0)
	await _click_named("BoardPreview")
	await _sleep(0.05)
	await _snap("ranks_loading")
	await _sleep(0.5)
	var page: RanksPage = get_tree().root.find_child("RanksPage", true, false)
	if page == null:
		print("QA ranks: no page")
		get_tree().quit()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ranks_board.json"))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	page.set_board(page.area(), page.period(), data)
	await _sleep(0.3)
	await _snap("ranks_week")
	await _click_named("PeriodAll")
	await _sleep(0.5)
	await _snap("ranks_offline")
	page.set_board(page.area(), page.period(), data)
	await _sleep(0.3)
	await _snap("ranks_all")
	await _click_named("Tab_city")
	await _sleep(0.5)
	await _snap("ranks_city")
	print("QA ranks: done (%s / %s, %d rows)" % [page.area(), page.period(), page.row_count()])
	page.close()
	await _sleep(0.4)
	# The settings sheet's PLAYER section.
	await _click_named("Menu")
	await _sleep(0.8)
	await _snap("settings_player")
	await _click_named("EnterCode")
	await _sleep(0.3)
	await _snap("settings_code")
	get_tree().quit()


## The league match-end page (docs/HOME.md → Results): the five moments
## staged from heat dicts, each snapped early (the slam / sink) and settled.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-match-end
func _run_match_end() -> void:
	await _sleep(0.6)
	var base := {"year": 2, "league_name": "ARCADE LEAGUE", "record_before": [2, 1], "record_after": [3, 1],
		"place_before": 3, "place_after": 2, "titles_before": 1, "titles_after": 1, "playoff": false, "round": "",
		"series_id": "", "best_of": 3, "series_before": [0, 0], "series_after": [0, 0], "decided": false,
		"series_won": false, "other_semi": ["kingsbridge", "ferry-row"], "final_opp": "", "teams": 6}
	var opp := LeagueData.shooter("brickport")
	var cases := [
		["win", true, 41, 37, {}, "fire7"],
		["loss", false, 33, 36, {"record_after": [2, 2], "place_after": 4}, ""],
		["advance", true, 44, 39, {"playoff": true, "round": "semifinal", "series_after": [2, 1], "decided": true, "series_won": true, "final_opp": "kingsbridge"}, "ice"],
		["eliminated", false, 35, 38, {"playoff": true, "round": "semifinal", "series_after": [1, 2], "decided": true, "series_won": false, "place_after": 3}, ""],
		["champion", true, 46, 40, {"playoff": true, "round": "final", "series_after": [3, 1], "decided": true, "series_won": true, "titles_after": 2}, "fire7"],
	]
	for c in cases:
		var e: Dictionary = base.duplicate(true)
		e.merge(c[4], true)
		var heat := {"won": c[1], "player_score": c[2], "ai_score": c[3], "ot": 0, "opponent": opp, "mode": "heat", "location": "cage",
			"league": {"id": "cage", "game": "po-sf-1" if bool(e["playoff"]) else "d4", "playoff": e["playoff"]},
			"tickets": 36 if c[1] else 16, "card_drop": c[5], "league_end": e}
		var o := MatchEndOverlay.new()
		o.name = "MatchEnd"
		o.build(MatchEndCopy.state(heat))
		add_child(o)
		await _sleep(0.75)
		await _snap("match_end_%s_a" % c[0])
		await _sleep(2.6)
		await _snap("match_end_%s_b" % c[0])   # the box popped, the stream under way
		await _sleep(2.0)
		await _snap("match_end_%s_c" % c[0])   # the count full
		print("QA match end %s: tickets read %s" % [c[0], o.tickets_text()])
		o.queue_free()
		await _sleep(0.2)
	print("QA match end: done")
	get_tree().quit()


## The archive opens in front of the home on a cold launch: close it (or
## pick an area through it) before tapping the home's own buttons.
func _close_archive() -> void:
	var page: AreaArchivePage = get_tree().root.find_child("AreaArchive", true, false)
	if page != null:
		# On a cold launch the archive is the front door and its < leads back
		# out to the splash, so the way "through" it is to pick the home area.
		page.pick("cage")
		await _sleep(1.4)


func _pick_area(id: String) -> void:
	var title: Node = get_tree().current_scene
	var page: AreaArchivePage = get_tree().root.find_child("AreaArchive", true, false)
	if page == null and title != null and title.has_method("_open_archive"):
		title.call("_open_archive")
		await _sleep(0.4)
		page = get_tree().root.find_child("AreaArchive", true, false)
	if page != null:
		page.pick(id)
		await _sleep(1.0)


## The splash (docs/HOME.md → Splash): the sign dark on the frosted cage,
## the chain down, the first blink, warming, lit with the buttons up; then
## CONTINUE / NEW GAME into the archive.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-splash
## The Area Unlock page (docs/HOME.md → Area unlock), staged for the beach
## and the city: the lock on the veiled picture, the shackle sprung on the lit
## picture, NEW AREA with the chips, the buttons.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-unlock
func _run_unlock() -> void:
	await _sleep(0.8)
	for pair in [["beach", 3], ["park", 4], ["city", 5]]:
		var page := AreaUnlockPage.new()
		page.build(AreaUnlockCopy.state(str(pair[0]), int(pair[1])))
		add_child(page)
		var marks := [0.5, 1.7, 2.6, 3.6]
		var at := 0.0
		for i in marks.size():
			await _sleep(float(marks[i]) - at)
			at = float(marks[i])
			await _snap("unlock_%s_%02d" % [pair[0], i])
		page.queue_free()
		await _sleep(0.3)
	print("QA unlock: done")
	get_tree().quit(0)


func _run_splash() -> void:
	# A fresh install (design 35a): NEW GAME, the NEW PLAYER form, LET'S PLAY,
	# then the home walkthrough (36a) — forget it was ever seen.
	App.qa_fresh = true
	var st: Dictionary = SaveService.get_settings()
	st["walkthroughsSeen"] = []
	SaveService.put_settings(st)
	var marks := [0.2, 0.8, 1.5, 3.0, 5.2]
	var at := 0.0
	for i in marks.size():
		await _sleep(float(marks[i]) - at)
		at = float(marks[i])
		await _snap("splash_%02d" % i)
	await _click_button_named("NEW GAME")
	await _sleep(0.6)
	await _snap("new_player")
	await _click_named("RollName")
	await _click_named("RollTown")
	await _sleep(0.35)
	await _snap("new_player_roll")
	var page: NewPlayerPage = get_tree().root.find_child("NewPlayerPage", true, false)
	var ne: LineEdit = page.find_child("NameEdit", true, false) if page != null else null
	if ne != null:
		ne.text = "AB"
		ne.text_changed.emit("AB")
	await _sleep(0.2)
	await _snap("new_player_invalid")
	await _click_named("RollName")
	await _sleep(0.35)
	await _click_button_named("LET'S PLAY")
	await _sleep(2.2)
	# The home walkthrough (design 36a): the welcome, every step, the end.
	await _snap("walkthrough_00")
	for i in 6:
		await _click_named("TourNext")
		await _sleep(0.7)
		await _snap("walkthrough_%02d" % (i + 1))
	await _click_named("TourNext")
	await _sleep(1.0)
	await _snap("new_player_home")
	print("QA splash: done (player %s, town %s)" % [Net.handle(), App.hometown()])
	get_tree().quit(0)


func _run_title() -> void:
	await _sleep(1.0)
	await _close_archive()
	# The home board mid-court (design 3a): filled with a stand-in top five
	# and a YOU row so the look can be judged without a server.
	var bp: BoardPreview = get_tree().root.find_child("BoardPreview", true, false)
	if bp != null:
		var rows := []
		for r in [["NEON OWL", 41], ["CLUTCH HAWK", 38], ["GLASS DUKE", 36], ["TURBO COMET", 35], ["LUCKY FOX", 34]]:
			rows.push_back({"rank": "#%d" % (rows.size() + 1), "name": r[0], "score": str(r[1]), "me": false})
		bp.set_rows(rows, {"rank": 212, "score": 29})
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
	await _pick_area("beach")
	await _sleep(0.4)
	await _snap("title_beach_00")
	await _sleep(6.0)
	await _snap("title_beach_01")
	await _pick_area("cage")
	await _sleep(0.4)
	await _snap("title_cage_back")
	# The league in context: open it, walk the tabs, close it.
	await _click_button_named("LEAGUE")
	await _sleep(0.8)
	await _snap("title_league_heat")
	# The pre-match pick before a league heat (docs/CARDS.md § Drops): the
	# next opponent, the cap at your level, this league's cards, the clock.
	var title_scene: Node = get_tree().current_scene
	if title_scene != null and title_scene.has_method("open_league_pre_match"):
		title_scene.call("open_league_pre_match", App.league_pre_match_info(App.league_doc(), App.league_cfg()))
		await _sleep(0.5)
		await _snap("title_prematch")
		title_scene.call("_close_pre_match")
		await _sleep(0.3)
	for tab in ["TABLE", "SCHED", "CARDS", "STATS"]:
		await _click_button_named(tab)
		await _sleep(0.6)
		await _snap("title_league_" + tab.to_lower())
	await _click_button_named("<")
	await _sleep(0.8)
	# The locker (an IconButton has no text: click it by name).
	var locker: Button = get_tree().root.find_child("Locker", true, false)
	if locker != null:
		var lc := _win_of(locker)
		_mouse_button(lc, true)
		await _sleep(0.08)
		_mouse_button(lc, false)
		await _sleep(0.8)
		await _snap("title_locker")
		await _click_button_named("CLOSE")
		await _sleep(0.6)
	# The menu (a HamburgerButton has no text: click it by name).
	var menu: Button = get_tree().root.find_child("Menu", true, false)
	if menu != null:
		var c := _win_of(menu)
		_mouse_button(c, true)
		await _sleep(0.08)
		_mouse_button(c, false)
		await _sleep(0.8)
		await _snap("title_settings")
		await _click_button_named("CLOSE")
		await _sleep(0.6)
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
	await _close_archive()
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
## Spawn a swish pop and an ON FIRE pop on the current screen's court
## (`_court` or the opponent's `_ai_court`) and snap at 0.15, 0.5 and 0.9 s.
func _pop_snaps(court_var: String, prefix: String) -> void:
	var screen := get_tree().current_scene
	if screen == null or not court_var in screen:
		print("QA: no %s on current scene!" % court_var)
		return
	var court: CourtGeometry = screen.get(court_var)
	court.rim_pop_from(HudCopy.rim_pop(ShotClassify.SWISH, 2))
	court.rim_pop_from(HudCopy.fire_pop())
	await _sleep(0.15)
	await _snap("%s_00" % prefix)
	await _sleep(0.35)
	await _snap("%s_01" % prefix)
	await _sleep(0.4)
	await _snap("%s_02" % prefix)


## The cage's ball-return ramp: drop a ball from rest over the slope (as a
## miss behind the rim would) and snap it bouncing and rolling down to the
## deck: ramp_00..03.
func _ramp_snaps() -> void:
	var screen := get_tree().current_scene
	if screen == null or not "trial" in screen:
		print("QA: no trial for the ramp snaps!")
		return
	var trial: TimeTrial = screen.get("trial")
	var geo: SimGeometry = trial.geo
	if not geo.has_ramp():
		print("QA: this geometry has no ramp")
		return
	trial._flights.push_back({
		"state": ShotSim.create_shot({"angle_deg": 0.0, "speed": 0.0, "rx": geo.ramp_x1 - 0.3, "ry": 1.3, "rz": 0.2, "bx": 1.0, "bz": 0.0}, geo),
		"seen_events": 0, "scored": false,
	})
	for i in 4:
		await _sleep([0.3, 0.35, 0.4, 0.5][i])
		await _snap("ramp_%02d" % i)


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


## The frame's cost on record: draw calls, primitives, objects (the last
## rendered frame) and the fps — printed by the area QAs before/after a trim.
func _render_stats() -> String:
	return "render: %d draw calls, %d primitives, %d objects, %d fps" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		int(Engine.get_frames_per_second())]


func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://qa/%s%s.png" % [name_, _snap_suffix])
	print("QA snap " + name_ + _snap_suffix)


## A crop of the screen (design coordinates, 720×1280) at 2× for a close look.
func _snap_rect(name_: String, rect: Rect2) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size   # the window may be smaller than the design
	var r := Rect2i(Rect2(rect.position * k, rect.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		print("QA snap %s: empty crop" % name_)
		return
	var crop := img.get_region(r)
	crop.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png("user://qa/%s.png" % name_)
	print("QA snap " + name_)


func _click_first_button() -> void:
	var buttons := get_tree().root.find_children("*", "Button", true, false)
	if buttons.is_empty():
		print("QA: no button found!")
		return
	var b: Button = buttons[0]
	var center := _win_of(b)  # viewport → window coords
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
			var center := _win_of(b)  # viewport → window
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
	ev.position = _window_pos(pos)
	ev.global_position = ev.position
	Input.parse_input_event(ev)


## A window position computed as band × scale → the real window position:
## on a screen taller than 9:16 the centred band sits UiLayout.offset() lower.
func _window_pos(pos: Vector2) -> Vector2:
	return pos + UiLayout.offset() * get_viewport().get_final_transform().get_scale()


## A control's centre as a band-relative window position for _mouse_button
## (which adds the band's offset back): right in a centred layer and in an
## anchored one — the canvas transform carries the layer's offset.
func _win_of(b: Control) -> Vector2:
	var ft := get_viewport().get_final_transform()
	return ft * (b.get_global_transform_with_canvas() * (b.size / 2.0)) - UiLayout.offset() * ft.get_scale()


func _mouse_move(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _window_pos(pos)
	ev.global_position = ev.position
	ev.relative = rel
	# Touch emulation only synthesizes ScreenDrag from motion that reports a
	# held button — real drags set this automatically, injected ones must too.
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)


## One flick gesture in window coords: press low-center, drag up over several
## motion events at real-time cadence, release. speed_sh sets the drag rate;
## travel_frac the total length; tilt_step adds lateral px per motion step.
## A real shot: press in the grab zone, pull down `pull_frac` of the window
## (the arc), then flick up at `speed_sh` screen-heights/s and let go.
## The release speed (sh) that carries a pull of `pull_frac` × the window
## height to the live hoop at its own arc — the ideal for the current trial.
func _ideal_sh(pull_frac: float) -> float:
	var screen := get_tree().current_scene
	if screen == null or not ("trial" in screen) or screen.trial == null:
		return 4.9
	var geo: SimGeometry = screen.trial.geo
	var pull_px := pull_frac * WIN.y * 2.0   # window → design px
	var angle := FlickMap.windup_angle(pull_px, UiLayout.DESIGN.y, App.tuning)
	var sh := FlickMap.speed_sh_for_reach(angle, geo.hoop_x, geo.rise, App.tuning)
	return sh if is_finite(sh) and sh > 0.0 else 4.9


func _flick_windup(pull_frac: float, speed_sh: float) -> void:
	var start := Vector2(WIN.x / 2.0, WIN.y * 0.58)
	_mouse_button(start, true)
	await _sleep(0.12)
	var pos := start
	var steps := 8
	for i in steps:
		var next := start + Vector2(0.0, pull_frac * WIN.y * float(i + 1) / float(steps))
		_mouse_move(next, next - pos)
		pos = next
		await _sleep(0.05)
	# One move per frame: the distance per move sets the speed the input sees.
	var travel := 0.30 * WIN.y
	var per_frame := speed_sh * WIN.y / 60.0
	var moves := maxi(2, roundi(travel / per_frame))
	for k in moves:
		await get_tree().process_frame
		var next := pos + Vector2(0.0, -travel / float(moves))
		_mouse_move(next, next - pos)
		pos = next
	_mouse_button(pos, false)


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



# ---- the args (the command line, or user://qa_args.txt once on a phone) --------------------

## The command line's user args — or, with none, the one-shot file a phone
## run leaves behind (tools/android_qa.sh writes user://qa_args.txt; it is
## deleted here so a QA mode never sticks to the install).
func _args() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		return args
	var path := "user://qa_args.txt"
	if not FileAccess.file_exists(path):
		return args
	var text := FileAccess.open(path, FileAccess.READ).get_as_text().strip_edges()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var out := PackedStringArray()
	for a in text.split(" ", false):
		out.push_back(a.strip_edges())
	print("QA: args from user://qa_args.txt: %s" % " ".join(out))
	return out


## Whether a launch with `args` skips the first-shot tutorial: only a QA pass
## that did not ask for it. A plain launch never skips (tested).
static func skips_tutorial(args: PackedStringArray) -> bool:
	return _has_prefixed(args, "--qa") and not args.has("--qa-tutorial")


static func _has_prefixed(args: PackedStringArray, prefix: String) -> bool:
	for a in args:
		if str(a).begins_with(prefix):
			return true
	return false


func _arg_value(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for a in args:
		if str(a).begins_with(prefix):
			return str(a).trim_prefix(prefix)
	return fallback


# ---- --qa-perf (docs/PERFORMANCE.md): frame time, render time, draws, script time ---------

## Every area × mode (league heat with the PiP open, with it minimized, the
## time trial) for PERF_SECONDS after a warm-up, a bot shooting on our side,
## the probe sampling every frame; one table row per run and
## user://qa/perf.json for tools/perf_ledger.gd. Filters: --qa-perf=beach,city
## --qa-perf-mode=heat_pip,trial --qa-perf-seconds=24.
##   Godot --path hoop_shoot --resolution 360x640 -- --qa-perf
##   tools/android_qa.sh --qa-perf                       (on the phone)
const PERF_AREAS := ["cage", "beach", "park", "city"]
const PERF_MODES := ["heat_pip", "heat_min", "trial"]
const PERF_WARMUP_S := 3.0
const PERF_SECONDS := 24.0

func _run_perf(args: PackedStringArray) -> void:
	var areas: Array = Array(_arg_value(args, "--qa-perf=", ",".join(PERF_AREAS)).split(",", false))
	var modes: Array = Array(_arg_value(args, "--qa-perf-mode=", ",".join(PERF_MODES)).split(",", false))
	var seconds := float(_arg_value(args, "--qa-perf-seconds=", str(PERF_SECONDS)))
	# A/B variants (CourtGeometry.ab): "base" then each named lever, every area × mode per variant.
	var variants: Array = Array(_arg_value(args, "--qa-perf-ab=", "").split(",", false))
	variants.push_front("base")
	Net.enabled = false
	await _sleep(1.0)
	# The dev save comes back exactly as it was: a QA heat must not advance a season.
	var save: Node = get_tree().root.get_node("SaveService")
	var kept := {"campaign": {}, "cosmetics": save.get_cosmetics(), "progress": save.get_progress(), "cards": save.get_cards()}
	for a in PERF_AREAS:
		kept["campaign"][a] = save.league_doc(a)
	var was_gating: bool = App.league_gating
	App.league_gating = false   # every court measured whatever this save has opened
	var runs := []
	# Area-outer, variant-inner: a phone warms up over a sweep (the first A/B sweep drifted
	# 3 ms of GPU time end to end, as much as most levers), so one area's variants run back
	# to back and the area closes with its reference again — the drift row (mode*).
	for area in areas:
		for variant in variants:
			# Every lever is measured against the same reference: the scenery caster rules OFF
			# (the game's default has them on); "casters" alone turns them on.
			CourtGeometry.ab = {"casters": str(variant) == "casters"} if variants.size() > 1 else {}
			if str(variant) not in ["base", "casters"]:
				CourtGeometry.ab[str(variant)] = true
			for mode in modes:
				var row := await _perf_run(str(area), str(mode), seconds)
				if not row.is_empty():
					if str(variant) != "base":
						row["variant"] = str(variant)
						row["mode"] = str(mode) + "@" + str(variant)
					runs.push_back(row)
					print("PERF " + PerfBudget.row_text(row))
		if modes.size() * variants.size() > 1:
			CourtGeometry.ab = {"casters": false} if variants.size() > 1 else {}
			var again := await _perf_run(str(area), str(modes[0]), seconds)
			if not again.is_empty():
				again["mode"] = str(modes[0]) + "*"
				runs.push_back(again)
				print("PERF " + PerfBudget.row_text(again))
	CourtGeometry.ab = {}
	App.league_gating = was_gating
	for a in PERF_AREAS:
		if kept["campaign"][a] is Dictionary and not Dictionary(kept["campaign"][a]).is_empty():
			save.put_league_doc(a, kept["campaign"][a])
	save.put_cosmetics(kept["cosmetics"])
	save.put_progress(kept["progress"])
	save.put_cards(kept["cards"])
	App.qa_player_bot = null
	var dump := {
		"device": {"model": OS.get_model_name(), "os": OS.get_name(), "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
			"adapter": RenderingServer.get_video_adapter_name(), "window": str(DisplayServer.window_get_size())},
		"when": Time.get_datetime_string_from_system(), "warmup_s": PERF_WARMUP_S, "seconds": seconds, "runs": runs,
	}
	var f := FileAccess.open("user://qa/perf.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(dump, "  "))
	f.close()
	print("PERF TABLE (%s · %s · %s)" % [dump["device"]["model"], dump["device"]["renderer"], dump["device"]["adapter"]])
	print(PerfBudget.header_text())
	for r in runs:
		print(PerfBudget.row_text(r))
	print("QA perf: wrote user://qa/perf.json (%d runs)" % runs.size())
	get_tree().quit(0)


## One scenario: start it, wait the warm-up, measure `seconds`, back to the title.
func _perf_run(area: String, mode: String, seconds: float) -> Dictionary:
	var is_heat := mode.begins_with("heat")
	if is_heat:
		# A fresh season, day 1, the same seed every run: the heat always exists and the runs compare.
		var cfg := LeagueData.league(area)
		if cfg.is_empty():
			print("QA perf: no league for %s" % area)
			return {}
		App.save_league_doc(Campaign.new_doc(cfg, 4242, int(Time.get_unix_time_from_system() * 1000.0)), area)
		if not App.enter_league(area):
			print("QA perf: could not enter the %s league" % area)
			return {}
		App.qa_player_bot = AiRatings.make(0.6, 0.5)
		App.play_league_heat()
	else:
		App.start_area("trial", area)
	await _sleep(1.0)
	var screen := get_tree().current_scene
	if screen == null or not ("trial" in screen):
		print("QA perf: %s %s did not start" % [area, mode])
		App.to_title()
		await _sleep(1.0)
		return {}
	# Through the countdown (TimeTrial.COUNTDOWN_SECONDS) and into play.
	await _sleep(TimeTrial.COUNTDOWN_SECONDS + 0.5)
	if mode == "heat_min":
		await _click_named("PipMin")
	var pip_vp: SubViewport = screen.get("_pip_vp") if is_heat else null
	var probe := PerfProbe.new()
	probe.name = "PerfProbe"
	probe.setup(get_viewport(), pip_vp, screen)
	add_child(probe)
	var flicker := 0.0
	var t := 0.0
	while t < PERF_WARMUP_S + seconds:
		var dt := 0.2
		await _sleep(dt)
		t += dt
		if t >= PERF_WARMUP_S and not probe.measuring:
			probe.begin()
		if not is_heat:
			flicker += dt
			if flicker >= 1.6:
				flicker = 0.0
				_flick(1.9, 0.30, randf_range(-1.0, 1.0))
	var row := probe.finish()
	row["area"] = area
	row["mode"] = mode
	probe.queue_free()
	App.qa_player_bot = null
	await _snap("perf_%s_%s" % [area, mode])
	App.to_title()
	await _sleep(1.2)
	return row


## The per-frame probe (docs/PERFORMANCE.md): frame time, each viewport's
## measured render time (CPU, and GPU where the driver has timestamps — none
## on Metal), visible + shadow draws / primitives / objects per viewport, the
## script time, and the see-through coverage (alpha-blended surfaces' screen
## area, in screens) every 10th frame.
class PerfProbe extends Node:
	const HITCH_MS := 20.0
	var measuring := false
	var _main: Viewport
	var _pip: SubViewport
	var _screen: Node
	var _frames: PackedFloat64Array = []
	var _script: PackedFloat64Array = []
	var _sim: PackedFloat64Array = []   # the rules tick alone (TimeTrialScreen.last_sim_ms)
	var _setup: PackedFloat64Array = []
	var _cov: PackedFloat64Array = []
	var _cov_tick := 0
	var _vp_sum := {}   # "main"/"pip" → {cpu, gpu, n, draws_v, draws_s, prims_v, prims_s, objs_v, objs_s}
	var _hitches: Array = []
	## Spikes (frames over the run's running p50 by more than one refresh period,
	## and over 1.5× it — after the first 60 frames) with what was on screen: the
	## shader-stutter check (docs/PERFORMANCE.md rule 8); a spike that lines up
	## with a first appearance is a pipeline compile. A phone at vsync quantises
	## frames to 16.7 / 33.3 ms, so a plain 1.5× p50 at a p50 of 20 ms counted
	## every ordinary dropped frame as a spike.
	var _spike_log: Array = []
	var _spike_p50 := 0.0
	var _period := 1000.0 / maxf(DisplayServer.screen_get_refresh_rate(), 30.0)   # -1 when unknown → 33 ms floor
	var _seen := {}   # tag → true once it has appeared (so "first:<tag>" marks the debut)
	var _t := 0.0
	var _alpha_cache := {}   # shader RID → bool
	## Script time: a sentinel that runs FIRST in the frame stamps the clock; the
	## probe runs LAST and takes the span — every _process in between, nothing else.
	var _first: Node
	var _span: PackedFloat64Array = []
	var _frame_start_usec := 0

	func setup(main: Viewport, pip: SubViewport, screen: Node) -> void:
		_main = main
		_pip = pip
		_screen = screen
		process_priority = 1000
		_first = Node.new()
		_first.name = "PerfFirst"
		_first.process_priority = -1000
		_first.set_script(FirstSentinel)
		add_child(_first)
		RenderingServer.viewport_set_measure_render_time(_main.get_viewport_rid(), true)
		if _pip != null:
			RenderingServer.viewport_set_measure_render_time(_pip.get_viewport_rid(), true)
		for k in ["main", "pip"]:
			_vp_sum[k] = {"cpu": 0.0, "gpu": 0.0, "n": 0, "draws_v": 0.0, "draws_s": 0.0, "prims_v": 0.0, "prims_s": 0.0, "objs_v": 0.0, "objs_s": 0.0}

	func begin() -> void:
		measuring = true
		_t = 0.0

	func _process(dt: float) -> void:
		if not measuring:
			return
		_t += dt
		var ms := dt * 1000.0
		_frames.push_back(ms)
		if ms > HITCH_MS:
			_hitches.push_back({"t": snappedf(_t, 0.01), "ms": snappedf(ms, 0.1)})
		var tags := _tags()
		if _frames.size() % 60 == 0:
			var fr := _frames.duplicate()
			fr.sort()
			_spike_p50 = _pct(fr, 0.5)
		if _spike_p50 > 0.0 and ms > spike_ms(_spike_p50) and _spike_log.size() < 60:
			_spike_log.push_back({"t": snappedf(_t, 0.01), "ms": snappedf(ms, 0.1), "tags": tags})
		for tg in tags:
			_seen[str(tg).trim_prefix("first:")] = true
		_script.push_back((Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		var start: int = _first.get("stamp") if _first != null else 0
		if start > 0:
			_span.push_back((Time.get_ticks_usec() - start) / 1000.0)
		if _screen != null and _screen.get("last_sim_ms") != null:
			_sim.push_back(float(_screen.get("last_sim_ms")))
		_setup.push_back(RenderingServer.get_frame_setup_time_cpu())
		_sample_vp("main", _main)
		if _pip != null and is_instance_valid(_pip):
			_sample_vp("pip", _pip)
		_cov_tick += 1
		if _cov_tick % 10 == 0:
			_cov.push_back(_coverage())

	## What is on screen this frame: card fx, pops, balls in flight, the PiP — a
	## tag reads "first:x" the frame it debuts.
	func _tags() -> Array:
		var out := []
		if _screen == null or not is_instance_valid(_screen):
			return out
		var court: Node = _screen.get("_court")
		if court != null:
			var fire: Node = court.get("_fire")
			var ice: Node = court.get("_ice")
			var mag: Node = court.get("_magnet")
			if fire != null and fire.is_lit():
				out.push_back("fire")
			if ice != null and ice.is_iced():
				out.push_back("ice")
			if mag != null and mag.is_up():
				out.push_back("magnet")
			if court.pop_count() > 0:
				out.push_back("pop")
		var trial: Variant = _screen.get("trial")
		if trial != null and trial.balls().size() > 0:
			out.push_back("flight")
		if _pip != null and is_instance_valid(_pip):
			out.push_back("pip")
		var heat: Variant = _screen.get("heat")
		if heat != null and heat.ai.fire_left() > 0.0:
			out.push_back("opp_fire")
		for i in out.size():
			if not _seen.has(str(out[i])):
				out[i] = "first:" + str(out[i])
		return out

	func _sample_vp(key: String, vp: Viewport) -> void:
		var rid := vp.get_viewport_rid()
		var s: Dictionary = _vp_sum[key]
		s["cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		s["gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		s["draws_v"] += vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		s["draws_s"] += vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		s["prims_v"] += vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		s["prims_s"] += vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		s["objs_v"] += vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		s["objs_s"] += vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		s["n"] += 1

	## Alpha-blended surfaces in the main view: the sum of their projected
	## bounding rects as a fraction of the screen (overdraw's upper bound).
	func _coverage() -> float:
		var cam := _main.get_camera_3d()
		if cam == null or _screen == null or not is_instance_valid(_screen):
			return 0.0
		var vp_size := Vector2(_main.get_visible_rect().size)
		var total := 0.0
		for gi in _screen.find_children("*", "GeometryInstance3D", true, false):
			var g := gi as GeometryInstance3D
			if g == null or not g.is_visible_in_tree() or g.get_viewport() != _main or not _is_blended(g):
				continue
			var aabb := g.global_transform * g.get_aabb()
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			var any_front := false
			for i in 8:
				var corner := aabb.get_endpoint(i)
				if cam.is_position_behind(corner):
					continue
				any_front = true
				var p := cam.unproject_position(corner)
				lo = lo.min(p)
				hi = hi.max(p)
			if not any_front:
				continue
			lo = lo.clamp(Vector2.ZERO, vp_size)
			hi = hi.clamp(Vector2.ZERO, vp_size)
			total += maxf(hi.x - lo.x, 0.0) * maxf(hi.y - lo.y, 0.0) / (vp_size.x * vp_size.y)
		return total

	func _is_blended(g: GeometryInstance3D) -> bool:
		var mats: Array = []
		if g.material_override != null:
			mats.push_back(g.material_override)
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(i)
				if m == null:
					m = mi.mesh.surface_get_material(i)
				if m != null:
					mats.push_back(m)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null and (g as MultiMeshInstance3D).multimesh.mesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh.mesh
			for i in mm.get_surface_count():
				var m: Material = mm.surface_get_material(i)
				if m != null:
					mats.push_back(m)
		for m in mats:
			if m is BaseMaterial3D and (m as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				return true
			if m is ShaderMaterial:
				var sm := m as ShaderMaterial
				if sm.shader == null:
					continue
				var key := sm.shader.get_rid()
				if not _alpha_cache.has(key):
					var code := sm.shader.code
					var re := RegEx.new()
					re.compile("\\bALPHA\\s*[*+\\-]?=")
					_alpha_cache[key] = re.search(code) != null and not code.contains("alpha_to_coverage") and not code.contains("ALPHA_SCISSOR_THRESHOLD")
				if bool(_alpha_cache[key]):
					return true
		return false

	## The spike threshold for a run whose p50 is `p50`: one refresh period over it, never under 1.5×.
	func spike_ms(p50: float) -> float:
		return maxf(1.5 * p50, p50 + _period)


	static func _pct(sorted: PackedFloat64Array, q: float) -> float:
		if sorted.is_empty():
			return 0.0
		var i := clampi(int(floor(q * (sorted.size() - 1))), 0, sorted.size() - 1)
		return sorted[i]

	func finish() -> Dictionary:
		measuring = false
		var fr := _frames.duplicate()
		fr.sort()
		var sc := _script.duplicate()
		sc.sort()
		var sp := _span.duplicate()
		sp.sort()
		var sm := _sim.duplicate()
		sm.sort()
		var p50 := _pct(fr, 0.5)
		var spikes := 0
		for v in _frames:
			if v > spike_ms(p50):
				spikes += 1
		var row := {
			"frames": _frames.size(), "seconds": snappedf(_t, 0.01),
			"frame_p50": snappedf(_pct(fr, 0.5), 0.01), "frame_p95": snappedf(_pct(fr, 0.95), 0.01), "frame_p99": snappedf(_pct(fr, 0.99), 0.01),
			"frame_max": snappedf(fr[fr.size() - 1] if not fr.is_empty() else 0.0, 0.01),
			"fps": snappedf(_frames.size() / maxf(_t, 0.001), 0.1),
			"hitches": _hitches.size(), "hitches_per_60s": snappedf(_hitches.size() * 60.0 / maxf(_t, 0.001), 0.1), "hitch_log": _hitches.slice(0, 20),
			"spikes": spikes, "spikes_per_60s": snappedf(spikes * 60.0 / maxf(_t, 0.001), 0.1), "spike_ms": snappedf(spike_ms(p50), 0.1),
			"spike_log": _spike_log, "spike_tags": _spike_tag_counts(),
			"loop_p50": snappedf(_pct(sc, 0.5), 0.01), "loop_p95": snappedf(_pct(sc, 0.95), 0.01),
			"script_p50": snappedf(_pct(sp, 0.5), 0.01), "script_p95": snappedf(_pct(sp, 0.95), 0.01),
			"sim_p50": snappedf(_pct(sm, 0.5), 0.01), "sim_p95": snappedf(_pct(sm, 0.95), 0.01),
			"casters": _screen.get("_court").caster_count() if _screen != null and _screen.get("_court") != null else 0,
			"setup_cpu_mean": snappedf(_mean(_setup), 0.01),
			"coverage_mean": snappedf(_mean(_cov), 0.001), "coverage_max": snappedf(_max(_cov), 0.001),
		}
		for k in ["main", "pip"]:
			var s: Dictionary = _vp_sum[k]
			var n := maxf(float(s["n"]), 1.0)
			if int(s["n"]) == 0:
				continue
			row[k] = {"cpu": snappedf(s["cpu"] / n, 0.01), "gpu": snappedf(s["gpu"] / n, 0.01),
				"draws_v": roundi(s["draws_v"] / n), "draws_s": roundi(s["draws_s"] / n),
				"prims_v": roundi(s["prims_v"] / n), "prims_s": roundi(s["prims_s"] / n),
				"objs_v": roundi(s["objs_v"] / n), "objs_s": roundi(s["objs_s"] / n)}
		return row

	## How many logged spikes carried each tag, and how many carried none.
	func _spike_tag_counts() -> Dictionary:
		var out := {"none": 0}
		for s in _spike_log:
			var tags: Array = s["tags"]
			if tags.is_empty():
				out["none"] += 1
			for tg in tags:
				out[str(tg)] = int(out.get(str(tg), 0)) + 1
		return out

	static func _mean(a: PackedFloat64Array) -> float:
		if a.is_empty():
			return 0.0
		var s := 0.0
		for v in a:
			s += v
		return s / a.size()

	static func _max(a: PackedFloat64Array) -> float:
		var m := 0.0
		for v in a:
			m = maxf(m, v)
		return m


## The first node to process each frame: it stamps the clock the probe reads last.
class FirstSentinel extends Node:
	var stamp := 0
	func _process(_dt: float) -> void:
		stamp = Time.get_ticks_usec()
