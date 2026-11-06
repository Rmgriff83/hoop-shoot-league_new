extends RefCounted
## The trailer's data and its pure parts (docs/TRAILER.md): the edit lands on
## the music's grid and keeps to the brief (lengths, card copy, the App
## Store cut's shooting view only), every shot file speaks verbs the
## director knows, and the helpers that pick a board row, a PEGGY aim, a
## stand-in flick and a card's pose do what they say.

const EDIT := "res://tools/trailer/edit.json"
const SHOTS := "res://tools/trailer/shots"
const Director := preload("res://tools/trailer/director.gd")
const Stages := preload("res://tools/trailer/director_stages.gd")
const CardScene := preload("res://tools/trailer/card_scene.gd")
const BANNED := ["physics", "realistic", "roguelite", "roguelike", "ultimate", "experience", "immersive", "next-level", "revolutionary", "deckbuilder"]
const DIRECTOR_VERBS := ["wait", "play", "spot", "until", "flick", "mark", "poster", "time_scale", "camera", "hud", "wear", "tap", "call", "end"]


func _beats(pos: String) -> float:
	return CardScene.beat_time({"bpm": 60.0}, pos)   # at 60 BPM a beat is a second: the position in beats


func _copy_ok(t, text: String, what: String) -> void:
	var words := text.replace("\n", " ").split(" ", false)
	t.ok(words.size() >= 2 and words.size() <= 4, "%s is 2-4 words (%s)" % [what, text.replace("\n", " ")])
	t.eq(text, text.to_upper(), "%s is all caps" % what)
	for w in BANNED:
		t.ok(not text.to_lower().contains(w), "%s avoids '%s'" % [what, w])
	var display := UiFont.display()
	for ch in text:
		t.ok(ch == "\n" or display.has_char(ch.unicode_at(0)), "%s: the display font has '%s'" % [what, ch])


func run(t) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EDIT))
	t.ok(parsed is Dictionary, "the edit parses")
	var edit: Dictionary = parsed
	t.eq(float(edit["bpm"]), 110.0, "the music's tempo")
	t.ok(FileAccess.file_exists("res://" + str(edit["music"])), "the music file is there")
	t.ok(absf(CardScene.beat_time(edit, "2.1") - 2.181818) < 1e-4 and absf(CardScene.beat_time(edit, "1.3") - 1.090909) < 1e-4, "a bar is 2.18 s, a beat 0.545 s")
	t.ok(str(edit.get("music_credit", "")).contains("FONOSKOP") and str(edit["music_credit"]).contains("CC BY 4.0"), "the music credit names the author and the licence")
	# The shot files: named as their file, verbs the director or its stages know.
	var stages := Stages.new(null)
	var shots := {}
	for file in DirAccess.get_files_at(SHOTS):
		if not str(file).ends_with(".json"):
			continue
		var shot: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [SHOTS, file]))
		t.ok(shot is Dictionary and shot.get("steps") is Array, "%s parses" % file)
		if not (shot is Dictionary):
			continue
		t.eq(str(shot["name"]) + ".json", str(file), "%s is named as its file" % file)
		shots[str(shot["name"])] = shot
		var marks := []
		for step in shot["steps"]:
			var verb := str(step.get("do", ""))
			t.ok(DIRECTOR_VERBS.has(verb) or stages.has_method("stage_" + verb), "%s: the director knows '%s'" % [file, verb])
			if verb == "mark":
				marks.push_back(str(step.get("name", "")))
		t.ok(marks.has("in") and marks.has("out"), "%s marks its in and out" % file)
		t.ok((shot["steps"] as Array).any(func(s: Dictionary) -> bool: return str(s.get("do", "")) == "poster" or bool(s.get("poster_mid", false))), "%s has a storyboard frame" % file)
	t.ok(shots.size() >= 20, "the shot list is there (%d)" % shots.size())
	# The cuts.
	var options: Dictionary = edit.get("copy_options", {})
	for id in options:
		t.eq((options[id] as Array).size(), 3, "three copy options for '%s'" % id)
		for text in options[id]:
			_copy_ok(t, str(text), "option for '%s'" % id)
	for name in ["appstore", "social"]:
		var cut: Dictionary = edit["cuts"][name]
		var last := -1.0
		for e in cut["timeline"]:
			var at := _beats(str(e["at"]))
			t.ok(at > last, "%s: %s comes after the entry before it" % [name, e["at"]])
			t.ok(absf(at * 2.0 - roundf(at * 2.0)) < 1e-6, "%s: %s lands on a beat or a half beat" % [name, e["at"]])
			last = at
			if e.has("clip"):
				t.ok(shots.has(str(e["clip"])), "%s: clip '%s' has a shot file" % [name, e["clip"]])
				if name == "appstore" and shots.has(str(e["clip"])):
					t.ok(not (shots[str(e["clip"])]["steps"] as Array).any(func(s: Dictionary) -> bool: return str(s.get("do", "")) in ["camera", "hud"]),
						"appstore: '%s' is the shooting view (no rim camera, the HUD left on)" % e["clip"])
		t.ok(last < float(int(cut["bars"]) * 4), "%s: the last entry starts inside the cut" % name)
		var worded := (cut["cards"] as Array).filter(func(c: Dictionary) -> bool: return str(c.get("text", "")) != "")
		t.ok(worded.size() <= 6, "%s: at most six text cards (%d)" % [name, worded.size()])
		for c in cut["cards"]:
			t.ok(_beats(str(c["until"])) > _beats(str(c["at"])), "%s: card '%s' ends after it starts" % [name, c["id"]])
		for c in worded:
			_copy_ok(t, str(c["text"]), "%s card '%s'" % [name, c["id"]])
			t.ok((options.get(str(c["id"]), []) as Array).has(str(c["text"])), "%s card '%s' is one of its options" % [name, c["id"]])
		t.ok((cut["cards"] as Array).any(func(c: Dictionary) -> bool: return str(c["id"]) == "credit"), "%s: the end card carries the music credit" % name)
	var app: Dictionary = edit["cuts"]["appstore"]
	var app_s := float(int(app["bars"]) * 4) * 60.0 / 110.0
	t.ok(app_s >= 15.0 and app_s <= 30.0, "the App Store cut is 15-30 s (%.2f)" % app_s)
	t.eq([app["size"], int(app["fps"])], [[886.0, 1920.0], 30], "…886 x 1920 at 30 fps (Apple's App Preview size for every current iPhone)")
	t.ok(not (app["cards"] as Array).any(func(c: Dictionary) -> bool: return str(c["id"]) == "free"), "…with no price or store line (Apple: no prices)")
	var social: Dictionary = edit["cuts"]["social"]
	var social_s := float(int(social["bars"]) * 4) * 60.0 / 110.0
	t.ok(social_s >= 30.0 and social_s <= 45.0, "the social cut is 30-45 s (%.2f)" % social_s)
	t.eq([social["size"], int(social["fps"])], [[1080.0, 1920.0], 60], "…1080 x 1920 at 60 fps")
	t.ok(str(social["timeline"][0].get("file", "")) != "", "…opening on the slot for the filmed hand")
	# A card's pose: the tour card's entrance, a short fade out.
	t.eq(CardScene.pose(0.0, 2.0), Vector2(0.0, CardScene.RISE_PX), "a card starts unseen, 16 px low")
	t.eq(CardScene.pose(1.0, 2.0), Vector2(1.0, 0.0), "…is settled and solid mid-way")
	t.ok(CardScene.pose(1.95, 2.0).x < 0.5 and CardScene.pose(2.0, 2.0).x == 0.0, "…and fades out at the end")
	# The board with YOU placed: the rows below shift down a place.
	var board := {"rows": [{"rank": 1, "name": "A", "score": 40, "me": false}, {"rank": 2, "name": "B", "score": 38, "me": false}, {"rank": 3, "name": "C", "score": 30, "me": false}]}
	var placed: Dictionary = Stages.board_with_me(board, 2, 39, "ME")
	t.eq((placed["rows"] as Array).map(func(r: Dictionary) -> String: return "%d %s" % [r["rank"], r["name"]]), ["1 A", "2 ME", "3 B", "4 C"], "YOU at second: the rest shift down")
	t.eq(placed["me"], {"rank": 2, "score": 39}, "…and the page's own card follows")
	t.eq((board["rows"] as Array).size(), 3, "…the fixture itself is untouched")
	# PEGGY: an aim that lands on the wanted plate, by the board's own sim.
	var plates := []
	for i in 7:
		plates.push_back({"rarity": "legend" if i == 0 or i == 6 else "common", "id": "x%d" % i, "kind": "ball"})
	var found := 0
	for seed_v in [11, 22, 33, 44]:
		var aim: float = Stages.aim_for("legend", plates, seed_v)
		if not is_nan(aim):
			found += 1
			var slot := int(PeggyBoard.simulate(aim, seed_v)["slot"])
			t.ok(slot == 0 or slot == 6, "the aim found lands on a legend plate (seed %d → slot %d)" % [seed_v, slot])
			t.ok(absf(aim) <= PeggyBoard.AIM_MAX, "…inside the crane's travel")
	t.ok(found >= 1, "an outer plate can be reached on at least one of four seeds (%d)" % found)
	t.ok(is_nan(Stages.aim_for("legend", plates.map(func(p: Dictionary) -> Dictionary: return {"rarity": "common", "id": "y"}), 11)), "no such plate: no aim")
	# A stand-in flick is a gesture the real estimator accepts, and it is seeded.
	var tr := FlickSynth.trace(320.0, 2.2, 6.0, DetRng.new(5))
	var again := FlickSynth.trace(320.0, 2.2, 6.0, DetRng.new(5))
	t.eq(tr, again, "a stand-in gesture is the same for the same seed")
	var sample := FlickSynth.sample_of(tr)
	t.ok(not sample.is_empty() and float(sample["speed_sh"]) > 1.0 and float(sample["pull_px"]) > 200.0, "…and reads as a wound-up flick")
	var geo := SimGeometry.arcade(App.ARCADE_HOOP_DIST)
	var solved := FlickSynth.solve(["SWISH", "MAKE"], FlickTuning.new(), geo, func(_p: Vector2) -> Dictionary: return {"rx": 0.0, "ry": 1.5, "rz": 0.0}, 3)
	t.ok(not solved.is_empty() and bool(solved["synth"]) and ["SWISH", "MAKE"].has(str(solved["outcome"]["type"])), "a make can be found by trying gestures through the real mapping and sim")
	# The director lives in tools/ and is loaded by path: the game names none of it.
	for dir in ["res://game", "res://core"]:
		for path in _scripts(dir):
			var src := FileAccess.get_file_as_string(path)
			t.ok(not src.contains("FlickSynth") and not src.contains("res://tools/trailer"), "%s names nothing of the trailer's" % path.trim_prefix("res://"))
	t.ok(FileAccess.get_file_as_string("res://tools/qa_driver.gd").contains("load(\"res://tools/trailer/director.gd\")"), "the QA driver loads the director by path")
	t.ok(Director != null and CardScene != null, "the director and the card scene compile")


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if str(f).ends_with(".gd"):
			out.push_back(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + sub))
	return out
