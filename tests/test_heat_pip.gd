extends RefCounted
## The opponent's window (docs/PERFORMANCE.md rule 9, docs/LOCKER.md → The
## kit): a CourtGeometry in the PIP profile draws no sun shadows and freezes
## its area fx; the kit it wears is the other phone's online (resolved
## against our catalog, stock for anything unknown) and the court's stock
## pair solo; the hoop only where the court lets a player pick one.


func run(t) -> void:
	for area in ["beach", "park", "city"]:
		var full := CourtGeometry.new()
		full.geo = SimGeometry.beach() if area == "beach" else SimGeometry.park()
		full.arena_set = CosmeticLibrary.get_arena(area)
		full.hoop_set = CosmeticLibrary.starter_hoop()
		full._ready()
		var pip := CourtGeometry.new()
		pip.profile = CourtGeometry.Profile.PIP
		pip.geo = full.geo
		pip.arena_set = full.arena_set
		pip.hoop_set = full.hoop_set
		pip._ready()
		t.ok(full.sun_shadows_on(), "%s FULL: the sun casts shadows" % area)
		t.ok(not pip.sun_shadows_on(), "%s PIP: no sun shadows" % area)
		t.ok(full.live_fx_count() >= 1, "%s FULL: its area fx animate (%d)" % [area, full.live_fx_count()])
		t.eq(pip.live_fx_count(), 0, "%s PIP: every area fx frozen" % area)
		t.ok(pip.find_child("Sun", true, false) != null and pip.find_child("Env", true, false) != null, "%s PIP keeps its sun, fog and ambient" % area)
		full.free()
		pip.free()
	var cage := CourtGeometry.new()
	cage.profile = CourtGeometry.Profile.PIP
	cage.geo = SimGeometry.arcade(2.9)
	cage.arena_set = CosmeticLibrary.get_arena("cage")
	cage.hoop_set = CosmeticLibrary.starter_hoop()
	cage._ready()
	t.eq(cage.live_fx_count(), 0, "cage PIP: the arcade life frozen")
	cage.free()

	# The kit the window wears.
	var HeatScreen = load("res://game/screens/heat_screen.gd")
	var hoop := CosmeticLibrary.starter_hoop()
	var online := {"online": true, "their_kit": {"v": 1, "ball": "galaxy", "net": "rwb"}}
	var k: Dictionary = HeatScreen.pip_kit(online, hoop, true)
	t.eq([k["ball"].id, k["net"].id, k["hoop"]], ["galaxy", "rwb", null], "online: the other phone's ball and net, the court's hoop")
	var unknown: Dictionary = HeatScreen.pip_kit({"online": true, "their_kit": {"v": 1, "ball": "zzz", "net": "zzz"}}, hoop, true)
	t.eq([unknown["ball"].id, unknown["net"].id], [CosmeticLibrary.starter_ball().id, "cotton"], "online, ids we do not know: the stock pair")
	var none: Dictionary = HeatScreen.pip_kit({"online": true}, hoop, true)
	t.eq([none["ball"].id, none["net"].id], [CosmeticLibrary.starter_ball().id, "cotton"], "online, no kit (an older build): the stock pair")
	var chain_hoop := CosmeticLibrary.get_hoop("city")
	if chain_hoop != null:
		var city: Dictionary = HeatScreen.pip_kit({"online": true}, chain_hoop, true)
		t.eq(city["net"].id, "chain", "…on a chain rim the stock net is the chain")
	var solo: Dictionary = HeatScreen.pip_kit({"league": {"id": "cage"}, "opponent": {"id": "sh_01"}}, hoop, true)
	t.eq([solo["ball"].id, solo["net"].id, solo["hoop"]], [CosmeticLibrary.starter_ball().id, "cotton", null], "solo: the stock pair (no shooter names a kit)")
	var hoops := CosmeticLibrary.hoops()
	if hoops.size() > 1:
		var other: HoopSet = hoops[1] if hoops[0].id == hoop.id else hoops[0]
		var cage_k: Dictionary = HeatScreen.pip_kit({"online": true, "their_kit": {"v": 1, "ball": "galaxy", "net": "rwb", "hoop": other.id}}, hoop, false)
		t.eq(cage_k["hoop"].id, other.id, "the cage (no fixed hoop) takes their hoop")
		var fixed: Dictionary = HeatScreen.pip_kit({"online": true, "their_kit": {"v": 1, "ball": "galaxy", "net": "rwb", "hoop": other.id}}, hoop, true)
		t.eq(fixed["hoop"], null, "…a court with a fixed hoop ignores it")
