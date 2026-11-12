extends Node
## `Ads` (autoload; docs/ADS.md, Ross 2026-11-01): interstitials between
## games for everyone who does not own remove_ads, through an AdsBackend
## (AdMob on the phone, the null one elsewhere). Two moves, apart since
## 2026-11-12: `count_result()` counts a finished result toward the grace,
## `gate(then, where)` asks the policy and plays the ad — with the game's
## sound off — and runs `then` when it closes, or at once when there is
## nothing to show, or after GUARD_S when the network never answers.
## `before_results(then)` is both (the AI heats and the time trials: the ad
## before the results); an online heat counts at the buzzer and gates on
## the way OUT (App.leave_online); practice gates once on QUIT after
## `practice_min_s` of play (`after_practice`), counting nothing. An owner
## never starts the SDK (no consent or tracking prompts); buying remove_ads
## mid-session stops the ads at the next policy check. `last_reason` says
## why the last gate did or did not show one (debug: a push_warning too).

## An interstitial is going up / came down (`shown` false = nothing played).
signal ad_started
signal ad_finished(shown: bool)

const PATH := "res://data/ads.json"
const PLACEHOLDER := "REPLACE_ME"
## An ad that never reports back is given up on after this long.
const GUARD_S := 8.0
const DEFAULT_POLICY := {"grace_matches": 3, "min_gap_s": 120, "upsell_every": 5, "practice_min_s": 300}
## Every verdict `last_reason` can hold.
const REASONS := ["shown", "failed", "owner", "not_started", "not_loaded", "grace", "gap", "practice_short"]

var backend: AdsBackend = AdsBackend.new()
var cfg: Dictionary = {}
var last_ad_at := -1.0
var ads_shown := 0
## Why the last gate did (shown) or did not show an ad — one of REASONS.
## Nothing user-facing: the QA driver and the debug log read it.
var last_reason := ""
var _started := false
var _showing := false
var _then: Callable = Callable()
var _upsell_pending := false
## Tests: a stand-in clock and sleep (no timers off-tree).
var clock: Callable = Callable()
var sleep: Callable = Callable()


func _ready() -> void:
	cfg = _load_cfg()
	backend = AdMobBackend.new()   # available only where the plugin was staged in
	_connect_backend()
	Net.account_ready.connect(func(_n: String, _t: String) -> void: start_if_needed())
	start_if_needed.call_deferred()


func _load_cfg() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {"policy": DEFAULT_POLICY.duplicate()}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return Dictionary(parsed) if parsed is Dictionary else {"policy": DEFAULT_POLICY.duplicate()}


## This platform's ids from data/ads.json; empty when they are placeholders.
func platform_cfg(os_name := OS.get_name()) -> Dictionary:
	var which := "ios" if os_name == "iOS" else ("android" if os_name == "Android" else "")
	var block: Dictionary = Dictionary(cfg.get(which, {})) if which != "" else {}
	for v in block.values():
		if str(v).contains(PLACEHOLDER):
			return {}
	return block


func policy(key: String) -> int:
	return int(Dictionary(cfg.get("policy", {})).get(key, DEFAULT_POLICY.get(key, 0)))


func _connect_backend() -> void:
	backend.interstitial_closed.connect(_on_closed)
	backend.started.connect(func() -> void: backend.load_interstitial())


## A fake backend (tests, QA) in place of the plugin.
func use_backend(b: AdsBackend) -> void:
	if backend.interstitial_closed.is_connected(_on_closed):
		backend.interstitial_closed.disconnect(_on_closed)
	backend = b
	_connect_backend()
	_started = false
	_showing = false
	_then = Callable()


func owner() -> bool:
	return Store.owns(Store.REMOVE_ADS)


## The network, once, for a player who sees ads: consent, the tracking
## prompt, the SDK, the first interstitial loading. Owners skip all of it.
func start_if_needed() -> void:
	if _started or owner() or not backend.available():
		return
	var pc := platform_cfg()
	if pc.is_empty() and not backend.accepts_empty_cfg():
		return
	_started = true
	backend.start(pc)


func started() -> bool:
	return _started


## Results so far (the grace period counts them), in the synced settings.
func matches_played() -> int:
	return int(SaveService.get_settings().get("adMatches", 0))


## A finished result (a heat's, a trial's) toward the grace. Practice is
## not one.
func count_result() -> void:
	var s := SaveService.get_settings()
	s["adMatches"] = int(s.get("adMatches", 0)) + 1
	SaveService.put_settings(s)


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() / 1000.0


## The policy's verdict right now: "" to show, else why not (AdPolicy.reason).
func reason() -> String:
	if _showing:
		return "not_loaded"   # one is up already
	return AdPolicy.reason({
		"owner": owner(), "available": backend.available() and _started, "ready": backend.ready(),
		"matches_played": matches_played(), "grace_matches": policy("grace_matches"),
		"last_ad_at": last_ad_at, "now": _now(), "min_gap_s": policy("min_gap_s"),
	})


## Would a gate show an ad (the policy, right now)?
func due() -> bool:
	return reason() == ""


## The gate before a results screen: the result counts toward the grace,
## and `then` moves there, after the ad or at once. The policy decides
## BEFORE the count: the grace is the results before this one.
func before_results(then: Callable) -> void:
	var r := reason()
	count_result()
	_run(r, then, "results")


## The gate on its own (nothing counted): `then` runs after the ad or at
## once. `where` names the moment for the debug log (online, practice…).
func gate(then: Callable, where: String) -> void:
	_run(reason(), then, where)


## Leaving practice: one chance at an ad when the session's live play ran
## `practice_min_s` or more; under that, straight on. Never a result.
func after_practice(play_s: float, then: Callable) -> void:
	if play_s < float(policy("practice_min_s")):
		_note("practice_short", "practice")
		_call(then)
		return
	gate(then, "practice")


func _run(why: String, then: Callable, where: String) -> void:
	if why != "":
		_note(why, where)
		_call(then)
		return
	_note("shown", where)
	_then = then
	_showing = true
	_mute(true)
	ad_started.emit()
	backend.show_interstitial()
	_guard()


func _note(why: String, where: String) -> void:
	last_reason = why
	if OS.is_debug_build():
		push_warning("ads: %s (%s)" % [why, where])


func _call(then: Callable) -> void:
	if then.is_valid():
		then.call()


func showing() -> bool:
	return _showing


func _guard() -> void:
	await _sleep(GUARD_S)
	if _showing:
		push_warning("ads: the interstitial never reported back; moving on")
		_finish(false)


func _on_closed(shown: bool) -> void:
	if _showing:
		_finish(shown)


func _finish(shown: bool) -> void:
	_showing = false
	_mute(false)
	if shown:
		last_ad_at = _now()
		ads_shown += 1
		_upsell_pending = AdPolicy.upsell_due(ads_shown, policy("upsell_every"))
	else:
		last_reason = "failed"   # it went up on the policy's word and never played
	ad_finished.emit(shown)
	var then := _then
	_then = Callable()
	_call(then)
	backend.load_interstitial()   # the next one, ready before the next results


## The results screen asks once: is the "tired of ads?" nudge due?
func take_upsell() -> bool:
	var due_ := _upsell_pending
	_upsell_pending = false
	return due_


## The game's sound off under the ad (the buses, not the settings), back after.
func _mute(on: bool) -> void:
	Sfx.set_music_sound(false if on else App.music_sound)
	Sfx.set_sfx_sound(false if on else App.sfx_sound)


func _sleep(s: float) -> void:
	if sleep.is_valid():
		await sleep.call(s)
	elif is_inside_tree():
		await get_tree().create_timer(s).timeout
