extends SceneTree
## Monte-Carlo calibration of the AI aim tables per hoop geometry (port of the
## original scripts/calibrate.ts). Writes assets/ai/calibration_<key>.json with
##   sigma_v:    [[make probability, speed sigma], ...]  (descending p)
##   acc_lookup: [[target make probability, sigma-table input], ...]  (ascending)
## Run after any physics-constant change:
##   godot --headless --path . -s tools/calibrate_ai.gd            (all keys)
##   godot --headless --path . -s tools/calibrate_ai.gd -- arcade  (one key)
## Deterministic (seeded DetRng), ~1–3 min per key.

const N := 1500
const OUT_DIR := "res://assets/ai"
const GRID := [0.002, 0.005, 0.008, 0.012, 0.017, 0.023, 0.03, 0.04, 0.055, 0.075, 0.1, 0.13, 0.17, 0.22, 0.28, 0.36]
const LOOKUPS := [0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95]


static func geo_for(key: String) -> SimGeometry:
	match key:
		"arcade":
			return SimGeometry.arcade()
		"beach":
			return SimGeometry.beach()
		"city":
			return SimGeometry.city()
		_:
			return SimGeometry.regulation()


func _make_rate_for_sigma(sigma_v: float, geo: SimGeometry, rng: DetRng) -> float:
	var makes := 0
	for i in N:
		var angle := 50.0 + 1.5 * rng.normal()
		var ideal := Ballistics.speed_for_angle(angle, geo.hoop_x, geo.rise)
		var out := ShotSim.simulate_shot({"angle_deg": angle, "speed": ideal * (1.0 + sigma_v * rng.normal()), "vz": 0.05 * rng.normal()}, true, geo)
		if out["made"]:
			makes += 1
	return float(makes) / float(N)


## Full pipeline with the lookup bypassed (acc fed straight to the sigma table).
func _pipeline_rate(lookup: float, geo: SimGeometry, calib: Dictionary, rng: DetRng) -> float:
	var ratings := AiRatings.make(lookup, 0.6)
	var mood := AiMood.init_mood(ratings, rng)
	var identity := {"sigma_v": calib["sigma_v"], "acc_lookup": [[0.0, 0.0], [1.0, 1.0]]}
	var makes := 0
	for i in N:
		var launch := AimError.ai_shot(ratings, mood, {"score_diff": 0, "time_left": 45.0}, rng, geo, identity, 1.0)
		if ShotSim.simulate_shot(launch, true, geo)["made"]:
			makes += 1
	return float(makes) / float(N)


func _calibrate(key: String) -> void:
	var geo := geo_for(key)
	var rng := DetRng.new(1234 + DetRng.hash_seed(key) % 1000)
	print("== %s (hoop_x %.2f)" % [key, geo.hoop_x])
	var sigma_v := []
	for sv in GRID:
		var p := _make_rate_for_sigma(float(sv), geo, rng)
		sigma_v.append([snappedf(p, 0.001), sv])
		print("  sigma %.3f -> make %.3f" % [sv, p])
	# Enforce monotone descending probabilities (noise can wobble adjacent rows).
	for i in range(1, sigma_v.size()):
		if sigma_v[i][0] > sigma_v[i - 1][0]:
			sigma_v[i][0] = sigma_v[i - 1][0]
	var calib := {"sigma_v": sigma_v, "acc_lookup": []}
	var lookup_rows := []
	for L in LOOKUPS:
		var observed := _pipeline_rate(float(L), geo, calib, rng)
		lookup_rows.append([snappedf(observed, 0.001), L])
		print("  lookup %.2f -> observed make %.3f" % [L, observed])
	lookup_rows.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(1, lookup_rows.size()):
		if lookup_rows[i][0] <= lookup_rows[i - 1][0]:
			lookup_rows[i][0] = lookup_rows[i - 1][0] + 0.001
	calib["acc_lookup"] = lookup_rows
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open("%s/calibration_%s.json" % [OUT_DIR, key], FileAccess.WRITE)
	f.store_string(JSON.stringify(calib, "  "))
	f.close()
	print("WROTE %s/calibration_%s.json" % [OUT_DIR, key])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var keys: Array = args if not args.is_empty() else ["regulation", "arcade", "beach", "city"]
	for k in keys:
		_calibrate(str(k))
	quit(0)
