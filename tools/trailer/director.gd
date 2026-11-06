extends Node
## The trailer director (docs/TRAILER.md → The director): plays one shot
## file through the real game so Godot's Movie Maker can record it.
##   tools/trailer/capture.sh tools/trailer/shots/<shot>.json <appstore|social>
## It is started by the QA driver from `-- --qa-trailer=<shot.json>` and
## leans on the driver's helpers (clicks, the archive, sleeps). A shot is a
## list of steps, each one small verb: start a mode, replay a recorded
## flick, play a card, open a page, set the camera, mark a frame. Flicks are
## Ross's recordings (marketing/trailer/flicks/bank.json), fed back through
## FlickInput with their own timestamps; a stand-in gesture (FlickSynth) is
## used only where there is no recording, and the log says so.
##
## Clean frames: the music bus is muted (the edit lays the music), the
## tuning panel and the recorder are off, tours and the tutorial are off
## (every --qa pass), and nothing here draws on screen.
##
## `--qa-trailer-still` runs without Movie Maker and saves one PNG at the
## shot's `poster` step (the storyboard for Checkpoint A).

const OUT_ROOT := "res://marketing/trailer"
const BANK := OUT_ROOT + "/flicks/bank.json"
const FRAME_USEC := 1_000_000.0 / 60.0

var driver: Node
var shot: Dictionary = {}
var shot_name := ""
var layout := "appstore"
var still := false
var out_dir := ""
var _marks := {}
var _performed: Array = []     # what each flick step used: a recording's id, or "synth"
var _bank: Array = []
var _trail: TouchTrail
var _rim_cam: Camera3D
var _vclock := 5_000_000       # the replay's own clock (usec): gestures never overlap
var _stop := false
var _problems: Array = []


func start(p_driver: Node, args: PackedStringArray) -> void:
	driver = p_driver
	var path := _arg(args, "--qa-trailer=")
	layout = _arg(args, "--qa-trailer-layout=", "appstore")
	still = args.has("--qa-trailer-still")
	out_dir = _arg(args, "--qa-trailer-out=", ProjectSettings.globalize_path(OUT_ROOT + ("/checkpoint_a/frames/" if still else "/clips/") + layout))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed.get("steps") is Array):
		print("TRAILER: cannot read shot %s" % path)
		get_tree().quit(1)
		return
	shot = parsed
	shot_name = str(shot.get("name", path.get_file().get_basename()))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_load_bank()
	await _prepare()
	for step in shot["steps"]:
		if _stop:
			break
		await _do(step)
	_finish()


static func _arg(args: PackedStringArray, prefix: String, fallback := "") -> String:
	for a in args:
		if str(a).begins_with(prefix):
			return str(a).trim_prefix(prefix)
	return fallback


func _load_bank() -> void:
	if not FileAccess.file_exists(BANK):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BANK))
	if parsed is Dictionary and parsed.get("rows") is Array:
		_bank = parsed["rows"]


## The state every shot starts from: no network, no music, no debug UI, the
## shot's kit worn (without touching the save), the home showing.
func _prepare() -> void:
	Net.enabled = false
	Sfx.set_music_sound(false)
	App.music_on = false
	App.tuning_mode = false
	App.record_flicks = false
	var setup: Dictionary = shot.get("setup", {})
	if setup.has("help"):
		App.shot_help = {"off": App.SHOT_HELP_OFF, "numbers": App.SHOT_HELP_NUMBERS, "full": App.SHOT_HELP_FULL}.get(str(setup["help"]), App.SHOT_HELP_DEFAULT)
	_wear(str(setup.get("ball", "")), str(setup.get("net", "")))
	await _sleep(0.8)
	await driver.call("_close_archive")


## Wear a ball and a net for this shot, as the pause menu's ball cycle does: no save.
func _wear(ball: String, net: String) -> void:
	if ball != "":
		var bs := CosmeticLibrary.get_ball(ball)
		if bs != null:
			App.ball_set = bs
			Sfx.load_ball_set(bs)
		else:
			_problem("no ball '%s'" % ball)
	if net != "":
		var ns := CosmeticLibrary.get_net(net)
		if ns != null:
			App.net_override = ns
		else:
			_problem("no net '%s'" % net)


func _problem(text: String) -> void:
	_problems.push_back(text)
	print("TRAILER PROBLEM (%s): %s" % [shot_name, text])


func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _scene() -> Node:
	return get_tree().current_scene


## The court screen (a time trial or a heat), or null.
func _court() -> Node:
	var sc := _scene()
	return sc if sc != null and "trial" in sc else null


# ---- the steps -----------------------------------------------------------------------


func _do(step: Dictionary) -> void:
	match str(step.get("do", "")):
		"wait":
			await _sleep(float(step.get("s", 1.0)))
		"play":
			await _play(step)
		"spot":
			var c := _court()
			if c != null:
				c.call("_set_spot", int(step.get("i", 0)))
		"until":
			await _until(str(step.get("what", "ready")), float(step.get("timeout", 20.0)))
		"flick":
			await _flick(step)
		"mark":
			_marks[str(step.get("name", "in"))] = Engine.get_frames_drawn()
		"poster":
			await _poster(step)
		"time_scale":
			Engine.time_scale = float(step.get("x", 1.0))
		"camera":
			_camera(step)
		"hud":
			_show_hud(bool(step.get("on", true)))
		"wear":
			_wear(str(step.get("ball", "")), str(step.get("net", "")))
		"tap":
			await driver.call("_click_named", str(step.get("name", "")))
		"call":
			await _call(step)
		"end":
			_stop = true
		var other:
			if not await _do_staged(other, step):
				_problem("unknown step '%s'" % other)


## Steps that stage a page or a match (league, online, PEGGY, the locker…):
## tools/trailer/director_stages.gd, loaded on first use.
var _stages: RefCounted

func _do_staged(verb: String, step: Dictionary) -> bool:
	if _stages == null:
		var script: Variant = load("res://tools/trailer/director_stages.gd") if ResourceLoader.exists("res://tools/trailer/director_stages.gd") else null
		if script == null:
			return false
		_stages = script.new(self)
	if not _stages.has_method("stage_" + verb):
		return false
	await _stages.call("stage_" + verb, step)
	return true


## A time trial or a practice session on a court, held until the ball is live.
func _play(step: Dictionary) -> void:
	var mode := str(step.get("mode", "practice"))
	var area := str(step.get("area", "cage"))
	App.start_area(mode, area)
	for i in 200:
		await get_tree().process_frame
		if _court() != null:
			break
	var c := _court()
	if c == null:
		_problem("the %s %s court never loaded" % [area, mode])
		_stop = true
		return
	# The spot shuffle and its like run on a seed of ours: the same shot every render.
	if "_rng" in c:
		(c.get("_rng") as RandomNumberGenerator).seed = int(step.get("seed", 7))
	if step.has("spot"):
		c.call("_set_spot", int(step["spot"]))
	_attach_trail(c)
	await _until("running", 30.0)
	await _sleep(float(step.get("settle", 0.4)))


func _attach_trail(c: Node) -> void:
	if not bool(Dictionary(shot.get("setup", {})).get("trail", false)):
		return
	var input := c.find_child("FlickInput", true, false) as FlickInput
	if input == null:
		return
	_trail = TouchTrail.new()
	c.add_child(_trail)
	_trail.follow(input)


func _until(what: String, timeout: float) -> void:
	var waited := 0.0
	while waited < timeout:
		var c := _court()
		var ok := false
		if what == "peggy_card":
			var sc := _scene()
			var page: Variant = sc.call("peggy") if sc != null and sc.has_method("peggy") else null
			ok = page != null and page.prize_card() != null
		elif c != null:
			var trial: TimeTrial = c.get("trial")
			match what:
				"running":
					ok = trial.phase == TimeTrial.PHASE_RUNNING
				"ready":
					ok = trial.phase == TimeTrial.PHASE_RUNNING and not trial.holding and trial.ball_ready()
				"resolved":
					ok = trial._flights.all(func(f: Dictionary) -> bool: return bool(f["scored"]))
				"settled":
					ok = trial._flights.is_empty()
				"entered":   # a ball is in the net: the moment the nets are for
					ok = trial._flights.any(func(f: Dictionary) -> bool: return bool((f["state"] as BallState).ever_entered))
				_:
					ok = true
		if ok:
			return
		await get_tree().process_frame
		waited += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	_problem("waited %.0f s for '%s'" % [timeout, what])


## The hand position the court would give a release at this touch point
## (time_trial_screen._on_drag's maths, read-only).
func _origin_for(c: Node, pos: Vector2) -> Dictionary:
	var hit: Variant = c.call("_screen_to_plane", pos)
	var spot: Vector3 = c.get("_spot")
	if hit == null:
		return {"rx": spot.x, "ry": 1.25, "rz": spot.z}
	var right: Vector3 = c.get("_right")
	var p: Vector3 = hit
	var lat := clampf((p - spot).dot(right), -float(c.get("HAND_LATERAL")), float(c.get("HAND_LATERAL")))
	var yr: Vector2 = c.get("HAND_Y_RANGE")
	p = spot + right * lat + Vector3(0.0, clampf(p.y, yr.x, yr.y), 0.0)
	return {"rx": float(p.x), "ry": float(p.y), "rz": float(p.z)}


## One flick: a recording from the bank that fits (`pick`), else a stand-in
## found for the wanted outcome. `then`: "resolved" waits for the ball.
func _flick(step: Dictionary) -> void:
	var c := _court()
	if c == null:
		_problem("a flick with no court")
		return
	await _until("ready", 15.0)
	var want: Array = step.get("want", ["SWISH", "MAKE"])
	var row := _pick_recording(step, c, want)
	var used := ""
	var trace: Array = []
	var lift := 0
	if not row.is_empty():
		used = str(row.get("id", "recording"))
		trace = row["sample"]["trace"]
		lift = int(row["sample"].get("lift_usec", trace[-1][0]))
		if row.get("tuning") is Dictionary:
			(c.get("tuning") as FlickTuning).apply_dict(row["tuning"])   # the phone's values: the same launch
		if bool(Dictionary(row.get("ctx", {})).get("practice", false)) and bool(c.get("_practice")):
			c.call("_set_spot", int(Dictionary(row["ctx"]).get("spot", 0)))
			await _until("ready", 5.0)
	else:
		var trial: TimeTrial = c.get("trial")
		# `plain`: solve as if no Magnet were up — a near miss the card then pulls in.
		var geo: SimGeometry = trial.geo.with_magnet(false) if bool(step.get("plain", false)) else trial.geo
		var tr := FlickSynth.solve(want, c.get("tuning"), geo, func(pos: Vector2) -> Dictionary: return _origin_for(c, pos), int(step.get("seed", 1)))
		if tr.is_empty():
			_problem("no stand-in flick gives %s here" % str(want))
			return
		used = "synth:%s" % str(tr["outcome"]["type"])
		trace = tr["trace"]
		lift = int(tr["lift_usec"])
	_performed.push_back(used)
	print("TRAILER flick (%s): %s" % [shot_name, used])
	await _replay(c, trace, lift, bool(step.get("poster_mid", false)))
	match str(step.get("then", "")):
		"resolved":
			await _until("resolved", 8.0)
		"settled":
			await _until("settled", 10.0)


## A recording for this court and outcome: the nth that fits, or {}.
func _pick_recording(step: Dictionary, c: Node, want: Array) -> Dictionary:
	if _bank.is_empty() or bool(step.get("synth", false)):
		return {}
	var area := str(Dictionary(c.get("_mode")).get("location", "cage"))
	var fits := _bank.filter(func(r: Dictionary) -> bool:
		if step.has("id"):
			return str(r.get("id", "")) == str(step["id"])
		return str(Dictionary(r.get("ctx", {})).get("area", "")) == area and want.has(str(r.get("outcome", ""))) and bool(r.get("replays", false)))
	if fits.is_empty():
		return {}
	return fits[int(step.get("nth", 0)) % fits.size()]


## Feed a trace to the court's FlickInput with its own timestamps, one
## movie frame at a time: the estimator reads exactly what it read on the
## phone, and the held ball moves as it did under the finger.
func _replay(c: Node, trace: Array, lift_usec: int, poster_mid := false) -> void:
	var fi := c.find_child("FlickInput", true, false) as FlickInput
	if fi == null or trace.size() < 2:
		return
	var t0 := int(trace[0][0])
	var base := _vclock
	var lift := lift_usec - t0
	fi._begin_at(Vector2(float(trace[0][1]), float(trace[0][2])), base)
	var i := 1
	var elapsed := 0.0
	while i < trace.size() or elapsed < lift:
		await get_tree().process_frame
		elapsed += FRAME_USEC
		while i < trace.size() and int(trace[i][0]) - t0 <= elapsed:
			fi._move_at(Vector2(float(trace[i][1]), float(trace[i][2])), base + int(trace[i][0]) - t0)
			i += 1
		if poster_mid and i >= int(trace.size() * 0.85):
			poster_mid = false
			await _poster({"keep_going": not still})   # the swipe itself: the storyboard's frame for a flick shot
			if _stop:
				return
	fi._end_at(base + lift)
	_vclock = base + lift + 2_000_000


## The social cut's rim camera: a second camera does the looking while the
## court's own keeps doing the flick's ray maths, so the shot is unchanged.
## {"at": [dx,dy,dz], "look": [dx,dy,dz], "fov": 38} from the hoop; {"off": true}.
func _camera(step: Dictionary) -> void:
	var c := _court()
	if c == null:
		return
	if bool(step.get("off", false)):
		if _rim_cam != null:
			_rim_cam.queue_free()
			_rim_cam = null
		(c.get("_cam") as Camera3D).make_current()
		return
	if layout == "appstore" and not bool(step.get("allow_appstore", false)):
		_problem("a rim camera in an App Store shot (shooting view only)")
		return
	var geo: SimGeometry = (c.get("trial") as TimeTrial).geo
	var hoop := Vector3(geo.hoop_x, geo.hoop_y, geo.hoop_z)
	var at: Array = step.get("at", [-0.62, 0.16, 0.30])
	var look: Array = step.get("look", [0.0, -0.18, 0.0])
	if _rim_cam == null:
		_rim_cam = Camera3D.new()
		_rim_cam.name = "TrailerCam"
		c.add_child(_rim_cam)
	_rim_cam.fov = float(step.get("fov", 38.0))
	_rim_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_rim_cam.position = hoop + Vector3(float(at[0]), float(at[1]), float(at[2]))
	_rim_cam.look_at(hoop + Vector3(float(look[0]), float(look[1]), float(look[2])))
	_rim_cam.make_current()


## Hide or show every UI layer of the current screen (the rim camera has no HUD).
func _show_hud(on: bool) -> void:
	var sc := _scene()
	if sc == null:
		return
	for n in sc.find_children("*", "CanvasLayer", true, false):
		if n != _trail:
			(n as CanvasLayer).visible = on


## {"on": "scene" | "app" | "driver" | "node:<Name>", "method": …, "args": […], "wait": true}
func _call(step: Dictionary) -> void:
	var on := str(step.get("on", "scene"))
	var target: Object = _scene()
	if on == "app":
		target = App
	elif on == "driver":
		target = driver
	elif on.begins_with("node:"):
		target = get_tree().root.find_child(on.trim_prefix("node:"), true, false)
	var method := str(step.get("method", ""))
	if target == null or not target.has_method(method):
		_problem("call: no %s.%s" % [on, method])
		return
	var r: Variant = target.callv(method, step.get("args", []))
	if bool(step.get("wait", false)):
		await r


## The storyboard frame. Still mode: save it and stop. Movie mode: a mark.
func _poster(step: Dictionary) -> void:
	_marks["poster" + str(step.get("tag", ""))] = Engine.get_frames_drawn()
	if not still:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [out_dir, shot_name, str(step.get("tag", ""))]
	img.save_png(path)
	print("TRAILER poster: %s" % path)
	if not bool(step.get("keep_going", false)):
		_stop = true


func _finish() -> void:
	Engine.time_scale = 1.0
	_marks["end"] = Engine.get_frames_drawn()
	var f := FileAccess.open("%s/%s.marks.json" % [out_dir, shot_name], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"shot": shot_name, "layout": layout, "fps": 60, "marks": _marks, "flicks": _performed, "problems": _problems}, "  "))
		f.close()
	print("TRAILER done: %s (%s) marks=%s flicks=%s problems=%d" % [shot_name, layout, str(_marks), str(_performed), _problems.size()])
	get_tree().quit(0 if _problems.is_empty() else 2)
