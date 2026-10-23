class_name RimMagnet
extends Node3D
## The Magnet card over the rim (design "Magnet Card FX" 38b, 2026-10-23):
## a chunky red horseshoe that pops up over the player's rim with a springy
## bounce, bobs, and throws short stepped zaps from its silver tips down to
## the front of the rim. When ShotSim grabs a near miss (`magnet_pull`), a
## forked bolt locks onto the ball from the nearest tip, with a spark burst
## on the ball, until the ball is released into the ring. SPENT pops it back
## down in four steps; ICED turns it pale blue and it drops away. Parented
## under the rim pivot so it rides the moving board. Presentation only — the
## sim decides everything (core/physics/shot_sim.gd).
##
## Built from primitives at runtime (no .glb): flat-shaded faces with 16×16
## pixel textures (dithered shadow rows, a highlight row, wear specks), the
## same low-poly look as the rest of the court. 1 body mesh (3 surfaces),
## 2 ImmediateMeshes (idle zaps, the bolt) and 1 MultiMesh (sparks): ≤ 6
## draws, no lights, no shadows.

const GOLD := Color("#F0B84A")
const CREAM := Color("#FFF3D0")
const INK := Color("#221C18")
const ICE_RED := Color("#B8D8F0")
const ICE_SILVER := Color("#DDEEF8")
const RED_T := ["#D0443A", "#9A2E24", "#F07A62", "#B8421F"]
const SILVER_T := ["#C9D0CC", "#8E9894", "#FFFFFF", "#A8B4B0"]

const TR := 0.055          # the bar's half-thickness (×1.2 for the arc and legs)
const R0 := 0.17           # the arc's radius: the legs hang at z = ±R0
const LEG := 0.11
const TIP := 0.075
const BAND := 0.016
const HOVER_Y := 0.52      # the magnet's centre above the rim plane
const BACK_X := -0.03      # …and a hair toward the shooter
const RIM_R := 0.23        # where the idle zaps land on the ring
const POP := [0.0, 0.45, 0.9, 1.18, 1.06, 0.97, 1.0]
const SPENT := [1.1, 0.8, 0.5, 0.2, 0.0]
const STEP_S := 0.06
const ICED_FALL_S := 0.55
const BOB_PERIOD_S := 0.26
const ZAP_FPS := 12.0
const BOLT_FPS := 20.0
const NZ := 7              # idle zap segments
const NB := 9              # bolt segments
const NS := 6              # spark rays
const VIEW := Vector3(1.0, 0.0, 0.0)   # the shooter looks down +x: ribbons face them

var _state := "off"        # off | up | on | end
var _t := 0.0              # the state clock
var _clock := 0.0
var _iced := false
var _scale := 0.0
var _body: MeshInstance3D
var _red: StandardMaterial3D
var _silver: StandardMaterial3D
var _zaps: MeshInstance3D
var _zap_mesh: ImmediateMesh
var _bolt: MeshInstance3D
var _bolt_mesh: ImmediateMesh
var _sparks: MultiMeshInstance3D
var _gold_mat: StandardMaterial3D
var _cream_mat: StandardMaterial3D
var _bolt_gold: StandardMaterial3D
var _bolt_cream: StandardMaterial3D
var _target: Variant = null          # the pulled ball, in local space, or null
var _pull_t := -1.0
var _zap_step := -1
var _jit: Array = []                 # [2][NZ + 1] of Vector2 (y, z)
var _rim_a: Array = [PI, PI]
var _bolt_step := -1
var _bolt_j: Array = []              # [NB + 1] of Vector3
var _fork_j: Array = []
var _rim_local := Vector3(-BACK_X, -HOVER_Y, 0.0)


func _ready() -> void:
	_red = _pixel_material(RED_T, 4.0)
	_silver = _pixel_material(SILVER_T, 1.0)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = INK
	ink.roughness = 0.9
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body = MeshInstance3D.new()
	_body.name = "Horseshoe"
	_body.mesh = _build_body(ink)
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.visible = false
	add_child(_body)
	_gold_mat = _flat(GOLD, false, 0)
	_cream_mat = _flat(CREAM, false, 1)
	_bolt_gold = _flat(GOLD, true, 5)
	_bolt_cream = _flat(CREAM, true, 6)
	_zap_mesh = ImmediateMesh.new()
	_zaps = _immediate("Zaps", _zap_mesh)
	_bolt_mesh = ImmediateMesh.new()
	_bolt = _immediate("Bolt", _bolt_mesh)
	_sparks = MultiMeshInstance3D.new()
	_sparks.name = "Sparks"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var ray := BoxMesh.new()
	ray.size = Vector3(0.012, 0.07, 0.012)
	mm.mesh = ray
	mm.instance_count = NS
	for i in NS:
		mm.set_instance_color(i, CREAM if i % 2 == 1 else GOLD)
		mm.set_instance_transform(i, Transform3D())
	_sparks.multimesh = mm
	var sm := _flat(Color.WHITE, true, 7)
	sm.vertex_color_use_as_albedo = true
	_sparks.material_override = sm
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.visible = false
	add_child(_sparks)
	for i in 2:
		var row := []
		for k in NZ + 1:
			row.push_back(Vector2.ZERO)
		_jit.push_back(row)
	for k in NB + 1:
		_bolt_j.push_back(Vector3.ZERO)
		_fork_j.push_back(Vector3.ZERO)


# ---- the card's life ---------------------------------------------------------------

## The card is played: pop up with the spring.
func pop() -> void:
	_state = "up"
	_t = 0.0
	_iced = false
	_red.albedo_color = Color.WHITE
	_silver.albedo_color = Color.WHITE
	_body.visible = true
	_scale = 0.0


## The window closed: SPENT pops it down, ICED tints it and drops it.
func end(iced: bool) -> void:
	if _state == "off" or _state == "end":
		return
	_state = "end"
	_t = 0.0
	_iced = iced
	if iced:
		_red.albedo_color = ICE_RED
		_silver.albedo_color = ICE_SILVER
	_target = null
	_pull_t = -1.0


func is_up() -> bool:
	return _state == "up" or _state == "on"


func state() -> String:
	return _state


## The sim's pulled ball (global position) each frame, or null when none.
func follow(target: Variant) -> void:
	if target == null or _state == "off":
		if _target != null:
			_pull_t = -1.0
		_target = null
		return
	var g: Vector3 = target
	_target = to_local(g)
	if _pull_t < 0.0:
		_pull_t = 0.0


func pulling() -> bool:
	return _target != null


func _process(dt: float) -> void:
	_clock += dt
	_t += dt
	if _state == "off":
		return
	var y := 0.0
	var sc := 1.0
	match _state:
		"up":
			var i := mini(POP.size() - 1, int(floor(_t / STEP_S)))
			sc = float(POP[i])
			if i == POP.size() - 1:
				_state = "on"
				_t = 0.0
		"on":
			y = 0.018 * round(sin(_clock / BOB_PERIOD_S) * 2.0) / 2.0
			if _target != null:
				_pull_t += dt
		"end":
			if _iced:
				y = -2.2 * _t * _t
				if _t > ICED_FALL_S:
					_state = "off"
			else:
				var i := mini(SPENT.size() - 1, int(floor(_t / STEP_S)))
				sc = float(SPENT[i])
				if i == SPENT.size() - 1:
					_state = "off"
	if _state == "off":
		_body.visible = false
		_zaps.visible = false
		_bolt.visible = false
		_sparks.visible = false
		_target = null
		return
	_scale = maxf(0.001, sc)
	_body.scale = Vector3.ONE * _scale
	_body.position = Vector3(0.0, y, 0.0)
	# The pull bolt and sparks, while a ball is being dragged in.
	var step := int(floor(_clock * ZAP_FPS))
	if _target != null and _state == "on":
		_draw_pull(y)
	else:
		_bolt.visible = false
		_sparks.visible = false
	# The idle zaps: tips → the front of the rim (→ the ball while pulling),
	# hidden every third step, re-jagged at ZAP_FPS.
	var zap_on := _target == null and ((_state == "on" and step % 3 != 2) or (_state == "up" and sc >= 1.0))
	if step != _zap_step:
		_zap_step = step
		for J in _jit:
			for k in J.size():
				J[k] = Vector2((randf() - 0.5) * 0.09, (randf() - 0.5) * 0.09)
		_rim_a = [PI * (0.6 + randf() * 0.8), PI * (0.6 + randf() * 0.8)]
	_zaps.visible = zap_on
	if zap_on:
		_draw_zaps(y)


# ---- drawing ------------------------------------------------------------------------

func _tip(i: int, y: float) -> Vector3:
	var z := (R0 if i == 1 else -R0) * _scale
	return Vector3(0.0, y - (LEG + TIP + 0.008) * _scale, z)


func _draw_zaps(y: float) -> void:
	_zap_mesh.clear_surfaces()
	for i in 2:
		var a := _tip(i, y)
		var sgn := -1.0 if i == 1 else 1.0
		var b := _rim_local + Vector3(RIM_R * cos(_rim_a[i]), 0.0, RIM_R * sin(_rim_a[i]) * sgn)
		_ribbon(_zap_mesh, _gold_mat, a, b, _jit[i], 0.045, 1.0, 0.0)
		_ribbon(_zap_mesh, _cream_mat, a, b, _jit[i], 0.016, 1.0, -0.01)


## A zigzag ribbon from A to B: NZ segments, the jitter (y, z) scaled by a
## sine envelope, a flat quad per segment facing the shooter. `dx` offsets
## the whole ribbon toward the shooter (the cream core in front of the gold).
func _ribbon(mesh: ImmediateMesh, mat: Material, a: Vector3, b: Vector3, jit: Array, w: float, amp: float, dx: float) -> void:
	var pts: Array[Vector3] = []
	for k in NZ + 1:
		var u := float(k) / NZ
		var env := sin(PI * u)
		var j: Vector2 = jit[k]
		pts.push_back(Vector3(a.x + (b.x - a.x) * u + dx, a.y + (b.y - a.y) * u + j.x * env * amp, a.z + (b.z - a.z) * u + j.y * env * amp))
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for k in NZ:
		var p0 := pts[k]
		var p1 := pts[k + 1]
		var d := p1 - p0
		var side := d.cross(VIEW)
		if side.length_squared() < 1e-10:
			side = Vector3(0.0, 1.0, 0.0)
		side = side.normalized() * (w / 2.0)
		_quad(mesh, p0 - side, p1 - side, p1 + side, p0 + side)
	mesh.surface_end()


func _quad(mesh: ImmediateMesh, q0: Vector3, q1: Vector3, q2: Vector3, q3: Vector3) -> void:
	mesh.surface_add_vertex(q0)
	mesh.surface_add_vertex(q1)
	mesh.surface_add_vertex(q2)
	mesh.surface_add_vertex(q0)
	mesh.surface_add_vertex(q2)
	mesh.surface_add_vertex(q3)


## The pull: a forked bolt from the nearest tip to the ball, re-jagged at
## BOLT_FPS with a flicker, thicker for the first 80 ms, plus six spark rays.
func _draw_pull(y: float) -> void:
	var to: Vector3 = _target
	var st := int(floor(_clock * BOLT_FPS))
	if st != _bolt_step:
		_bolt_step = st
		for k in NB + 1:
			_bolt_j[k] = Vector3(0.0, (randf() - 0.5) * 2.0, (randf() - 0.5) * 2.0)
			_fork_j[k] = Vector3(0.0, (randf() - 0.5) * 2.0, (randf() - 0.5) * 2.0)
	var strength := 1.5 if _pull_t < 0.08 else 1.0
	var flick := 0.55 if st % 4 == 3 else 1.0
	var amp := 0.07 * strength
	var from := _tip(1 if to.z > 0.0 else 0, y)
	_bolt_mesh.clear_surfaces()
	_bolt_ribbon(_bolt_gold, from, to, _bolt_j, amp, 0.07 * strength * flick)
	_bolt_ribbon(_bolt_cream, from, to, _bolt_j, amp, 0.026 * strength * flick)
	if st % 3 != 0:
		var mid: Vector3 = from.lerp(to, 0.45) + (_bolt_j[4] as Vector3) * amp
		var f_end := to + Vector3(0.0, 0.12, 0.16 if _bolt_j[2].z > 0.0 else -0.16)
		_bolt_ribbon(_bolt_gold, mid, f_end, _fork_j, amp * 0.6, 0.035 * strength)
	_bolt.visible = true
	# Sparks on the ball.
	var mm := _sparks.multimesh
	for i in NS:
		var a := float(i) / NS * TAU + st * 0.7
		var len := (0.6 + 0.4 * float((st + i) % 2)) * strength
		var off := Vector3(0.0, cos(a), sin(a)) * (0.08 + 0.02 * len)
		var basis := Basis.from_euler(Vector3(a, 0.0, 0.0)).scaled(Vector3(1.0, len, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, to + off))
	_sparks.visible = true


## The bolt's ribbon: NB segments, the random jag scaled by a sine envelope,
## tapering toward the ball.
func _bolt_ribbon(mat: Material, a: Vector3, b: Vector3, jag: Array, amp: float, w: float) -> void:
	var d := b - a
	var side := d.cross(VIEW)
	if side.length_squared() < 1e-10:
		side = Vector3(0.0, 1.0, 0.0)
	side = side.normalized()
	var pts: Array[Vector3] = []
	for k in NB + 1:
		var u := float(k) / NB
		var env := sin(PI * u)
		pts.push_back(a + d * u + (jag[k] as Vector3) * (env * amp))
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for k in NB:
		var s0 := side * (w / 2.0 * (1.0 - 0.55 * float(k) / NB))
		var s1 := side * (w / 2.0 * (1.0 - 0.55 * float(k + 1) / NB))
		_quad(_bolt_mesh, pts[k] - s0, pts[k + 1] - s1, pts[k + 1] + s1, pts[k] + s0)
	_bolt_mesh.surface_end()


# ---- the horseshoe ------------------------------------------------------------------

## The body: a 3-segment half-ring with a square section standing in the ZY
## plane (open downward), two legs, two black bands, two silver tips.
func _build_body(ink: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var t := TR * 1.2
	# Red: the arc and the legs.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_seg := 3
	for i in n_seg:
		var q0 := float(i) / n_seg * PI
		var q1 := float(i + 1) / n_seg * PI
		var u0 := q0 / PI * 0.75
		var u1 := q1 / PI * 0.75
		var ro := R0 + t
		var ri := R0 - t
		# Outer face (radial out), inner face (radial in), front (+x), back (−x).
		_face(st, _arc_p(q0, ro, t), _arc_p(q1, ro, t), _arc_p(q1, ro, -t), _arc_p(q0, ro, -t), _radial(q0, q1), u0, u1)
		_face(st, _arc_p(q0, ri, -t), _arc_p(q1, ri, -t), _arc_p(q1, ri, t), _arc_p(q0, ri, t), -_radial(q0, q1), u0, u1)
		_face(st, _arc_p(q0, ri, t), _arc_p(q1, ri, t), _arc_p(q1, ro, t), _arc_p(q0, ro, t), Vector3(1.0, 0.0, 0.0), u0, u1)
		_face(st, _arc_p(q0, ro, -t), _arc_p(q1, ro, -t), _arc_p(q1, ri, -t), _arc_p(q0, ri, -t), Vector3(-1.0, 0.0, 0.0), u0, u1)
	for z in [-R0, R0]:
		_box(st, Vector3(0.0, -LEG / 2.0, z), Vector3(t, LEG / 2.0, t), 0.0, 1.0)
	st.commit(mesh)
	mesh.surface_set_material(0, _red)
	# Ink: the bands.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [-R0, R0]:
		_box(st, Vector3(0.0, -LEG, z), Vector3(TR * 1.32, BAND / 2.0, TR * 1.32), 0.0, 1.0)
	st.commit(mesh)
	mesh.surface_set_material(1, ink)
	# Silver: the tips.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [-R0, R0]:
		_box(st, Vector3(0.0, -LEG - TIP / 2.0 - 0.008, z), Vector3(TR * 1.25, TIP / 2.0, TR * 1.25), 0.0, 1.0)
	st.commit(mesh)
	mesh.surface_set_material(2, _silver)
	return mesh


## A point on the arc: angle q around +x, radius r in the ZY plane, offset x.
func _arc_p(q: float, r: float, x: float) -> Vector3:
	return Vector3(x, r * sin(q), r * cos(q))


func _radial(q0: float, q1: float) -> Vector3:
	var q := (q0 + q1) / 2.0
	return Vector3(0.0, sin(q), cos(q))


## One flat quad with its normal and a u range (v runs 0 → 1 across).
func _face(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, u0: float, u1: float) -> void:
	st.set_normal(n)
	st.set_uv(Vector2(u0, 0.0))
	st.add_vertex(p0)
	st.set_uv(Vector2(u1, 0.0))
	st.add_vertex(p1)
	st.set_uv(Vector2(u1, 1.0))
	st.add_vertex(p2)
	st.set_uv(Vector2(u0, 0.0))
	st.add_vertex(p0)
	st.set_uv(Vector2(u1, 1.0))
	st.add_vertex(p2)
	st.set_uv(Vector2(u0, 1.0))
	st.add_vertex(p3)


## An axis-aligned box (centre, half-size), six flat faces.
func _box(st: SurfaceTool, c: Vector3, h: Vector3, u0: float, u1: float) -> void:
	var x0 := c.x - h.x
	var x1 := c.x + h.x
	var y0 := c.y - h.y
	var y1 := c.y + h.y
	var z0 := c.z - h.z
	var z1 := c.z + h.z
	_face(st, Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(1, 0, 0), u0, u1)
	_face(st, Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(-1, 0, 0), u0, u1)
	_face(st, Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, 0, 1), u0, u1)
	_face(st, Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(0, 0, -1), u0, u1)
	_face(st, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 1, 0), u0, u1)
	_face(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(0, -1, 0), u0, u1)


# ---- materials ----------------------------------------------------------------------

## A 16×16 pixel texture: base, dithered shadow rows at the bottom, a
## highlight row near the top, wear specks — nearest-filtered, tiled.
func _pixel_material(cols: Array, repeat_u: float) -> StandardMaterial3D:
	var base := Color(cols[0])
	var dark := Color(cols[1])
	var lite := Color(cols[2])
	var spec := Color(cols[3])
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var c := base
			if y >= 10 and (x + y) % 2 == 0:
				c = dark
			elif y == 3 or (y == 4 and x % 2 == 0):
				c = lite
			elif (x * 5 + y * 3) % 17 == 0:
				c = spec
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.uv1_scale = Vector3(repeat_u, 1.0, 1.0)
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _flat(col: Color, over_everything: bool, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = over_everything
	m.render_priority = priority
	return m


func _immediate(name_: String, mesh: ImmediateMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0   # never frustum-culled: the ribbons move every frame
	mi.visible = false
	add_child(mi)
	return mi
