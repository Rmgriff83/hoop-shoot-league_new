class_name PeggyWarm
extends Node
## PEGGY's cabinet draws in its own 2x-MSAA, transparent, shadowless world,
## so none of its dozen material variants share a pipeline with the courts.
## On a fresh install (an empty shader cache) its first visit froze while
## they compiled. This draws one machine, posed to show every variant
## (`PeggyMachine.warm_pose`) and invisible (alpha 0), for a few frames under
## the first LoadingScreen of a launch, then writes a marker so later
## launches skip it. The marker lives in user://warm, outside the save and
## never synced: a reinstall wipes it along with the shader cache.
## SceneLoader runs it (docs/PERFORMANCE.md rule 8, docs/LOCKER.md).

const DIR := "user://warm"
## Bump when the cabinet's materials change, so every phone warms again.
const VERSION := 1
const FRAMES := 3
const SIZE := Vector2(288, 500)

var done := false
var _machine: PeggyMachine
var _frames := -1


## Whether this launch should warm PEGGY: no marker for this engine and
## cabinet, and a GPU to compile on.
static func needed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not FileAccess.file_exists(marker_path())


static func marker_path() -> String:
	var v := Engine.get_version_info()
	return DIR.path_join("peggy_%d.%d.%d_v%d.done" % [int(v["major"]), int(v["minor"]), int(v["patch"]), VERSION])


func _ready() -> void:
	name = "PeggyWarm"
	if ResourceLoader.load_threaded_request(PeggyMachine.GLB, "", true) != OK:
		_build(load(PeggyMachine.GLB))


func _process(_dt: float) -> void:
	if done:
		return
	if _machine == null:
		var st := ResourceLoader.load_threaded_get_status(PeggyMachine.GLB)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		_build(ResourceLoader.load_threaded_get(PeggyMachine.GLB) if st == ResourceLoader.THREAD_LOAD_LOADED else load(PeggyMachine.GLB))
		return
	_frames -= 1
	if _frames <= 0:
		_finish()


func _build(scene: PackedScene) -> void:
	PeggyMachine.keep_scene(scene)
	if scene == null:
		_finish()
		return
	_machine = PeggyMachine.new()   # attaches the kept scene at once
	_machine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_machine.modulate.a = 0.0   # drawn into its viewport, never onto the screen
	_machine.size = SIZE
	add_child(_machine)
	_machine.warm_pose()
	_frames = FRAMES


func _finish() -> void:
	done = true
	if _machine != null:
		_machine.queue_free()
		_machine = null
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(marker_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(Time.get_datetime_string_from_system())
		f.close()
