extends RefCounted
## The match's countdown and clock sounds (Ross, 2026-10-30): a beep on each
## of 3, 2, 1, stomachache's "Countdown Start" on GO, and iainmccurdy's
## "Timer Ticking" (11 s sped up 10% to 10 s, raised 3 dB) under the last ten seconds.


func run(t) -> void:
	for clip in ["countdown_beep", "countdown_go", "timer_tick", "time_up_ring"]:
		t.ok(ResourceLoader.exists("res://assets/audio/%s.wav" % clip), "%s.wav ships" % clip)
	var tick: AudioStreamWAV = load("res://assets/audio/timer_tick.wav")
	t.close(tick.get_length(), 10.0, 0.05, "the ticking runs ten seconds, the length of the window it plays in")
	var tts := load("res://game/screens/time_trial_screen.gd")
	t.eq(tts.TICK_FROM_S, 10.0, "it starts with ten seconds left")
	t.ok(Sfx.BEEP_DB < 0.0 and Sfx.GO_DB < 0.0 and Sfx.TICK_DB < 0.0 and Sfx.RING_DB < 0.0, "the clock's sounds play under their clips' level")
	var credits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))
	var titles := []
	for c in credits["sounds"]:
		titles.push_back("%s by %s" % [c["title"], c["author"]])
	t.ok(titles.has("Timer Ticking by iainmccurdy"), "the ticking is credited (CC BY 4.0)")
	t.ok(titles.has("Countdown Start by stomachache"), "the GO sound is credited (CC0, a courtesy)")
	t.ok(titles.has("Analog Timer by EagleStealthTeam"), "the time-up ring is credited (CC0, a courtesy)")
