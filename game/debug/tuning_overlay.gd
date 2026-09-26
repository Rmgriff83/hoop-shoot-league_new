class_name TuningOverlay
extends CanvasLayer
## Live tuning for the flick pass. Two faces of the same tunables:
##  • Keyboard (desktop): F3 or backtick toggles a text readout; 1-9 select a
##    tunable, -/= adjust it.
##  • Touch strip (device, when App.tuning_mode is on): ◀ ▶ select, − + adjust,
##    RESET / LOG. Lives in the top UI zone above the grab line, so it never
##    intercepts a shot. RESET first stashes the current values in the save, and
##    the same button reads UNDO (across restarts) until they are put back. Every adjustment persists immediately via SaveService's
##    "tuning" part (and the live FlickTuning is App-owned, so it survives scene
##    changes); LOG prints `TUNING {json}` so values can be read from logcat.

const HISTORY := 14

var tuning: FlickTuning
var geo: SimGeometry
## Build the touch strip. Set before add_child.
var touch_panel := false

var _label: Label
var _lines: Array[String] = []
var _attempts := 0
var _makes := 0
var _selected := 0
var _last_flick := ""
var _last_outcome := ""

var _panel: Control
var _field_btn: Button
var _reset_btn: Button
var _readout: Label

## Hard rails per field: [min, max].
const LIMITS := {
	"side_dead_deg": [0.0, 12.0], "side_gain": [0.0, 1.5],
	"roll_dead": [0.0, 12.0], "roll_gain": [0.0, 1.5],
	"angle_low": [5.0, 60.0], "angle_high": [30.0, 80.0],
	"pull_full_frac": [0.05, 0.9], "dead_zone_px": [0.0, 120.0],
}

## Keys 1-9 / ◀ ▶ select these in order: [field, step].
## Optional: a "FIRE" button on the touch panel that toggles the rim's on-fire
## effect so it can be previewed without a streak (practice only; set by the screen).
var fire_toggle := Callable()
var ice_toggle := Callable()
## Optional: cycles the ball to the next cosmetic set and returns its display
## name for the button label. Set by the screen. This deliberately bypasses
## App.select(), which refuses anything the save does not own — a fresh save
## owns only "classic" — and it does not persist. It is a dev tool.
var ball_cycle := Callable()

var _ball_btn: Button

var _fields := [
	["angle_low", 1.0], ["angle_high", 1.0], ["pull_full_frac", 0.02],
	["flick_min_sh", 0.05], ["flick_max_sh", 0.1],
	["side_dead_deg", 0.5], ["side_gain", 0.05],
	["backspin_per_mps", 0.1], ["roll_gain", 0.05], ["dead_zone_px", 5.0],
]


func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)
	if touch_panel:
		_build_panel()
	_render()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# F3 or backtick: on a MacBook, bare F3 is Mission Control and never
		# reaches the game unless Fn is held, so backtick is the reliable toggle.
		if event.keycode == KEY_F3 or event.keycode == KEY_QUOTELEFT:
			_label.visible = not _label.visible
			_render()
		elif _label.visible and event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_select_index(9 if event.keycode == KEY_0 else event.keycode - KEY_1)
		elif _label.visible and event.keycode in [KEY_MINUS, KEY_EQUAL] and tuning != null:
			_adjust(-1.0 if event.keycode == KEY_MINUS else 1.0)


# ---- touch strip ---------------------------------------------------------------


func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "TouchPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_top = 76
	_panel.offset_bottom = 396   # +60 for the ball picker row
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.17, 0.26, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(bg)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12
	vb.offset_right = -12
	vb.offset_top = 10
	vb.offset_bottom = -10
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vb.add_child(row1)
	row1.add_child(_btn("◀", 84, func() -> void: _select_index(_selected - 1)))
	_field_btn = _btn("", 0, func() -> void: _select_index(_selected + 1))
	_field_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_btn.add_theme_font_size_override("font_size", 22)
	row1.add_child(_field_btn)
	row1.add_child(_btn("▶", 84, func() -> void: _select_index(_selected + 1)))
	row1.add_child(_btn("−", 84, func() -> void: _adjust(-1.0)))
	row1.add_child(_btn("+", 84, func() -> void: _adjust(1.0)))

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 18)
	_readout.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.custom_minimum_size = Vector2(0, 84)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_readout)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	vb.add_child(row3)
	var specs := [["RESET", _reset_or_undo], ["LOG", _log]]
	if fire_toggle.is_valid():
		specs.append(["FIRE", func() -> void: fire_toggle.call()])
	if ice_toggle.is_valid():
		specs.append(["ICE", func() -> void: ice_toggle.call()])
	for spec in specs:
		var b := _btn(spec[0], 0, spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 22)
		row3.add_child(b)
		if spec[0] == "RESET":
			_reset_btn = b

	# The ball picker gets its own full-width row rather than a fifth button on
	# row 3 — with FIRE and ICE up there already, a fifth at 22pt is unreadable
	# on a phone, and this one has to show a name, not a 4-letter label.
	if ball_cycle.is_valid():
		_ball_btn = _btn("BALL ▶", 0, func() -> void:
			var name_ := str(ball_cycle.call())
			if _ball_btn != null:
				_ball_btn.text = "BALL ▶  %s" % name_
		)
		_ball_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ball_btn.custom_minimum_size = Vector2(0, 52)
		_ball_btn.add_theme_font_size_override("font_size", 22)
		vb.add_child(_ball_btn)


func _btn(text: String, min_w: float, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 64)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b


func _select_index(idx: int) -> void:
	_selected = posmod(idx, _fields.size())
	_render()


func _adjust(sign: float) -> void:
	if tuning == null:
		return
	var field: String = _fields[_selected][0]
	var step: float = _fields[_selected][1]
	var value := snappedf(tuning.get(field) + sign * step, 0.001)
	# Sane rails so a run of taps can't silently disable a mechanic (a 35° dead
	# band once made every shot dead-centre).
	if LIMITS.has(field):
		value = clampf(value, LIMITS[field][0], LIMITS[field][1])
	tuning.set(field, value)
	_persist(tuning.to_dict())
	_render()


## Autoloads resolved at runtime (by node path) so this class also compiles in
## headless tool scripts, where class_name scripts load before the autoloads.
func _persist(fields: Dictionary) -> void:
	var save := get_tree().root.get_node_or_null("SaveService")
	var app := get_tree().root.get_node_or_null("App")
	if save == null:
		return
	var mode: bool = app.get("tuning_mode") if app != null else true
	save.call("put_tuning", mode, fields)


func _save_node() -> Node:
	return get_tree().root.get_node_or_null("SaveService")


## The stashed pre-reset values ({} when there is nothing to undo).
func _undo_fields() -> Dictionary:
	var save := _save_node()
	if save == null:
		return {}
	return Dictionary(save.call("get_tuning")).get("undo", {})


func _reset_or_undo() -> void:
	if _undo_fields().is_empty():
		_reset()
	else:
		_undo()


## Stash the current values first, so the reset can be undone — even after a
## restart. A reset wiped a week of on-device tuning once; never again.
func _reset() -> void:
	if tuning == null:
		return
	var save := _save_node()
	if save != null:
		save.call("put_tuning_undo", tuning.to_dict())
	tuning.apply_dict(FlickTuning.defaults().to_dict())
	_persist({})
	_last_outcome = "reset to defaults (UNDO puts yours back)"
	_render()


func _undo() -> void:
	if tuning == null:
		return
	var prev := _undo_fields()
	if prev.is_empty():
		return
	tuning.apply_dict(prev)
	_persist(prev)
	var save := _save_node()
	if save != null:
		save.call("put_tuning_undo", {})
	_last_outcome = "undo: your values are back"
	_render()


func _log() -> void:
	if tuning == null:
		return
	print("TUNING ", JSON.stringify(tuning.to_dict()))
	_last_outcome = "logged (adb logcat -s godot)"
	_render()


# ---- readouts -----------------------------------------------------------------


func record_flick(sample: Dictionary, launch: Dictionary) -> void:
	var speed_sh: float = Vector2(sample["vel_x"], sample["vel_y"]).length() / sample["viewport_h"]
	if launch.is_empty():
		_last_flick = "flick %.2f sh/s → CANCELLED" % speed_sh
	else:
		# The make band at this angle: the speed that centers the rim for the
		# real triangle (side/high releases carry dist/rise in the launch).
		var g := geo if geo != null else SimGeometry.regulation()
		var ideal := Ballistics.speed_for_angle(
			launch["angle_deg"], launch.get("dist", g.hoop_x), launch.get("rise", g.rise)
		)
		var delta := NAN
		if not is_nan(ideal):
			delta = launch["speed"] - ideal
		var extra := ""
		if launch.has("pull"):
			extra += " pull %.2f" % launch["pull"]
		if launch.has("bx"):
			extra += " brg %+.1f°" % rad_to_deg(atan2(launch["bz"], launch["bx"]))
		if launch.has("roll"):
			extra += " roll %+.1f" % launch["roll"]
		_last_flick = "flick %.2f sh/s → %.1f° %.2f m/s (ideal %+.2f)%s" % [
			speed_sh, launch["angle_deg"], launch["speed"], delta, extra,
		]
		# Machine-readable line for on-device calibration (adb logcat -s godot).
		var tilt_deg := rad_to_deg(atan2(sample["vel_x"], -sample["vel_y"]))
		print("FLICK sh=%.3f angle=%.1f speed=%.3f ideal_delta=%+.3f pull=%.2f tilt=%+.1f origin=(%.2f,%.2f) dist=%.2f rise=%.2f" % [
			speed_sh, launch["angle_deg"], launch["speed"], delta, launch.get("pull", 0.0), tilt_deg,
			launch.get("ry", 0.0), launch.get("rz", 0.0), launch.get("dist", 0.0), launch.get("rise", 0.0)])
	_render()


func record_outcome(outcome: Dictionary) -> void:
	_attempts += 1
	if outcome["made"]:
		_makes += 1
	var entry: String = outcome["type"]
	if not is_nan(outcome["entry_angle_deg"]):
		entry += " (entry %.0f°)" % outcome["entry_angle_deg"]
	print("OUTCOME %s made=%s" % [outcome["type"], str(outcome["made"])])
	_last_outcome = entry
	_lines.push_front(entry)
	if _lines.size() > HISTORY:
		_lines.resize(HISTORY)
	_render()


func _render() -> void:
	if _reset_btn != null:
		_reset_btn.text = "RESET" if _undo_fields().is_empty() else "UNDO"
	if tuning == null:
		return
	var field: String = _fields[_selected][0]
	if _field_btn != null:
		_field_btn.text = "%s = %s" % [field, str(tuning.get(field))]
	if _readout != null:
		_readout.text = "%s\n%s · makes %d/%d" % [
			_last_flick, _last_outcome, _makes, _attempts]
	if not _label.visible:
		return
	var txt := "FLICK LAB — F3 or ` hides · 1-9 select · -/= adjust\n"
	for i in _fields.size():
		var f: String = _fields[i][0]
		txt += "%s %d.%s = %s\n" % ["▶" if i == _selected else " ", i + 1, f, str(tuning.get(f))]
	txt += "\n%s\n" % _last_flick
	txt += "makes %d/%d (%.0f%%)\n\n" % [_makes, _attempts, 100.0 * _makes / maxi(_attempts, 1)]
	for l in _lines:
		txt += l + "\n"
	_label.text = txt
