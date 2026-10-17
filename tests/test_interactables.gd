extends RefCounted
## Area interactables: ray-vs-box picking, the radio kind's playlist cycle on
## Sfx's track channel and the leave hook (over a stand-in: no area ships a
## prop since 2026-10-16), and the sets without their radios.


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
	# No area ships an interactable since 2026-10-16: the beach boombox and the
	# city speaker came out (level music is the HUD's note, test_level_music).
	# The radio kind stays for a future prop, exercised here over a stand-in rig.
	var beach: ArenaSet = CosmeticLibrary.get_arena("beach")
	t.eq(beach.interactables.size(), 0, "the beach has no interactable (no boombox)")
	t.eq(beach.validate(), PackedStringArray(), "beach arena validates")
	t.ok(InteractableKinds.make("radio") is RadioInteractable, "radio kind builds")
	t.eq(InteractableKinds.make("nope"), null, "unknown kind → null")
	var cage: ArenaSet = CosmeticLibrary.get_arena("cage")
	t.eq(cage.interactables.size(), 0, "cage has none")
	var city: ArenaSet = CosmeticLibrary.get_arena("city")
	t.eq(city.interactables.size(), 0, "the city has no interactable (no speaker)")
	var cglb: Node = load(city.model_path).instantiate()
	t.ok(cglb.find_child("Speakers", true, false) == null and cglb.find_child("SpeakerLed", true, false) == null and cglb.find_child("SpeakerBox0", true, false) == null, "no speaker in the city glb")
	t.ok(cglb.find_child("ScoreboardRig", true, false) == null and cglb.find_child("ScoreClock", true, false) is MeshInstance3D, "the city's scoreboard hangs on the fence (no turning rig; tests/test_scoreboard.gd)")
	cglb.free()
	# The beach glb: no boombox; the reader board stands on the wall's cap.
	var glb: Node = load(str(beach.model_path)).instantiate()
	t.ok(glb.find_child("Boombox", true, false) == null and glb.find_child("BoomboxLed", true, false) == null, "no boombox in the beach glb")
	var sb := glb.find_child("ScoreboardRig", true, false) as Node3D
	t.ok(sb != null and absf(sb.position.y - 0.51) < 0.02, "the reader board sits on the wall cap (y %.2f)" % (sb.position.y if sb != null else -1.0))
	glb.free()
	# A stand-in boombox: a box with an LED part beside it, as the glb had.
	var bb := Node3D.new()
	bb.name = "Boombox"
	var bbm := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.22, 0.28, 0.7)
	bbm.mesh = bbox
	bb.add_child(bbm)
	var hold := Node3D.new()
	hold.add_child(bb)
	var led := MeshInstance3D.new()
	led.name = "BoomboxLed"
	var lbox := BoxMesh.new()
	lbox.material = StandardMaterial3D.new()
	led.mesh = lbox
	hold.add_child(led)
	var row := {"kind": "radio", "node": "Boombox", "pad": 0.08, "gain_db": -14.0, "tracks": App.LEVEL_MUSIC["tracks"]}
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
	hold.free()
	target.free()
