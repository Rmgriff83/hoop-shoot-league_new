class_name FlickSynth
extends RefCounted
## Stand-in flicks for the trailer (docs/TRAILER.md → Flicks): a touch trace
## shaped like a finger's — an uneven pull down, an uneven flick up — built
## to land a wanted outcome. Used ONLY where Ross has no recording for a
## court or an outcome; the director says so in its log, and Checkpoint A
## marks those shots. Never perfect: the timing and the path are jittered
## from a seed, and the outcome is found by trying gestures through the real
## estimator, mapping and sim, not by aiming at the hoop.

const PRESS := Vector2(360, 940)


## A trace: press, pull down `pull_px`, flick up at about `speed_sh` screen
## heights a second, leaning `tilt_px` sideways. [[usec, x, y], …] + lift.
static func trace(pull_px: float, speed_sh: float, tilt_px: float, rng: DetRng) -> Dictionary:
	var t := 0
	var p := PRESS + Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-24.0, 24.0))
	var pts := [[t, p.x, p.y]]
	var steps := 9 + rng.range_i(0, 4)
	for i in steps:
		t += 26_000 + rng.range_i(0, 18_000)
		var k := float(i + 1) / float(steps)
		var e := 1.0 - (1.0 - k) * (1.0 - k)   # the pull slows as it bottoms out
		pts.push_back([t, p.x + rng.randf_range(-2.0, 2.0), p.y + pull_px * e])
	t += 40_000 + rng.range_i(0, 60_000)       # the beat at the bottom
	var bottom := Vector2(p.x, p.y + pull_px)
	var up := speed_sh * 1280.0               # px/s
	var rise := pull_px + 260.0 + rng.randf_range(0.0, 120.0)
	var dur := rise / maxf(up, 1.0)
	var n := maxi(5, int(dur / 0.0125))
	for i in n:
		var dt := int(dur / n * 1_000_000.0) + rng.range_i(0, 3_000) - 1_500
		t += maxi(dt, 4_000)
		var k := float(i + 1) / float(n)
		pts.push_back([t, bottom.x + tilt_px * k + rng.randf_range(-1.5, 1.5), bottom.y - rise * (0.35 * k + 0.65 * k * k)])
	return {"trace": pts, "lift_usec": t + 4_000 + rng.range_i(0, 6_000)}


## Run a trace through a fresh estimator: the release sample ({} if it never released).
static func sample_of(tr: Dictionary) -> Dictionary:
	var fi := FlickInput.new()
	var got: Array = [{}]
	var cb := func(s: Dictionary) -> void: got[0] = s
	fi.flick_released.connect(cb)
	var pts: Array = tr["trace"]
	fi._begin_at(Vector2(float(pts[0][1]), float(pts[0][2])), int(pts[0][0]))
	for k in range(1, pts.size()):
		fi._move_at(Vector2(float(pts[k][1]), float(pts[k][2])), int(pts[k][0]))
	fi._end_at(int(tr["lift_usec"]))
	fi.flick_released.disconnect(cb)
	fi.free()
	return got[0]


## The outcome a trace gives on this geometry from this hand position:
## {type, made, launch} ({} for a cancelled gesture).
static func outcome_of(tr: Dictionary, tuning: FlickTuning, geo: SimGeometry, origin: Dictionary) -> Dictionary:
	var s := sample_of(tr)
	if s.is_empty():
		return {}
	var launch := FlickMap.map_windup(s, tuning, geo, origin)
	if launch.is_empty():
		return {}
	var o := ShotClassify.classify_shot(ShotSim.run_shot(launch, false, geo))
	return {"type": str(o["type"]), "made": bool(o["made"]), "launch": launch, "sample": s}


## A jittered gesture whose outcome is one of `want` (ShotClassify types),
## or {} if the sweep finds none. `origin_for` gives the hand position for a
## release point (the court's own camera maths).
static func solve(want: Array, tuning: FlickTuning, geo: SimGeometry, origin_for: Callable, seed_value: int) -> Dictionary:
	var rng := DetRng.new(seed_value)
	for attempt in 700:
		var pull := rng.randf_range(140.0, 620.0)
		var speed := rng.randf_range(1.2, 4.4)
		var tilt := rng.randf_range(-26.0, 26.0)
		var tr := trace(pull, speed, tilt, rng)
		var last: Array = (tr["trace"] as Array)[-1]
		var origin: Dictionary = origin_for.call(Vector2(float(last[1]), float(last[2])))
		var o := outcome_of(tr, tuning, geo, origin)
		if not o.is_empty() and want.has(o["type"]):
			tr["outcome"] = {"type": o["type"], "made": o["made"]}
			tr["synth"] = true
			return tr
	return {}
