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
	# Levelling up (Ross, 2026-10-26): heyheytheree's coin rings once as the
	# post-match XP meter fills to LEVEL UP; a plain fill never rings.
	var coin: AudioStream = load("res://assets/audio/level_up.wav")
	t.ok(coin != null and coin.get_length() > 0.9 and coin.get_length() < 1.4, "level_up ships (~1.1 s)")
	if sfx != null:
		t.ok(sfx.has_method("level_up"), "Sfx exposes level_up()")
	t.eq(str(urls.get("https://freesound.org/people/heyheytheree/sounds/872480/", {}).get("author", "")), "heyheytheree", "the coin is credited at Ross's link")
	var up := XpMeter.new({"level": 3, "level_before": 2, "need": 100, "gained": 40, "up": true, "cap": false, "from": 70, "to": 100}, 300.0)
	up.manual = true
	up.play(0.0)
	up.step(0.3)
	t.ok(not up.rang(), "no ring while the bar is still filling")
	up.step(XpMeter.FILL_S)
	t.ok(up.rang() and up.text() == "LEVEL UP · LEVEL 3", "the coin rings as the bar fills to LEVEL UP")
	up.step(1.0)
	t.ok(up.rang(), "…once (the flag holds)")
	up.free()
	var plain := XpMeter.new({"level": 2, "level_before": 2, "need": 100, "gained": 20, "up": false, "cap": false, "from": 30, "to": 50}, 300.0)
	plain.manual = true
	plain.play(0.0)
	plain.step(XpMeter.FILL_S + 1.0)
	t.ok(not plain.rang(), "a fill short of a level never rings")
	plain.free()
	# A clean swish rings the till (Ross, 2026-10-26): mokasza's cash register,
	# trimmed and sped up, on the SWISH branch of the scoring; credited.
	var till: AudioStream = load("res://assets/audio/swish_register.wav")
	t.ok(till != null and till.get_length() > 1.2 and till.get_length() < 1.7, "swish_register ships trimmed (~1.5 s)")
	if sfx != null:
		t.ok(sfx.has_method("swish_register"), "Sfx exposes swish_register()")
	t.eq(str(urls.get("https://freesound.org/people/mokasza/sounds/810738/", {}).get("author", "")), "mokasza", "the till is credited")
	var screen := FileAccess.get_file_as_string("res://game/screens/time_trial_screen.gd")
	t.ok(screen.find("if is_swish:\n\t\t\tSfx.swish_register()") >= 0, "the till rings on a swish")
	# On fire and paid extra (Ross, 2026-10-26): gavynator's coin on a make at
	# tier 2+ that is not a swish — a swish keeps the till; credited.
	var coin2: AudioStream = load("res://assets/audio/streak_coin.wav")
	t.ok(coin2 != null and coin2.get_length() > 0.15 and coin2.get_length() < 0.3, "streak_coin ships (~0.2 s)")
	if sfx != null:
		t.ok(sfx.has_method("streak_coin"), "Sfx exposes streak_coin()")
	t.eq(str(urls.get("https://freesound.org/people/gavynator/sounds/691965/", {}).get("author", "")), "gavynator", "the coin is credited")
	t.ok(screen.find("Sfx.swish_register()") < screen.find("elif lit and tier > 1:\n\t\t\tSfx.streak_coin()"), "the coin rings on a lit, extra-points make that is not a swish; a swish keeps the till")
	t.eq(StreakRules.base_points(StreakRules.FIRE_AT), 1, "(at FIRE_AT itself a make pays 1: no coin until the first tier)")
	t.ok(StreakRules.base_points(int(StreakRules.TIERS[0][0])) > 1, "…the first tier pays extra")
	# Losing a match (Ross, 2026-10-26): tommasomotteran's defeat stinger behind
	# Sfx.match_loss (the API the match-end page already calls); credited.
	var defeat: AudioStream = load("res://assets/audio/match_defeat.wav")
	t.ok(defeat != null and defeat.get_length() > 2.5 and defeat.get_length() < 3.1, "match_defeat ships (~2.8 s)")
	t.eq(str(urls.get("https://freesound.org/people/tommasomotteran/sounds/856516/", {}).get("author", "")), "tommasomotteran", "the defeat stinger is credited")
	var sfx_src := FileAccess.get_file_as_string("res://game/autoload/sfx.gd")
	t.ok(sfx_src.find("func match_loss() -> void:\n\t_play(\"match_defeat\"") >= 0, "match_loss plays the stinger")
	# The tickets gained (Ross, 2026-10-26): breviceps's card shuffle rings once
	# as the ticket stream's flyers launch on either end page; never with none.
	var shuf: AudioStream = load("res://assets/audio/ticket_shuffle.wav")
	t.ok(shuf != null and shuf.get_length() > 0.5 and shuf.get_length() < 0.8, "ticket_shuffle ships (~0.6 s)")
	if sfx != null:
		t.ok(sfx.has_method("ticket_shuffle"), "Sfx exposes ticket_shuffle()")
	t.eq(str(urls.get("https://freesound.org/people/breviceps/sounds/447918/", {}).get("author", "")), "breviceps", "the shuffle is credited")
	var stream := TicketStream.new()
	stream.manual = true
	stream.play(Vector2.ZERO, Vector2(100, 100), 12, 0.5)
	stream.step(0.2)
	t.ok(not stream.rang(), "quiet before the flyers launch")
	stream.step(0.4)
	t.ok(stream.rang(), "the shuffle rings as they launch")
	stream.step(3.0)
	t.ok(stream.rang(), "…once")
	stream.free()
	var none := TicketStream.new()
	none.manual = true
	none.play(Vector2.ZERO, Vector2(100, 100), 0, 0.0)
	none.step(1.0)
	t.ok(not none.rang(), "no tickets, no shuffle")
	none.free()
