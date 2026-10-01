class_name CityFx
extends Node
## Presentation-only city life (docs/HOME.md → Adding an area): cars pass on
## the street beyond the back fence, the buildings (Sam Grady's pack on one
## photo atlas) share one cheap material, the street trees face the camera.
## Midday since 2026-10-01: no floodlight spots, no lamp omnis (they lagged
## the phone), the sun does the lighting. Never touches the sim.
## Seeded (never randomize()) so a QA screenshot or a test replays
## identically. (The window-light shader was removed 2026-10-01: it lagged
## the phone.)

## The daylit photo atlas as shot (midday): one unshaded material per texture.
const FACADE_TINT := Color(0.96, 0.96, 0.97)
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
## Heavy evening traffic (Ross, 2026-09-30): each car follows the one ahead
## — it drives at the lane's pace until it closes to its following distance,
## brakes to a stop a bumper gap behind, and pulls away again only when the
## car ahead has opened the gap, so stops ripple back down the queue the way
## real jams do. A car never stops for nothing: every stop has a car in
## front of it, and the FRONT of each queue stops for a SIGNAL at the lane's
## exit (just past where the cars leave view) that goes red now and then —
## the pile-up behind it is the jam.
const CAR_SPEED := Vector2(0.0, 5.0)        # a car's pace: stop to a slow roll
const SIGNAL_GREEN := Vector2(14.0, 30.0)   # s a lane's exit signal stays green
const SIGNAL_RED := Vector2(10.0, 22.0)     # s it holds red (the queue builds)
const SIGNAL_X := 2.0                       # m past the exit edge where the lead car stops
const CAR_LEN := 4.4
const STOP_GAP := 1.6                       # m bumper to bumper when stopped
const FOLLOW_GAP := 3.0                     # m of clear road a car keeps while rolling
const ACCEL := 1.8                          # m/s² pulling away
const BRAKE := 3.0                          # m/s² stopping
# Light traffic (Ross, 2026-10-01: the phone lagged under the bumper-to-bumper
# wave): a car passes now and then, at most one per lane, one real spot.
const CAR_GAP := Vector2(14.0, 34.0)        # s between cars joining a lane
const MAX_CARS := 2
const HEADLIGHT_SPOTS := 1                  # real spot lights on this many cars (the rest glow)
const HEADLIGHT_ENERGY := 0.9
const HEADLIGHT_RANGE := 14.0
const HEADLIGHT_ANGLE := 32.0
## The court's floodlights: a spot hung on every FloodHead*, aimed at the key.
## Aimed at the floor around the key with a cone tight enough that the pale
## steel board only catches its edge (inverse-square falloff from 8 m up).

var _rig: Node3D
var _street_x := STREET_X
var _street_z0 := 0.0
var _yaw := 0.0
var _fx_root: Node3D
var _cars: Array[Dictionary] = []
var _next_car := 10.0
var _lane_wait := [0.0, 0.0]               # per lane (index 0: +z travel, 1: −z), s until it may join
var _deck: Array[int] = []                   # models to draw, shuffled: every model once before any repeats
var _last_model := -1
var _signal_red := [false, false]          # per lane: the exit signal's state
var _signal_t := [12.0, 20.0]              # s until it changes
var _spots := 0
var _sent := 0
var _rng := RandomNumberGenerator.new()
var _tree_rigs: Array[Node3D] = []
var _facade_mats: Dictionary = {}     # texture path → the one dusk material its faces share
var _facade_faces := 0
var _t := 0.0


## Bind the city glb: the street line, the trees, the facades, the lamp heads.
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
		elif n is MeshInstance3D and (n.name.begins_with("Building") or n.name.begins_with("Windows")):
			_bind_facade(n as MeshInstance3D)
		elif n is MeshInstance3D and (n.name.begins_with("LampGlow") or n.name.begins_with("ParkGlow")):
			n.visible = false   # bulbs are off at midday
		elif n is MeshInstance3D and (n.name == "BusPoster" or n.name == "BusSign"):
			_unshade(n as MeshInstance3D)
	_fx_root = Node3D.new()
	_fx_root.name = "Traffic"
	arena.add_child(_fx_root)
	_rng.seed = RNG_SEED
	_next_car = _rng.randf_range(3.0, CAR_GAP.y)
	return true


## The pack's buildings and the tenements: one shared unshaded material per
## texture (so the faces still batch), the daylit photos graded to dusk.
func _bind_facade(mi: MeshInstance3D) -> void:
	var tex := BeachFx._albedo_of(mi)
	var key := tex.resource_path if tex != null else "<none>"
	if not _facade_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
		m.albedo_color = FACADE_TINT
		if tex != null:
			m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if key.contains("facades") else BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_facade_mats[key] = m
	mi.material_override = _facade_mats[key]
	_facade_faces += 1


static func _unshade(mi: MeshInstance3D) -> void:
	for i in mi.get_surface_override_material_count():
		var m := mi.get_active_material(i)
		if m is BaseMaterial3D:
			(m as BaseMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(m as BaseMaterial3D).disable_fog = true


func facade_count() -> int:
	return _facade_faces


func facade_material_count() -> int:
	return _facade_mats.size()


func car_count() -> int:
	return _cars.size()


func sent() -> int:
	return _sent


func car_position(i: int) -> Vector3:
	return (_cars[i]["node"] as Node3D).position


## A lane's open-road pace (m/s, signed): what a car with nothing ahead does.
func lane_speed(dir: float) -> float:
	return dir * CAR_SPEED.y


## Is a lane's exit signal red?
func signal_red(dir: float) -> bool:
	return bool(_signal_red[0 if dir > 0.0 else 1])


## The lane's exit signal stop line, in z (past the edge where cars leave view).
func signal_z(dir: float) -> float:
	return _street_z0 + dir * (CAR_EDGE + SIGNAL_X)


func car_velocity(i: int) -> float:
	return float(_cars[i]["vel"])


## Clear road ahead of car `i` in its lane (m, bumper to bumper): to the car
## in front, or to the exit signal's stop line when it is red; INF if none.
func gap_ahead(i: int) -> float:
	var c := _cars[i]
	var dir := float(c["dir"])
	var z := (c["node"] as Node3D).position.z
	var best := INF
	for j in _cars.size():
		if j == i or float(_cars[j]["dir"]) != dir:
			continue
		var d := ((_cars[j]["node"] as Node3D).position.z - z) * dir
		if d > 0.0:
			best = minf(best, d - CAR_LEN)
	if signal_red(dir):
		var d := (signal_z(dir) - z) * dir - CAR_LEN * 0.5
		if d > 0.0:
			best = minf(best, d)
	return best


## Is a lane's joining edge clear (the last car at least a stopped pitch ahead)?
func lane_clear(dir: float) -> bool:
	var edge := _street_z0 - dir * CAR_EDGE
	for c in _cars:
		if float(c["dir"]) == dir and absf((c["node"] as Node3D).position.z - edge) < CAR_LEN + STOP_GAP:
			return false
	return true


## Put a car on the street at one end: +z travel takes the far lane, −z the
## near one (right-hand traffic seen from the court). Refused when the street
## is full.
func spawn_car(dir := 0.0) -> void:
	if _cars.size() >= MAX_CARS or _fx_root == null:
		return
	if dir == 0.0:
		dir = 1.0 if _rng.randf() < 0.5 else -1.0
	if not lane_clear(dir):
		return
	var path: String = MODELS[_draw_model()]
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
	var has_spot := false
	if _spots < HEADLIGHT_SPOTS:
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
		_spots += 1
		has_spot = true
	car.position = Vector3(_street_x + dir * LANE_HALF, 0.0, _street_z0 - dir * CAR_EDGE)
	car.rotation.y = (0.0 if dir > 0.0 else PI) + _yaw
	_fx_root.add_child(car)
	_cars.push_back({"node": car, "dir": dir, "spot": has_spot, "vel": lane_speed(dir) * 0.5})
	_sent += 1


## The next model from a shuffled deck, so the mix is even: every model
## appears once before any repeats, and a fresh deck never opens with the
## model that closed the last one, so two of a kind never follow each other.
func _draw_model() -> int:
	if _deck.is_empty():
		for i in MODELS.size():
			_deck.push_back(i)
		for i in range(_deck.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp := _deck[i]
			_deck[i] = _deck[j]
			_deck[j] = tmp
		if _deck.size() > 1 and _deck[_deck.size() - 1] == _last_model:
			var tmp := _deck[_deck.size() - 1]
			_deck[_deck.size() - 1] = _deck[0]
			_deck[0] = tmp
	_last_model = _deck.pop_back()
	return _last_model


func last_model() -> int:
	return _last_model


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
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		for rig in _tree_rigs:
			rig.rotation.y = CourtGeometry.yaw_toward(rig.global_position, cam.global_position)
	# The exit signals: green for a while, then red, and the queue backs up.
	for k in 2:
		_signal_t[k] = float(_signal_t[k]) - dt
		if float(_signal_t[k]) <= 0.0:
			_signal_red[k] = not bool(_signal_red[k])
			var span := SIGNAL_RED if bool(_signal_red[k]) else SIGNAL_GREEN
			_signal_t[k] = _rng.randf_range(span.x, span.y)
	# Each car follows what is ahead — the next car, or a red signal: a target
	# speed from the clear road (open-road pace with room, a stop at the bumper
	# gap, a proportional crawl between), reached at its own acceleration or
	# braking. Nothing else ever slows a car.
	for i in _cars.size():
		var c := _cars[i]
		var dir := float(c["dir"])
		var pace := absf(lane_speed(dir))
		var room := gap_ahead(i)
		var want := pace
		if room < INF:
			want = minf(pace, clampf((room - STOP_GAP) / FOLLOW_GAP, 0.0, 1.0) * CAR_SPEED.y)
		var v := absf(float(c["vel"]))
		if want > v:
			v = minf(v + ACCEL * dt, want)
		else:
			v = maxf(v - BRAKE * dt, want)
		c["vel"] = v * dir
	var keep: Array[Dictionary] = []
	for c in _cars:
		var node := c["node"] as Node3D
		node.position.z += float(c["vel"]) * dt
		if absf(node.position.z - _street_z0) > CAR_EDGE + SIGNAL_X + 2.0:
			if bool(c["spot"]):
				_spots -= 1
			node.queue_free()
		else:
			keep.push_back(c)
	_cars = keep
	# Each lane fills from its edge: the next car joins once the last has
	# pulled a pitch ahead, after a moment's hesitation.
	for k in 2:
		var dir := 1.0 if k == 0 else -1.0
		_lane_wait[k] = float(_lane_wait[k]) - dt
		if float(_lane_wait[k]) <= 0.0 and lane_clear(dir) and _cars.size() < MAX_CARS:
			spawn_car(dir)
			_lane_wait[k] = _rng.randf_range(CAR_GAP.x, CAR_GAP.y)
