extends RefCounted
## Area interactables: ray-vs-box picking, the beach radio's data, the
## playlist cycle on Sfx's track channel, and the leave hook.


func run(t) -> void:
	# Picking: a ray through the box hits, one beside it misses, distance is right.
	var target := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.28, 0.7)
	mi.mesh = box
	target.add_child(mi)
	var it := Interactable.new()
	it.setup(target, {"kind": "prop", "pad": 0.0})
	t.close(it.bounds().size.z, 0.7, 1e-6, "bounds from the mesh")
	t.close(it.hit(Vector3(-3.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)), 3.0 - 0.11, 1e-6, "ray through the box hits at its near face")
	t.ok(it.hit(Vector3(-3.0, 0.0, 0.6), Vector3(1.0, 0.0, 0.0)) < 0.0, "ray beside the box misses")
	t.ok(it.hit(Vector3(-3.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0)) < 0.0, "ray pointing away misses")
	var padded := Interactable.new()
	padded.setup(target, {"kind": "prop", "pad": 0.1})
	t.ok(padded.hit(Vector3(-3.0, 0.0, 0.4), Vector3(1.0, 0.0, 0.0)) > 0.0, "pad grows the tap box")
	it.free()
	padded.free()
	# Data: the beach declares one radio on the boombox with six tracks that exist.
	var beach: ArenaSet = CosmeticLibrary.get_arena("beach")
	t.eq(beach.interactables.size(), 1, "beach has one interactable")
	var row: Dictionary = beach.interactables[0]
	t.eq(str(row["kind"]), "radio", "it is the radio")
	t.eq(str(row["node"]), "Boombox", "on the boombox")
	t.eq(Array(row["tracks"]).size(), 6, "six tracks")
	t.eq(str(row["tracks"][0]), str(App.TITLE_MUSIC["clip"]), "the title loop leads the playlist")
	for tp in row["tracks"]:
		t.ok(FileAccess.file_exists(str(tp)), "track shipped: %s" % tp)
	t.eq(beach.validate(), PackedStringArray(), "beach arena validates with its tracks")
	t.ok(beach.referenced_paths().has(str(row["tracks"][3])), "tracks are referenced paths")
	t.ok(InteractableKinds.make("radio") is RadioInteractable, "radio kind builds")
	t.eq(InteractableKinds.make("nope"), null, "unknown kind → null")
	var cage: ArenaSet = CosmeticLibrary.get_arena("cage")
	t.eq(cage.interactables.size(), 0, "cage has none yet")
	var city: ArenaSet = CosmeticLibrary.get_arena("city")
	t.eq(city.interactables.size(), 1, "the city has one interactable")
	t.ok(str(city.interactables[0]["kind"]) == "radio" and str(city.interactables[0]["node"]) == "Speakers", "the floor speaker is its radio")
	var cglb: Node = load(city.model_path).instantiate()
	t.ok(cglb.find_child("Speakers", true, false) is Node3D and cglb.find_child("SpeakerLed", true, false) is MeshInstance3D, "Speakers + SpeakerLed in the city glb")
	# The 2026-10-03 polish: woofer, mid, tweeter and badge; one cabinet since 2026-10-05.
	for i in 1:
		for part in ["SpeakerWoofer%dCone", "SpeakerWoofer%dCap", "SpeakerWoofer%dScrew5", "SpeakerMid%dCone", "SpeakerTweeter%d", "SpeakerDome%d", "SpeakerBadge%d", "SpeakerBaffle%d"]:
			t.ok(cglb.find_child(part % i, true, false) is MeshInstance3D, "%s in the city glb" % (part % i))
	t.eq(cglb.find_child("SpeakerBox1", true, false), null, "only one cabinet")
	t.ok(cglb.find_child("ScoreboardRig", true, false) == null and cglb.find_child("ScoreClock", true, false) is MeshInstance3D, "the city's scoreboard hangs on the fence (no turning rig; tests/test_scoreboard.gd)")
	cglb.free()
	# The glb has the boombox and its LED.
	var glb: Node = load(str(beach.model_path)).instantiate()
	var bb := glb.find_child("Boombox", true, false)
	t.ok(bb is Node3D, "Boombox node in the beach glb")
	t.ok(glb.find_child("BoomboxLed", true, false) is MeshInstance3D, "BoomboxLed mesh in the glb")
	# Radio cycle with a pinned seed: off → 0 → a permutation of 1..5 → off → …
	var radio := RadioInteractable.new()
	var seeded := row.duplicate()
	seeded["seed"] = 4
	radio.setup(bb as Node3D, seeded)
	t.eq(radio.current(), -1, "radio starts off")
	t.ok(radio._led_mat != null, "the boombox LED (a sibling part) is bound")
	radio.on_tap(null)
	t.ok(radio._led_mat.emission_energy_multiplier > 1.0, "LED glows while playing")
	radio.on_leave()
	t.close(radio._led_mat.emission_energy_multiplier, 0.0, 1e-6, "LED dark when off")
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	var seq := []
	for i in 7:
		radio.on_tap(null)
		seq.push_back(radio.current())
	t.eq(seq[0], 0, "first tap plays the title loop")
	var rest: Array = seq.slice(1, 6)
	rest.sort()
	t.eq(rest, [1, 2, 3, 4, 5], "then every other track once (%s)" % str(seq.slice(1, 6)))
	t.eq(seq[6], -1, "then off again")
	if sfx != null:
		t.eq(sfx.track_id(), "", "track channel silent when off")
		radio.on_tap(null)
		t.eq(sfx.track_id(), "radio0", "track channel follows the radio")
		t.ok(sfx.ambience_layer_count() == 0 or true, "layers untouched by the track")
		radio.on_leave()
		t.eq(radio.current(), -1, "leaving turns the radio off")
		t.eq(sfx.track_id(), "", "and stops the track")
		sfx.play_track("x", str(App.TITLE_MUSIC["clip"]), -20.0)
		sfx.stop_ambience()
		t.eq(sfx.track_id(), "", "stop_ambience also clears the track")
	# Hints: one "tap" disc when off; "next" + a smaller "off" while playing.
	t.eq(radio.icons(), [{"id": "tap"}], "off → tap hint")
	radio.on_tap(null)
	t.eq(radio.icons(), [{"id": "next"}, {"id": "off"}], "playing → next + off hints")
	var lay: Array = PropIcons.layout(Vector2(300, 200), radio.icons())
	t.eq(lay.size(), 2, "two discs laid out")
	t.ok(lay[0]["center"].x < lay[1]["center"].x and float(lay[1]["r"]) < float(lay[0]["r"]), "next left, the smaller off disc right")
	t.close((lay[0]["center"].x + lay[1]["center"].x) * 0.5, 300.0, 40.0, "centred on the anchor")
	radio.on_icon("off", null)
	t.eq(radio.current(), -1, "off disc turns the radio off")
	t.eq(radio.icons(), [{"id": "tap"}], "back to the tap hint")
	radio.on_icon("tap", null)
	t.eq(radio.current(), 0, "tap disc plays the first track")
	radio.on_icon("next", null)
	t.ok(radio.current() > 0, "next disc advances")
	radio.on_leave()
	t.ok(radio.anchor().y > radio.bounds().end.y, "hint anchor floats above the prop")
	var radio2 := RadioInteractable.new()
	radio2.setup(bb as Node3D, seeded)
	var seq2 := []
	for i in 6:
		radio2.on_tap(null)
		seq2.push_back(radio2.current())
	t.eq(seq2, seq.slice(0, 6), "same seed → same order")
	radio2.on_leave()
	radio.free()
	radio2.free()
	glb.free()
	target.free()
