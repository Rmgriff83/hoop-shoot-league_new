extends Node
## `Achievements` (autoload; docs/ACHIEVEMENTS.md): the one place that
## decides an achievement is earned and hands it to the platform. The game
## reports moments (`note_*`), AchievementRules says which keys they earn,
## and each key is unlocked once: kept in the device's account part
## (`achievements`), awarded through `Platform.backend.unlock(apple_id)`,
## and parked in `achievementsPending` when there is no signed-in platform
## to take it (flushed on the next sign-in). Game Center is the durable
## record: on every sign-in the player's earned list is loaded and merged
## back, so a reinstall (or the sandbox's reset) recovers from Apple, and
## anything held here that Apple lacks is reported again. A one-time
## backfill grants what the device's records already earned when this
## shipped. Server milestones arrive through Platform.milestone_unlocked
## (AchievementDefs.MILESTONE_MAP); the weekly board ranks through Net's
## score reply and board fetches. No in-game toast: Apple's banner.

## An achievement newly earned on this device (before the platform hears).
signal unlocked(key: String)
## The platform accepted the award call for a key.
signal reported(key: String)

const CACHE := "achievements"
const PENDING := "achievementsPending"
const BACKFILLED := "achievementsBackfilled"

## The in-match make / swish counters (the player's side only).
var tracker := AchievementRules.StreakTracker.new()
var _syncing := false


## The wiring is done at construction (the earlier autoloads exist by then)
## so the headless test runner, which never reaches a frame, sees it too.
func _init() -> void:
	Platform.milestone_unlocked.connect(_on_milestone)
	Platform.signed_in.connect(_on_signed_in)
	Platform.achievement_failed.connect(_on_award_failed)
	Net.score_accepted.connect(_on_score_accepted)
	Net.board_loaded.connect(_on_board_loaded)
	Net.save_pulled.connect(func(_parts: Array) -> void: backfill(true))


func _ready() -> void:
	backfill.call_deferred()
	if Platform.backend.is_signed_in():
		_on_signed_in.call_deferred()


# ---- the record ------------------------------------------------------------------

## The keys earned on this device (the roster's order is not kept).
func earned() -> Array:
	return Array(Net.account().get(CACHE, []))


func has(key: String) -> bool:
	return earned().has(key)


## Keys awarded here that no platform has taken yet.
func pending() -> Array:
	var out := []
	for p in Array(Net.account().get(PENDING, [])):
		out.push_back(str(p.get("key", "")) if p is Dictionary else str(p))
	return out


func count() -> int:
	return earned().size()


func points() -> int:
	var n := 0
	for k in earned():
		n += AchievementDefs.points(str(k))
	return n


## Earn `key` now: false when it is unknown or already held. `banner`:
## Apple's completion banner (off for the backfill's batch).
func unlock(key: String, banner := true) -> bool:
	if not AchievementDefs.has(key):
		push_warning("Achievements: unknown key %s" % key)
		return false
	var a := Net.account()
	var held := Array(a.get(CACHE, []))
	if held.has(key):
		return false
	held.push_back(key)
	a[CACHE] = held
	SaveService.put_account(a)
	unlocked.emit(key)
	_report(key, banner)
	return true


## Several at once (the rules' lists): the keys newly earned.
func unlock_all(keys: Array, banner := true) -> Array:
	var fresh := []
	for k in keys:
		if unlock(str(k), banner):
			fresh.push_back(str(k))
	return fresh


func _report(key: String, banner: bool) -> void:
	var be := Platform.backend
	if be.is_signed_in() and be.unlock(AchievementDefs.apple_id(key), banner):
		reported.emit(key)
		return
	_park(key, banner)


func _park(key: String, banner: bool) -> void:
	var a := Net.account()
	var p := Array(a.get(PENDING, []))
	for e in p:
		if (str(e.get("key", "")) if e is Dictionary else str(e)) == key:
			return
	p.push_back({"key": key, "banner": banner})
	a[PENDING] = p
	SaveService.put_account(a)


## Hand the parked keys to the platform (signed in): the ones it took.
func flush_pending() -> Array:
	var be := Platform.backend
	if not be.is_signed_in():
		return []
	var a := Net.account()
	var p := Array(a.get(PENDING, []))
	if p.is_empty():
		return []
	var left := []
	var sent := []
	for e in p:
		var key := str(e.get("key", "")) if e is Dictionary else str(e)
		var banner := bool(e.get("banner", true)) if e is Dictionary else true
		if AchievementDefs.has(key) and be.unlock(AchievementDefs.apple_id(key), banner):
			sent.push_back(key)
			reported.emit(key)
		else:
			left.push_back(e)
	a[PENDING] = left
	SaveService.put_account(a)
	return sent


## The platform's earned list (Apple ids) folded in: keys it has that this
## device lacks are remembered (no award), and keys held here that it
## lacks are parked for a quiet re-report. Returns the keys adopted.
func merge_remote(apple_ids: Array) -> Array:
	var remote := {}
	for id in apple_ids:
		var k := AchievementDefs.key_for_apple_id(str(id))
		if k != "":
			remote[k] = true
	var a := Net.account()
	var held := Array(a.get(CACHE, []))
	var adopted := []
	for k in remote:
		if not held.has(k):
			held.push_back(k)
			adopted.push_back(k)
	a[CACHE] = held
	SaveService.put_account(a)
	var pend := pending()
	for k in held:
		if not remote.has(k) and not pend.has(str(k)):
			_park(str(k), false)
	return adopted


## The platform signed in: park nothing, report everything, read Apple's list.
func _on_signed_in() -> void:
	if _syncing:
		return
	_syncing = true
	var be := Platform.backend
	var r: Dictionary = await be.load_achievements()
	if bool(r.get("ok", false)):
		merge_remote(Array(r.get("earned", [])))
	flush_pending()
	_syncing = false


## A platform award that failed after the call was accepted: parked again.
func _on_award_failed(apple_id: String) -> void:
	var k := AchievementDefs.key_for_apple_id(apple_id)
	if k != "":
		_park(k, true)


# ---- the moments -----------------------------------------------------------------

## A match (time trial or the player's side of a heat) starts: fresh streaks.
func reset_streaks() -> void:
	tracker.reset()


## One of the player's shots landed (never the tutorial's): an iced-out
## make counts as a miss. `timed` false (practice, no clock) earns only the
## first swish; the streaks want a time trial or a heat.
func note_shot(made: bool, swish: bool, timed := true) -> Array:
	if not timed:
		return unlock_all(["nothing_but_net"]) if made and swish else []
	return unlock_all(tracker.note(made, swish))


## A finished time trial (App.finish_run's run dict).
func note_run(run: Dictionary) -> Array:
	return unlock_all(AchievementRules.for_run(run))


## A league heat folded into the campaign (App._apply_league_heat).
func note_league_heat(ctx: Dictionary) -> Array:
	return unlock_all(AchievementRules.for_league_heat(ctx))


## The player deployed a card: its effect kind, the opponent's streak then.
func note_card(kind: String, opp_streak: int) -> Array:
	return unlock_all(AchievementRules.for_card(kind, opp_streak))


## A PEGGY drop landed (App.last_prize).
func note_prize(prize: Dictionary) -> Array:
	return unlock_all(AchievementRules.for_prize(prize))


## An online match settled (the room's settle message, App.match_how).
func note_settle(msg: Dictionary, how: String) -> Array:
	return unlock_all(AchievementRules.for_settle(msg, how))


## This player's rank on a weekly time-trial board.
func note_week_rank(rank: int) -> Array:
	return unlock_all(AchievementRules.for_week_rank(rank))


func _on_milestone(key: String) -> void:
	unlock_all(AchievementDefs.for_milestones([key]))


func _on_score_accepted(_area: String, reply: Dictionary) -> void:
	if reply.get("weekRank") != null:
		note_week_rank(int(reply.get("weekRank", 0)))


func _on_board_loaded(_area: String, period: String, data: Dictionary) -> void:
	if period != "week" or not (data.get("me") is Dictionary):
		return
	note_week_rank(int(str(Dictionary(data["me"]).get("rank", 0)).trim_prefix("#")))


# ---- the backfill ------------------------------------------------------------------

## What the device's records already earn, granted quietly once (again
## after a save pull, `force`): the keys newly earned.
func backfill(force := false) -> Array:
	var a := Net.account()
	if bool(a.get(BACKFILLED, false)) and not force:
		return []
	var fresh := unlock_all(AchievementRules.backfill(backfill_state()), false)
	a = Net.account()
	a[BACKFILLED] = true
	SaveService.put_account(a)
	return fresh


## The plain-dict view of the records AchievementRules.backfill reads.
func backfill_state() -> Dictionary:
	var leagues := []
	for l in LeagueData.leagues():
		var doc := SaveService.league_doc(str(l.get("id", "")))
		if doc.is_empty() or not (doc.get("career") is Dictionary):
			continue
		var career: Dictionary = doc["career"]
		var totals: Dictionary = career.get("totals", {}) if career.get("totals") is Dictionary else {}
		var highs: Dictionary = career.get("highs", {}) if career.get("highs") is Dictionary else {}
		leagues.push_back({"id": str(l.get("id", "")), "championships": int(career.get("championships", 0)),
			"wins": int(totals.get("wins", 0)), "best_streak": int(highs.get("streak", 0))})
	var prizes := []
	var roster := {}
	for e in App.peggy_roster():
		roster[str(e.get("id", ""))] = str(e.get("rarity", "common"))
	for kind in ["ball", "net"]:
		var starters := []
		for s in App._starters(kind):
			if s != null:
				starters.push_back(str(s.id))
		for id in App.owned_ids(kind):
			if roster.has(str(id)) and not starters.has(str(id)):
				prizes.push_back(roster[str(id)])
	return {"level": App.level(), "leagues": leagues, "runs": SaveService.top_scores(100000),   # (score_count trips on an unloaded part)
		"prizes": prizes, "milestones": Platform.unlocked()}


# ---- the sheet -------------------------------------------------------------------

## Apple's achievements sheet can open (a signed-in platform that has one).
func can_show() -> bool:
	var be := Platform.backend
	return be.is_available() and be.is_signed_in() and be.has_achievements_sheet()


func show_sheet() -> bool:
	if not can_show():
		return false
	return Platform.backend.show_achievements()
