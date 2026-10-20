extends RefCounted
## The league difficulty ladder (docs/LEAGUE.md → One strength, four courts,
## tools/league_lab.gd → assets/ai/league_ladder.json): since 2026-10-19 every
## league's roster measures the same as the arcade cage's — the courts carry
## the progression, the AI does not. The lab plays every roster shooter
## against one reference bot in points; this pins what it found and the shape
## of the data behind it.

## A league's mean may sit this far off the cage's.
const MEAN_TOL := 0.06
## Pushovers (the reference wins ≥ 75 %) per league: a soft bottom, never the
## whole roster. The count runs higher off the cage because the reference bot
## scores more on those hoops; the AI's points are what the ladder pins.
const PUSHOVERS_MIN := 2
const PUSHOVERS_MAX := 5


func run(t) -> void:
	# The data: no roster fields a star past the cage's band, no hidden boost.
	for league in LeagueData.leagues():
		var lid := str(league["id"])
		var accs: Array[float] = []
		for id in league["roster"]:
			accs.push_back(LeagueData.ratings_of(str(id)).accuracy)
		t.ok(accs.max() <= 0.58, "%s fields no star above 0.58 (%.2f)" % [lid, accs.max()])
		t.ok(accs.min() <= 0.46, "%s has a soft floor (%.2f)" % [lid, accs.min()])
		t.ok(float(league.get("err_mult", 1.0)) == 1.0, "no hidden err_mult ramp: %s 1.0" % lid)
	# The measurement.
	var path := "res://assets/ai/league_ladder.json"
	t.ok(FileAccess.file_exists(path), "the lab's ladder file ships")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	t.ok(doc is Dictionary and doc.has("leagues"), "…and parses")
	if not (doc is Dictionary and doc.has("leagues")):
		return
	var L: Dictionary = doc["leagues"]
	for lid in ["cage", "beach", "park", "city"]:
		t.ok(L.has(lid) and L[lid]["shooters"].size() == 7, "%s measured, seven shooters" % lid)
	var cage_mean := float(L["cage"]["mean"])
	var cage_top := float(L["cage"]["max"])
	for lid in ["beach", "park", "city"]:
		var r := float(L[lid]["mean"]) / cage_mean
		t.ok(r >= 1.0 - MEAN_TOL and r <= 1.0 + MEAN_TOL, "%s AIs score what the cage's do (x%.2f)" % [lid, r])
		var top_r := float(L[lid]["max"]) / cage_top
		t.ok(top_r < 1.15, "%s's star is no wall (x%.2f of the cage's)" % [lid, top_r])
	for lid in ["cage", "beach", "park", "city"]:
		var p := int(L[lid]["pushovers"])
		t.ok(p >= PUSHOVERS_MIN and p <= PUSHOVERS_MAX, "%s has %d–%d pushovers (%d)" % [lid, PUSHOVERS_MIN, PUSHOVERS_MAX, p])
		for id in L[lid]["shooters"]:
			t.ok(float(L[lid]["shooters"][id]["win"]) < 0.9, "%s/%s is beatable (wins %.0f%%)" % [lid, id, 100.0 * float(L[lid]["shooters"][id]["win"])])
