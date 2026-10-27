extends RefCounted
## The end-page chimes (Ross, 2026-10-26): canberries4's two retro chimes
## ship and are credited; the small one is for a match won or a time-trial
## personal best, the big one for the championship, an all-time global best
## or a new area. The global-best call is pure.

const CreditsScreen := preload("res://game/screens/credits_screen.gd")


func run(t) -> void:
	for clip in ["chime_win", "chime_big"]:
		var s: AudioStream = load("res://assets/audio/%s.wav" % clip)
		t.ok(s != null and s.get_length() > 0.3 and s.get_length() < 0.7, "%s ships (~0.4-0.5 s)" % clip)
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	if sfx != null:
		t.ok(sfx.has_method("chime_win") and sfx.has_method("chime_big"), "Sfx exposes both chimes")
	var credits := CreditsScreen.load_credits()
	var urls := {}
	for c in credits["sounds"]:
		urls[str(c.get("url", ""))] = c
	t.ok(urls.has("https://freesound.org/people/canberries4/sounds/866243/") and urls.has("https://freesound.org/people/canberries4/sounds/866244/"), "both chimes credited to canberries4 at Ross's links")
	for u in ["https://freesound.org/people/canberries4/sounds/866243/", "https://freesound.org/people/canberries4/sounds/866244/"]:
		t.eq(str(urls.get(u, {}).get("author", "")), "canberries4", "author on %s" % u)
	# The match-end page's sounds by moment.
	var src := FileAccess.get_file_as_string("res://game/ui/match_end_overlay.gd")
	var body := src.substr(src.find("func _play_sound"))
	body = body.substr(0, body.find("\n\n\n"))
	t.ok(body.find("\"win\", \"advance\":\n\t\t\tSfx.chime_win()") >= 0, "a match won (and a playoff advance) plays the small chime")
	t.ok(body.find("\"champion\":\n\t\t\tSfx.chime_big()") >= 0, "the championship plays the big chime")
	t.ok(body.find("Sfx.match_loss()") >= 0 and body.find("peggy") < 0, "losses keep the sting; no PEGGY sounds on the match end")
	# The global best: beats every row of the cached all-time board; nothing without a board.
	var board := {"rows": [{"rank": 1, "score": 31}, {"rank": 2, "score": 27}]}
	t.ok(ResultsCopy.global_best(32, board), "32 beats a board topped by 31")
	t.ok(not ResultsCopy.global_best(31, board), "a tie is not a new global best")
	t.ok(not ResultsCopy.global_best(30, board), "30 does not")
	t.ok(not ResultsCopy.global_best(99, {}), "no board in hand (offline): no global claim")
	t.ok(not ResultsCopy.global_best(99, {"rows": []}), "an empty board: no global claim")
	t.ok(ResultsCopy.global_best(1, {"rows": [{"score": 0}]}), "beating a 0 counts")
	# The unlock page chimes big as the lock springs.
	var unlock := FileAccess.get_file_as_string("res://game/ui/area_unlock_page.gd")
	t.ok(unlock.find("Sfx.chime_big()") >= 0 and unlock.find("Sfx.score_pop(true)") < 0, "the area unlock page plays the big chime at the lock")
