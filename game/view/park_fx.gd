class_name ParkFx
extends Node
## Presentation-only park dressing (docs/HOME.md → Adding an area, Ross's
## "Park Area Concept" 2026-10-15): the PSX pack's trees and litter
## instanced from data/park_layout.json (one MultiMeshInstance3D per model
## surface — 35 trees in a couple of dozen draws, leaves alpha-cut, only the
## trees casting shadows; a third of them, the ones in view from the key,
## sway a few centimetres under park_tree_sway.gdshader — Ross, 2026-10-26),
## three parked cars from the vehicle pool with a
## snow cap each, the falling snow (one points mesh under park_snow.gdshader,
## every flake's motion in the vertex shader, the box following the camera)
## and the sky: the design's sky shader (a line-for-line port of the
## concept's SkyDome, handed off 2026-10-16 — gradient, sun glow, two layers
## of pixel-stepped fbm clouds drifting about one cell per 80 s) as the
## court Environment's Sky, its clock the shader's own TIME plus a phase set
## once (a per-frame uniform write re-rendered the sky's radiance cubemap
## every frame, 2026-10-16; the rollover is pushed out to days in
## project.godot); the glb's `Sky` dome is hidden under it. Never touches
## the sim. Seeded: a QA screenshot or a test replays identically.

const TREES_DIR := "res://assets/arena/park/trees/%s.glb"
const VEHICLE := "res://assets/vehicles/%s.glb"
const SNOW_SHADER := preload("res://game/court/park_snow.gdshader")
const SWAY_SHADER := preload("res://game/court/park_tree_sway.gdshader")
## The sky is AreaSky's (shared with the city since 2026-10-16); the
## palette and the sun are the ArenaSet's sky_* exports.
const CLOUD_T0 := AreaSky.CLOUD_T0
const SNOW_BOX := Vector3(14.0, 9.0, 14.0)
const SNOW_CAP := 800
const ASPEN_TINT := Color("#9A7650")
const CAR_SCALE := 0.8
const RNG_SEED := 0x9A7C_5E0F
## Trees within this of the hoop cast shadows (the big aspen and the pine
## by the slab: two); the rest draw unshadowed, which
## halves the shadow pass (2026-10-16, the park running lighter).
const SHADOW_R := 16.0
const HOOP_XZ := Vector2(3.7, 0.0)
## The swaying trees (Ross, 2026-10-26: "a very slight sway, a third of the
## trees, the ones you'd see shooting from the key"): the camera stands
## KEY_CAM_XZ looking down +x at the hoop; the trees within SWAY_HALF_DEG of
## that line, nearest the line first, up to SWAY_SHARE of the trees, run the
## sway shader (its own multimesh draws; no script per frame).
const KEY_CAM_XZ := Vector2(-0.3, 0.0)
const SWAY_HALF_DEG := 20.0
const SWAY_SHARE := 1.0 / 3.0

var _rng := RandomNumberGenerator.new()
var _root: Node3D
var _multis: Array[MultiMeshInstance3D] = []
var _instances := 0
var _casters := 0
var _swayers := 0
var _sway_meshes := {}   # mesh → its copy under the sway shader
var _cars: Array[Node3D] = []
var _snow: MeshInstance3D
var _snow_mat: ShaderMaterial
var _snow_count := 0
var _sky_mat: ShaderMaterial
var _sky: Sky
var _cloud_t := CLOUD_T0
var _cam: Camera3D


## Bind the park glb and dress it from the ArenaSet. False when there is
## nothing to add (no layout, no snow, no cars, no sky).
func setup(arena: Node, set: ArenaSet) -> bool:
	if set == null:
		return false
	var any := set.snow or set.tree_layout != "" or not set.parked_cars.is_empty() or set.sky != ""
	if not any:
		return false
	_rng.seed = RNG_SEED
	_root = Node3D.new()
	_root.name = "ParkDressing"
	arena.add_child(_root)
	if set.tree_layout != "":
		_build_trees(set.tree_layout)
	for car in set.parked_cars:
		_build_car(car)
	if set.snow:
		_build_snow(mini(int(set.snow_amount), SNOW_CAP))
	if set.sky != "":
		_build_sky(arena, set)
	return true


# ---- the trees and the litter ---------------------------------------------------------


## One multimesh per (model, surface, near|far, sway|still): every placement
## of that model in one draw, the near trees (within SHADOW_R of the hoop)
## casting shadows and the far ones not, the swaying trees on the sway
## shader's copy of the mesh.
func _build_trees(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ParkFx: no layout at %s" % path)
		return
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (doc is Dictionary) or not doc.has("rows"):
		return
	# --qa-perf-ab=no_sway (docs/PERFORMANCE.md): every tree still, for the A/B.
	var swaying := sway_rows(doc["rows"]) if not CourtGeometry.ab.has("no_sway") else []
	_swayers = swaying.size()
	var by_model := {}
	for row in doc["rows"]:
		var m := str(row.get("model", ""))
		if not by_model.has(m):
			by_model[m] = []
		by_model[m].push_back(row)
	var models: Array = by_model.keys()
	models.sort()
	for m in models:
		var rows: Array = by_model[m]
		var is_tree := is_tree_model(str(m))
		var groups := {"near": [], "far": [], "near_sway": [], "far_sway": []}
		for row in rows:
			var d := Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0))).distance_to(HOOP_XZ)
			var key := "near" if is_tree and d <= SHADOW_R else "far"
			if swaying.has(row):
				key += "_sway"
			groups[key].push_back(row)
		_casters += groups["near"].size() + groups["near_sway"].size()
		var parts := _model_parts(str(m))
		for part in parts:
			var mesh: Mesh = part["mesh"]
			var local: Transform3D = part["xform"]
			for key in ["near", "far", "near_sway", "far_sway"]:
				var grows: Array = groups[key]
				if grows.is_empty():
					continue
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%s_%d_%s" % [m, part["index"], key]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = _sway_mesh(mesh) if key.ends_with("_sway") else mesh
				mm.instance_count = grows.size()
				for i in grows.size():
					mm.set_instance_transform(i, _placement(grows[i]) * local)
				mmi.multimesh = mm
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key.begins_with("near") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_root.add_child(mmi)
				_multis.push_back(mmi)
		_instances += rows.size()


static func is_tree_model(m: String) -> bool:
	return m.find("tree_0") >= 0 and m.find("stump") < 0 and m.find("fallen") < 0


## The layout rows that sway: the trees inside the key camera's view cone
## (within SWAY_HALF_DEG of the line to the hoop, ahead of the camera),
## nearest the line first, capped at SWAY_SHARE of the trees. Deterministic
## from the layout; the rows come back by reference.
static func sway_rows(rows: Array) -> Array:
	var trees := 0
	var cone: Array = []
	for row in rows:
		if not is_tree_model(str(row.get("model", ""))):
			continue
		trees += 1
		var rel := Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0))) - KEY_CAM_XZ
		if rel.x <= 0.0:
			continue
		var off := absf(rad_to_deg(atan2(rel.y, rel.x)))
		if off <= SWAY_HALF_DEG:
			cone.push_back([off, row])
	cone.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	var cap := ceili(trees * SWAY_SHARE)
	for i in mini(cone.size(), cap):
		out.push_back(cone[i][1])
	return out


## The mesh again with every surface's conformed StandardMaterial swapped
## for the sway shader carrying the same texture, tint and alpha cut.
func _sway_mesh(mesh: Mesh) -> Mesh:
	if _sway_meshes.has(mesh):
		return _sway_meshes[mesh]
	var copy: Mesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var bm := copy.surface_get_material(s) as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = SWAY_SHADER
		if bm != null:
			sm.set_shader_parameter("albedo", bm.albedo_texture)
			sm.set_shader_parameter("tint", bm.albedo_color)
			sm.set_shader_parameter("vertex_tint", bm.vertex_color_use_as_albedo)
			sm.set_shader_parameter("cut", bm.alpha_scissor_threshold if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.0)
		copy.surface_set_material(s, sm)
	_sway_meshes[mesh] = copy
	return copy


## A pack model's meshes with their transforms inside the glb, materials
## conformed for the phone: alpha-cut leaves, no blending, flat; the aspens'
## leaves tinted the design's winter brown.
func _model_parts(model: String) -> Array:
	var out := []
	var scene: PackedScene = load(TREES_DIR % model) if ResourceLoader.exists(TREES_DIR % model) else null
	if scene == null:
		return out
	var inst: Node = scene.instantiate()
	var index := 0
	for n in BeachFx._descendants(inst):
		if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					bm.alpha_scissor_threshold = 0.45
					bm.cull_mode = BaseMaterial3D.CULL_DISABLED
				bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				bm.roughness = 0.95
				bm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				if model.begins_with("aspen"):
					bm.albedo_color = ASPEN_TINT
		# the mesh's transform relative to the glb root
		var xf := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != inst:
			if walk is Node3D:
				xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		out.push_back({"mesh": mesh, "xform": xf, "index": index})
		index += 1
	inst.free()
	return out


static func _placement(row: Dictionary) -> Transform3D:
	var s := float(row.get("s", 1.0))
	var sy := float(row.get("sy", s))
	var basis := Basis.from_euler(Vector3(float(row.get("rx", 0.0)), float(row.get("ry", 0.0)), float(row.get("rz", 0.0))))
	basis = basis.scaled(Vector3(s, sy, s))
	return Transform3D(basis, Vector3(float(row.get("x", 0.0)), float(row.get("y", 0.0)), float(row.get("z", 0.0))))


# ---- the parked cars -------------------------------------------------------------------


func _build_car(car: Dictionary) -> void:
	var path := VEHICLE % str(car.get("model", ""))
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		return
	var inst: Node3D = scene.instantiate() as Node3D
	if inst == null:
		return
	inst.name = "Car_" + str(car.get("model", ""))
	inst.scale = Vector3.ONE * CAR_SCALE
	inst.rotation.y = float(car.get("yaw", 0.0))
	inst.position = Vector3(float(car.get("x", 0.0)), 0.0, float(car.get("z", 0.0)))
	_root.add_child(inst)
	# A snow cap on the roof: a flat slab over the car's bounds.
	var aabb := _bounds(inst)
	if aabb.size.length() > 0.1:
		var cap := MeshInstance3D.new()
		cap.name = "SnowCap"
		var box := BoxMesh.new()
		box.size = Vector3(aabb.size.x * 0.62, 0.07, aabb.size.z * 0.42)
		cap.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.93, 0.95, 0.97)
		m.roughness = 0.95
		cap.material_override = m
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.position = Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.end.y + 0.02, aabb.position.z + aabb.size.z * 0.5)
		_root.add_child(cap)
	_cars.push_back(inst)


static func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in BeachFx._descendants(n):
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var a: AABB = mi.get_aabb()
			var xf := Transform3D.IDENTITY
			var walk: Node = mi
			while walk != null and walk != n.get_parent():
				if walk is Node3D:
					xf = (walk as Node3D).transform * xf
				walk = walk.get_parent()
			var b := xf * a
			out = b if first else out.merge(b)
			first = false
	return out


# ---- the falling snow -------------------------------------------------------------------


func _build_snow(n: int) -> void:
	var seeds := PackedVector3Array()
	seeds.resize(n)
	for i in n:
		seeds[i] = Vector3(_rng.randf(), _rng.randf(), _rng.randf())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = seeds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	_snow = MeshInstance3D.new()
	_snow.name = "Snowfall"
	_snow.mesh = mesh
	_snow_mat = ShaderMaterial.new()
	_snow_mat.shader = SNOW_SHADER
	_snow_mat.set_shader_parameter("box", SNOW_BOX)
	_snow_mat.set_shader_parameter("center", Vector3(0.0, 4.0, 0.0))
	_snow.material_override = _snow_mat
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 300, 400))
	_snow.extra_cull_margin = 1000.0
	_root.add_child(_snow)
	_snow_count = n


# ---- the sky ----------------------------------------------------------------------------


## The design's sky as a Sky resource (CourtGeometry hangs it on the court's
## Environment: background Sky, fog_sky_affect 0, linear tonemap). The glb's
## dome would hide it, so it goes.
func _build_sky(arena: Node, set: ArenaSet) -> void:
	_sky = AreaSky.build(set)
	_sky_mat = _sky.sky_material as ShaderMaterial
	AreaSky.hide_dome(arena)


## The PiP's static park (CourtGeometry.Profile.PIP): the trees, the cars
## and the sky stay (the sky's clouds run on the shader's own TIME, no
## uniform is written), the snowfall goes, and nothing runs per frame.
var frozen := false   # CourtGeometry.Profile.PIP: built, then still


func freeze() -> void:
	frozen = true
	if _snow != null:
		_snow.visible = false
	set_process(false)


## The Sky the court's Environment shows (null when the area has no sky).
func sky_resource() -> Sky:
	return _sky


## Seconds the clouds have drifted since load (tests).
func clock() -> float:
	return _cloud_t


# ---- per frame ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	_cloud_t += delta   # the clouds' clock for tests; the shader keeps its own
	if _snow_mat == null:
		return
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	if _cam != null:
		_snow_mat.set_shader_parameter("center", _cam.global_position + Vector3(0.0, 2.0, 0.0))


# ---- for tests and the QA driver -----------------------------------------------------------


func instance_count() -> int:
	return _instances


func draw_count() -> int:
	return _multis.size()


## The trees that cast shadows (within SHADOW_R of the hoop).
func shadow_caster_count() -> int:
	return _casters


## The trees that sway (the key view's third).
func sway_count() -> int:
	return _swayers


func car_count() -> int:
	return _cars.size()


func snow_count() -> int:
	return _snow_count


func has_sky() -> bool:
	return _sky_mat != null
