class_name BallPool
extends Node3D
## Renders sim BallStates onto a pool of MeshInstance3D spheres, plus the held
## ball in the shooter's hands. Scene space = canonical sim space, so mapping
## is a straight copy (float32 truncation here is render-only — the sim keeps
## its own float64 state).

const POOL_SIZE := 8
## Squash feel. The ball dents along the surface it hit, by an amount set by the
## contact's normal closing speed — so a square floor slam flattens it and a
## glancing rim kiss barely moves it.
##
## SQUASH_KICK is sized so a reference impact peaks at exactly MAX_SQUASH when
## the spring is sampled at 60 Hz (measured against the real stepper, not the
## analytic peak, which a frame grid straddles). Faster frame rates sample
## nearer the true peak and are caught by the clamp.
## NOTE: these two move TOGETHER. The kick is capped at the reference impact,
## so it alone sets what a hard hit reaches; MAX_SQUASH is only the ceiling
## above it. Raising the ceiling on its own changes nothing.
## These three move TOGETHER. The kick is capped at IMPACT_REF, so it alone
## sets what a hard hit reaches; MAX_SQUASH is only the ceiling above it.
## Raising the ceiling on its own changes nothing.
##
## IMPACT_REF is calibrated from REAL play, not guessed: a device capture of
## 21 contacts over 5 shots (2026-09-20) ran 1.65 - 8.04 m/s with a median of
## 3.91. The first pass used 7.0, so a typical bounce only earned ~56 % of the
## kick and dented about 9 % - visible in a test, invisible in the hand. At 4.5
## a normal bounce uses most of the range and genuinely hard hits saturate.
const MAX_SQUASH := 0.30
const IMPACT_REF := 4.5     # m/s of normal closing speed = a solid hit
## The dent's SHAPE, which mattered far more than its size. Tuned against the
## device, and the last fix was the important one:
##
## The dent used to be KICKED — velocity added to a spring starting at zero —
## so it ramped UP over ~50 ms and peaked well after the ball had already left
## the floor. On screen that read as the ball anticipating the bounce: it was
## most deformed in mid-air. A real ball is flattest AT the contact.
##
## So the dent is now SET at full depth on the contact frame and only decays.
## (360, 0.9) ramping in -> "very slow", "anticipating". (700, 1.0) set-and-
## decay -> full depth on the contact frame, gone in 0.13 s. Damping is exactly
## 1 so the decay is monotonic: it dents once and recovers, never flutters.
const SQUASH_STIFFNESS := 700.0
const SQUASH_DAMPING := 1.0
## Rest pose of the held ball. x = 0 is the sim's canonical release plane, so
## the finger-projected hand point IS the shot's release origin (no hop).
const HELD_POS := Vector3(0.0, 1.25, 0.0)
## Live rest pose (the screen moves it when the shooter changes spot).
var rest_pos := HELD_POS

var _pool: Array[MeshInstance3D] = []
var _squash: Array[JuiceSpring] = []
## Which BallState currently owns each pool slot. The squash springs are keyed
## by SLOT (squash_at() finds a ball by world position, not by identity),
## but the flight list compacts when a ball resolves — ball 1 slides into slot
## 0 and would inherit the dead ball's still-ringing oscillation, a visible pop
## on an unrelated ball. Re-seating a slot resets its spring.
var _ball_in_slot: Array = []
## World-space surface normal of each slot's last contact — the axis it dents
## along. Defaults to up so a ball that somehow squashes without a recorded
## contact behaves like the old vertical flatten rather than vanishing.
var _squash_n: Array[Vector3] = []
var _held: MeshInstance3D

## Every pickup grabs the ball however it comes: a fresh random orientation,
## carried from the hand into the flight so release doesn't snap the texture.
## Purely presentational — the sim core stays RNG-free and deterministic.
var _rng := RandomNumberGenerator.new()
var _grab_base := Basis.IDENTITY
var _base_by_ball := {}   # BallState → Basis (orientation at release)
var _angle_by_ball := {}  # BallState → float (integrated backspin angle)
var _roll_by_ball := {}   # BallState → float (integrated roll about the travel axis)


## The active ball bundle (skin, squash feel). Set before add_child; defaults to
## the starter set. Every ball shares ONE mesh and differs only by `skin_path`,
## applied per-instance as a material_override.
##
## material_override specifically, NOT mesh.surface_set_material(): all nine
## MeshInstance3Ds here share a single Mesh, and load() hands the heat screen's
## second pool the very same cached sub-resource — so writing to the surface
## would repaint every ball in the session, the AI court's included, and poison
## the imported resource until restart.
var ball_set: BallSet

var _skin_mat: StandardMaterial3D


func _ready() -> void:
	if ball_set == null:
		ball_set = CosmeticLibrary.starter_ball()
	var ball_mesh := _load_ball_mesh()
	_skin_mat = _make_skin_mat()
	for i in POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.name = "Ball%d" % i
		mi.mesh = ball_mesh
		mi.material_override = _skin_mat
		mi.visible = false
		add_child(mi)
		_pool.push_back(mi)
		_squash.push_back(JuiceSpring.new(0.0, SQUASH_STIFFNESS, SQUASH_DAMPING))
		_ball_in_slot.push_back(null)
		_squash_n.push_back(Vector3.UP)
	_held = MeshInstance3D.new()
	_held.name = "HeldBall"
	_held.mesh = ball_mesh
	_held.material_override = _skin_mat
	_held.visible = false
	_held.position = rest_pos
	add_child(_held)
	_rng.randomize()
	_grab_base = _random_grab()


## The skin, as one material shared by all nine instances. Matches what the glb
## itself carries (roughness 0.82, double-sided) so overriding changes only the
## texture. Linear-filtered: the ball is the project's smooth exception, and
## nearest texels would fight the smooth shading.
func _make_skin_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var path := ball_set.skin_path if ball_set != null else ""
	if path != "":
		mat.albedo_texture = load(path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 0.82
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Swap the ball mid-session. Nothing else does this — App.select() only takes
## effect on the next screen build — so the tuning-mode ball cycler needs it.
## Only the skin changes; the mesh is shared and never reloaded.
func set_ball_set(s: BallSet) -> void:
	if s == null:
		return
	ball_set = s
	var tex: Texture2D = load(s.skin_path) if s.skin_path != "" else null
	if _skin_mat != null:
		_skin_mat.albedo_texture = tex


## Pull the ArrayMesh out of the imported glb scene. Falls back to a plain
## textured SphereMesh if the model is missing so the game still runs.
func _load_ball_mesh() -> Mesh:
	var path := ball_set.model_path if ball_set != null else ""
	var scene: PackedScene = load(path) if path != "" else null
	if scene:
		var root: Node = scene.instantiate()
		var mesh := _find_mesh(root)
		root.free()
		if mesh:
			return mesh
	push_warning("BallPool: %s missing a MeshInstance3D, using SphereMesh fallback" % path)
	var sphere := SphereMesh.new()
	sphere.radius = SimConstants.R_BALL
	sphere.height = SimConstants.R_BALL * 2.0
	# No material here: the caller sets material_override on every instance, so
	# the fallback sphere gets the right skin for free.
	return sphere


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh:
		return node.mesh
	for child in node.get_children():
		var found := _find_mesh(child)
		if found:
			return found
	return null


func _random_grab() -> Basis:
	return Basis.from_euler(Vector3(
		_rng.randf_range(0.0, TAU),
		_rng.randf_range(0.0, TAU),
		_rng.randf_range(0.0, TAU)
	))


## Move the held ball (world space) — the screen projects the finger onto the
## hand plane and calls this on every drag event. Presentational only: the
## sim always launches from its own release point.
func set_held_position(p: Vector3) -> void:
	_held.position = p


## Call every frame with the rules object's in-flight balls.
func update_balls(balls: Array[BallState], holding: bool, dt: float) -> void:
	# Fresh pickup → the hand ball shows a new random grab orientation.
	if holding and not _held.visible:
		_grab_base = _random_grab()
		_held.basis = _grab_base
	# Ball left the hand → park the visual back at the rest pose.
	if not holding and _held.visible:
		_held.position = rest_pos
	for i in _pool.size():
		var mi := _pool[i]
		if i < balls.size():
			var s := balls[i]
			if _ball_in_slot[i] != s:
				_ball_in_slot[i] = s
				_squash[i].set_to(0.0)
				_squash_n[i] = Vector3.UP
			# First frame in flight: inherit the orientation it was held with.
			if not _base_by_ball.has(s):
				_base_by_ball[s] = _grab_base
				_angle_by_ball[s] = 0.0
			mi.visible = true
			# Integrate the sim's real spin (positive = backspin; decays on
			# rim/board contacts) and roll about the sim's spin axis, which is
			# perpendicular to the launch bearing (world z for a center shot).
			_angle_by_ball[s] += s.spin * dt
			_roll_by_ball[s] = _roll_by_ball.get(s, 0.0) + s.roll * dt
			var spin_axis := Vector3(-s.dir_z, 0.0, s.dir_x)
			var travel_axis := Vector3(s.dir_x, 0.0, s.dir_z)
			# Typed explicitly: the dictionary lookups are Variant, so `:=` here
			# cannot infer Basis and the file fails to parse.
			var rot: Basis = (
				Basis(travel_axis, _roll_by_ball[s])
				* Basis(spin_axis, _angle_by_ball[s])
				* _base_by_ball[s]
			)
			var gain := ball_set.squash_gain if ball_set != null else 1.0
			# Clamped at zero on the low side: that clips the spring's rebound
			# half, so the ball dents and recovers but never stretches.
			var sq := clampf(_squash[i].step(dt) * gain, 0.0, MAX_SQUASH)
			var n: Vector3 = _squash_n[i]
			# Composed OUTSIDE the spin so the dent stays locked to the surface
			# that caused it. Writing mi.scale or mi.rotation after this would
			# make Godot re-derive the basis and silently discard the shear —
			# which is exactly the bug this replaces (the old code scaled local
			# Y, an axis that tumbles with backspin).
			mi.basis = _squash_basis(n, sq) * rot
			# The sim holds the centre at R_BALL through a contact, so a centre-
			# scaled dent would lift the flattened face off the surface. Offset
			# the node to keep the contact face planted.
			mi.position = (Vector3(s.pos.x, s.pos.y, s.pos.z)
				- n * (SimConstants.R_BALL * sq))
		else:
			mi.visible = false
			_squash[i].set_to(0.0)
			_ball_in_slot[i] = null
			_squash_n[i] = Vector3.UP
	_held.visible = holding
	# Drop rotation state for balls that left the sim.
	if _base_by_ball.size() > balls.size():
		for key in _base_by_ball.keys():
			if not balls.has(key):
				_base_by_ball.erase(key)
				_angle_by_ball.erase(key)
				_roll_by_ball.erase(key)


## Dent the pool ball nearest a contact, along that contact's surface normal.
## `impact` is the sim's normal closing speed (already cos^2-scaled for rim
## hits), so a graze deforms far less than a square hit with no extra maths.
func squash_at(pos: Vector3, normal: Vector3, impact: float) -> void:
	if normal.length_squared() < 1e-12:
		# Colliders.rim_contact can hand back a zero normal from its d < 1e-9
		# guard. Normalising that would poison the basis with NaN.
		return
	var best := -1
	var best_d := 0.5  # only squash if a visible ball is plausibly at the contact
	for i in _pool.size():
		if not _pool[i].visible:
			continue
		var d := _pool[i].position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return
	_squash_n[best] = normal.normalized()
	# Set, don't kick: the ball is at its flattest the instant it lands, not
	# 50 ms later. maxf keeps a harder hit from being softened by a graze that
	# lands while the previous dent is still recovering.
	var target := minf(impact / IMPACT_REF, 1.0) * MAX_SQUASH
	_squash[best].value = maxf(_squash[best].value, target)
	_squash[best].velocity = 0.0


## Flatten by `s` along `n` and bulge by half that across it, so the silhouette
## holds its mass. Built from the three world axes rather than an orthonormal
## frame around `n`, which would need a fallback when `n` is parallel to the
## reference axis; this form is symmetric and has no degenerate case.
static func _squash_basis(n: Vector3, s: float) -> Basis:
	if s <= 0.0:
		return Basis.IDENTITY
	var bulge := s * 0.5
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var cols: Array[Vector3] = []
	for axis in axes:
		var along := n * axis.dot(n)
		cols.push_back((axis - along) * (1.0 + bulge) + along * (1.0 - s))
	return Basis(cols[0], cols[1], cols[2])
