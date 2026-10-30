extends RefCounted
## App's side of a rated decision (docs/BACKEND.md → Ranked → Stage B):
## the tickets granted once, the settle's keys merged into last_heat
## whichever of settled_online / settle_heat lands second, the bright spots
## noted against the online store, the shoot-around offer and its once-a-day
## bonus. No network: Net is left alone (nothing here reaches it).


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func _settle(won: bool) -> Dictionary:
	return {"t": "settled", "won": won, "reason": "played", "ranked": true, "pay": true, "tickets": 30 if won else 14,
		"rating": {"before": {"mu": 1500.0, "rd": 350.0, "cons": 800.0}, "after": {"mu": 1518.0, "rd": 290.0, "cons": 938.0}, "delta": 18.0},
		"rank": {"tier": "rookie", "division": 2}, "events": ["promoted"], "peak": {"tier": "rookie", "division": 2},
		"spoils": {"captured": ["ice"], "lost": [], "insured": null}, "meter": {"before": 0, "after": 14, "size": 22, "odds": {"common": 1.0, "rare": 0.0, "epic": 0.0}},
		"granted": [], "milestones": ["first_ranked_match"], "loss_streak": 0 if won else 4}


func _result() -> Dictionary:
	return {"won": true, "player_score": 30, "ai_score": 20, "ot": 0, "online": true,
		"sides": {"player": {"makes": 15, "attempts": 25, "swishes": 5, "bestStreak": 6, "bonus": 3, "iced": 0},
			"ai": {"makes": 10, "attempts": 25, "swishes": 2, "bestStreak": 3, "bonus": 0, "iced": 0}}}


func run(t) -> void:
	# The ranked poll's body (Ross, 2026-10-29): the picker's court as a
	# preference; ANY sends the old empty body an older Worker still takes.
	t.eq(App.ranked_body("beach"), {"area": "beach"}, "a picked court rides the ranked poll")
	t.eq(App.ranked_body("any"), {}, "ANY sends nothing")
	t.eq(App.ranked_body(""), {}, "…and so does no pick")
	var app = _app()
	if app == null:
		t.ok(false, "App autoload present")
		return
	var save: Node = Engine.get_main_loop().root.get_node("SaveService")
	var tickets0: int = app.tickets()
	var prog0: Dictionary = save.get_progress()
	var was_heat: Dictionary = app.last_heat.duplicate(true)
	var was_next: Dictionary = app.next_heat.duplicate(true) if app.next_heat is Dictionary else {}
	var was_settle: Dictionary = app.online_settle.duplicate(true)
	var was_room = app.room
	app.room = null
	# The decision lands first, the heat's own result after.
	app.online_settle = {}
	app.last_heat = {}
	app.next_heat = {"remote": true, "ranked": true, "their_level": 4, "opponent": {"name": "THEM"}}
	app.settled_online(_settle(true))
	t.eq(app.tickets(), tickets0 + 30, "the server's tickets are granted")
	app.settled_online(_settle(true))
	t.eq(app.tickets(), tickets0 + 30, "…once")
	app.settle_heat(_result())
	t.ok(bool(app.last_heat.get("ranked", false)) and int(app.last_heat.get("tickets", 0)) == 30, "settle_heat keeps the settle's keys (tickets)")
	t.eq(app.last_heat.get("spoils"), _settle(true)["spoils"], "…the spoils")
	t.eq(int(Dictionary(app.last_heat.get("meter", {})).get("after", 0)), 14, "…the meter")
	t.eq(app.last_heat.get("milestones"), ["first_ranked_match"], "…the milestones")
	t.ok(app.last_heat.get("bright") is Array, "bright spots noted against the online store")
	var online: Dictionary = save.get_progress().get("online", {})
	t.ok(Dictionary(online.get("career", {})).has("bright"), "…and the store keeps the running bests")
	# The other order: the heat's result first, the decision after.
	app.online_settle = {}
	app.last_heat = {}
	app.settle_heat(_result())
	t.ok(not app.last_heat.has("tickets"), "no settle yet, no tickets on the page")
	app.settled_online(_settle(false))
	t.eq(app.tickets(), tickets0 + 44, "the loss's tickets granted")
	t.eq(int(app.last_heat.get("tickets", 0)), 14, "…and merged into the page's dict")
	t.eq(int(app.last_heat.get("loss_streak", 0)), 4, "the streak rides along")
	# The shoot-around: offered after a stretch, once a day.
	var pr: Dictionary = save.get_progress()
	var on: Dictionary = pr.get("online", {})
	on.erase("shoot_day")
	pr["online"] = on
	save.put_progress(pr)
	t.ok(app.shoot_around_offered(), "offered at a 4-loss stretch with no shoot-around today")
	app._shoot_bonus_pending = true
	t.eq(app.take_shoot_bonus(), 5, "the bonus from data")
	t.eq(app.take_shoot_bonus(), 0, "…once")
	t.ok(not app.shoot_around_offered(), "not offered again today")
	t.eq(int(Dictionary(save.get_progress().get("online", {})).get("shoot_day", -1)), app.utc_day(), "the day is stamped")
	app.online_settle = {"ranked": true, "loss_streak": 1}
	pr = save.get_progress()
	on = pr.get("online", {})
	on.erase("shoot_day")
	pr["online"] = on
	save.put_progress(pr)
	t.ok(not app.shoot_around_offered(), "one loss is no stretch")
	# Put everything back.
	app.spend_tickets(44)
	save.put_progress(prog0)
	app.last_heat = was_heat
	app.next_heat = was_next
	app.online_settle = was_settle
	app.room = was_room
