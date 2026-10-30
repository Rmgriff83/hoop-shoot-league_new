extends RefCounted
## The match's countdown and clock sounds (Ross, 2026-10-30): a beep on each
## of 3, 2, 1, stomachache's "Countdown Start" on GO, and iainmccurdy's
## "Timer Ticking" (cut to 10 s, raised 3 dB) under the last ten seconds.


func run(t) -> void:
	for clip in ["countdown_beep", "countdown_go", "timer_tick"]:
		t.ok(ResourceLoader.exists("res://assets/audio/%s.wav" % clip), "%s.wav ships" % clip)
	var tick: AudioStreamWAV = load("res://assets/audio/timer_tick.wav")
	t.close(tick.get_length(), 10.0, 0.05, "the ticking runs ten seconds, the length of the window it plays in")
	var tts := load("res://game/screens/time_trial_screen.gd")
	t.eq(tts.TICK_FROM_S, 10.0, "it starts with ten seconds left")
	var credits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))
	var titles := []
	for c in credits["sounds"]:
		titles.push_back("%s by %s" % [c["title"], c["author"]])
	t.ok(titles.has("Timer Ticking by iainmccurdy"), "the ticking is credited (CC BY 4.0)")
	t.ok(titles.has("Countdown Start by stomachache"), "the GO sound is credited (CC0, a courtesy)")
