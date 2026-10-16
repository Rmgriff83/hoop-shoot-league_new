extends RefCounted
## Nets as cosmetics (docs/LOCKER.md → NETS): ownership, the per-area
## selection, no counter (nets are PEGGY prizes), and a court that hangs — and swaps — the
## style the player chose.


func run(t) -> void:
	var app: Node = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		print("test_nets: no App autoload (headless suite): skipped")
		return
	var cos_before: Dictionary = SaveService.get_cosmetics()
	var cos: Dictionary = SaveService.default_cosmetics()   # the suite's parts start empty (headless)
	cos.merge(SaveService.get_cosmetics(), true)
	cos["tickets"] = 0
	cos["net"] = SaveService.default_nets()
	SaveService.put_cosmetics(cos)
	app.net_override = null

	t.eq(app.owned_ids("net"), ["cotton", "chain"], "the stock pair is owned")
	t.ok(app.owns("net", "cotton") and app.owns("net", "chain"), "…and owns() agrees")
	t.eq(app.net_kind_for_mode("trial"), "cotton", "the cage hangs cotton")
	t.eq(app.net_kind_for_mode("heat_beach"), "cotton", "the beach hangs cotton")
	t.eq(app.net_kind_for_mode("city"), "chain", "the city hangs chain")
	t.eq(app.net_areas("chain"), ["city"], "chain areas")
	t.eq(app.net_areas("cotton"), ["cage", "beach", "park"], "cotton areas (the park hangs cotton too)")
	t.eq(app.net_kind_for_mode("trial_park"), "cotton", "the park hangs cotton")
	t.eq(app.net_set_for("city").id, "chain", "the city's net is the stock chain")
	t.eq(app.net_set_for("cage").id, "cotton", "the cage's net is cotton")
	t.eq(app.net_set_for("nowhere").id, "cotton", "an unknown area falls back to cotton")
	t.eq(app.net_for_mode("trial_city").id, "chain", "a mode resolves its area's net")
	t.ok(not app.select_net("city", "cotton"), "a cotton net cannot hang on the chain rim")
	t.ok(not app.select_net("city", "jack"), "an unowned net cannot be hung")
	t.ok(not app.try_buy("net", "jack"), "nets are never bought (PEGGY prizes)")
	app.grant_tickets(600)
	t.ok(not app.try_buy("net", "jack"), "…not even with the tickets")
	t.eq(app.tickets(), 600, "…and nothing is spent")
	t.ok(app.grant_cosmetic("net", "jack"), "PEGGY grants the jack chain")
	t.ok(app.owns("net", "jack"), "the jack chain is owned")
	t.ok(app.unseen_prizes().has("jack"), "…and flagged unseen for the locker's dot")
	app.mark_prizes_seen()
	t.ok(app.select_net("city", "jack"), "and hangs on the city")
	t.eq(app.net_set_for("city").id, "jack", "the city shows it")
	t.eq(app.net_set_for("cage").id, "cotton", "the cage is untouched")
	t.ok(not app.select_net("cage", "jack"), "a chain cannot hang on the cage")
	t.eq(app.net_in_use_areas("jack"), ["city"], "in use on the city")
	t.eq(app.net_in_use_areas("chain"), [], "the stock chain stands by")
	t.ok(app.select_net_everywhere("chain"), "the locker hangs the stock chain everywhere it fits")
	t.eq(app.net_in_use_areas("jack"), [], "…so the jack chain is off")
	t.ok(app.grant_cosmetic("net", "ladder"), "a net can be granted")
	t.ok(app.owns("net", "ladder") and not app.grant_cosmetic("net", "ladder"), "…once")
	# A selection of a net no longer owned falls back to the stock net.
	var c2: Dictionary = SaveService.get_cosmetics()
	c2["net"]["selected"]["city"] = "ladder"
	c2["net"]["owned"] = ["cotton", "chain"]
	SaveService.put_cosmetics(c2)
	t.eq(app.net_set_for("city").id, "chain", "an unowned selection falls back to the stock net")
	# The QA override hangs a net without the save.
	app.net_override = CosmeticLibrary.get_net("ladder")
	t.eq(app.net_set_for("city").id, "ladder", "the override hangs on a chain court")
	t.eq(app.net_set_for("cage").id, "cotton", "…but not on a cotton one")
	app.net_override = null

	# A court hangs the chosen style and swaps it live.
	var court := CourtGeometry.new()
	court.geo = SimGeometry.city()
	court.arena_set = CosmeticLibrary.get_arena("city")
	court.hoop_set = CosmeticLibrary.get_hoop("chain")
	court.net_set = CosmeticLibrary.get_net("jack")
	court._ready()   # off-tree, as test_rim_feel builds its court
	t.eq(court.net_style, "jack", "the court hangs the jack chain")
	t.ok(court.net_body() is JackNet, "…as a JackNet body")
	t.eq(court.net_sim.particle_count(), 144, "…on the jack layout")
	court.set_net(CosmeticLibrary.get_net("ladder"))
	t.eq(court.net_style, "ladder", "set_net swaps to the ladder")
	t.ok(court.net_body() is LadderNet and court.net_sim.particle_count() == 72, "…body and sim together")
	t.eq(court.rim_pivot.find_children("NetBody", "", true, false).size(), 1, "the old body is gone")
	court.set_net(CosmeticLibrary.get_net("cotton"))
	t.eq(court.net_style, "chain", "a cotton net on the steel rim falls back to the stock chain")
	court.set_net(null)
	t.eq(court.net_style, "chain", "no net set: the stock chain")
	court.free()
	# A tinted cotton: the cotton body with the set's colour on its cords.
	var cage := CourtGeometry.new()
	cage.geo = SimGeometry.arcade()
	cage.arena_set = CosmeticLibrary.get_arena("cage")
	cage.hoop_set = CosmeticLibrary.get_hoop("classic")
	cage.net_set = CosmeticLibrary.get_net("neon_yellow")
	cage._ready()
	t.eq(cage.net_style, "cotton", "a neon cotton hangs the cotton body")
	var body := cage.net_body()
	t.ok(body is CottonNet and (body as CottonNet).tint == CosmeticLibrary.get_net("neon_yellow").tint, "…tinted by the set")
	var cords := (body as CottonNet).skeleton.get_node("Net_Cords") as MeshInstance3D
	var arr: Array = cords.mesh.surface_get_arrays(0)
	var want: Color = CosmeticLibrary.get_net("neon_yellow").tint
	var got: Color = (arr[Mesh.ARRAY_COLOR] as PackedColorArray)[0] if arr[Mesh.ARRAY_COLOR] != null else Color.BLACK
	t.ok(absf(got.r - want.r) < 0.01 and absf(got.g - want.g) < 0.01 and absf(got.b - want.b) < 0.01, "the cords carry the neon colour (8-bit on the mesh)")
	cage.set_net(CosmeticLibrary.get_net("cotton"))
	var plain := cage.net_body() as CottonNet
	var parr: Array = (plain.skeleton.get_node("Net_Cords") as MeshInstance3D).mesh.surface_get_arrays(0)
	t.ok(plain.tint == Color.WHITE and parr[Mesh.ARRAY_COLOR] == null, "back to plain cotton: no vertex colours")
	cage.free()
	SaveService.put_cosmetics(cos_before)
