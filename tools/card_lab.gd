extends SceneTree
## Card power lab: measures every card in every league on the real engine
## (CardLab) and writes assets/cards/card_power.json, the file CardDefs reads
## for power → rarity band / price and CardBudget reads for the area envelope.
##   godot --headless --path . -s tools/card_lab.gd              (all cards)
##   godot --headless --path . -s tools/card_lab.gd -- ice       (one card, others kept)
##   godot --headless --path . -s tools/card_lab.gd -- --n=60    (quick look)
## Deterministic (seeded DetRng): the same n and seed rewrite the same file.
## About 0.4 s a heat: n × leagues × (cards + 1) heats. See docs/CARDS.md.

const N := 500
const SEED := 4242
const OUT := "res://assets/cards/card_power.json"


func _initialize() -> void:
	var n := N
	var only: Array[String] = []
	for a in OS.get_cmdline_user_args():
		var arg := str(a)
		if arg.begins_with("--n="):
			n = int(arg.trim_prefix("--n="))
		else:
			only.push_back(arg)
	var doc := CardDefs.power_doc()
	if doc.is_empty() or int(doc.get("n", 0)) != n or int(doc.get("seed", 0)) != SEED:
		doc = {"n": n, "seed": SEED, "generated": "", "cards": {}, "detail": {}}
	var ids: Array = []
	for card in CardDefs.all():
		var id := str(card["id"])
		if only.is_empty() or only.has(id):
			ids.push_back(id)
	var t0 := Time.get_ticks_msec()
	for league in LeagueData.leagues():
		var lid := str(league["id"])
		var res := CardLab.measure_all(ids, league, n, SEED)
		for id in ids:
			var m: Dictionary = res[id]
			if not doc["cards"].has(id):
				doc["cards"][id] = {}
				doc["detail"][id] = {}
			doc["cards"][id][lid] = snappedf(float(m["power"]), 0.01)
			doc["detail"][id][lid] = {"se": snappedf(float(m["se"]), 0.001), "with": snappedf(float(m["with"]), 0.01),
				"without": snappedf(float(m["without"]), 0.01), "played": snappedf(float(m["played"]), 0.001)}
			print("  %-8s %-6s power %+.2f ± %.2f  (margin %+.2f vs %+.2f, played %.0f%%, n %d, %.0fs)" % [
				id, lid, m["power"], m["se"], m["with"], m["without"], 100.0 * float(m["played"]), n, (Time.get_ticks_msec() - t0) / 1000.0])
	doc["generated"] = Time.get_date_string_from_system()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("WROTE %s" % OUT)
	quit(0)
