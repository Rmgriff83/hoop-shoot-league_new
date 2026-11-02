class_name AchievementRules
extends RefCounted
## When each achievement is earned (docs/ACHIEVEMENTS.md): pure functions
## over plain dictionaries, called by the autoload `Achievements` at the
## seven moments the game reports — a shot's outcome, a time trial's end, a
## league heat folded in, a card deployed, a PEGGY drop, an online settle,
## a weekly board rank — plus the one-time backfill over what a device
## already achieved before this shipped. Every function returns achievement
## keys (AchievementDefs); the caller dedupes against what is already held.
## No nodes, no RNG, no save access.

## Sharpshooter I / II / III: a time trial's score (Ross, 2026-11-02: any court).
const SHARPSHOOTER := [20, 30, 40]
## Perfect Run needs this many shots (a one-shot-then-wait run is not a run).
const PERFECT_RUN_MIN_SHOTS := 10
const HEATING_UP := 10
const ON_FIRE := 25
const PURE := 5
## Cold Shoulder: the opponent's make streak when the ice lands.
const COLD_SHOULDER_STREAK := 3
const HALL_OF_FAMER_LEVEL := 7
const BOARD_MEMBER_RANK := 100
## The card Big Steal wants captured.
const MAGNET_CARD := "magnet6"
## The areas with an unlock achievement (the cage is open from the start).
const AREA_KEYS := {"beach": "beach_bound", "park": "park_regular", "city": "city_lights"}
## A league title → its Champion achievement (league ids, data/leagues.json).
const TITLE_KEYS := {"cage": "cage_champion", "beach": "beach_champion", "park": "park_champion", "city": "city_champion"}


## The in-match counters: consecutive makes and swishes on the player's
## side. Any miss (an iced-out shot included) resets both; a swish counts
## as a make. Fresh per match.
class StreakTracker:
	extends RefCounted
	var makes := 0
	var swishes := 0

	func reset() -> void:
		makes = 0
		swishes = 0

	## The outcome of one shot → the achievement keys it crosses.
	func note(made: bool, swish: bool) -> Array:
		var out := []
		if not made:
			reset()
			return out
		makes += 1
		if swish:
			swishes += 1
			out.push_back("nothing_but_net")
		else:
			swishes = 0
		if makes == HEATING_UP:
			out.push_back("heating_up")
		if makes == ON_FIRE:
			out.push_back("on_fire")
		if swishes == PURE:
			out.push_back("pure")
		return out


## A finished (not practice) time trial: {score, makes, attempts, …}.
static func for_run(run: Dictionary) -> Array:
	var out := ["on_the_clock"]
	out.append_array(sharpshooter(int(run.get("score", 0))))
	var attempts := int(run.get("attempts", 0))
	if attempts >= PERFECT_RUN_MIN_SHOTS and int(run.get("makes", 0)) == attempts:
		out.push_back("perfect_run")
	return out


## The Sharpshooter tiers a score reaches.
static func sharpshooter(score: int) -> Array:
	var out := []
	for i in SHARPSHOOTER.size():
		if score >= int(SHARPSHOOTER[i]):
			out.push_back("sharpshooter_%d" % (i + 1))
	return out


## A league heat folded into the campaign: {won, ot, trailing_at_half,
## title, league_id, difficulty, level_after}.
static func for_league_heat(ctx: Dictionary) -> Array:
	var out := []
	var won := bool(ctx.get("won", false))
	if won:
		out.push_back("opening_night")
		if int(ctx.get("ot", 0)) > 0:
			out.push_back("bonus_basketball")
		if bool(ctx.get("trailing_at_half", false)):
			out.push_back("never_out_of_it")
	if bool(ctx.get("title", false)):
		var champ: String = str(TITLE_KEYS.get(str(ctx.get("league_id", "")), ""))
		if champ != "":
			out.push_back(champ)
		if str(ctx.get("difficulty", "")) == "hard":
			out.push_back("hard_way")
	out.append_array(for_level(int(ctx.get("level_after", 0))))
	return out


## The areas and the Hall a level reaches (Progression's area levels).
static func for_level(level: int) -> Array:
	var out := []
	for area in AREA_KEYS:
		if level >= Progression.area_level(area):
			out.push_back(AREA_KEYS[area])
	if level >= HALL_OF_FAMER_LEVEL:
		out.push_back("hall_of_famer")
	return out


## A card deployed by the player: its effect kind and the opponent's make
## streak as it landed.
static func for_card(kind: String, opp_streak: int) -> Array:
	var out := ["ace_up_the_sleeve"]
	if kind == "ice" and opp_streak >= COLD_SHOULDER_STREAK:
		out.push_back("cold_shoulder")
	return out


## A PEGGY drop's prize record {id, rarity, …} (a refund has id "").
static func for_prize(prize: Dictionary) -> Array:
	if str(prize.get("id", "")) == "":
		return []
	return for_prize_rarity(str(prize.get("rarity", "")))


static func for_prize_rarity(rarity: String) -> Array:
	var out := ["drop_it"]
	if rarity == "epic":
		out.push_back("jackpot")
	elif rarity == "legend":
		out.push_back("golden_drop")
	return out


## An online match settled: the room's settle message and how the match
## was started (App.match_how; "rematch" after RUN IT BACK). The settle's
## server milestones reach the autoload through Platform.milestone_unlocked.
static func for_settle(msg: Dictionary, how: String) -> Array:
	var out := []
	var won := bool(msg.get("won", false))
	if won and how == "rematch":
		out.push_back("run_it_back")
	var sp: Dictionary = msg.get("spoils", {}) if msg.get("spoils") is Dictionary else {}
	var captured: Array = sp.get("captured", []) if sp.get("captured") is Array else []
	for id in captured:
		if str(id) == MAGNET_CARD:
			out.push_back("big_steal")
			break
	return out


## A weekly time-trial board rank for this player (0 / negative = unranked).
static func for_week_rank(rank: int) -> Array:
	var out := []
	if rank <= 0:
		return out
	if rank <= BOARD_MEMBER_RANK:
		out.push_back("board_member")
	if rank == 1:
		out.push_back("number_one")
	return out


## Everything a device's records already earn, once, when this ships
## (docs/ACHIEVEMENTS.md → Backfill). `state`:
##   level: int
##   leagues: [{id, championships, wins, best_streak}]
##   runs: [{score, makes, attempts, bestStreak, swishes}]  (time trials)
##   prizes: [rarity]  (PEGGY prizes owned)
##   milestones: [server keys]
## Not recoverable (no record kept): Pure, Ace Up the Sleeve, Cold Shoulder,
## Hard Way, Bonus Basketball, Never Out of It, Run It Back, Big Steal, the
## board ranks.
static func backfill(state: Dictionary) -> Array:
	var out := []
	var add := func(keys: Array) -> void:
		for k in keys:
			if not out.has(k):
				out.push_back(k)
	add.call(for_level(int(state.get("level", 0))))
	var best_streak := 0
	for l in Array(state.get("leagues", [])):
		if int(l.get("championships", 0)) > 0:
			add.call([str(TITLE_KEYS.get(str(l.get("id", "")), ""))].filter(func(k: String) -> bool: return k != ""))
		if int(l.get("wins", 0)) > 0:
			add.call(["opening_night"])
		best_streak = maxi(best_streak, int(l.get("best_streak", 0)))
	var best_score := -1
	for r in Array(state.get("runs", [])):
		add.call(["on_the_clock"])
		if int(r.get("swishes", 0)) > 0:
			add.call(["nothing_but_net"])
		best_score = maxi(best_score, int(r.get("score", 0)))
		best_streak = maxi(best_streak, int(r.get("bestStreak", 0)))
		var attempts := int(r.get("attempts", 0))
		if attempts >= PERFECT_RUN_MIN_SHOTS and int(r.get("makes", 0)) == attempts:
			add.call(["perfect_run"])
	if best_score >= 0:
		add.call(sharpshooter(best_score))
	if best_streak >= HEATING_UP:
		add.call(["heating_up"])
	if best_streak >= ON_FIRE:
		add.call(["on_fire"])
	for rarity in Array(state.get("prizes", [])):
		add.call(for_prize_rarity(str(rarity)))
	add.call(AchievementDefs.for_milestones(Array(state.get("milestones", []))))
	return out
