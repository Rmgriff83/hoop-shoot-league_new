extends RefCounted
## The splash (design "Splash Screen" 29a): the 2D neon sign's timeline
## (chain tug, blinks, slow swell, breath), its colours, the button copy per
## save state, the social icons, and the routing (main scene, App.to_splash,
## the archive's front door).


func run(t) -> void:
	# The timeline, straight from Neon Sign.html.
	t.close(NeonSign.level_at(1.0), 0.0, 1e-9, "dark for the first 1.3 s")
	t.close(NeonSign.level_at(1.35), 0.3, 1e-9, "the first blink")
	t.close(NeonSign.level_at(1.5), 0.04, 1e-9, "…drops almost out")
	t.close(NeonSign.level_at(1.65), 0.4, 1e-9, "…the second blink")
	t.ok(NeonSign.level_at(2.5) > 0.18 and NeonSign.level_at(2.5) < 0.6, "warming through the swell")
	t.ok(NeonSign.level_at(4.5) >= 0.99, "full by 4.5 s")
	var lo := 1.0
	var hi := 0.0
	for i in 60:
		var k := NeonSign.level_at(4.6 + i * 0.1)
		lo = minf(lo, k)
		hi = maxf(hi, k)
	t.ok(lo >= 0.92 and hi <= 1.0, "then it breathes within 7 %% (%.2f–%.2f)" % [lo, hi])
	t.close(NeonSign.chain_at(0.0), 0.0, 1e-9, "the chain hangs still at first")
	t.ok(NeonSign.chain_at(0.75) > 30.0, "tugged down by 0.75 s (%.0f px)" % NeonSign.chain_at(0.75))
	t.close(NeonSign.chain_at(1.3), 0.0, 1e-9, "…and back up by 1.3 s")
	t.ok(NeonSign.chain_at(0.55) > 0.0 and NeonSign.chain_at(0.55) < NeonSign.chain_at(0.75), "on its way down mid-tug")
	# Colours: dark glass off, orange glass and cream core on.
	t.ok(NeonSign.tube_color(0.0).is_equal_approx(NeonSign.OFF_GLASS), "off: dark glass")
	t.ok(NeonSign.tube_color(1.0).is_equal_approx(NeonSign.ON_GLASS), "on: orange glass")
	t.ok(NeonSign.core_color(1.0).is_equal_approx(NeonSign.ON_CORE), "on: cream core")
	# The node.
	var sign := NeonSign.new()
	var sz := NeonSign.sign_size()
	t.ok(sz.x > 480.0 and sz.x < 600.0 and sz.y > 400.0, "three rows at 96 px cap plus the chain (%s)" % str(sz))
	t.ok(sign.size == sz, "the control is its own size")
	t.ok(not sign.done() and sign.level() == 0.0, "dark at 0")
	sign.step(4.7)
	t.ok(sign.done() and sign.level() > 0.9, "done once lit")
	sign.replay()
	t.ok(not sign.done() and sign.time() == 0.0, "a tap replays from the top")
	t.ok(sign.chain_anchor().x > 300.0 and sign.chain_anchor().y > 280.0, "the chain hangs off the last E (%s)" % str(sign.chain_anchor()))
	t.eq(sign._polylines().size(), 4 * 2 + 1 + 2 + 2 + 3 + 1 + 1 + 1 + 1 + 1 + 1 + 1, "every letter's strokes (HOOP 3+1+1+1, SHOOT 1+1+1+1+2, LEAGUE 1+2+1+1+1+2)")
	sign.free()
	# Copy and routing.
	t.eq(load("res://game/screens/splash_screen.gd").primary_label(true), "CONTINUE", "a save: CONTINUE")
	t.eq(load("res://game/screens/splash_screen.gd").primary_label(false), "NEW GAME", "no save: NEW GAME")
	for n in ["icon_discord", "icon_reddit", "icon_gear", "icon_ball"]:
		t.ok(PixelIcon.tex(n) != null, "%s ships" % n)
	t.eq(PixelIcon.tex("icon_discord").get_width(), 16, "the design's 16 px Discord glyph")
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app != null:
		t.eq(str(ProjectSettings.get_setting("application/run/main_scene")), app.SPLASH_SCENE, "the splash is the main scene")
		t.ok(ResourceLoader.exists(app.SPLASH_SCENE) and app.has_method("to_splash"), "App.to_splash reaches it")
		t.ok(app.has_save() == true or app.has_save() == false, "has_save answers")
	var spec := {"cam_pos": Vector3(-1.65, 2.0, -0.55), "look_at": Vector3(2.9, 1.55, 0.2), "drift": Vector3(0.05, 0, 0.5), "period_s": 28.0, "fov": 66.0}
	var zo: Dictionary = load("res://game/screens/splash_screen.gd").zoomed_out(spec)
	t.ok(float(zo["fov"]) > 66.0 and Vector3(zo["cam_pos"]).x < -1.65 and float(zo["period_s"]) > 28.0, "zoomed out: wider, farther back, slower")
