extends SceneTree
## Replay a flick trace (docs/HOME.md → The flick): every gesture the phone
## logged with tuning mode on (user://qa/flick_trace.json, one JSON row per
## release) goes back through FlickInput with its own timestamps, and the
## tool prints the old reading (the 40 ms EMA with the lift-off decay) next
## to the honest one, the ratio between them (what to scale the power band
## by so the tuned feel carries over) and each reading's spread — the
## inconsistency before and after.
##   godot --headless --path . -s tools/flick_trace.gd -- build/qa/flick_trace.json


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "build/qa/flick_trace.json"
	for a in args:
		if not str(a).begins_with("--"):
			path = str(a)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("no trace at " + path)
		quit(1)
		return
	var rows: Array = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var row = JSON.parse_string(line)
		if row is Dictionary and row.has("trace"):
			rows.push_back(row)
	f.close()
	print("%d flicks in %s" % [rows.size(), path])
	var fi := FlickInput.new()
	var news: Array = []
	var olds: Array = []
	var ratios: Array = []
	var i := 0
	for row in rows:
		var trace: Array = row["trace"]
		if trace.size() < 2:
			continue
		var got: Array = [{}]
		var cb := func(s: Dictionary) -> void:
			got[0] = s
		fi.flick_released.connect(cb)
		var first: Array = trace[0]
		fi._begin_at(Vector2(float(first[1]), float(first[2])), int(first[0]))
		for k in range(1, trace.size()):
			var p: Array = trace[k]
			fi._move_at(Vector2(float(p[1]), float(p[2])), int(p[0]))
		var last: Array = trace[trace.size() - 1]
		fi._end_at(int(row.get("lift_usec", last[0])))
		fi.flick_released.disconnect(cb)
		var s: Dictionary = got[0]
		if s.is_empty():
			continue
		var new_sh := float(s["speed_sh"])
		var old_sh := float(s["ema_sh"])
		var frames := trace.size() - 1
		print("  #%02d  old %.2f  new %.2f  peak %.2f  held %3.0f ms  pull %4.0f px  %d samples  %s" % [
			i, old_sh, new_sh, float(s["peak_sh"]), float(s["held_s"]) * 1000.0, float(s["pull_px"]), frames,
			"cancelled" if bool(row.get("cancelled", false)) else "%.1f° %.2f m/s" % [float(row.get("angle", 0.0)), float(row.get("speed", 0.0))]])
		i += 1
		if new_sh > 0.0 and old_sh > 0.0:
			news.push_back(new_sh)
			olds.push_back(old_sh)
			ratios.push_back(new_sh / old_sh)
	if ratios.is_empty():
		print("nothing to compare")
		quit()
		return
	var r_med := _median(ratios)
	print("new / old: median %.2f, mean %.2f, min %.2f, max %.2f" % [r_med, _mean(ratios), ratios.min(), ratios.max()])
	print("old readings: mean %.2f, cv %.1f %%" % [_mean(olds), 100.0 * _sd(olds) / maxf(_mean(olds), 1e-9)])
	print("new readings: mean %.2f, cv %.1f %%" % [_mean(news), 100.0 * _sd(news) / maxf(_mean(news), 1e-9)])
	var tuning := FlickTuning.new()
	print("band today %.2f–%.2f sh/s → at the median ratio %.2f–%.2f" % [tuning.flick_min_sh, tuning.flick_max_sh, tuning.flick_min_sh * r_med, tuning.flick_max_sh * r_med])
	quit()


static func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(a.size(), 1)


static func _sd(a: Array) -> float:
	var m := _mean(a)
	var s := 0.0
	for v in a:
		s += (float(v) - m) * (float(v) - m)
	return sqrt(s / maxf(a.size(), 1))


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	var n := b.size()
	return float(b[n / 2]) if n % 2 == 1 else 0.5 * (float(b[n / 2 - 1]) + float(b[n / 2]))
