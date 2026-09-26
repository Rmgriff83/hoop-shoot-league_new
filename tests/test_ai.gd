extends RefCounted
## AI calibration regression (port of tests/aiCalibration.spec.ts) on the
## arcade geometry, plus mood/cadence bounds. Re-run tools/calibrate_ai.gd
## after physics changes if this drifts.

const N := 600


func _ratings(acc: float, swish: float) -> AiRatings:
	return AiRatings.make(acc, swish, 4.0, 0.5, 0.0, 1.0)


func _observed(r: AiRatings, n: int, seed_v: int, geo: SimGeometry, calib: Dictionary) -> Dictionary:
	var rng := DetRng.new(seed_v)
	var mood := AiMood.init_mood(r, rng)
	var makes := 0
	var swishes := 0
	for i in n:
		var launch := AimError.ai_shot(r, mood, {"score_diff": 0, "time_left": 45.0}, rng, geo, calib, 1.0)
		var out := ShotSim.simulate_shot(launch, true, geo)
		if out["made"]:
			makes += 1
			if out["type"] == ShotClassify.SWISH:
				swishes += 1
	return {"make": float(makes) / n, "swish_share": (float(swishes) / makes) if makes > 0 else 0.0}


func run(t) -> void:
	var geo := SimGeometry.arcade()
	var calib := AimError.calibration_for("arcade")
	t.ok(calib.has("sigma_v") and calib.has("acc_lookup"), "arcade calibration loads")
	t.ok(FileAccess.file_exists("res://assets/ai/calibration_arcade.json"), "arcade calibration file exists (tools/calibrate_ai.gd)")
	for acc in [0.4, 0.6, 0.8]:
		var a: float = acc
		var obs := _observed(_ratings(a, 0.6), N, 7 + int(a * 100), geo, calib)
		t.ok(absf(float(obs["make"]) - a) < 0.08, "accuracy %.1f → observed make %.3f (±0.08)" % [a, obs["make"]])
	var low := _observed(_ratings(0.7, 0.2), N, 11, geo, calib)
	var high := _observed(_ratings(0.7, 0.9), N, 12, geo, calib)
	t.ok(float(high["swish_share"]) > float(low["swish_share"]) + 0.05, "swish share rises with swish_rate (%.2f vs %.2f)" % [high["swish_share"], low["swish_share"]])
	# Cadence: think time over the ball-return wait, floors, rare stalls.
	var rng := DetRng.new(5)
	var r := AiRatings.make(0.6, 0.6, 4.0, 0.7, 0.3, 0.8)
	var late := 0
	var total := 0.0
	for i in 500:
		var c := AiCadence.next_cadence(r, {"score_diff": 0, "time_left": 30.0}, rng, 1.0)
		t.ok(float(c["pickup_delay"]) >= AiCadence.MIN_PICKUP, "pickup delay never instant") if i == 0 else null
		t.ok(float(c["aim_time"]) >= AiCadence.MIN_AIM, "aim time ≥ MIN_AIM") if i == 0 else null
		t.ok(float(c["pickup_delay"]) >= 1.0, "pickup delay covers the ball-return wait") if i == 0 else null
		total += float(c["pickup_delay"]) + float(c["aim_time"])
		if float(c["aim_time"]) >= AiCadence.AIM_CAP:
			late += 1
	var mean := total / 500.0
	t.close(mean, AiCadence.cycle_s(r, 1.0), 0.15 * AiCadence.cycle_s(r, 1.0), "mean cycle ≈ wait + pace × TEMPO (%.2f vs %.2f)" % [mean, AiCadence.cycle_s(r, 1.0)])
	t.ok(late / 500.0 < 0.06, "rarely stalls past the aim cap (%d/500)" % late)
	var rng2 := DetRng.new(5)
	var c15 := AiCadence.next_cadence(r, {"score_diff": 0, "time_left": 30.0}, rng2, 1.5)
	var rng3 := DetRng.new(5)
	var c10 := AiCadence.next_cadence(r, {"score_diff": 0, "time_left": 30.0}, rng3, 1.0)
	t.close(float(c15["pickup_delay"]) - float(c10["pickup_delay"]), 0.5, 1e-6, "a longer wait adds straight to the pickup delay")
	var fast := AiRatings.make(0.6, 0.6, 2.4)
	var slow := AiRatings.make(0.6, 0.6, 5.6)
	t.ok(AiCadence.cycle_s(fast, 1.0) < AiCadence.cycle_s(slow, 1.0), "faster pace → shorter cycle")
	t.close(AiCadence.cycle_s(fast, 1.0), 1.84, 1e-6, "pace 2.4 in a league heat ≈ 1.84 s a shot")
	# Mood: pressure and streak shift accuracy within bounds.
	var m := AiMood.init_mood(r, DetRng.new(3))
	var base := AiMood.effective_accuracy(r, m, {"score_diff": 0})
	var trailing := AiMood.effective_accuracy(r, m, {"score_diff": -10})
	t.ok(trailing > base, "composed shooter steels when trailing")
	t.ok(base >= 0.05 and base <= 0.97, "effective accuracy clamped")
	# Determinism: same seed → identical shots.
	var s1 := AimError.ai_shot(r, AiMood.init_mood(r, DetRng.new(9)), {"score_diff": 0}, DetRng.new(9), geo, calib)
	var s2 := AimError.ai_shot(r, AiMood.init_mood(r, DetRng.new(9)), {"score_diff": 0}, DetRng.new(9), geo, calib)
	t.eq(s1, s2, "ai_shot replays from a seed")
