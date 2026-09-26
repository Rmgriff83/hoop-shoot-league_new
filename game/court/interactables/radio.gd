class_name RadioInteractable
extends Interactable
## The beach boombox: a tap cycles the playlist. Off → the first track (the
## title loop) → the rest in a random order drawn once per visit → off. Only
## the boombox's little LED shows the state (glows while a track plays) plus
## a quick nudge on the tap. Music plays on Sfx's track channel, beside the
## area's ambience.

var tracks: PackedStringArray = PackedStringArray()
var gain_db := -14.0
var _order: Array[int] = []   # play order after the first track
var _step := -1               # -1 off, 0 first track, 1.. into _order
var _led_mat: StandardMaterial3D
var _nudge: Tween
var _rng := RandomNumberGenerator.new()


func _after_setup() -> void:
	tracks = PackedStringArray(params.get("tracks", []))
	gain_db = float(params.get("gain_db", -14.0))
	if params.has("seed"):
		_rng.seed = int(params["seed"])
	else:
		_rng.randomize()
	_draw_order()
	var led := find_part(str(params.get("led", "BoomboxLed")))
	if led is MeshInstance3D and (led as MeshInstance3D).mesh != null and (led as MeshInstance3D).mesh.get_surface_count() > 0:
		var src := (led as MeshInstance3D).mesh.surface_get_material(0)
		if src is StandardMaterial3D:
			_led_mat = (src as StandardMaterial3D).duplicate()
			_led_mat.emission_enabled = true
			_led_mat.emission = Color(1.0, 0.25, 0.15)
			_led_mat.emission_energy_multiplier = 0.0
			(led as MeshInstance3D).material_override = _led_mat


func _draw_order() -> void:
	_order.clear()
	for i in range(1, tracks.size()):
		_order.push_back(i)
	for i in range(_order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _order[i]
		_order[i] = _order[j]
		_order[j] = tmp


## Index into `tracks` of what is playing, or -1 when off.
func current() -> int:
	if _step < 0 or tracks.is_empty():
		return -1
	if _step == 0:
		return 0
	return _order[_step - 1]


func is_on() -> bool:
	return current() >= 0


func on_tap(_court: Node) -> void:
	if tracks.is_empty():
		return
	_step += 1
	if _step > _order.size():
		_step = -1
		_draw_order()   # a fresh shuffle for the next lap
	_apply()
	_bump()


## Off: one "tap" hint. Playing: "next" plus a small "off".
func icons() -> Array:
	if is_on():
		return [{"id": "next"}, {"id": "off"}]
	return [{"id": "tap"}]


func on_icon(id: String, court: Node) -> void:
	if id == "off":
		_step = -1
		_draw_order()
		_apply()
		_bump()
	else:
		on_tap(court)


func on_leave() -> void:
	_step = -1
	_apply()


func _apply() -> void:
	var sfx = _sfx()
	var i := current()
	if i < 0:
		if sfx != null:
			sfx.stop_track()
	elif sfx != null:
		sfx.play_track("radio%d" % i, tracks[i], gain_db)
	if _led_mat != null:
		_led_mat.emission_energy_multiplier = 6.0 if i >= 0 else 0.0


func _bump() -> void:
	if target == null or not target.is_inside_tree():
		return
	if _nudge != null:
		_nudge.kill()
	var base := Vector3.ONE
	target.scale = base * 0.94
	_nudge = target.create_tween()
	_nudge.tween_property(target, "scale", base, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _sfx() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("Sfx")


func label() -> String:
	return "radio"
