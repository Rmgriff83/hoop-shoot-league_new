extends SceneTree
## League difficulty lab (docs/LEAGUE.md → Difficulty ladder): plays every
## roster shooter against one reference player bot on the league's real
## geometry, error multiplier, format and calibration (CardLab.run_heat, no
## cards) and prints what the ladder is IN POINTS — mean AI points per heat,
## the reference's points, the AI's win share, and per league the pushover
## count (the reference wins at least 75 % of heats), the top shooter and
## the beach/cage and city/cage ratios. Writes assets/ai/league_ladder.json,
## which tests/test_league_ladder.gd pins.
##   godot --headless --path . -s tools/league_lab.gd            (all leagues)
##   godot --headless --path . -s tools/league_lab.gd -- beach   (one league, others kept)
##   godot --headless --path . -s tools/league_lab.gd -- --n=20  (quick look)
## Deterministic (seeded): the same n and seed rewrite the same file.
## About 0.4 s a heat: n × 21 shooters.

const N := 40
const SEED := 7171
const OUT := "res://assets/ai/league_ladder.json"
## A decent human: the reference every shooter is measured against.
const REF := {"accuracy": 0.55, "swish": 0.5, "pace": 4.0, "composure": 0.6, "streakiness": 0.3, "consistency": 0.8}
## A pushover: a shooter the reference beats at least three times in four.
const PUSHOVER_WIN := 0.25


static func reference() -> AiRatings:
	return AiRatings.make(float(REF["accuracy"]), float(REF["swish"]), float(REF["pace"]), float(REF["composure"]),
		float(REF["streakiness"]), float(REF["consistency"]))


## One league's table: {shooters: {id: {ai, ref, win, acc}}, mean, min, max, top, top_id, pushovers, ref_mean}.
static func measure(league: Dictionary, n: int, seed_value: int) -> Dictionary:
	var ratings := LeagueData.league_ratings(league)
	var ids: Array = ratings.keys()
	ids.sort()
	var ref := reference()
	var out := {"shooters": {}, "n": n}
	var sum := 0.0
	var ref_sum := 0.0
	var top := -1.0
	var top_id := ""
	var low := INF
	for id in ids:
		var ai_sum := 0.0
		var r_sum := 0.0
		var wins := 0
		for i in n:
			var heat_seed := int(QuickSim.seed_from([seed_value, league.get("id", "?"), id, i]) & 0x7FFFFFFF)
			var h := CardLab.run_heat(league, ratings[id], ref, heat_seed, "")
			ai_sum += float(h["ai"])
			r_sum += float(h["player"])
			if int(h["ai"]) > int(h["player"]):
				wins += 1
		var ai_mean := ai_sum / n
		var r_mean := r_sum / n
		out["shooters"][id] = {"ai": snappedf(ai_mean, 0.1), "ref": snappedf(r_mean, 0.1), "win": snappedf(float(wins) / n, 0.01),
			"acc": (ratings[id] as AiRatings).accuracy}
		sum += ai_mean
		ref_sum += r_mean
		low = minf(low, ai_mean)
		if ai_mean > top:
			top = ai_mean
			top_id = str(id)
	var ref_mean := ref_sum / ids.size()
	var pushovers := 0
	for id in ids:
		if float(out["shooters"][id]["win"]) <= PUSHOVER_WIN:
			pushovers += 1
	out["mean"] = snappedf(sum / ids.size(), 0.1)
	out["min"] = snappedf(low, 0.1)
	out["max"] = snappedf(top, 0.1)
	out["top_id"] = top_id
	out["ref_mean"] = snappedf(ref_mean, 0.1)
	out["pushovers"] = pushovers
	out["err_mult"] = float(league.get("err_mult", 1.0))
	return out


func _initialize() -> void:
	var n := N
	var only: Array[String] = []
	for a in OS.get_cmdline_user_args():
		var arg := str(a)
		if arg.begins_with("--n="):
			n = int(arg.trim_prefix("--n="))
		else:
			only.push_back(arg)
	var doc := {}
	if FileAccess.file_exists(OUT):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(OUT))
		if parsed is Dictionary:
			doc = parsed
	if doc.is_empty() or int(doc.get("n", 0)) != n or int(doc.get("seed", 0)) != SEED:
		doc = {"n": n, "seed": SEED, "reference": REF, "pushover_win": PUSHOVER_WIN, "leagues": {}}
	var t0 := Time.get_ticks_msec()
	for league in LeagueData.leagues():
		var lid := str(league["id"])
		if not only.is_empty() and not only.has(lid):
			continue
		var res := measure(league, n, SEED)
		doc["leagues"][lid] = res
		print("== %s  (err_mult %.2f, reference %.1f pts)" % [lid, res["err_mult"], res["ref_mean"]])
		var ids: Array = res["shooters"].keys()
		ids.sort_custom(func(a, b): return float(res["shooters"][a]["ai"]) < float(res["shooters"][b]["ai"]))
		for id in ids:
			var s: Dictionary = res["shooters"][id]
			print("  %-16s acc %.2f  ai %5.1f  ref %5.1f  win %3.0f%%%s" % [id, s["acc"], s["ai"], s["ref"], 100.0 * float(s["win"]),
				"   <- pushover" if float(s["win"]) <= PUSHOVER_WIN else ""])
		print("  mean %.1f  min %.1f  max %.1f (%s)  pushovers %d   [%.0fs]" % [res["mean"], res["min"], res["max"], res["top_id"], res["pushovers"],
			(Time.get_ticks_msec() - t0) / 1000.0])
	if doc["leagues"].has("cage"):
		var cage: Dictionary = doc["leagues"]["cage"]
		for lid in ["beach", "city"]:
			if doc["leagues"].has(lid):
				var l: Dictionary = doc["leagues"][lid]
				print("ladder %s/cage: mean x%.2f  top x%.2f" % [lid, float(l["mean"]) / float(cage["mean"]), float(l["max"]) / float(cage["max"])])
	doc["generated"] = Time.get_date_string_from_system()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("WROTE %s" % OUT)
	quit(0)
