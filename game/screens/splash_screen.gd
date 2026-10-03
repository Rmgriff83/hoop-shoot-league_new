extends Node3D
## The splash (design "Splash Screen" 29a, 2026-10-03; docs/HOME.md →
## Splash): the first screen on launch and where the Area Archive's back
## leads. The arcade cage pans behind a frosted glass door — the title's
## slow truck, zoomed out a little, rendered small and scaled up soft under
## an ink scrim — with the 2D neon sign (NeonSign) hung on it. The sign
## lights up the moment the screen appears; as it reaches full glow the two
## orange buttons rise in: CONTINUE (NEW GAME with no save) → the title,
## which opens the archive as the front door, and SETTINGS → the campaign
## home's sheet. Discord and Reddit icons sit top-left (links to come).
## A tap on the sign replays it.

const GLASS_SIZE := Vector2i(180, 320)   # the court renders at a quarter size: a soft 4 px blur
const SCRIM_ALPHA := 0.45
const ZOOM_OUT_FOV := 14.0               # wider than the title's pan
const ZOOM_OUT_BACK := 0.9               # metres pulled back along the look
const PAN_SLOW := 1.5                    # the truck takes half again as long
const ICON_ROW := Vector2(28.0, 40.0)
const ICON_HIT := 56.0
const ICON_PX := 40.0
const SIGN_LEFT := 60.0
const SIGN_TOP := 150.0
const SIGN_AREA_H := 720.0
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
var _court: CourtGeometry
var _spec: Dictionary
var _t := 0.0
var _ui: CanvasLayer
var _sign: NeonSign
var _buttons: Array[Control] = []
var _risen := false
var _settings: SettingsPanel
var _leaving := false


## CONTINUE with a save behind it, NEW GAME without.
static func primary_label(has_save: bool) -> String:
	return "CONTINUE" if has_save else "NEW GAME"


func _ready() -> void:
	Sfx.start_music(App.TITLE_MUSIC["id"], App.TITLE_MUSIC["clip"], App.TITLE_MUSIC["gain_db"])
	_build_glass()
	_build_ui()


## The cage in a small viewport: the title's pan, zoomed out, drawn soft.
func _build_glass() -> void:
	_sub = SubViewport.new()
	_sub.name = "Glass"
	_sub.size = GLASS_SIZE
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_sub.add_child(_cam)
	var card: Dictionary = AreaArchiveCopy.AREAS[0]
	var arena := CosmeticLibrary.get_arena(str(card["area"]))
	if arena == null:
		arena = CosmeticLibrary.starter_arena()
	_court = CourtGeometry.new()
	_court.name = "Court"
	_court.geo = App.geo_for_mode(str(card["mode"]))
	_court.arena_set = arena
	_court.hoop_set = App.hoop_for_mode(str(card["mode"]))
	_sub.add_child(_court)
	_court.led.set_text("HOOP SHOOT", _court.led.accent_color)
	_spec = zoomed_out(TitlePan.spec_of(arena))
	_cam.fov = float(_spec["fov"])
	var p := TitlePan.pose(_spec, 0.0)
	_cam.position = p["pos"]
	_cam.look_at(p["look"])


## The title's pan spec, pulled back and widened: you are outside the door.
static func zoomed_out(spec: Dictionary) -> Dictionary:
	var out := spec.duplicate()
	var dir: Vector3 = (Vector3(spec["look_at"]) - Vector3(spec["cam_pos"])).normalized()
	out["cam_pos"] = Vector3(spec["cam_pos"]) - dir * ZOOM_OUT_BACK
	out["fov"] = float(spec["fov"]) + ZOOM_OUT_FOV
	out["period_s"] = float(spec["period_s"]) * PAN_SLOW
	return out


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "Ui"
	_ui.layer = 10
	add_child(_ui)
	# The glass: the small render scaled up with linear filtering, then the scrim.
	var glass := TextureRect.new()
	glass.name = "GlassView"
	glass.texture = _sub.get_texture()
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glass.stretch_mode = TextureRect.STRETCH_SCALE
	glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(glass)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(RetroTheme.SCENE_OUTLINE, SCRIM_ALPHA)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(scrim)
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
	# The sign, centred in its 720 px band.
	_sign = NeonSign.new()
	_sign.name = "NeonSign"
	_sign.position = Vector2(SIGN_LEFT, SIGN_TOP + (SIGN_AREA_H - NeonSign.sign_size().y) / 2.0)
	_sign.tapped.connect(_replay)
	_ui.add_child(_sign)
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


func _process(dt: float) -> void:
	_t += dt
	var p := TitlePan.pose(_spec, _t)
	_cam.position = p["pos"]
	_cam.look_at(p["look"])
	_court.step_rim(dt)
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
