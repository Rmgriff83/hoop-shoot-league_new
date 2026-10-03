extends Node3D
## The splash (design "Splash Screen" 29a, 2026-10-03; docs/HOME.md →
## Splash): the first screen on launch and where the Area Archive's back
## leads. The design's own 3D neon sign (NeonSign3D) hangs in a 720×720
## viewport over black — Ross's call for now: no court, no frosted glass —
## and lights up the moment the screen appears; as it reaches full glow the
## two orange buttons rise in: CONTINUE (NEW GAME with no save) → the title,
## which opens the archive as the front door, and SETTINGS → the campaign
## home's sheet. Discord and Reddit icons sit top-left (links to come).
## A tap on the sign replays it.

const SIGN_VIEW := Vector2i(720, 720)
const SIGN_TOP := 150.0
const SIGN_FOV := 40.0
const ICON_ROW := Vector2(28.0, 40.0)
const ICON_HIT := 56.0
const ICON_PX := 40.0
const BUTTON_LEFT := 36.0
const BUTTON_RIGHT := 42.0
const BUTTON_TOP := 900.0
const BUTTON_H := 140.0
const BUTTON_GAP := 30.0
const RISE_PX := 40.0
const RISE_S := 0.45
const RISE_STAGGER := 0.15
const SOCIAL := ["discord", "reddit"]

var _sub: SubViewport
var _cam: Camera3D
var _sign: NeonSign3D
var _ui: CanvasLayer
var _buttons: Array[Control] = []
var _risen := false
var _settings: SettingsPanel
var _leaving := false


## CONTINUE with a save behind it, NEW GAME without.
static func primary_label(has_save: bool) -> String:
	return "CONTINUE" if has_save else "NEW GAME"


func _ready() -> void:
	Sfx.start_music(App.TITLE_MUSIC["id"], App.TITLE_MUSIC["clip"], App.TITLE_MUSIC["gain_db"])
	_build_sign()
	_build_ui()


## The sign in its own world: black, a touch of glow for the tubes, a soft
## key light for the steel chain and the blocked-out jumps; the camera fits
## the sign the way the design's embed does.
func _build_sign() -> void:
	_sub = SubViewport.new()
	_sub.name = "SignView"
	_sub.size = SIGN_VIEW
	_sub.own_world_3d = true
	_sub.transparent_bg = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.45, 0.4)
	env.ambient_light_energy = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_sub.add_child(we)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_energy = 0.8
	key.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	_sub.add_child(key)
	_sign = NeonSign3D.new()
	_sub.add_child(_sign)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = SIGN_FOV
	var c := _sign.bounds().get_center()
	_sub.add_child(_cam)
	_cam.position = Vector3(c.x, c.y, c.z + _sign.fit_distance(SIGN_FOV, 1.0))
	_cam.look_at(c)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "Ui"
	_ui.layer = 10
	add_child(_ui)
	# Black for now, then the sign's viewport in its 720 px band.
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)
	var view := TextureRect.new()
	view.name = "SignTexture"
	view.texture = _sub.get_texture()
	view.position = Vector2(0.0, SIGN_TOP)
	view.size = Vector2(SIGN_VIEW)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(view)
	var tap := Button.new()
	tap.name = "SignTap"
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		tap.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	tap.position = view.position
	tap.size = view.size
	tap.pressed.connect(_replay)
	_ui.add_child(tap)
	# Discord / Reddit, top-left (the links come later).
	for i in SOCIAL.size():
		var b := Button.new()
		b.name = "Social_%s" % SOCIAL[i]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.position = ICON_ROW + Vector2((ICON_HIT + 12.0) * i, 0.0)
		b.size = Vector2.ONE * ICON_HIT
		var ic := PixelIcon.new("icon_%s" % SOCIAL[i], Vector2.ONE * ICON_PX, 3.0)
		ic.position = Vector2.ONE * ((ICON_HIT - ICON_PX) / 2.0)
		b.add_child(ic)
		_ui.add_child(b)
	# The two buttons, parked low and clear until the sign is lit.
	var primary := _button(primary_label(App.has_save()), "icon_ball", BUTTON_TOP)
	primary.name = "Primary"
	primary.pressed.connect(_continue)
	var settings := _button("SETTINGS", "icon_gear", BUTTON_TOP + BUTTON_H + BUTTON_GAP)
	settings.name = "Settings"
	settings.pressed.connect(_open_settings)
	for b in [primary, settings]:
		b.modulate.a = 0.0
		b.position.y += RISE_PX
		_ui.add_child(b)
		_buttons.push_back(b)


## A full-width orange card button: the label left, a pixel icon right.
func _button(text: String, icon: String, top: float) -> ShadowCard:
	var b := ShadowCard.new(RetroTheme.c("orange"))
	b.position = Vector2(BUTTON_LEFT, top)
	b.size = Vector2(720.0 - BUTTON_LEFT - BUTTON_RIGHT, BUTTON_H)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 32.0
	row.offset_right = -(32.0 + ShadowCard.OFFSET)
	row.offset_bottom = -ShadowCard.OFFSET
	b.add_child(row)
	var l := Label.new()
	l.name = "Label"
	l.text = text
	l.add_theme_font_override("font", UiFont.display())
	l.add_theme_font_size_override("font_size", 32)
	RetroTheme.on_scene(l)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(48, 48)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(PixelIcon.new(icon, Vector2(48, 48), 3.0))
	row.add_child(box)
	return b


func _process(_dt: float) -> void:
	if not _risen and _sign.done():
		_rise()


## The buttons rise in under the lit sign, 0.15 s apart, with the design's overshoot.
func _rise() -> void:
	_risen = true
	for i in _buttons.size():
		var b := _buttons[i]
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "position:y", b.position.y - RISE_PX, RISE_S).set_delay(i * RISE_STAGGER)
		tw.tween_property(b, "modulate:a", 1.0, RISE_S * 0.6).set_delay(i * RISE_STAGGER)


func risen() -> bool:
	return _risen


func _replay() -> void:
	_sign.replay()


func _continue() -> void:
	if _leaving or _settings != null:
		return
	_leaving = true
	App.show_archive = true
	App.to_title()


func _open_settings() -> void:
	if _settings != null or _leaving:
		return
	_settings = SettingsPanel.new()
	_settings.name = "SettingsPanel"
	_settings.closed.connect(func() -> void: _settings = null)
	add_child(_settings)
