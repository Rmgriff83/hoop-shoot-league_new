class_name AiCadence
extends RefCounted
## AI shooting rhythm (ported from src/core/ai/cadence.ts, re-keyed to the
## heat's ball-return wait): grab → pre-shot beat → release, never instant.
## `pace` is think time on top of the wait: release-to-release cycle ≈
## ball_return_s + pace × TEMPO, split 40 % pickup delay / 60 % aim, with
## jitter and a composure-scaled hesitation under pressure. The driver starts
## the next cycle at release (like the human, who can grab the next ball while
## the last is in the air). AIM_CAP keeps a hesitating shooter from stalling.

const AIM_CAP := 3.0
## Seconds of think time per point of pace (pace 2.4 → 0.84 s, 5.6 → 1.96 s).
const TEMPO := 0.35
const MIN_PICKUP := 0.25
const MIN_AIM := 0.4


## → {"pickup_delay": s after the release before reaching for the next ball
## (the ball-return wait still applies), "aim_time": s held before the shot}
static func next_cadence(ratings: AiRatings, situation: Dictionary, rng: DetRng, ball_return_s := 1.0) -> Dictionary:
	var think := maxf(ratings.pace, 1.5) * TEMPO
	var pickup_delay := maxf(MIN_PICKUP, maxf(ball_return_s, 0.0) + think * 0.4 * (0.85 + 0.3 * rng.next()))
	var pressure := clampf(-float(situation.get("score_diff", 0)) / 10.0, 0.0, 1.0)
	var hesitation := (1.0 - ratings.composure) * pressure * 0.6 * rng.next()
	var aim_time := think * 0.6 * (0.8 + 0.4 * rng.next()) + hesitation
	if aim_time > AIM_CAP - 0.15 and rng.next() < 0.85:
		aim_time = AIM_CAP - 0.15 - 0.3 * rng.next()
	return {"pickup_delay": pickup_delay, "aim_time": maxf(MIN_AIM, aim_time)}


## Mean release-to-release seconds for a shooter at a given ball-return wait.
static func cycle_s(ratings: AiRatings, ball_return_s := 1.0) -> float:
	return maxf(ball_return_s, 0.0) + maxf(ratings.pace, 1.5) * TEMPO
