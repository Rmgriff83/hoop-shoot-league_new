class_name ProgressionBudget
extends RefCounted
## The pacing envelope (docs/PROGRESSION.md): the archetype seasons in
## data/progression.json run through Progression.match_xp — a terrible,
## an awful, a decent and a strong season — and the levels each pays, held
## inside its band. tools/progression_ledger.gd prints it, the suite
## enforces it (tests/test_progression.gd).


## One archetype's season in a league: 14 regular games with its win rate
## and stats, plus its playoff games. Returns {id, xp, levels, band, ok}.
static func season(arch: Dictionary, league: Dictionary) -> Dictionary:
	var games := int(arch.get("games", 14))
	var wins := int(arch.get("wins", 7))
	var margin_wins := int(arch.get("margin_wins", 0))
	var state := Progression.empty_state()
	var played := 0
	for g in games + int(arch.get("playoff_games", 0)):
		var playoff := g >= games
		var won := (g * wins) / games < ((g + 1) * wins) / games if not playoff else (g - games) % 2 == 0
		var wide := won and margin_wins > 0
		if wide:
			margin_wins -= 1
		var result := {"won": won, "player_score": 30 if not wide else 40, "ai_score": 25 if won else 33, "ot": 0,
			"league": {"playoff": playoff},
			"sides": {"player": {"swishes": int(arch.get("swishes", 0)), "bestStreak": int(arch.get("streak", 0))}, "ai": {}}}
		Progression.apply_match(state, result, league, 1)
		played += 1
	var xp := int(state["xp"])
	var levels := float(xp) / float(Progression.xp_per_level())
	var band: Array = arch.get("levels", [0.0, 99.0])
	return {"id": str(arch.get("id", "?")), "xp": xp, "levels": levels, "band": band, "games": played,
		"ok": levels >= float(band[0]) and levels <= float(band[1])}


static func seasons(league: Dictionary) -> Array:
	var out := []
	for arch in Progression.doc().get("archetypes", []):
		out.push_back(season(arch, league))
	return out


## Every rule the shipped data must satisfy; empty = in-envelope.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for p in Progression.validate():
		out.push_back(p)
	for l in LeagueData.leagues():
		for row in seasons(l):
			if not bool(row["ok"]):
				out.push_back("%s: a %s season pays %.2f levels, outside %s-%s" % [l["id"], row["id"], row["levels"], row["band"][0], row["band"][1]])
		# The title always reaches the cap from anywhere in the band.
		var st := Progression.empty_state()
		st["xp"] = (Progression.min_level(l) - Progression.start_level()) * Progression.xp_per_level()
		Progression.apply_title(st, l)
		if Progression.level_for(int(st["xp"])) != Progression.cap_level(l):
			out.push_back("%s: the title does not reach the cap" % l["id"])
	return out
