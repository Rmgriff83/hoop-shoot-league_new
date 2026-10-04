extends RefCounted
## The league difficulty ladder (docs/LEAGUE.md → Difficulty ladder,
## tools/league_lab.gd → assets/ai/league_ladder.json): leagues get harder by
## having fewer pushovers, not stronger stars. The lab measures every roster
## shooter against one reference bot in points; this pins what it found and
## the shape of the data behind it.


func run(t) -> void:
	# The data: bands overlap (the floor rises, the ceiling barely), and no
	# hidden boost past the cage.
	var bands := {}
	for league in LeagueData.leagues():
		var lid := str(league["id"])
		var accs: Array[float] = []
		for id in league["roster"]:
			accs.push_back(LeagueData.ratings_of(str(id)).accuracy)
		bands[lid] = {"min": accs.min(), "max": accs.max(), "err": float(league.get("err_mult", 1.0))}
	t.ok(bands["beach"]["min"] < bands["cage"]["max"] and bands["city"]["min"] < bands["beach"]["max"], "rating bands overlap league to league")
	t.ok(bands["city"]["max"] <= 0.70 and bands["beach"]["max"] <= 0.66, "no league fields a star above 0.70 (city %.2f, beach %.2f)" % [bands["city"]["max"], bands["beach"]["max"]])
	t.ok(bands["cage"]["min"] < 0.45 and bands["beach"]["min"] <= 0.52 and bands["city"]["min"] >= 0.53, "floors rise: cage %.2f, beach %.2f, city %.2f" % [bands["cage"]["min"], bands["beach"]["min"], bands["city"]["min"]])
	t.ok(bands["cage"]["err"] == 1.0 and bands["beach"]["err"] == 1.0 and bands["city"]["err"] == 1.0, "no hidden err_mult ramp: 1.0 everywhere")
	# The measurement.
	var path := "res://assets/ai/league_ladder.json"
	t.ok(FileAccess.file_exists(path), "the lab's ladder file ships")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	t.ok(doc is Dictionary and doc.has("leagues"), "…and parses")
	if not (doc is Dictionary and doc.has("leagues")):
		return
	var L: Dictionary = doc["leagues"]
	for lid in ["cage", "beach", "city"]:
		t.ok(L.has(lid) and L[lid]["shooters"].size() == 7, "%s measured, seven shooters" % lid)
	t.eq(int(L["cage"]["pushovers"]), 3, "the cage has three pushovers")
	t.eq(int(L["beach"]["pushovers"]), 1, "the beach one")
	t.eq(int(L["city"]["pushovers"]), 0, "the city none")
	var cage_mean := float(L["cage"]["mean"])
	var beach_r := float(L["beach"]["mean"]) / cage_mean
	var city_r := float(L["city"]["mean"]) / cage_mean
	t.ok(beach_r > 1.0 and beach_r < 1.3, "beach AIs score a little more than the cage's (x%.2f)" % beach_r)
	# The mean ratio is mostly the pushover count (three in the cage drag its
	# mean down); the fair comparison is the shooters who are not pushovers.
	t.ok(city_r > beach_r and city_r < 1.6, "the city a little more again (x%.2f)" % city_r)
	var cage_np := _non_pushover_mean(L["cage"], float(doc.get("pushover_win", 0.25)))
	var city_np := _non_pushover_mean(L["city"], float(doc.get("pushover_win", 0.25)))
	t.ok(city_np / cage_np < 1.4, "the city's regulars score under 1.4x the cage's regulars (x%.2f)" % (city_np / cage_np))
	var top_r := float(L["city"]["max"]) / float(L["cage"]["max"])
	t.ok(top_r < 1.35, "the city's star is not a wall (x%.2f of the cage's)" % top_r)
	for lid in ["beach", "city"]:
		for id in L[lid]["shooters"]:
			t.ok(float(L[lid]["shooters"][id]["win"]) < 0.95, "%s/%s is beatable (wins %.0f%%)" % [lid, id, 100.0 * float(L[lid]["shooters"][id]["win"])])


static func _non_pushover_mean(league: Dictionary, win_floor: float) -> float:
	var sum := 0.0
	var n := 0
	for id in league["shooters"]:
		var sh: Dictionary = league["shooters"][id]
		if float(sh["win"]) > win_floor:
			sum += float(sh["ai"])
			n += 1
	return sum / maxi(1, n)
