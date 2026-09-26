class_name CardLab
extends RefCounted
## Measures a card's power on the real engine: seeded bot-vs-bot heats on a
## league's format, geometry and roster, paired — every seed runs a control
## heat with no cards and one heat per card with that card in the AI's hand —
## and the power is the mean change in the AI's margin, in points. Nothing
## here models an effect: the heat plays the card through CardPolicy →
## Heat.play_card → CardEffects → TimeTrial exactly as a league heat does, so
## a new effect kind is measured the day it exists. Offline only
## (tools/card_lab.gd writes the result to assets/cards/card_power.json; the
## suite reads that file, never this). Measured on the still court: no board
## slide, no spot shuffle — a card's swing barely depends on either and the
## control is cleaner without them.

const MAX_HEAT_S := 400.0   # tick guard: regulation + a stack of overtimes


static func geo_for_key(key: String) -> SimGeometry:
	match key:
		"arcade":
			return SimGeometry.arcade()
		"beach":
			return SimGeometry.beach()
		_:
			return SimGeometry.regulation()


## One heat to the buzzer. `card_id` = "" for the control run. Returns
## {margin: ai − player, played: bool, ai, player, done}.
static func run_heat(league: Dictionary, home: AiRatings, away: AiRatings, seed_value: int, card_id: String) -> Dictionary:
	var h := Heat.new({
		"geo": geo_for_key(str(league.get("calib_key", "regulation"))),
		"seconds": float(league.get("heat_seconds", Heat.DEFAULT_SECONDS)),
		"ot_seconds": float(league.get("ot_seconds", Heat.DEFAULT_OT_SECONDS)),
		"ball_return_s": float(league.get("ball_return_s", Heat.DEFAULT_BALL_RETURN_S)),
		"ai": home, "player_bot": away,
		"err_mult": float(league.get("err_mult", 1.0)), "seed": seed_value,
		"calib_key": str(league.get("calib_key", "regulation")),
		"ai_cards": [card_id] if card_id != "" else [], "player_cards": [],
	})
	var steps := int(MAX_HEAT_S / SimConstants.SIM_DT)
	for i in steps:
		h.tick(SimConstants.SIM_DT)
		if h.done:
			break
	return {"margin": h.ai.score - h.player.score, "played": not h.cards_played[Heat.AI].is_empty(),
		"ai": h.ai.score, "player": h.player.score, "done": h.done}


## → {card_id: {power, se, with, without, played, n}} for every card in
## `card_ids`, on `n` paired seeds. `power` = mean of (margin with the card −
## control margin); `se` = its standard error (the paired differences'
## deviation / √n — a card within ~2·se of a band edge needs a bigger n);
## `played` = the share of runs where the policy actually deployed it (a card
## the AI never finds a moment for measures near zero, and this says why).
## One control heat per seed serves every card.
static func measure_all(card_ids: Array, league: Dictionary, n: int, seed_value: int) -> Dictionary:
	var ratings := LeagueData.league_ratings(league)
	var ids: Array = ratings.keys()
	ids.sort()
	var sum_d := {}
	var sum_d2 := {}
	var sum_with := {}
	var played := {}
	for id in card_ids:
		sum_d[id] = 0.0
		sum_d2[id] = 0.0
		sum_with[id] = 0.0
		played[id] = 0
	var sum_without := 0.0
	for i in n:
		var rng := DetRng.new(QuickSim.seed_from([seed_value, league.get("id", "?"), i]))
		var home: AiRatings = ratings[rng.pick(ids)]
		var away: AiRatings = ratings[rng.pick(ids)]
		var heat_seed := rng.next_u() & 0x7FFFFFFF
		var control := run_heat(league, home, away, heat_seed, "")
		sum_without += float(control["margin"])
		for id in card_ids:
			var with := run_heat(league, home, away, heat_seed, str(id))
			var d := float(with["margin"]) - float(control["margin"])
			sum_d[id] = float(sum_d[id]) + d
			sum_d2[id] = float(sum_d2[id]) + d * d
			sum_with[id] = float(sum_with[id]) + float(with["margin"])
			if with["played"]:
				played[id] = int(played[id]) + 1
	var nn := maxf(float(n), 1.0)
	var out := {}
	for id in card_ids:
		var mean_d := float(sum_d[id]) / nn
		var var_d := maxf(float(sum_d2[id]) / nn - mean_d * mean_d, 0.0)
		out[id] = {"power": mean_d, "se": sqrt(var_d / nn), "with": float(sum_with[id]) / nn,
			"without": sum_without / nn, "played": float(played[id]) / nn, "n": n}
	return out


## One card (the same numbers measure_all gives it).
static func measure(card_id: String, league: Dictionary, n: int, seed_value: int) -> Dictionary:
	return measure_all([card_id], league, n, seed_value)[card_id]
