class_name Economy
extends RefCounted
## The one currency (docs/ECONOMY.md, 2026-10-19): TICKETS, one global
## wallet, earned by time trials (never practice), league heats and titles,
## spent on PEGGY plays and on each league's power-up cards (the cards stay
## in the league they were bought in; only the wallet is global). Online
## cards are never bought. The numbers live in data/economy.json (trials,
## the card bands) and data/leagues.json `rewards` (heats); this is the
## arithmetic, headless.

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


## The card rules: heats-to-afford bands per rarity, the informational
## ticket share the card ledger assumes goes to cards.
static func cards_cfg() -> Dictionary:
	return doc().get("cards", {})


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


## Tickets for a league heat from the league's `rewards` row (win or loss,
## plus the title bonus). Online heats pay nothing yet (the ranked task).
static func heat_rewards(league: Dictionary, won: bool, title: bool) -> Dictionary:
	var r: Dictionary = league.get("rewards", {})
	var tickets := int(r.get("win_tickets", 0)) if won else int(r.get("loss_tickets", 0))
	if title:
		tickets += int(r.get("title_tickets", 0))
	return {"tickets": tickets}


## Expected tickets per heat at the reference win rate.
static func expected_tickets_per_heat(league: Dictionary, p_win := -1.0) -> float:
	var r: Dictionary = league.get("rewards", {})
	var p := p_win if p_win >= 0.0 else float(Dictionary(tickets_cfg().get("reference", {})).get("p_win", 0.5))
	return p * float(r.get("win_tickets", 0)) + (1.0 - p) * float(r.get("loss_tickets", 0))
