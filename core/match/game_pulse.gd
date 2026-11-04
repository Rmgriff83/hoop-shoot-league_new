class_name GamePulse
extends RefCounted
## The game pulse (design "League Post-Match v2" 6b, 2026-11-04; docs/HOME.md
## → League post-match): both sides' score sampled every `Heat.PULSE_STEP`
## seconds of the match clock, `Heat.result()["pulse"] = {step, you, opp}`
## (the last pair is the final; OT carries the series on), read into what
## the chart shows — the axis top, the margin's extremes, the lead changes,
## the caption's kind and its marker, the clock ticks. Headless and pure;
## the caption's words are `HeatCopy.pulse_caption`'s.

## A comeback / a slip is a margin this big against the final result.
const MARGIN_MARK := 6
## Fewer lead changes than this is a wire-to-wire game or a chase.
const CHANGES_MARK := 2
const REGULATION_S := 90.0


## Everything the chart draws from a result's `pulse`; `{}` for fewer than two samples.
static func analyse(pulse: Dictionary, regulation_s := REGULATION_S) -> Dictionary:
	var you: Array = pulse.get("you", [])
	var opp: Array = pulse.get("opp", [])
	var n := mini(you.size(), opp.size())
	if n < 2:
		return {}
	var step := float(pulse.get("step", 2.0))
	var duration := (n - 1) * step
	var last := n - 1
	var lo := 0
	var hi := 0
	var lo_i := 0
	var hi_i := 0
	var changes := 0
	var lead := 0
	for i in n:
		var d := int(you[i]) - int(opp[i])
		if d < lo:
			lo = d
			lo_i = i
		if d > hi:
			hi = d
			hi_i = i
		var s := signi(d)
		if s != 0 and lead != 0 and s != lead:
			changes += 1
		if s != 0:
			lead = s
	var won := int(you[last]) > int(opp[last])
	var kind := ""
	var mark_i := -1
	var mark_text := ""
	if won and lo <= -MARGIN_MARK:
		kind = "comeback"
		mark_i = lo_i
		mark_text = str(lo)
	elif not won and hi >= MARGIN_MARK:
		kind = "slipped"
		mark_i = hi_i
		mark_text = "+%d" % hi
	elif changes >= CHANGES_MARK:
		kind = "changes"
	else:
		kind = "wire" if won else "chased"
	var top := int(ceil((maxi(int(you[last]), int(opp[last])) + 3) / 10.0)) * 10
	return {
		"you": you.duplicate(), "opp": opp.duplicate(), "step": step, "duration": duration,
		"ot": duration > regulation_s + 1e-6, "won": won,
		"lo": lo, "lo_i": lo_i, "hi": hi, "hi_i": hi_i, "changes": changes,
		"kind": kind, "mark_i": mark_i, "mark_text": mark_text, "mark_t": mark_i * step if mark_i >= 0 else -1.0,
		"max": maxi(top, 10), "ticks": ticks(duration, regulation_s),
	}


## `m:ss` of a clock reading.
static func fmt(seconds: float) -> String:
	var s := roundi(seconds)
	return "%d:%02d" % [s / 60, s % 60]


## The four clock ticks under the chart: thirds of the game, or with overtime
## the half, the buzzer and the end.
static func ticks(duration: float, regulation_s := REGULATION_S) -> Array:
	if duration > regulation_s + 1e-6:
		return [fmt(0.0), fmt(regulation_s * 0.5), fmt(regulation_s), fmt(duration)]
	return [fmt(0.0), fmt(duration / 3.0), fmt(duration * 2.0 / 3.0), fmt(duration)]


## A pulse from keyframes (the design's fixtures, QA, tests): `kt` the clock
## of each frame, `ky` / `ko` the scores there, linear between, sampled every `step`.
static func from_keyframes(kt: Array, ky: Array, ko: Array, step := 2.0) -> Dictionary:
	var d := float(kt[kt.size() - 1])
	var you: Array[int] = []
	var opp: Array[int] = []
	var s := 0.0
	while s <= d + 1e-6:
		you.push_back(_at(kt, ky, s))
		opp.push_back(_at(kt, ko, s))
		s += step
	return {"step": step, "you": you, "opp": opp}


static func _at(kt: Array, k: Array, s: float) -> int:
	var i := 0
	while i < kt.size() - 2 and s > float(kt[i + 1]):
		i += 1
	var f := (s - float(kt[i])) / (float(kt[i + 1]) - float(kt[i]))
	return roundi(float(k[i]) + (float(k[i + 1]) - float(k[i])) * minf(1.0, f))
