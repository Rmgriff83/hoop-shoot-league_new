extends Node3D
## The splash (design "Splash Screen" 30a NEON WALL, 2026-10-30; docs/HOME.md
## → Splash): the first screen on launch and where the Area Archive's back
## leads. The app icon's look blown up — no 3D model any more: a dark brick
## wall, HOOP SHOOT LEAGUE in white pixel neon, and the orange neon ball. The
## ball drops in from above-left and rolls right as it bounces (two steps on
## the first bounce, one on each of the next two), squashing on each landing,
## three bounces lower each time, and settles behind the end of LEAGUE; the
## words then buzz and flicker on and hold with a faint hum. As they light,
## the menu fades in: your save card (CONTINUE → the title, the archive as
## the front door) or NEW GAME (→ the NEW PLAYER form, design 35a), SETTINGS,
## CREDITS (whose back returns here). Discord and Reddit sit top-left (links
## to come). A tap on the sign replays it all. The timeline is the design's
## CSS keyframes, ported as pure functions (ball_pose, ball_frame,
## text_level, fade_at) so the tests can read them.

const DESIGN_H := 1560.0
const SHORT_H := 1280.0
## On a 9:16 screen the sign block rides up this far (the menu keeps its
## distance from the bottom); in between it scales with the screen.
const SHORT_LIFT := 170.0
const TEXT_Y := -40.0
const BALL_POS := Vector2(312, 569)
const BALL_PX := 400.0
const BALL_PIVOT := Vector2(200, 320)
const BALL_FRAMES := 12
const BALL_START := 0.2        # ballIn / ballRoll: 2 s from 0.2 s
const BALL_DUR := 2.0
const BALL_HUM_AT := 2.4       # then the ball hums on a 4.3 s loop
const BALL_HUM_S := 4.3
const TEXT_START := 1.9        # neonOn: 2.2 s from 1.9 s
const TEXT_DUR := 2.2
const TEXT_HUM_AT := 4.1       # then a 3.7 s hum
const TEXT_HUM_S := 3.7
const SOCIAL_POS := Vector2(28, 126)
const ICON_HIT := 56.0
const ICON_PX := 40.0
const SOCIAL_AT := 3.0
const SOCIAL_FADE := 0.5
const MENU_LEFT := 36.0
const MENU_RIGHT := 42.0
const MENU_TOP := 1025.0
const MENU_GAP := 26.0
const CARD_H := 236.0
const NEW_H := 140.0
const ROW_H := 70.0
const FADE_S := 0.6
const FADE_AT := [2.7, 2.85, 3.0]   # the primary card, SETTINGS, CREDITS
const BADGE := Color("#FFE45C")
const SOCIAL := ["discord", "reddit"]
## The ballIn keys: [t, translate, scale, ease of the segment it starts]
## ("in" = CSS ease-in, "out" = ease-out).
const BALL_KEYS := [
	[0.0, Vector2(-120, -1100), Vector2(0.96, 1.05), "in"],
	[0.32, Vector2(-80, 0), Vector2(0.97, 1.04), "out"],
	[0.36, Vector2(-75, 0), Vector2(1.1, 0.89), "out"],
	[0.41, Vector2(-69, -36), Vector2(0.97, 1.03), "out"],
	[0.53, Vector2(-54, -190), Vector2(1, 1), "in"],
	[0.64, Vector2(-41, 0), Vector2(0.985, 1.02), "out"],
	[0.67, Vector2(-37, 0), Vector2(1.06, 0.94), "out"],
	[0.71, Vector2(-32, -16), Vector2(0.98, 1.02), "out"],
	[0.78, Vector2(-24, -70), Vector2(1, 1), "in"],
	[0.85, Vector2(-15, 0), Vector2(1, 1), "out"],
	[0.875, Vector2(-12, 0), Vector2(1.03, 0.97), "out"],
	[0.91, Vector2(-7, -6), Vector2(1, 1), "out"],
	[0.94, Vector2(-4, -18), Vector2(1, 1), "in"],
	[0.97, Vector2(0, 0), Vector2(1.015, 0.985), "out"],
	[1.0, Vector2(0, 0), Vector2(1, 1), "out"],
]
## ballRoll: the strip frame from each point on (9 → 11 in two steps on the
## first bounce, then 12 and 13, which wrap to 0 and 1).
const ROLL_KEYS := [[0.0, 9], [0.36, 10], [0.40, 11], [0.70, 0], [0.89, 1]]
## neonOn (the later definition in the design's CSS, which wins): linear.
const NEON_KEYS := [[0.0, 0.0], [0.05, 0.7], [0.07, 0.0], [0.13, 0.9], [0.15, 0.15], [0.19, 0.0],
	[0.27, 0.5], [0.29, 0.1], [0.35, 0.75], [0.37, 0.4], [0.45, 0.55], [1.0, 1.0]]
## neonHum: full, then a stutter at 60–62 %.
const HUM_KEYS := [[0.0, 1.0], [0.58, 1.0], [0.60, 0.82], [0.61, 0.97], [0.62, 0.86], [0.64, 1.0], [1.0, 1.0]]

var _ui: CanvasLayer
var _ball: TextureRect
var _ball_tex: AtlasTexture
var _text_on: TextureRect
var _social: Control
var _buttons: Array[Control] = []
var _t := 0.0
var _risen := false
var _settings: SettingsPanel
var _new_player: NewPlayerPage
var _leaving := false


## CONTINUE once a player exists, NEW GAME before (App.player_created).
static func primary_label(created: bool) -> String:
	return "CONTINUE" if created else "NEW GAME"


# ---- the timeline (pure) ----------------------------------------------------------------


## CSS ease-in / ease-out: cubic-bezier(.42,0,1,1) / (0,0,.58,1), solved for x.
static func css_ease(kind: String, x: float) -> float:
	if x <= 0.0 or x >= 1.0:
		return clampf(x, 0.0, 1.0)
	var p1 := Vector2(0.42, 0.0) if kind == "in" else Vector2(0.0, 0.0)
	var p2 := Vector2(1.0, 1.0) if kind == "in" else Vector2(0.58, 1.0)
	var lo := 0.0
	var hi := 1.0
	var u := x
	for i in 30:
		u = (lo + hi) * 0.5
		var bx := 3.0 * (1.0 - u) * (1.0 - u) * u * p1.x + 3.0 * (1.0 - u) * u * u * p2.x + u * u * u
		if bx < x:
			lo = u
		else:
			hi = u
	return 3.0 * (1.0 - u) * (1.0 - u) * u * p1.y + 3.0 * (1.0 - u) * u * u * p2.y + u * u * u


## The ball's offset from its resting spot and its scale `t` s in.
static func ball_pose(t: float) -> Dictionary:
	var k := clampf((t - BALL_START) / BALL_DUR, 0.0, 1.0)
	for i in BALL_KEYS.size() - 1:
		var a: Array = BALL_KEYS[i]
		var b: Array = BALL_KEYS[i + 1]
		if k <= float(b[0]):
			var e := css_ease(str(a[3]), (k - float(a[0])) / (float(b[0]) - float(a[0])))
			return {"pos": (a[1] as Vector2).lerp(b[1], e), "scale": (a[2] as Vector2).lerp(b[2], e)}
	return {"pos": Vector2.ZERO, "scale": Vector2.ONE}


## Which of the roll strip's twelve frames shows `t` s in.
static func ball_frame(t: float) -> int:
	var k := clampf((t - BALL_START) / BALL_DUR, 0.0, 1.0)
	var f := 9
	for key in ROLL_KEYS:
		if k >= float(key[0]):
			f = int(key[1])
	return f


## A linear keyframe track at `k` (0..1).
static func _track(keys: Array, k: float) -> float:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if k <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (k - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-6))
	return float(keys[keys.size() - 1][1])


## The hum: 1 but for its stutter, looping every `period` s from `at`.
static func hum(t: float, at: float, period: float) -> float:
	if t < at:
		return 1.0
	return _track(HUM_KEYS, fposmod(t - at, period) / period)


## The lit words' opacity: dark, the flicker on, then the hum.
static func text_level(t: float) -> float:
	if t < TEXT_START:
		return 0.0
	if t < TEXT_START + TEXT_DUR:
		return _track(NEON_KEYS, (t - TEXT_START) / TEXT_DUR)
	return hum(t, TEXT_HUM_AT, TEXT_HUM_S)


## A fade in (CSS ease-out) of `dur` s from `at`.
static func fade_at(t: float, at: float, dur: float) -> float:
	return css_ease("out", clampf((t - at) / dur, 0.0, 1.0))


## How far the sign block rides up on a screen `h` tall (0 at the design's 1560).
static func sign_lift(h: float) -> float:
	return roundf(lerpf(SHORT_LIFT, 0.0, clampf((h - SHORT_H) / (DESIGN_H - SHORT_H), 0.0, 1.0)))


# ---- the screen -----------------------------------------------------------------------------


func _ready() -> void:
	Sfx.start_music(App.TITLE_MUSIC["id"], App.TITLE_MUSIC["clip"], App.TITLE_MUSIC["gain_db"])
	_build_ui()
	_apply()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "Ui"
	_ui.layer = 10
	UiLayout.anchor_layer(_ui)
	add_child(_ui)
	var h := UiLayout.screen_height()
	var lift := sign_lift(h)
	var dark := ColorRect.new()
	dark.name = "Dark"
	dark.color = Color("#17110F")
	UiLayout.full_rect(dark)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(dark)
	# The wall from the top, the design's full height (a shorter screen crops its foot).
	var wall := _image("Wall", "neon_bg", Vector2.ZERO)
	_ui.add_child(wall)
	# The ball behind the words, one 400 px frame of the roll strip.
	_ball_tex = AtlasTexture.new()
	_ball_tex.atlas = load("res://assets/splash/neon_ball_roll.png")
	_ball_tex.region = Rect2(ball_frame(0.0) * BALL_PX, 0, BALL_PX, BALL_PX)
	_ball = TextureRect.new()
	_ball.name = "Ball"
	_ball.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ball.stretch_mode = TextureRect.STRETCH_SCALE
	_ball.texture = _ball_tex
	_ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ball.size = Vector2.ONE * BALL_PX
	_ball.pivot_offset = BALL_PIVOT
	_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_ball)
	var off := _image("TextOff", "neon_text_off", Vector2(0, TEXT_Y - lift))
	_ui.add_child(off)
	_text_on = _image("TextOn", "neon_text_on", Vector2(0, TEXT_Y - lift))
	_ui.add_child(_text_on)
	var tap := Button.new()
	tap.name = "SignTap"
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		tap.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	tap.position = Vector2(0, 260.0 - lift)
	tap.size = Vector2(720, 700)
	tap.pressed.connect(replay)
	_ui.add_child(tap)
	# Discord / Reddit, top-left under the notch (the links come later).
	_social = Control.new()
	_social.name = "Social"
	_social.position = Vector2(SOCIAL_POS.x, UiLayout.header_top(SOCIAL_POS.y, 18.0))
	_social.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_social)
	for i in SOCIAL.size():
		var b := Button.new()
		b.name = "Social_%s" % SOCIAL[i]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.position = Vector2((ICON_HIT + 12.0) * i, 0.0)
		b.size = Vector2.ONE * ICON_HIT
		var ic := PixelIcon.new("icon_%s" % SOCIAL[i], Vector2.ONE * ICON_PX, 3.0)
		ic.position = Vector2.ONE * ((ICON_HIT - ICON_PX) / 2.0)
		b.add_child(ic)
		_social.add_child(b)
	# The menu, its distance from the bottom kept from the design.
	var y := h - (DESIGN_H - MENU_TOP)
	var created := App.player_created()
	var primary := _save_card() if created else _new_game()
	primary.name = "Primary"
	primary.pressed.connect(_continue)
	var settings := _row("SETTINGS", PixelIcon.new("icon_gear", Vector2(30, 30), 2.0))
	settings.name = "Settings"
	settings.pressed.connect(_open_settings)
	var credits := _row("CREDITS", _display(">", 20))
	credits.name = "Credits"
	credits.pressed.connect(_open_credits)
	for b in [primary, settings, credits]:
		b.position = Vector2(MENU_LEFT, y)
		_ui.add_child(b)
		_buttons.push_back(b)
		y += b.size.y - ShadowStyle.OFFSET + MENU_GAP


func _image(name_: String, file: String, at: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.name = name_
	r.texture = load("res://assets/splash/%s.png" % file)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.position = at
	r.size = Vector2(720, DESIGN_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _display(text: String, size_: int) -> Label:
	var l := RetroTheme.display(text, size_, RetroTheme.SCENE_TEXT)
	RetroTheme.on_scene(l)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _words(text: String, size_: int) -> Label:
	var l := RetroTheme.caps(text, size_, RetroTheme.SCENE_TEXT)
	RetroTheme.on_scene(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A menu button the design's width, `h` tall, with its row inset `pad`.
func _card(colour: Color, h: float, pad: float, shine: bool) -> Array:
	var b := ShadowCard.new(colour)
	b.size = Vector2(720.0 - MENU_LEFT - MENU_RIGHT, h) + Vector2.ONE * ShadowStyle.OFFSET
	b.clip_contents = true
	if shine:
		var sh := PreMatchPage.Shine.new(2.0, 200.0, 0.55)
		sh.name = "Shine"
		sh.size = b.size - Vector2.ONE * ShadowStyle.OFFSET
		b.add_child(sh)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(row)
	row.offset_left = pad
	row.offset_right = -(pad + ShadowStyle.OFFSET)
	row.offset_bottom = -ShadowStyle.OFFSET
	b.add_child(row)
	return [b, row]


## Your save: the jersey, your name, town, online badge (when rated) and
## level, `>` on the right.
func _save_card() -> ShadowCard:
	var made := _card(RetroTheme.c("orange"), CARD_H, 32.0, true)
	var row: HBoxContainer = made[1]
	var rec := FaceOffPage.you_record()
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 18)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(who)
	var jersey := PixelIcon.new("icon_jersey", Vector2(96, 96), 4.0)
	jersey.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(jersey)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(col)
	var name_l := _display(str(rec.get("name", "YOU")), 32)
	name_l.name = "Name"
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_l)
	var town := str(rec.get("town", ""))
	if town != "":
		var t := _words(town, 21)
		t.name = "Town"
		col.add_child(t)
	var rank: Dictionary = rec.get("rank", {})
	if not rank.is_empty() and int(rank.get("games", 0)) > 0:
		var badge := _display(RankedRules.badge_text(rank), 19)
		badge.name = "Badge"
		badge.add_theme_color_override("font_color", BADGE)
		col.add_child(badge)
	var lvl := _words("LVL %d" % int(rec.get("level", 1)), 21)
	lvl.name = "Level"
	col.add_child(lvl)
	row.add_child(_display(">", 32))
	return made[0]


func _new_game() -> ShadowCard:
	var made := _card(RetroTheme.c("orange"), NEW_H, 32.0, true)
	var row: HBoxContainer = made[1]
	var l := _display(primary_label(false), 32)
	l.name = "Label"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(NewPlayerPage.icon_slot("icon_neonball"))
	return made[0]


func _row(text: String, end: Control) -> ShadowCard:
	var made := _card(RetroTheme.SCENE_TEXT, ROW_H, 24.0, false)
	var row: HBoxContainer = made[1]
	var l := _display(text, 20)
	l.name = "Label"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	end.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(end)
	return made[0]


func _process(dt: float) -> void:
	_t += dt
	_apply()


## Pose everything for `_t`: the ball's drop, roll and hum, the words'
## flicker and hum, the menu and icons fading in.
func _apply() -> void:
	var lift := sign_lift(UiLayout.screen_height())
	var pose := ball_pose(_t)
	_ball.position = BALL_POS + Vector2(0, -lift) + (pose["pos"] as Vector2)
	_ball.scale = pose["scale"]
	_ball_tex.region = Rect2(ball_frame(_t) * BALL_PX, 0, BALL_PX, BALL_PX)
	_ball.modulate.a = hum(_t, BALL_HUM_AT, BALL_HUM_S)
	_text_on.modulate.a = text_level(_t)
	_social.modulate.a = fade_at(_t, SOCIAL_AT, SOCIAL_FADE)
	for i in _buttons.size():
		var a := fade_at(_t, float(FADE_AT[i]), FADE_S)
		_buttons[i].modulate.a = a
		_buttons[i].mouse_filter = Control.MOUSE_FILTER_STOP if a >= 0.5 else Control.MOUSE_FILTER_IGNORE
	if not _risen and _t >= float(FADE_AT[0]):
		_risen = true


func risen() -> bool:
	return _risen


func time() -> float:
	return _t


## A tap on the sign: the whole timeline again (ball, words, menu).
func replay() -> void:
	_t = 0.0
	_risen = false
	_apply()


func _open_credits() -> void:
	if _leaving or _settings != null or _new_player != null:
		return
	_leaving = true
	App.to_credits("splash")


func _continue() -> void:
	if _leaving or _settings != null or _new_player != null:
		return
	if not App.player_created():
		_open_new_player()
		return
	_leaving = true
	App.show_archive = true
	App.to_title("continue")


## NEW GAME: the splash (sign and all) slides out to the left while the NEW
## PLAYER form slides in from the right; its < brings the splash back.
func _open_new_player() -> void:
	_new_player = NewPlayerPage.new()
	_new_player.name = "NewPlayerPage"
	_new_player.closed.connect(func() -> void:
		_new_player = null
		_slide_ui(false)
	)
	add_child(_new_player)
	_new_player.slide_in()
	_slide_ui(true)


func _slide_ui(out: bool) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ui, "offset:x", -HomePage.SLIDE if out else 0.0, HomePage.OPEN_S)


func new_player_open() -> bool:
	return _new_player != null


func _open_settings() -> void:
	if _settings != null or _leaving:
		return
	_settings = SettingsPanel.new()
	_settings.name = "SettingsPanel"
	_settings.closed.connect(func() -> void: _settings = null)
	add_child(_settings)
