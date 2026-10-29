extends RefCounted
## FlickInput (docs/HOME.md → The flick, 2026-10-25): the release speed
## measures the flick — a short fixed window, the fastest of the final
## stretch, no ramp from the pull, no random lift-off decay — and the latch
## gives the charge back what the turn drained.

const H := 1280.0
const FRAME := 16_667   # µs, 60 Hz


## A gesture: a press at `start`, then moves of `steps` ([dx, dy] px per frame
## in design px), one per frame unless a `pause_us` precedes a step (an Array
## entry [dx, dy, pause_us]). Returns the released sample.
func _gesture(fi: FlickInput, start: Vector2, steps: Array, lift_gap_us := 0) -> Dictionary:
	var out: Array = [{}]   # a holder: a lambda captures locals by value
	var cb := func(s: Dictionary) -> void:
		out[0] = s
	fi.flick_released.connect(cb)
	var t := 1_000_000
	var pos := start
	fi._begin_at(pos, t)
	for st in steps:
		var gap: int = FRAME
		if st.size() > 2:
			gap = int(st[2])
		t += gap
		pos += Vector2(float(st[0]), float(st[1]))
		fi._move_at(pos, t)
	fi._end_at(t + lift_gap_us)
	fi.flick_released.disconnect(cb)
	return out[0]


## A pull of `pull` px down over 8 frames, then `frames` upward frames at `sh` screen-heights/s.
func _pull_then_flick(pull: float, frames: int, sh: float, extra: Array = []) -> Array:
	var steps: Array = []
	for i in 8:
		steps.push_back([0.0, pull / 8.0])
	var per := sh * H / 60.0
	for i in frames:
		steps.push_back([0.0, -per])
	return steps + extra


func run(t) -> void:
	var fi := FlickInput.new()
	var start := Vector2(360, 1000)
	# 1. The speed is the flick's, whatever its length.
	var s4 := _gesture(fi, start, _pull_then_flick(300.0, 4, 5.0))
	t.ok(absf(float(s4["speed_sh"]) - 5.0) < 0.15, "a 4-frame flick at 5.0 sh reads 5.0 (%.2f)" % float(s4["speed_sh"]))
	var s3 := _gesture(fi, start, _pull_then_flick(300.0, 3, 5.0))
	var s8 := _gesture(fi, start, _pull_then_flick(300.0, 8, 5.0))
	t.ok(absf(float(s3["speed_sh"]) - float(s8["speed_sh"])) < 0.15, "3 and 8 frames read alike (%.2f / %.2f): no ramp" % [float(s3["speed_sh"]), float(s8["speed_sh"])])
	t.ok(float(s4["vel_y"]) < 0.0 and absf(float(s4["vel_x"])) < 1.0, "the release velocity points up")
	t.ok(absf(float(s4["vel_y"]) / H) - 5.0 < 0.15, "vel_y carries the same speed")
	t.ok(float(s4["ema_sh"]) < float(s4["speed_sh"]) * 0.95, "the old EMA reading sat under it (%.2f): the trace keeps it" % float(s4["ema_sh"]))
	# 2. Lift-off a frame after the last move is the same speed (no random decay).
	var late := _gesture(fi, start, _pull_then_flick(300.0, 4, 5.0), FRAME)
	t.ok(absf(float(late["speed_sh"]) - float(s4["speed_sh"])) < 0.01, "a 17 ms delivery gap before lift-off changes nothing (%.2f)" % float(late["speed_sh"]))
	t.ok(float(late["held_s"]) > 0.016, "…and the sample says how long the gap was")
	# 3. A rest at the bottom: the charge is kept whole, the speed is the flick's.
	var rest_steps := _pull_then_flick(300.0, 0, 0.0)
	var per := 5.0 * H / 60.0
	rest_steps.push_back([0.0, -per, 200_000])   # the first move after a 200 ms rest
	for i in 3:
		rest_steps.push_back([0.0, -per])
	var rest := _gesture(fi, start, rest_steps)
	t.ok(absf(float(rest["pull_px"]) - 300.0) < 1e-6, "a rest at the bottom then a flick keeps the whole pull (%.1f)" % float(rest["pull_px"]))
	t.ok(absf(float(rest["speed_sh"]) - 5.0) < 0.15, "…and reads the flick's speed (%.2f)" % float(rest["speed_sh"]))
	# 3b. A slow pull with sparse events (gaps over REST_S) still charges in full.
	var slow_pull: Array = []
	for i in 6:
		slow_pull.push_back([0.0, 50.0, 70_000])
	for i in 4:
		slow_pull.push_back([0.0, -per])
	var slow := _gesture(fi, start, slow_pull)
	t.ok(absf(float(slow["pull_px"]) - 300.0) < 1e-6, "a slow pull (70 ms between events) charges in full (%.1f)" % float(slow["pull_px"]))
	t.ok(absf(float(slow["speed_sh"]) - 5.0) < 0.15, "…and the flick after it reads its speed (%.2f)" % float(slow["speed_sh"]))
	# 4. The throw's first frames no longer drain the arc.
	t.ok(absf(float(s4["pull_px"]) - 300.0) < 1e-6, "a straight flick keeps the pull it turned from (%.1f)" % float(s4["pull_px"]))
	# The live pull (ShotFeel's, 2026-10-28) is never latched: the flick
	# drains it as the finger comes back up, while the throw keeps the 300.
	var live: Array = []
	var live_cb := func(px: float) -> void:
		live.push_back(px)
	fi.pull_changed.connect(live_cb)
	var s4b := _gesture(fi, start, _pull_then_flick(300.0, 4, 5.0))
	fi.pull_changed.disconnect(live_cb)
	t.ok(absf(float(s4b["pull_px"]) - 300.0) < 1e-6, "…the throw's pull is still the latched 300")
	t.ok(live.size() >= 13 and absf(float(live[8]) - 300.0) < 1e-6, "the live pull reached 300 at the turn (%s)" % str(live[8] if live.size() > 8 else null))
	t.ok(float(live[live.size() - 1]) < 1e-6, "…and the flick drained it to 0 by lift-off (%.1f)" % float(live[live.size() - 1]))
	t.ok(float(live[9]) < float(live[8]) and float(live[9]) > 0.0, "…shrinking from the flick's first frame (%.1f)" % float(live[9]))
	# 5. A slow ease-up discharges and never latches.
	var latched_any: Array = [false]
	var speeds: Array = []
	var cb := func(sh: float, latched: bool) -> void:
		speeds.push_back(sh)
		if latched:
			latched_any[0] = true
	fi.flick_charging.connect(cb)
	var ease_steps := _pull_then_flick(300.0, 0, 0.0)
	for i in 10:
		ease_steps.push_back([0.0, -0.3 * H / 60.0])
	var ease := _gesture(fi, start, ease_steps)
	fi.flick_charging.disconnect(cb)
	t.ok(not bool(latched_any[0]), "an ease-up at 0.3 sh never latches")
	t.ok(float(ease["pull_px"]) < 300.0 - 50.0, "…and discharges the pull (%.1f)" % float(ease["pull_px"]))
	t.ok(not speeds.is_empty() and absf(float(speeds[speeds.size() - 1]) - 0.3) < 0.05, "flick_charging reports the window speed (%.2f)" % float(speeds[speeds.size() - 1]))
	# 6. A flick that stops and rests before lift-off is a soft hold.
	var hold := _gesture(fi, start, _pull_then_flick(300.0, 4, 5.0), 200_000)
	t.ok(float(hold["speed_sh"]) < 0.5, "a 200 ms hold before lift-off is soft (%.2f)" % float(hold["speed_sh"]))
	# 7. Sideways motion changes no charge; a tap cancels in the mapping.
	var side_steps: Array = []
	for i in 8:
		side_steps.push_back([0.0, 30.0])
	for i in 6:
		side_steps.push_back([40.0, 0.0])
	var side := _gesture(fi, start, side_steps)
	t.ok(absf(float(side["pull_px"]) - 240.0) < 1e-6, "sideways motion leaves the charge alone (%.1f)" % float(side["pull_px"]))
	var tap := _gesture(fi, start, [[0.0, 2.0]])
	t.ok(FlickMap.map_windup(tap, FlickTuning.new(), SimGeometry.arcade()).is_empty(), "a tap cancels in the mapping (dead zone)")
	# 8. A fast window with a slower last frame still reads the fast one (the finger leaves the glass).
	var taper := _pull_then_flick(300.0, 4, 5.0, [[0.0, -2.0 * H / 60.0]])
	var tp := _gesture(fi, start, taper)
	t.ok(float(tp["speed_sh"]) > 4.0, "a tapering last frame keeps the flick's peak (%.2f)" % float(tp["speed_sh"]))
	# 9. The mapping takes the sample as before.
	var launch := FlickMap.map_windup(s4, FlickTuning.new(), SimGeometry.arcade())
	t.ok(not launch.is_empty() and float(launch["speed"]) > 0.0, "map_windup launches from the sample")
	# 10. Presses in the UI zone are ignored.
	var ignored := _gesture(fi, Vector2(360, 100), [[0.0, 50.0]])
	t.ok(ignored.is_empty(), "a press above the grab zone never tracks")
	fi.free()
