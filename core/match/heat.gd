class_name Heat
extends RefCounted
## A league heat: a head-to-head time trial. Both sides shoot at once on their
## own rim for `seconds`, with a ball-return wait so nobody can spam shots;
## the higher score wins, ties go to `ot_seconds` overtime periods until
## decided. One TimeTrial per side (so streak tiers, fire and ice apply to
## both), the AI side driven by cadence timers and AimError shots from a
## seeded DetRng — a seed replays the whole heat.
##
## Renderer contract, same shape as TimeTrial: tick(dt) → drain_events() →
## balls(side). Every relayed event carries "side": "player" | "ai"; the heat
## adds ot_start {n} and heat_done {result}.
##
## Online (docs/BACKEND.md → Phase 3): `remote: true` drives the AI side from
## the other phone instead of a bot. Their launches replay through the AI
## TimeTrial for the picture (the same float64 sim, the same arc); their
## scoreboard, period ends and totals come from their own messages and are
## authoritative — each side owns its own shots. The local replay's score is
## only compared against theirs to flag a desync.

const PLAYER := "player"
const AI := "ai"
const DEFAULT_SECONDS := 90.0
const DEFAULT_OT_SECONDS := 20.0
const DEFAULT_BALL_RETURN_S := 1.5
## Flight time the AI leads a moving hoop by.
const AI_LEAD_S := 0.9
## Spot shuffle marks (the beach's last-30 s mechanic), mirrored for the AI.
const SHUFFLE_MARKS := [30.0, 20.0, 10.0]

var seconds := DEFAULT_SECONDS
var ot_seconds := DEFAULT_OT_SECONDS
var ball_return_s := DEFAULT_BALL_RETURN_S
var err_mult := 1.0
var seed_value := 1
var calib_key := "regulation"

var player: TimeTrial
var ai: TimeTrial
var ai_ratings: AiRatings
var ai_mood: AiMood
var ot := 0
var done := false
var rng: DetRng

## Shooting spots the AI can stand on ([{x, y, z}] in sim space, index 0 =
## the base spot) and whether the last-30 s shuffle moves it between them.
var spots: Array = []
var spot_shuffle := false
var ai_spot_index := 0
var _shuffle_next := 0
## Overtime break: after a tied buzzer the heat pauses this long (the
## announcement), then both sides reset to the key and open OT on a countdown.
const OT_BREAK_S := 2.5
var _ot_break := -1.0

## Power-up cards in hand per side (ids; consumed on play).
var hands: Dictionary = {PLAYER: [], AI: []}
var cards_played: Dictionary = {PLAYER: [], AI: []}

## Optional bot on the PLAYER side (`player_bot` in the config: AiRatings) —
## the card lab's AI-vs-AI heats. It runs the same cadence/aim/card driver as
## the AI side on its own forked stream, so a heat without one draws exactly
## the numbers it always did and every seeded replay stays valid.
var player_bot: AiRatings = null

## Online: the AI side is the other phone (no bot). Their authoritative
## running score, their period-end report, launches that arrived before our
## replay of their clock was running, and a forfeit.
var remote := false
var remote_score := 0
var remote_shots := 0
var _remote_period: Dictionary = {}
var _remote_queue: Array = []
var _forfeit := ""

var _events: Array[Dictionary] = []
## side → {ratings, mood, rng, state (wait | aiming), timer, launch}
var _bots: Dictionary = {}
var _sides: Dictionary = {}
var _result := {}


## config: geo (SimGeometry), seconds, ot_seconds, ball_return_s, ai (AiRatings),
## err_mult, seed (int), calib_key (String), board_motion (bool),
## player_cards / ai_cards (Array of ids), player_bot (AiRatings, optional)
func _init(config: Dictionary = {}) -> void:
	var geo: SimGeometry = config.get("geo", null)
	if geo == null:
		geo = SimGeometry.regulation()
	seconds = float(config.get("seconds", DEFAULT_SECONDS))
	ot_seconds = float(config.get("ot_seconds", DEFAULT_OT_SECONDS))
	ball_return_s = float(config.get("ball_return_s", DEFAULT_BALL_RETURN_S))
	err_mult = float(config.get("err_mult", 1.0))
	seed_value = int(config.get("seed", 1))
	calib_key = str(config.get("calib_key", "regulation"))
	ai_ratings = config.get("ai", null)
	if ai_ratings == null:
		ai_ratings = AiRatings.make(0.5, 0.5)
	rng = DetRng.new(seed_value)
	ai_mood = AiMood.init_mood(ai_ratings, rng.fork("mood"))
	player = TimeTrial.new(geo, seconds)
	ai = TimeTrial.new(geo, seconds)
	for side in [player, ai]:
		side.ball_return_s = ball_return_s
		side.board_motion = bool(config.get("board_motion", false))
	_sides = {PLAYER: player, AI: ai}
	remote = bool(config.get("remote", false))
	if not remote:
		_bots[AI] = _bot_entry(ai_ratings, ai_mood, rng)
	player_bot = config.get("player_bot", null)
	if player_bot != null:
		var brng := rng.fork("player_bot")
		_bots[PLAYER] = _bot_entry(player_bot, AiMood.init_mood(player_bot, brng.fork("mood")), brng)
	hands[PLAYER] = Array(config.get("player_cards", [])).duplicate()
	hands[AI] = Array(config.get("ai_cards", [])).duplicate()
	set_spots(Array(config.get("spots", [])), bool(config.get("spot_shuffle", false)))


## Card decisions draw from their own forked stream, so a hand in play never
## shifts the shooting draws: the card lab pairs a heat with and without a
## card and the only difference between the two is the card's effect.
static func _bot_entry(ratings: AiRatings, mood: AiMood, p_rng: DetRng) -> Dictionary:
	return {"ratings": ratings, "mood": mood, "rng": p_rng, "card_rng": p_rng.fork("cards"),
		"state": "wait", "timer": 0.0, "launch": {}}


static func other_side(name_: String) -> String:
	return AI if name_ == PLAYER else PLAYER


func _reset_bot(side_name: String) -> void:
	if not _bots.has(side_name):
		return
	var b: Dictionary = _bots[side_name]
	b["state"] = "wait"
	b["timer"] = 0.0
	b["launch"] = {}


## Spots from the arena (the screen passes them once it knows the court).
func set_spots(list: Array, shuffle: bool) -> void:
	spots = list.duplicate()
	spot_shuffle = shuffle and spots.size() > 1
	ai_spot_index = 0
	_shuffle_next = 0


## Where the AI stands right now ({x, y, z}; the base origin when no spots).
func ai_spot() -> Dictionary:
	if spots.is_empty() or ai_spot_index >= spots.size():
		return {"x": 0.0, "y": 0.0, "z": 0.0}
	return spots[ai_spot_index]


## The AI's release origin and range from its spot.
func _ai_origin() -> Dictionary:
	var sp := ai_spot()
	var g := ai.geo
	var rx := float(sp["x"])
	var rz := float(sp["z"])
	var ry := g.release_h
	var dx := g.hoop_x - rx
	var dz := g.hoop_z - rz
	return {"rx": rx, "ry": ry, "rz": rz, "dist": sqrt(dx * dx + dz * dz), "rise": g.hoop_y - ry}


## At each mark inside the last 30 s the AI walks to a random other spot
## (seeded). A held ball is put down; the next pickup shoots from there.
func _step_ai_shuffle() -> void:
	if remote or not spot_shuffle or ai.phase != TimeTrial.PHASE_RUNNING or ai.overtime or _shuffle_next >= SHUFFLE_MARKS.size():
		return
	if ai.time_left > float(SHUFFLE_MARKS[_shuffle_next]):
		return
	_shuffle_next += 1
	var next := ai_spot_index
	while next == ai_spot_index:
		next = rng.range_i(0, spots.size() - 1)
	ai_spot_index = next
	if ai.holding:
		ai.drop()
		_reset_bot(AI)
	_events.push_back({"kind": "ai_spot", "side": AI, "index": ai_spot_index, "spot": ai_spot()})


func side(name_: String) -> TimeTrial:
	return _sides[name_]


func balls(name_: String) -> Array[BallState]:
	return side(name_).balls()


## A side's score for the board: online, the other phone's own count.
func score(name_: String) -> int:
	if remote and name_ == AI:
		return remote_score
	return side(name_).score


func time_left() -> float:
	return player.time_left


func phase() -> String:
	return player.phase


# ---- player input (the screen's FlickInput drives these) ----

func pickup() -> bool:
	return player.pickup()


func drop() -> void:
	player.drop()


func release(launch: Dictionary) -> bool:
	return player.release(launch)


func ball_wait() -> float:
	return player.ball_wait()


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func tick(dt: float) -> void:
	if done and player.balls().is_empty() and ai.balls().is_empty():
		return
	player.tick(dt)
	ai.tick(dt)
	for ev in player.drain_events():
		ev["side"] = PLAYER
		_events.push_back(ev)
		if ev["kind"] == "outcome" and _bots.has(PLAYER):
			_bots[PLAYER]["mood"].update(player_bot, _bots[PLAYER]["rng"])
	for ev in ai.drain_events():
		ev["side"] = AI
		_events.push_back(ev)
		if ev["kind"] == "outcome":
			ai_mood.update(ai_ratings, rng)   # the next cycle already started at release
	if _ot_break >= 0.0:
		_ot_break -= dt
		if _ot_break <= 0.0:
			_start_ot_period()
		return
	_step_ai_shuffle()
	if remote:
		_replay_queued()
	else:
		# The AI first (its draws come off the shared stream in the order they
		# always did), then the player bot on its own stream.
		_drive_bot(AI, dt)
		_drive_bot_cards(AI)
	if _bots.has(PLAYER):
		_drive_bot(PLAYER, dt)
		_drive_bot_cards(PLAYER)
	_check_period_end()


# ---- the other phone (online) -----------------------------------------------------


## Their shot: replay it through the AI TimeTrial for the picture. Arrives
## before our copy of their clock runs (latency at a period's open) → queued.
## Returns true when it went in flight now.
func remote_release(launch: Dictionary) -> bool:
	if not remote or done or launch.is_empty():
		return false
	remote_shots += 1
	_place_remote_from(launch)
	if ai.phase != TimeTrial.PHASE_RUNNING:
		_remote_queue.push_back(launch)
		return false
	return _replay(launch)


func _replay(launch: Dictionary) -> bool:
	# Their ball-return wait is theirs to keep; the replay never refuses.
	ai.holding = true
	return ai.release(launch)


func _replay_queued() -> void:
	if _remote_queue.is_empty() or ai.phase != TimeTrial.PHASE_RUNNING:
		return
	for launch in _remote_queue:
		_replay(launch)
	_remote_queue.clear()


## The spot they shot from, by the launch's origin: the PiP frame follows.
func _place_remote_from(launch: Dictionary) -> void:
	if spots.size() < 2 or not launch.has("rx"):
		return
	var best := ai_spot_index
	var best_d := INF
	for i in spots.size():
		var sp: Dictionary = spots[i]
		var dx := float(sp["x"]) - float(launch["rx"])
		var dz := float(sp["z"]) - float(launch.get("rz", 0.0))
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = i
	if best != ai_spot_index:
		ai_spot_index = best
		_events.push_back({"kind": "ai_spot", "side": AI, "index": ai_spot_index, "spot": ai_spot()})


## Their running score after a shot (authoritative; the replay only pictures it).
func remote_outcome(score: int) -> void:
	if remote and not done:
		remote_score = maxi(remote_score, score)


## Their period is over: `totals` as Heat.totals_of, `score` final for the
## period. The heat decides (OT or done) once ours is over too.
func remote_period_end(period: int, score: int, totals: Dictionary) -> void:
	if not remote or done:
		return
	remote_score = score
	_remote_period = {"period": period, "score": score, "totals": totals.duplicate(true)}


## They left: a win by forfeit once the match has been on long enough to
## count (`min_played_s` of regulation), otherwise a void. Ends the heat now.
func remote_forfeit(min_played_s := 30.0) -> void:
	if not remote or done:
		return
	var played := seconds - player.time_left if ot == 0 else seconds
	_forfeit = "forfeit" if played >= min_played_s else "void"
	done = true
	_result = _build_result()
	_result["reason"] = _forfeit
	_result["won"] = _forfeit == "forfeit"
	_events.push_back({"kind": "heat_done", "result": _result})


## Their card, out of the hand the room dealt them: the same play_card the
## bot would make (ice lands on our rim — our sim, our report; fire and
## vortex light our replay of theirs). False when it is not in their hand.
func remote_card(id: String) -> bool:
	if not remote or done:
		return false
	return play_card(AI, id)


## Online: does the replay disagree with what they reported?
func desync() -> bool:
	return remote and ai.score != remote_score


func forfeit_reason() -> String:
	return _forfeit


## Deploy a card from `side`'s hand against the other side. The card leaves
## the hand only when its effect applied. Emits card_played {side, card,
## target, ok}. Returns true when it applied.
func play_card(side_name: String, card_id: String) -> bool:
	var hand: Array = hands[side_name]
	if not hand.has(card_id) or done:
		return false
	var card := CardDefs.get_card(card_id)
	if card.is_empty():
		return false
	var target := _target_for(side_name, card_id)
	var effect: Dictionary = card.get("effect", {})
	var ok := CardEffects.apply(str(effect.get("kind", "")), effect, self, target)
	if ok:
		hand.erase(card_id)
		cards_played[side_name].push_back(card_id)
	_events.push_back({"kind": "card_played", "side": side_name, "card": card_id, "target": target, "ok": ok})
	return ok


## Self cards act on the side playing them; the rest on the other side.
func _target_for(side_name: String, card_id: String) -> String:
	if CardDefs.target_of(card_id) == "self":
		return side_name
	return AI if side_name == PLAYER else PLAYER


func can_play(side_name: String, card_id: String) -> bool:
	var card := CardDefs.get_card(card_id)
	if card.is_empty() or done or not hands[side_name].has(card_id):
		return false
	var target := _target_for(side_name, card_id)
	return CardEffects.can_apply(str(card.get("effect", {}).get("kind", "")), self, target)


func _drive_bot_cards(side_name: String) -> void:
	var tt: TimeTrial = _sides[side_name]
	if done or not _bots.has(side_name) or hands[side_name].is_empty() or tt.phase != TimeTrial.PHASE_RUNNING:
		return
	var pick := CardPolicy.choose_for(side_name, hands[side_name], self, _bots[side_name]["card_rng"])
	if pick != "":
		play_card(side_name, pick)


## Two-state bot driver on the human's rhythm: wait (the cadence's pickup
## delay, which covers the ball-return wait, counted from the last release)
## → aiming (hold for aim_time) → release → wait again at once, so the next
## ball can be in hand while the last is still in the air. The AI side shoots
## from its spot (the beach walk); a player bot shoots from the key.
func _drive_bot(side_name: String, dt: float) -> void:
	var tt: TimeTrial = _sides[side_name]
	if tt.phase != TimeTrial.PHASE_RUNNING or done:
		return
	var b: Dictionary = _bots[side_name]
	var ratings: AiRatings = b["ratings"]
	var mood: AiMood = b["mood"]
	var brng: DetRng = b["rng"]
	var other: TimeTrial = _sides[other_side(side_name)]
	var situation := {"score_diff": tt.score - other.score, "time_left": tt.time_left}
	match str(b["state"]):
		"wait":
			if b["launch"].is_empty():
				var cad := AiCadence.next_cadence(ratings, situation, brng, ball_return_s)
				b["timer"] = float(cad["pickup_delay"])
				b["launch"] = {"aim_time": float(cad["aim_time"])}
			b["timer"] = float(b["timer"]) - dt
			if float(b["timer"]) <= 0.0 and tt.ball_ready() and not tt.holding:
				if tt.pickup():
					b["state"] = "aiming"
					b["timer"] = float(b["launch"]["aim_time"])
		"aiming":
			b["timer"] = float(b["timer"]) - dt
			if float(b["timer"]) <= 0.0:
				var calib := AimError.calibration_for(calib_key)
				# A moving board: aim where the hoop will be after a typical flight.
				var aim_geo := tt.geo_in(AI_LEAD_S) if tt.moving else tt.geo
				var launch: Dictionary
				if spots.is_empty() or side_name != AI:
					launch = AimError.ai_shot(ratings, mood, situation, brng, aim_geo, calib, err_mult)
				else:
					var o := _ai_origin()
					launch = AimError.ai_shot(ratings, mood, situation, brng, aim_geo, calib, err_mult, float(o["dist"]), float(o["rise"]))
					launch["rx"] = o["rx"]
					launch["ry"] = o["ry"]
					launch["rz"] = o["rz"]
				tt.release(launch)
				b["state"] = "wait"
				b["launch"] = {}   # a fresh cadence, clocked from this release
				b["timer"] = 0.0
		_:
			pass


## The OT break is over: both shooters back at the key, the last-30 s
## mechanics off, and the period opens on a countdown.
func _start_ot_period() -> void:
	_ot_break = -1.0
	if not spots.is_empty():
		ai_spot_index = 0
		_shuffle_next = SHUFFLE_MARKS.size()
		_events.push_back({"kind": "ai_spot", "side": AI, "index": 0, "spot": ai_spot()})
	player.start_period(ot_seconds, true)
	ai.start_period(ot_seconds, true)
	_reset_bot(AI)
	_reset_bot(PLAYER)
	_events.push_back({"kind": "ot_period", "n": ot})


## When both periods are over: decide, or start overtime.
func _check_period_end() -> void:
	if done:
		return
	if player.phase != TimeTrial.PHASE_DONE or ai.phase != TimeTrial.PHASE_DONE:
		return
	if remote and int(_remote_period.get("period", -1)) != ot:
		return   # waiting on their report for this period
	if player.score == score(AI):
		ot += 1
		_ot_break = OT_BREAK_S
		_remote_queue.clear()
		_events.push_back({"kind": "ot_start", "n": ot})
		return
	done = true
	_result = _build_result()
	_events.push_back({"kind": "heat_done", "result": _result})


func result() -> Dictionary:
	return _result


static func totals_of(tt: TimeTrial) -> Dictionary:
	return {
		"score": tt.score, "makes": tt.makes, "swishes": tt.swishes, "attempts": tt.attempts,
		"bestStreak": tt.best_streak, "bonus": tt.bonus_points, "iced": tt.times_iced,
	}


func _build_result() -> Dictionary:
	var p := totals_of(player)
	p["cardsPlayed"] = cards_played[PLAYER].duplicate()
	var a := totals_of(ai)
	if remote:
		# Their own numbers, not our replay's.
		var theirs: Dictionary = _remote_period.get("totals", {})
		for k in a:
			if theirs.has(k):
				a[k] = theirs[k]
		a["score"] = remote_score
	a["cardsPlayed"] = cards_played[AI].duplicate()
	var out := {
		"won": player.score > score(AI),
		"player_score": player.score,
		"ai_score": score(AI),
		"ot": ot,
		"seed": seed_value,
		"sides": {PLAYER: p, AI: a},
	}
	if remote:
		out["online"] = true
		out["desync"] = desync()
	return out
