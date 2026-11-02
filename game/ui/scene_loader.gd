class_name SceneLoader
extends Node
## Every move between scenes (design "Loading States" 39a / 39b, 2026-10-25;
## docs/HOME.md → Loading). The old way was a blocking change_scene_to_file
## and a frozen screen while the next scene's _ready loaded its arena and
## hoop models. Now a move:
##  1. puts the button under the finger in its loading state (ButtonBusy);
##  2. loads the scene AND the heavy resources it will ask for (the arena
##     model, the hoop model) on threads (ResourceLoader.load_threaded_*), so
##     the bar shows real progress and the scene's own load() calls hit the
##     cache;
##  3. raises the LoadingScreen only if that runs past 0.4 s, and keeps it up
##     at least 0.6 s so it never flashes (LoadingCopy.next_step);
##  4. changes to the packed scene under the screen, then fades the screen out.
## A child of the App autoload, so it and its screen outlive the change.

## QA passes keep the old instant moves (their fixed sleeps assume them);
## `force_show` raises the screen at once (the --qa-loading pass).
var instant := false
var force_show := false
var _path := ""
var _requests: Array = []
var _hold: Array = []
var _t := 0.0
var _screen: LoadingScreen
var _dest: Dictionary = {}
var _art := ""
var _shown_at := -1.0


func _ready() -> void:
	set_process(false)


func busy() -> bool:
	return _path != ""


func screen() -> LoadingScreen:
	return _screen


## Move to `path`. `dest` from LoadingCopy.dest (the screen's words), `art`
## the destination picture, `extras` the resources its _ready will load.
func go(path: String, dest: Dictionary, art := "", extras: Array = []) -> void:
	if busy():
		return
	if instant or not is_inside_tree():
		get_tree().change_scene_to_file(path)
		return
	_path = path
	_dest = dest
	_art = art
	_t = 0.0
	_shown_at = -1.0
	_hold.clear()
	_requests = [path]
	for e in extras:
		if str(e) != "" and ResourceLoader.exists(str(e)) and not _requests.has(str(e)):
			_requests.push_back(str(e))
	for r in _requests:
		if ResourceLoader.load_threaded_request(r, "", true) != OK:
			_requests.erase(r)
	if not _requests.has(path):
		_fallback()
		return
	_busy_button()
	if force_show:
		_show()
	set_process(true)


func _process(dt: float) -> void:
	if not busy():
		set_process(false)
		return
	_t += dt
	var total := 0.0
	var loaded := true
	for r in _requests:
		var prog: Array = []
		var st := ResourceLoader.load_threaded_get_status(r, prog)
		match st:
			ResourceLoader.THREAD_LOAD_LOADED:
				total += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				total += float(prog[0]) if not prog.is_empty() else 0.0
				loaded = false
			_:
				if r == _path:
					_fallback()
					return
				total += 1.0   # an extra that failed: the scene loads it the old way
	if _screen != null:
		_screen.set_progress(0.9 * total / float(maxi(_requests.size(), 1)))
	match LoadingCopy.next_step(_t, loaded, _screen.shown_for() if _screen != null else -1.0):
		"show":
			_show()
		"finish":
			_finish()


func _show() -> void:
	if _screen != null:
		return
	_screen = LoadingScreen.new(_dest, _art)
	add_child(_screen)


func _finish() -> void:
	set_process(false)
	var packed := ResourceLoader.load_threaded_get(_path) as PackedScene
	for r in _requests:
		if r != _path:
			_hold.push_back(ResourceLoader.load_threaded_get(r))   # cached until the scene has them
	if packed == null:
		_fallback()
		return
	get_tree().change_scene_to_packed(packed)
	var screen_ := _screen
	await get_tree().process_frame
	await get_tree().process_frame
	_hold.clear()
	_path = ""
	_screen = null
	if screen_ != null and is_instance_valid(screen_):
		screen_.finish()


func _fallback() -> void:
	set_process(false)
	var p := _path
	_path = ""
	if _screen != null:
		_screen.finish()
		_screen = null
	get_tree().change_scene_to_file(p)


## The pressed button: the control under the pointer (a tap's release) when
## it is a button on the current scene.
func _busy_button() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var c := vp.gui_get_hovered_control()
	while c != null and not (c is BaseButton):
		c = c.get_parent() as Control
	if c != null and get_tree().current_scene != null and get_tree().current_scene.is_ancestor_of(c):
		ButtonBusy.apply(c as BaseButton, str(_dest.get("busy", "")), get_tree().current_scene)
