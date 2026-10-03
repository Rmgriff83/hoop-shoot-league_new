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
## positions, springs are its edges plus a "cord memory" SPRING toward the
## rest shape (a force, so the net overshoots and rings down — the snap of a
## real swish, 2026-10-03) and a faint positional pull; the top ring is pinned
## to the rim, the bottom ring hangs heavier so it lags and whips back. The
## ball is sub-sampled between frames, the sim's rim-plane `enter` event
## kicks the cords (kick()), the net eases to sleep rather than jumping, and
## the normals follow the cords so the light does too.

## Fixed internal step (s). Position-based springs settle differently per step
## size, so the net always integrates at exactly this rate (frame-rate
## independent and identical on every device); frames accumulate into it.
const STEP := 1.0 / 120.0
const MAX_STEPS_PER_FRAME := 6
const ITERATIONS := 3
## Feel (instance fields so a HoopSet can configure them; defaults = classic).
var damping := 0.9965
const GRAVITY := 9.81
## Cord elasticity: fraction of a spring's length error corrected per iteration.
## Below 1 the cords STRETCH under the ball and store energy, which is what
## whips them back up after it passes (1.0 = inextensible, no snap at all).
var stiffness := 0.14
## Shape memory, two parts: a SPRING toward the rest shape (an acceleration,
## /s², so the cords carry momentum through rest and overshoot) and a faint
## per-substep positional pull that kills the last millimetres of drift.
var rest_spring := 90.0
var rest_pull := 0.003
## The bottom ring's share of gravity (×): heavier, it lags the ball and
## whips back up after it.
var tail_mass := 1.6
## The swish kick (m/s) kick() hands the cords under an entering ball.
var kick_speed := 1.6
const CORD_R := 0.012
## Cords within this band outside the ball's surface are drawn onto it (the net
## drapes and grips the ball rather than merely being pushed).
var grab_band := 0.05
var grab_pull := 0.6
## Fraction of the ball's surface velocity handed to cords it grips. This is
## the backspin grab: the spinning surface drags the front cords down as it
## passes, and the stretched cords whip them back up afterwards.
var ball_friction := 0.55
const WAKE_RANGE := 0.7
const SLEEP_POS_EPS := 0.004   # gravity sags the cords ~2 mm below rest
const SLEEP_VEL_EPS := 0.002
const SLEEP_EASE_S := 0.3      # near rest this long, eased home, then asleep
const SLEEP_EASE := 0.1        # per-frame lerp toward rest while easing
const KICK_REACH := 0.08       # m beyond the ball's radius that the kick reaches

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
var _g_scale := PackedFloat32Array()
var _last_balls: Array = []        # last frame's local balls, for sub-sampling
var _ease_t := 0.0
var _index: PackedInt32Array = PackedInt32Array()
## Chain rendering (the city hoop): the driven surface is hidden and every
## spring between rings is drawn as a run of steel links in a multimesh.
const LINK_PITCH := 0.028
const LINK_LEN := 0.034
const LINK_W := 0.017
const LINK_WIRE := 0.0028
var _chain: MultiMeshInstance3D
var _chain_edges: PackedInt32Array = PackedInt32Array()   # spring index per rendered edge
var _chain_n: PackedInt32Array = PackedInt32Array()       # links per rendered edge
var _chain_xf: Array[Transform3D] = []                     # the placed links (a CPU copy: tests, headless)


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
	rest_spring = set.net_rest_spring
	tail_mass = set.net_tail_mass
	kick_speed = set.net_kick
	grab_band = set.net_grab_band
	grab_pull = set.net_grab_pull
	ball_friction = set.net_friction
	if _ready_ok:
		_pos = _rest.duplicate()
		_prev = _rest.duplicate()
		_settle_rest()
		_upload()


## The knobs the tuning strip turns, by name (docs/BLENDER_101.md §23).
const KNOBS := ["stiffness", "damping", "rest_pull", "rest_spring", "tail_mass", "kick_speed",
	"grab_band", "grab_pull", "ball_friction"]


func knobs() -> Dictionary:
	var out := {}
	for k in KNOBS:
		out[k] = float(get(k))
	return out


## Set one knob and re-settle the rest pose (the spring, the tail weight and
## the stiffness all change how the idle net hangs).
func set_knob(name_: String, value: float) -> void:
	if not KNOBS.has(name_):
		return
	set(name_, value)
	if name_ == "tail_mass":
		var y_min := INF
		for p in _rest:
			y_min = minf(y_min, p.y)
		for i in _rest.size():
			_g_scale[i] = tail_mass if _rest[i].y <= y_min + 1e-4 else 1.0
	resettle()


## On-device overrides over the hoop set's values ({knob: value}).
func apply_overrides(d: Dictionary) -> void:
	for k in d:
		if KNOBS.has(str(k)) and (d[k] is float or d[k] is int):
			set(str(k), float(d[k]))
	if _ready_ok:
		resettle()


func resettle() -> void:
	if not _ready_ok:
		return
	_pos = _rest.duplicate()
	_prev = _rest.duplicate()
	_settle_rest()
	_upload()
	_awake = false


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
	# The bottom ring hangs heavier.
	var y_min := INF
	for p in _rest:
		y_min = minf(y_min, p.y)
	_g_scale.resize(_rest.size())
	for i in _rest.size():
		_g_scale[i] = tail_mass if _rest[i].y <= y_min + 1e-4 else 1.0
	_index = index

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


## Draw the net as CHAIN: hide the cord surface and place a link mesh along
## every spring that runs between rings (the chains), re-placed whenever the
## particles move. Off: the surface shows again.
func set_chain(on: bool) -> void:
	if not _ready_ok:
		return
	if _chain != null:
		_chain.queue_free()
		_chain = null
	_chain_edges = PackedInt32Array()
	_chain_n = PackedInt32Array()
	_chain_xf = []
	_mi.visible = not on
	if not on:
		return
	for s in _spring_a.size():
		var a := _rest[_spring_a[s]]
		var b := _rest[_spring_b[s]]
		if absf(a.y - b.y) < 1e-4:
			continue   # a ring's horizontal: a stiffener, not a chain
		_chain_edges.push_back(s)
		_chain_n.push_back(maxi(1, roundi(a.distance_to(b) / LINK_PITCH)))
	var total := 0
	for n in _chain_n:
		total += n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _link_mesh()
	mm.instance_count = total
	_chain = MultiMeshInstance3D.new()
	_chain.name = "Chain"
	_chain.multimesh = mm
	_chain.transform = _mi.transform
	var parent := _mi.get_parent()
	if parent != null:
		parent.add_child(_chain)
	_upload_chain()


func chain_link_count() -> int:
	return _chain_xf.size()


func chain_instance_transform(i: int) -> Transform3D:
	return _chain_xf[i] if i < _chain_xf.size() else Transform3D()


## One link: an oval ring of wire (LINK_LEN x LINK_W, wire LINK_WIRE), its
## long axis along +y, its flat plane x-y. ~80 tris; galvanised grey.
static func _link_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around := 10
	var tube := 4
	var half_l := LINK_LEN * 0.5 - LINK_W * 0.5
	var ring_r := LINK_W * 0.5 - LINK_WIRE
	# Centre-line of the oval: two straight runs joined by semicircles (a stadium).
	var path: Array[Vector3] = []
	var tangents: Array[Vector3] = []
	for i in around:
		var t := float(i) / around
		var p: Vector3
		var tg: Vector3
		if t < 0.5:
			var ang := PI * (t / 0.5) - PI * 0.5      # right semicircle, from bottom to top
			p = Vector3(ring_r * cos(ang), half_l + ring_r * sin(ang), 0.0)
			tg = Vector3(-sin(ang), cos(ang), 0.0)
			if i == 0:
				p = Vector3(ring_r, -half_l, 0.0)
				tg = Vector3(0, 1, 0)
		else:
			var ang := PI * ((t - 0.5) / 0.5) + PI * 0.5   # left semicircle, top to bottom
			p = Vector3(ring_r * cos(ang), -half_l + ring_r * sin(ang), 0.0)
			tg = Vector3(-sin(ang), cos(ang), 0.0)
			if i == around / 2:
				p = Vector3(-ring_r, half_l, 0.0)
				tg = Vector3(0, -1, 0)
		path.push_back(p)
		tangents.push_back(tg.normalized())
	var rings: Array = []
	for i in around:
		var tg := tangents[i]
		var side := Vector3(0, 0, 1)
		var out := tg.cross(side).normalized()
		var ring := []
		for k in tube:
			var a := TAU * k / tube
			var nrm := (out * cos(a) + side * sin(a)).normalized()
			ring.push_back([path[i] + nrm * LINK_WIRE, nrm])
		rings.push_back(ring)
	for i in around:
		var r0: Array = rings[i]
		var r1: Array = rings[(i + 1) % around]
		for k in tube:
			var k1 := (k + 1) % tube
			for tri in [[r0[k], r1[k], r1[k1]], [r0[k], r1[k1], r0[k1]]]:
				for v in tri:
					st.set_normal(v[1])
					st.add_vertex(v[0])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.74, 0.78)
	mat.metallic = 0.6
	mat.roughness = 0.45
	mesh.surface_set_material(0, mat)
	return mesh


## Place every link along its spring: y along the edge, the flat plane
## turned 90 degrees on every other link, as a real chain hangs.
func _upload_chain() -> void:
	if _chain == null:
		return
	var mm := _chain.multimesh
	if _chain_xf.size() != mm.instance_count:
		_chain_xf.resize(mm.instance_count)
	var idx := 0
	for e in _chain_edges.size():
		var s := _chain_edges[e]
		var a := _pos[_spring_a[s]]
		var b := _pos[_spring_b[s]]
		var dir := (b - a)
		var n := _chain_n[e]
		if dir.length() < 1e-6:
			for k in n:
				_chain_xf[idx] = Transform3D(Basis(), a)
				mm.set_instance_transform(idx, _chain_xf[idx])
				idx += 1
			continue
		var y := dir.normalized()
		var ref := Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)
		var x := y.cross(ref).normalized()
		var z := x.cross(y).normalized()
		for k in n:
			var p := a + dir * ((k + 0.5) / n)
			var basis := Basis(x, y, z) if k % 2 == 0 else Basis(z, y, -x)
			_chain_xf[idx] = Transform3D(basis, p)
			mm.set_instance_transform(idx, _chain_xf[idx])
			idx += 1


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
	# Sub-sample: each ball slides from where it was last frame to where it
	# is now across the substeps, so a pass is a pull-through, not shoves.
	for si in steps:
		var f := float(si + 1) / float(steps)
		var sub: Array = []
		for k in local_balls.size():
			var cur: Dictionary = local_balls[k]
			var prev: Dictionary = _last_balls[k] if k < _last_balls.size() else cur
			var b2 := cur.duplicate()
			b2["pos"] = (prev["pos"] as Vector3).lerp(cur["pos"], f)
			sub.push_back(b2)
		_substep(STEP, sub)
	_last_balls = local_balls

	# Sleep once still and alone: ease the last millimetres home, then stop.
	if not near:
		var max_v := 0.0
		for i in _pos.size():
			max_v = maxf(max_v, _pos[i].distance_to(_prev[i]))
		if max_displacement() < SLEEP_POS_EPS and max_v < SLEEP_VEL_EPS:
			_ease_t += dt
			for i in _pos.size():
				_pos[i] = _pos[i].lerp(_rest[i], SLEEP_EASE)
				_prev[i] = _prev[i].lerp(_rest[i], SLEEP_EASE)
			if _ease_t >= SLEEP_EASE_S:
				_pos = _rest.duplicate()
				_prev = _rest.duplicate()
				_awake = false
				_ease_t = 0.0
				_last_balls = []
		else:
			_ease_t = 0.0
	else:
		_ease_t = 0.0
	_upload()


func _substep(h: float, balls: Array) -> void:
	var n := _pos.size()
	var g := Vector3(0.0, -GRAVITY * h * h, 0.0)
	var k_spring := rest_spring * h * h
	# Verlet integrate + cord memory (the spring carries momentum through
	# rest; the pull only mops up drift).
	for i in n:
		if _pinned[i] == 1:
			continue
		var p := _pos[i]
		var v := (p - _prev[i]) * damping
		_prev[i] = p
		var to_rest := _rest[i] - p
		p += v + g * (_g_scale[i] if i < _g_scale.size() else 1.0) + to_rest * k_spring
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


## The swish: the sim's rim-plane `enter` event hands the cords under the
## ball a shove along its travel (plus a little outward), so the net snaps
## down with the ball instead of waiting to be pushed. World space.
func kick(world_pos: Vector3, world_vel: Vector3, strength := -1.0) -> void:
	if not _ready_ok:
		return
	var v_kick := kick_speed if strength < 0.0 else strength
	if v_kick <= 0.0:
		return
	var xf := _mi.global_transform if _mi.is_inside_tree() else _mi.transform
	var inv := xf.affine_inverse()
	var c: Vector3 = inv * world_pos
	var dir: Vector3 = (inv.basis * world_vel)
	dir = dir.normalized() if dir.length() > 1e-6 else Vector3.DOWN
	var reach := SimConstants.R_BALL + KICK_REACH
	for i in _pos.size():
		if _pinned[i] == 1:
			continue
		var d := _pos[i] - c
		var flat := Vector3(d.x, 0.0, d.z)
		var hd := flat.length()
		if hd > reach or _pos[i].y > c.y + SimConstants.R_BALL * 0.5:
			continue
		var w := 1.0 - hd / reach
		var out := flat / hd if hd > 1e-6 else Vector3.ZERO
		var v := (dir + out * 0.35) * v_kick * w
		_prev[i] -= v * STEP
	_awake = true


## Per-vertex normals from the deformed triangles (accumulated per particle),
## so the cords shade with their shape and not with the rest pose.
func _recompute_normals(verts: PackedVector3Array) -> void:
	var acc := PackedVector3Array()
	acc.resize(_pos.size())
	acc.fill(Vector3.ZERO)
	for t in range(0, _index.size() - 2, 3):
		var a := _index[t]
		var b := _index[t + 1]
		var c := _index[t + 2]
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		acc[_vert_to_particle[a]] += fn
		acc[_vert_to_particle[b]] += fn
		acc[_vert_to_particle[c]] += fn
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		var nrm := acc[_vert_to_particle[i]]
		normals[i] = nrm.normalized() if nrm.length() > 1e-9 else Vector3.UP
	_arrays[Mesh.ARRAY_NORMAL] = normals


func _upload() -> void:
	var verts: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = _pos[_vert_to_particle[i]]
	_arrays[Mesh.ARRAY_VERTEX] = verts
	_recompute_normals(verts)
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	if _material != null:
		_mesh.surface_set_material(0, _material)
	_upload_chain()
