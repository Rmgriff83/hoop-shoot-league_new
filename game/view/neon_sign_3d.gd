class_name NeonSign3D
extends Node3D
## The splash's neon sign, the design's own model ("Neon Sign.html"): HOOP /
## SHOOT / LEAGUE as glass tubes — one continuous stroke per letter part,
## with rounded elbows — each a cream core inside an orange glass tube with
## two additive halos; the jumps between a word's strokes run behind the
## sign as blocked-out dark tubes, each word ends in an electrode, and a
## pull chain of sixteen beads hangs under the last E. Three orange spill
## lights. Built with SurfaceTool at startup (TubeGeometry's equivalent),
## animated by the design's timeline: the chain tug (0.35–1.2 s), dark
## until 1.3 s, four uneven blinks, a 2.6 s swell to full, then a breath.

const W := 0.6
const S := 0.26          # the cap height, metres
const TR := 0.0115       # tube radius
const ADV := 0.92
const ROWH := 1.42
## The jumps run this far behind the glass: past the wide halo's reach
## (TR × 4.5 = 0.052), so they never cut dark lines through the glow.
const ZB := -0.07
const ER := 0.012        # elbow radius of a jump
const ROWS := ["HOOP", "SHOOT", "LEAGUE"]
## Each letter: strokes of {r: corner radius, p: points in [0, W] × [0, 1]}.
const LETTERS := {
	"H": [{"r": 0.0, "p": [[0, 0], [0, 1]]}, {"r": 0.0, "p": [[0, 0.5], [W, 0.5]]}, {"r": 0.0, "p": [[W, 1], [W, 0]]}],
	"O": [{"r": 0.3, "p": [[W / 2, 0], [0, 0], [0, 1], [W, 1], [W, 0], [W / 2, 0]]}],
	"P": [{"r": 0.22, "p": [[0, 0], [0, 1], [W, 1], [W, 0.46], [0, 0.46]]}],
	"S": [{"r": 0.27, "p": [[W, 0.8], [W, 1], [0, 1], [0, 0.5], [W, 0.5], [W, 0], [0, 0], [0, 0.2]]}],
	"T": [{"r": 0.0, "p": [[0, 1], [W, 1]]}, {"r": 0.0, "p": [[W / 2, 1], [W / 2, 0]]}],
	"L": [{"r": 0.06, "p": [[0, 1], [0, 0], [W, 0]]}],
	"E": [{"r": 0.06, "p": [[W, 1], [0, 1], [0, 0], [W, 0]]}, {"r": 0.0, "p": [[0, 0.5], [W * 0.8, 0.5]]}],
	"A": [{"r": 0.05, "p": [[0, 0], [W / 2, 1], [W, 0]]}, {"r": 0.0, "p": [[W * 0.21, 0.42], [W * 0.79, 0.42]]}],
	"G": [{"r": 0.24, "p": [[W, 0.78], [W, 1], [0, 1], [0, 0], [W, 0], [W, 0.46], [W * 0.5, 0.46]]}],
	"U": [{"r": 0.28, "p": [[0, 1], [0, 0], [W, 0], [W, 1]]}],
}
## The design's colours.
const ON_CORE := Color("#FFF1E2")
const CORE_EMISSION := Color("#FFD2B0")
const ON_GLASS := Color("#FF7A3D")
const GLASS_EMISSION := Color("#FF5A1A")
const HALO := Color("#FF6A2A")
const HALO_WIDE := Color("#FF5A1A")
const OFF_CORE := Color("#15110F")
const OFF_GLASS := Color("#1E1714")
const BLOCKOUT := Color("#120F0E")
const STEEL := Color("#C9C4BA")
const CORE_ENERGY := 2.6
const GLASS_ENERGY := 2.4
const HALO_ALPHA := 0.22
const HALO_WIDE_ALPHA := 0.07
const SPILL := 0.45
const CHAIN_BEADS := 16
const CHAIN_DROP := 0.045
const SAMPLE := 0.012    # metres between tube rings
const DONE_S := 4.6

var _t := 0.0
var _core: StandardMaterial3D
var _glass: StandardMaterial3D
var _halo: StandardMaterial3D
var _halo_wide: StandardMaterial3D
var _chain: Node3D
var _chain_y := 0.0
var _lights: Array[OmniLight3D] = []
var _tubes := 0
var _jumps := 0
var _aabb := AABB()


func _init() -> void:
	name = "NeonSign"
	_core = StandardMaterial3D.new()
	_core.roughness = 0.4
	_core.emission_enabled = true
	_core.emission = CORE_EMISSION
	_glass = StandardMaterial3D.new()
	_glass.roughness = 0.15
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_glass.emission_enabled = true
	_glass.emission = GLASS_EMISSION
	_halo = _halo_material(HALO)
	_halo_wide = _halo_material(HALO_WIDE)
	_halo_wide.render_priority = 1
	build()
	set_level(0.0)


static func _halo_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(c, 0.0)
	m.render_priority = 2
	return m


# ---- the timeline (Neon Sign.html frame()/level()) --------------------------------


static func _ease(x: float) -> float:
	return 2.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0


static func level_at(t: float) -> float:
	if t < 1.3:
		return 0.0
	var u := t - 1.3
	if u < 0.12:
		return 0.3
	if u < 0.3:
		return 0.04
	if u < 0.42:
		return 0.4
	if u < 0.6:
		return 0.18
	if u < 3.2:
		return 0.18 + 0.82 * _ease((u - 0.6) / 2.6)
	return 1.0 - 0.07 * (0.5 - 0.5 * cos((u - 3.2) * 1.3))


## The chain's downward travel at t (metres): tugged 0.35–0.75 s, eased back by 1.2 s.
static func chain_at(t: float) -> float:
	var c := 0.0
	if t >= 0.35 and t < 0.75:
		c = (t - 0.35) / 0.4
	elif t >= 0.75 and t < 1.2:
		c = 1.0 - _ease((t - 0.75) / 0.45)
	return CHAIN_DROP * sin(minf(1.0, c) * PI / 2.0)


func time() -> float:
	return _t


func level() -> float:
	return level_at(_t)


func done() -> bool:
	return _t >= DONE_S


func replay() -> void:
	_t = 0.0
	_apply()


func step(dt: float) -> void:
	_t += dt
	_apply()


func _process(dt: float) -> void:
	step(dt)


func _apply() -> void:
	set_level(level())
	if _chain != null:
		_chain.position.y = _chain_y - chain_at(_t)


## Light the tubes: the design's per-material curve.
func set_level(k: float) -> void:
	_core.albedo_color = OFF_CORE.lerp(ON_CORE, k)
	_core.emission_energy_multiplier = CORE_ENERGY * k * k
	_glass.albedo_color = OFF_GLASS.lerp(ON_GLASS, k)
	_glass.albedo_color.a = 0.85 - 0.35 * minf(1.0, k * 1.5)
	_glass.emission_energy_multiplier = GLASS_ENERGY * k
	_halo.albedo_color.a = HALO_ALPHA * k
	_halo_wide.albedo_color.a = HALO_WIDE_ALPHA * k
	for l in _lights:
		l.light_energy = SPILL * k


func tube_count() -> int:
	return _tubes


func jump_count() -> int:
	return _jumps


func bounds() -> AABB:
	return _aabb


## Camera distance that fits the sign's bounding sphere (the design's fit).
func fit_distance(fov_deg: float, aspect: float) -> float:
	var r := _aabb.size.length() / 2.0
	var f := tan(deg_to_rad(fov_deg) / 2.0)
	return r * 1.08 / minf(f, f * aspect)


# ---- geometry ---------------------------------------------------------------------


## A stroke's points with rounded corners (the design's roundedPath), in sign units.
static func rounded(pts: Array, r: float) -> PackedVector2Array:
	var p: Array[Vector2] = []
	for q in pts:
		p.push_back(Vector2(float(q[0]), float(q[1])))
	var out := PackedVector2Array()
	var prev := p[0]
	out.push_back(prev)
	for i in range(1, p.size() - 1):
		var a := p[i - 1]
		var b := p[i]
		var c := p[i + 1]
		var ab := a - b
		var cb := c - b
		var rev := ab.normalized().dot(cb.normalized()) > 0.99
		var rr := 0.0 if rev else minf(r, minf(ab.length() / 2.0, cb.length() / 2.0))
		if rr <= 0.0:
			out.push_back(b)
			prev = b
			continue
		var s := b + ab.normalized() * rr
		var e := b + cb.normalized() * rr
		out.push_back(s)
		for k in range(1, 7):
			var u := k / 7.0
			out.push_back(s.lerp(b, u).lerp(b.lerp(e, u), u))
		out.push_back(e)
		prev = e
	out.push_back(p[p.size() - 1])
	return out


## Resample a 3D polyline at ~SAMPLE spacing.
static func spaced(pts: PackedVector3Array, spacing := SAMPLE) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / spacing)))
		for k in n:
			out.push_back(a.lerp(b, float(k) / n))
	out.push_back(pts[pts.size() - 1])
	return out


## A 3D polyline with small rounded bends (the design's bent()).
static func bent(pts: Array, r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var prev: Vector3 = pts[0]
	out.push_back(prev)
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var rr := minf(r, minf((a - b).length() / 2.0, (c - b).length() / 2.0))
		var s := b + (a - b).normalized() * rr
		var e := b + (c - b).normalized() * rr
		out.push_back(s)
		for k in range(1, 5):
			var u := k / 5.0
			out.push_back(s.lerp(b, u).lerp(b.lerp(e, u), u))
		out.push_back(e)
	out.push_back(pts[pts.size() - 1])
	return out


## A tube of `radius` along `path` (open ends), one mesh.
static func tube_mesh(path: PackedVector3Array, radius: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := path.size()
	# Parallel-transport frames so the rings never twist through a bend.
	var tangent := (path[1] - path[0]).normalized()
	var normal := tangent.cross(Vector3.UP)
	if normal.length() < 1e-3:
		normal = tangent.cross(Vector3.RIGHT)
	normal = normal.normalized()
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for i in n:
		var t := tangent
		if i < n - 1:
			t = (path[i + 1] - path[maxi(0, i - 1)]).normalized()
		else:
			t = (path[i] - path[i - 1]).normalized()
		# Rotate the normal with the tangent (minimal rotation).
		var axis := tangent.cross(t)
		if axis.length() > 1e-5:
			normal = normal.rotated(axis.normalized(), tangent.angle_to(t))
		normal = (normal - t * normal.dot(t)).normalized()
		tangent = t
		var binormal := t.cross(normal)
		var ring := PackedVector3Array()
		var rn := PackedVector3Array()
		for k in sides:
			var a := TAU * k / sides
			var nrm := normal * cos(a) + binormal * sin(a)
			ring.push_back(path[i] + nrm * radius)
			rn.push_back(nrm)
		rings.push_back(ring)
		ring_normals.push_back(rn)
	for i in n - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var a := rings[i][k]
			var b := rings[i][k2]
			var c := rings[i + 1][k2]
			var d := rings[i + 1][k]
			st.set_normal(ring_normals[i][k]); st.add_vertex(a)
			st.set_normal(ring_normals[i + 1][k]); st.add_vertex(d)
			st.set_normal(ring_normals[i + 1][k2]); st.add_vertex(c)
			st.set_normal(ring_normals[i][k]); st.add_vertex(a)
			st.set_normal(ring_normals[i + 1][k2]); st.add_vertex(c)
			st.set_normal(ring_normals[i][k2]); st.add_vertex(b)
	return st.commit()


func _add_tube(path: PackedVector3Array, radius: float, sides: int, mat: Material, label: String, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = tube_mesh(path, radius, sides)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _grow(p: Vector3) -> void:
	if _aabb.size == Vector3.ZERO and _aabb.position == Vector3.ZERO:
		_aabb = AABB(p, Vector3.ZERO)
	else:
		_aabb = _aabb.expand(p)


## Lay the three words out and build every tube, jump, electrode and the chain.
func build() -> void:
	# The painted-out jumps and electrodes: on the splash's black they should
	# all but vanish, so they take no light (the design lit them on a dark board).
	var blockout := StandardMaterial3D.new()
	blockout.albedo_color = BLOCKOUT
	blockout.roughness = 0.6
	blockout.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var metal := StandardMaterial3D.new()
	metal.albedo_color = STEEL
	metal.metallic = 0.35
	metal.roughness = 0.35
	var tubes := Node3D.new()
	tubes.name = "Tubes"
	add_child(tubes)
	var glow := Node3D.new()
	glow.name = "Halos"
	add_child(glow)
	var dark := Node3D.new()
	dark.name = "Jumps"
	add_child(dark)
	var row_w: Array[float] = []
	for w in ROWS:
		row_w.push_back((w.length() * ADV - (ADV - W)) * S)
	var total_h := (ROWS.size() - 1) * ROWH * S + S
	var x0: float = -float(row_w.max()) / 2.0
	var ends: Array[Vector3] = []
	var last := Vector3.ZERO
	for ri in ROWS.size():
		var word: String = ROWS[ri]
		var y0 := total_h / 2.0 - S - ri * ROWH * S
		var prev_exit := Vector3.INF
		for ci in word.length():
			var lx: float = x0 + ci * ADV * S
			for si in LETTERS[word[ci]].size():
				var stroke: Dictionary = LETTERS[word[ci]][si]
				var pts2 := rounded(stroke["p"], float(stroke["r"]))
				var pts := PackedVector3Array()
				for q in pts2:
					pts.push_back(Vector3(lx + q.x * S, y0 + q.y * S, 0.0))
				if prev_exit != Vector3.INF and pts[pts.size() - 1].distance_to(prev_exit) < pts[0].distance_to(prev_exit):
					pts.reverse()
				pts = spaced(pts)
				var label := "%s_%d_%s%d" % [word, ci, word[ci], si]
				if prev_exit == Vector3.INF:
					ends.push_back(pts[0])
				else:
					var jump := spaced(bent([prev_exit, Vector3(prev_exit.x, prev_exit.y, ZB), Vector3(pts[0].x, pts[0].y, ZB), pts[0]], ER))
					_add_tube(jump, TR, 14, blockout, "blockout_jump_" + label, dark)
					_jumps += 1
				_add_tube(pts, TR, 16, _glass, "tube_" + label, tubes)
				_add_tube(pts, TR * 0.48, 10, _core, "core_" + label, tubes)
				_add_tube(pts, TR * 1.9, 12, _halo, "halo_" + label, glow)
				_add_tube(pts, TR * 4.5, 12, _halo_wide, "halo_wide_" + label, glow)
				_tubes += 1
				for q in pts:
					_grow(q)
				prev_exit = pts[pts.size() - 1]
		ends.push_back(prev_exit)
		last = prev_exit
	for ei in ends.size():
		var p: Vector3 = ends[ei]
		var back := MeshInstance3D.new()
		back.name = "electrode_%d" % ei
		var cyl := CylinderMesh.new()
		cyl.top_radius = TR
		cyl.bottom_radius = TR
		cyl.height = 0.04
		cyl.radial_segments = 12
		back.mesh = cyl
		back.material_override = blockout
		back.rotation.x = PI / 2.0
		back.position = Vector3(p.x, p.y, ZB - 0.0)
		add_child(back)
		var cap := MeshInstance3D.new()
		cap.name = "electrode_cap_%d" % ei
		var sph := SphereMesh.new()
		sph.radius = TR * 1.3
		sph.height = TR * 2.6
		cap.mesh = sph
		cap.material_override = blockout
		cap.position = Vector3(p.x, p.y, ZB - 0.02)
		add_child(cap)
	# The pull chain under the last E.
	_chain = Node3D.new()
	_chain.name = "PullChain"
	for i in CHAIN_BEADS:
		var b := MeshInstance3D.new()
		b.name = "chain_bead"
		var sph := SphereMesh.new()
		sph.radius = 0.0045
		sph.height = 0.009
		sph.radial_segments = 12
		sph.rings = 6
		b.mesh = sph
		b.material_override = metal
		b.position = Vector3(last.x, last.y - 0.012 - i * 0.011, ZB)
		_chain.add_child(b)
	var pull := MeshInstance3D.new()
	pull.name = "chain_pull"
	var pc := CylinderMesh.new()
	pc.top_radius = 0.008
	pc.bottom_radius = 0.011
	pc.height = 0.04
	pc.radial_segments = 24
	pull.mesh = pc
	pull.material_override = metal
	var pull_y := last.y - 0.012 - CHAIN_BEADS * 0.011 - 0.02
	pull.position = Vector3(last.x, pull_y, ZB)
	_chain.add_child(pull)
	add_child(_chain)
	_chain_y = 0.0
	_grow(Vector3(last.x, pull_y - 0.02 - CHAIN_DROP, ZB))
	# Orange spill onto whatever hangs behind the sign.
	for i in 3:
		var at: Vector2 = [Vector2(-0.25, 0.2), Vector2(0.25, -0.05), Vector2(0.0, -0.3)][i]
		var l := OmniLight3D.new()
		l.name = "neon_spill_%d" % i
		l.light_color = ON_GLASS
		l.light_energy = 0.0
		l.omni_range = 1.2
		l.omni_attenuation = 2.0
		l.position = Vector3(at.x, at.y, 0.08)
		add_child(l)
		_lights.push_back(l)
