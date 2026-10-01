extends RefCounted
## Ambient life: the cage's cabinets + ArcadeFx, the beach's tourists, birds
## and arm waves via BeachFx.


func _count(root: Node, prefix: String, mesh_only := true) -> int:
	var n := 0
	for c in BeachFx._descendants(root):
		if c.name.begins_with(prefix) and (not mesh_only or c is MeshInstance3D):
			n += 1
	return n


func run(t) -> void:
	_city(t)
	# Cage: ten cabinets with screens and marquees; ArcadeFx binds them.
	var cage: Node = load("res://assets/arena/cage/cage.glb").instantiate()
	t.eq(_count(cage, "Cabinet"), 14, "14 cabinet bodies")
	t.eq(_count(cage, "CabScreen"), 14, "14 cabinet screens")
	t.eq(_count(cage, "CabMarquee"), 14, "14 cabinet marquees")
	var afx := ArcadeFx.new()
	t.ok(afx.setup(cage), "ArcadeFx binds the cabinets")
	t.eq(afx.screen_count(), 14, "14 screen materials")
	t.eq(afx.marquee_count(), 14, "14 marquee materials")
	afx._process(0.5)
	t.close(afx.clock(), 0.5, 1e-9, "ArcadeFx clock runs")
	var games := {}
	for m in afx._screens:
		games[int(m.get_shader_parameter("game"))] = true
	t.eq(games.size(), 4, "all four attract games in use")
	t.ok(CosmeticLibrary.get_arena("cage").arcade_life, "cage arena enables arcade life")
	# String lights replaced the HOOP SHOOT sign.
	t.eq(_count(cage, "Marquee", false), 0, "the HOOP SHOOT sign is gone")
	t.ok(afx.bulb_count() > 20, "the hall's runner lights are bound (%d bulbs)" % afx.bulb_count())
	t.close(afx._bulb_mat.get_shader_parameter("count"), float(afx.bulb_count()), 1e-6,
		"the shader knows how many are in the loop")
	t.ok(afx._bulb_mat != null, "the bulbs share ONE material so they still batch")
	# Twinkle: the run's brightness must actually move, and a flare must decay.
	afx.flare()
	afx._process(0.1)
	var lit: float = afx._bulb_mat.get_shader_parameter("flare")
	t.ok(lit > 0.1, "heat-up flares the string lights (%.2f)" % lit)
	afx._process(ArcadeFx.FLARE_S + 0.1)
	t.close(afx._bulb_mat.get_shader_parameter("flare"), 0.0, 1e-6, "the flare decays back out")
	afx.free()
	cage.free()
	# Beach: three tourist groups with arms and umbrellas; birds spawn and cross.
	t.ok(FileAccess.file_exists("res://assets/textures/beach_bird.png"), "bird sheet generated")
	var beach: Node = load("res://assets/arena/beach/beach.glb").instantiate()
	t.eq(_count(beach, "TouristRig", false), 3, "3 tourist groups")
	t.eq(_count(beach, "Towel"), 3, "3 towels")
	t.eq(_count(beach, "Umbrella", false), 2, "2 umbrella rigs")
	var bfx := BeachFx.new()
	t.ok(bfx.setup(beach), "BeachFx sets up")
	t.eq(bfx.arm_count(), 0, "nobody on the towels (no arms to wave)")
	t.eq(bfx.bird_count(), 0, "no birds at first")
	bfx.spawn_flock()
	var n0 := bfx.bird_count()
	t.ok(n0 >= 3 and n0 <= 6, "a flock of 3–6 (%d)" % n0)
	var z0: float = bfx._birds[0].position.z
	t.ok(absf(z0) > 40.0, "flock starts beyond the sky edge (z %.1f)" % z0)
	for i in 120:
		bfx._process(1.0 / 60.0)
	t.ok(absf(bfx._birds[0].position.z) < absf(z0), "birds fly inward")
	for i in int(20.0 * 60):
		bfx._process(1.0 / 60.0)
		if bfx.bird_count() == 0:
			break
	t.eq(bfx.bird_count(), 0, "flock freed once it has crossed")
	# --- Beach life: walkers on the sand, a ship on the horizon, a plane. ---
	for f in ["beach_ship", "beach_plane"]:
		t.ok(FileAccess.file_exists("res://assets/textures/%s.png" % f), "%s sheet generated" % f)

	# The ship must stay side-on rather than billboard, and sit on the horizon
	# inside the sky cylinder (r 60) or it would clip through the painted sky.
	t.ok(not bfx.has_ship(), "no ship at first")
	bfx.spawn_ship()
	t.ok(bfx.has_ship(), "a cruise ship appears")
	var sp: Vector3 = bfx._ship.position
	t.close(sp.y, BeachFx.SHIP_Y, 1e-6, "sitting on the waterline")
	t.ok(sqrt(sp.x * sp.x + sp.z * sp.z) < 58.0, "inside the sky cylinder (r %.1f)" % sqrt(sp.x * sp.x + sp.z * sp.z))
	t.ok(absf(bfx._ship.rotation.y) > 1.5, "turned side-on, not facing the camera")
	var sz0: float = sp.z
	for i in 300:
		bfx._process(1.0 / 60.0)
	t.ok(absf(bfx._ship.position.z - sz0) > 1.0, "and it crosses, slowly (%.1f m in 5 s)" % absf(bfx._ship.position.z - sz0))

	t.ok(not bfx.has_plane() and not bfx.has_jet(), "no plane at first")
	bfx.spawn_jet()
	t.ok(bfx.has_jet(), "a high jet passes now and then")
	var jp: Vector3 = bfx._jet.position
	t.ok(jp.y >= 40.0 and Vector2(jp.x, jp.z).length() < 58.0, "the jet is high and inside the sky (y %.0f)" % jp.y)
	for i in 60:
		bfx._process(1.0 / 60.0)
	t.ok(absf(bfx._jet.position.z) < absf(jp.z), "and crosses")
	bfx.spawn_plane()
	t.ok(bfx.has_plane(), "an airliner passes")
	var pp: Vector3 = bfx._plane.position
	t.ok(pp.y > 20.0, "high in the sky (y %.1f)" % pp.y)
	t.ok(sqrt(pp.x * pp.x + pp.z * pp.z) < 58.0, "and inside the sky cylinder")

	# Seeded, not randomize(): two runs must agree. This is what retires the
	# long-standing ~7 %% flake in this file.
	var b2 := BeachFx.new()
	var beach2: Node = load("res://assets/arena/beach/beach.glb").instantiate()
	b2.setup(beach2)
	b2.spawn_ship()
	var c2 := BeachFx.new()
	var beach3: Node = load("res://assets/arena/beach/beach.glb").instantiate()
	c2.setup(beach3)
	c2.spawn_ship()
	t.eq(b2._ship.position, c2._ship.position, "ambient life replays identically (seeded RNG)")
	t.close(b2._ship_vel, c2._ship_vel, 1e-9, "and at the same speed")
	# Slow: it should take minutes to cross, not seconds.
	t.ok(absf(b2._ship_vel) < 0.4, "the ship crosses slowly (%.2f m/s)" % absf(b2._ship_vel))
	b2.free()
	beach2.free()
	c2.free()
	beach3.free()

	bfx.free()
	beach.free()


## The city: cars cross the street beyond the fence (seeded, freed past the
## edge, no colliders), the windows run the pane shader, the trees billboard.
func _city(t) -> void:
	for path in CityFx.MODELS:
		t.ok(FileAccess.file_exists(path), "vehicle model shipped (%s)" % path.get_file())
	t.ok(FileAccess.file_exists("res://assets/arena/city/city.glb"), "city arena built")
	if not FileAccess.file_exists("res://assets/arena/city/city.glb"):
		return
	var city: Node = load("res://assets/arena/city/city.glb").instantiate()
	t.eq(_count(city, "StreetRig", false), 1, "one street line")
	t.ok(_count(city, "Building") >= 10, "the pack's buildings stand around the court (%d)" % _count(city, "Building"))
	for f in ["city_facades", "city_facades_lit", "city_facades_id"]:
		t.ok(FileAccess.file_exists("res://assets/textures/%s.png" % f), "%s conformed" % f)
	t.eq(_count(city, "TreeRig", false), 4, "4 street trees")
	t.ok(_count(city, "FloodHead") >= 4, "floodlight heads at the court's corners")
	t.ok(CosmeticLibrary.get_arena("city").traffic, "the city arena set asks for traffic")
	var cfx := CityFx.new()
	t.ok(cfx.setup(city), "CityFx sets up")
	t.eq(cfx.window_count(), _count(city, "Building") + _count(city, "Windows"), "every building is bound to the facade shader")
	t.eq(cfx.window_material_count(), 1, "one shared facade material (they still batch)")
	t.eq(cfx.flood_count(), 4, "a spot light hangs on each court floodlight")
	t.ok(_count(city, "LampHead") >= 5, "street lamps line the far sidewalk (%d)" % _count(city, "LampHead"))
	t.ok(_count(city, "LampGlow") >= 5, "their bulbs glow toward the court")
	t.eq(_count(city, "BusSign"), 1, "the shelter's roof sign")
	t.ok(_count(city, "BusStop", false) == 1 and _count(city, "BusPoster") == 1, "a bus shelter with a lit poster")
	t.eq(_count(city, "ParkHead"), 3, "three park lamps behind the player")
	t.eq(cfx.lamp_count(), _count(city, "LampHead") + _count(city, "ParkHead") + 1, "an omni under every lamp and park head and one in the shelter")
	var lit0 := CityFx.lit_fraction(0.0)
	t.ok(lit0 > 0.2 and lit0 < 0.5, "about a third of the windows are lit (%.2f)" % lit0)
	var changed := CityFx.lit_changed(0.0, 300.0)
	t.ok(changed > 0.05 and changed < 0.6, "some, not all, have switched five minutes later (%.2f)" % changed)
	var lit5 := CityFx.lit_fraction(300.0)
	t.ok(lit5 > 0.2 and lit5 < 0.5, "still about a third lit later (%.2f) — they never all come on" % lit5)
	t.close(CityFx.lit_fraction(0.0), lit0, 1e-12, "the window rule is pure")
	t.eq(cfx.car_count(), 0, "no car yet")
	cfx.spawn_car()
	t.eq(cfx.car_count(), 1, "a car spawned")
	var car: Node3D = cfx._cars[0]["node"]
	t.eq(car.find_children("*", "StaticBody3D", true, false).size(), 0, "a passing car carries no collider")
	t.ok(car.find_children("*", "SpotLight3D", true, false).size() >= 1, "its headlights are on")
	var p0 := cfx.car_position(0)
	t.ok(absf(p0.z) > CityFx.CAR_EDGE - 1.0, "it starts beyond the edge (z %.1f)" % p0.z)
	t.close(absf(p0.x - CityFx.STREET_X), CityFx.LANE_HALF, 1e-6, "in a lane of the street")
	t.ok(Vector2(p0.x, p0.z).length() < 58.0, "inside the sky cylinder")
	t.ok(absf(sin(car.rotation.y)) < 1e-6, "aligned with the street")
	var v0 := absf(cfx.car_velocity(0))
	t.ok(v0 >= CityFx.CAR_SPEED.x and v0 <= CityFx.CAR_SPEED.y, "city speed (%.1f m/s)" % v0)
	for i in 120:
		cfx._process(1.0 / 60.0)
	t.ok(absf(cfx.car_position(0).z) < absf(p0.z), "it drives inward")
	for i in int(20.0 * 60):
		cfx._process(1.0 / 60.0)
		if cfx.car_count() == 0:
			break
	t.eq(cfx.car_count(), 0, "it crosses and is freed")
	t.ok(cfx.sent() >= 1, "counted")
	cfx.spawn_car()
	cfx.spawn_car()
	cfx.spawn_car()
	t.eq(cfx.car_count(), CityFx.MAX_CARS, "the street holds %d cars at most" % CityFx.MAX_CARS)
	# Determinism: two fresh cities spawn the same first car.
	var c2: Node = load("res://assets/arena/city/city.glb").instantiate()
	var f2 := CityFx.new()
	f2.setup(c2)
	f2.spawn_car()
	var c3: Node = load("res://assets/arena/city/city.glb").instantiate()
	var f3 := CityFx.new()
	f3.setup(c3)
	f3.spawn_car()
	t.eq(f2.car_position(0), f3.car_position(0), "traffic replays identically (seeded RNG)")
	t.close(f2.car_velocity(0), f3.car_velocity(0), 1e-9, "and at the same speed")
	for i in 60:
		f2._process(1.0 / 60.0)
		f3._process(1.0 / 60.0)
	t.eq(f2.car_position(0), f3.car_position(0), "still in step a second later")
	for n in [cfx, f2, f3]:
		n.free()
	for n in [city, c2, c3]:
		n.free()
