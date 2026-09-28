class_name TimeTrial
extends RefCounted
## Time Trial: 60 seconds, halfcourt, as many points as you can. No per-shot
## clock — the global timer is the pressure, and it's rapid fire: grab the next
## ball the instant you release, so several balls can be in flight at once.
## Shots released before the buzzer count when they land (buzzer beaters).
## Ported from src/core/match/timeTrial.ts. This class is the renderer
## contract: tick(dt) → drain_events() → balls — the future MatchEngine (M2)
## exposes the same shape.
## Events are Dictionaries with "kind" ∈ go | pickup | release | contact |
## outcome | buzzer | done (+ ice_on/ice_crack/ice_caught/ice_break, ball_ready,
## heat_up). Heats (core/match/heat.gd) run one TimeTrial per side with a
## custom length and a ball-return wait.

const TIME_TRIAL_SECONDS := 60.0
const COUNTDOWN_SECONDS := 3.0

## Moving-board difficulty phase: with this much time left, the hoop starts
## sliding on a figure-8 — depth between BOARD_NEAR and BOARD_FAR on a
## BOARD_CYCLE_S sine, and sideways ±LATERAL_AMP at twice that rate (the
## arcade cage's crossbar/trolley rails).
const MOVE_PHASE_LEFT := 30.0
const BOARD_NEAR := 2.4
const BOARD_FAR := 3.4
const BOARD_CYCLE_S := 12.0
## Board edge reaches 0.4 + 0.61 = 1.01 m off-centre: inside the 1.4 m cage
## half-width and the phone's 1.27 m visible half-width at that depth.
const LATERAL_AMP := 0.4

const PHASE_COUNTDOWN := "countdown"
const PHASE_RUNNING := "running"
const PHASE_FINISHING := "finishing"
const PHASE_DONE := "done"

## Geometry the trial was created with — the flick mapping's skill anchor.
## NEVER mutated (the screen aliases it).
var base_geo: SimGeometry
## Live hoop/board geometry for new shots; each ball freezes it at launch.
## Replaced wholesale (fresh instance) while the board moves.
var geo: SimGeometry
## Opt-in for the moving-board difficulty phase (the arcade game screen
## enables it). Off by default so plain trials — including the regulation
## fixtures — keep a stationary hoop.
var board_motion := false
## True once the moving-board phase has begun.
var moving := false
## Endless practice: no countdown, the clock never runs down, no buzzer — the
## trial stays PHASE_RUNNING until the screen leaves. Score/makes still count.
var endless := false
## Practice "30 s mode": start the moving phase now, whatever the clock says.
var force_motion := false
## Overtime period: the last-30 s mechanics (board slide, spot shuffle) stay off.
var overtime := false
var motion_locked := false

## Length of the period (heats pass 90, overtime 20).
var seconds := TIME_TRIAL_SECONDS
## Ball-return wait: after a release the next pickup is refused for this long
## (0 = rapid fire, the classic time trial). Heats use 1.5 s.
var ball_return_s := 0.0
var ball_ready_at := 0.0
## Running clock (seconds since the trial started ticking).
var t := 0.0

var phase := PHASE_COUNTDOWN
var countdown := COUNTDOWN_SECONDS
var time_left := TIME_TRIAL_SECONDS
var score := 0
var makes := 0
var swishes := 0
var attempts := 0
var streak := 0
var best_streak := 0
## Points earned above the plain 1-per-make / 2-per-swish rule (StreakRules).
var bonus_points := 0
## Cold streak (StreakRules.COLD_AT misses in a row ices the rim).
var miss_streak := 0
var iced := false
var ice_hits := 0
var times_iced := 0
var holding := false
## Card fire: a power-up lit the rim for a window of the trial clock. The
## streak jumps to StreakRules.FIRE_AT so makes pay (and stack) like a real
## hot streak; the window's end, a miss, or ice puts it out and resets the streak.
var fire_card := false
var fire_until := -1.0
## The streak the fire card lent (FIRE_AT minus the streak it found): withdrawn
## when the window closes, so the makes shot during it stay a real streak and
## a strong shooter is never worse off for having played the card.
var _fire_loan := 0
## Card vortex (docs/CARDS.md): the rim pulls any ball that touched iron or
## board through, for a window of the trial clock. Ice ends it; a miss does not.
var vortex_card := false
var vortex_until := -1.0

# Each flight: { "state": BallState, "seen_events": int, "scored": bool }
var _flights: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _accumulator := 0.0
var _move_time := 0.0


func _init(p_geo: SimGeometry = null, p_seconds := TIME_TRIAL_SECONDS) -> void:
	base_geo = p_geo if p_geo != null else SimGeometry.regulation()
	geo = base_geo
	seconds = p_seconds
	time_left = p_seconds


## Seconds until the next ball may be picked up (0 = ready now).
func ball_wait() -> float:
	return maxf(ball_ready_at - t, 0.0)


## Is a pickup allowed right now?
func ball_ready() -> bool:
	return ball_wait() <= 0.0


## Ice the rim from outside the miss-streak rule (a power-up card). Same
## consequences as a cold streak; `reason` rides the ice_on event.
func freeze_rim(reason := "card") -> bool:
	if iced:
		return false
	iced = true
	ice_hits = 0
	times_iced += 1
	_set_geo(geo)
	_events.push_back({"kind": "ice_on", "misses": miss_streak, "reason": reason})
	_end_card_fire("ice")
	_end_vortex("ice")
	return true


## Light the rim from a power-up card for `seconds` of the trial clock. Refused
## during the countdown, while iced, while already lit (a real streak or
## another card). Emits fire_on {reason, seconds}.
func light_rim(seconds: float, reason := "card") -> bool:
	if fire_card or iced or phase != PHASE_RUNNING or StreakRules.is_lit(streak):
		return false
	fire_card = true
	fire_until = t + seconds
	_fire_loan = StreakRules.FIRE_AT - streak
	streak = StreakRules.FIRE_AT
	_events.push_back({"kind": "fire_on", "reason": reason, "seconds": seconds})
	return true


## Seconds of card fire left (0 when none).
func fire_left() -> float:
	return maxf(fire_until - t, 0.0) if fire_card else 0.0


func _end_card_fire(reason: String) -> void:
	if not fire_card:
		return
	fire_card = false
	fire_until = -1.0
	# A miss broke the streak outright. The clock (or ice) puts the fire OUT:
	# the card's loan is taken back and the makes shot under it stay a real
	# but unlit streak (capped under FIRE_AT — a card never hands over a hot
	# streak, the shooter has to earn the next one). Never worse than not
	# having played it. (The card lab found the old hard reset made Heat
	# Check a net LOSS for strong shooters: it wiped the streak they built.)
	streak = 0 if reason == "miss" else clampi(streak - _fire_loan, 0, StreakRules.FIRE_AT - 1)
	_fire_loan = 0
	_events.push_back({"kind": "fire_off", "reason": reason})


## Spin the rim from a power-up card for `seconds` of the trial clock: every
## ball that touches iron or board is pulled through (ShotSim). Refused during
## the countdown, while iced, while already spinning. Emits vortex_on.
func spin_rim(seconds: float, reason := "card") -> bool:
	if vortex_card or iced or phase != PHASE_RUNNING:
		return false
	vortex_card = true
	vortex_until = t + seconds
	_set_geo(geo)
	_events.push_back({"kind": "vortex_on", "reason": reason, "seconds": seconds})
	return true


## Seconds of the vortex left (0 when none).
func vortex_left() -> float:
	return maxf(vortex_until - t, 0.0) if vortex_card else 0.0


func _end_vortex(reason: String) -> void:
	if not vortex_card:
		return
	vortex_card = false
	vortex_until = -1.0
	_set_geo(geo)
	_events.push_back({"kind": "vortex_off", "reason": reason})


## Any shot still unresolved (in the air or rattling)?
func _shot_pending() -> bool:
	for f in _flights:
		if not f["scored"]:
			return true
	return false


## Start another period on the same state (overtime): the clock resets, the
## hands empty, the arena resets (balls cleared, hoop parked at home, the
## last-30 s mechanics locked off), streak/fire/ice carry over. With
## `with_countdown` the period opens on the 3 s countdown (tick emits `go`);
## otherwise it is running at once.
func start_period(p_seconds: float, with_countdown := false) -> void:
	seconds = p_seconds
	time_left = p_seconds
	holding = false
	ball_ready_at = 0.0
	overtime = true
	_flights.clear()
	moving = false
	force_motion = false
	motion_locked = true
	_move_time = 0.0
	_set_geo(base_geo)
	if with_countdown:
		phase = PHASE_COUNTDOWN
		countdown = COUNTDOWN_SECONDS
		return
	phase = PHASE_RUNNING
	_events.push_back({"kind": "go"})


## In-flight ball states, oldest first (renderer maps these onto a view pool).
func balls() -> Array[BallState]:
	var out: Array[BallState] = []
	for f in _flights:
		out.push_back(f["state"])
	return out


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


## A rim hit while iced chips the ice; the third one breaks it (the ball in
## flight keeps going and may still score).
func _ice_rim_hit() -> void:
	if not iced:
		return
	ice_hits += 1
	if ice_hits >= StreakRules.ICE_BREAK_HITS:
		_break_ice("hits")
	else:
		_events.push_back({"kind": "ice_crack", "hits": ice_hits, "left": StreakRules.ICE_BREAK_HITS - ice_hits})


func _break_ice(by: String) -> void:
	iced = false
	ice_hits = 0
	miss_streak = 0
	_set_geo(geo)
	_events.push_back({"kind": "ice_break", "by": by})


## The live geometry always carries the ice flag (the moving board rebuilds
## the pose every step, so it is re-applied here).
func _set_geo(g: SimGeometry) -> void:
	var out := g
	if out.ice != iced:
		out = out.with_ice(iced)
	if out.vortex != vortex_card:
		out = out.with_vortex(vortex_card)
	geo = out


## Grab a ball — only while the clock runs and hands are empty.
func pickup() -> bool:
	if phase != PHASE_RUNNING or holding or not ball_ready():
		return false
	holding = true
	_events.push_back({"kind": "pickup"})
	return true


## Put the ball down without shooting (the shooter walked to another spot).
func drop() -> void:
	holding = false


func release(launch: Dictionary) -> bool:
	if phase != PHASE_RUNNING or not holding:
		return false
	holding = false
	attempts += 1
	if ball_return_s > 0.0:
		ball_ready_at = t + ball_return_s
	_flights.push_back({"state": ShotSim.create_shot(launch, geo), "seen_events": 0, "scored": false})
	_events.push_back({"kind": "release", "launch": launch})
	return true


func tick(dt: float) -> void:
	# Keeps stepping after 'done' too, so the last balls finish bouncing
	# behind the results overlay instead of freezing midair.
	if phase == PHASE_DONE and _flights.is_empty():
		return
	_accumulator += dt
	while _accumulator >= SimConstants.SIM_DT:
		_accumulator -= SimConstants.SIM_DT
		_step_fixed()


## Deterministic figure-8 (Lissajous 1:2): depth is a sine between BOARD_NEAR
## and BOARD_FAR, phase-offset so the first moving step is continuous with the
## base distance (no jump) and the board drifts AWAY first; the lateral term
## has no phase so it starts at the base offset (0). Pure function of elapsed
## move time — no RNG, so runs replay identically.
func _step_board_motion() -> void:
	if not board_motion or motion_locked:
		return
	if not moving:
		if time_left > MOVE_PHASE_LEFT and not force_motion:
			return
		moving = true
		_events.push_back({"kind": "heat_up"})
	_move_time += SimConstants.SIM_DT
	_set_geo(pose_at(_move_time))


## Practice "30 s mode" off: park the hoop back at its base pose.
func stop_motion() -> void:
	board_motion = false
	force_motion = false
	moving = false
	_move_time = 0.0
	geo = base_geo


## The hoop pose after `move_time` seconds of the moving phase (pure function).
func pose_at(move_time: float) -> SimGeometry:
	var mid := (BOARD_NEAR + BOARD_FAR) / 2.0
	var amp := (BOARD_FAR - BOARD_NEAR) / 2.0
	var phi := asin(clampf((base_geo.hoop_x - mid) / amp, -1.0, 1.0))
	var w := TAU * move_time / BOARD_CYCLE_S
	var d := mid + amp * sin(w + phi)
	var lat := base_geo.hoop_z + LATERAL_AMP * sin(2.0 * w)
	return base_geo.with_pose(d, lat)


## Where the hoop will be `seconds` from now — the aim lead. While the hoop is
## still, this is just the current geo.
func geo_in(seconds: float) -> SimGeometry:
	if not moving or phase != PHASE_RUNNING:
		return geo
	return pose_at(_move_time + seconds)


func _step_fixed() -> void:
	var was_waiting := ball_return_s > 0.0 and not ball_ready()
	t += SimConstants.SIM_DT
	# The card's window closes once the last shot of it has landed.
	if fire_card and t >= fire_until and not _shot_pending():
		_end_card_fire("time")
	if vortex_card and t >= vortex_until and not _shot_pending():
		_end_vortex("time")
	if was_waiting and ball_ready() and phase == PHASE_RUNNING:
		_events.push_back({"kind": "ball_ready"})
	if phase == PHASE_COUNTDOWN:
		countdown -= SimConstants.SIM_DT
		if endless:
			countdown = 0.0
		if countdown <= 0.0:
			phase = PHASE_RUNNING
			_events.push_back({"kind": "go"})
		return

	if phase == PHASE_RUNNING:
		if not endless:
			time_left -= SimConstants.SIM_DT
		if time_left <= 0.0:
			time_left = 0.0
			holding = false
			phase = PHASE_FINISHING
			_events.push_back({"kind": "buzzer"})
		else:
			_step_board_motion()

	# Step every in-flight ball against the LIVE hoop (so a make is a make
	# where you see the hoop — the moving rim is a moving collider); score on
	# resolve, drop once settled.
	for f in _flights:
		var s: BallState = f["state"]
		if s.settled:
			continue
		s.geo = geo
		ShotSim.step_shot(s)
		while f["seen_events"] < s.events.size():
			var contact: Dictionary = s.events[f["seen_events"]]
			_events.push_back({"kind": "contact", "contact": contact})
			f["seen_events"] += 1
			if contact["kind"] == Colliders.KIND_RIM:
				_ice_rim_hit()
			elif contact["kind"] == "ice_catch":
				_events.push_back({"kind": "ice_caught"})
			elif contact["kind"] == "ice_pop" and iced:
				_break_ice("make")
			elif contact["kind"] == "enter" and iced:
				# A clean entry (only a ball that never touched iron gets here
				# while iced): the ice shatters as the ball drops through. Whether
				# it scores is decided at resolution — only a swish does.
				f["broke_ice"] = true
				_break_ice("swish")
		if s.resolved and not f["scored"]:
			f["scored"] = true
			var outcome := ShotClassify.classify_shot(s)
			# Streak scoring (StreakRules): the classifier's points are the
			# shot's own value (1, swish 2); the streak tier can raise them.
			if outcome["type"] == ShotClassify.ICE_CAUGHT:
				# Iced over: the ice grabbed the would-be make and popped it out;
				# the ice broke on the pop. Nothing to score, streaks untouched.
				outcome["iced_out"] = true
				outcome["points"] = 0
				if iced:
					_break_ice("make")
			elif outcome["made"] and f.get("broke_ice", false) and outcome["type"] != ShotClassify.SWISH:
				# Broke through the ice cleanly but rattled in after: only a swish
				# scores through the ice. The ice is already gone.
				outcome["iced_out"] = true
				outcome["base_points"] = outcome["points"]
				outcome["points"] = 0
			elif outcome["made"]:
				if f.get("broke_ice", false):
					outcome["ice_broken"] = "swish"  # the swish that shattered the ice
				miss_streak = 0
				streak += 1
				makes += 1
				var swish: bool = outcome["type"] == ShotClassify.SWISH
				if swish:
					swishes += 1
				outcome["base_points"] = outcome["points"]
				outcome["points"] = StreakRules.points_for(streak, swish)
				bonus_points += int(outcome["points"]) - int(outcome["base_points"])
				score += outcome["points"]
				best_streak = maxi(best_streak, streak)
			else:
				outcome["streak_broken"] = streak
				streak = 0
				miss_streak += 1
				if not iced and miss_streak >= StreakRules.COLD_AT:
					iced = true
					ice_hits = 0
					times_iced += 1
					_set_geo(geo)
					_events.push_back({"kind": "ice_on", "misses": miss_streak})
					_end_vortex("ice")
			outcome["streak"] = streak
			outcome["miss_streak"] = miss_streak
			outcome["iced"] = iced
			_events.push_back({
				"kind": "outcome",
				"outcome": outcome,
				"buzzer_beater": phase != PHASE_RUNNING,
			})
			if fire_card and not outcome["made"] and not outcome.get("iced_out", false):
				_end_card_fire("miss")
	var kept: Array[Dictionary] = []
	for f in _flights:
		var s: BallState = f["state"]
		if not s.settled or not f["scored"]:
			kept.push_back(f)
	_flights = kept

	if phase == PHASE_FINISHING:
		var all_scored := true
		for f in _flights:
			if not f["scored"]:
				all_scored = false
				break
		if all_scored:
			phase = PHASE_DONE
			_events.push_back({"kind": "done"})
