extends RefCounted
## Cosmetic sets: manifests validate, the library finds them, a set configures
## the net feel and LED palette, and Sfx routes contact sounds by ownership
## (hoop owns rim/board/make/miss, ball owns floor bounces), loading on demand.


func run(t) -> void:
	_street_and_arenas(t)
	# Manifests + library.
	var hoop := CosmeticLibrary.get_hoop("classic")
	var ball := CosmeticLibrary.get_ball("classic")
	t.ok(hoop != null and ball != null, "classic hoop and ball sets load")
	t.eq(hoop.validate(), PackedStringArray(), "classic hoop references only existing files")
	t.eq(ball.validate(), PackedStringArray(), "classic ball references only existing files")
	t.eq(hoop.make_clips.size(), 7, "classic hoop has 7 make clips")
	t.eq(hoop.miss_clips.size(), 5, "classic hoop has 5 miss clips")
	t.ok(CosmeticLibrary.starter_hoop() == hoop and CosmeticLibrary.starter_ball() == ball, "classic sets are the starters")
	t.ok(CosmeticLibrary.get_hoop("nope") == null, "unknown id → null")

	# Every registered ball. CosmeticLibrary.balls() filters with `if s is
	# BallSet`, so a .tres that fails to load yields null, fails that test and is
	# SILENTLY dropped — no error, no warning, the ball just does not exist.
	# Across twenty generated resources that is the likeliest failure, and this
	# is the only thing that would catch it.
	var registered := CosmeticLibrary.BALLS.size()
	var loaded := CosmeticLibrary.balls()
	t.eq(loaded.size(), registered,
		"every registered ball loads as a BallSet (%d of %d)" % [loaded.size(), registered])
	var ids := {}
	var free_ids: Array[String] = []
	for b in loaded:
		t.eq(b.validate(), PackedStringArray(), "%s references only existing files" % b.id)
		t.ok(b.skin_path != "", "%s has a skin" % b.id)
		t.ok(not ids.has(b.id), "ball id %s is unique" % b.id)
		ids[b.id] = true
		if b.price_coins == 0:
			free_ids.push_back(b.id)
	# starter_ball() returns the FIRST set priced 0, so a second free ball would
	# silently steal the starter slot out from under classic.
	t.eq(free_ids, ["classic"] as Array[String], "classic is the only free ball")
	var broken := HoopSet.new()
	broken.id = "x"
	broken.model_path = "res://assets/hoops/x/missing.glb"
	t.eq(broken.validate().size(), 1, "validate reports a missing model")

	# Net feel: set defaults match NetSim defaults; configure applies.
	var ns := NetSim.new()
	t.close(HoopSet.new().net_stiffness, ns.stiffness, 0.0, "set default stiffness = NetSim default")
	t.close(HoopSet.new().net_damping, ns.damping, 0.0, "set default damping = NetSim default")
	var soft := HoopSet.new()
	soft.net_stiffness = 0.5
	soft.net_friction = 0.2
	ns.configure(soft)
	t.close(ns.stiffness, 0.5, 0.0, "configure applies stiffness")
	t.close(ns.ball_friction, 0.2, 0.0, "configure applies friction")
	ns.free()

	# LED palette from the set.
	var led := LedBoard.new()
	var neon := HoopSet.new()
	neon.led_color = Color8(0, 255, 120)
	neon.band_flash_color = Color8(0, 200, 255)
	led.set_palette(neon)
	t.eq(led.on_color, Color8(0, 255, 120), "palette sets the on colour")
	t.eq(led.band_flash_color, Color8(0, 200, 255), "palette sets the band flash colour")
	led.set_text("HI")
	t.eq(led._color, Color8(0, 255, 120), "default text colour follows the palette")
	led.free()

	# Sfx routing (the autoload is live in the test runner).
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	t.ok(sfx != null, "Sfx autoload present")
	if sfx != null:
		sfx.load_hoop_set(hoop)
		sfx.load_ball_set(ball)
		t.eq(sfx.hoop_clip_count("make"), 7, "hoop set loaded 7 make streams")
		t.eq(sfx.hoop_clip_count("miss"), 5, "hoop set loaded 5 miss streams")
		t.eq(sfx.contact_source("rim"), "generic", "classic hoop has no rim override → generic")
		t.eq(sfx.contact_source("floor"), "ball", "classic ball owns floor contacts with its recorded bounces")
		t.eq(sfx.ball_clip_count("bounce"), 15, "classic ball loaded 15 bounce streams")
		# Pole hits are WORLD sounds, not a cosmetic set's: recorded clips that
		# play at any pole, whichever hoop and ball are equipped.
		t.eq(sfx.contact_source("pole"), "generic", "pole contacts are generic, not owned by a set")
		for i in 3:
			t.ok(FileAccess.file_exists("res://assets/audio/fx/pole_sound_%d.wav" % (i + 1)),
				"pole_sound_%d ships" % (i + 1))
		# Same non-repeating picker as the bounces. Only THREE clips here, so the
		# distinct count tops out at 3 — don't copy the bounce test's >= 8.
		sfx.gain_db = -80.0
		var p_last := -1
		var p_repeats := 0
		var p_seen := {}
		for i in 40:
			sfx.contact("pole", 4.0)
			var pidx := int(sfx._last.get("generic:pole", -1))
			if pidx == p_last:
				p_repeats += 1
			p_seen[pidx] = true
			p_last = pidx
		sfx.gain_db = 0.0
		t.eq(p_repeats, 0, "a pole hit never repeats the previous clip")
		t.eq(p_seen.size(), 3, "pole hits use all three clips (%d distinct in 40)" % p_seen.size())
		# Random, never the same clip twice running (the hoop swish picker).
		sfx.gain_db = -80.0
		var last := -1
		var repeats := 0
		var seen := {}
		for i in 40:
			sfx.contact("floor", 4.0)
			var idx := int(sfx._last.get("ball:bounce", -1))
			if idx == last:
				repeats += 1
			seen[idx] = true
			last = idx
		sfx.gain_db = 0.0
		t.eq(repeats, 0, "a bounce never repeats the previous clip")
		t.ok(seen.size() >= 8, "bounces spread across the clips (%d distinct in 40)" % seen.size())
		# Any number of clips makes a ball own its bounces (not only three).
		var loud := BallSet.new()
		loud.id = "loud"
		loud.bounce_clips = PackedStringArray(["res://assets/audio/bounce_0.wav", "res://assets/audio/bounce_1.wav"])
		sfx.load_ball_set(loud)
		t.eq(sfx.contact_source("floor"), "ball", "ball set with 2 bounce clips owns floor contacts")
		t.eq(sfx.ball_id(), "loud", "active ball id")
		# A second hoop replaces the first's table entirely.
		var other := HoopSet.new()
		other.id = "other"
		other.make_clips = PackedStringArray(["res://assets/audio/swish.wav", "res://assets/audio/net.wav"])
		other.rim_clips = PackedStringArray([
			"res://assets/audio/rim_clang_0.wav", "res://assets/audio/rim_clang_1.wav", "res://assets/audio/rim_clang_2.wav"])
		sfx.load_hoop_set(other)
		t.eq(sfx.hoop_clip_count("make"), 2, "swapping hoops replaces the make table")
		t.eq(sfx.hoop_clip_count("miss"), 0, "the previous hoop's miss clips are gone")
		t.eq(sfx.contact_source("rim"), "hoop", "hoop set with 3 rim clips owns rim contacts")
		# Restore the real sets for anything that runs after this test.
		sfx.load_hoop_set(hoop)
		sfx.load_ball_set(ball)


func _street_and_arenas(t) -> void:
	var street := CosmeticLibrary.get_hoop("street")
	t.ok(street != null, "street hoop set resolves")
	if street != null:
		t.eq(street.validate(), PackedStringArray(), "street set references only files that exist")
		t.close(street.model_board_h, 1.05, 1e-12, "street board authored at regulation height")
		t.close(street.model_board_half_w, 0.915, 1e-12, "street board authored at regulation width")
		t.eq(street.make_clips.size(), 7, "street reuses the 7 make clips")
		t.eq(street.net_kind, "nylon", "the street hoop hangs nylon")
		t.eq(street.miss_clips.size(), 5, "street reuses the 5 miss clips")
	var chain := CosmeticLibrary.get_hoop("chain")
	t.ok(chain != null, "chain hoop set resolves")
	if chain != null:
		t.eq(chain.validate(), PackedStringArray(), "chain set references only files that exist")
		t.eq(chain.net_kind, "chain", "it hangs a chain")
		t.ok(chain.net_stiffness > 0.9 and chain.net_friction < 0.5, "links: near-inextensible, little grip")
		t.close(chain.model_board_h, 1.05, 1e-12, "regulation board")
		t.eq(chain.make_clips.size(), 3, "three chain swishes")
		var hoop_scene: PackedScene = load(chain.model_path)
		var inst: Node = hoop_scene.instantiate()
		t.ok(inst.find_child("Gooseneck", true, false) != null, "the chain hoop stands on its own gooseneck")
		var netm: MeshInstance3D = inst.find_child("Net", true, false)
		t.ok(inst.find_child("NetRing", true, false) == null and netm != null, "the chain net is open at the bottom (no ring)")
		if netm != null:
			t.ok(netm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() >= 60, "the chain lattice has its 5 rings of 12")
		t.ok(inst.find_child("BoardArm", true, false) == null, "no street arm on it")
		inst.free()
		t.ok(chain.price_coins > 0, "not a starter")
		var bad := HoopSet.new()
		bad.id = "y"
		bad.net_kind = "rope"
		t.ok(bad.validate().size() == 1, "an unknown net kind fails validation")
		var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
		if sfx != null:
			sfx.load_hoop_set(chain)
			t.eq(sfx.net_kind(), "chain", "Sfx knows the chain")
			t.eq(sfx.hoop_clip_count("make"), 3, "and its swishes")
			sfx.load_hoop_set(CosmeticLibrary.starter_hoop())
			t.eq(sfx.net_kind(), "nylon", "back to nylon with the classic")
	t.eq(CosmeticLibrary.starter_hoop().id, "classic", "the classic is still the starter hoop")
	t.close(HoopSet.new().model_board_h, 0.76, 1e-12, "default board dims are the classic's")
	t.eq(HoopSet.new().miss_anim, "", "a bare set has no miss clip")
	t.eq(CosmeticLibrary.get_hoop("classic").miss_anim, "Miss", "classic names its rim reaction")
	if street != null:
		t.eq(street.miss_anim, "Miss", "street names its rim reaction")
	t.eq(CosmeticLibrary.starter_hoop().id, "classic", "classic is still the starter hoop")
	var cage := CosmeticLibrary.get_arena("cage")
	var beach := CosmeticLibrary.get_arena("beach")
	t.ok(cage != null and beach != null, "both arena sets resolve")
	if cage != null and beach != null:
		t.eq(cage.validate(), PackedStringArray(), "cage arena files exist")
		t.eq(beach.validate(), PackedStringArray(), "beach arena files exist")
		t.eq(CosmeticLibrary.starter_arena().id, "cage", "cage is the starter arena")
		t.ok(beach.ocean and not cage.ocean, "only the beach has an ocean")
		var city := CosmeticLibrary.get_arena("city")
		t.ok(city != null and city.validate() == PackedStringArray() and city.traffic and not beach.traffic and not cage.traffic,
			"the city resolves, validates, and is the one with traffic")
		t.ok(not cage.emissive_nodes.has("Marquee"), "the HOOP SHOOT sign is gone (string lights replace it)")
		t.ok(beach.sun_rotation_deg.y > 0.0 and beach.sun_rotation_deg.y < 60.0 and beach.sun_rotation_deg.x < 0.0,
			"beach sun sits low in the east-north-east (yaw %.1f)" % beach.sun_rotation_deg.y)
		t.ok(beach.sun_shadows and beach.fog_enabled and beach.fill_energy > 0.0, "beach has shadows, haze and a fill light")
		for a in [cage, beach]:
			t.ok(a.title_period_s > 0.0 and a.title_fov > 0.0, "%s carries a home-card pan pose" % a.id)

