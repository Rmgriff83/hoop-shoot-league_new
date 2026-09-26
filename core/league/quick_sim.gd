class_name QuickSim
extends RefCounted
## Cheap rating-based resolution of heats the player isn't watching (ported
## from quickSim.ts, adapted to 90 s heats): each shooter takes
## floor(seconds / pace) Bernoulli shots with the hot/cold chain, an empirical
## swish split, and the same StreakRules the live engine uses (fire tiers,
## swish +1, ice after COLD_AT misses — a swish through it scores, any other
## make only breaks it, misses while iced chip it). 20 s OT rounds until
## untied. Seeded per game → reproducible box scores, no physics.

const OT_MAX := 20


## Fitted vs the physics pipeline: swish share of makes ≈ 0.05 + 0.30·acc·swish.
static func effective_swish_share(r: AiRatings) -> float:
	return minf(0.05 + 0.3 * r.accuracy * r.swish_rate, 0.75)


## Attempts in a period: the live AI's release-to-release cycle
## (AiCadence.cycle_s: ball-return wait + pace × TEMPO) into the clock.
static func shots_for(r: AiRatings, seconds: float, ball_return_s := 1.0) -> int:
	return maxi(int(seconds / AiCadence.cycle_s(r, ball_return_s)), 2)


static func empty_box() -> Dictionary:
	return {"points": 0, "makes": 0, "swishes": 0, "shots": 0, "bestStreak": 0, "iced": 0}


## One period for one shooter; `state` carries streak/mood across OT periods.
static func sim_period(r: AiRatings, rng: DetRng, shots: int, state: Dictionary) -> Dictionary:
	var swish_share := effective_swish_share(r)
	var box := empty_box()
	box["shots"] = shots
	for i in shots:
		var p := clampf(r.accuracy + float(state["mood"]) * 0.06 * r.streakiness, 0.05, 0.97)
		var made := rng.next() < p
		if made:
			var swish := rng.next() < swish_share
			if state["iced"]:
				# Only a swish scores through the ice; either way the ice is gone.
				state["iced"] = false
				state["miss_streak"] = 0
				if swish:
					state["streak"] += 1
					box["makes"] += 1
					box["swishes"] += 1
					box["points"] += StreakRules.points_for(int(state["streak"]), true)
			else:
				state["streak"] += 1
				state["miss_streak"] = 0
				box["makes"] += 1
				if swish:
					box["swishes"] += 1
				box["points"] += StreakRules.points_for(int(state["streak"]), swish)
			state["best"] = maxi(int(state["best"]), int(state["streak"]))
		else:
			state["streak"] = 0
			if state["iced"]:
				# About half of misses rattle the rim; three chips break the ice.
				if rng.next() < 0.5:
					state["ice_hits"] += 1
					if int(state["ice_hits"]) >= StreakRules.ICE_BREAK_HITS:
						state["iced"] = false
						state["miss_streak"] = 0
			else:
				state["miss_streak"] += 1
				if int(state["miss_streak"]) >= StreakRules.COLD_AT:
					state["iced"] = true
					state["ice_hits"] = 0
					box["iced"] += 1
		var stay := 0.5 + 0.45 * r.streakiness
		if rng.next() > stay:
			state["mood"] = -1 if int(state["mood"]) == 1 else 1
	box["bestStreak"] = int(state["best"])
	return box


static func _add(a: Dictionary, b: Dictionary) -> Dictionary:
	return {
		"points": a["points"] + b["points"], "makes": a["makes"] + b["makes"], "swishes": a["swishes"] + b["swishes"],
		"shots": a["shots"] + b["shots"], "bestStreak": maxi(a["bestStreak"], b["bestStreak"]), "iced": a["iced"] + b["iced"],
	}


static func _fresh_state(rng: DetRng) -> Dictionary:
	return {"mood": 1 if rng.next() < 0.5 else -1, "streak": 0, "miss_streak": 0, "iced": false, "ice_hits": 0, "best": 0}


## → {"home": box, "away": box, "ot": n}
static func sim_heat(home: AiRatings, away: AiRatings, seed_value: int, seconds := 90.0, ot_seconds := 20.0, ball_return_s := 1.0) -> Dictionary:
	var rng := DetRng.new(seed_value)
	var hs := _fresh_state(rng)
	var as_ := _fresh_state(rng)
	var h := sim_period(home, rng, shots_for(home, seconds, ball_return_s), hs)
	var a := sim_period(away, rng, shots_for(away, seconds, ball_return_s), as_)
	var ot := 0
	while h["points"] == a["points"]:
		ot += 1
		h = _add(h, sim_period(home, rng, maxi(shots_for(home, ot_seconds, ball_return_s), 3), hs))
		a = _add(a, sim_period(away, rng, maxi(shots_for(away, ot_seconds, ball_return_s), 3), as_))
		if ot > OT_MAX:
			# Equal-rating loop guard: a one-point nudge.
			if rng.next() < 0.5:
				h = _add(h, {"points": 1, "makes": 1, "swishes": 0, "shots": 1, "bestStreak": 0, "iced": 0})
			else:
				a = _add(a, {"points": 1, "makes": 1, "swishes": 0, "shots": 1, "bestStreak": 0, "iced": 0})
			break
	return {"home": h, "away": a, "ot": ot}


## Stable seed from parts (season seed, year, day, game id…).
static func seed_from(parts: Array) -> int:
	var text := ""
	for p in parts:
		text += str(p) + "/"
	return DetRng.hash_seed(text)
