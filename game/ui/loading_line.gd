class_name LoadingLine
extends CenterContainer
## A loading slot in the online lobby (design "Online Lobby" 37a,
## 2026-10-31): the 32 px PixelSpinner and `LOADING PLAYER` in the display
## face at 18, its three dots counting up (LoadingCopy.dots), centred in a
## box `height` px tall. The lobby swaps it out when the answer arrives.

const SPIN := 32.0
const GAP := 18

var word := ""
var _label: Label
var _t := 0.0


func _init(p_word: String, height: float) -> void:
	word = p_word
	name = "Loading"
	custom_minimum_size = Vector2(0, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var spin := PixelSpinner.new(SPIN)
	spin.name = "Spinner"
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spin)
	_label = RetroTheme.on_scene(UiFont.label(word + "...", 18, RetroTheme.SCENE_TEXT)) as Label
	_label.name = "Word"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The width of the word and all three dots, so the row does not jump.
	_label.custom_minimum_size.x = UiFont.display().get_string_size(word + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(18)).x + 2.0 * RetroTheme.OUTLINE
	row.add_child(_label)
	_tick()


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	_tick()


func _tick() -> void:
	var t := word + LoadingCopy.dots(_t)
	if _label.text != t:
		_label.text = t


func text() -> String:
	return word
