extends RefCounted
## The first-play free PEGGY play (design 36c, docs/LOCKER.md → Free plays):
## a new player's first finished time trial or match gives one free play and
## queues the tour; a player from before it shipped gets neither.


func run(t) -> void:
	# The rule, pure.
	t.ok(PeggyGifts.is_first_play({}), "nothing played: this is the first play")
	t.ok(PeggyGifts.is_first_play({"scores": 0, "league_games": 0, "online_games": 0, "results": 0, "xp": 0, "drops": 0}), "…all zeros too")
	for k in PeggyGifts.PLAYED_FACTS:
		t.ok(not PeggyGifts.is_first_play({k: 1}), "an earlier play shows in %s: not the first" % k)
	var g := PeggyGifts.grant({"drops": 2}, "first_play")
	t.ok(bool(g["ok"]) and g["peggy"] == {"drops": 2, "gifts": ["first_play"], "free": 1}, "a grant adds the play and remembers the reason")
	t.ok(not bool(PeggyGifts.grant(g["peggy"], "first_play")["ok"]), "…once")
	t.ok(bool(PeggyGifts.grant(g["peggy"], "other", 2)["ok"]) and PeggyGifts.free_plays(PeggyGifts.grant(g["peggy"], "other", 2)["peggy"]) == 3, "another reason adds to it")
	t.eq(PeggyGifts.free_plays({"free": -3}), 0, "a bad count reads as none")
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	var save = Engine.get_main_loop().root.get_node_or_null("SaveService")
	var net = Engine.get_main_loop().root.get_node_or_null("Net")
	if app == null or save == null or net == null:
		return
	var was_settings: Dictionary = save.get_settings()
	var was_cos: Dictionary = save.get_cosmetics()
	var was_campaign: Dictionary = save.get_campaign()
	var was_progress: Dictionary = save.get_progress()
	var was_scores: Dictionary = save._scores
	var was_rank: Dictionary = net.me_rank
	# A brand-new save: nothing played.
	var fresh := func() -> void:
		var st: Dictionary = was_settings.duplicate(true)
		st.erase("adMatches")
		st.erase("firstPlayDone")
		st["walkthroughsSeen"] = []
		save.put_settings(st)
		var c: Dictionary = SaveService.default_cosmetics()
		c["tickets"] = 36
		save.put_cosmetics(c)
		save.put_campaign({"leagues": {}, "records": {}})
		var pr: Dictionary = was_progress.duplicate(true)
		pr["xp"] = 0
		save.put_progress(pr)
		save._scores = {"docs": []}
		net.me_rank = {}
	fresh.call()
	t.eq(app.first_play_facts(), {"scores": 0, "league_games": 0, "online_games": 0, "results": 0, "xp": 0, "drops": 0}, "a new save's facts are all zero")
	t.ok(not app.peggy_tour_due(), "no free play yet: no tour")
	app._note_first_play()
	t.eq(app.peggy_free_plays(), 1, "the first finished play gives one free PEGGY play")
	t.ok(bool(save.get_settings().get("firstPlayDone", false)), "…and the save remembers it decided")
	t.ok(app.peggy_tour_due(), "…the tour waits for the home")
	app._note_first_play()
	t.eq(app.peggy_free_plays(), 1, "the second finished play gives nothing more")
	t.eq(app.tickets(), 36, "tickets are untouched")
	app.mark_walkthrough_seen("peggy")
	t.ok(not app.peggy_tour_due(), "the tour seen (or skipped): not due")
	var st2: Dictionary = save.get_settings()
	st2["walkthroughsSeen"] = []
	save.put_settings(st2)
	t.ok(app.peggy_tour_due(), "(unseen again)")
	t.ok(app.peggy_insert_ticket(), "the free play is played")
	t.ok(not app.peggy_tour_due(), "…with it used, no tour")
	# A player from before the free play: each trace of an earlier play blocks it.
	var before := {
		"scores": func() -> void: save._scores = {"docs": [{"score": 12}]},
		"league_games": func() -> void: save.put_campaign({"leagues": {"cage": {"career": {"totals": {"games": 3}}}}, "records": {}}),
		"online_games": func() -> void: net.me_rank = {"games": 2},
		"results": func() -> void:
			var s: Dictionary = save.get_settings()
			s["adMatches"] = 1
			save.put_settings(s),
		"xp": func() -> void:
			var p: Dictionary = save.get_progress()
			p["xp"] = 40
			save.put_progress(p),
		"drops": func() -> void:
			var c: Dictionary = save.get_cosmetics()
			c["peggy"] = {"drops": 1}
			save.put_cosmetics(c),
	}
	for k in PeggyGifts.PLAYED_FACTS:
		fresh.call()
		(before[k] as Callable).call()
		t.ok(int(app.first_play_facts()[k]) > 0, "the save shows %s" % k)
		app._note_first_play()
		t.eq(app.peggy_free_plays(), 0, "a player with %s behind them gets no free play" % k)
		t.ok(bool(save.get_settings().get("firstPlayDone", false)) and not app.peggy_tour_due(), "…the decision is made once, no tour (%s)" % k)
	save._scores = was_scores
	net.me_rank = was_rank
	save.put_campaign(was_campaign)
	save.put_progress(was_progress)
	save.put_cosmetics(was_cos)
	save.put_settings(was_settings)
	# The wiring: both finished-play paths ask, the home hosts the tour.
	var app_src := FileAccess.get_file_as_string("res://game/autoload/app.gd")
	t.ok(app_src.contains("func finish_run(run: Dictionary) -> void:\n\t_note_first_play()"), "a finished time trial asks first")
	t.ok(app_src.contains("func settle_heat(result: Dictionary) -> Dictionary:\n\t_note_first_play()"), "a finished match asks first")
	var title_src := FileAccess.get_file_as_string("res://game/screens/title_screen.gd")
	t.ok(title_src.contains("elif _peggy_tour_ready():\n\t\t_start_peggy_tour()"), "the home starts the free-play tour on arrival")
	t.ok(title_src.contains("if not _open and _peggy_tour_ready():"), "…or when the league closes back to it")
	t.ok(title_src.contains("_open_peggy(true)") and title_src.contains("_make_locker()"), "OPEN PEGGY opens it from the home; its BACK builds the locker")
	t.ok(title_src.contains("_league_slide.finished.connect(_maybe_league_tour)"), "ENTER LEAGUE asks for the league tour once it has slid in")
