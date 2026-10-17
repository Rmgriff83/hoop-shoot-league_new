class_name AreaSky
extends RefCounted
## The design's sky (Ross's "Park Area Concept" SkyDome, handed off
## 2026-10-16: a gradient, the sun's glow, two layers of pixel-stepped fbm
## clouds drifting about one cell per 80 s) as a Sky resource any area can
## hang on its court Environment — the park first, the city since 2026-10-16
## in its own blue and haze. The palette and the sun's direction are the
## ArenaSet's `sky_*` exports; the clouds' clock is the shader's own TIME
## plus one phase set here (a per-frame uniform write re-rendered the
## radiance cubemap every frame), the radiance map is 64 (reflections only;
## the clouds skip the cubemap pass) and renders once. The glb's painted
## `Sky` dome would hide it, so hide_dome() turns it off.

const SHADER := preload("res://game/court/park_sky.gdshader")
## Every load sees the same sky (the concept starts at page-load time).
const CLOUD_T0 := 137.0


static func build(set: ArenaSet) -> Sky:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("sun_dir", set.sky_sun_dir.normalized())
	mat.set_shader_parameter("top_color", Vector3(set.sky_top.r, set.sky_top.g, set.sky_top.b))
	mat.set_shader_parameter("mid_color", Vector3(set.sky_mid.r, set.sky_mid.g, set.sky_mid.b))
	mat.set_shader_parameter("horizon_color", Vector3(set.sky_horizon.r, set.sky_horizon.g, set.sky_horizon.b))
	mat.set_shader_parameter("cloud_time", CLOUD_T0)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	return sky


## The arena glb's painted dome (`Sky`), hidden under the shader sky.
static func hide_dome(arena: Node) -> void:
	var dome := arena.find_child("Sky", true, false) as MeshInstance3D
	if dome != null:
		dome.visible = false
