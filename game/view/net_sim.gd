class_name NetSim
extends Node
## Runtime net: the hoop's Net mesh driven as a Verlet cord lattice by the sim's
## balls — position, velocity and backspin — so every make deforms the net the
## way that ball actually went through it. Visual only: it reads BallStates and
## never pushes back on the sim. No randomness, so the same shot always looks
## the same.
##
## Setup takes the Blender-authored Net MeshInstance3D (rest shape, UVs,
## material come from the glb); the mesh is replaced by a dynamic ArrayMesh
## rebuilt each frame the net is awake. Particles are the mesh's unique vertex
## positions, springs are its edges plus a weak "cord memory" pull toward the
## rest shape; the top ring is pinned to the rim.

## Fixed internal step (s). Position-based springs settle differently per step
## size, so the net always integrates at exactly this rate (frame-rate
## independent and identical on every device); frames accumulate into it.
const STEP := 1.0 / 120.0
const MAX_STEPS_PER_FRAME := 8
const ITERATIONS := 3
## Feel (instance fields so a HoopSet can configure them; defaults = classic).
var damping := 0.999
const GRAVITY := 9.81
## Cord elasticity: fraction of a spring's length error corrected per iteration.
## Below 1 the cords STRETCH under the ball and store energy, which is what
## whips them back up after it passes (1.0 = inextensible, no snap at all).
var stiffness := 0.08
## Per-substep pull toward the rest shape — a nylon net's shape memory.
var rest_pull := 0.018
const CORD_R := 0.012
## Cords within this band outside the ball's surface are drawn onto it (the net
## drapes and grips the ball rather than merely being pushed).
var grab_band := 0.05
var grab_pull := 0.6
## Fraction of the ball's surface velocity handed to cords it grips. This is
## the backspin grab: the spinning surface drags the front cords down as it
## passes, and the stretched cords whip them back up afterwards.
var ball_friction := 1.0
const WAKE_RANGE := 0.7
const SLEEP_POS_EPS := 0.004   # gravity sags the cords ~2 mm below rest
const SLEEP_VEL_EPS := 0.002

var _mi: MeshInstance3D
var _mesh: ArrayMesh
var _arrays: Array = []
var _material: Material
var _rest := PackedVector3Array()
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _pinned := PackedByteArray()
var _vert_to_particle := PackedInt32Array()
var _spring_a := PackedInt32Array()
var _spring_b := PackedInt32Array()
var _spring_len := PackedFloat32Array()
var _awake := false
var _ready_ok := false
var _accum := 0.0


## Ball description for step(): world position/velocity (m, m/s), scalar spin
## (rad/s) about `axis` (unit, world), radius (m).
static func ball_from_state(s: BallState) -> Dictionary:
	return {
		"pos": Vector3(s.pos.x, s.pos.y, s.pos.z),
		"vel": Vector3(s.vel.x, s.vel.y, s.vel.z),
		"spin": float(s.spin),
		"axis": Vector3(-s.dir_z, 0.0, s.dir_x),
		"radius": SimConstants.R_BALL,
	}


## Apply a hoop set's net feel. Call BEFORE setup() (the rest pose is settled
## with these values); calling after re-settles.
func configure(set: HoopSet) -> void:
	stiffness = set.net_stiffness
	damping = set.net_damping
	rest_pull = set.net_rest_pull
	grab_band = set.net_grab_band
	grab_pull = set.net_grab_pull
	ball_friction = set.net_friction
	if _ready_ok:
		_pos = _rest.duplicate()
		_prev = _rest.duplicate()
		_settle_rest()
		_upload()


## Take over a MeshInstance3D's mesh (surface 0). Returns false if unusable.
func setup(mi: MeshInstance3D) -> bool:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return false
	_mi = mi
	var src: Mesh = mi.mesh
	_arrays = src.surface_get_arrays(0)
	var verts: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = _arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty():
		return false
	_material = mi.material_override if mi.material_override != null else src.surface_get_material(0)
	if index.is_empty():
		index = PackedInt32Array()
		for i in verts.size():
			index.push_back(i)
		_arrays[Mesh.ARRAY_INDEX] = index

	# Unique particles from quantised positions (UV-seam duplicates share one).
	var lookup := {}
	_vert_to_particle.resize(verts.size())
	_rest = PackedVector3Array()
	for i in verts.size():
		var v := verts[i]
		var key := Vector3i(roundi(v.x * 10000.0), roundi(v.y * 10000.0), roundi(v.z * 10000.0))
		if not lookup.has(key):
			lookup[key] = _rest.size()
			_rest.push_back(v)
		_vert_to_particle[i] = lookup[key]
	_pos = _rest.duplicate()
	_prev = _rest.duplicate()

	# Pin the top ring (highest particles) to the rim.
	var y_max := -INF
	for p in _rest:
		y_max = maxf(y_max, p.y)
	_pinned.resize(_rest.size())
	for i in _rest.size():
		_pinned[i] = 1 if _rest[i].y >= y_max - 1e-4 else 0

	# Springs = mesh edges (structural + the triangle diagonals), deduplicated.
	var seen := {}
	_spring_a = PackedInt32Array()
	_spring_b = PackedInt32Array()
	_spring_len = PackedFloat32Array()
	for t in range(0, index.size() - 2, 3):
		var tri := [_vert_to_particle[index[t]], _vert_to_particle[index[t + 1]], _vert_to_particle[index[t + 2]]]
		for e in 3:
			var a: int = tri[e]
			var b: int = tri[(e + 1) % 3]
			if a == b:
				continue
			var k := Vector2i(mini(a, b), maxi(a, b))
			if seen.has(k):
				continue
			seen[k] = true
			_spring_a.push_back(k.x)
			_spring_b.push_back(k.y)
			_spring_len.push_back(_rest[k.x].distance_to(_rest[k.y]))

	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	if _material != null:
		_mesh.surface_set_material(0, _material)
	_mi.mesh = _mesh
	_mi.material_override = null
	_ready_ok = true
	_settle_rest()
	_upload()
	_awake = false
	return true


## Let the cords sag under gravity and adopt that as the rest pose, so the
## idle net hangs naturally and "at rest" really is at rest (sleep works).
func _settle_rest() -> void:
	for _round in 3:
		for _i in 480:
			_substep(STEP, [])
		_rest = _pos.duplicate()
		_prev = _pos.duplicate()


func particle_count() -> int:
	return _rest.size()


func is_awake() -> bool:
	return _awake


func particle_position(i: int) -> Vector3:
	return _pos[i]


func rest_position(i: int) -> Vector3:
	return _rest[i]


## Largest displacement of any particle from its rest position (m).
func max_displacement() -> float:
	var m := 0.0
	for i in _pos.size():
		m = maxf(m, _pos[i].distance_to(_rest[i]))
	return m


## Advance the net by dt with the given balls (see ball_from_state).
func step(dt: float, balls: Array) -> void:
	if not _ready_ok:
		return
	# Balls in the net's local space (the pivot wobbles and the board slides).
	var xf := _mi.global_transform if _mi.is_inside_tree() else _mi.transform
	var inv := xf.affine_inverse()
	var local_balls: Array = []
	var near := false
	for b in balls:
		var lp: Vector3 = inv * b["pos"]
		if lp.length() < WAKE_RANGE:
			near = true
		local_balls.push_back({
			"pos": lp,
			"vel": inv.basis * b["vel"],
			"spin": b["spin"],
			"axis": (inv.basis * b["axis"]).normalized(),
			"radius": b["radius"],
		})
	if near:
		_awake = true
	if not _awake:
		_accum = 0.0
		return

	_accum += dt
	var steps := mini(int(floor(_accum / STEP)), MAX_STEPS_PER_FRAME)
	_accum -= steps * STEP
	if steps == 0:
		return
	for _s in steps:
		_substep(STEP, local_balls)

	# Sleep once still and alone.
	if not near:
		var max_v := 0.0
		for i in _pos.size():
			max_v = maxf(max_v, _pos[i].distance_to(_prev[i]))
		if max_displacement() < SLEEP_POS_EPS and max_v < SLEEP_VEL_EPS:
			_pos = _rest.duplicate()
			_prev = _rest.duplicate()
			_awake = false
	_upload()


func _substep(h: float, balls: Array) -> void:
	var n := _pos.size()
	var g := Vector3(0.0, -GRAVITY * h * h, 0.0)
	# Verlet integrate + cord memory.
	for i in n:
		if _pinned[i] == 1:
			continue
		var p := _pos[i]
		var v := (p - _prev[i]) * damping
		_prev[i] = p
		p += v + g
		p += (_rest[i] - p) * rest_pull
		_pos[i] = p
	# Ball contact: push cords to the ball's surface, hand them surface velocity.
	for b in balls:
		var c: Vector3 = b["pos"]
		var r: float = b["radius"] + CORD_R
		var omega: Vector3 = b["axis"] * b["spin"]
		for i in n:
			if _pinned[i] == 1:
				continue
			var d := _pos[i] - c
			var dist := d.length()
			if dist >= r + grab_band or dist < 1e-6:
				continue
			var nrm := d / dist
			if dist < r:
				_pos[i] = c + nrm * r          # pushed out to the surface
			else:
				_pos[i] = _pos[i].lerp(c + nrm * r, grab_pull)   # draped onto it
			var surf: Vector3 = b["vel"] + omega.cross(nrm * b["radius"])
			var tangent := surf - nrm * surf.dot(nrm)
			var cur := _pos[i] - _prev[i]
			var want := tangent * h
			_prev[i] = _pos[i] - (cur * (1.0 - ball_friction) + want * ball_friction)
	# Distance constraints.
	for _it in ITERATIONS:
		for s in _spring_a.size():
			var a := _spring_a[s]
			var b := _spring_b[s]
			var delta := _pos[b] - _pos[a]
			var dist := delta.length()
			if dist < 1e-9:
				continue
			var diff := (dist - _spring_len[s]) / dist * stiffness
			var pa := _pinned[a] == 1
			var pb := _pinned[b] == 1
			if pa and pb:
				continue
			if pa:
				_pos[b] -= delta * diff
			elif pb:
				_pos[a] += delta * diff
			else:
				_pos[a] += delta * (0.5 * diff)
				_pos[b] -= delta * (0.5 * diff)
	for i in n:
		if _pinned[i] == 1:
			_pos[i] = _rest[i]


func _upload() -> void:
	var verts: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = _pos[_vert_to_particle[i]]
	_arrays[Mesh.ARRAY_VERTEX] = verts
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	if _material != null:
		_mesh.surface_set_material(0, _material)
