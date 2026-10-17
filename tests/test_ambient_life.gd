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
	# The padded back (2026-10-03): egg-crate foam over the panel, the ribbon
	# board housed on top of it, and the return arrows down the lane.
	t.eq(_count(cage, "BackPad"), 1, "the egg-crate foam over the back panel")
	t.eq(_count(cage, "LeagueHousing"), 1, "the ribbon board's housing on the foam")
	t.eq(_count(cage, "DeckArrow"), 2 * ArcadeFx.ARROW_STEPS, "two rows of %d return arrows" % ArcadeFx.ARROW_STEPS)
	# The production pass (design "Arcade Cage Concept" 32a, 2026-10-16): the
	# deck funnel and the ball gate, the hardwood, the rug, the ceiling lights.
	t.eq(ArcadeFx.ARROW_STEPS, 7, "seven arrow steps: the two past the gate went")
	for n in ["DeckFunnel", "GateFrame", "GateMesh0", "GateMesh1", "HallRug", "HallLights", "HallLightWire"]:
		t.ok(cage.find_child(n, true, false) is MeshInstance3D, "the cage glb has %s" % n)
	var gate: Node3D = cage.find_child("BallGate", true, false)
	t.ok(gate != null and absf(gate.position.x - 1.25) < 1e-6, "the gate stands at x 1.25 (the sim's lip)")
	t.eq(_count(cage, "DeckCurb"), 0, "the straight deck curbs are gone (the funnel replaces them)")
	t.eq(cage.find_child("DeckFunnelFill", true, false), null, "no black fill: the gutters' red tops run out to the wall, as the design renders")
	var rc: MeshInstance3D = cage.find_child("RampCurb0", true, false)
	t.ok(rc != null and rc.get_aabb().size.y > 0.15, "the ramp gutters are 18 cm tall")
	var deck_m := (cage.find_child("Deck", true, false) as MeshInstance3D).mesh.surface_get_material(0)
	var ramp_m := (cage.find_child("Ramp", true, false) as MeshInstance3D).mesh.surface_get_material(0)
	t.ok(deck_m != null and deck_m == ramp_m, "the deck and the ramp share the hardwood")
	for gone in ["cage_deck.png", "cage_ramp.png", "cage_mesh.png"]:
		t.ok(not FileAccess.file_exists("res://assets/textures/" + gone), "%s is gone (the hardwood and the slate / galvanised mesh replaced it)" % gone)
	for kept in ["cage_hardwood.png", "cage_mesh_slate.png", "cage_mesh_galv.png", "cage_rug.png", "cage_pad.png", "cage_arrow.png"]:
		t.ok(FileAccess.file_exists("res://assets/textures/" + kept), "%s ships" % kept)
	# The front console (2026-10-04) came out again on 2026-10-07: nothing of it in the glb.
	t.eq(cage.find_child("ConsoleBody", true, false), null, "no console in the cage glb")
	var lface: MeshInstance3D = cage.find_child("LeagueFace", true, false)
	var aabb := lface.get_aabb()
	t.ok(aabb.size.z > 2.3 and aabb.size.z < 2.4, "the ribbon board is full width (%.2f m)" % aabb.size.z)
	t.ok(aabb.size.y > 0.25 and aabb.size.y < 0.28, "…and a touch taller (%.3f m)" % aabb.size.y)
	var afx := ArcadeFx.new()
	t.ok(afx.setup(cage), "ArcadeFx binds the cabinets")
	t.eq(afx.arrow_count(), 2 * ArcadeFx.ARROW_STEPS, "…and the return arrows")
	t.eq(afx.arrow_steps(), ArcadeFx.ARROW_STEPS, "…in %d steps" % ArcadeFx.ARROW_STEPS)
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
	t.ok((cage.find_child("HallLights", true, false) as MeshInstance3D).material_override is StandardMaterial3D, "the ceiling string lights glow unshaded (one mesh, no chase)")
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
	# The return arrows' chase (GO): top of the ramp first, down to the
	# shooter's feet, three passes, then dim again.
	t.ok(not afx.chasing() and afx.arrow_lit(0) == 0.0, "arrows idle dim")
	var arrow_src := FileAccess.get_file_as_string("res://game/court/deck_arrow.gdshader")
	t.ok(arrow_src.contains("led_off") and arrow_src.contains("led_on") and arrow_src.contains("ramp(lit)"), "the chase colours the LEDs: an off-ember to warm-white ramp over lit (design 32a)")
	afx.chase()
	t.ok(afx.chasing() and afx.arrow_lit(0) > 0.99 and afx.arrow_lit(ArcadeFx.ARROW_STEPS - 1) == 0.0, "GO: the top-of-ramp arrow lights first")
	afx._process((ArcadeFx.ARROW_STEPS - 1) * ArcadeFx.CHASE_STAGGER + 0.01)
	t.ok(afx.arrow_lit(ArcadeFx.ARROW_STEPS - 1) > 0.9 and afx.arrow_lit(0) < 0.05, "…and the chase reaches the shooter's feet")
	afx._process(ArcadeFx.CHASE_PASSES * afx.chase_period())
	t.ok(not afx.chasing() and afx.arrow_lit(0) == 0.0 and afx.arrow_lit(4) == 0.0, "after %d passes the arrows go dim" % ArcadeFx.CHASE_PASSES)
	afx.free()
	cage.free()
	# Beach: three tourist groups with arms and umbrellas; birds spawn and cross.
	t.ok(FileAccess.file_exists("res://assets/textures/beach_bird.png"), "bird sheet generated")
	var beach: Node = load("res://assets/arena/beach/beach.glb").instantiate()
	t.eq(_count(beach, "TouristRig", false), 3, "3 tourist groups")
	t.eq(_count(beach, "Towel"), 3, "3 towels")
	t.eq(_count(beach, "Umbrella", false), 2, "2 umbrella rigs")
	# Production pass (design 34a): the umbrellas are one vertex-coloured mesh
	# each, the palms ten PalmRig handles drawn as two MultiMeshes from palm.glb.
	t.eq(_count(beach, "UmbMesh"), 2, "each umbrella is one mesh")
	t.eq(_count(beach, "UmbCanopy") + _count(beach, "UmbPole"), 0, "no cone + pole umbrellas")
	t.eq(_count(beach, "PalmRig", false), 10, "10 palm rigs")
	t.eq(_count(beach, "Palm"), 0, "no palm billboard quads")
	for f in ["beach_bark", "beach_frond", "beach_curb", "beach_dither", "beach_concrete"]:
		t.ok(FileAccess.file_exists("res://assets/textures/%s.png" % f), "%s skin generated" % f)
	t.ok(not FileAccess.file_exists("res://assets/textures/beach_palm.png"), "the palm billboard sheet is gone")
	var palm: Node = load("res://assets/arena/beach/palm.glb").instantiate()
	var fronds := palm.find_child("PalmFronds", true, false) as MeshInstance3D
	t.ok(palm.find_child("PalmTrunk", true, false) is MeshInstance3D and fronds != null, "palm.glb: PalmTrunk + PalmFronds")
	t.ok(fronds != null and not (fronds.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).is_empty(), "the fronds carry their flutter phase in UV2")
	palm.free()
	var bfx := BeachFx.new()
	t.ok(bfx.setup(beach), "BeachFx sets up")
	var umb := beach.find_child("UmbMesh0", true, false) as MeshInstance3D
	t.ok(umb != null and (umb.mesh.surface_get_material(0) as BaseMaterial3D).vertex_color_use_as_albedo, "the umbrellas' gores take their vertex colours")
	t.eq(bfx.palm_count(), 10, "ten palms")
	t.eq(bfx.palm_draw_count(), 2, "…in two draws (trunks, fronds)")
	var trunks := beach.find_child("PalmTrunks", true, false) as MultiMeshInstance3D
	t.ok(trunks != null and trunks.multimesh.instance_count == 10, "PalmTrunks MultiMesh holds 10 instances")
	if trunks != null:
		var buf := trunks.multimesh.buffer
		var rig0 := beach.find_child("PalmRig0", true, false) as Node3D
		# buffer rows: xx yx zx ox | xy yy zy oy | xz yz zz oz (12 floats per instance)
		t.close(buf[3], rig0.position.x, 1e-4, "instance 0 stands at PalmRig0 (x)")
		t.close(buf[11], rig0.position.z, 1e-4, "instance 0 stands at PalmRig0 (z)")
		t.ok(absf(buf[5] - rig0.scale.y) < 1e-3, "…scaled to the rig's height (%.2f)" % rig0.scale.y)
		t.ok(trunks.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "palms cast shadows")
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

	# The pelican: solo, bigger and slower than a gull, low, and freed past the edge.
	t.ok(FileAccess.file_exists("res://assets/textures/beach_pelican.png"), "pelican sheet generated")
	bfx._clear_pelican()   # the loops above ran long enough for its timer to fire
	t.eq(bfx.pelican_count(), 0, "no pelican once cleared")
	bfx.spawn_pelican()
	t.eq(bfx.pelican_count(), 1, "one pelican")
	var pel: MeshInstance3D = bfx._pelican
	t.ok(absf(pel.position.z) > 40.0 and pel.position.y > BeachFx.FLOCK_Y.y, "it enters at the sky's edge, above the gulls' band (y %.1f)" % pel.position.y)
	t.ok(absf(bfx._pelican_vel.z) < BeachFx.BIRD_SPEED * 0.5, "…at less than half a gull's pace")
	var sx := (pel.mesh as QuadMesh).size.x
	t.ok(sx > BeachFx.BIRD_SIZE.x * 1.2 and sx < BeachFx.BIRD_SIZE.x * 1.6, "…a little bigger than a gull, not a lot (%.2f m)" % sx)
	t.ok(float(bfx._pelican_mat.get_shader_parameter("flap_hz")) < 2.0, "…with a lazy flap")
	var pz0 := pel.position.z
	bfx._process(1.0)
	t.ok(absf(bfx._pelican.position.z) < absf(pz0), "it flies inward")
	for i in 60:
		bfx._process(1.0)
		if bfx.pelican_count() == 0:
			break
	t.eq(bfx.pelican_count(), 0, "freed once it has crossed")
	bfx.free()
	beach.free()


## The city: cars cross the street beyond the fence (seeded, freed past the
## edge, no colliders), the facades share one dusk material, the trees billboard.
static func _lights(root: Node) -> int:
	var n := 0
	for d in BeachFx._descendants(root):
		if d is Light3D:
			n += 1
	return n


func _city(t) -> void:
	for path in CityFx.MODELS:
		t.ok(FileAccess.file_exists(path), "vehicle model shipped (%s)" % path.get_file())
	t.ok(FileAccess.file_exists("res://assets/arena/city/city.glb"), "city arena built")
	if not FileAccess.file_exists("res://assets/arena/city/city.glb"):
		return
	var city: Node = load("res://assets/arena/city/city.glb").instantiate()
	t.eq(_count(city, "StreetRig", false), 1, "one street line")
	t.eq(_count(city, "Building"), 1, "the pack's fourteen buildings are one merged Buildings mesh (one draw, 2026-10-16)")
	t.ok(FileAccess.file_exists("res://assets/textures/city_facades.png"), "the facade atlas is conformed")
	t.ok(not FileAccess.file_exists("res://game/court/windows.gdshader"), "the window-light shader is gone (it lagged the phone)")
	t.eq(_count(city, "TreeRig", false), 4, "4 street trees")
	t.ok(_count(city, "FloodHead") >= 4, "floodlight heads at the court's corners")
	t.ok(CosmeticLibrary.get_arena("city").traffic, "the city arena set asks for traffic")
	var cfx := CityFx.new()
	t.ok(cfx.setup(city), "CityFx sets up")
	t.eq(cfx.facade_count(), _count(city, "Building") + _count(city, "Windows"), "every building is bound to the dusk material")
	t.ok(cfx.facade_material_count() <= 3, "a shared material per texture, no more (%d)" % cfx.facade_material_count())
	t.eq(_lights(city), 0, "midday: no spot or omni lights hung in the city (they lagged the phone)")
	t.eq(_count(city, "LampHead"), 1, "the street lamps' heads are one mesh")
	t.eq(_count(city, "LampGlow"), 1, "…and their bulb glows one (hidden at midday)")
	for n in ["LaneDashes", "FenceWork", "LampPosts", "Roads", "Sidewalks", "SidewalksFar", "Kerbs", "SpeakerScrews", "SpeakerDrivers", "ScoreVents", "FloodRigs"]:
		t.ok(city.find_child(n, true, false) is MeshInstance3D, "merged %s" % n)
	t.ok(_count(city, "LaneDash") == 1 and _count(city, "FencePost") == 0 and _count(city, "ScoreVent") == 1, "the repeated pieces are gone as nodes")
	var meshes := 0
	for c in BeachFx._descendants(city):
		if c is MeshInstance3D:
			meshes += 1
	t.ok(meshes < 80, "the city is under 80 mesh nodes (%d; 263 before)" % meshes)
	# The dressing with the set: the clouds, no shadows from the backdrop, the cars held ready.
	var city2: Node = load("res://assets/arena/city/city.glb").instantiate()
	var cfx2 := CityFx.new()
	t.ok(cfx2.setup(city2, CosmeticLibrary.get_arena("city")), "CityFx sets up with the set")
	t.ok(cfx2.sky_resource() is Sky and (cfx2.sky_resource() as Sky).sky_material is ShaderMaterial, "the city has the park's clouds (AreaSky)")
	t.ok(not (city2.find_child("Sky", true, false) as MeshInstance3D).visible, "…its painted dome hidden under them")
	var mat := (cfx2.sky_resource() as Sky).sky_material as ShaderMaterial
	t.ok(Vector3(mat.get_shader_parameter("mid_color")).is_equal_approx(Vector3(0.6, 0.76, 0.95)), "…in the city's own blue")
	t.eq((city2.find_child("Buildings", true, false) as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the buildings cast no shadow")
	t.eq((city2.find_child("Roads", true, false) as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "…nor the road")
	t.eq((city2.find_child("FenceWork", true, false) as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the fence still does")
	t.eq(cfx2.scene_count(), CityFx.MODELS.size(), "every vehicle scene is loaded once, up front")
	cfx2.free()
	city2.free()
	t.eq(_count(city, "BusSign"), 1, "the shelter's roof sign")
	t.ok(_count(city, "BusStop", false) == 1 and _count(city, "BusPoster") == 1, "a bus shelter with a lit poster")
	t.eq(_count(city, "ParkHead"), 1, "the three park lamps behind the player, one merged mesh")
	t.eq(_count(city, "Wall"), 0, "no knee wall: the fence runs to the ground")
	t.ok(_count(city, "FenceFoot") == 0 and city.find_child("FenceWork", true, false) != null, "the fence's posts, corners, feet and rails are one FenceWork mesh")
	t.ok(city.find_child("Fence", true, false) is MeshInstance3D and city.find_child("FenceBack", true, false) == null, "one chain-link loop (black, all four sides)")
	# Pigeons: a loose bunch crosses over the street now and then (a
	# different bird from the beach's gulls), glides included, freed past the edge.
	t.ok(FileAccess.file_exists("res://assets/textures/city_pigeon.png"), "pigeon sheet generated")
	t.eq(cfx.pigeon_count(), 0, "no pigeons at first")
	cfx.spawn_pigeons()
	var np := cfx.pigeon_count()
	t.ok(np >= 4 and np <= 7, "a bunch of 4-7 pigeons (%d)" % np)
	var pz: float = cfx._pigeons[0].position.z
	var px: float = cfx._pigeons[0].position.x
	t.ok(px >= CityFx.PIGEON_X.x and px <= CityFx.PIGEON_X.y, "over the street (%.1f)" % px)
	t.ok(cfx._pigeons[0].position.y < BeachFx.FLOCK_Y.x + 3.0, "lower than the gulls")
	for i in 60:
		cfx._step_pigeons(1.0 / 60.0)
	t.ok(absf(cfx._pigeons[0].position.z) < absf(pz), "pigeons fly inward")
	var glided := false
	for i in 60 * 20:
		cfx._step_pigeons(1.0 / 60.0)
		for g in cfx._pigeon_gliding:
			if g:
				glided = true
		if cfx.pigeon_count() == 0:
			break
	t.ok(glided, "some pigeons glided on the way")
	t.eq(cfx.pigeon_count(), 0, "the bunch is freed once it has crossed")
	# Rooftop smoke: a chimney on the grand block, a persistent plume of a few
	# cheap billboard puffs rising, drifting, growing and fading on the clock.
	t.ok(FileAccess.file_exists("res://assets/textures/city_smoke.png"), "smoke puff generated")
	t.eq(_count(city, "Chimney"), 1, "a chimney with its cap on the roof across the street (one mesh)")
	t.ok(city.find_child("SmokeStack", true, false) != null, "the SmokeStack empty")
	t.eq(cfx.smoke_count(), CityFx.SMOKE_N, "a handful of puffs, no particles")
	cfx._step_smoke()
	var ys := []
	for i in CityFx.SMOKE_N:
		ys.push_back(cfx._smoke[i].position.y)
	ys.sort()
	t.ok(ys[0] >= 0.0 and ys[ys.size() - 1] <= CityFx.SMOKE_RISE + 0.01, "puffs sit between the stack and the top of the plume")
	t.ok(ys[ys.size() - 1] - ys[0] > CityFx.SMOKE_RISE * 0.5, "…spread along it")
	var young := -1
	for i in CityFx.SMOKE_N:
		if young < 0 or cfx.smoke_phase(i) < cfx.smoke_phase(young):
			young = i
	var old := -1
	for i in CityFx.SMOKE_N:
		if old < 0 or cfx.smoke_phase(i) > cfx.smoke_phase(old):
			old = i
	t.ok(cfx._smoke[old].scale.x > cfx._smoke[young].scale.x, "a puff grows as it rises")
	t.ok(float(cfx._smoke_mats[old].get_shader_parameter("alpha")) < float(cfx._smoke_mats[young].get_shader_parameter("alpha")) or cfx.smoke_phase(young) < 0.05, "…and fades")
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
	t.ok(v0 >= CityFx.CAR_SPEED.x and v0 <= CityFx.CAR_SPEED.y * CityFx.CAR_PACE.y, "a roll (%.1f m/s)" % v0)
	# Every car has its own cruising pace, so a stream is never one speed.
	var paces := {}
	var pf := CityFx.new()
	pf.setup(load("res://assets/arena/city/city.glb").instantiate())
	for i in 6:
		pf.spawn_car(1.0 if i % 2 == 0 else -1.0)
		for c in pf._cars:
			paces["%.2f" % float(c["pace"])] = true
		pf._cars.clear()
	t.ok(paces.size() >= 3, "cars cruise at different paces (%d distinct of 6)" % paces.size())
	pf.free()
	for i in 600:
		cfx._process(1.0 / 60.0)
	t.ok(absf(cfx.car_position(0).z) < absf(p0.z), "it rolls inward")
	# Light traffic: a car now and then, never more than the cap, each keeping
	# its distance from whatever is ahead.
	for i in int(30.0 * 60):
		cfx._process(1.0 / 60.0)
	t.ok(cfx.car_count() >= 1 and cfx.car_count() <= CityFx.MAX_CARS, "a car or two on the street (%d)" % cfx.car_count())
	var min_gap := INF
	for a in cfx.car_count():
		min_gap = minf(min_gap, cfx.gap_ahead(a))
	t.ok(min_gap >= CityFx.STOP_GAP - 0.6, "never closer than the stop gap, bumper to bumper (%.1f m)" % min_gap)
	# Every stop has a reason: a car stopped mid-road always has something
	# within its stop gap ahead — the car in front, or the lane's red signal.
	var stopped := false
	var moving := false
	var speeds_differ := false
	# (A car whose obstacle just vanished — the light went green, the car ahead
	# left view — needs a few frames to get rolling: only a stop that STAYS
	# unexplained for over 0.1 s counts.)
	var unexplained := 0
	var saw_red := false
	var idle_frames := {}
	for i in int(60.0 * 60):
		cfx._process(1.0 / 60.0)
		var lo := INF
		var hi := 0.0
		for a in cfx.car_count():
			var sp := absf(cfx.car_velocity(a))
			lo = minf(lo, sp)
			hi = maxf(hi, sp)
			var node: Node = cfx._cars[a]["node"]
			if sp < 0.05 and cfx.gap_ahead(a) > CityFx.STOP_GAP + CityFx.FOLLOW_GAP + 0.5:
				idle_frames[node] = int(idle_frames.get(node, 0)) + 1
				if int(idle_frames[node]) > 6:
					unexplained += 1
			else:
				idle_frames[node] = 0
		if cfx.signal_red(1.0) or cfx.signal_red(-1.0):
			saw_red = true
		if lo < 0.05:
			stopped = true
		if hi > 2.0:
			moving = true
		if hi - lo > 1.0:
			speeds_differ = true
	t.ok(saw_red, "a lane's exit signal went red")
	t.ok(moving, "cars roll past (%s %s)" % [stopped, speeds_differ])
	t.eq(unexplained, 0, "no car ever stopped with open road ahead")
	t.ok(cfx.car_count() <= CityFx.MAX_CARS, "under the cap (%d)" % cfx.car_count())
	var spots := 0
	for c in cfx._cars:
		if c["spot"]:
			spots += 1
	t.ok(spots <= CityFx.HEADLIGHT_SPOTS, "at most %d real headlight spots (%d)" % [CityFx.HEADLIGHT_SPOTS, spots])
	t.ok(cfx.sent() >= 4, "counted")
	# An even mix: the deck hands out every model before any repeats, and
	# never the same model twice running.
	var f4 := CityFx.new()
	var seen: Array[int] = []
	var prev := -1
	var twice_running := false
	for i in CityFx.MODELS.size() * 3:
		var m := f4._draw_model()
		if m == prev:
			twice_running = true
		prev = m
		seen.push_back(m)
	t.ok(not twice_running, "no model follows itself")
	for k in 3:
		var deck := seen.slice(k * CityFx.MODELS.size(), (k + 1) * CityFx.MODELS.size())
		deck.sort()
		t.eq(deck, range(CityFx.MODELS.size()), "deck %d is every model once" % k)
	f4.free()
	var clear_before := cfx.lane_clear(1.0)
	var before_spawn := cfx.car_count()
	cfx.spawn_car(1.0)
	t.ok(cfx.car_count() == before_spawn + (1 if clear_before and before_spawn < CityFx.MAX_CARS else 0), "a car joins only when its lane's edge is clear")
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
