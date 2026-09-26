extends RefCounted
## Area ambience: arena-set data, looping layers, no-op restarts, stop.


func run(t) -> void:
	var beach: ArenaSet = CosmeticLibrary.get_arena("beach")
	var cage: ArenaSet = CosmeticLibrary.get_arena("cage")
	t.eq(beach.ambient_clips.size(), 1, "beach declares one ambient layer (seagulls)")
	t.close(beach.ambient_gain_db(0), 12.0, 1e-6, "seagulls at +12 dB (the recording is ~26 dB quieter than the arcade one)")
	t.close(beach.ambient_gain_db(5), 0.0, 1e-6, "missing gain → 0 dB")
	t.eq(beach.validate(), PackedStringArray(), "beach arena validates (clip exists)")
	t.eq(cage.ambient_clips.size(), 1, "cage has its arcade ambience")
	var stream: AudioStream = load(beach.ambient_clips[0])
	t.ok(stream != null and stream.get_length() > 60.0, "seagulls load as a long stream (%.0f s)" % (stream.get_length() if stream else 0.0))
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	t.ok(sfx != null, "Sfx autoload present")
	if sfx == null:
		return
	sfx.start_ambience(beach)
	t.eq(sfx.ambience_id(), "beach", "beach ambience active")
	t.eq(sfx.ambience_layer_count(), 1, "one layer")
	var layer: AudioStreamPlayer = sfx._amb_players[0]
	t.ok(layer.playing or DisplayServer.get_name() == "headless", "layer playing (headless audio never reports playback)")
	t.ok(layer.stream is AudioStreamOggVorbis and (layer.stream as AudioStreamOggVorbis).loop, "layer loops")
	sfx.start_ambience(beach)
	t.eq(sfx.ambience_layer_count(), 1, "restarting the same area keeps one layer")
	sfx.stop_ambience()
	t.ok(sfx.ambience_stopping(), "stop begins a fade")
	sfx.start_ambience(beach)
	t.ok(not sfx.ambience_stopping() and sfx.ambience_layer_count() == 1, "same area returning cancels the fade")
	var silent := ArenaSet.new()
	silent.id = "silent"
	sfx.start_ambience(silent)
	t.ok(sfx.ambience_stopping(), "an area without clips fades the layers out")
	t.eq(sfx.ambience_id(), "", "no ambience id while fading out")
	sfx.start_ambience(beach)
	sfx._amb_kill_layers()
	t.eq(sfx.ambience_layer_count(), 0, "layers dropped")
	# Title music rides the same channel; an area's ambience replaces it.
	sfx.start_music("title", str(App.TITLE_MUSIC["clip"]), float(App.TITLE_MUSIC["gain_db"]))
	t.eq(sfx.ambience_id(), "title", "title music playing")
	t.eq(sfx.ambience_layer_count(), 1, "one music layer")
	t.close(sfx._amb_gains[0], float(App.TITLE_MUSIC["gain_db"]), 1e-6, "music gain from the data")
	sfx.start_music("title", str(App.TITLE_MUSIC["clip"]), float(App.TITLE_MUSIC["gain_db"]))
	t.eq(sfx.ambience_layer_count(), 1, "credits screen re-asking for the title loop is a no-op")
	sfx.start_ambience(beach)
	t.eq(sfx.ambience_id(), "beach", "entering an area replaces the music")
	t.eq(sfx.ambience_layer_count(), 1, "one beach layer")
	sfx._amb_kill_layers()
