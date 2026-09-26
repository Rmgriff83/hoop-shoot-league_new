class_name StreakRules
extends RefCounted
## Streak scoring: the rim catches fire at FIRE_AT makes in a row, and from
## the tier thresholds on each make is worth more. A swish always adds +1 on
## top of the tier's base. Pure, static, no nodes — used by TimeTrial (core)
## and by the screens for messaging.
##
##   makes in a row (counting this make)   base points
##   1 – 5                                  1   (rim lights on the 5th)
##   6 – 7                                  2
##   8 – 10                                 3
##   11 +                                   4

## A fire power-up card (TimeTrial.light_rim) sets the streak straight to
## FIRE_AT for its window, so the tiers below apply as if the shooter had just
## caught fire; the window's end, a miss or ice resets it.
const FIRE_AT := 5
## [streak count from which a make pays N, N] — ascending.
const TIERS := [[6, 2], [8, 3], [11, 4]]
const SWISH_BONUS := 1

## Cold streak: misses in a row that ice the rim over. While iced a swish
## still drops through and scores (and breaks the ice); any other would-be
## make is caught by the ice and popped out for nothing (breaking it too);
## ICE_BREAK_HITS rim hits in total across shots also break it.
const COLD_AT := 7
const ICE_BREAK_HITS := 3


## Base points for a make that brings the streak to `streak_after`.
static func base_points(streak_after: int) -> int:
	var pts := 1
	for tier in TIERS:
		if streak_after >= int(tier[0]):
			pts = int(tier[1])
	return pts


## Points for a make at this streak length (swish adds SWISH_BONUS at every tier).
static func points_for(streak_after: int, swish: bool) -> int:
	return base_points(streak_after) + (SWISH_BONUS if swish else 0)


## Is the rim on fire at this streak length?
static func is_lit(streak: int) -> bool:
	return streak >= FIRE_AT


## The next threshold above `streak`: {"at": makes in a row, "points": base}.
## Below FIRE_AT the "next" is the fire itself (points stay 1). Empty at the top.
static func next_tier(streak: int) -> Dictionary:
	if streak < FIRE_AT:
		return {"at": FIRE_AT, "points": 1}
	for tier in TIERS:
		if streak < int(tier[0]):
			return {"at": int(tier[0]), "points": int(tier[1])}
	return {}
