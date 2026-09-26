extends RefCounted
## Card governance (docs/CARDS.md): every card carries a measured power, its
## rarity and price sit on the scale that power puts it on, every league's AI
## allowance sits inside its declared parity with the player's income, parity
## never falls along the unlock chain, and the per-season dealer respects its
## allowance and cap. Reads assets/cards/card_power.json (tools/card_lab.gd);
## never runs the lab.


func run(t) -> void:
	_scale(t)
	_envelope(t)
	_dealer(t)


func _scale(t) -> void:
	t.ok(FileAccess.file_exists(CardDefs.POWER_PATH), "card_power.json is generated and committed (tools/card_lab.gd)")
	for c in CardDefs.all():
		t.ok(CardDefs.has_power(str(c["id"])), "%s has a measured power in every league" % c["id"])
		for l in LeagueData.leagues():
			t.ok(CardDefs.power_doc().get("cards", {}).get(str(c["id"]), {}).has(str(l["id"])),
				"%s measured in %s" % [c["id"], l["id"]])
	var bands := CardDefs.rarity_bands()
	t.ok(bands.has("common") and bands.has("rare") and bands.has("epic"), "three rarity bands")
	t.eq(CardDefs.rarity_for(float(bands["common"][0])), "common", "band floor is inclusive")
	t.eq(CardDefs.rarity_for(float(bands["rare"][0])), "rare", "rare from its floor")
	t.eq(CardDefs.rarity_for(float(bands["epic"][0]) + 5.0), "epic", "far above → epic")
	t.eq(CardDefs.rarity_for(-3.0), "common", "below every band → the lowest")
	t.eq(CardDefs.price_for(0.0), 0, "no power, no price")
	t.ok(CardDefs.price_for(3.0) > CardDefs.price_for(2.0) and CardDefs.price_for(2.0) > CardDefs.price_for(1.0), "price rises with power")
	t.eq(CardDefs.price_for(2.0) % 10, 0, "prices are round tens")
	t.ok(CardDefs.price_ok(CardDefs.price_for(2.0), 2.0), "the curve's own price passes")
	t.ok(not CardDefs.price_ok(CardDefs.price_for(2.0) * 2, 2.0), "double the curve's price fails")
	# The shipped data sits on its scale and inside its envelope. This is the
	# assertion that fails when a new card or league bends the graph.
	var problems := CardBudget.problems()
	t.eq(problems, PackedStringArray(), "card data inside its envelope: %s" % str(problems))


func _envelope(t) -> void:
	var leagues := LeagueData.leagues()
	for l in leagues:
		var target := float(l.get("card_parity", 0.0))
		var got := CardBudget.parity(l)
		t.ok(target > 0.0, "%s declares a card_parity" % l["id"])
		t.ok(absf(got - target) <= CardBudget.PARITY_TOL * target, "%s parity %.2f within %.2f ±%.0f%%" % [l["id"], got, target, 100.0 * CardBudget.PARITY_TOL])
		var a := CardBudget.ai_budget(l)
		t.eq(int(a["authored_n"]) + int(a["dealt_n"]), int(a["per_season"]), "%s allowance = authored + dealt" % l["id"])
		t.ok(float(a["power"]) > 0.0, "%s AI budget is positive (%.2f)" % [l["id"], a["power"]])
		var p := CardBudget.player_income(l)
		t.ok(float(p["drops"]) > 0.0 and float(p["coins"]) > 0.0 and float(p["power"]) > 0.0, "%s player income positive" % l["id"])
	var chain := CardBudget.unlock_chain(leagues)
	t.eq(chain[0]["id"], "cage", "the open league heads the chain")
	t.eq(chain[1]["id"], "beach", "the beach follows it")
	for i in range(1, chain.size()):
		t.ok(float(chain[i]["card_parity"]) >= float(chain[i - 1]["card_parity"]), "parity does not fall from %s to %s" % [chain[i - 1]["id"], chain[i]["id"]])
	# The cage's arithmetic, by hand: 7 opponents × 2 rounds = 14 games; drops at
	# 0.5·0.6 + 0.5·0.25 = 0.425 a game plus 4 playoff games at +0.15.
	var cage := LeagueData.league("cage")
	t.eq(CardBudget.regular_games(cage), 14, "14 regular-season games")
	var inc := CardBudget.player_income(cage)
	t.close(float(inc["drops"]), 14 * 0.425 + 4 * 0.575, 1e-9, "expected drops per season")
	t.close(float(inc["coins"]), 18 * 35.0 + 0.2 * 300.0, 1e-9, "expected coins per season")
	var a := CardBudget.ai_budget(cage)
	t.eq(int(a["authored_n"]), 3, "cage authors 3 signature cards")
	t.eq(int(a["per_season"]), 6, "cage allowance is 6")
	# Drift is caught: the same league with a swollen allowance leaves its envelope.
	var hot := cage.duplicate(true)
	hot["ai_cards_per_season"] = 40
	t.ok(CardBudget.parity(hot) > float(cage["card_parity"]) * (1.0 + CardBudget.PARITY_TOL), "a swollen allowance breaks parity (%.2f)" % CardBudget.parity(hot))
	var cold := cage.duplicate(true)
	cold["ai_cards_per_season"] = 3
	t.ok(CardBudget.parity(cold) < CardBudget.parity(cage), "a smaller allowance lowers parity")


func _dealer(t) -> void:
	var cage := LeagueData.league("cage")
	var beach := LeagueData.league("beach")
	var seen_diff := false
	var first := CardRewards.ai_hands(cage, 100)
	for s in 50:
		var hands := CardRewards.ai_hands(cage, 100 + s)
		var total := 0
		var over := false
		var unknown := false
		for sid in hands:
			total += hands[sid].size()
			if hands[sid].size() > int(cage["ai_hand_max"]):
				over = true
			for id in hands[sid]:
				if CardDefs.get_card(str(id)).is_empty():
					unknown = true
		if s < 3 or total != int(cage["ai_cards_per_season"]):
			t.eq(total, int(cage["ai_cards_per_season"]), "cage deals exactly its allowance (seed %d)" % (100 + s))
		if over:
			t.ok(false, "a cage hand exceeded ai_hand_max (seed %d)" % (100 + s))
		if unknown:
			t.ok(false, "dealt an unknown card (seed %d)" % (100 + s))
		t.eq(hands.size(), 7, "every roster shooter has a hand") if s == 0 else null
		t.ok(hands["brickport"].has("fire7") and hands["pinewick"].has("ice") and hands["goldgulch"].has("ice"),
			"signature cards are always dealt (seed %d)" % (100 + s)) if s < 5 else null
		if hands != first:
			seen_diff = true
	t.ok(seen_diff, "different seeds deal different hands")
	t.eq(CardRewards.ai_hands(cage, 5), CardRewards.ai_hands(cage, 5), "the deal replays from its seed")
	var b := CardRewards.ai_hands(beach, 9)
	var b_total := 0
	for sid in b:
		b_total += b[sid].size()
	t.eq(b_total, int(beach["ai_cards_per_season"]), "beach deals its allowance on top of 9 authored")
	t.eq(b["frostpeak"], ["ice", "ice"], "a full authored hand is dealt as authored")
	# A league without the fields: just its authored hands.
	var bare := {"id": "x", "roster": ["a", "b"], "ai_cards": {"a": ["ice"]}}
	t.eq(CardRewards.ai_hands(bare, 1), {"a": ["ice"], "b": []}, "no allowance fields → authored only")
	# The rarity-weighted picker leans common, like the drops.
	var rng := DetRng.new(3)
	var n_fire := 0
	for i in 400:
		if CardRewards.pick_weighted(["ice", "fire7"], rng) == "fire7":
			n_fire += 1
	t.ok(n_fire > 200, "common cards are dealt more often (%d/400)" % n_fire)
	# The dealer's data rules live in LeagueData.validate: a typo'd id is caught.
	var bad := cage.duplicate(true)
	bad["ai_cards"] = {"brickport": ["fire77"]}
	var problems := PackedStringArray()
	LeagueData._validate_cards(bad, problems)
	t.ok(problems.size() == 1 and problems[0].contains("unknown card"), "an unknown signature card is a data problem (%s)" % str(problems))
	var fat := cage.duplicate(true)
	fat["ai_cards"] = {"brickport": ["fire7", "fire7", "fire7"]}
	problems = PackedStringArray()
	LeagueData._validate_cards(fat, problems)
	t.ok(problems.size() >= 1 and problems[0].contains("exceeds ai_hand_max"), "an over-cap authored hand is a data problem")
