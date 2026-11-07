## Ads (docs/ADS.md, 2026-11-01): the policy table, the facade's gate before
## a results screen against a fake network, the sound under an ad, the
## guard, the owner rule and the store nudge; and that App's two results
## moves go through the gate.

var _slept: Array = []


func run(t) -> void:
	var root = Engine.get_main_loop().root
	var ads: Node = root.get_node_or_null("Ads")
	var store: Node = root.get_node_or_null("Store")
	var save: Node = root.get_node("SaveService")
	if ads == null or store == null:
		t.ok(false, "Ads and Store autoloads present")
		return
	_policy(t)
	await _facade(t, ads, store, save)
	_seams(t)


func _policy(t) -> void:
	var base := {"owner": false, "available": true, "ready": true, "matches_played": 10, "grace_matches": 6, "last_ad_at": -1.0, "now": 1000.0, "min_gap_s": 120}
	t.ok(AdPolicy.should_show(base), "a player past the grace, a loaded ad, no ad yet: show")
	t.ok(not AdPolicy.should_show(base.merged({"owner": true}, true)), "an owner of remove_ads: never")
	t.ok(not AdPolicy.should_show(base.merged({"available": false}, true)), "no network: never")
	t.ok(not AdPolicy.should_show(base.merged({"ready": false}, true)), "nothing loaded: not now")
	t.ok(not AdPolicy.should_show(base.merged({"matches_played": 5}, true)), "inside the grace (6 results): not yet")
	t.ok(AdPolicy.should_show(base.merged({"matches_played": 6}, true)), "…the 7th result is the first that may")
	t.ok(not AdPolicy.should_show(base.merged({"last_ad_at": 900.0}, true)), "100 s after the last one: not yet (120 s gap)")
	t.ok(AdPolicy.should_show(base.merged({"last_ad_at": 880.0}, true)), "…120 s after: may")
	t.ok(AdPolicy.upsell_due(5, 5) and AdPolicy.upsell_due(10, 5), "the nudge on the 5th and 10th ad")
	t.ok(not AdPolicy.upsell_due(4, 5) and not AdPolicy.upsell_due(0, 5) and not AdPolicy.upsell_due(5, 0), "…not otherwise")


func _facade(t, ads, store, save) -> void:
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
	t.eq(ads.policy("grace_matches"), 6, "data/ads.json: 6 results of grace")
	t.eq(ads.policy("min_gap_s"), 120, "…120 s between ads")
	t.eq(ads.policy("upsell_every"), 5, "…the nudge every 5")
	t.eq(str(ads.platform_cfg("iOS").get("app_id", "")), "ca-app-pub-3569871537594448~6449564013", "data/ads.json: the iOS AdMob app id")
	t.eq(str(ads.platform_cfg("iOS").get("interstitial", "")), "ca-app-pub-3569871537594448/6439001907", "…and the real interstitial unit (the App Store release, 2026-11-07), never Google's test unit")
	var real_cfg: Dictionary = ads.cfg
	ads.cfg = {"ios": {"app_id": "ca-app-pub-REPLACE_ME~REPLACE_ME", "interstitial": "ca-app-pub-REPLACE_ME/REPLACE_ME"}, "policy": real_cfg.get("policy", {})}
	t.eq(ads.platform_cfg("iOS"), {}, "placeholder ids are no ids")
	ads.cfg = real_cfg
	t.ok(not ads.started(), "nothing started yet")
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
	# The grace: the first six results go straight through.
	for i in 6:
		ads.before_results(then)
	t.eq(calls[0], 6, "six results inside the grace: straight to the screen")
	t.eq(fake.shows, 0, "…no ad")
	t.eq(ads.matches_played(), 6, "…counted in the synced settings")
	# The seventh: an ad, the sound off under it, then the screen.
	fake.auto = false
	ads.before_results(then)
	t.ok(ads.showing() and fake.shows == 1 and calls[0] == 6, "the 7th result: the interstitial is up, the screen waits")
	t.ok(not Sfx.music_sound() and not Sfx.sfx_sound(), "…the game's sound off under it")
	t.eq(events, ["started"], "…ad_started")
	fake.close()
	t.ok(not ads.showing() and calls[0] == 7, "closed: the screen")
	t.ok(Sfx.music_sound() == App.music_sound and Sfx.sfx_sound() == App.sfx_sound, "…the sound back to the settings")
	t.eq(events, ["started", "finished true"], "…ad_finished(shown)")
	t.eq(ads.ads_shown, 1, "one ad shown")
	t.eq(ads.last_ad_at, 1000.0, "…at the clock")
	t.eq(fake.loads, 2, "…and the next one loading")
	# The gap.
	fake.auto = true
	now[0] = 1060.0
	ads.before_results(then)
	t.ok(calls[0] == 8 and fake.shows == 1, "60 s later: no ad, straight through")
	now[0] = 1120.0
	ads.before_results(then)
	t.ok(calls[0] == 9 and fake.shows == 2 and ads.ads_shown == 2, "120 s later: the next ad")
	# A show that fails, nothing loaded: through, nothing counted.
	now[0] = 2000.0
	fake.show_outcome = "failed"
	ads.before_results(then)
	t.ok(calls[0] == 10 and fake.shows == 3 and ads.ads_shown == 2 and ads.last_ad_at == 1120.0, "a failed show: the screen, nothing counted")
	t.eq(events.back(), "finished false", "…ad_finished(false)")
	fake.show_outcome = "shown"
	fake.ready_ = false
	ads.before_results(then)
	t.ok(calls[0] == 11 and fake.shows == 3, "nothing loaded: straight through")
	fake.ready_ = true
	# The guard: an ad that never reports back.
	fake.auto = false
	_slept.clear()
	ads.before_results(then)
	t.eq(_slept, [ads.GUARD_S], "an ad up: the guard waits GUARD_S…")
	t.ok(ads.showing() and calls[0] == 11, "…the screen waiting meanwhile")
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	t.ok(not ads.showing() and calls[0] == 12, "…and moves on when nothing came back")
	t.ok(Sfx.music_sound() == App.music_sound, "…sound back")
	fake.close()
	t.eq(calls[0], 12, "a late close changes nothing")
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
	# An owner: never an ad, and a fresh network never starts.
	store._srv_keys = ["remove_ads"]
	store._merge_owned()
	t.ok(ads.owner(), "remove_ads owned")
	ads.last_ad_at = -1.0
	ads.before_results(then)
	t.ok(calls[0] == 15 and fake.shows == 5, "an owner: straight through")
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
	store._rc_keys = was_rc
	store._srv_keys = was_srv
	store._merge_owned()
	store._owned = was_owned
	save.put_settings(was_settings)
	Sfx.set_music_sound(App.music_sound)
	Sfx.set_sfx_sound(App.sfx_sound)


## App's two results moves go through the gate (a read of the source: the
## moves themselves need the loader and a scene).
func _seams(t) -> void:
	var src := FileAccess.get_file_as_string("res://game/autoload/app.gd")
	t.eq(src.count("Ads.before_results("), 2, "finish_run and to_heat_result both go through Ads.before_results")
	t.ok(src.contains("Ads.before_results(func() -> void: _move(RESULTS_SCENE") and src.contains("Ads.before_results(func() -> void: _move(HEAT_RESULT_SCENE"), "…wrapping the two scene moves")
	var rs := FileAccess.get_file_as_string("res://game/screens/results_screen.gd")
	var hs := FileAccess.get_file_as_string("res://game/screens/heat_result_screen.gd")
	t.ok(rs.contains("AdsUpsell.maybe_toast(chrome)") and hs.contains("AdsUpsell.maybe_toast(chrome)"), "both results screens ask for the nudge (on the chrome, a full-rect control: a side toast needs one)")
