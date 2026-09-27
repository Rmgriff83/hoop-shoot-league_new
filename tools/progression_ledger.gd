extends SceneTree
## The progression ledger (docs/PROGRESSION.md): the level bands, what each
## archetype season pays in every league, the card levels, and any rule the
## data breaks — the same ProgressionBudget numbers the suite enforces. Run
## it after touching data/progression.json, the `levels` / `unlock` /
## `xp_mult` rows in data/leagues.json, or a card's `level`:
##   godot --headless --path . -s tools/progression_ledger.gd


func _initialize() -> void:
	var d := Progression.doc()
	print("LEVELS  (%d XP a level, start at %d; season soft cap %d, over-cap rate %.2f)" % [
		Progression.xp_per_level(), Progression.start_level(), int(d.get("season_soft_cap", 100)), float(d.get("over_cap_rate", 0.3))])
	var m: Dictionary = d.get("match", {})
	print("  a match: win %s / loss %s, %.1f a swish, streak %s, wide win %s, OT win %s, playoffs x%.2f" % [
		m.get("win", 9), m.get("loss", 2), float(m.get("per_swish", 0.4)), str(m.get("streak", [])), str(m.get("margin", [])), m.get("ot_win", 1), float(m.get("playoff_mult", 1.5))])
	print("")
	print("LEAGUES")
	for l in LeagueData.leagues():
		var rule: Variant = l.get("unlock", null)
		print("  %-7s levels %d -> %d  unlock %s  xp x%.2f  cap at %d XP" % [
			l["id"], Progression.min_level(l), Progression.cap_level(l), ("level %d" % int(rule["level"])) if rule is Dictionary else "open",
			float(l.get("xp_mult", 1.0)), Progression.cap_xp(l)])
		for row in ProgressionBudget.seasons(l):
			print("    %-9s season: %3d XP = %.2f levels  (band %.2f-%.2f)  %s" % [row["id"], row["xp"], row["levels"], row["band"][0], row["band"][1], "ok" if row["ok"] else "OUT"])
	print("")
	print("CARDS")
	for c in CardDefs.all():
		print("  %-7s %-12s level %d" % [c["id"], c["name"], Progression.card_level(c)])
	print("")
	var problems := ProgressionBudget.problems()
	for p in problems:
		print("RULE  " + p)
	print("in envelope" if problems.is_empty() else "%d problem(s)" % problems.size())
	quit(0 if problems.is_empty() else 1)
