extends SceneTree
## The economy ledger (docs/ECONOMY.md): what every mode pays the reference
## player per minute, how long every locker item takes to afford and its
## tier, the whole catalog's hours, each league's coins per heat and heats
## per card, and any rule the data breaks — the same EconomyBudget numbers
## the suite enforces. Run it after touching data/economy.json,
## data/leagues.json rewards, data/cards.json or any cosmetic's price:
##   godot --headless --path . -s tools/economy_ledger.gd


func _initialize() -> void:
	var cfg := Economy.tickets_cfg()
	var ref := EconomyBudget.ref_player()
	print("EARNING  (reference player: %.1f-min trials scoring %s, %.1f-min heats at p_win %.2f)" % [
		float(ref.get("trial_minutes", 1.5)), str(ref.get("avg_score", {})), float(ref.get("heat_minutes", 2.5)), float(ref.get("p_win", 0.5))])
	var band: Array = cfg.get("rate_band_per_min", [6, 14])
	for r in EconomyBudget.rates():
		var ok: bool = float(r["rate"]) >= float(band[0]) and float(r["rate"]) <= float(band[1])
		print("  %-14s %5.1f tickets/min  %s" % [r["mode"], r["rate"], "ok" if ok else "OUT of %s-%s" % [band[0], band[1]]])
	print("  grind rate (mean trial): %.1f tickets/min" % EconomyBudget.grind_rate())
	print("")
	print("LOCKER  (minutes of trials to afford, at the grind rate)")
	var tiers: Dictionary = cfg.get("tiers", {})
	var tier_txt := []
	for name_ in tiers:
		tier_txt.push_back("%s %s-%s min" % [name_, tiers[name_][0], tiers[name_][1]])
	print("  tiers: %s" % ", ".join(tier_txt))
	print("  %-5s %-14s %6s %8s  %s" % ["kind", "id", "price", "minutes", "tier"])
	for item in EconomyBudget.catalog():
		print("  %-5s %-14s %6d %8.0f  %s" % [item["kind"], item["id"], item["price"], item["minutes"], item["tier"] if str(item["tier"]) != "" else "NONE"])
	var hours: Array = cfg.get("catalog_hours", [15, 35])
	print("  whole catalog: %.1f hours (band %s-%s)" % [EconomyBudget.catalog_hours(), hours[0], hours[1]])
	print("")
	print("COINS  (per league; heats to afford each card at the expected coins per heat)")
	var bands: Dictionary = Economy.coins_cfg().get("heats_to_afford", {})
	for l in LeagueData.leagues():
		var r: Dictionary = l.get("rewards", {})
		print("  %-7s win %d / loss %d / title %d coins, win %d / loss %d / title %d tickets → %.1f coins + %.1f tickets a heat" % [
			l["id"], int(r.get("win_coins", 0)), int(r.get("loss_coins", 0)), int(r.get("title_coins", 0)),
			int(r.get("win_tickets", 0)), int(r.get("loss_tickets", 0)), int(r.get("title_tickets", 0)),
			Economy.expected_coins_per_heat(l), Economy.expected_tickets_per_heat(l)])
		for c in CardDefs.all():
			var n := EconomyBudget.heats_to_afford(l, int(c.get("price", 0)))
			var b: Array = bands.get(str(c.get("rarity", "")), [0, 1e9])
			print("    %-8s %-7s %4d coins  %4.1f heats  (band %s-%s) %s" % [c["id"], c.get("rarity", "?"), int(c.get("price", 0)), n, b[0], b[1],
				"ok" if n >= float(b[0]) and n <= float(b[1]) else "OUT"])
	print("")
	var problems := EconomyBudget.problems()
	var data_problems := LeagueData.validate()
	if problems.is_empty() and data_problems.is_empty():
		print("OK — every mode in band, every item tiered, every league's cards affordable.")
	else:
		for m in data_problems:
			print("DATA  " + m)
		for m in problems:
			print("RULE  " + m)
	quit(0 if problems.is_empty() and data_problems.is_empty() else 1)
