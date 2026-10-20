extends RefCounted
## The two-currency economy (docs/ECONOMY.md): trial tickets from the score,
## heat rewards per league, and the envelope — every mode's rate in band,
## every locker item in a price tier, the catalog's hours in range, every
## card affordable in a sane number of heats — with a mispriced item and a
## firehose mode caught.


func run(t) -> void:
	_trial(t)
	_heats(t)
	_envelope(t)
	_drift(t)



func _trial(t) -> void:
	var cfg: Dictionary = Economy.tickets_cfg().get("trial", {})
	var base := int(cfg.get("base", 6))
	t.eq(Economy.trial_tickets({"score": 0, "location": "cage"}, false), base, "a zero run pays the base")
	var n24 := Economy.trial_tickets({"score": 24, "location": "cage"}, false)
	t.eq(n24, int(roundf(base + float(cfg.get("per_point", 0.45)) * 24.0)), "tickets grow per point")
	t.eq(Economy.trial_tickets({"score": 24, "location": "cage"}, true), n24 + int(cfg.get("new_best", 10)), "a new best adds its bonus")
	var beach := Economy.trial_tickets({"score": 24, "location": "beach"}, false)
	t.ok(beach > n24, "the beach pays a little more for the same score (%d vs %d)" % [beach, n24])
	t.eq(Economy.trial_tickets({"score": -5, "location": "cage"}, false), base, "a negative score is treated as zero")
	t.eq(Economy.trial_tickets({"score": 0, "location": "cage"}, true), base, "a zero run gets no new-best bonus")
	t.eq(Economy.trial_tickets({}, false), base, "a bare run pays the base at the cage rate")


func _heats(t) -> void:
	var cage := LeagueData.league("cage")
	var r: Dictionary = cage["rewards"]
	var win := Economy.heat_rewards(cage, true, false)
	var loss := Economy.heat_rewards(cage, false, false)
	var title := Economy.heat_rewards(cage, true, true)
	t.eq(win.keys(), ["tickets"], "a heat pays tickets and nothing else (coins are gone, 2026-10-19)")
	t.eq(int(win["tickets"]), int(r["win_tickets"]), "win tickets from the league row")
	t.eq(int(loss["tickets"]), int(r["loss_tickets"]), "loss tickets")
	t.eq(int(title["tickets"]), int(r["win_tickets"]) + int(r["title_tickets"]), "the title adds its tickets")
	t.ok(int(win["tickets"]) > int(loss["tickets"]), "winning pays more")
	t.eq(r.keys(), ["win_tickets", "loss_tickets", "title_tickets"], "the league row carries the three ticket keys only")
	var beach := LeagueData.league("beach")
	t.ok(Economy.expected_tickets_per_heat(beach) > Economy.expected_tickets_per_heat(cage), "the harder league pays more tickets a heat")
	var city := LeagueData.league("city")
	t.ok(Economy.expected_tickets_per_heat(city) > Economy.expected_tickets_per_heat(beach), "the city pays more a heat than the beach")
	t.ok(Economy.trial_tickets({"score": 24, "location": "city"}, false) > Economy.trial_tickets({"score": 24, "location": "beach"}, false), "and its trials pay more for the same score")
	var park_pay := Economy.trial_tickets({"score": 24, "location": "park"}, false)
	t.ok(park_pay > Economy.trial_tickets({"score": 24, "location": "beach"}, false) and park_pay < Economy.trial_tickets({"score": 24, "location": "city"}, false), "the park's trials pay between the beach's and the city's")
	var park := LeagueData.league("park")
	t.ok(Economy.expected_tickets_per_heat(park) > Economy.expected_tickets_per_heat(beach) and Economy.expected_tickets_per_heat(park) < Economy.expected_tickets_per_heat(city), "the park league's tickets sit between")
	t.close(Economy.expected_tickets_per_heat(cage), 0.5 * int(r["win_tickets"]) + 0.5 * int(r["loss_tickets"]), 1e-9, "expected tickets at a coin flip")
	t.close(Economy.expected_tickets_per_heat(cage), 26.0, 1e-9, "the cage heat: 36 / 16 → 26 a heat (2026-10-19)")
	t.eq(Economy.trial_tickets({"score": 24, "location": "cage"}, false), 15, "a 24-point cage trial pays 15 (base 5 + 0.4 a point)")


func _envelope(t) -> void:
	var band: Array = Economy.tickets_cfg().get("rate_band_per_min", [6, 14])
	var rates := EconomyBudget.rates()
	t.ok(rates.size() >= 4, "two trial rates and two heat rates (%d)" % rates.size())
	for r in rates:
		t.ok(float(r["rate"]) >= float(band[0]) and float(r["rate"]) <= float(band[1]), "%s pays inside the band (%.1f/min)" % [r["mode"], r["rate"]])
	t.ok(EconomyBudget.heat_rate(LeagueData.league("cage")) > EconomyBudget.trial_rate("cage"), "a cage heat out-earns a cage trial a minute (one currency: heats carry the wallet, trials a bit less)")
	var catalog := EconomyBudget.catalog()
	t.ok(catalog.size() >= 2, "the priced hoops are in the catalog (%d)" % catalog.size())
	for item in catalog:
		t.eq(item["kind"], "hoop", "%s is a hoop: balls and nets are PEGGY prizes, never priced" % item["id"])
		t.ok(str(item["tier"]) != "", "%s %s (%d) sits in a tier (%.0f min)" % [item["kind"], item["id"], item["price"], item["minutes"]])
	for n in CosmeticLibrary.nets():
		t.eq(n.price_coins, 0, "net %s is a PEGGY prize, priced 0" % n.id)
	var roster := EconomyBudget.peggy_roster()
	var nets_in := 0
	for e in roster:
		if PeggyPrizes.kind_of(e) == "net":
			nets_in += 1
	t.eq(nets_in, CosmeticLibrary.nets().size(), "every net is on PEGGY's roster")
	t.eq(EconomyBudget.peggy_start_owned().size(), 3, "a fresh save owns the starter ball and the stock pair")
	# PEGGY (docs/LOCKER.md): a drop is an entry purchase, the machine pays
	# the whole roster out, barely wastes a drop, and the roster's hours are
	# the bulk of the catalog.
	t.eq(EconomyBudget.tier_of(PeggyPrizes.DROP_COST), "entry", "a drop is an entry purchase")
	var pt := EconomyBudget.peggy_tickets()
	var to_win := EconomyBudget.peggy_to_win()
	t.ok(pt >= to_win * PeggyPrizes.DROP_COST, "winning %d prizes costs at least %d drops (%.0f tickets)" % [to_win, to_win, pt])
	t.ok(EconomyBudget.peggy_per_prize() <= PeggyPrizes.DROP_COST * 1.35, "a prize costs about a drop (%.0f tickets)" % EconomyBudget.peggy_per_prize())
	t.ok(EconomyBudget.peggy_hours() > EconomyBudget.catalog_hours() * 0.5, "the roster is most of the catalog (%.1f of %.1f h)" % [EconomyBudget.peggy_hours(), EconomyBudget.catalog_hours()])
	var hours: Array = Economy.tickets_cfg().get("catalog_hours", [15, 35])
	var h := EconomyBudget.catalog_hours()
	t.ok(h >= float(hours[0]) and h <= float(hours[1]), "the whole catalog takes %.1f hours, inside %s-%s" % [h, hours[0], hours[1]])
	t.ok(EconomyBudget.minutes_to_afford(250) < EconomyBudget.minutes_to_afford(1500), "pricier takes longer")
	for l in LeagueData.leagues():
		for c in CardDefs.all():
			var n := EconomyBudget.heats_to_afford(l, int(c["price"]))
			t.ok(n >= 1.0 and n <= 14.0, "%s: %s costs %.1f heats" % [l["id"], c["id"], n])
	var problems := EconomyBudget.problems()
	t.eq(problems, PackedStringArray(), "the shipped economy is inside its envelope: %s" % str(problems))


func _drift(t) -> void:
	# A firehose mode and a dead one both fall outside the rate band.
	var band: Array = Economy.tickets_cfg().get("rate_band_per_min", [6, 14])
	var hot := LeagueData.league("cage").duplicate(true)
	hot["rewards"]["win_tickets"] = 400
	hot["rewards"]["loss_tickets"] = 300
	t.ok(EconomyBudget.heat_rate(hot) > float(band[1]), "a firehose league is outside the band (%.1f)" % EconomyBudget.heat_rate(hot))
	var dead := LeagueData.league("cage").duplicate(true)
	dead["rewards"]["win_tickets"] = 1
	dead["rewards"]["loss_tickets"] = 0
	t.ok(EconomyBudget.heat_rate(dead) < float(band[0]), "a dead league is outside the band")
	# A mispriced item lands in no tier / past the grail.
	t.eq(EconomyBudget.tier_of(5000), "", "5000 tickets is in no tier")
	t.eq(EconomyBudget.tier_of(250), "entry", "250 is entry")
	t.eq(EconomyBudget.tier_of(1500), "grail", "1500 is grail")
	# An overpriced card takes too many heats.
	t.ok(EconomyBudget.heats_to_afford(LeagueData.league("cage"), 900) > 14.0, "a 900-ticket card is out of reach")
