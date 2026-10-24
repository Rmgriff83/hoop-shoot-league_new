extends SceneTree
## Online drops ledger (docs/BACKEND.md → Ranked → Stage B): the numbers
## data/online_drops.json implies for the reference player — the derived
## meter size, points a week, cards in against cards played per ranked match
## (banded), the rarity odds per tier, the login schedule, the milestone
## list, and what ranked play pays a minute. Exits 1 on a band break.
##   godot --headless --path . -s tools/online_ledger.gd


func _initialize() -> void:
	var d := OnlineDrops.derive()
	var r := OnlineDrops.reference_player()
	var m := OnlineDrops.meter_cfg()
	print("DROP METER  (data/online_drops.json: target %d cards a week)" % OnlineDrops.weekly_target())
	print("  reference: %d ranked a week at p_win %.2f, %.0f%% of losses close, %d login days, %.1f cards played a match" % [
		int(r.get("ranked_per_week", 0)), float(r.get("win_rate", 0)), 100.0 * float(r.get("close_loss_share", 0)), int(r.get("login_days_per_week", 0)), float(r.get("cards_played_per_match", 0))])
	print("  points: win %d · close loss %d · loss %d · first win of the day %d" % [int(m.get("win", 0)), int(m.get("close_loss", 0)), int(m.get("loss", 0)), int(m.get("first_win_day", 0))])
	print("  %.2f points a match, %.2f first-win days → %.1f points a week; %.2f streak Ice a week" % [d["points_per_match"], d["first_win_days"], d["points_per_week"], d["streak_cards_per_week"]])
	print("  METER SIZE %d  → %.2f cards in per ranked match vs %.1f played: ratio %.3f (band %s)" % [
		int(d["meter_size"]), d["cards_in_per_match"], float(r.get("cards_played_per_match", 1.5)), d["ratio"], str(OnlineDrops.doc().get("ratio_band", []))])
	print("RARITY ODDS  (by tier, at levels 1 / 3 / 5; the pool is what the level and the card's minimum tier allow)")
	for t in RankedRules.tiers():
		var id := str(t["id"])
		var cells := []
		for lv in [1, 3, 5]:
			cells.push_back("L%d %s" % [lv, OnlineDrops.odds_text(OnlineDrops.odds_for(id, lv))])
		print("  %-8s %s" % [id, "  |  ".join(cells)])
	var lg := OnlineDrops.logins_cfg()
	var sched := []
	for e in lg.get("schedule", []):
		sched.push_back("day %d %s" % [int(e[0]), str(e[1])])
	print("LOGINS  first login → %s; %s; welcome back after %d days away → %s" % [str(lg.get("first", "")), ", ".join(sched), int(lg.get("welcome_back_days", 7)), str(lg.get("welcome_back", ""))])
	print("STREAK  the %dth straight played loss → %s, at most %d a day; insurance from %d straight losses; same opponent pays %d games a day" % [
		int(OnlineDrops.streak_cfg().get("losses", 4)), str(OnlineDrops.streak_cfg().get("card", "ice")), int(OnlineDrops.streak_cfg().get("per_day", 1)),
		int(OnlineDrops.insurance_cfg().get("losses", 3)), OnlineDrops.same_opponent_cap()])
	print("MILESTONES  %d keys: %s" % [OnlineDrops.all_milestone_keys().size(), ", ".join(OnlineDrops.all_milestone_keys())])
	print("TICKETS  (EconomyBudget.rates, band %s a minute)" % str(Economy.tickets_cfg().get("rate_band_per_min", [])))
	var problems := PackedStringArray()
	var band: Array = Economy.tickets_cfg().get("rate_band_per_min", [6, 14])
	for row in EconomyBudget.rates():
		if str(row["mode"]) in ["ranked", "shoot around"]:
			var ok := float(row["rate"]) >= float(band[0]) and float(row["rate"]) <= float(band[1])
			print("  %-14s %5.1f tickets/min  %s" % [row["mode"], row["rate"], "ok" if ok else "OUT OF BAND"])
			if not ok:
				problems.push_back("%s pays %.1f a minute, outside %s" % [row["mode"], row["rate"], str(band)])
	var rb: Array = OnlineDrops.doc().get("ratio_band", [0.0, 1.0])
	if float(d["ratio"]) < float(rb[0]) or float(d["ratio"]) > float(rb[1]):
		problems.push_back("cards in / played %.3f is outside %s" % [d["ratio"], str(rb)])
	if problems.is_empty():
		print("OK — the meter lands the weekly target, the ratio and the ticket rates sit in band.")
	else:
		for p in problems:
			print("RULE  %s" % p)
	quit(0 if problems.is_empty() else 1)
