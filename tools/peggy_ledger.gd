extends SceneTree
## PEGGY's numbers (docs/LOCKER.md), printed: the board's constants, the slot
## odds along the rail, the rarity odds per level at the centre and at the
## end-stop, the expected tickets to win the whole roster, and the roster by
## rarity. Exits 1 when the odds leave their bands or the economy rule
## (EconomyBudget.problems) is broken.
##   godot --headless --path . -s tools/peggy_ledger.gd

const N := 1500


func _initialize() -> void:
	var bad := 0
	print("BOARD  rows %d, pegs r %.2f, bumpers r %.2f, puck r %.2f, e_peg %.2f, e_wall %.2f, jitter ±%.0f°, rail ±%.1f" % [
		PeggyBoard.ROWS, PeggyBoard.PEG_R, PeggyBoard.BUMP_R, PeggyBoard.PUCK_R, PeggyBoard.E_PEG,
		PeggyBoard.E_WALL, PeggyBoard.JITTER_DEG, PeggyBoard.AIM_MAX])
	print("")
	print("ODDS  (%d drops per aim)" % N)
	print("  %-6s %6s %6s %6s %6s %6s %6s %6s" % ["aim", "s0", "s1", "s2", "s3", "s4", "s5", "s6"])
	var centre := PeggyBoard.odds(0.0, N)
	var end := PeggyBoard.odds(-PeggyBoard.AIM_MAX, N)
	var aims := [-PeggyBoard.AIM_MAX, -PeggyBoard.AIM_MAX * 0.5, 0.0, PeggyBoard.AIM_MAX * 0.5, PeggyBoard.AIM_MAX]
	for a in aims:
		var p := centre if a == 0.0 else (end if a == -PeggyBoard.AIM_MAX else PeggyBoard.odds(a, N))
		var cells := []
		for v in p:
			cells.push_back("%5.1f%%" % (v * 100.0))
		print("  %-6.2f %s" % [a, " ".join(cells)])
	# Bands: the centre slot is the likeliest, an edge from the centre is
	# occasional, and the end-stop makes its edge reachable but not sure.
	if centre[3] < 0.18 or centre[3] > 0.40:
		print("RULE  centre slot from the centre is %.1f%%, outside 18-40" % (centre[3] * 100.0))
		bad += 1
	for s in [0, 6]:
		if centre[s] > 0.09:
			print("RULE  edge slot %d from the centre is %.1f%%, above 9" % [s, centre[s] * 100.0])
			bad += 1
	if end[0] < 0.08 or end[0] > 0.30:
		print("RULE  near edge from the end-stop is %.1f%%, outside 8-30" % (end[0] * 100.0))
		bad += 1
	print("")
	print("RARITY  (what a drop pays, by level)")
	for level in [1, 3, 5]:
		var lay := PeggyPrizes.layout(level)
		var c := PeggyBoard.rarity_odds_from(centre, lay)
		var e := PeggyBoard.rarity_odds_from(end, lay)
		var parts := []
		for r in PeggyPrizes.visible_rarities(level):
			parts.push_back("%s %4.1f%% / %4.1f%%" % [r, float(c.get(r, 0.0)) * 100.0, float(e.get(r, 0.0)) * 100.0])
		print("  lvl %d  %s   (centre / end-stop)" % [level, ",  ".join(parts)])
	print("")
	var roster := EconomyBudget.peggy_roster()
	var per := {}
	for b in roster:
		per[b["rarity"]] = int(per.get(b["rarity"], 0)) + 1
	print("ROSTER  %d balls: %s" % [roster.size(), str(per)])
	print("  a drop: %d tickets = %.0f min of trials (tier %s)" % [PeggyPrizes.DROP_COST,
		EconomyBudget.minutes_to_afford(PeggyPrizes.DROP_COST), EconomyBudget.tier_of(PeggyPrizes.DROP_COST)])
	print("  whole roster: expected %.0f tickets, %.0f a ball, %.1f hours; catalog with hoops %.1f hours" % [
		EconomyBudget.peggy_tickets(), EconomyBudget.peggy_per_ball(), EconomyBudget.peggy_hours(), EconomyBudget.catalog_hours()])
	for lvl in [1, 3]:
		var owned := ["classic"]
		var cost := PeggyPrizes.expected_tickets_to_complete(centre, roster, owned, lvl, 60)
		var n := 0
		for b in roster:
			if lvl >= PeggyPrizes.rarity_level(str(b["rarity"])) and not owned.has(b["id"]):
				n += 1
		print("  at level %d: %d balls reachable, expected %.0f tickets" % [lvl, n, cost])
	var problems := EconomyBudget.problems()
	for m in problems:
		print("RULE  " + m)
	bad += problems.size()
	print("")
	print("OK — odds in band, roster payable." if bad == 0 else "%d problem(s)" % bad)
	quit(0 if bad == 0 else 1)
