extends RefCounted
## AI DIFFICULTY (docs/LEAGUE.md → One strength, four courts): the global
## setting shifts the accuracy of every AI the player faces, on every court,
## and nothing else; NORMAL is the roster as authored.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func run(t) -> void:
	# The knob.
	t.eq(AiDifficulty.LEVELS, ["easy", "normal", "hard"], "three levels")
	t.eq(AiDifficulty.next("easy"), "normal", "easy → normal")
	t.eq(AiDifficulty.next("normal"), "hard", "normal → hard")
	t.eq(AiDifficulty.next("hard"), "easy", "hard wraps to easy")
	t.eq(AiDifficulty.normalize("HARD"), "hard", "case-insensitive")
	t.eq(AiDifficulty.normalize("pro"), "normal", "an unknown value is NORMAL")
	t.eq(AiDifficulty.normalize(null), "normal", "a missing value is NORMAL")
	t.eq(AiDifficulty.label("easy"), "EASY", "EASY label")
	t.eq(AiDifficulty.label("normal"), "NORMAL", "NORMAL label")
	t.eq(AiDifficulty.label("hard"), "HARD", "HARD label")
	t.ok(AiDifficulty.shift("easy") < AiDifficulty.shift("normal") and AiDifficulty.shift("normal") < AiDifficulty.shift("hard"), "easy < normal < hard")
	t.ok(AiDifficulty.shift("normal") > 0.0 and AiDifficulty.shift("normal") <= 0.03, "NORMAL carries a small lift over the authored roster (%.2f)" % AiDifficulty.shift("normal"))
	var r := {"accuracy": 0.5, "swishRate": 0.6, "pace": 3.4}
	var n := AiDifficulty.apply(r, "normal")
	t.close(float(n["accuracy"]), 0.5 + AiDifficulty.shift("normal"), 1e-9, "NORMAL shifts accuracy by the normal step")
	t.close(float(n["swishRate"]), 0.6, 1e-9, "…and nothing else")
	n["accuracy"] = 0.9
	t.close(float(r["accuracy"]), 0.5, 1e-9, "…and a copy, not the shooter's own dict")
	var e := AiDifficulty.apply(r, "easy")
	t.close(float(e["accuracy"]), 0.5 + AiDifficulty.shift("easy"), 1e-9, "EASY shifts accuracy by the easy step")
	t.close(float(e["pace"]), 3.4, 1e-9, "…and nothing else")
	var h := AiDifficulty.apply(r, "hard")
	t.close(float(h["accuracy"]), 0.5 + AiDifficulty.shift("hard"), 1e-9, "HARD shifts accuracy by the hard step")
	t.close(float(AiDifficulty.apply({"accuracy": 0.95}, "hard")["accuracy"]), 0.97, 1e-9, "clamped at AiMood's ceiling")
	t.close(float(AiDifficulty.apply({"accuracy": 0.08}, "easy")["accuracy"]), 0.05, 1e-9, "…and its floor")
	# The ratings type reads the shifted dict like any other.
	var ar := AiRatings.from_dict(AiDifficulty.apply(LeagueData.shooter("brickport")["ratings"], "hard"))
	t.close(ar.accuracy, 0.38 + AiDifficulty.shift("hard"), 1e-9, "a shifted roster dict parses into AiRatings")
	# The labs measure the cage where the player plays it.
	t.close(LeagueData.CAGE_HEAT_DIST, 2.9, 1e-9, "the cage heat hoop sits at 2.9 m")
	t.close(CardLab.geo_for_key("arcade").hoop_x, LeagueData.CAGE_HEAT_DIST, 1e-9, "the lab's cage geometry is the live one")
	_app_side(t)


func _app_side(t) -> void:
	var app = _app()
	if app == null:
		t.ok(true, "(no App autoload in this runner)")
		return
	t.close(float(app.ARCADE_HOOP_DIST), LeagueData.CAGE_HEAT_DIST, 1e-9, "App.ARCADE_HOOP_DIST matches LeagueData.CAGE_HEAT_DIST")
	var was: String = app.ai_difficulty
	var saved_before: Dictionary = SaveService.get_settings()
	t.eq(AiDifficulty.normalize(saved_before.get("aiDifficulty", "normal")), was, "App carries the saved setting")
	app.set_ai_difficulty("hard")
	t.eq(app.ai_difficulty, "hard", "set_ai_difficulty sets")
	t.eq(str(SaveService.get_settings().get("aiDifficulty", "")), "hard", "…and the settings part remembers")
	app.cycle_ai_difficulty()
	t.eq(app.ai_difficulty, "easy", "cycle wraps hard → easy")
	app.set_ai_difficulty("bogus")
	t.eq(app.ai_difficulty, "normal", "junk falls back to NORMAL")
	# The player's games carry the shift; the roster itself does not change.
	var raw := float(app.QUICK_OPPONENT["ratings"]["accuracy"])
	app.set_ai_difficulty("hard")
	var q: Dictionary = app.quick_heat_config("heat")
	t.close(float(q["ai"]["accuracy"]), raw + AiDifficulty.shift("hard"), 1e-9, "a quick heat's AI is shifted")
	t.close(float(app.QUICK_OPPONENT["ratings"]["accuracy"]), raw, 1e-9, "…the quick opponent's own ratings are not")
	if app.enter_league("cage"):
		var cfg: Dictionary = app.league_heat_config(app.league_doc("cage"), app.league_cfg("cage"))
		if not cfg.is_empty():
			var opp: Dictionary = cfg["opponent"]
			var authored := float(LeagueData.shooter(str(opp["id"]))["ratings"]["accuracy"])
			t.close(float(cfg["ai"]["accuracy"]), authored + AiDifficulty.shift("hard"), 1e-9, "a league heat's AI is shifted (%s)" % opp["id"])
			t.close(float(opp["ratings"]["accuracy"]), authored, 1e-9, "…the opponent card still shows the authored shooter")
	app.set_ai_difficulty("easy")
	var q2: Dictionary = app.quick_heat_config("heat")
	t.close(float(q2["ai"]["accuracy"]), raw + AiDifficulty.shift("easy"), 1e-9, "EASY the other way")
	app.set_ai_difficulty(was)
