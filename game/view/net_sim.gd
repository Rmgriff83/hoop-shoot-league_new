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
##
## Structure sources feed the one solver. setup(mi) takes a mesh (the
## primitive fallback, the tests' cylinder). setup_cotton() / setup_chain()
## take no mesh: the particles are the knots and pinned hooks of a net tied
## the way a real one is (knotted_layout(), docs/BLENDER_101.md §28–29) and a
## NetRig body (CottonNet, ChainNet) rides its bones, so nothing is rebuilt
## per frame. NetSim itself draws nothing but the mesh it was handed.

## Fixed internal step (s). Position-based springs settle differently per step
## size, so the net always integrates at exactly this rate (frame-rate
## independent and identical on every device); frames accumulate into it.
const STEP := 1.0 / 120.0
const MAX_STEPS_PER_FRAME := 6
const ITERATIONS := 3
## Feel (instance fields so a HoopSet can configure them; defaults = classic).
var damping := 0.9864   # Ross, on-device 2026-10-03 (was 0.9965)
const GRAVITY := 9.81
## Cord elasticity: fraction of a spring's length error corrected per iteration.
## Below 1 the cords STRETCH under the ball and store energy, which is what
## whips them back up after it passes (1.0 = inextensible, no snap at all).
var stiffness := 0.14
## Shape memory, two parts: a SPRING toward the rest shape (an acceleration,
## /s², so the cords carry momentum through rest and overshoot) and a faint
## per-substep positional pull that kills the last millimetres of drift.
var rest_spring := 0.0     # the cotton net: no memory (2026-10-14; the mesh net ran 90 / 0.003)
var rest_pull := 0.0
## The bottom ring's share of gravity (×): heavier, it lags the ball and
## whips back up after it.
var tail_mass := 0.5       # 2026-10-14 (was 1.6)
## The swish kick (m/s) kick() hands the cords under an entering ball.
var kick_speed := 4.7      # 2026-10-14 (was 1.6)
const CORD_R := 0.012
## Cords within this band outside the ball's surface are drawn onto it (the net
## drapes and grips the ball rather than merely being pushed).
var grab_band := 0.06
var grab_pull := 0.0    # Ross, on-device 2026-10-03: no drape-grab on nylon
## Fraction of the ball's surface velocity handed to cords it grips. This is
## the backspin grab: the spinning surface drags the front cords down as it
## passes, and the stretched cords whip them back up afterwards.
var ball_friction := 0.09  # 2026-10-14 (was 0.55)
const WAKE_RANGE := 0.7
const SLEEP_POS_EPS := 0.004   # gravity sags the cords ~2 mm below rest
const SLEEP_VEL_EPS := 0.002
const SLEEP_EASE_S := 0.3      # near rest this long, eased home, then asleep
const SLEEP_EASE := 0.1        # per-frame lerp toward rest while easing
const KICK_REACH := 0.08       # m beyond the ball's radius that the kick reaches

## "mesh" (setup), "cotton" (setup_cotton) or "chain" (setup_chain).
var structure := "mesh"
var _mi: MeshInstance3D
var _space: Node3D               # the node whose local space the particles live in
var _mesh: ArrayMesh
var _arrays: Array = []
var _material: Material
var _anchor := PackedVector3Array()   # the authored layout: the shape memory's target
var _rest := PackedVector3Array()     # the settled idle pose: sleep, ease-home, displacement
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
		_weigh_tail()
		resettle()


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
		_weigh_tail()
	resettle()


## The bottom ring's share of gravity (tail_mass); the rest weigh 1.
func _weigh_tail() -> void:
	if _rest.is_empty():
		return
	_g_scale.resize(_rest.size())
	if not _bottom.is_empty():
		_g_scale.fill(1.0)
		for i in _bottom:
			_g_scale[i] = tail_mass
		return
	var y_min := INF
	for p in _anchor:
		y_min = minf(y_min, p.y)
	for i in _anchor.size():
		_g_scale[i] = tail_mass if _anchor[i].y <= y_min + 1e-4 else 1.0


## On-device overrides over the hoop set's values ({knob: value}).
func apply_overrides(d: Dictionary) -> void:
	for k in d:
		if KNOBS.has(str(k)) and (d[k] is float or d[k] is int):
			set(str(k), float(d[k]))
	if _ready_ok:
		_weigh_tail()
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
	_space = mi
	structure = "mesh"
	_bottom = PackedInt32Array()
	_layout = {}
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
	_anchor = _rest.duplicate()
	_pos = _rest.duplicate()
	_prev = _rest.duplicate()

	# Pin the top ring (highest particles) to the rim.
	var y_max := -INF
	for p in _rest:
		y_max = maxf(y_max, p.y)
	_pinned.resize(_rest.size())
	for i in _rest.size():
		_pinned[i] = 1 if _rest[i].y >= y_max - 1e-4 else 0
	_weigh_tail()   # the bottom ring hangs heavier
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



## ---- Knotted nets (2026-10-14): twelve continuous cords or chains ----
## No ring cords. Cord i climbs a left diagonal from the bottom
## (Knot_k_((i−k) mod 12), k = ROWS…1), rises through its top knot Knot_0_i,
## turns over Hook_i and comes back down the right diagonal (Knot_k_i,
## k = 1…ROWS); neighbouring cords are knotted where they cross, which makes
## the diamonds. Ross's design models (26a cotton, 27a chain) with one change:
## the hooks sit UNDER the rim tube so nothing shows above the rim line.
const COLS := 12
const COTTON_COLS := COLS
const COTTON_ROWS := 6                # 7 rings of knots, the top one included
const CHAIN_ROWS := 4                 # 5 rings (build_chain_hoop.py NET_RINGS)
const NET_LEN := 0.42                 # rim centre line → bottom ring (m)
const COTTON_LEN := NET_LEN
const NET_BOTTOM_R := 0.10
const COTTON_BOTTOM_R := NET_BOTTOM_R
const COTTON_TOP_GAP := 0.028         # cotton: ring 0 hangs this far below the tube's underside
const HOOK_DROP := 0.9                # cotton: hook height = −tube_r × this (inside the tube)
const HOOK_OUT := 0.002               # cotton: hook radius = rim_r + this
const CHAIN_HOOK_DROP := 0.030        # chain: S-hook bone = −(tube_r + this), its top curl on the rim's NetHook loop
const CHAIN_HOOK_HH := 0.025          # chain: ring 0 hangs this far under the S-hooks (one link)
var _bottom := PackedInt32Array()     # particle indices of the bottom ring
var _layout: Dictionary = {}          # the knotted layout this sim was built from


## Ring k's radius at t = k / ROWS: tapers fast near the rim, gently below.
static func cotton_ring_radius(t: float, rim_r := SimConstants.R_RIM) -> float:
	return rim_r + (NET_BOTTOM_R - rim_r) * (1.0 - pow(1.0 - t, 1.7))


## A knotted layout, in rim space (origin = rim centre, y up, metres):
## {knots: PackedVector3Array (ring-major: ring k, knot i at k×12+i),
##  hooks: PackedVector3Array (12), springs: [[a, b, rest_len]] (particle
##  indices with the hooks FIRST: hook i = i, knot (k, i) = 12 + k×12 + i),
##  cords: [{left: [idx per ring], right: [idx per ring], hook, k0}],
##  bottom: [12 particle indices], ring_y: [heights], rows}.
static func knotted_layout(rows: int, ring0_y: float, hook_r: float, hook_y: float, rim_r := SimConstants.R_RIM) -> Dictionary:
	var knots := PackedVector3Array()
	var hooks := PackedVector3Array()
	var ring_y := PackedFloat32Array()
	for k in rows + 1:
		var t := float(k) / float(rows)
		var r := cotton_ring_radius(t, rim_r)
		var y := ring0_y + (-NET_LEN - ring0_y) * t
		ring_y.push_back(y)
		for i in COLS:
			var a := (float(i) + float(k) * 0.5) / float(COLS) * TAU
			knots.push_back(Vector3(r * cos(a), y, r * sin(a)))
	for i in COLS:
		var a := float(i) / float(COLS) * TAU
		hooks.push_back(Vector3(hook_r * cos(a), hook_y, hook_r * sin(a)))
	var knot_idx := func(k: int, i: int) -> int:
		return COLS + k * COLS + posmod(i, COLS)
	var springs: Array = []
	var cords: Array = []
	var seen := {}
	var add_spring := func(a: int, b: int) -> void:
		var key := Vector2i(mini(a, b), maxi(a, b))
		if seen.has(key):
			return
		seen[key] = true
		var pa: Vector3 = hooks[a] if a < COLS else knots[a - COLS]
		var pb: Vector3 = hooks[b] if b < COLS else knots[b - COLS]
		springs.push_back([a, b, pa.distance_to(pb)])
	for i in COLS:
		var left: Array = []
		var right: Array = []
		for k in rows + 1:
			left.push_back(knot_idx.call(k, i - k))
			right.push_back(knot_idx.call(k, i))
		for k in rows:
			add_spring.call(left[k], left[k + 1])
			add_spring.call(right[k], right[k + 1])
		add_spring.call(knot_idx.call(0, i), i)
		cords.push_back({"left": left, "right": right, "hook": i, "k0": knot_idx.call(0, i)})
	var bottom: Array = []
	for i in COLS:
		bottom.push_back(knot_idx.call(rows, i))
	return {"knots": knots, "hooks": hooks, "springs": springs, "cords": cords, "bottom": bottom, "ring_y": ring_y, "rows": rows}


## The cotton net (docs/BLENDER_101.md §28): 7 rings, hooks tucked inside the
## rim tube just outside its centre line, the top knots under its underside.
static func cotton_layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	return knotted_layout(COTTON_ROWS, -(tube_r + COTTON_TOP_GAP), rim_r + HOOK_OUT, -tube_r * HOOK_DROP, rim_r)


## The chain net (§29): 5 rings, the S-hook bones on the rim's radius under
## its NetHook loops, the top junction rings one link below them.
static func chain_layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	var hook_y := -(tube_r + CHAIN_HOOK_DROP)
	return knotted_layout(CHAIN_ROWS, hook_y - CHAIN_HOOK_HH, rim_r, hook_y, rim_r)


## Build the particles from a knotted layout: hooks first (pinned), then the
## knots; springs = the cord pieces; the bottom ring weighs tail_mass.
## `space` is the node whose local space the layout lives in (the NetRig at
## the rim centre). No mesh: the rig reads the particles each frame.
func setup_cotton(space: Node3D, rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> bool:
	return setup_layout(space, cotton_layout(rim_r, tube_r), "cotton")


func setup_chain(space: Node3D, rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> bool:
	return setup_layout(space, chain_layout(rim_r, tube_r), "chain")


## Any knotted layout ({knots, hooks, springs, bottom, …} — a net body's
## static layout()); `tag` is the net KIND ("cotton" | "chain") for tests.
func setup_layout(space: Node3D, layout: Dictionary, tag: String) -> bool:
	if space == null or not layout.has("knots") or not layout.has("hooks") or not layout.has("springs"):
		return false
	_space = space
	_mi = null
	structure = tag
	_layout = layout
	var hooks: PackedVector3Array = layout["hooks"]
	var knots: PackedVector3Array = layout["knots"]
	_rest = PackedVector3Array()
	_pinned = PackedByteArray()
	for h in hooks:
		_rest.push_back(h)
		_pinned.push_back(1)
	for k in knots:
		_rest.push_back(k)
		_pinned.push_back(0)
	_anchor = _rest.duplicate()
	_pos = _rest.duplicate()
	_prev = _rest.duplicate()
	_bottom = PackedInt32Array(layout["bottom"])
	_weigh_tail()
	_spring_a = PackedInt32Array()
	_spring_b = PackedInt32Array()
	_spring_len = PackedFloat32Array()
	for s in layout["springs"]:
		_spring_a.push_back(int(s[0]))
		_spring_b.push_back(int(s[1]))
		_spring_len.push_back(float(s[2]))
	_vert_to_particle = PackedInt32Array()
	_index = PackedInt32Array()
	_arrays = []
	_ready_ok = true
	_settle_rest()
	_awake = false
	return true


## The knotted layout this sim was built from (empty for a mesh).
func layout() -> Dictionary:
	return _layout


## The net's cords ({left, right, hook, k0} per cord; empty for a mesh).
func cords() -> Array:
	return _layout.get("cords", [])


func cotton_cords() -> Array:
	return cords()


func is_pinned(i: int) -> bool:
	return _pinned[i] == 1


## The springs as [a, b, rest_len] (particle indices).
func spring_count() -> int:
	return _spring_a.size()


func spring(i: int) -> Array:
	return [_spring_a[i], _spring_b[i], _spring_len[i]]


## Let the cords sag under gravity and adopt that as the rest pose, so the
## idle net hangs naturally and "at rest" really is at rest (sleep works).
## The shape memory pulls toward the ANCHOR (the authored layout), never
## toward the settled pose: re-baking the spring's target each round would
## let a soft net (the chain's 0.22 stiffness) sink a few millimetres every
## round and hang below rest for ever, never asleep (2026-10-14). Settled
## against the fixed anchor, the equilibrium is stationary, and that is rest.
func _settle_rest() -> void:
	for _i in 1440:
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
	var xf := _space.global_transform if _space.is_inside_tree() else _space.transform
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
		var to_anchor := _anchor[i] - p
		p += v + g * (_g_scale[i] if i < _g_scale.size() else 1.0) + to_anchor * k_spring
		p += (_anchor[i] - p) * rest_pull
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
	var xf := _space.global_transform if _space.is_inside_tree() else _space.transform
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
	if structure != "mesh":
		return   # a CottonNet reads the particles itself (sync)
	var verts: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = _pos[_vert_to_particle[i]]
	_arrays[Mesh.ARRAY_VERTEX] = verts
	_recompute_normals(verts)
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	if _material != null:
		_mesh.surface_set_material(0, _material)
