extends SceneTree
## The card ledger: every card's measured power, band and price against the
## scale, every league's AI allowance against the player's expected income,
## and any rule the data breaks — the same CardBudget numbers the suite
## enforces. Run it after touching data/cards.json, data/leagues.json or the
## lab output:  godot --headless --path . -s tools/card_ledger.gd
## See docs/CARDS.md.


func _initialize() -> void:
	var leagues := LeagueData.leagues()
	var lids: Array = leagues.map(func(l): return str(l["id"]))
	var pdoc := CardDefs.power_doc()
	print("CARD POWER  (assets/cards/card_power.json: n %d, seed %d, %s)" % [int(pdoc.get("n", 0)), int(pdoc.get("seed", 0)), pdoc.get("generated", "unmeasured")])
	var bands := CardDefs.rarity_bands()
	print("  %-8s %-7s %5s  %-30s %6s  %-5s %s" % ["card", "rarity", "price", "power " + "/".join(lids), "mean", "band", "price curve"])
	for c in CardDefs.all():
		var id := str(c["id"])
		var per := []
		for lid in lids:
			var d: Dictionary = pdoc.get("detail", {}).get(id, {}).get(str(lid), {})
			per.push_back("%+.2f±%.2f" % [CardDefs.power(id, str(lid)), float(d.get("se", 0.0))])
		var pm := CardDefs.power_mean(id)
		var band := CardDefs.rarity_for(pm)
		var want := CardDefs.price_for(pm)
		# Mean of independent per-league means: se_mean = √Σse² / L.
		var se_mean := 0.0
		for lid in lids:
			var e := float(pdoc.get("detail", {}).get(id, {}).get(str(lid), {}).get("se", 0.0))
			se_mean += e * e
		se_mean = sqrt(se_mean) / maxf(lids.size(), 1.0)
		var edge := ""
		for r in bands:
			for b in [float(bands[r][0]), float(bands[r][1])]:
				if b > 0.0 and b < 90.0 and absf(pm - b) < 2.0 * se_mean:
					edge = "  NEAR EDGE %.2f (±%.2f): raise the lab's n before trusting the band" % [b, se_mean]
		print("  %-8s %-7s %5d  %-30s %+6.2f  %-5s %s%s" % [id, c.get("rarity", "?"), int(c.get("price", 0)), " / ".join(per), pm,
			"ok" if band == str(c.get("rarity", "")) else band.to_upper(),
			("ok (%d)" % want) if CardDefs.price_ok(int(c.get("price", 0)), pm) else "WANT %d" % want, edge])
	var band_txt := []
	for r in bands:
		band_txt.push_back("%s %.1f–%.1f" % [r, float(bands[r][0]), float(bands[r][1])])
	var curve := CardDefs.price_curve()
	print("  scale: %s; price = round10(%.0f · power^%.2f) ±%.0f%%" % [", ".join(band_txt), float(curve["k"]), float(curve["exp"]), 100.0 * float(curve["tolerance"])])
	print("")
	print("AREA ENVELOPE  (per season; player income at p_win %.2f, %.0f playoff games, title p %.2f)" % [CardBudget.P_WIN, CardBudget.PLAYOFF_GAMES, CardBudget.P_TITLE])
	print("  %-7s %6s %8s %8s %8s | %6s %8s %8s %8s | %6s %6s %s" % ["league", "allow", "authored", "dealt", "AI pwr", "drops", "coins", "bought", "PLR pwr", "ratio", "target", ""])
	for l in CardBudget.unlock_chain(leagues):
		var a := CardBudget.ai_budget(l)
		var p := CardBudget.player_income(l)
		var ratio := CardBudget.parity(l)
		var target := float(l.get("card_parity", 0.0))
		var ok := absf(ratio - target) <= CardBudget.PARITY_TOL * target
		print("  %-7s %6d %8s %8s %8.2f | %6.2f %8.0f %8.2f %8.2f | %6.2f %6.2f %s" % [l["id"], int(a["per_season"]),
			"%d (%.1f)" % [int(a["authored_n"]), float(a["authored_power"])], "%d (%.1f)" % [int(a["dealt_n"]), float(a["dealt_power"])],
			float(a["power"]), float(p["drops"]), float(p["coins"]), float(p["bought"]), float(p["power"]), ratio, target, "ok" if ok else "OUT"])
	print("")
	print("SIGNATURE HANDS")
	for l in leagues:
		var parts := []
		for sid in l.get("ai_cards", {}):
			parts.push_back("%s %s" % [sid, str(l["ai_cards"][sid])])
		print("  %-7s cap %d/shooter, pool %s: %s" % [l["id"], int(l.get("ai_hand_max", 0)), str(l.get("ai_pool", [])), "; ".join(parts) if not parts.is_empty() else "none"])
	print("")
	var problems := CardBudget.problems()
	var data_problems := LeagueData.validate() + CardDefs.validate()
	if problems.is_empty() and data_problems.is_empty():
		print("OK — every card on the scale, every league inside its envelope.")
	else:
		for m in data_problems:
			print("DATA  " + m)
		for m in problems:
			print("RULE  " + m)
	quit(0 if problems.is_empty() and data_problems.is_empty() else 1)
