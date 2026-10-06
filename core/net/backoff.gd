class_name Backoff
extends RefCounted
## Client-side throttling (docs/BACKEND.md → Throttling, layer 1): how long
## to wait after a failure and whether a periodic call may fire yet. Pure.

const BASE_S := 2.0
const CAP_S := 300.0
## A spread of ±25 % so a thousand phones coming back online do not knock
## on the same second.
const JITTER := 0.25


## Seconds to wait before attempt `attempt` (0 = the first retry): 2, 4, 8 …
## capped at five minutes, jittered by `u` in [0, 1). A server `Retry-After`
## (seconds, ≥ 0) wins outright, with at least a second's grace.
static func next_delay(attempt: int, retry_after := -1.0, u := 0.5) -> float:
	if retry_after >= 0.0:
		return maxf(retry_after, 1.0)
	var base := minf(CAP_S, BASE_S * pow(2.0, float(maxi(attempt, 0))))
	var spread := 1.0 + JITTER * (2.0 * clampf(u, 0.0, 1.0) - 1.0)
	return minf(CAP_S, base * spread)


## May a call that last fired at `last` (seconds; < 0 = never) fire at `now`
## given a minimum gap?
static func can_fire(now: float, last: float, min_gap: float) -> bool:
	return last < 0.0 or now - last >= min_gap
