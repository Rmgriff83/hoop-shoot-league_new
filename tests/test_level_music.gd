extends RefCounted
## Level music (2026-10-16): one shared playlist on every court, toggled by
## the HUD's bottom-left note and remembered as the `musicOn` setting, off on
## a fresh install. Replaces the in-world radios (the beach boombox, the city
## speaker), which are gone.


func run(t) -> void:
	t.eq(SaveService.default_settings().get("musicOn", null), false, "musicOn defaults off")
	var tracks: Array = App.LEVEL_MUSIC["tracks"]
	t.eq(tracks.size(), 6, "six level tracks")
	t.eq(str(tracks[0]), str(App.TITLE_MUSIC["clip"]), "the title loop is in the playlist")
	var credits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))
	var credited := {}
	for c in credits["sounds"]:
		credited[str(c.get("file", "")).get_file()] = true
	for tp in tracks:
		t.ok(FileAccess.file_exists(str(tp)), "track shipped: %s" % tp)
	t.ok(float(App.LEVEL_MUSIC["gain_db"]) < 0.0, "level music sits under the ambience")
	# The setting round-trips through App like dark mode.
	var was := App.music_on
	App.set_music_on(true)
	t.ok(App.music_on and bool(SaveService.get_settings()["musicOn"]), "set_music_on(true) saves")
	App.set_music_on(false)
	t.ok(not App.music_on and not bool(SaveService.get_settings()["musicOn"]), "set_music_on(false) saves")
	App.set_music_on(was)
	# Sfx: a level track on the track channel, beside the ambience; off again.
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.start_level_music(2)
		t.eq(sfx.track_id(), "music2", "start_level_music(2) plays the third track")
		t.ok(sfx.level_music_on(), "…and reports music on")
		sfx.start_level_music(4)
		t.eq(sfx.track_id(), "music4", "a new pick replaces it")
		sfx.stop_level_music()
		t.eq(sfx.track_id(), "", "stop_level_music clears the channel")
		t.ok(not sfx.level_music_on(), "…and reports music off")
		sfx.start_level_music(0)
		sfx.stop_ambience()
		t.eq(sfx.track_id(), "", "leaving a level (stop_ambience) drops the music too")
		# The chevron beside the note (2026-10-17): the next song, wrapping.
		t.eq(sfx.level_music_index(), -1, "no index while silent")
		sfx.next_level_music()
		t.eq(sfx.track_id(), "music0", "from silence the first song")
		sfx.start_level_music(4)
		sfx.next_level_music()
		t.eq(sfx.track_id(), "music5", "the next song")
		sfx.next_level_music()
		t.eq(sfx.track_id(), "music0", "…and round again")
		sfx.stop_level_music()
	# The note icon draws in both states.
	var nb := IconButton.new("next", 44.0)
	t.ok(nb.kind == "next" and nb.size == Vector2(44, 44), "a smaller next-song chevron")
	nb.free()
	var b := IconButton.new("music")
	t.eq(b.kind, "music", "music kind")
	t.ok(b.active, "lit by default")
	b.active = false
	t.ok(not b.active, "struck through when off")
	b.free()
	# No area declares an interactable radio any more.
	for area in ["cage", "beach", "park", "city"]:
		var set: ArenaSet = CosmeticLibrary.get_arena(area)
		t.eq(set.interactables.size(), 0, "%s has no in-world radio" % area)
