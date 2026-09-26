extends Node3D
## The Time Trial game screen. Owns a TimeTrial rules instance and follows the
## renderer contract the Vue screens used (and M2's match screen will reuse):
##   frame: rules.tick(dt) → drain_events() (sfx + juice) → sync views + HUD.

## Baseline geometry (from App.MODES for the requested mode): the court's
## initial build and camera framing. The trial's live geo diverges from it
## during the moving-hoop phase, and AIMING FOLLOWS THE LIVE HOOP: flick
## mapping and the preview solve against trial.geo (led by flight time).
var base_geo: SimGeometry
var trial: TimeTrial
var tuning := FlickTuning.new()
## The mode's row from App.MODES, and the fixtures it resolved to.
var _mode: Dictionary
var _arena_set: ArenaSet
var _hoop_set: HoopSet

var _holding_visual := false
var _cam: Camera3D
var _court: CourtGeometry
var _pool: BallPool
var _hud: Hud
var _overlay: TuningOverlay
var _preview: AimPreview
var _readout: AimReadout
## Where this shot's wind-up started, on the hand plane. The shot-help numbers
## PIN here for the whole gesture rather than riding the ball down: the ball
## sinks toward the bottom edge as you pull, and readouts that follow it end up
## drifting exactly when you are trying to read them.
var _grab_anchor := Vector3.ZERO
var _anchor_pending := false
var _finished_handed_off := false
## Current wind-up depth (px) while holding — drives the preview arc.
var _pull_px := 0.0


## Endless practice (mode.endless): no clock, no results, BACK returns to title.
var _practice := false
## Streak tier the screen has already announced (0 = none; reset on a miss).
var _tier_shown := 1


func _ready() -> void:
	_mode = App.mode_config(App.next_mode)
	base_geo = App.geo_for_mode(App.next_mode)
	_make_rules()
	_practice = _mode["endless"]
	trial.endless = _practice
	trial.board_motion = _mode["board_motion"]
	_arena_set = CosmeticLibrary.get_arena(_mode["arena"])
	if _arena_set == null:
		_arena_set = CosmeticLibrary.starter_arena()
	_hoop_set = App.hoop_for_mode(App.next_mode)
	if _hoop_set != App.hoop_set:
		Sfx.load_hoop_set(_hoop_set)  # the mode's hoop owns make/miss here
	Sfx.rim_rigidity = base_geo.rim_rigidity()  # the iron rings to match how it bounces
	Sfx.start_ambience(_arena_set)  # the area's background layers (a no-op if already playing)
	_court = CourtGeometry.new()
	_court.name = "Court"
	_court.geo = base_geo
	_court.arena_set = _arena_set
	_court.hoop_set = _hoop_set
	add_child(_court)
	if _mode["led_text"] != "":
		_court.led.set_text(_mode["led_text"], _court.led.accent_color)
	else:
		_court.led.show_score(0)  # a plain reader board: the score, from the first shot

	# Camera: placed behind whichever shooting spot is active (_set_spot).
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = _arena_set.camera_fov if _arena_set != null else 60.0
	add_child(_cam)

	_pool = BallPool.new()
	_pool.name = "Balls"
	_pool.ball_set = App.ball_set
	add_child(_pool)

	_hud = Hud.new()
	_hud.name = "Hud"
	add_child(_hud)

	# Hints over the area's tappable props (the beach radio).
	var prop_layer := CanvasLayer.new()
	prop_layer.name = "PropUi"
	prop_layer.layer = 6
	add_child(prop_layer)
	_prop_icons = PropIcons.new()
	_prop_icons.name = "PropIcons"
	_prop_icons.setup(_court, _cam)
	prop_layer.add_child(_prop_icons)
	if _practice:
		_hud.set_practice(true, _mode["hud_label"])
	_add_back_button()
	_spots = _arena_set.spots() if _arena_set != null else [{"name": "KEY", "pos": Vector3.ZERO}]
	_set_spot(0)
	if _spots.size() > 1:
		_add_spot_picker()
		# Timed runs (time trials) don't allow free spot switching; only the
		# last-30 s shuffle moves the shooter. Practice keeps the picker. Heats
		# decide for themselves (league heats lock it).
		if not _practice and not bool(_mode.get("heat", false)):
			lock_spot_picker()
	_shuffle_enabled = bool(_mode.get("spot_shuffle", false)) and _spots.size() > 1
	_rng.randomize()
	if _practice:
		_add_thirty_button()

	# Tunables: the session-wide live instance (persisted overrides applied by App).
	tuning = App.tuning

	_preview = AimPreview.new()
	_preview.name = "AimPreview"
	add_child(_preview)

	var help_layer := CanvasLayer.new()
	help_layer.name = "ShotHelpUi"
	help_layer.layer = 7  # over the HUD and prop hints, under the debug chrome
	add_child(help_layer)
	_readout = AimReadout.new()
	_readout.name = "AimReadout"
	_readout.setup(_cam)
	help_layer.add_child(_readout)

	_overlay = TuningOverlay.new()
	_overlay.name = "Overlay"
	_overlay.tuning = tuning
	_overlay.geo = base_geo
	_overlay.touch_panel = App.tuning_mode
	if _practice:
		_overlay.fire_toggle = _toggle_fire_preview
		_overlay.ice_toggle = _toggle_ice_preview
	_overlay.ball_cycle = _cycle_ball
	add_child(_overlay)

	var input := FlickInput.new()
	input.name = "FlickInput"
	add_child(input)
	input.grab_pressed.connect(_on_grab)
	input.drag_moved.connect(_on_drag)
	input.windup_changed.connect(_on_windup)
	input.flick_charging.connect(_on_charging)
	input.flick_released.connect(_on_flick)
	_after_ready()


## The rules object this screen drives. The heat screen overrides it to run a
## Heat and point `trial` at the player's side.
func _make_rules() -> void:
	trial = TimeTrial.new(base_geo)


## Hook for subclasses once every view exists (the heat screen adds its PiP).
## The cage's back-wall league ribbon. The base shows attract copy; the heat
## screen overrides this with live league content. A no-op on an arena with no
## LeagueFace mesh, so callers need not care which arena they are in.
func _refresh_ticker() -> void:
	_court.set_ticker(TickerText.arcade_items(_best_score()))


## Top time-trial score for this location, 0 if none yet.
func _best_score() -> int:
	var top := SaveService.top_scores(1, str(_mode.get("location", "")))
	return int(top[0].get("score", 0)) if not top.is_empty() else 0


func _after_ready() -> void:
	_refresh_ticker()


## BACK to the title from either mode. Top-centre of the UI zone (well above
## the grab line, so it never intercepts a flick) and on the topmost canvas
## layer so the tuning strip can't sit over it. Leaving a trial mid-run just
## abandons it — nothing is scored or saved.
func _add_back_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BackUi"
	layer.layer = 11
	add_child(layer)
	var b := Button.new()
	b.text = "◀ BACK"
	b.add_theme_font_size_override("font_size", 24)
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.position = Vector2(270, 12)
	b.custom_minimum_size = Vector2(180, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(App.to_title)
	layer.add_child(b)
	_add_pause_button(layer)


## PAUSE (every mode): freezes the whole tree — sim, AI, clocks, animations —
## behind a dim overlay with RESUME / QUIT. The overlay itself keeps
## processing so its buttons work while paused. Leaving the screen unpauses.
var _pause_layer: CanvasLayer


func _add_pause_button(layer: CanvasLayer) -> void:
	var b := Button.new()
	b.name = "PauseButton"
	b.text = "⏸"
	b.add_theme_font_size_override("font_size", 26)
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.position = Vector2(196, 12)
	b.custom_minimum_size = Vector2(64, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(pause_game)
	layer.add_child(b)

	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseUi"
	_pause_layer.layer = 30
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.visible = false
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.1, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow touches: no flicks through the menu
	_pause_layer.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-220, -200)
	vb.size = Vector2(440, 400)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 22)
	_pause_layer.add_child(vb)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.81, 0.54))
	vb.add_child(title)
	var resume := Button.new()
	resume.name = "Resume"
	resume.text = "  RESUME ▶  "
	resume.add_theme_font_size_override("font_size", 34)
	resume.custom_minimum_size = Vector2(0, 84)
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(resume_game)
	vb.add_child(resume)
	# Shot help lives here rather than on the title screen so it can be flipped
	# mid-run and judged on the very next shot. The views read App.shot_help
	# every frame, so there is nothing to rewire when it changes.
	var help := Button.new()
	help.name = "ShotHelp"
	help.text = _shot_help_label()
	help.add_theme_font_size_override("font_size", 24)
	help.custom_minimum_size = Vector2(0, 60)
	help.focus_mode = Control.FOCUS_NONE
	help.add_theme_color_override("font_color", Color(0.62, 0.68, 0.85))
	help.pressed.connect(func() -> void:
		App.cycle_shot_help()
		help.text = _shot_help_label()
	)
	vb.add_child(help)
	var quit := Button.new()
	quit.name = "Quit"
	quit.text = "QUIT TO TITLE"
	quit.add_theme_font_size_override("font_size", 24)
	quit.custom_minimum_size = Vector2(0, 60)
	quit.focus_mode = Control.FOCUS_NONE
	quit.add_theme_color_override("font_color", Color(0.62, 0.68, 0.85))
	quit.pressed.connect(func() -> void:
		resume_game()
		App.to_title()
	)
	vb.add_child(quit)


func _shot_help_label() -> String:
	return "SHOT HELP: %s" % App.SHOT_HELP_LABELS[App.shot_help]


func pause_game() -> void:
	if _pause_layer == null or _finished_handed_off:
		return
	_pause_layer.visible = true
	get_tree().paused = true


func resume_game() -> void:
	if _pause_layer != null:
		_pause_layer.visible = false
	get_tree().paused = false


func is_paused() -> bool:
	return _pause_layer != null and _pause_layer.visible


## Leaving a mode that swapped the hoop's sounds restores the player's set,
## and never leaves the tree paused behind us.
func _exit_tree() -> void:
	get_tree().paused = false
	if _court != null:
		_court.leave_interactables()
	Sfx.stop_ambience()
	if _hoop_set != null and _hoop_set != App.hoop_set:
		Sfx.load_hoop_set(App.hoop_set)


func _on_grab() -> void:
	if trial.pickup():
		_holding_visual = true
		_anchor_pending = true  # pinned on the first drag of this grab


## Taps on the area's props (the beach radio) come first: a press that lands
## on one is consumed here — along with its release — so the flick input never
## sees it as a grab.
var _tap_index := -1
var _prop_icons: PropIcons


func _input(event: InputEvent) -> void:
	if _court == null or _cam == null or is_paused():
		return
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	var index := 0
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		pressed = t.pressed
		released = not t.pressed
		pos = t.position
		index = t.index
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var m := event as InputEventMouseButton
		pressed = m.pressed
		released = not m.pressed
		pos = m.position
		index = -2
	else:
		return
	if pressed:
		var icon: Dictionary = _prop_icons.hit_icon(pos) if _prop_icons != null else {}
		if not icon.is_empty():
			_tap_index = index
			(icon["it"] as Interactable).on_icon(str(icon["id"]), _court)
			get_viewport().set_input_as_handled()
			return
		var it := _court.pick_interactable(_cam, pos)
		if it != null:
			_tap_index = index
			it.on_tap(_court)
			get_viewport().set_input_as_handled()
	elif released and index == _tap_index:
		_tap_index = -1
		get_viewport().set_input_as_handled()


## For probes/tests: what a tap at this screen point would hit.
func interactable_at(pos: Vector2) -> Interactable:
	return _court.pick_interactable(_cam, pos) if _court != null else null


## Shooting spots. The arena lists where the shooter can stand; each spot has
## its own frame: `_fwd` toward the hoop, `_right` = fwd × up (screen-right for
## the camera behind the spot). The camera, the hand plane, the ball's rest
## pose and the reader board all follow the active spot; the hoop never moves.
var _spots: Array = []
var _spot_index := 0
var _spot := Vector3.ZERO
var _fwd := Vector3.RIGHT
var _right := Vector3.BACK
var _spot_buttons: Array[Button] = []

## Spot shuffle (the beach's "last 30 s"): with SHUFFLE_MARKS seconds left the
## game walks the shooter to a random other spot, each move announced for
## SHUFFLE_WARN seconds first (banner countdown, reader-board marquee, the
## target's picker button flashing). The picker is locked while it runs.
const SHUFFLE_MARKS := [30.0, 20.0, 10.0]
const SHUFFLE_WARN := 3.0
const SHUFFLE_PRACTICE_PERIOD := 10.0
var _shuffle_enabled := false
var _shuffle_next := 0           # index into SHUFFLE_MARKS (trial)
var _shuffle_clock := 0.0        # practice: seconds since the toggle went on
var _shuffle_mark_at := 0.0      # practice: clock value of the next move
## Practice "30 s mode" toggle: the arena's last-30-seconds mechanic on demand.
var _thirty_on := false
var _thirty_btn: Button
var _shuffle_target := -1        # spot index announced for the next mark
var _shuffle_shown := -1         # last countdown second shown
var _picker_locked := false
## Free spot switching (the picker row). League heats turn it off: only the
## last-30 s shuffle moves the shooter there.
var _picker_free := true
var _rng := RandomNumberGenerator.new()

## Held ball follows the finger: cast the touch through the camera onto the
## vertical hand plane through the spot (facing the camera) and clamp so the
## ball stays in frame. That point is also the shot's release origin — the sim
## aims from it at the hoop, so a shot from the side really is a shot from the side.
const HAND_Y_RANGE := Vector2(0.35, 2.3)
const HAND_LATERAL := 0.9
var _hand_pos: Vector3 = BallPool.HELD_POS


func _set_spot(i: int) -> void:
	_spot_index = clampi(i, 0, _spots.size() - 1)
	_spot = _spots[_spot_index]["pos"]
	var hoop := Vector3(base_geo.hoop_x, 0.0, base_geo.hoop_z)
	_fwd = hoop - _spot
	_fwd.y = 0.0
	_fwd = _fwd.normalized() if _fwd.length() > 1e-6 else Vector3.RIGHT
	_right = _fwd.cross(Vector3.UP)
	if trial.holding:
		trial.drop()  # walked away mid-hold: put the ball down
	_holding_visual = false
	_pull_px = 0.0
	# Camera 1.35 m behind the spot at eye height, looking at the hoop.
	_cam.position = _spot - _fwd * 1.35 + Vector3(0.0, 1.55, 0.0)
	var look_h: float = _arena_set.camera_look_height if _arena_set != null else 2.2
	_cam.look_at(Vector3(base_geo.hoop_x, look_h, base_geo.hoop_z))
	_pool.rest_pos = _spot + Vector3(0.0, 1.25, 0.0)
	_pool.set_held_position(_pool.rest_pos)
	_hand_pos = _pool.rest_pos
	if _preview != null:
		_preview.hide_preview()
	if _readout != null:
		_readout.clear()
	_anchor_pending = false
	_court.face_scoreboard(_spot)
	_refresh_picker()


## Hide and disable the picker row for the rest of the run.
func lock_spot_picker() -> void:
	_picker_free = false
	var ui := get_node_or_null("SpotUi")
	if ui != null:
		ui.visible = false
	_refresh_picker()


func picker_free() -> bool:
	return _picker_free


func _refresh_picker() -> void:
	for k in _spot_buttons.size():
		_spot_buttons[k].disabled = _picker_locked or not _picker_free or (k == _spot_index)
		_spot_buttons[k].modulate = Color.WHITE


## Seconds until the next spot move: the trial reads the clock's marks, practice
## runs its own rolling 10 s timer. INF when there is no move coming.
func _shuffle_remaining(dt: float) -> float:
	if _practice:
		_shuffle_clock += dt
		return _shuffle_mark_at - _shuffle_clock
	if trial.overtime or _shuffle_next >= SHUFFLE_MARKS.size():
		return INF
	return trial.time_left - SHUFFLE_MARKS[_shuffle_next]


func _shuffle_advance() -> void:
	if _practice:
		_shuffle_mark_at += SHUFFLE_PRACTICE_PERIOD
	else:
		_shuffle_next += 1


func _process_shuffle(dt: float) -> void:
	if not _shuffle_enabled or trial.phase != TimeTrial.PHASE_RUNNING:
		return
	var remaining := _shuffle_remaining(dt)
	if remaining > SHUFFLE_WARN:
		return
	var mark := 0.0
	var tl := remaining
	if _shuffle_target < 0:
		# Announce: pick a different spot, lock the picker, tell the board.
		_shuffle_target = _spot_index
		while _shuffle_target == _spot_index and _spots.size() > 1:
			_shuffle_target = _rng.randi_range(0, _spots.size() - 1)
		_picker_locked = true
		_refresh_picker()
		var nm: String = _spots[_shuffle_target]["name"]
		_court.led.marquee("MOVE TO %s" % nm, 24.0, _court.led.accent_color)
		if _shuffle_next == 0 and _shuffle_clock < SHUFFLE_PRACTICE_PERIOD:
			Sfx.score_pop(true)
	var nm2: String = _spots[_shuffle_target]["name"]
	var secs := ceili(tl - mark)
	if tl > mark:
		if secs != _shuffle_shown:
			_shuffle_shown = secs
			_hud.banner("→ %s in %d" % [nm2, secs], Color(1.0, 0.75, 0.3))
		# The target's button flashes.
		if _shuffle_target < _spot_buttons.size():
			var on := fmod(tl, 0.5) < 0.25
			_spot_buttons[_shuffle_target].modulate = Color(1.0, 0.85, 0.3) if on else Color.WHITE
		return
	# Time: walk over.
	_set_spot(_shuffle_target)
	_hud.banner("NOW SHOOTING: %s" % nm2, Color(0.4, 0.9, 0.55))
	_court.led.flash(nm2, 2, _court.led.accent_color)
	_shuffle_target = -1
	_shuffle_shown = -1
	_shuffle_advance()


## Practice-only toggle for the arena's "last 30 s" mechanic: the arcade's
## moving hoop, the beach's spot shuffle. Sits under the top row (below the
## spot picker / tuning strip when those are up), above the grab line.
func _add_thirty_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ThirtyUi"
	layer.layer = 11
	add_child(layer)
	var y := 330.0 if App.tuning_mode else 84.0
	if _spots.size() > 1:
		y += 50.0
	_thirty_btn = Button.new()
	_thirty_btn.text = "30s MODE: OFF"
	_thirty_btn.add_theme_font_size_override("font_size", 18)
	_thirty_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_thirty_btn.position = Vector2(12, y)
	_thirty_btn.custom_minimum_size = Vector2(220, 44)
	_thirty_btn.focus_mode = Control.FOCUS_NONE
	_thirty_btn.pressed.connect(_toggle_thirty)
	layer.add_child(_thirty_btn)


## Tuning-strip FIRE button: light/put out the rim to look at the effect.
func _toggle_fire_preview() -> void:
	_court.set_fire(not _court.fire_lit(), StreakRules.FIRE_AT + 3)


## Tuning-strip BALL button: step to the next cosmetic ball so the whole roster
## can be compared on consecutive shots.
##
## Deliberately NOT App.select(): that refuses any set the save does not own and
## a fresh save owns only "classic", and it only takes effect on the next screen
## build. This is a dev affordance — it swaps the live pool's skin and does not
## touch the save.
var _ball_index := -1


func _cycle_ball() -> String:
	var all := CosmeticLibrary.balls()
	if all.is_empty():
		return "?"
	if _ball_index < 0:
		# Start from whatever is actually equipped, so the first press advances.
		for i in all.size():
			if App.ball_set != null and all[i].id == App.ball_set.id:
				_ball_index = i
				break
	_ball_index = (_ball_index + 1) % all.size()
	var set_: BallSet = all[_ball_index]
	App.ball_set = set_
	Sfx.load_ball_set(set_)
	_pool.set_ball_set(set_)
	return set_.display_name


## Tuning-strip ICE button: ice the rim over / shatter it to look at the effect.
func _toggle_ice_preview() -> void:
	if _court.iced():
		_court.set_ice(false, "hits")
	else:
		_court.set_ice(true)


func _toggle_thirty() -> void:
	_thirty_on = not _thirty_on
	_thirty_btn.text = "30s MODE: ON" if _thirty_on else "30s MODE: OFF"
	if _spots.size() > 1:
		# Beach: the spot shuffle on a rolling clock.
		_shuffle_enabled = _thirty_on
		_shuffle_clock = 0.0
		_shuffle_mark_at = SHUFFLE_PRACTICE_PERIOD
		_shuffle_target = -1
		_shuffle_shown = -1
		if not _thirty_on:
			_picker_locked = false
			_refresh_picker()
			_hud.banner("30s mode off", Color(0.85, 0.88, 0.95))
		else:
			_hud.banner("30s MODE: spots shuffle every 10 s", Color(1.0, 0.75, 0.3))
	else:
		# Arcade: the figure-8 hoop, now.
		if _thirty_on:
			trial.board_motion = true
			trial.force_motion = true
			_hud.banner("30s MODE: hoop on the move", Color(1.0, 0.75, 0.3))
		else:
			trial.stop_motion()
			_hud.banner("30s mode off", Color(0.85, 0.88, 0.95))


## Spot picker: one small button per spot in the top UI zone (below the tuning
## strip when that is on), well above the grab line.
func _add_spot_picker() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SpotUi"
	layer.layer = 11
	add_child(layer)
	var row := HBoxContainer.new()
	row.position = Vector2(12, 330 if App.tuning_mode else 84)
	row.size = Vector2(696, 44)
	row.add_theme_constant_override("separation", 6)
	layer.add_child(row)
	for k in _spots.size():
		var b := Button.new()
		b.text = _spots[k]["name"]
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_spot.bind(k))
		row.add_child(b)
		_spot_buttons.push_back(b)
	for k in _spot_buttons.size():
		_spot_buttons[k].disabled = (k == _spot_index)


## Screen point → world point on the vertical plane through the spot, via the
## camera. Returns a Vector3, or null if the ray misses the plane.
func _screen_to_plane(pos: Vector2) -> Variant:
	if _cam == null:
		return null
	var plane := Plane(_fwd, _spot)
	return plane.intersects_ray(_cam.project_ray_origin(pos), _cam.project_ray_normal(pos))


func _on_drag(pos: Vector2) -> void:
	if not trial.holding:
		return
	var hit = _screen_to_plane(pos)
	if hit == null:
		return
	var p: Vector3 = hit
	# Clamp in the shooter's frame: height, and sideways along the spot's right.
	var lat := clampf((p - _spot).dot(_right), -HAND_LATERAL, HAND_LATERAL)
	p = _spot + _right * lat + Vector3(0.0, clampf(p.y, HAND_Y_RANGE.x, HAND_Y_RANGE.y), 0.0)
	_hand_pos = p
	_pool.set_held_position(p)
	if _anchor_pending:
		_grab_anchor = p
		_anchor_pending = false
	_refresh_preview()
	_refresh_readout()


## Wind-up: the deepest pull-back so far sets the arc; show where a
## perfect-power throw at that arc would go, from the hand's current spot.
func _on_windup(pull_px: float) -> void:
	_pull_px = pull_px
	_refresh_preview()
	_refresh_readout()


## Tuning mode draws the whole arc to the rim (a dev aid). Shot help draws most
## of it, tapering out before the rim — the launch and the arc, without quite
## handing over where the ball lands.
const HELP_ARC_FRAC := 0.85
## The numbers sit this far to the shooter's left of the ball — close enough to
## read in the same glance, far enough that they never cover it. The ball is
## 0.242 m across, so this clears its edge by about half a ball.
const HELP_SIDE := 0.18


func _refresh_preview() -> void:
	if not trial.holding or not (App.tuning_mode or App.shot_help == App.SHOT_HELP_FULL):
		_preview.hide_preview()
		return
	var viewport_h := get_viewport().get_visible_rect().size.y
	var angle := FlickMap.windup_angle(_pull_px, viewport_h, tuning)
	var frac := 1.0 if App.tuning_mode else HELP_ARC_FRAC
	_preview.show_preview(_hand_pos, angle, _lead_geo(angle, NAN), frac)


## The shot-help numbers. Same angle and same lead geometry the arc solves
## against, so the readout can never disagree with the line it sits beside.
func _refresh_readout() -> void:
	if _readout == null:
		return
	if not trial.holding or App.shot_help == App.SHOT_HELP_OFF or _anchor_pending:
		_readout.clear()
		return
	var viewport_h := get_viewport().get_visible_rect().size.y
	var angle := FlickMap.windup_angle(_pull_px, viewport_h, tuning)
	# Pinned in HEIGHT to where the wind-up started, but tracking the ball
	# sideways: the ball sinks as you pull (so a readout that follows it
	# vertically drifts away mid-read), yet it also slides left and right with
	# your thumb, and numbers that ignored that would drift off the ball.
	var lat := (_hand_pos - _spot).dot(_right) - HELP_SIDE
	var anchor := _spot + _right * lat + Vector3(0.0, _grab_anchor.y, 0.0)
	_readout.aim(anchor, angle, _hand_pos, _lead_geo(angle, NAN))


## Live throw strength, for the power number. Only meaningful once latched.
func _on_charging(speed_sh: float, latched: bool) -> void:
	if _readout != null and App.shot_help != App.SHOT_HELP_OFF and trial.holding:
		_readout.power(speed_sh, latched, tuning)


## The hoop pose to aim at: where it will be after this shot's flight time.
## speed NAN → use the ideal speed for the arc (preview); dist defaults to the
## current slant from the hand.
func _lead_geo(angle_deg: float, speed: float, dist := NAN) -> SimGeometry:
	if not trial.moving:
		return trial.geo
	var g := trial.geo
	if is_nan(dist):
		var dx := g.hoop_x - _hand_pos.x
		var dz := g.hoop_z - _hand_pos.z
		dist = sqrt(dx * dx + dz * dz)
	var v := speed
	if is_nan(v):
		v = Ballistics.speed_for_angle(angle_deg, dist, g.hoop_y - _hand_pos.y)
		if is_nan(v):
			return g
	var ft := Ballistics.flight_time(angle_deg, v, dist)
	return trial.geo_in(clampf(ft, 0.0, 2.0))


func _on_flick(sample: Dictionary) -> void:
	_preview.hide_preview()
	if not trial.holding:
		return
	# Release origin = where the hand ball is right now (sim space, float64 keys).
	var origin := {"rx": float(_hand_pos.x), "ry": float(_hand_pos.y), "rz": float(_hand_pos.z)}
	var launch := FlickMap.map_windup(sample, tuning, trial.geo, origin)
	if not launch.is_empty() and trial.moving:
		# Lead the moving hoop: re-solve against where it will be when the ball
		# arrives (one refinement pass — the flight time barely changes).
		var lead := _lead_geo(launch["angle_deg"], launch["speed"], launch.get("dist", trial.geo.hoop_x))
		launch = FlickMap.map_windup(sample, tuning, lead, origin)
	_overlay.record_flick(sample, launch)
	if launch.is_empty():
		_refresh_readout()  # cancelled gesture: ball stays in hand, so do the numbers
		return
	if _readout != null and App.shot_help != App.SHOT_HELP_OFF:
		# The release sample is the honest speed; the live value was still
		# climbing. Freeze on that and hold it into the flight.
		var vh: float = float(sample["viewport_h"])
		var sh: float = Vector2(sample["vel_x"], sample["vel_y"]).length() / vh if vh > 0.0 else 0.0
		_readout.freeze(sh, tuning)
	trial.release(launch)
	_holding_visual = false


var _applied_geo: SimGeometry


## Frame-delta clamp (s), as in the original's render loop: a hitch must not
## dump a whole backlog into the 240 Hz sim in one frame (ball teleports).
const MAX_FRAME_DT := 0.05


func _process(dt: float) -> void:
	_step_rules(minf(dt, MAX_FRAME_DT))
	_process_shuffle(dt)

	# Board slide: TimeTrial swaps in a fresh geo instance each moving step —
	# object identity is the cheap change signal.
	if trial.geo != _applied_geo:
		_applied_geo = trial.geo
		_court.apply_geometry(trial.geo)
		_overlay.geo = trial.geo
		if trial.holding:
			_refresh_preview()  # the dotted arc slides with the hoop
			_refresh_readout()

	# View sync.
	_holding_visual = trial.holding
	_pool.update_balls(trial.balls(), _holding_visual, dt)
	_court.step_rim(dt)
	_court.step_net(dt, trial.balls())
	_hud.update_clock(trial.time_left, trial.countdown, trial.phase)
	# Backboard light band: flashes yellow as the clock runs down.
	if trial.phase == TimeTrial.PHASE_RUNNING and not _practice:
		_court.led.band_flash(_court.led.band_flash_color, LedBoard.band_hz_for(trial.time_left))


## Advance the rules and dispatch their events (the heat screen overrides this
## to tick both sides and route the opponent's events to its own court).
func _step_rules(dt: float) -> void:
	trial.tick(dt)
	for ev in trial.drain_events():
		_handle_event(ev)


func _handle_event(ev: Dictionary) -> void:
	match ev["kind"]:
		"go":
			if not _practice:
				_hud.banner("GO! 🏀", Color(0.4, 0.9, 0.55))
				_court.led.set_text("")
				_court.led.show_score(0)
				_court.led.flash("GO!", 2, _court.led.accent_color)
		"ot_period":
			# Overtime opens with everyone back at the key, no shuffle pending.
			_shuffle_target = -1
			if _spots.size() > 1:
				_set_spot(0)
		"contact":
			var c: Dictionary = ev["contact"]
			if c["kind"] == "enter":
				# Ball just dropped into the rim: play the make clip NOW rather than
				# 22 cm later when the sim declares the make (the audible swish
				# happens at entry in life too, in-and-outs included).
				Sfx.make()
				return
			if c["kind"] == "ice_catch" or c["kind"] == "ice_pop":
				return  # the trial's ice_caught / ice_break events carry the show
			Sfx.contact(c["kind"], c["speed"])
			# GROUND ONLY. The dent offsets the ball's drawn position by up to
			# R_BALL * MAX_SQUASH (3.6 cm) into the surface so the flattened
			# face stays planted. On the floor that is invisible and correct;
			# next to the rim it is 3.6 cm of lie about where the ball is,
			# right where the player is judging whether it went in.
			if c["kind"] == "floor":
				_pool.squash_at(
					Vector3(c["pos"]["x"], c["pos"]["y"], c["pos"]["z"]),
					Vector3(c["normal"]["x"], c["normal"]["y"], c["normal"]["z"]),
					c["speed"])
			if c["kind"] == "rim":
				_court.rim_react(c["speed"])
				# Recorded miss clip on the rim hit itself (immediate, no waiting
				# for the outcome); rate-limited so a rattle plays it once.
				Sfx.miss_on_rim()
		"outcome":
			_on_outcome(ev["outcome"], ev["buzzer_beater"])
		# Hot/cold streak and ice feedback is scoreboard-only for now (no HUD
		# banners or chip) — the rig animations and the LED carry it.
		"ice_on":
			_court.set_ice(true)
			_court.led.marquee("ICED OVER", 24.0, _court.led.accent_color)
		"ice_caught":
			_court.ice_grab()
			_court.led.flash("CAUGHT", 2, _court.led.accent_color)
		"ice_crack":
			_court.ice_crack(int(ev["left"]))
		"ice_break":
			_court.set_ice(false, str(ev["by"]))
			_court.led.marquee("ICE BROKEN", 24.0, _court.led.accent_color)
		"fire_on":
			# A fire card: lit from FIRE_AT for the card's window.
			_tier_shown = 1
			_court.set_fire(true, StreakRules.FIRE_AT)
			_court.led.marquee("ON FIRE", 24.0, _court.led.accent_color)
			Sfx.score_pop(true)
		"fire_off":
			# The card's window closed (a miss already cooled it via the outcome).
			_tier_shown = 1
			_court.led.show_score(trial.score)
			if _court.fire_lit():
				_court.set_fire(false)
				_court.led.marquee("BURNED OUT" if str(ev.get("reason", "")) == "time" else "COOLED OFF", 24.0, _court.led.accent_color)
		"heat_up":
			Sfx.score_pop(true)
			_hud.banner("🔥 HEATING UP!", Color(1.0, 0.55, 0.2))
			_court.led.marquee("HEATING UP", 24.0, _court.led.accent_color)
			_court.flare_lights()
		"buzzer":
			Sfx.buzzer()
			_hud.banner("⏰ TIME!", Color(1.0, 0.45, 0.45))
			_court.led.set_text("TIME")
			_court.led.band_solid(_court.led.band_buzzer_color, 2.0)
			_court.play_arena("CageShake")
		"done":
			if not _practice:
				_finish()


func _on_outcome(outcome: Dictionary, buzzer_beater: bool) -> void:
	_overlay.record_outcome(outcome)
	var streak: int = outcome.get("streak", trial.streak)
	var pts: int = outcome["points"]
	var accent := _court.led.accent_color
	if outcome.get("iced_out", false):
		# The ball went in but only cleared the ice (the ice_break event just
		# announced it). Net/rim react; nothing to score.
		_court.rim_nudge()
		return
	if outcome["made"]:
		var is_swish: bool = outcome["type"] == ShotClassify.SWISH
		var tier := StreakRules.base_points(streak)
		var lit := StreakRules.is_lit(streak)
		# (The make clip already played on the "enter" contact event.)
		_hud.set_score(trial.score)
		_refresh_ticker()
		_court.led.show_score(trial.score, tier)
		# The net reacts to the ball itself (NetSim); the pivot spring adds a
		# little rim bounce even on a clean swish (rim contacts kick it harder).
		_court.rim_nudge()
		# HUD banners are plain scoring only; the streak story stays on the LED.
		if buzzer_beater:
			_hud.banner("🚨 BUZZER BEATER +%d!" % pts, Color(1.0, 0.6, 0.2))
			_court.led.flash("BUZZER +%d" % pts, 3, accent)
		elif is_swish:
			_hud.banner("✨ SWISH +%d" % pts)
			_court.led.flash("SWISH +%d" % pts, 2, accent)
		else:
			_hud.banner("+%d" % pts, Color(0.9, 0.95, 1.0))
		if lit and streak == StreakRules.FIRE_AT:
			_court.led.marquee("ON FIRE", 24.0, accent)
			Sfx.score_pop(true)
		elif lit and tier > _tier_shown:
			_court.led.marquee("%d PTS A BASKET" % tier, 24.0, accent)
			Sfx.score_pop(true)
		if lit:
			_tier_shown = tier
			_court.set_fire(true, streak)
	else:
		_tier_shown = 1
		_court.led.show_score(trial.score)
		if _court.fire_lit():
			_court.set_fire(false)
			_court.led.marquee("COOLED OFF", 24.0, accent)
		elif outcome["type"] == ShotClassify.IN_AND_OUT:
			_hud.banner("💔 in and out!", Color(1.0, 0.5, 0.6))


func _finish() -> void:
	if _finished_handed_off:
		return
	_finished_handed_off = true
	_court.set_fire(false)
	_court.set_ice(false)
	var run := {
		"score": trial.score,
		"makes": trial.makes,
		"swishes": trial.swishes,
		"attempts": trial.attempts,
		"bestStreak": trial.best_streak,
		"bonus": trial.bonus_points,
		"iced": trial.times_iced,
		"location": _mode.get("location", "cage"),
	}
	# Let the last banner breathe before switching, like the original's delay.
	get_tree().create_timer(1.4).timeout.connect(func() -> void: App.finish_run(run))
