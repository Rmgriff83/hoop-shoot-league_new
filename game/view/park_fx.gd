class_name ParkFx
extends Node
## Presentation-only park dressing (docs/HOME.md → Adding an area, Ross's
## "Park Area Concept" 2026-10-15): the PSX pack's trees and litter
## instanced from data/park_layout.json (one MultiMeshInstance3D per model
## surface — 35 trees in a couple of dozen draws, leaves alpha-cut, only the
## trees casting shadows), three parked cars from the vehicle pool with a
## snow cap each, the falling snow (one points mesh under park_snow.gdshader,
## every flake's motion in the vertex shader, the box following the camera)
## and the sky: the design's sky shader (a line-for-line port of the
## concept's SkyDome, handed off 2026-10-16 — gradient, sun glow, two layers
## of pixel-stepped fbm clouds drifting about one cell per 80 s) as the
## court Environment's Sky, its clock driven from here so it never jumps at
## TIME's rollover; the glb's `Sky` dome is hidden under it. Never touches
## the sim. Seeded: a QA screenshot or a test replays identically.

const TREES_DIR := "res://assets/arena/park/trees/%s.glb"
const VEHICLE := "res://assets/vehicles/%s.glb"
const SNOW_SHADER := preload("res://game/court/park_snow.gdshader")
const SKY_SHADER := preload("res://game/court/park_sky.gdshader")
## The concept's sun, normalize(-14, 11, -12); the clouds' clock starts here
## so every load sees the same sky (the concept starts at page-load time).
const SUN_DIR := Vector3(-0.65204, 0.51232, -0.55890)
const CLOUD_T0 := 137.0
const SNOW_BOX := Vector3(14.0, 9.0, 14.0)
const SNOW_CAP := 800
const ASPEN_TINT := Color("#9A7650")
const CAR_SCALE := 0.8
const RNG_SEED := 0x9A7C_5E0F

var _rng := RandomNumberGenerator.new()
var _root: Node3D
var _multis: Array[MultiMeshInstance3D] = []
var _instances := 0
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


## One multimesh per (model, surface): every placement of that model in one draw.
func _build_trees(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ParkFx: no layout at %s" % path)
		return
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (doc is Dictionary) or not doc.has("rows"):
		return
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
		var parts := _model_parts(str(m))
		for part in parts:
			var mesh: Mesh = part["mesh"]
			var local: Transform3D = part["xform"]
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d" % [m, part["index"]]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = rows.size()
			for i in rows.size():
				mm.set_instance_transform(i, _placement(rows[i]) * local)
			mmi.multimesh = mm
			var is_tree := str(m).find("tree_0") >= 0 and str(m).find("stump") < 0 and str(m).find("fallen") < 0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if is_tree else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(mmi)
			_multis.push_back(mmi)
		_instances += rows.size()


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
func _build_sky(arena: Node, _set: ArenaSet) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter("sun_dir", SUN_DIR)
	_sky_mat.set_shader_parameter("cloud_time", _cloud_t)
	_sky = Sky.new()
	_sky.sky_material = _sky_mat
	_sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	_sky.radiance_size = Sky.RADIANCE_SIZE_256
	var dome := arena.find_child("Sky", true, false) as MeshInstance3D
	if dome != null:
		dome.visible = false


## The Sky the court's Environment shows (null when the area has no sky).
func sky_resource() -> Sky:
	return _sky


# ---- per frame ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	if _sky_mat != null:
		_cloud_t += delta
		_sky_mat.set_shader_parameter("cloud_time", _cloud_t)
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


func car_count() -> int:
	return _cars.size()


func snow_count() -> int:
	return _snow_count


func has_sky() -> bool:
	return _sky_mat != null
