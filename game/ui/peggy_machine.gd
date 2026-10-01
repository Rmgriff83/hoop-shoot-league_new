class_name PeggyMachine
extends SubViewportContainer
## PEGGY, the locker's drop machine (docs/LOCKER.md): the 3D cabinet in its
## own little world, and the hands that work it. Drag along the rail band to
## aim the carriage (a servo whines while it moves), press and HOLD the big
## red button to feed a ticket (release early and it backs out, nothing
## spent); at full feed App.peggy_drop() runs the headless board and the
## puck's path plays back here — pegs flash and tick, the slot lights, the
## marquee flares — then `dropped` hands the prize record to the panel.
## The glb's node names are the contract with tools/blender/build_peggy.py.

signal dropped(prize: Dictionary)
signal aim_changed(aim: float)
signal feeding(frac: float)

const GLB := "res://assets/locker/peggy.glb"
const BULB_SHADER := preload("res://game/court/bulb.gdshader")
const VIEW := Vector2i(600, 840)
const FEED_S := 0.6
const PLAY_RATE := 0.75
const U := 0.1
const BOARD_Y0 := 0.52
const PEG_Z := 0.185
const RAIL_BAND := 150.0            # px from the top of the view that aim the carriage
const BUTTON_RECT := Rect2(140.0, 660.0, 320.0, 180.0)
const AIM_LERP := 12.0
const CAM_POS := Vector3(0.0, 1.42, 2.62)
const CAM_LOOK := Vector3(0.0, 1.17, 0.1)
const PRIZE_SCALE := 0.29
const TIER_COLOR := {
	"common": Color("#B8AE96"), "rare": Color("#7FAEC6"), "epic": Color("#E8703A"), "legend": Color("#F0B84A"),
}

static var _ball_mesh: Mesh

var can_drop := true

var _vp: SubViewport
var _cam: Camera3D
var _root: Node3D
var _puck: Node3D
var _carriage: Node3D
var _btn_cap: MeshInstance3D
var _ticket: Node3D
var _plates: Array = []
var _lights: Array = []
var _prizes: Array = []
var _prize_mats: Array = []
var _pegs: Array = []
var _bulb_mat: ShaderMaterial
var _gold_mat: StandardMaterial3D
var _btn_down_mat: StandardMaterial3D
var _light_mat: StandardMaterial3D
var _t := 0.0
var _flare := 0.0
var _aim := 0.0
var _aim_target := 0.0
var _dragging := false
var _servo_until := 0.0
var _holding := false
var _feed := 0.0
var _ticket_tween: Tween
var _playing := false
var _play_t := 0.0
var _path: Array = []
var _hits: Array = []
var _hit_i := 0
var _prize: Dictionary = {}
var _landed_slot := -1
var _slots: Array = []


func _init() -> void:
	name = "Peggy"
	custom_minimum_size = Vector2(VIEW)
	size = Vector2(VIEW)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


## Built in _init so the panel (and the tests) can read the machine before
## it is in the tree.
func _build() -> void:
	_vp = SubViewport.new()
	_vp.name = "PeggyViewport"
	_vp.size = VIEW
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#120F14")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.8)
	e.ambient_light_energy = 0.55
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.rotation_degrees = Vector3(-38.0, 22.0, 0.0)
	sun.shadow_enabled = false
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = 40.0
	_cam.position = CAM_POS
	_cam.look_at_from_position(CAM_POS, CAM_LOOK, Vector3.UP)
	_vp.add_child(_cam)
	var scene: PackedScene = load(GLB)
	if scene != null:
		_root = scene.instantiate()
		_root.name = "Cabinet"
		_vp.add_child(_root)
		_bind()
	gui_input.connect(_on_gui_input)
	set_process(true)


func _node(n: String) -> Node:
	return _root.find_child(n, true, false) if _root != null else null


func _bind() -> void:
	_puck = _node("Puck")
	_carriage = _node("Carriage")
	_btn_cap = _node("BtnCap")
	_ticket = _node("Ticket")
	if _ticket != null:
		_ticket.visible = false
	_gold_mat = StandardMaterial3D.new()
	_gold_mat.albedo_color = Color("#F0B84A")
	_gold_mat.emission_enabled = true
	_gold_mat.emission = Color("#F0B84A")
	_gold_mat.emission_energy_multiplier = 1.5
	_btn_down_mat = StandardMaterial3D.new()
	_btn_down_mat.albedo_texture = load("res://assets/textures/peggy_button_down.png")
	_btn_down_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_texture = load("res://assets/textures/peggy_light.png")
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1.0, 0.9, 0.65)
	_light_mat.emission_energy_multiplier = 0.0
	for n in BeachFx._descendants(_root):
		if not (n is MeshInstance3D):
			if n is Node3D and String(n.name).begins_with("Prize"):
				_prizes.push_back(n)
			continue
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if nm.begins_with("Bulb"):
			if _bulb_mat == null:
				_bulb_mat = ShaderMaterial.new()
				_bulb_mat.shader = BULB_SHADER
				_bulb_mat.set_shader_parameter("speed", 6.0)
				_bulb_mat.set_shader_parameter("tail", 5.0)
			mi.material_override = _bulb_mat
			mi.set_instance_shader_parameter("bulb_index", float(nm.substr(4).to_int()))
		elif nm.begins_with("Peg") or nm.begins_with("Bumper") or nm.begins_with("Divider"):
			if not nm.begins_with("DividerWall"):
				_pegs.push_back(mi)
		elif nm.begins_with("SlotPlate"):
			_plates.push_back(mi)
		elif nm.begins_with("SlotLight"):
			var m := _light_mat.duplicate() as StandardMaterial3D
			mi.material_override = m
			_lights.push_back(mi)
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("count", 18.0)
	_pegs.sort_custom(func(a: Node, b: Node) -> bool: return _peg_order(a) < _peg_order(b))
	_plates.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	_lights.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	_prizes.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for i in _prizes.size():
		var mi := MeshInstance3D.new()
		mi.name = "PrizeBall"
		mi.mesh = ball_mesh()
		mi.scale = Vector3.ONE * PRIZE_SCALE
		var m := StandardMaterial3D.new()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.roughness = 0.82
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_prizes[i] as Node3D).add_child(mi)
		_prize_mats.push_back(m)
	_place_puck_at_rail()


## The core's peg order (row-major: bumper, pegs, bumper; then dividers), so a
## hit's peg index from PeggyBoard.simulate() maps straight onto a mesh.
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


static func ball_mesh() -> Mesh:
	if _ball_mesh == null:
		var scene: PackedScene = load("res://assets/balls/classic/basketball.glb")
		if scene != null:
			var root: Node = scene.instantiate()
			for n in BeachFx._descendants(root):
				if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
					_ball_mesh = (n as MeshInstance3D).mesh
					break
			root.free()
		if _ball_mesh == null:
			var s := SphereMesh.new()
			s.radius = 0.121
			s.height = 0.242
			_ball_mesh = s
	return _ball_mesh


# ---- plates ---------------------------------------------------------------------


## Show the next drop's plates: a rarity plate and the prize ball in each bay
## ("" = the refund plate).
func set_slots(slots: Array) -> void:
	_slots = slots
	for i in mini(slots.size(), _plates.size()):
		var s: Dictionary = slots[i]
		var rarity := str(s.get("rarity", ""))
		var tex_name := "peggy_plate_%s.png" % (rarity if rarity != "" else "refund")
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/" + tex_name)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		(_plates[i] as MeshInstance3D).material_override = m
		if i < _prizes.size():
			var ball: MeshInstance3D = (_prizes[i] as Node3D).get_node_or_null("PrizeBall")
			var id := str(s.get("ball_id", ""))
			var set := CosmeticLibrary.get_ball(id) if id != "" else null
			if ball != null:
				ball.visible = set != null
				if set != null:
					(_prize_mats[i] as StandardMaterial3D).albedo_texture = load(set.skin_path)
	for l in _lights:
		((l as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 0.0
	_landed_slot = -1


func slots() -> Array:
	return _slots


# ---- aim ------------------------------------------------------------------------


func aim() -> float:
	return _aim_target


func set_aim(x: float) -> void:
	var a := PeggyBoard.clamp_aim(x)
	if absf(a - _aim_target) < 1e-6:
		return
	_aim_target = a
	_servo_until = _t + 0.25
	aim_changed.emit(_aim_target)


func nudge(dx: float) -> void:
	set_aim(_aim_target + dx)


func _place_puck_at_rail() -> void:
	if _carriage != null:
		_carriage.position.x = _aim * U
	if _puck != null and not _playing:
		_puck.position = Vector3(_aim * U, BOARD_Y0 + PeggyBoard.RELEASE_Y * U, PEG_Z)


# ---- the button -----------------------------------------------------------------


func is_busy() -> bool:
	return _playing or _holding


## Finger down on the button: the cap sinks, the ticket starts feeding.
func press() -> void:
	if _holding or _playing or not can_drop:
		return
	_holding = true
	_feed = 0.0
	Sfx.peggy_press()
	if _btn_cap != null:
		_btn_cap.position.y -= 0.012
		_btn_cap.material_override = _btn_down_mat
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("speed", 22.0)
	if _ticket != null:
		if _ticket_tween != null:
			_ticket_tween.kill()
		_ticket.visible = true
		_ticket.position = Vector3(0.0, 0.0, 0.06)
		_ticket_tween = create_tween()
		_ticket_tween.tween_property(_ticket, "position:z", -0.03, FEED_S)
	Sfx.peggy_ticket()


## Finger up: before the feed completes the ticket backs out, nothing spent.
func release() -> void:
	if not _holding:
		return
	_holding = false
	_cap_up()
	if _feed < FEED_S:
		if _ticket != null:
			if _ticket_tween != null:
				_ticket_tween.kill()
			_ticket_tween = create_tween()
			_ticket_tween.tween_property(_ticket, "position:z", 0.06, 0.2)
			_ticket_tween.tween_callback(func() -> void: _ticket.visible = false)
		if _bulb_mat != null:
			_bulb_mat.set_shader_parameter("speed", 6.0)
	feeding.emit(0.0)


func _cap_up() -> void:
	if _btn_cap != null:
		_btn_cap.position.y += 0.012
		_btn_cap.material_override = null


func _fire() -> void:
	_holding = false
	_cap_up()
	if _ticket != null:
		_ticket.visible = false
	var prize: Dictionary = App.peggy_drop(_aim_target)
	if prize.is_empty():
		if _bulb_mat != null:
			_bulb_mat.set_shader_parameter("speed", 6.0)
		feeding.emit(0.0)
		return
	_prize = prize
	var result: Dictionary = prize["result"]
	_path = result["path"]
	_hits = result["hits"]
	_hit_i = 0
	_play_t = 0.0
	_playing = true
	_aim = _aim_target
	if _carriage != null:
		_carriage.position.x = _aim * U


func _finish_drop() -> void:
	_playing = false
	var slot := int(_prize.get("slot", 0))
	_landed_slot = slot
	if slot < _lights.size():
		((_lights[slot] as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 2.5
	if _bulb_mat != null:
		_flare = 0.6
		_bulb_mat.set_shader_parameter("flare", _flare)
		_bulb_mat.set_shader_parameter("speed", 6.0)
	var rarity := str(_prize.get("rarity", ""))
	if rarity == "epic" or rarity == "legend":
		Sfx.peggy_jackpot()
	else:
		Sfx.peggy_win()
	dropped.emit(_prize)


# ---- input ----------------------------------------------------------------------


func _on_gui_input(ev: InputEvent) -> void:
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
		if _dragging:
			_aim_from_px(ev.position)
		return
	else:
		return
	if pressed:
		if pos.y < RAIL_BAND and not _playing:
			_dragging = true
			_aim_from_px(pos)
		elif BUTTON_RECT.has_point(pos):
			press()
	elif released:
		_dragging = false
		release()


func _aim_from_px(px: Vector2) -> void:
	var half := float(VIEW.x) * 0.31   # the board's half width on screen, roughly
	set_aim((px.x - float(VIEW.x) * 0.5) / half * PeggyBoard.WALL_X)


# ---- per frame ------------------------------------------------------------------


func _process(delta: float) -> void:
	_t += delta
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("t", _t)
		if _flare > 0.0:
			_flare = maxf(_flare - delta * 0.8, 0.0)
			_bulb_mat.set_shader_parameter("flare", _flare)
	# The carriage follows the aim; the servo whines while it is moving.
	var moving := absf(_aim_target - _aim) > 0.004
	if moving:
		_aim = lerpf(_aim, _aim_target, minf(1.0, AIM_LERP * delta))
		if absf(_aim_target - _aim) <= 0.004:
			_aim = _aim_target
		_place_puck_at_rail()
	if (moving or _t < _servo_until) and not _playing:
		if not Sfx.peggy_servo_playing():
			Sfx.peggy_servo_start()
	elif Sfx.peggy_servo_playing():
		Sfx.peggy_servo_stop()
	# Prize balls turn slowly in their bays.
	for p in _prizes:
		var ball: Node3D = (p as Node3D).get_node_or_null("PrizeBall")
		if ball != null and ball.visible:
			ball.rotate_y(delta * 0.6)
	# Feeding the ticket.
	if _holding:
		_feed += delta
		feeding.emit(clampf(_feed / FEED_S, 0.0, 1.0))
		if _feed >= FEED_S:
			_fire()
	if _playing:
		_step_playback(delta)
	for l in _lights:
		var m := (l as MeshInstance3D).material_override as StandardMaterial3D
		if m.emission_energy_multiplier > 0.0 and _landed_slot >= 0:
			m.emission_energy_multiplier = 1.6 + 0.9 * sin(_t * 9.0)


func _step_playback(delta: float) -> void:
	_play_t += delta * PLAY_RATE
	# The puck along the path (samples [x, y, t]).
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
		_puck.position = Vector3(x * U, BOARD_Y0 + y * U, PEG_Z)
	# Peg hits that have come due: a tick and a gold flash.
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
	mi.material_override = _gold_mat
	var base := mi.scale
	mi.scale = base * 1.6
	var tw := create_tween()
	tw.tween_property(mi, "scale", base, 0.12)
	tw.tween_callback(func() -> void: mi.material_override = null)


## Playback and cabinet details, for tests and the QA driver.
func playing() -> bool:
	return _playing


func feed_fraction() -> float:
	return clampf(_feed / FEED_S, 0.0, 1.0) if _holding else 0.0


func peg_count() -> int:
	return _pegs.size()


func cabinet() -> Node3D:
	return _root


func set_view_active(on: bool) -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
