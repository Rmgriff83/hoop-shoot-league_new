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
	t.eq(bfx.arm_count(), 3, "3 wavable arms")
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
	# Arm wave: force one and check the arm moves then returns to rest.
	bfx._next_wave = 0.0
	bfx._process(1.0 / 60.0)
	bfx._process(0.5)
	var k: int = bfx._wave_arm
	t.ok(k >= 0 and bfx._arms[k].rotation != bfx._arm_rest[k], "an arm is waving")
	bfx._process(3.0)
	t.eq(bfx._arms[k].rotation, bfx._arm_rest[k], "arm back at rest after the wave")
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

	t.ok(not bfx.has_plane(), "no plane at first")
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
