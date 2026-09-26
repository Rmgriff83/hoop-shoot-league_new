extends RefCounted
## Credits data: every third-party sound has the attribution fields, and the
## ambience clips in use are credited.

const CreditsScreen := preload("res://game/screens/credits_screen.gd")


func run(t) -> void:
	t.eq(CreditsScreen.validate(), PackedStringArray(), "credits validate")
	var credits := CreditsScreen.load_credits()
	t.ok(credits["sounds"].size() >= 3, "title music + arcade + beach ambience credited")
	var arcade := {}
	for c in credits["sounds"]:
		if str(c.get("author", "")) == "kevp888":
			arcade = c
	t.eq(CreditsScreen.attribution_line(arcade), "250825_152710_PH_Arcade_games by kevp888 -- https://freesound.org/s/840203/ -- License: Attribution 4.0", "the author's attribution text, verbatim")
	var music := {}
	for c in credits["sounds"]:
		if str(c.get("url", "")) == "https://freesound.org/s/856449/":
			music = c
	t.eq(CreditsScreen.attribution_line(music), "Moog_SEM 110bpm by fonoskop -- https://freesound.org/s/856449/ -- License: Attribution 4.0", "title music attribution, verbatim")
	t.ok(FileAccess.file_exists(str(App.TITLE_MUSIC["clip"])), "title music clip exists")
	# The beach radio's five extra tracks, credited verbatim and shipped.
	var expect := {
		"https://freesound.org/s/860354/": ["zero mass 110 by fonoskop -- https://freesound.org/s/860354/ -- License: Attribution 4.0", "res://assets/music/zero_mass.ogg"],
		"https://freesound.org/s/865348/": ["Scarpeta 110 by fonoskop -- https://freesound.org/s/865348/ -- License: Attribution 4.0", "res://assets/music/scarpeta.ogg"],
		"https://freesound.org/s/862800/": ["footloose 110bpm by fonoskop -- https://freesound.org/s/862800/ -- License: Attribution 4.0", "res://assets/music/footloose.ogg"],
		"https://freesound.org/s/856396/": ["Synthwave Beat 110 BPM loop by fonoskop -- https://freesound.org/s/856396/ -- License: Attribution 4.0", "res://assets/music/synthwave_beat.ogg"],
		"https://freesound.org/s/853379/": ["Anabell 110BPM Melodic Synth-Wave Loop by fonoskop -- https://freesound.org/s/853379/ -- License: Attribution 4.0", "res://assets/music/anabell.ogg"],
	}
	var seen := 0
	for c in credits["sounds"]:
		var u := str(c.get("url", ""))
		if expect.has(u):
			seen += 1
			t.eq(CreditsScreen.attribution_line(c), expect[u][0], "radio track attribution, verbatim")
			t.ok(FileAccess.file_exists(expect[u][1]), "radio track shipped: %s" % expect[u][1])
	t.eq(seen, 5, "five radio tracks credited")
	var cage: ArenaSet = CosmeticLibrary.get_arena("cage")
	t.eq(cage.ambient_clips.size(), 1, "cage has its ambience now")
	t.eq(cage.validate(), PackedStringArray(), "cage arena validates")
	var fonts: Array = credits.get("fonts", [])
	t.ok(fonts.size() >= 1 and str(fonts[0]["title"]) == "Caveat", "the chalk font is credited")
	t.ok(FileAccess.file_exists("res://assets/fonts/caveat/Caveat.ttf") and FileAccess.file_exists("res://assets/fonts/caveat/OFL.txt"), "font and its licence ship together")
	var fire := {}
	for c in credits["sounds"]:
		if str(c.get("author", "")) == "SilverIllusionist":
			fire = c
	t.eq(CreditsScreen.attribution_line(fire), "Fire Burst.wav by SilverIllusionist -- https://freesound.org/s/472688/ -- License: Attribution 4.0", "fire burst attribution, verbatim")
	t.ok(FileAccess.file_exists("res://assets/audio/fx/fire_burst.wav"), "fire burst clip shipped")
	# The pole hits are third-party and must carry their attribution; nothing
	# else would catch a missing one, since credits validate in one direction
	# only (credits -> files, never files -> credits).
	var pole := {}
	for c in credits["sounds"]:
		if str(c.get("url", "")) == "https://freesound.org/s/543321/":
			pole = c
	t.ok(not pole.is_empty(), "the pole hit sound is credited")
	for key in ["title", "author", "url", "license"]:
		t.ok(str(pole.get(key, "")) != "", "pole credit has %s" % key)
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	# (The runner executes before the autoload's _ready fills its stream table,
	# so check the clip and the API directly.)
	t.ok(load("res://assets/audio/fx/fire_burst.wav") is AudioStream, "fire burst imports as an AudioStream")
	if sfx != null:
		t.ok(sfx.has_method("fire_burst"), "Sfx exposes fire_burst()")
	var ice_stream: AudioStream = load("res://assets/audio/fx/ice_form.wav")
	t.ok(ice_stream != null and ice_stream.get_length() > 2.0 and ice_stream.get_length() < 2.6, "ice form clip trimmed to ~2.4 s")
	var ice_credit := {}
	for c in credits["sounds"]:
		if str(c.get("author", "")) == "timbreknight":
			ice_credit = c
	t.ok(not ice_credit.is_empty() and str(ice_credit["url"]).contains("342546"), "ice cracking credited")
	var by_author := {}
	for c in credits["sounds"]:
		by_author[str(c.get("author", ""))] = c
	t.eq(CreditsScreen.attribution_line(by_author.get("theplax", {})), "Breaking Glass Mix.wav by theplax -- https://freesound.org/s/546671/ -- License: Attribution 4.0", "ice break attribution, verbatim")
	t.eq(CreditsScreen.attribution_line(by_author.get("cmusounddesign", {})), "mp glass break.wav by cmusounddesign -- https://freesound.org/s/85184/ -- License: Attribution 4.0", "swish break attribution, verbatim")
	var brk: AudioStream = load("res://assets/audio/fx/ice_break.wav")
	var sw: AudioStream = load("res://assets/audio/fx/ice_swish.wav")
	t.ok(brk != null and brk.get_length() > 1.5 and brk.get_length() < 1.8, "generic ice break clip whole (~1.7 s)")
	t.ok(sw != null and sw.get_length() > 1.1 and sw.get_length() < 1.3, "swish break clip trimmed to ~1.2 s")
	for c in credits["sounds"]:
		by_author[str(c.get("author", ""))] = c
	t.eq(CreditsScreen.attribution_line(by_author.get("Wavewire", {})), "MatchstickDeath-03 by Wavewire -- https://freesound.org/s/834140/ -- License: Attribution 4.0", "fire out attribution, verbatim")
	t.ok(load("res://assets/audio/fx/fire_out.wav") is AudioStream, "fire out clip imports")
	if sfx != null:
		t.ok(sfx.has_method("fire_out"), "Sfx exposes fire_out()")
