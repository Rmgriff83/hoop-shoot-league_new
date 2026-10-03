extends RefCounted
## The splash (design "Splash Screen" 29a): the 2D neon sign's timeline
## (chain tug, blinks, slow swell, breath), its colours, the button copy per
## save state, the social icons, and the routing (main scene, App.to_splash,
## the archive's front door).


func run(t) -> void:
	# The timeline, straight from Neon Sign.html.
	t.close(NeonSign3D.level_at(1.0), 0.0, 1e-9, "dark for the first 1.3 s")
	t.close(NeonSign3D.level_at(1.35), 0.3, 1e-9, "the first blink")
	t.close(NeonSign3D.level_at(1.5), 0.04, 1e-9, "…drops almost out")
	t.close(NeonSign3D.level_at(1.65), 0.4, 1e-9, "…the second blink")
	t.ok(NeonSign3D.level_at(2.5) > 0.18 and NeonSign3D.level_at(2.5) < 0.6, "warming through the swell")
	t.ok(NeonSign3D.level_at(4.5) >= 0.99, "full by 4.5 s")
	var lo := 1.0
	var hi := 0.0
	for i in 60:
		var k := NeonSign3D.level_at(4.6 + i * 0.1)
		lo = minf(lo, k)
		hi = maxf(hi, k)
	t.ok(lo >= 0.92 and hi <= 1.0, "then it breathes within 7 %% (%.2f–%.2f)" % [lo, hi])
	t.close(NeonSign3D.chain_at(0.0), 0.0, 1e-9, "the chain hangs still at first")
	t.ok(NeonSign3D.chain_at(0.75) > 0.04, "tugged down by 0.75 s (%.3f m)" % NeonSign3D.chain_at(0.75))
	t.close(NeonSign3D.chain_at(1.3), 0.0, 1e-9, "…and back up by 1.3 s")
	t.ok(NeonSign3D.chain_at(0.55) > 0.0 and NeonSign3D.chain_at(0.55) < NeonSign3D.chain_at(0.75), "on its way down mid-tug")
	# Geometry helpers: rounded corners and spaced sampling.
	var r := NeonSign3D.rounded([[0, 0], [0, 1], [1, 1]], 0.3)
	t.ok(r.size() > 3 and r[0] == Vector2(0, 0) and r[r.size() - 1] == Vector2(1, 1), "a corner rounds into a bezier run")
	t.eq(NeonSign3D.rounded([[0, 0], [1, 0]], 0.3).size(), 2, "a straight stroke stays two points")
	var sp := NeonSign3D.spaced(PackedVector3Array([Vector3.ZERO, Vector3(0.12, 0, 0)]))
	t.ok(sp.size() >= 10 and sp[sp.size() - 1] == Vector3(0.12, 0, 0), "sampled every ~12 mm")
	var mesh := NeonSign3D.tube_mesh(sp, 0.01, 8)
	t.eq(mesh.get_surface_count(), 1, "a tube is one surface")
	t.eq(mesh.surface_get_array_len(0), (sp.size() - 1) * 8 * 6, "…two triangles per ring segment")
	# The model.
	var sign := NeonSign3D.new()
	t.eq(sign.tube_count(), 23, "23 lit strokes across HOOP / SHOOT / LEAGUE")
	t.eq(sign.jump_count(), 20, "the jumps between a word's strokes (23 − 3 words)")
	t.eq(sign.get_node("PullChain").get_child_count(), NeonSign3D.CHAIN_BEADS + 1, "sixteen beads and the pull")
	var electrodes := 0
	for c in sign.get_children():
		if String(c.name).begins_with("electrode"):
			electrodes += 1
	t.eq(electrodes, 12, "an electrode (post + cap) at both ends of each word")
	var b := sign.bounds()
	t.ok(b.size.x > 1.2 and b.size.x < 1.5 and b.size.y > 1.0 and b.size.y < 1.5, "about 1.35 m wide and 1.2 tall with the chain (%s)" % str(b.size))
	t.ok(sign.fit_distance(40.0, 1.0) > 2.0 and sign.fit_distance(40.0, 1.0) < 3.5, "the camera fits it from ~2.7 m")
	t.ok(not sign.done() and sign.level() == 0.0, "dark at 0")
	t.close(sign._core.emission_energy_multiplier, 0.0, 1e-9, "…no core glow")
	sign.step(4.7)
	t.ok(sign.done() and sign.level() > 0.9, "done once lit")
	t.ok(sign._core.emission_energy_multiplier > 2.0 and sign._glass.emission_energy_multiplier > 2.0, "the materials follow the level")
	t.ok(sign._halo.albedo_color.a > 0.15 and sign._lights[0].light_energy > 0.3, "halo and spill lights on")
	sign.replay()
	t.ok(not sign.done() and sign.time() == 0.0, "a tap replays from the top")
	sign.step(0.75)
	t.ok(sign._chain.position.y < -0.03, "the chain hangs lower mid-tug (%.3f)" % sign._chain.position.y)
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
