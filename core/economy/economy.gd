class_name Economy
extends RefCounted
## The two currencies (docs/ECONOMY.md). TICKETS are global and buy locker
## items; earned by time trials (never practice) and league heats. COINS are
## one wallet per league and buy that league's power-up cards; earned by
## that league's heats. The numbers live in data/economy.json (trials) and
## data/leagues.json `rewards` (heats); this is the arithmetic, headless.

const PATH := "res://data/economy.json"

static var _doc: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_doc = parsed


static func doc() -> Dictionary:
	_load()
	return _doc


static func tickets_cfg() -> Dictionary:
	return doc().get("tickets", {})


static func coins_cfg() -> Dictionary:
	return doc().get("coins", {})


## Tickets for a finished time trial: (base + per_point × score) × the
## location's multiplier, rounded, plus the new-best bonus. Never negative.
static func trial_tickets(run: Dictionary, is_best: bool) -> int:
	var t: Dictionary = tickets_cfg().get("trial", {})
	var mult := float(Dictionary(t.get("location_mult", {})).get(str(run.get("location", "cage")), 1.0))
	var score := maxf(float(run.get("score", 0)), 0.0)
	var n := int(roundf((float(t.get("base", 6)) + float(t.get("per_point", 0.45)) * score) * mult))
	if is_best and score > 0.0:   # an empty board makes any run a "best"; zero earns no bonus
		n += int(t.get("new_best", 10))
	return maxi(n, 0)


## Coins and tickets for a league heat from the league's `rewards` row.
static func heat_rewards(league: Dictionary, won: bool, title: bool) -> Dictionary:
	var r: Dictionary = league.get("rewards", {})
	var coins := int(r.get("win_coins", 50)) if won else int(r.get("loss_coins", 20))
	var tickets := int(r.get("win_tickets", 0)) if won else int(r.get("loss_tickets", 0))
	if title:
		coins += int(r.get("title_coins", 300))
		tickets += int(r.get("title_tickets", 0))
	return {"coins": coins, "tickets": tickets}


## The online match payout (docs/BACKEND.md → Cards online; the server's
## cards.ts runs the same rule): online coins only — the winner's base scaled
## by the upset (a lower level beating a higher one earns more), the loser's
## flat. {coins, mult}.
static func online_coins(won: bool, my_level: int, their_level: int) -> Dictionary:
	var o: Dictionary = doc().get("online", {})
	if not won:
		return {"coins": int(o.get("loss_coins", 20)), "mult": 1.0}
	var raw := 1.0 + float(o.get("upset_per_level", 0.15)) * float(their_level - my_level)
	var mult := clampf(raw, float(o.get("mult_min", 0.5)), float(o.get("mult_max", 2.5)))
	return {"coins": int(roundf(float(o.get("win_coins", 50)) * mult)), "mult": roundf(mult * 100.0) / 100.0}


## Expected coins per heat at the reference win rate.
static func expected_coins_per_heat(league: Dictionary, p_win := -1.0) -> float:
	var r: Dictionary = league.get("rewards", {})
	var p := p_win if p_win >= 0.0 else float(Dictionary(tickets_cfg().get("reference", {})).get("p_win", 0.5))
	return p * float(r.get("win_coins", 50)) + (1.0 - p) * float(r.get("loss_coins", 20))


## Expected tickets per heat at the reference win rate.
static func expected_tickets_per_heat(league: Dictionary, p_win := -1.0) -> float:
	var r: Dictionary = league.get("rewards", {})
	var p := p_win if p_win >= 0.0 else float(Dictionary(tickets_cfg().get("reference", {})).get("p_win", 0.5))
	return p * float(r.get("win_tickets", 0)) + (1.0 - p) * float(r.get("loss_tickets", 0))
