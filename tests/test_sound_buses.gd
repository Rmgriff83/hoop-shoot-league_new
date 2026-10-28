extends RefCounted
## The settings SOUND switches (Ross, 2026-10-27; design "Settings" 42a):
## MUSIC and SOUND EFFECTS, each the mute of its own bus. Sfx makes the two
## buses under Master at start; the title loop and the track channel ride
## MUSIC, the clip pool, the servo and an area's ambience ride SFX.


func run(t) -> void:
	t.eq(SaveService.default_settings().get("musicSound", null), true, "musicSound defaults on")
	t.eq(SaveService.default_settings().get("sfxSound", null), true, "sfxSound defaults on")
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	if sfx == null:
		return
	sfx.set_music_sound(true)   # first use makes the buses out of the tree
	var mi := AudioServer.get_bus_index(sfx.MUSIC_BUS)
	var si := AudioServer.get_bus_index(sfx.SFX_BUS)
	t.ok(mi >= 0 and si >= 0, "both buses exist")
	t.eq([AudioServer.get_bus_send(mi), AudioServer.get_bus_send(si)], [&"Master", &"Master"], "…sent to Master")
	for p in sfx._players:
		t.eq(String(p.bus), sfx.SFX_BUS, "a pool player sits on the sfx bus")
	# The channels.
	sfx.start_music("test_title", "res://assets/audio/swish.wav", -20.0, 0.0)
	t.eq(sfx._amb_players.size(), 1, "the title loop is one layer")
	t.eq(String(sfx._amb_players[0].bus), sfx.MUSIC_BUS, "…on the music bus")
	sfx.start_layers("test_amb", PackedStringArray(["res://assets/audio/swish.wav"]), PackedFloat32Array([-20.0]), 0.0)
	t.eq(String(sfx._amb_players[0].bus), sfx.SFX_BUS, "an area's ambience rides the sfx bus")
	sfx.start_level_music(0)
	t.eq(String(sfx._track.bus), sfx.MUSIC_BUS, "a level track rides the music bus")
	sfx.stop_ambience(0.0)
	sfx.peggy_servo_start()   # no clip in a headless run: the servo stays unbuilt
	if sfx._servo != null:
		t.eq(String(sfx._servo.bus), sfx.SFX_BUS, "the PEGGY servo rides the sfx bus")
		sfx.peggy_servo_stop(0.0)
	# The switches: App round-trips the setting and the mute.
	var was_music: bool = App.music_sound
	var was_sfx: bool = App.sfx_sound
	App.set_music_sound(false)
	t.ok(not App.music_sound and not bool(SaveService.get_settings()["musicSound"]), "set_music_sound(false) saves")
	t.ok(AudioServer.is_bus_mute(mi) and not AudioServer.is_bus_mute(si), "…and mutes only the music bus")
	t.ok(not sfx.music_sound() and sfx.sfx_sound(), "…which Sfx reports")
	App.set_sfx_sound(false)
	t.ok(AudioServer.is_bus_mute(si), "set_sfx_sound(false) mutes the sfx bus")
	App.set_music_sound(true)
	t.ok(not AudioServer.is_bus_mute(mi), "set_music_sound(true) unmutes")
	# A cloud pull re-reads both (App._on_save_pulled → _read_sound_settings).
	var s: Dictionary = SaveService.get_settings()
	s["sfxSound"] = true
	SaveService.put_settings(s)
	App._read_sound_settings()
	t.ok(App.sfx_sound and not AudioServer.is_bus_mute(si), "a pulled settings part applies the switches")
	App.set_music_sound(was_music)
	App.set_sfx_sound(was_sfx)
