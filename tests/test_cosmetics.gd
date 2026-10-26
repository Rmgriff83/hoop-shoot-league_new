extends RefCounted
## Cosmetic sets: manifests validate, the library finds them, a set configures
## the net feel and LED palette, and Sfx routes contact sounds by ownership
## (hoop owns rim/board/make/miss, ball owns floor bounces), loading on demand.


func run(t) -> void:
	_wall_sound(t)
	_net_overrides(t)
	_nets(t)
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
	var per_rarity := {}
	for b in loaded:
		t.eq(b.validate(), PackedStringArray(), "%s references only existing files" % b.id)
		t.ok(b.skin_path != "", "%s has a skin" % b.id)
		t.ok(not ids.has(b.id), "ball id %s is unique" % b.id)
		ids[b.id] = true
		# Balls are PEGGY prizes (docs/LOCKER.md): never priced, always rated.
		t.eq(b.price_coins, 0, "%s is unpriced" % b.id)
		t.ok(PeggyPrizes.RARITIES.has(b.rarity), "%s has a PEGGY rarity (%s)" % [b.id, b.rarity])
		per_rarity[b.rarity] = int(per_rarity.get(b.rarity, 0)) + 1
	# starter_ball() returns the FIRST set priced 0: classic must stay first.
	t.eq(loaded[0].id, "classic", "classic is the first ball, so it is the starter")
	t.eq(loaded.size(), 91, "the four-tier roster: 47 + Ross's 44 from the Ball Roster design, 2026-10-25 (%d)" % loaded.size())
	t.eq(per_rarity, {"common": 16, "rare": 24, "epic": 33, "legend": 18}, "the design's rarity counts")
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balls/ball_manifest.json"))
	var listed: Array = []
	for b in loaded:
		listed.push_back(b.id)
	var order: Array = []
	for r in manifest:
		order.push_back(str(r["id"]))
	t.eq(listed, order, "the library lists the manifest's balls in its order")
	var skins_ok := true
	for b in loaded:
		if not ResourceLoader.exists(b.skin_path) or not ResourceLoader.exists("res://assets/textures/balls/thumbs/%s.png" % b.id):
			skins_ok = false
	t.ok(skins_ok, "every ball has its skin and its locker thumbnail")
	for nid in ["pink", "speckle_navy", "leopard_neon", "galaxy_aqua", "mosaic_red", "frankenstein"]:
		t.ok(CosmeticLibrary.get_ball(nid) != null, "%s is in" % nid)
	for r in PeggyPrizes.RARITIES:
		t.ok(int(per_rarity.get(r, 0)) >= 8, "a bunch of %s balls (%d)" % [r, int(per_rarity.get(r, 0))])
	t.eq(CosmeticLibrary.get_ball("classic").rarity, "common", "classic is common")
	t.eq(CosmeticLibrary.get_ball("pumpkin").rarity, "legend", "the pumpkin is a legend")
	var broken := HoopSet.new()
	broken.id = "x"
	broken.model_path = "res://assets/hoops/x/missing.glb"
	t.eq(broken.validate().size(), 1, "validate reports a missing model")

	# Net feel: set defaults match NetSim defaults; configure applies.
	var ns := NetSim.new()
	var hs := HoopSet.new()
	t.close(hs.net_stiffness, ns.stiffness, 0.0, "set default stiffness = NetSim default")
	t.close(hs.net_damping, ns.damping, 0.0, "set default damping = NetSim default")
	t.close(hs.net_rest_spring, ns.rest_spring, 0.0, "set default rest spring = NetSim default")
	t.close(hs.net_rest_pull, ns.rest_pull, 0.0, "set default rest pull = NetSim default")
	t.close(hs.net_tail_mass, ns.tail_mass, 0.0, "set default tail mass = NetSim default")
	t.close(hs.net_friction, ns.ball_friction, 0.0, "set default friction = NetSim default")
	t.close(hs.net_kick, ns.kick_speed, 0.0, "set default kick = NetSim default")
	t.close(hs.net_grab_band, ns.grab_band, 0.0, "set default grab band = NetSim default")
	t.close(hs.net_grab_pull, ns.grab_pull, 0.0, "set default grab pull = NetSim default")
	# The chain hoop's own feel (Ross's 2026-10-14 lab set, docs/BLENDER_101.md §29).
	var chain: HoopSet = load("res://assets/hoops/chain/hoop_set.tres")
	t.eq(chain.net_kind, "chain", "chain set hangs a chain")
	t.close(chain.net_stiffness, 0.22, 0.0, "chain: stiffness 0.22")
	t.close(chain.net_damping, 0.9601, 0.0, "chain: damping 0.9601")
	t.close(chain.net_rest_spring, 25.0, 0.0, "chain: rest spring 25")
	t.close(chain.net_rest_pull, 0.007, 0.0, "chain: rest pull 0.007")
	t.close(chain.net_tail_mass, 0.5, 0.0, "chain: tail 0.5")
	t.close(chain.net_kick, 0.6, 0.0, "chain: kick 0.6")
	t.close(chain.net_grab_band, 0.02, 0.0, "chain: grab band 0.02")
	t.close(chain.net_grab_pull, 0.22, 0.0, "chain: grab pull 0.22")
	t.close(chain.net_friction, 0.23, 0.0, "chain: friction 0.23")
	# Ross's 2026-10-14 cotton set (docs/BLENDER_101.md §28).
	t.close(hs.net_rest_spring, 0.0, 0.0, "cotton: no rest spring")
	t.close(hs.net_tail_mass, 0.5, 0.0, "cotton: light tail")
	t.close(hs.net_kick, 4.7, 0.0, "cotton: hard kick")
	t.close(hs.net_friction, 0.09, 0.0, "cotton: little spin grab")
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


## The net styles (docs/LOCKER.md → NETS): the stock pair flagged, every
## style a free PEGGY prize with a body of its kind.
func _nets(t) -> void:
	var all := CosmeticLibrary.nets()
	t.eq(all.size(), CosmeticLibrary.NETS.size(), "every net manifest loads (%d)" % all.size())
	var ids := []
	for n in all:
		t.eq(n.validate(), PackedStringArray(), "net %s validates" % n.id)
		t.ok(n.kind in NetSet.KINDS, "net %s has a kind (%s)" % [n.id, n.kind])
		t.ok(NetBodies.has_style(n.body_style()) and NetBodies.kind_of(n.body_style()) == n.kind, "net %s has a body of its kind" % n.id)
		t.ok(not ids.has(n.id), "net id %s is unique" % n.id)
		ids.push_back(n.id)
	t.eq(ids, ["cotton", "chain", "jack", "ladder", "wool", "neon_yellow", "neon_orange", "rwb", "tattered", "neon_blue", "neon_purple", "wool_ocean", "wool_ember", "rasta"], "the fourteen nets, stock first (Ross's Net Roster, 2026-10-25)")
	t.ok(CosmeticLibrary.get_net("rwb").kind == "cotton" and CosmeticLibrary.get_net("rwb").body_style() == "rwb", "the red white blue net is a cotton with its own body")
	for nid in ["neon_yellow", "neon_orange"]:
		var neon := CosmeticLibrary.get_net(nid)
		t.ok(neon.kind == "cotton" and neon.body_style() == "cotton" and neon.tint != Color.WHITE and not neon.stock, "%s is the cotton body, tinted, a prize" % nid)
	t.ok(not CosmeticLibrary.get_net("wool").stock and CosmeticLibrary.get_net("wool").kind == "cotton", "the wool net is a cotton prize")
	for n2 in all:
		t.eq(n2.price_coins, 0, "net %s is never bought (price 0)" % n2.id)
	t.eq(CosmeticLibrary.nets_of_kind("cotton").size(), 11, "eleven cotton styles")
	t.ok(CosmeticLibrary.get_net("tattered").kind == "cotton" and CosmeticLibrary.get_net("tattered").body_style() == "tattered", "tattered is a cotton with its own worn body (26d)")
	t.ok(CosmeticLibrary.get_net("cotton").stock, "cotton is the stock cotton")
	t.ok(CosmeticLibrary.get_net("chain").stock, "the stock chain is stock")
	t.ok(not CosmeticLibrary.get_net("jack").stock and CosmeticLibrary.get_net("jack").kind == "chain", "the jack chain is a chain prize")
	t.ok(not CosmeticLibrary.get_net("ladder").stock and CosmeticLibrary.get_net("ladder").kind == "chain", "the ladder chain is a chain prize")
	t.eq(CosmeticLibrary.stock_net("cotton").id, "cotton", "cotton's stock net")
	t.eq(CosmeticLibrary.stock_net("chain").id, "chain", "chain's stock net")
	t.eq(CosmeticLibrary.nets_of_kind("chain").size(), 3, "three chain styles")
	t.eq(CosmeticLibrary.stock_nets().size(), 2, "two stock nets (the flag, not the price)")
	# A kit off the wire resolves against this catalog; anything unknown is the court's stock.
	var rk := CosmeticLibrary.resolve_kit({"v": 1, "ball": "galaxy", "net": "rwb"}, "cotton")
	t.eq(rk["ball"].id, "galaxy", "resolve_kit: a known ball")
	t.eq(rk["net"].id, "rwb", "…a known net")
	t.eq(rk["hoop"], null, "…no hoop named: the court keeps its own")
	var rk2 := CosmeticLibrary.resolve_kit({"v": 1, "ball": "no_such_ball", "net": "no_such_net", "hoop": "no_such_hoop"}, "chain")
	t.eq(rk2["ball"].id, CosmeticLibrary.starter_ball().id, "…an unknown ball → the starter")
	t.eq(rk2["net"].id, "chain", "…an unknown net → the court's stock kind")
	t.eq(rk2["hoop"], null, "…an unknown hoop → none")
	var rk3 := CosmeticLibrary.resolve_kit({}, "cotton")
	t.eq([rk3["ball"].id, rk3["net"].id], [CosmeticLibrary.starter_ball().id, "cotton"], "…an empty kit → the stock pair")
	t.eq(CosmeticLibrary.get_net("cotton").tint, Color.WHITE, "the stock cotton is untinted")
	t.eq(NetSet.kind_of_hoop(CosmeticLibrary.get_hoop("classic")), "cotton", "a nylon hoop hangs cotton")
	t.eq(NetSet.kind_of_hoop(CosmeticLibrary.get_hoop("chain")), "chain", "the steel rim hangs chain")
	t.ok(CosmeticLibrary.get_net("nope") == null, "an unknown net is null")
	var bad := NetSet.new()
	bad.id = "x"
	bad.kind = "rope"
	bad.style = "cotton"
	t.eq(bad.validate().size(), 2, "a rope net fails validation (kind, and cotton is not rope)")
	var wrong := NetSet.new()
	wrong.id = "y"
	wrong.kind = "cotton"
	wrong.style = "jack"
	t.eq(wrong.validate().size(), 1, "a cotton net cannot wear a chain body")


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
		t.ok(chain.net_stiffness < 0.5 and chain.net_friction < 0.5, "links: Ross's 2026-10-14 chain set, little grip")
		t.close(chain.model_board_h, 1.05, 1e-12, "regulation board")
		# Four recorded chain swishes (Ross's 2026-10-03 cuts joined the first);
		# Sfx.make() picks one at random, never the same twice running.
		t.eq(chain.make_clips.size(), 4, "the chain's four recorded swishes")
		for c in chain.make_clips:
			t.ok(str(c).begins_with("res://assets/hoops/chain/sfx/swish_") and load(str(c)) is AudioStream, "%s is a chain swish that loads" % str(c).get_file())
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
			t.ok(sfx.hoop_clip_count("make") >= 1, "and its swishes")
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
		var park := CosmeticLibrary.get_arena("park")
		t.ok(park != null and park.validate() == PackedStringArray() and park.snow and park.sky == "partly_cloudy" and park.parked_cars.size() == 1 and park.tree_layout != "",
			"the park resolves, validates, snows, has a sky, one parked car and a tree layout")
		t.ok(park != null and not park.traffic and not park.ocean and park.title_stars == 3, "…and nothing of the other areas' life")
		t.ok(park != null and park.sun_shadows and absf(park.shadow_distance - 20.0) < 1e-9 and park.shadow_size == 1024 and absf(park.render_scale - 1.0) < 1e-9, "the park runs lighter: 20 m shadows in a 1024 map, the 3D still full-res (0.7 blurred it)")
		for a in [cage, beach]:
			t.ok(a != null and absf(a.shadow_distance - 30.0) < 1e-9 and a.shadow_size == 2048 and absf(a.render_scale - 1.0) < 1e-9, "%s keeps the full shadows and scale" % (a.id if a != null else "?"))
		var city_set := CosmeticLibrary.get_arena("city")
		t.ok(city_set != null and absf(city_set.shadow_distance - 20.0) < 1e-9 and city_set.shadow_size == 1024 and absf(city_set.render_scale - 1.0) < 1e-9, "the city runs lighter too: 20 m shadows in a 1024 map, full-res")
		t.ok(city_set != null and city_set.sky == "partly_cloudy" and city_set.sky_mid.is_equal_approx(city_set.background_color) and city_set.sky_horizon.is_equal_approx(city_set.fog_color), "…with the clouds in its own blue and haze")
		t.ok(city_set != null and not city_set.emissive_nodes.has("Sky"), "…its painted dome no longer lit (hidden)")
		t.ok(park != null and park.sky_top.is_equal_approx(Color(0.30, 0.52, 0.84)) and park.sky_sun_dir.is_equal_approx(Vector3(-0.65204, 0.51232, -0.55890)), "the park keeps the design's palette and sun")
		var park_hoop := CosmeticLibrary.get_hoop("park")
		t.ok(park_hoop != null and park_hoop.validate() == PackedStringArray() and park_hoop.net_kind == "nylon", "the park hoop resolves and hangs nylon")
		t.close(park_hoop.model_board_half_w, 0.70, 1e-12, "…on the slim 1.40 m board")
		t.ok(beach.sun_rotation_deg.y > 0.0 and beach.sun_rotation_deg.y < 60.0 and beach.sun_rotation_deg.x < 0.0,
			"beach sun sits low in the east-north-east (yaw %.1f)" % beach.sun_rotation_deg.y)
		t.ok(beach.sun_shadows and beach.fog_enabled and beach.fill_energy > 0.0, "beach has shadows, haze and a fill light")
		for a in [cage, beach]:
			t.ok(a.title_period_s > 0.0 and a.title_fov > 0.0, "%s carries a home-card pan pose" % a.id)


func _wall_sound(t) -> void:
	t.ok(not CosmeticLibrary.get_arena("beach").wall_sound, "the beach's unseen walls are silent")
	t.ok(CosmeticLibrary.get_arena("cage").wall_sound and CosmeticLibrary.get_arena("city").wall_sound, "the cage and city fences rattle")
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	if sfx == null:
		return
	var was: bool = sfx.wall_sound
	sfx.wall_sound = false
	sfx.contact("wall", 5.0)   # returns before any clip is picked
	sfx.wall_sound = was
	t.ok(true, "a silent wall plays nothing (no clip picked)")


func _net_overrides(t) -> void:
	var save = Engine.get_main_loop().root.get_node_or_null("SaveService")
	if save == null:
		return
	var before: Dictionary = save.get_tuning_net()
	save.put_tuning_net({"nylon": {"rest_spring": 120.0}, "chain": {"kick_speed": 0.9}})
	t.eq(save.get_tuning_net()["nylon"]["rest_spring"], 120.0, "net overrides persist per kind")
	t.eq(save.get_tuning_net()["chain"]["kick_speed"], 0.9, "…for the chain too")
	var fields: Dictionary = save.get_tuning().get("fields", {})
	save.put_tuning(bool(save.get_tuning().get("tuningMode", false)), fields)
	t.ok(save.get_tuning_net().has("nylon"), "writing the flick fields keeps the net overrides")
	save.put_tuning_net(before)
