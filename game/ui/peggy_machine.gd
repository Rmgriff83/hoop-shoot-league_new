class_name PeggyMachine
extends SubViewportContainer
## PEGGY, the PEGGY page's drop machine (docs/LOCKER.md): the v2 carnival
## cabinet in its own little world, and the hands that work it. The joystick
## drives the crane along the full rail (a servo whines while it moves); PLAY
## on the page feeds a ticket — the big ticket flies in from the bottom of
## the screen, holds, shrinks and slides into the console slot — and CREDITS
## the machine (the DROP cap glows and its halo pulses until used); the DROP
## button spends the credit: App.peggy_drop() runs the headless board and
## the puck's path plays back here — pegs flash and tick, the bay lights,
## the bulbs flare — then `dropped` hands the prize record to the page. The
## prizes stay hidden: each bay shows a generic ball or net with a "?" and
## its plate's rarity dot. Short of tickets with no credit the cap goes grey
## with a slow-flashing red X. The glb's node names are the contract with
## tools/blender/build_peggy.py. Transparent around the cabinet.

signal dropped(prize: Dictionary)
signal aim_changed(aim: float)
signal credited
signal feeding(frac: float)
## The cabinet is in (at once when it loads synchronously; after the slot
## spinner when it loads on a thread).
signal model_loaded

const GLB := "res://assets/locker/peggy.glb"
const FEED_S := 2.1
const PLAY_RATE := 0.75
const U := 0.1
const BOARD_Y0 := 0.54
const BZ := 0.06
const PZ := BZ + 0.02
const CRANE_V := 5.5               # board units a second at full tilt
const FOV := 36.0
const CAM_LOOK := Vector3(0.0, 1.15, 0.0)
const CAM_Y := 1.38
const JOY_R := 0.18                # hit circles, metres (the console is scaled 1.3)
const BTN_R := 0.20
const LANDED_HOLD := 2.4
const TIER_COLOR := {
	"common": Color("#8FC1E3"), "rare": Color("#3F8C7A"), "epic": Color("#E0457B"), "legend": Color("#F0B84A"),
}
const BULB_COLORS := ["#E8703A", "#F0B84A", "#3FBF8C", "#F0B84A", "#E8703A", "#3FBF8C", "#F1E8D0"]
const CAP_ORANGE := Color("#E8703A")
const CAP_DIM := Color("#7A4A34")
const CAP_GREY := Color("#5A514A")

## Load the cabinet on a thread with the slot spinner up (design "Loading
## States" 39b: the slot keeps its size and face, the spinning ball sits in
## the middle until the model is in). App turns it on; tests and the instant
## QA passes build synchronously.
static var threaded := false
const SPINNER_PX := 40.0

var tilt := 0.0
var _spinner: PixelSpinner
var _pending := false

var _vp: SubViewport
var _cam: Camera3D
var _root: Node3D
var _puck: Node3D
var _crane: Node3D
var _stick: Node3D
var _knob: Node3D
var _cap: MeshInstance3D
var _cap_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _xmark: Node3D
var _x_red: StandardMaterial3D
var _x_ink: StandardMaterial3D
var _deck: Node3D
var _slot_mark: Node3D
var _ticket: Node3D
var _big_ticket: MeshInstance3D
var _big_mat: StandardMaterial3D
var _pegs: Array = []
var _sprites: Array = []
var _sprite_mats: Array = []
var _lights: Array = []
var _light_mats: Array = []
var _bulbs: Array = []
var _bulb_mats: Array = []
var _glows: Array = []
var _glow_mats: Array = []
var _flash_mat: StandardMaterial3D
var _t := 0.0
var _flare := 0.0
var _aim := 0.0
var _joy_x0 := 0.0
var _joy_w := 1.0
var _joy_down := false
var _credit := false
var _locked := false
var _feeding := false
var _feed := 0.0
var _playing := false
var _play_t := 0.0
var _path: Array = []
var _hits: Array = []
var _hit_i := 0
var _prize: Dictionary = {}
var _landed_slot := -1
var _landed_at := -1.0
var _slots: Array = []
var _rail_y := 0.0
var _cap_z := 0.05


func _init() -> void:
	name = "Peggy"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


## Built in _init so the page (and the tests) can read the machine before it
## is in the tree.
func _build() -> void:
	_vp = SubViewport.new()
	_vp.name = "PeggyViewport"
	_vp.size = Vector2i(576, 1000)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 1.0, 1.0)
	e.ambient_light_energy = 0.9
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.4
	sun.light_color = Color("#FFF4E6")
	sun.position = Vector3(1.2, 2.6, 3.0)
	sun.look_at_from_position(Vector3(1.2, 2.6, 3.0), Vector3.ZERO, Vector3.UP)
	sun.shadow_enabled = false
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = FOV
	_cam.near = 0.05
	_cam.far = 20.0
	_vp.add_child(_cam)
	_rail_y = BOARD_Y0 + PeggyBoard.RELEASE_Y * U + 0.05
	if threaded and not ResourceLoader.has_cached(GLB) and ResourceLoader.load_threaded_request(GLB, "", true) == OK:
		_pending = true
		_spinner = PixelSpinner.new(SPINNER_PX)
		_spinner.name = "SlotSpinner"
		add_child(_spinner)
		_center_spinner()
	else:
		_attach(load(GLB))
	_fit_camera(Vector2(576, 1000))
	gui_input.connect(_on_gui_input)
	resized.connect(func() -> void:
		_fit_camera(size)
		_center_spinner())
	set_process(true)


func _attach(scene: PackedScene, late := false) -> void:
	if scene == null:
		return
	_root = scene.instantiate()
	_root.name = "Cabinet"
	_vp.add_child(_root)
	_bind()
	if late:   # the page set the plates and read the save while it loaded
		set_slots(_slots)
		refresh_state()


## Whether the cabinet is in (false while the threaded load runs).
func loaded() -> bool:
	return _root != null


func _center_spinner() -> void:
	if _spinner != null:
		_spinner.position = ((size - _spinner.size) * 0.5).round()


## Poll the threaded load; when the model is in, drop the spinner.
func _poll_load() -> void:
	var st := ResourceLoader.load_threaded_get_status(GLB)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_pending = false
	var scene: PackedScene = ResourceLoader.load_threaded_get(GLB) if st == ResourceLoader.THREAD_LOAD_LOADED else load(GLB)
	_attach(scene, true)
	if _spinner != null:
		_spinner.queue_free()
		_spinner = null
	model_loaded.emit()


## The design's fit: the whole cabinet (2.7 m tall, 1.18 m wide) in frame
## at any aspect, the camera a little above the board's middle.
func _fit_camera(px: Vector2) -> void:
	if _cam == null or px.x <= 0.0 or px.y <= 0.0:
		return
	var aspect := px.x / px.y
	var half := tan(deg_to_rad(FOV) * 0.5)
	var fit := 2.7 / (2.0 * half)
	var fit_w := 1.18 / (2.0 * half * aspect)
	var d := maxf(fit, fit_w) * 0.97
	_cam.look_at_from_position(Vector3(0.0, CAM_Y, d), CAM_LOOK, Vector3.UP)


func _node(n: String) -> Node:
	return _root.find_child(n, true, false) if _root != null else null


static func _unshaded(colour: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


func _bind() -> void:
	_puck = _node("Puck")
	_crane = _node("Crane")
	_stick = _node("Stick")
	_knob = _node("Knob")
	_xmark = _node("XMark")
	if _xmark != null:
		# The red X on the locked cap pulses in opacity (never fully off).
		_x_red = _unshaded(Color("#E8302E"))
		_x_red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_x_ink = _unshaded(Color("#221C18"))
		_x_ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for c in _xmark.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).material_override = _x_red if String(c.name).begins_with("XRed") else _x_ink
	_deck = _node("Deck")
	_slot_mark = _node("SlotMark")
	_ticket = _node("Ticket")
	if _ticket != null:
		_ticket.visible = false
	_cap = _node("Cap")
	if _cap != null:
		_cap_z = _cap.position.z
		_cap_mat = StandardMaterial3D.new()
		_cap_mat.albedo_color = CAP_ORANGE
		_cap_mat.roughness = 0.45
		_cap_mat.emission_enabled = true
		_cap_mat.emission = Color("#4A1A08")
		_cap.material_override = _cap_mat
	var halo: MeshInstance3D = _node("Halo")
	if halo != null:
		_halo_mat = _unshaded(Color(Color("#F0B84A"), 0.0))
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo.material_override = _halo_mat
	_big_ticket = _node("BigTicket")
	if _big_ticket != null:
		_big_mat = _unshaded(Color.WHITE, load("res://assets/textures/peggy_big_ticket.png"))
		_big_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_big_mat.alpha_scissor_threshold = 0.1
		_big_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_big_mat.no_depth_test = true
		_big_mat.render_priority = 100
		_big_ticket.material_override = _big_mat
		_big_ticket.visible = false
	_flash_mat = _unshaded(Color("#F1E8D0"))
	var glow_tex: Texture2D = load("res://assets/textures/peggy_glow.png")
	for n in BeachFx._descendants(_root):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if nm.begins_with("Bulb"):
			_bulbs.push_back(mi)
		elif nm.begins_with("Glow"):
			_glows.push_back(mi)
		elif nm.begins_with("Peg") or nm.begins_with("Bumper") or nm.begins_with("Divider"):
			_pegs.push_back(mi)
		elif nm.begins_with("PrizeSprite"):
			_sprites.push_back(mi)
		elif nm.begins_with("SlotLight"):
			_lights.push_back(mi)
	var by_name := func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name)
	_pegs.sort_custom(func(a: Node, b: Node) -> bool: return _peg_order(a) < _peg_order(b))
	_bulbs.sort_custom(by_name)
	_glows.sort_custom(by_name)
	_lights.sort_custom(by_name)
	_sprites.sort_custom(by_name)
	for i in _bulbs.size():
		var c := Color(BULB_COLORS[i % BULB_COLORS.size()])
		var bm := _unshaded(c)
		(_bulbs[i] as MeshInstance3D).material_override = bm
		_bulb_mats.push_back(bm)
	for i in _glows.size():
		var c := Color(BULB_COLORS[i % BULB_COLORS.size()])
		var gm := _unshaded(Color(c, 0.5), glow_tex)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm.no_depth_test = true
		(_glows[i] as MeshInstance3D).material_override = gm
		_glow_mats.push_back(gm)
	for l in _lights:
		var lm := _unshaded(Color(Color("#F0B84A"), 0.0))
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		(l as MeshInstance3D).material_override = lm
		_light_mats.push_back(lm)
	for s in _sprites:
		var sm := _unshaded(Color.WHITE)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sm.alpha_scissor_threshold = 0.3
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		(s as MeshInstance3D).material_override = sm
		(s as MeshInstance3D).visible = false
		_sprite_mats.push_back(sm)
	_place()


## The core's peg order (an even row's bumper, pegs, bumper; an odd row's
## pegs; then dividers), so a hit's peg index from PeggyBoard.simulate()
## maps straight onto a mesh.
static func _peg_order(n: Node) -> int:
	var table := PeggyBoard.pegs()
	var nm := String(n.name)
	var kind := "peg"
	if nm.begins_with("Bumper"):
		kind = "bumper"
	elif nm.begins_with("Divider"):
		kind = "divider"
	var k := nm.trim_prefix("Peg").trim_prefix("Bumper").trim_prefix("Divider").to_int()
	var seen := 0
	for i in table.size():
		if table[i]["kind"] == kind:
			if seen == k:
				return i
			seen += 1
	return 999


# ---- plates ---------------------------------------------------------------------


## Show the next drop's plates: a hidden prize per bay — the generic ball or
## net with the plate's rarity dot — nothing on a refund plate.
func set_slots(slots: Array) -> void:
	_slots = slots
	for i in mini(slots.size(), _sprites.size()):
		var s: Dictionary = slots[i]
		var id := str(s.get("id", ""))
		var mi := _sprites[i] as MeshInstance3D
		mi.visible = id != ""
		if id != "":
			var kind := str(s.get("kind", "ball"))
			var rarity := str(s.get("rarity", ""))
			if not TIER_COLOR.has(rarity):
				rarity = "common"
			var tex: Texture2D = load("res://assets/textures/peggy_mystery_%s_%s.png" % [kind, rarity])
			(_sprite_mats[i] as StandardMaterial3D).albedo_texture = tex
			(_sprite_mats[i] as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	for lm in _light_mats:
		(lm as StandardMaterial3D).albedo_color.a = 0.0
	_landed_slot = -1
	_landed_at = -1.0
	_place()


func slots() -> Array:
	return _slots


## Read the save's state: the credit in the machine and whether a play is
## affordable (the page calls this on arrival and after every change).
func refresh_state() -> void:
	_credit = App.peggy_credit()
	_locked = not _credit and App.tickets() < PeggyPrizes.DROP_COST
	if _xmark != null:
		_xmark.visible = _locked


func credit() -> bool:
	return _credit


func locked() -> bool:
	return _locked


# ---- aim ------------------------------------------------------------------------


func aim() -> float:
	return _aim


func set_aim(x: float) -> void:
	var a := PeggyBoard.clamp_aim(x)
	if absf(a - _aim) < 1e-9:
		return
	_aim = a
	_place()
	aim_changed.emit(_aim)


func nudge(dx: float) -> void:
	set_aim(_aim + dx)


func _place() -> void:
	if _crane != null:
		_crane.position.x = _aim * U
	if _puck != null and not _playing and _landed_slot < 0:
		_puck.position = Vector3(_aim * U, _rail_y - 0.075, PZ)


# ---- PLAY and DROP ----------------------------------------------------------------


func is_busy() -> bool:
	return _playing or _feeding or _pending


func playing() -> bool:
	return _playing


func feed_fraction() -> float:
	return clampf(_feed / FEED_S, 0.0, 1.0) if _feeding else 0.0


## PLAY: the ticket flies in; at the end the machine is credited (the page
## has already spent the tickets through App.peggy_insert_ticket, so a quit
## mid-flight keeps the credit). False while busy or already credited.
func insert_ticket() -> bool:
	if _feeding or _playing or _credit:
		return false
	_feeding = true
	_feed = 0.0
	_flare = 0.5
	_landed_slot = -1
	_landed_at = -1.0
	_place()
	Sfx.peggy_ticket()
	feeding.emit(0.0)
	return true


func _credit_now() -> void:
	_feeding = false
	_feed_anim(-1.0)
	_credit = true
	_locked = false
	if _xmark != null:
		_xmark.visible = false
	_flare = 0.6
	feeding.emit(1.0)
	credited.emit()


## DROP: only with a credit, only when idle.
func press() -> void:
	if _playing or _feeding or not _credit:
		return
	Sfx.peggy_press()
	if _cap != null:
		_cap.position.z = _cap_z - 0.02
		var tw := create_tween()
		tw.tween_interval(0.16)
		tw.tween_callback(func() -> void: _cap.position.z = _cap_z)
	_fire()


func _fire() -> void:
	var prize: Dictionary = App.peggy_drop(_aim)
	refresh_state()
	if prize.is_empty():
		return
	_prize = prize
	var result: Dictionary = prize["result"]
	_path = result["path"]
	_hits = result["hits"]
	_hit_i = 0
	_play_t = 0.0
	_playing = true
	_landed_slot = -1
	_landed_at = -1.0


func _finish_drop() -> void:
	_playing = false
	var slot := int(_prize.get("slot", 0))
	_landed_slot = slot
	_landed_at = _t
	_flare = 0.6
	var rarity := str(_prize.get("rarity", ""))
	if rarity == "epic" or rarity == "legend":
		Sfx.peggy_jackpot()
	else:
		Sfx.peggy_win()
	refresh_state()
	dropped.emit(_prize)


# ---- the ticket flight ---------------------------------------------------------------


static func _smooth(s: float) -> float:
	return s * s * (3.0 - 2.0 * s)


static func _back(s: float) -> float:
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(s - 1.0, 3.0) + c * pow(s - 1.0, 2.0)


## The big ticket along its flight, f in 0..1 (hidden outside): up from
## below the camera with a back-ease, a held beat, a shrinking swoop to
## above the slot while turning to the deck's frame, then into the slot.
func _feed_anim(f: float) -> void:
	if _big_ticket == null or _cam == null:
		return
	if f < 0.0 or f >= 1.0:
		_big_ticket.visible = false
		return
	_big_ticket.visible = true
	var cam_pos := _cam.global_position
	var cam_q := _cam.global_transform.basis.get_rotation_quaternion()
	var start := cam_pos + (CAM_LOOK - cam_pos).normalized() * 1.25
	var slot := _slot_mark.global_position if _slot_mark != null else Vector3(0.0, 0.45, 0.5)
	var dq := _deck.global_transform.basis.orthonormalized().get_rotation_quaternion() if _deck != null else cam_q
	var up := dq * Vector3.UP
	var above := slot + up * 0.11
	var cam_up := cam_q * Vector3.UP
	var below := start - cam_up * 0.95
	var portrait := Quaternion(Vector3(0, 0, 1), PI * 0.5)
	var p: Vector3
	var s := 1.0
	var q := cam_q
	var op := 1.0
	if f < 0.3:
		var a := f / 0.3
		p = below.lerp(start, _back(a))
		q = cam_q * Quaternion(Vector3(0, 0, 1), sin(a * 8.0) * 0.1 * (1.0 - a))
	elif f < 0.44:
		p = start + cam_up * (sin((f - 0.3) / 0.14 * PI) * 0.01)
	elif f < 0.8:
		var a := _smooth((f - 0.44) / 0.36)
		p = start.lerp(above, a)
		p.y += sin(a * PI) * 0.08
		s = 1.0 + (0.27 - 1.0) * a
		q = cam_q.slerp(dq, a)
	else:
		var a := (f - 0.8) / 0.2
		p = above.lerp(slot - up * 0.03, _smooth(a))
		s = 0.27
		q = dq
		op = 1.0 - maxf(0.0, (a - 0.45) / 0.55)
	_big_ticket.global_position = p
	_big_ticket.quaternion = q * portrait
	_big_ticket.scale = Vector3.ONE * s
	_big_mat.albedo_color.a = op


# ---- input ----------------------------------------------------------------------


func _hit(pos: Vector2, node: Node3D, r_m: float) -> bool:
	if node == null or _cam == null:
		return false
	var centre := _cam.unproject_position(node.global_position)
	var edge := _cam.unproject_position(node.global_position + _cam.global_transform.basis.x * r_m)
	return pos.distance_to(centre) <= maxf(centre.distance_to(edge), 24.0)


func _on_gui_input(ev: InputEvent) -> void:
	if _root == null:
		return
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		pressed = mb.pressed
		released = not mb.pressed
		pos = mb.position
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		pressed = st.pressed
		released = not st.pressed
		pos = st.position
	elif ev is InputEventMouseMotion or ev is InputEventScreenDrag:
		if _joy_down:
			tilt = clampf((ev.position.x - _joy_x0) / (_joy_w * 0.08), -1.0, 1.0)
		return
	else:
		return
	if pressed:
		if _hit(pos, _knob, JOY_R):
			_joy_down = true
			_joy_x0 = pos.x
			_joy_w = maxf(size.x, 1.0)
			tilt = 0.0
		elif _hit(pos, _cap, BTN_R):
			press()
	elif released:
		_joy_down = false
		tilt = 0.0


# ---- per frame ------------------------------------------------------------------


func _process(delta: float) -> void:
	_t += delta
	if _pending:
		_center_spinner()   # sized before it entered the tree: no resized yet
		_poll_load()
		return
	var busy := _playing or _feeding
	# The joystick drives the crane; the servo whines while it moves.
	var moving := false
	if tilt != 0.0 and not _playing:
		var before := _aim
		set_aim(_aim + tilt * CRANE_V * delta)
		moving = _aim != before
	if _stick != null:
		_stick.rotation.y = lerpf(_stick.rotation.y, -tilt * 0.45, minf(1.0, 18.0 * delta))
	if moving:
		if not Sfx.peggy_servo_playing():
			Sfx.peggy_servo_start()
	elif Sfx.peggy_servo_playing():
		Sfx.peggy_servo_stop()
	# The ticket flight.
	if _feeding:
		_feed += delta
		_feed_anim(_feed / FEED_S)
		feeding.emit(clampf(_feed / FEED_S, 0.0, 1.0))
		if _feed >= FEED_S:
			_credit_now()
	# The DROP cap: grey with the X when locked, orange when a credit is in
	# (glowing and haloed until used), dim orange otherwise.
	var ready := _credit and not _playing
	var pk := 0.5 + 0.5 * sin(_t * 2.8)
	if _cap_mat != null:
		_cap_mat.albedo_color = CAP_GREY if _locked else (CAP_ORANGE if (_credit or _playing) else CAP_DIM)
		var base := Color("#4A1A08") if ready else Color("#2A1008")
		_cap_mat.emission = base.lerp(Color("#C85A28"), pk * 0.8 if ready else 0.0)
	if _halo_mat != null:
		_halo_mat.albedo_color.a = 0.15 + 0.8 * pk if ready else 0.0
	if _xmark != null and _locked:
		var k := 0.5 + 0.5 * sin(_t * 2.6)
		_x_red.albedo_color.a = 0.2 + 0.8 * k
		_x_ink.albedo_color.a = 0.15 + 0.7 * k
	# The bulb chase: a head running round the ring with a four-bulb tail,
	# faster while busy, flaring on events.
	_flare = maxf(_flare - delta * 0.8, 0.0)
	var n := _bulbs.size()
	if n > 0:
		var head := fmod(_t * (14.0 if busy else 4.0), float(n))
		for i in n:
			var d := fmod(head - i + n, float(n))
			var k := clampf(maxf(0.0, 1.0 - d / 4.0) * 0.6 + 0.4 + _flare, 0.0, 1.0)
			var c := Color(BULB_COLORS[i % BULB_COLORS.size()])
			(_bulb_mats[i] as StandardMaterial3D).albedo_color = c * (0.45 + 0.55 * k)
			if i < _glow_mats.size():
				(_glow_mats[i] as StandardMaterial3D).albedo_color = Color(c, 0.25 + 0.75 * k)
				(_glows[i] as Node3D).scale = Vector3.ONE * ((0.09 + 0.06 * k) / 0.12)
	# The hidden prizes wobble in their bays.
	for i in _sprites.size():
		(_sprites[i] as Node3D).rotation.z = sin(_t * 0.6 + i) * 0.25
	if _playing:
		_step_playback(delta)
	# The landed bay flashes, then the puck goes back to the crane.
	if _landed_slot >= 0:
		if _landed_slot < _light_mats.size():
			(_light_mats[_landed_slot] as StandardMaterial3D).albedo_color.a = 0.35 + 0.25 * sin(_t * 9.0)
		if _landed_at >= 0.0 and _t - _landed_at > LANDED_HOLD and not _playing and not _feeding:
			(_light_mats[_landed_slot] as StandardMaterial3D).albedo_color.a = 0.0
			_landed_slot = -1
			_landed_at = -1.0
			_place()


func _step_playback(delta: float) -> void:
	_play_t += delta * PLAY_RATE
	var n := _path.size()
	var i := 0
	while i + 1 < n and float(_path[i + 1][2]) <= _play_t:
		i += 1
	var x: float
	var y: float
	if i + 1 < n:
		var a: Array = _path[i]
		var b: Array = _path[i + 1]
		var span := maxf(float(b[2]) - float(a[2]), 1e-6)
		var f := clampf((_play_t - float(a[2])) / span, 0.0, 1.0)
		x = lerpf(float(a[0]), float(b[0]), f)
		y = lerpf(float(a[1]), float(b[1]), f)
	else:
		var last: Array = _path[n - 1]
		x = float(last[0])
		y = float(last[1])
	if _puck != null:
		_puck.position = Vector3(x * U, BOARD_Y0 + y * U, PZ)
	while _hit_i < _hits.size() and float(_hits[_hit_i][2]) <= _play_t:
		var h: Array = _hits[_hit_i]
		Sfx.peggy_peg(_hit_i % 3, minf(1.0 + 0.012 * _hit_i, 1.3))
		var idx := int(h[3])
		if idx < _pegs.size():
			_flash_peg(_pegs[idx])
		_hit_i += 1
	if i + 1 >= n:
		_finish_drop()


func _flash_peg(mi: MeshInstance3D) -> void:
	mi.material_override = _flash_mat
	var base := Vector3.ONE
	mi.scale = base * 1.7
	var tw := create_tween()
	tw.tween_property(mi, "scale", base, 0.12)
	tw.tween_callback(func() -> void: mi.material_override = null)


## Cabinet details, for tests and the QA driver.
func peg_count() -> int:
	return _pegs.size()


func bulb_count() -> int:
	return _bulbs.size()


## QA: a control's centre in window (design px) coordinates.
func debug_screen_pos(which: String) -> Vector2:
	var n: Node3D = _knob if which == "knob" else _cap
	if n == null or _cam == null:
		return Vector2.ZERO
	return get_global_transform_with_canvas() * _cam.unproject_position(n.global_position)


func cabinet() -> Node3D:
	return _root


func set_view_active(on: bool) -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
