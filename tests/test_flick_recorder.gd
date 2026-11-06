extends RefCounted
## The flick recorder (game/debug/flick_recorder.gd, docs/TRAILER.md): what a
## recorded row holds, that a recorded trace replays to the same release,
## and that it only ever runs in a debug build with the DEV switch on.

const TEST_PATH := "user://trailer/test_flicks.jsonl"


## A human-ish gesture through the real estimator: press, pull down, flick up.
func _gesture(fi: FlickInput) -> Dictionary:
	var got: Array = [{}]
	var cb := func(s: Dictionary) -> void: got[0] = s
	fi.flick_released.connect(cb)
	var t := 1_000_000
	fi._begin_at(Vector2(360, 900), t)
	for i in 8:
		t += 37_000 + (i % 3) * 4_000   # uneven, as a finger is
		fi._move_at(Vector2(360 + i * 0.7, 900 + (i + 1) * 24.0), t)
	for i in 9:
		t += 13_000 + (i % 2) * 5_000
		fi._move_at(Vector2(365 - i * 1.5, 1092 - (i + 1) * 46.0), t)
	fi._end_at(t + 6_000)
	fi.flick_released.disconnect(cb)
	return got[0]


func _replay(fi: FlickInput, trace: Array, lift: int) -> Dictionary:
	var got: Array = [{}]
	var cb := func(s: Dictionary) -> void: got[0] = s
	fi.flick_released.connect(cb)
	var first: Array = trace[0]
	fi._begin_at(Vector2(float(first[1]), float(first[2])), int(first[0]))
	for k in range(1, trace.size()):
		var p: Array = trace[k]
		fi._move_at(Vector2(float(p[1]), float(p[2])), int(p[0]))
	fi._end_at(lift)
	fi.flick_released.disconnect(cb)
	return got[0]


func run(t) -> void:
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	# JSON-safe values.
	t.eq(FlickRecorder.clean({"a": NAN, "b": [1.5, INF, {"c": -INF}], "d": "x", 3: true}), {"a": null, "b": [1.5, null, {"c": null}], "d": "x", "3": true}, "NaN and infinity become null, keys become strings")
	t.eq(FlickRecorder.outcome_for({"type": "SWISH", "made": true, "points": 2, "entry_angle_deg": NAN, "streak": 4}),
		{"type": "SWISH", "made": true, "points": 2, "entry_angle_deg": null}, "an outcome keeps its type, make, points and entry angle")
	# A real gesture and its row.
	var fi := FlickInput.new()
	var sample := _gesture(fi)
	t.ok(sample.has("trace") and (sample["trace"] as Array).size() == 18, "the release carries its whole trace (press + 17 moves)")
	t.ok(float(sample["speed_sh"]) > 1.0 and float(sample["pull_px"]) > 100.0, "…a wound-up flick (%.2f sh, %.0f px)" % [float(sample["speed_sh"]), float(sample["pull_px"])])
	var geo := SimGeometry.arcade(App.ARCADE_HOOP_DIST)
	var origin := {"rx": 0.0, "ry": 1.6, "rz": 0.0}
	var tuning := FlickTuning.new()
	var launch := FlickMap.map_windup(sample, tuning, geo, origin)
	t.ok(not launch.is_empty(), "…that maps to a launch")
	var ctx := {"mode": "trial", "area": "cage", "practice": false, "heat": false, "spot": 0, "moving": false, "ball": "classic", "net": "cotton"}
	var row := FlickRecorder.row_for(ctx, sample, launch, origin, tuning.to_dict(), geo)
	for k in ["v", "t_ms", "ctx", "origin", "geo", "tuning", "sample", "launch"]:
		t.ok(row.has(k), "a row has %s" % k)
	t.eq(row["v"], FlickRecorder.VERSION, "…versioned")
	t.eq(row["ctx"], ctx, "…where it was thrown from")
	t.eq([row["geo"]["hoop_x"], row["geo"]["hoop_z"]], [geo.hoop_x, geo.hoop_z], "…the hoop's pose")
	t.eq((row["tuning"] as Dictionary).size(), FlickTuning.FIELDS.size(), "…every tuning value the phone had")
	var back: Variant = JSON.parse_string(JSON.stringify(row))
	t.ok(back is Dictionary and (back["sample"]["trace"] as Array).size() == 18, "the row survives JSON")
	# The point of it all: the trace, replayed, is the same release.
	var again := _replay(FlickInput.new(), back["sample"]["trace"], int(back["sample"]["lift_usec"]))
	for k in ["speed_sh", "peak_sh", "pull_px", "vel_x", "vel_y", "curl", "held_s", "path_px"]:
		t.ok(absf(float(again[k]) - float(sample[k])) < 1e-6, "a replayed trace gives the same %s" % k)
	var relaunch := FlickMap.map_windup(again, tuning, geo, origin)
	t.ok(absf(float(relaunch["speed"]) - float(launch["speed"])) < 1e-9 and absf(float(relaunch["angle_deg"]) - float(launch["angle_deg"])) < 1e-9, "…and so the same launch")
	fi.free()
	# The recorder: a shot waits for its outcome, a cancel is written at once.
	var abs_path := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(abs_path)
	var rec := FlickRecorder.new()
	rec.path = TEST_PATH
	rec.note_flick(ctx, {"speed_sh": 1.0}, launch, origin, tuning.to_dict(), geo)
	t.eq(rec.count(), 0, "a sample with no trace is not a flick")
	rec.note_flick(ctx, sample, launch, origin, tuning.to_dict(), geo)
	t.eq([rec.count(), rec.pending()], [1, 1], "a shot waits for its outcome")
	t.ok(not FileAccess.file_exists(TEST_PATH), "…nothing written yet")
	rec.note_flick(ctx, sample, {}, origin, tuning.to_dict(), geo)
	rec.note_outcome({"type": "BACK_RIM", "made": false, "points": 0, "entry_angle_deg": NAN})
	rec.note_flick(ctx, sample, launch, origin, tuning.to_dict(), geo)
	rec.flush()
	t.eq(rec.pending(), 0, "leaving the court writes what was still in the air")
	var lines := FileAccess.get_file_as_string(TEST_PATH).strip_edges().split("\n")
	t.eq(lines.size(), 3, "three rows written")
	var rows := []
	for l in lines:
		rows.push_back(JSON.parse_string(l))
	t.eq(rows[0]["outcome"], {"type": FlickRecorder.CANCELLED, "made": false}, "the cancelled gesture first, marked")
	t.eq([rows[1]["outcome"]["type"], rows[1]["seq"]], ["BACK_RIM", 0.0], "the shot with the outcome that landed")
	t.eq(rows[2]["outcome"], null, "the ball still in the air has none")
	t.ok(str(rows[1]["session"]) == rec.session and (rec.find_child("Rec", true, false) as Label).text == "REC 3", "rows carry the session; REC n counts on screen")
	rec.free()
	DirAccess.remove_absolute(abs_path)
	# Debug builds only, and only with the DEV switch on.
	if app != null:
		var was: bool = app.record_flicks
		var was_tuning: Dictionary = SaveService.get_tuning()
		app.set_record_flicks(true)
		t.eq(app.record_flicks, OS.is_debug_build(), "RECORD FLICKS turns on only in a debug build")
		t.eq(FlickRecorder.enabled(), OS.is_debug_build(), "…and the recorder follows it")
		t.eq(bool(SaveService.get_tuning().get("recordFlicks", false)), OS.is_debug_build(), "…kept on the device-local tuning part")
		SaveService.put_tuning(bool(was_tuning.get("tuningMode", false)), was_tuning.get("fields", {}))
		t.eq(bool(SaveService.get_tuning().get("recordFlicks", false)), OS.is_debug_build(), "…and a tuning save does not drop it")
		app.set_record_flicks(false)
		t.ok(not FlickRecorder.enabled(), "off: nothing records")
		app.record_flicks = was
		SaveService.put_tuning_record(was)
	var src := FileAccess.get_file_as_string("res://game/screens/time_trial_screen.gd")
	t.ok(src.contains("if FlickRecorder.enabled():") and src.contains("_recorder.note_flick(") and src.contains("_recorder.note_outcome(") and src.contains("_recorder.flush()"), "the court records a release, its outcome, and flushes on the way out")
	t.ok(FileAccess.get_file_as_string("res://game/debug/flick_recorder.gd").contains("return OS.is_debug_build() and App.record_flicks"), "the gate is the debug build AND the switch")
