## Ads (docs/ADS.md, 2026-11-01; the 2026-11-12 policy: grace 3, the online
## ad on the way out, a practice ad, a reason): the policy table and its
## reasons, the facade's gate against a fake network (the count apart from
## the gate), the sound under an ad, the guard, the owner rule and the store
## nudge; an online heat's result counted at the buzzer and its ad on HOME /
## on the room ending under the page / none on a rematch; practice's one
## chance after five minutes of live play; the practice clock; and that
## App's moves go through the right seams.

var _slept: Array = []


## A scene mover that records the path instead of changing the scene.
class StubLoader extends SceneLoader:
	var gone: Array = []

	func go(path: String, _dest: Dictionary, _art := "", _extras: Array = []) -> void:
		gone.push_back(path)


func run(t) -> void:
	var root = Engine.get_main_loop().root
	var ads: Node = root.get_node_or_null("Ads")
	var store: Node = root.get_node_or_null("Store")
	var app: Node = root.get_node_or_null("App")
	var save: Node = root.get_node("SaveService")
	if ads == null or store == null or app == null:
		t.ok(false, "Ads, Store and App autoloads present")
		return
	_policy(t)
	_clock(t)
	await _facade(t, ads, store, app, save)
	_seams(t)


func _policy(t) -> void:
	var base := {"owner": false, "available": true, "ready": true, "matches_played": 10, "grace_matches": 3, "last_ad_at": -1.0, "now": 1000.0, "min_gap_s": 120}
	t.ok(AdPolicy.should_show(base), "a player past the grace, a loaded ad, no ad yet: show")
	t.eq(AdPolicy.reason(base), "", "…no reason against it")
	t.eq(AdPolicy.reason(base.merged({"owner": true}, true)), "owner", "an owner of remove_ads: never")
	t.eq(AdPolicy.reason(base.merged({"available": false}, true)), "not_started", "no network: never")
	t.eq(AdPolicy.reason(base.merged({"ready": false}, true)), "not_loaded", "nothing loaded: not now")
	t.eq(AdPolicy.reason(base.merged({"matches_played": 2}, true)), "grace", "inside the grace (3 results): not yet")
	t.ok(AdPolicy.should_show(base.merged({"matches_played": 3}, true)), "…the 4th result is the first that may")
	t.eq(AdPolicy.reason(base.merged({"last_ad_at": 900.0}, true)), "gap", "100 s after the last one: not yet (120 s gap)")
	t.ok(AdPolicy.should_show(base.merged({"last_ad_at": 880.0}, true)), "…120 s after: may")
	t.eq(AdPolicy.reason(base.merged({"owner": true, "ready": false}, true)), "owner", "the owner rule comes first")
	t.ok(AdPolicy.upsell_due(5, 5) and AdPolicy.upsell_due(10, 5), "the nudge on the 5th and 10th ad")
	t.ok(not AdPolicy.upsell_due(4, 5) and not AdPolicy.upsell_due(0, 5) and not AdPolicy.upsell_due(5, 0), "…not otherwise")


## Practice's play clock: frames add, a long frame counts as a stall, the
## background counts nothing, a new session starts at zero.
func _clock(t) -> void:
	var c := PracticeClock.new()
	for i in 10:
		c.tick(0.1)
	t.close(c.seconds, 1.0, 1e-6, "ten frames of a tenth: a second")
	c.tick(2.0)
	t.close(c.seconds, 1.0 + PracticeClock.MAX_FRAME_S, 1e-6, "a 2 s frame (a stall, a resume) counts %.2f" % PracticeClock.MAX_FRAME_S)
	c.tick(-1.0)
	c.tick(0.0)
	t.close(c.seconds, 1.25, 1e-6, "nothing from an empty frame")
	c.suspend()
	c.tick(0.1)
	t.close(c.seconds, 1.25, 1e-6, "in the background: nothing counts")
	c.resume()
	c.tick(0.1)
	t.close(c.seconds, 1.35, 1e-6, "…back: it counts again")
	c.suspend()
	c.reset()
	t.ok(c.seconds == 0.0 and not c.suspended, "a new session: zero, live")


func _facade(t, ads, store, app, save) -> void:
	var was_backend = ads.backend
	var was_settings: Dictionary = save.get_settings()
	var was_owned: Dictionary = store._owned.duplicate()
	var was_rc: Array = store._rc_keys.duplicate()
	var was_srv: Array = store._srv_keys.duplicate()
	var fake := FakeAdsBackend.new()
	ads.use_backend(fake)
	ads.cfg = ads._load_cfg()
	var now := [1000.0]
	ads.clock = func() -> float: return now[0]
	# A sleep that lasts one frame: an ad stays up across a test's synchronous asserts.
	ads.sleep = func(s: float) -> void:
		_slept.push_back(s)
		await Engine.get_main_loop().process_frame
	ads.last_ad_at = -1.0
	ads.ads_shown = 0
	store._rc_keys = []
	store._srv_keys = []
	store._merge_owned()
	var s: Dictionary = save.get_settings()
	s["adMatches"] = 0
	save.put_settings(s)
	t.eq(ads.policy("grace_matches"), 3, "data/ads.json: 3 results of grace (2026-11-12, was 6)")
	t.eq(ads.policy("min_gap_s"), 120, "…120 s between ads")
	t.eq(ads.policy("upsell_every"), 5, "…the nudge every 5")
	t.eq(ads.policy("practice_min_s"), 300, "…five minutes of practice before its ad")
	t.eq(ads.DEFAULT_POLICY, {"grace_matches": 3, "min_gap_s": 120, "upsell_every": 5, "practice_min_s": 300}, "the built-in default says the same")
	t.eq(str(ads.platform_cfg("iOS").get("app_id", "")), "ca-app-pub-3569871537594448~6449564013", "data/ads.json: the iOS AdMob app id")
	t.eq(str(ads.platform_cfg("iOS").get("interstitial", "")), "ca-app-pub-3569871537594448/6439001907", "…and the real interstitial unit (the App Store release, 2026-11-07), never Google's test unit")
	var real_cfg: Dictionary = ads.cfg
	ads.cfg = {"ios": {"app_id": "ca-app-pub-REPLACE_ME~REPLACE_ME", "interstitial": "ca-app-pub-REPLACE_ME/REPLACE_ME"}, "policy": real_cfg.get("policy", {})}
	t.eq(ads.platform_cfg("iOS"), {}, "placeholder ids are no ids")
	ads.cfg = real_cfg
	t.ok(not ads.started(), "nothing started yet")
	t.eq(ads.reason(), "not_started", "…and the policy says so")
	ads.start_if_needed()
	t.ok(ads.started() and fake.starts.size() == 1, "start_if_needed starts the network once…")
	t.eq(fake.loads, 1, "…which loads the first interstitial")
	ads.start_if_needed()
	t.eq(fake.starts.size(), 1, "…and not again")
	var calls := [0]
	var then := func() -> void: calls[0] += 1
	var events: Array = []
	ads.ad_started.connect(func() -> void: events.push_back("started"))
	ads.ad_finished.connect(func(shown: bool) -> void: events.push_back("finished %s" % shown))
	# The grace: the first three results go straight through.
	for i in 3:
		ads.before_results(then)
	t.eq(calls[0], 3, "three results inside the grace: straight to the screen")
	t.eq(fake.shows, 0, "…no ad")
	t.eq(ads.matches_played(), 3, "…counted in the synced settings")
	t.eq(ads.last_reason, "grace", "…the reason: the grace")
	# The fourth: an ad, the sound off under it, then the screen.
	fake.auto = false
	ads.before_results(then)
	t.ok(ads.showing() and fake.shows == 1 and calls[0] == 3, "the 4th result: the interstitial is up, the screen waits")
	t.eq(ads.last_reason, "shown", "…the reason: shown")
	t.ok(not Sfx.music_sound() and not Sfx.sfx_sound(), "…the game's sound off under it")
	t.eq(events, ["started"], "…ad_started")
	t.eq(ads.reason(), "not_loaded", "…another gate meanwhile would not show (one is up)")
	fake.close()
	t.ok(not ads.showing() and calls[0] == 4, "closed: the screen")
	t.ok(Sfx.music_sound() == App.music_sound and Sfx.sfx_sound() == App.sfx_sound, "…the sound back to the settings")
	t.eq(events, ["started", "finished true"], "…ad_finished(shown)")
	t.eq(ads.ads_shown, 1, "one ad shown")
	t.eq(ads.last_ad_at, 1000.0, "…at the clock")
	t.eq(fake.loads, 2, "…and the next one loading")
	# The gap.
	fake.auto = true
	now[0] = 1060.0
	ads.before_results(then)
	t.ok(calls[0] == 5 and fake.shows == 1, "60 s later: no ad, straight through")
	t.eq(ads.last_reason, "gap", "…the reason: the gap")
	now[0] = 1120.0
	ads.before_results(then)
	t.ok(calls[0] == 6 and fake.shows == 2 and ads.ads_shown == 2, "120 s later: the next ad")
	# A show that fails, nothing loaded: through, nothing counted.
	now[0] = 2000.0
	fake.show_outcome = "failed"
	ads.before_results(then)
	t.ok(calls[0] == 7 and fake.shows == 3 and ads.ads_shown == 2 and ads.last_ad_at == 1120.0, "a failed show: the screen, nothing counted")
	t.eq(events.back(), "finished false", "…ad_finished(false)")
	t.eq(ads.last_reason, "failed", "…the reason: failed")
	fake.show_outcome = "shown"
	fake.ready_ = false
	ads.before_results(then)
	t.ok(calls[0] == 8 and fake.shows == 3, "nothing loaded: straight through")
	t.eq(ads.last_reason, "not_loaded", "…the reason: not loaded")
	fake.ready_ = true
	# The gate on its own counts nothing; the count on its own shows nothing.
	var played: int = ads.matches_played()
	ads.gate(then, "test")
	t.ok(calls[0] == 9 and fake.shows == 4 and ads.matches_played() == played, "gate: the ad, no result counted")
	ads.last_ad_at = -1.0
	ads.count_result()
	t.ok(ads.matches_played() == played + 1 and fake.shows == 4 and calls[0] == 9, "count_result: a result, no ad")
	ads.gate(Callable(), "test")
	t.ok(fake.shows == 5 and not ads.showing(), "a gate with nothing to run after shows and finishes clean")
	ads.last_ad_at = -1.0
	# Practice: one chance after practice_min_s of play, never a result.
	played = ads.matches_played()
	ads.after_practice(299.9, then)
	t.ok(calls[0] == 10 and fake.shows == 5 and ads.last_reason == "practice_short", "4:59 of practice: straight home, practice_short")
	ads.after_practice(300.0, then)
	t.ok(calls[0] == 11 and fake.shows == 6 and ads.last_reason == "shown", "5:00: the ad")
	t.eq(ads.matches_played(), played, "…and practice never counts as a result")
	ads.last_ad_at = -1.0
	fake.ready_ = false
	ads.after_practice(600.0, then)
	t.ok(calls[0] == 12 and fake.shows == 6 and ads.last_reason == "not_loaded", "nothing loaded at the quit: skipped, no retry")
	fake.ready_ = true
	# The guard: an ad that never reports back.
	fake.auto = false
	_slept.clear()
	ads.before_results(then)
	t.eq(_slept, [ads.GUARD_S], "an ad up: the guard waits GUARD_S…")
	t.ok(ads.showing() and calls[0] == 12, "…the screen waiting meanwhile")
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	t.ok(not ads.showing() and calls[0] == 13, "…and moves on when nothing came back")
	t.eq(ads.last_reason, "failed", "…noted as failed")
	t.ok(Sfx.music_sound() == App.music_sound, "…sound back")
	fake.close()
	t.eq(calls[0], 13, "a late close changes nothing")
	fake.auto = true
	# The nudge: on the 5th ad, once.
	ads.ads_shown = 4
	ads.last_ad_at = -1.0
	ads.before_results(then)
	t.ok(ads.ads_shown == 5 and ads.take_upsell(), "the 5th ad: the store nudge is due")
	t.ok(not ads.take_upsell(), "…and taken once")
	ads.last_ad_at = -1.0
	ads.before_results(then)
	t.ok(not ads.take_upsell(), "the 6th: no nudge")
	# Online: the result counts at the buzzer, the ad on the way out.
	ads.last_ad_at = -1.0
	_online(t, ads, app, save, fake, now)
	# An owner: never an ad, and a fresh network never starts.
	store._srv_keys = ["remove_ads"]
	store._merge_owned()
	t.ok(ads.owner(), "remove_ads owned")
	ads.last_ad_at = -1.0
	var shows := fake.shows
	ads.before_results(then)
	t.ok(calls[0] == 16 and fake.shows == shows and ads.last_reason == "owner", "an owner: straight through, the reason: owner")
	var fresh := FakeAdsBackend.new()
	ads.use_backend(fresh)
	ads.start_if_needed()
	t.ok(not ads.started() and fresh.starts.is_empty(), "…and the network is never started for them")
	# Put the world back.
	ads.use_backend(was_backend)
	ads.clock = Callable()
	ads.sleep = Callable()
	ads.last_ad_at = -1.0
	ads.ads_shown = 0
	ads.last_reason = ""
	store._rc_keys = was_rc
	store._srv_keys = was_srv
	store._merge_owned()
	store._owned = was_owned
	save.put_settings(was_settings)
	Sfx.set_music_sound(App.music_sound)
	Sfx.set_sfx_sound(App.sfx_sound)


## An online heat through App with a fake peer as the room and a stub scene
## mover: no ad before the post-match page (the rematch window is open), the
## ad on HOME with the room closed first, the ad right when the room ends
## under the page (once), none on HOME after that; and practice's QUIT.
func _online(t, ads, app, save, fake, now: Array) -> void:
	var was_loader = app.loader
	var was_heat: Dictionary = app.last_heat.duplicate(true)
	var was_next = app.next_heat
	var was_settle: Dictionary = app.online_settle.duplicate(true)
	var was_room = app.room
	var was_how: String = app.match_how
	var was_state: String = app.rematch_state
	var was_scene = Engine.get_main_loop().current_scene
	var stub := StubLoader.new()
	app.loader = stub
	var s: Dictionary = save.get_settings()
	s["adMatches"] = 20
	save.put_settings(s)
	var peer := QaFakePeer.new()
	app.room = peer
	app.match_how = "create"
	app.rematch_state = ""
	app.online_settle = {}
	app.last_heat = {}
	app.next_heat = {"remote": true, "ranked": false, "their_level": 4, "opponent": {"name": "THEM", "tag": "07"}}
	app.settle_heat({"won": true, "player_score": 30, "ai_score": 20, "ot": 0, "online": true,
		"sides": {"player": {"makes": 15, "attempts": 25, "swishes": 5, "bestStreak": 6, "bonus": 3, "iced": 0},
			"ai": {"makes": 10, "attempts": 25, "swishes": 2, "bestStreak": 3, "bonus": 0, "iced": 0}}})
	t.ok(bool(app.last_heat.get("online", false)), "an online heat settled")
	var shows: int = fake.shows
	app.to_heat_result()
	t.ok(fake.shows == shows and stub.gone.back() == app.HEAT_RESULT_SCENE, "online: no ad, straight to the post-match page")
	t.eq(ads.matches_played(), 21, "…the result counted")
	t.ok(app.room == peer, "…the room still open (the rematch window)")
	# HOME: the room closes first, then the ad, then the title.
	var room_at_ad: Array = []
	var on_start := func() -> void: room_at_ad.push_back(app.room)
	ads.ad_started.connect(on_start)
	var screen_script: GDScript = load("res://game/screens/heat_result_screen.gd")
	var screen: Node = screen_script.new()
	var chrome: Control = screen.build_chrome(app.last_heat, {}, {})
	t.ok(chrome.find_child("Rematch", true, false) != null, "the page carries REMATCH? while the room is open")
	fake.auto = false
	var moves: int = stub.gone.size()
	(chrome.find_child("Home", true, false) as Button).pressed.emit()
	t.ok(fake.shows == shows + 1 and ads.showing(), "HOME: the ad goes up")
	t.ok(app.room == null and peer.is_queued_for_deletion(), "…the room closed")
	t.eq(room_at_ad, [null], "…BEFORE the ad went up")
	t.eq(stub.gone.size(), moves, "…and the title waits")
	fake.close()
	t.ok(stub.gone.back() == app.TITLE_SCENE and stub.gone.size() == moves + 1, "closed: home")
	t.eq(ads.last_reason, "shown", "…reason shown")
	chrome.free()
	fake.auto = true
	# The room ending under the page (they left, the window expired): the ad
	# right then, once; HOME after it gates nothing.
	ads.last_ad_at = -1.0
	app.match_how = "create"
	app.rematch_state = ""
	peer = QaFakePeer.new()
	app.room = peer
	chrome = screen.build_chrome(app.last_heat, {}, {})
	screen.watch_room()
	moves = stub.gone.size()
	shows = fake.shows
	room_at_ad.clear()
	app._set_rematch("gone")
	t.ok(fake.shows == shows + 1 and app.room == null and room_at_ad == [null], "the room gone: the ad, the dead room cleared first")
	t.eq(stub.gone.size(), moves, "…the page stays (THEY LEFT)")
	t.ok(screen.gone_gated(), "…noted on the page")
	app._set_rematch("gone")
	t.eq(fake.shows, shows + 1, "a second gone: nothing")
	ads.last_ad_at = -1.0
	(chrome.find_child("Home", true, false) as Button).pressed.emit()
	t.ok(fake.shows == shows + 1 and stub.gone.back() == app.TITLE_SCENE, "HOME after it: straight home, no second ad")
	screen.unwatch_room()
	chrome.free()
	# A page that opens with the room already gone gates at once.
	ads.last_ad_at = -1.0
	app.rematch_state = "gone"
	var late: Node = screen_script.new()
	late.watch_room()
	t.eq(fake.shows, shows + 2, "a page opened on a dead room: the ad at once")
	late.free()
	screen.free()
	ads.ad_started.disconnect(on_start)
	# Practice's QUIT on a bare screen: the clock decides, never a result.
	var tts: Node = load("res://game/screens/time_trial_screen.gd").new()
	tts._practice = true
	ads.last_ad_at = -1.0
	shows = fake.shows
	var played: int = ads.matches_played()
	tts._play_clock.seconds = 299.0
	tts._quit_to_title()
	t.ok(fake.shows == shows and stub.gone.back() == app.TITLE_SCENE and ads.last_reason == "practice_short", "QUIT at 4:59: home, no ad")
	tts._play_clock.seconds = 300.0
	tts._quit_to_title()
	t.ok(fake.shows == shows + 1 and ads.last_reason == "shown", "QUIT at 5:00: the ad")
	t.eq(ads.matches_played(), played, "…practice is no result")
	tts._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	tts._play_clock.tick(0.1)
	t.close(tts.play_seconds(), 300.0, 1e-6, "in the background the clock stops")
	tts._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	tts._play_clock.tick(0.1)
	t.close(tts.play_seconds(), 300.1, 1e-6, "…and runs again in front")
	tts._practice = false
	ads.last_ad_at = -1.0
	tts._quit_to_title()
	t.eq(fake.shows, shows + 1, "a time trial's QUIT: no ad")
	tts.free()
	# Put App back.
	app.loader = was_loader
	app.last_heat = was_heat
	app.next_heat = was_next
	app.online_settle = was_settle
	app.room = was_room
	app.match_how = was_how
	app.rematch_state = was_state
	stub.free()
	t.ok(Engine.get_main_loop().current_scene == was_scene, "no scene was changed under the suite")


## App's moves go through the right seams (a read of the source: the moves
## themselves need the loader and a scene).
func _seams(t) -> void:
	var src := FileAccess.get_file_as_string("res://game/autoload/app.gd")
	t.eq(src.count("Ads.before_results("), 2, "finish_run and to_heat_result go through Ads.before_results")
	t.ok(src.contains("Ads.before_results(func() -> void: _move(RESULTS_SCENE") and src.contains("Ads.before_results(move)"), "…wrapping the two scene moves")
	t.ok(src.contains("if bool(last_heat.get(\"online\", false)):\n\t\t# Online") and src.count("Ads.count_result()") == 1, "to_heat_result counts an online result and moves at once")
	t.eq(src.count("Ads.gate("), 1, "one gate in App: leave_online")
	t.ok(src.contains("func leave_online(then: Callable) -> void:\n\tcancel_online()\n\tAds.gate(then, \"online\")"), "…the room closed before the ad, then the destination")
	t.ok(src.contains("leave_online(func() -> void: start_area(\"trial\""), "SHOOT AROUND? leaves through it")
	var go := src.substr(src.find("func _rematch_go("), 400)
	t.ok(not go.contains("Ads."), "a rematch that goes shows no ad")
	var hs := FileAccess.get_file_as_string("res://game/screens/heat_screen.gd")
	t.ok(hs.contains("Ads.before_results(App.to_title)"), "the Area Unlock page's GO THERE counts and gates like LATER")
	t.ok(hs.contains("\"failed\":\n\t\t\t# They left") and hs.contains("App.leave_online(App.to_title)"), "a rematch's room failing before the tip-off leaves through leave_online")
	var rs := FileAccess.get_file_as_string("res://game/screens/results_screen.gd")
	var hr := FileAccess.get_file_as_string("res://game/screens/heat_result_screen.gd")
	t.ok(rs.contains("AdsUpsell.maybe_toast(chrome)") and hr.contains("AdsUpsell.maybe_toast(chrome)"), "both results screens ask for the nudge (on the chrome, a full-rect control: a side toast needs one)")
	t.ok(hr.contains("if bool(heat.get(\"online\", false)):\n\t\twatch_room.call_deferred()"), "an online post-match page watches for the room ending")
	var tts := FileAccess.get_file_as_string("res://game/screens/time_trial_screen.gd")
	t.ok(tts.contains("elif not _match_held():\n\t\t_step_rules(minf(dt, MAX_FRAME_DT))\n\t\tif _practice:\n\t\t\t_play_clock.tick(dt)"), "practice's clock ticks only on a live frame: not the lesson, not a hold")
	t.ok(tts.contains("resume_game()\n\t\t_quit_to_title()"), "QUIT goes through _quit_to_title")
	t.ok(not tts.contains("Ads.count_result") and not tts.contains("Ads.before_results"), "…and practice never counts a result")
