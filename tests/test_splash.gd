extends RefCounted
## The splash (design "Splash Screen" 30a NEON WALL, 2026-10-30): the ball's
## drop (three bounces lower each time, squash on landing, the roll frames),
## the words' flicker and hum, the menu's fades, the button copy per save
## state, the textures, and the routing (main scene, App.to_splash, the
## credits back).


func run(t) -> void:
	var S = load("res://game/screens/splash_screen.gd")
	var at := func(k: float) -> float: return S.BALL_START + k * S.BALL_DUR
	# CSS easing.
	t.close(S.css_ease("in", 0.0), 0.0, 1e-6, "ease-in from 0")
	t.close(S.css_ease("in", 1.0), 1.0, 1e-4, "…to 1")
	t.ok(S.css_ease("in", 0.5) < 0.5 and S.css_ease("out", 0.5) > 0.5, "ease-in starts slow, ease-out fast")
	# The drop.
	var p0: Dictionary = S.ball_pose(0.0)
	t.eq(p0["pos"], Vector2(-120, -1100), "the ball starts high and left, off the top")
	for k in [0.32, 0.64, 0.85, 0.97]:
		t.close((S.ball_pose(at.call(k))["pos"] as Vector2).y, 0.0, 0.5, "on the floor at %d %%" % int(k * 100))
	var apex := [(S.ball_pose(at.call(0.53))["pos"] as Vector2).y, (S.ball_pose(at.call(0.78))["pos"] as Vector2).y, (S.ball_pose(at.call(0.94))["pos"] as Vector2).y]
	t.eq(apex, [-190.0, -70.0, -18.0], "three bounces, lower each time")
	for k in [0.36, 0.67, 0.875]:
		var sc: Vector2 = S.ball_pose(at.call(k))["scale"]
		t.ok(sc.x > 1.0 and sc.y < 1.0, "squashed flat on the landing at %.1f %% (%s)" % [k * 100.0, str(sc)])
	t.ok((S.ball_pose(at.call(0.16))["pos"] as Vector2).y < -1100.0 * 0.5, "the fall eases in (still high halfway through it)")
	var end: Dictionary = S.ball_pose(9.0)
	t.ok(end["pos"] == Vector2.ZERO and end["scale"] == Vector2.ONE, "settled at its spot")
	t.eq([S.ball_frame(0.0), S.ball_frame(at.call(0.37)), S.ball_frame(at.call(0.5)), S.ball_frame(at.call(0.75)), S.ball_frame(9.0)], [9, 10, 11, 0, 1],
		"the roll: two steps on the first bounce, one on each of the next two")
	# The words.
	t.eq(S.text_level(1.8), 0.0, "dark until 1.9 s")
	t.close(S.text_level(S.TEXT_START + 0.05 * S.TEXT_DUR), 0.7, 1e-6, "the first buzz")
	t.close(S.text_level(S.TEXT_START + 0.19 * S.TEXT_DUR), 0.0, 1e-6, "…out again")
	t.close(S.text_level(S.TEXT_HUM_AT), 1.0, 1e-6, "lit by 4.1 s")
	var lo := 1.0
	for i in 400:
		lo = minf(lo, S.text_level(S.TEXT_HUM_AT + i * 0.01))
	t.close(lo, 0.82, 0.01, "then a hum that dips to 0.82")
	# The menu's fades and the sign's lift on a short screen.
	t.ok(S.fade_at(2.6, 2.7, 0.6) == 0.0 and absf(S.fade_at(3.4, 2.7, 0.6) - 1.0) < 1e-3, "the first button fades in from 2.7 s")
	t.eq([S.sign_lift(1560.0), S.sign_lift(1280.0)], [0.0, S.SHORT_LIFT], "the sign rides up on a 9:16 screen")
	# Copy, textures, the built screen.
	t.eq(S.primary_label(true), "CONTINUE", "a save: CONTINUE")
	t.eq(S.primary_label(false), "NEW GAME", "no save: NEW GAME")
	for n in ["neon_bg", "neon_text_off", "neon_text_on", "neon_ball_on", "neon_ball_roll"]:
		t.ok(load("res://assets/splash/%s.png" % n) is Texture2D, "%s ships" % n)
	t.eq(load("res://assets/splash/neon_ball_roll.png").get_width(), 4800, "the roll strip: twelve 400 px frames")
	for n in ["icon_discord", "icon_reddit", "icon_gear", "icon_jersey", "icon_neonball"]:
		t.ok(PixelIcon.tex(n) != null, "%s ships" % n)
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app != null:
		t.eq(str(ProjectSettings.get_setting("application/run/main_scene")), app.SPLASH_SCENE, "the splash is the main scene")
		t.ok(ResourceLoader.exists(app.SPLASH_SCENE) and app.has_method("to_splash"), "App.to_splash reaches it")
		t.ok(app.has_save() == true or app.has_save() == false, "has_save answers")
		app.credits_from = "splash"
		t.ok(app.has_method("leave_credits") and app.credits_from == "splash", "credits opened from the splash remembers it")
		app.credits_from = "title"
