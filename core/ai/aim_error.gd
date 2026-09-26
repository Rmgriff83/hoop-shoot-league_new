class_name AimError
extends RefCounted
## Ratings → physical aim error (ported from src/core/ai/aimError.ts): the AI
## solves the ideal shot analytically, then perturbs it —
##   swish_rate → launch-angle distribution (into the 52–55° swish window)
##   accuracy   → speed-error sigma (speed dominates make probability)
## The shared physics sim resolves the result; no dice rolls on outcomes.
##
## The two tables are FITTED per hoop geometry by tools/calibrate_ai.gd
## (assets/ai/calibration_<key>.json): SIGMA_V maps make probability → speed
## sigma (fraction of ideal speed); ACC_LOOKUP compensates the full pipeline
## (angle spread + lateral wobble on top of speed error). Re-run the tool after
## any physics-constant change. The defaults below are the original game's
## regulation-distance fit.

const DEFAULT_SIGMA_V := [
	[0.97, 0.002], [0.88, 0.005], [0.73, 0.008], [0.59, 0.012], [0.5, 0.017], [0.45, 0.023],
	[0.39, 0.03], [0.35, 0.04], [0.27, 0.055], [0.2, 0.075], [0.16, 0.1], [0.13, 0.13],
]
const DEFAULT_ACC_LOOKUP := [
	[0.29, 0.436], [0.39, 0.545], [0.51, 0.613], [0.63, 0.687], [0.77, 0.761], [0.87, 0.825],
]
const CALIB_DIR := "res://assets/ai"

static var _calibs: Dictionary = {}


## A calibration: {"sigma_v": [[makeP, sigma]...] descending, "acc_lookup": [[target, lookup]...] ascending}
static func default_calibration() -> Dictionary:
	return {"sigma_v": DEFAULT_SIGMA_V, "acc_lookup": DEFAULT_ACC_LOOKUP}


## Calibration for a geometry key ("regulation", "arcade", "beach"…); falls
## back to the defaults when no fitted file exists.
static func calibration_for(key: String) -> Dictionary:
	if _calibs.has(key):
		return _calibs[key]
	var path := "%s/calibration_%s.json" % [CALIB_DIR, key]
	var calib := default_calibration()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and parsed.has("sigma_v") and parsed.has("acc_lookup"):
			calib = parsed
	_calibs[key] = calib
	return calib


static func set_calibration(key: String, calib: Dictionary) -> void:
	_calibs[key] = calib


static func lookup_for(target: float, calib: Dictionary) -> float:
	var t: Array = calib["acc_lookup"]
	var first: Array = t[0]
	var last: Array = t[t.size() - 1]
	if target <= float(first[0]):
		return maxf(float(first[1]) - (float(first[0]) - target) * 1.09, 0.1)
	if target >= float(last[0]):
		return minf(float(last[1]) + (target - float(last[0])) * 0.64, 0.97)
	for i in t.size() - 1:
		var lo: Array = t[i]
		var hi: Array = t[i + 1]
		if target >= float(lo[0]) and target <= float(hi[0]):
			return float(lo[1]) + ((target - float(lo[0])) / (float(hi[0]) - float(lo[0]))) * (float(hi[1]) - float(lo[1]))
	return float(last[1])


## Interpolate the fitted table: make probability → σv fraction.
static func sigma_v_for(make_p: float, calib: Dictionary) -> float:
	var t: Array = calib["sigma_v"]
	var first: Array = t[0]
	var last: Array = t[t.size() - 1]
	if make_p >= float(first[0]):
		return float(first[1])
	if make_p <= float(last[0]):
		return float(last[1])
	for i in t.size() - 1:
		var hi: Array = t[i]
		var lo: Array = t[i + 1]
		if make_p <= float(hi[0]) and make_p >= float(lo[0]):
			var f := (float(hi[0]) - make_p) / (float(hi[0]) - float(lo[0]))
			return float(hi[1]) + (float(lo[1]) - float(hi[1])) * f
	return float(last[1])


## Mean launch angle: swish_rate 0.9 shooters live at ~53° — the swish window.
static func mean_angle_for(swish_rate: float) -> float:
	return 44.0 + 10.0 * swish_rate


## Angle discipline: high swish_rate = tight arc selection.
static func sigma_angle_for(swish_rate: float) -> float:
	return 3.4 - 2.2 * swish_rate


## One AI shot for `geo`: ideal solve + rating-scaled perturbation.
## err_mult = the league's difficulty multiplier (ratings stay fixed for honest
## standings; the tier scales error). Returns a launch {angle_deg, speed, vz}.
## `dist`/`rise` override the shot's range when the shooter stands off the
## centre spot (NAN = the geometry's own hoop_x / rise).
static func ai_shot(ratings: AiRatings, mood: AiMood, situation: Dictionary, rng: DetRng,
		geo: SimGeometry, calib: Dictionary, err_mult := 1.0, dist := NAN, rise := NAN) -> Dictionary:
	var acc := AiMood.effective_accuracy(ratings, mood, situation)
	var angle_deg := clampf(mean_angle_for(ratings.swish_rate)
		+ sigma_angle_for(ratings.swish_rate) * err_mult * rng.normal(), 35.0, 66.0)
	var d := geo.hoop_x if is_nan(dist) else dist
	var r := geo.rise if is_nan(rise) else rise
	var ideal := Ballistics.speed_for_angle(angle_deg, d, r)
	if is_nan(ideal):
		angle_deg = 52.0
		ideal = Ballistics.speed_for_angle(angle_deg, d, r)
	var sigma_v := sigma_v_for(lookup_for(acc, calib), calib) * err_mult
	var speed := ideal * (1.0 + sigma_v * rng.normal())
	var vz := (0.16 * (1.0 - acc) * rng.normal() + 0.02 * rng.normal()) * err_mult
	return {"angle_deg": angle_deg, "speed": speed, "vz": vz}
