class_name CityFx
extends Node
## Presentation-only city life (docs/HOME.md → Adding an area): cars pass on
## the street beyond the back fence, the buildings (Sam Grady's pack on one
## photo atlas) are dusked by the facade shader with their windows switching
## on and off a pane at a time, the floodlight and lamp heads glow, the
## street trees face the camera. Never touches the sim. Seeded (never
## randomize()) so a QA screenshot or a test replays identically.

const WINDOW_SHADER := preload("res://game/court/windows.gdshader")
const FACADE_MASK := "res://assets/textures/city_facades_lit.png"
const FACADE_CELLS := Vector2(32, 32)
## The traffic pool: the hometown pack's cars (GGBot "PSX Style Cars",
## data/credits.json). Forward is Godot +Z, the origin is on the ground.
const MODELS: Array[String] = [
	"res://assets/vehicles/sedan.glb", "res://assets/vehicles/sedan_red.glb", "res://assets/vehicles/sedan_black.glb",
	"res://assets/vehicles/hatch.glb", "res://assets/vehicles/hatch_blue.glb", "res://assets/vehicles/compact_yellow.glb",
	"res://assets/vehicles/taxi.glb", "res://assets/vehicles/van_grey.glb", "res://assets/vehicles/muscle_grey.glb",
	"res://assets/vehicles/jalopy_brown.glb",
]
const RNG_SEED := 0x0C17_0CA5
## The street runs laterally behind the hoop (along sim z); `StreetRig` in the
## glb sits on its centre line (tools/blender/build_city.py STREET_X).
const STREET_X := 11.1
const LANE_HALF := 1.6            # lane centres at street_x ± LANE_HALF
const CAR_EDGE := 34.0            # z where a car appears / is freed (corner radius 35.8 < SKY_R 60)
const CAR_SPEED := Vector2(8.0, 11.0)
const CAR_GAP := Vector2(8.0, 20.0)
const MAX_CARS := 2
const HEADLIGHT_ENERGY := 0.9
const HEADLIGHT_RANGE := 14.0
const HEADLIGHT_ANGLE := 32.0
## The court's floodlights: a spot hung on every FloodHead*, aimed at the key.
## Aimed at the floor around the key with a cone tight enough that the pale
## steel board only catches its edge (inverse-square falloff from 8 m up).
const FLOOD_TARGET := Vector3(-0.5, 0.0, 0.0)
const FLOOD_ENERGY := 8.0
const FLOOD_RANGE := 40.0
const FLOOD_ANGLE := 32.0
## Window lights: the share of panes lit, and each pane's own switching
## period (minutes), mirrored by windows.gdshader.
const LIT_SHARE := 0.6
const PERIOD_BASE := 180.0
const PERIOD_SPREAD := 300.0

var _rig: Node3D
var _street_x := STREET_X
var _street_z0 := 0.0
var _yaw := 0.0
var _fx_root: Node3D
var _cars: Array[Dictionary] = []
var _next_car := 10.0
var _sent := 0
var _rng := RandomNumberGenerator.new()
var _tree_rigs: Array[Node3D] = []
var _window_mats: Dictionary = {}     # texture path → the one ShaderMaterial its faces share
var _window_faces := 0
var _flood_lights: Array[SpotLight3D] = []
var _t := 0.0


## Bind the city glb: the street line, the trees, the windows, the lamp heads.
## False when the arena has no street (nothing to animate).
func setup(arena: Node) -> bool:
	_rig = arena.find_child("StreetRig", true, false) as Node3D
	if _rig == null:
		return false
	_street_x = _rig.position.x
	_street_z0 = _rig.position.z
	_yaw = _rig.rotation.y
	for n in BeachFx._descendants(arena):
		if n is Node3D and n.name.begins_with("TreeRig"):
			_tree_rigs.push_back(n as Node3D)
		elif n is MeshInstance3D and n.name.begins_with("Building"):
			_bind_facade(n as MeshInstance3D)
		elif n is MeshInstance3D and n.name.begins_with("Windows"):
			_bind_windows(n as MeshInstance3D)
		elif n is MeshInstance3D and n.name.begins_with("FloodHead"):
			_unshade(n as MeshInstance3D)
			if not n.name.begins_with("FloodHeadL"):
				_hang_flood(n as MeshInstance3D)
	_fx_root = Node3D.new()
	_fx_root.name = "Traffic"
	arena.add_child(_fx_root)
	_rng.seed = RNG_SEED
	_next_car = _rng.randf_range(3.0, CAR_GAP.y)
	return true


## The pack's buildings: one shared facade material over the atlas + the
## derived window mask, an instance seed per building so they light apart.
func _bind_facade(mi: MeshInstance3D) -> void:
	var tex := BeachFx._albedo_of(mi)
	var key := "facade:" + (tex.resource_path if tex != null else "<none>")
	if not _window_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = WINDOW_SHADER
		if tex != null:
			m.set_shader_parameter("albedo", tex)
		if ResourceLoader.exists(FACADE_MASK):
			m.set_shader_parameter("mask", load(FACADE_MASK))
		m.set_shader_parameter("use_mask", true)
		m.set_shader_parameter("cells", FACADE_CELLS)
		m.set_shader_parameter("lit_share", LIT_SHARE)
		m.set_shader_parameter("period_base", PERIOD_BASE)
		m.set_shader_parameter("period_spread", PERIOD_SPREAD)
		_window_mats[key] = m
	mi.material_override = _window_mats[key]
	mi.set_instance_shader_parameter("seed", float(_window_faces))
	_window_faces += 1


## One shared material per window texture (so the faces still batch): the
## wall tile with 4×4 windows, or the tower tile with 4×8 panes.
func _bind_windows(mi: MeshInstance3D) -> void:
	var tex := BeachFx._albedo_of(mi)
	var key := tex.resource_path if tex != null else "<none>"
	if not _window_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = WINDOW_SHADER
		if tex != null:
			m.set_shader_parameter("albedo", tex)
		var tower := key.contains("tower")
		m.set_shader_parameter("use_mask", false)
		m.set_shader_parameter("cells", Vector2(4, 8) if tower else Vector2(4, 4))
		m.set_shader_parameter("pane_min", Vector2(0.125, 0.125) if tower else Vector2(0.25, 0.19))
		m.set_shader_parameter("pane_max", Vector2(0.875, 0.875) if tower else Vector2(0.75, 0.81))
		m.set_shader_parameter("lit_share", LIT_SHARE)
		m.set_shader_parameter("period_base", PERIOD_BASE)
		m.set_shader_parameter("period_spread", PERIOD_SPREAD)
		if tower:
			m.set_shader_parameter("lit_color", Color(0.75, 0.85, 1.0))
		_window_mats[key] = m
	mi.material_override = _window_mats[key]
	_window_faces += 1


## A warm spot at the head, aimed at the key, no shadows (the phone's budget).
func _hang_flood(head: MeshInstance3D) -> void:
	var lamp := SpotLight3D.new()
	lamp.name = "Flood"
	lamp.light_color = Color(1.0, 0.94, 0.82)
	lamp.light_energy = FLOOD_ENERGY
	lamp.spot_range = FLOOD_RANGE
	lamp.spot_angle = FLOOD_ANGLE
	lamp.spot_attenuation = 1.0
	lamp.light_specular = 0.25   # the steel board sits in the cone: no hot spot
	lamp.shadow_enabled = false
	head.add_child(lamp)
	# The head quad's local frame is its own; aim in the arena's frame.
	lamp.global_position = head.global_position
	lamp.look_at(head.get_parent_node_3d().to_global(FLOOD_TARGET) if head.get_parent_node_3d() != null else FLOOD_TARGET)
	_flood_lights.push_back(lamp)


func flood_count() -> int:
	return _flood_lights.size()


static func _unshade(mi: MeshInstance3D) -> void:
	for i in mi.get_surface_override_material_count():
		var m := mi.get_active_material(i)
		if m is BaseMaterial3D:
			(m as BaseMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(m as BaseMaterial3D).disable_fog = true


## The shader's rule in GDScript, over a `cols × rows` field of cells: the
## share of panes lit at `clock` (tests pin it near LIT_SHARE and moving).
static func lit_fraction(clock: float, cols := 32, rows := 32) -> float:
	var lit := 0
	for y in rows:
		for x in cols:
			var cell := Vector2(x, y)
			var h1 := _hash(cell + Vector2(0.1, 0.1))
			var h2 := _hash(cell + Vector2(7.3, 7.3))
			var h3 := _hash(cell + Vector2(3.7, 3.7))
			var period := PERIOD_BASE + PERIOD_SPREAD * h2
			var flips := floorf((clock + h3 * period) / period)
			var base_lit := h1 < LIT_SHARE
			var flipped := fmod(flips, 2.0) >= 1.0
			if base_lit != flipped:
				lit += 1
	return float(lit) / float(cols * rows)


static func _hash(p: Vector2) -> float:
	var v := sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453
	return v - floorf(v)


func window_count() -> int:
	return _window_faces


func window_material_count() -> int:
	return _window_mats.size()


func car_count() -> int:
	return _cars.size()


func sent() -> int:
	return _sent


func car_position(i: int) -> Vector3:
	return (_cars[i]["node"] as Node3D).position


func car_velocity(i: int) -> float:
	return float(_cars[i]["vel"])


## Put a car on the street at one end: +z travel takes the far lane, −z the
## near one (right-hand traffic seen from the court). Refused when the street
## is full.
func spawn_car() -> void:
	if _cars.size() >= MAX_CARS or _fx_root == null:
		return
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var path: String = MODELS[_rng.randi_range(0, MODELS.size() - 1)]
	var speed := _rng.randf_range(CAR_SPEED.x, CAR_SPEED.y)
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	var car: Node3D = scene.instantiate() as Node3D
	if car == null:
		return
	car.name = "Car%d" % _sent
	# A moving prop must not carry a collider (it would shove the ball).
	for b in car.find_children("*", "StaticBody3D", true, false):
		b.get_parent().remove_child(b)
		b.free()
	_light_lamps(car)
	var lamp := SpotLight3D.new()
	lamp.name = "Headlights"
	lamp.position = Vector3(0, 0.65, 2.0)
	lamp.rotate_y(PI)            # a spot shines down local −Z; the car's front is +Z
	lamp.light_energy = HEADLIGHT_ENERGY
	lamp.spot_range = HEADLIGHT_RANGE
	lamp.spot_angle = HEADLIGHT_ANGLE
	lamp.light_color = Color(1.0, 0.93, 0.8)
	lamp.shadow_enabled = false
	car.add_child(lamp)
	car.position = Vector3(_street_x + dir * LANE_HALF, 0.0, _street_z0 - dir * CAR_EDGE)
	car.rotation.y = (0.0 if dir > 0.0 else PI) + _yaw
	_fx_root.add_child(car)
	_cars.push_back({"node": car, "vel": dir * speed})
	_sent += 1


## The pack's lamp materials (`*Glow`) glow on their own at dusk.
static func _light_lamps(car: Node) -> void:
	for n in BeachFx._descendants(car):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and m.resource_name.contains("Glow"):
				var sm := m as BaseMaterial3D
				sm.emission_enabled = true
				sm.emission = Color(1.0, 0.9, 0.7)
				sm.emission_energy_multiplier = 2.0


func _process(dt: float) -> void:
	_t += dt
	for m in _window_mats.values():
		(m as ShaderMaterial).set_shader_parameter("clock", _t)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		for rig in _tree_rigs:
			rig.rotation.y = CourtGeometry.yaw_toward(rig.global_position, cam.global_position)
	var keep: Array[Dictionary] = []
	for c in _cars:
		var node := c["node"] as Node3D
		node.position.z += float(c["vel"]) * dt
		if absf(node.position.z - _street_z0) > CAR_EDGE + 1.0:
			node.queue_free()
		else:
			keep.push_back(c)
	_cars = keep
	_next_car -= dt
	if _next_car <= 0.0:
		if _cars.size() < MAX_CARS:
			spawn_car()
			_next_car = _rng.randf_range(CAR_GAP.x, CAR_GAP.y)
		else:
			_next_car = CAR_GAP.x
