extends RefCounted
## The league in context, design "Home League Context v2" (2026-10-30): the
## season-over card, the bracket as a tree, the shop's ask → CONFIRM → +1
## ADDED with its fallbacks, YOUR CARDS on the home, and the summary lines.


func _app():
	return Engine.get_main_loop().root.get_node_or_null("App")


func run(t) -> void:
	_summary(t)
	var app = _app()
	if app == null:
		return
	var cfg := LeagueData.league("cage")
	var was_league: String = app.current_league
	t.ok(app.enter_league("cage"), "the cage league is current")
	var kept: Dictionary = app.league_doc("cage").duplicate(true)
	var cards_before: Dictionary = SaveService.get_cards().duplicate(true)
	var cos_before: Dictionary = SaveService.get_cosmetics().duplicate(true)
	_season_over(t, app, cfg)
	app.save_league_doc(kept, "cage")
	_shop(t, app)
	_float_cards(t, app)
	SaveService.put_cards(cards_before)
	SaveService.put_cosmetics(cos_before)
	app.save_league_doc(kept, "cage")
	app.current_league = was_league


func _summary(t) -> void:
	var P := Campaign.PLAYER
	var season := {"series": [
		{"id": "s1", "round": "semifinal", "highSeedId": P, "lowSeedId": "ollie knots", "highWins": 2, "lowWins": 1, "winnerId": P},
		{"id": "f", "round": "final", "highSeedId": "paco prickle", "lowSeedId": P, "highWins": 2, "lowWins": 3, "winnerId": P}]}
	var run_line := LeagueSummary.playoff_run(season)
	t.ok(run_line.begins_with("BEAT ") and run_line.contains(" 2-1 · BEAT ") and run_line.ends_with(" 3-2"), "a champion's run (%s)" % run_line)
	season["series"][1]["winnerId"] = "paco prickle"
	t.ok(LeagueSummary.playoff_run(season).contains("LOST TO "), "a run that stopped says where")
	t.eq(LeagueSummary.playoff_run({"series": []}), "MISSED THE PLAYOFFS", "no series: missed")
	var doc := Campaign.new_doc(LeagueData.league("cage"), 3, 0)
	var lines := LeagueSummary.season_line_stats(doc)
	t.eq([lines[0]["l"], lines[1]["l"], lines[2]["l"]], ["AVG PTS", "HIGH", "STREAK"], "the season-over lines")
	t.eq(lines[0]["v"], "-", "no games: no average")


func _done_doc(cfg: Dictionary) -> Dictionary:
	var doc := Campaign.new_doc(cfg, 7, 1000)
	var win := {"won": true, "player_score": 34, "ai_score": 20, "ot": 0,
		"sides": {"player": {"score": 34, "makes": 20, "swishes": 6, "attempts": 28, "bestStreak": 9, "bonus": 4, "iced": 0},
			"ai": {"score": 20, "makes": 12, "swishes": 2, "attempts": 25, "bestStreak": 3, "bonus": 0, "iced": 0}}}
	Campaign.apply_live_result(doc, cfg, win, 2000)
	Campaign.sim_to_playoffs(doc, cfg)
	var guard := 0
	while doc["season"]["phase"] == "playoffs" and guard < 20:
		guard += 1
		if Campaign.player_alive(doc):
			Campaign.apply_live_result(doc, cfg, win, 3000)
		else:
			Campaign.sim_step(doc, cfg)
	return doc


func _season_over(t, app, cfg: Dictionary) -> void:
	var doc := _done_doc(cfg)
	t.eq(str(doc["season"]["phase"]), Season.PHASE_DONE, "the staged season is over")
	app.save_league_doc(doc, "cage")
	var lc := LeagueContext.new()
	lc.setup("cage")
	t.ok(lc.find_child("SeasonOver", true, false) is ShadowPanel, "MATCH shows the season-over card")
	t.ok(lc.find_child("MatchDot", true, false) == null, "…and no waiting dot on MATCH")
	var champ: Label = lc.find_child("Champion", true, false)
	t.ok(champ != null and champ.text != "", "the champion's name (%s)" % (champ.text if champ != null else ""))
	t.ok(lc.find_child("NextSeason", true, false) != null, "START SEASON on the card")
	var run: Control = lc.find_child("PlayoffRun", true, false)
	t.ok(run != null, "the playoff run under the rule")
	var tree: Control = lc.find_child("Bracket", true, false)
	t.ok(tree != null and tree.find_child("Final", true, false) != null and tree.find_child("Connector", true, false) is LeagueContext.Connector, "TABLE: the final over a connector")
	var semis: Control = lc.find_child("Semis", true, false) if tree != null else null
	t.eq(semis.get_child_count() if semis != null else 0, 2, "…over the two semis side by side")
	lc.free()


## The first card you can play at your level (the shop sells the rest dimmed).
func _usable(app) -> String:
	for c in CardDefs.all():
		if Progression.can_use(app.level(), c):
			return str(c["id"])
	return ""


func _shop(t, app) -> void:
	var id := _usable(app)
	t.ok(id != "", "a card is on sale at level %d" % app.level())
	if id == "":
		return
	var card := CardDefs.get_card(id)
	var price := int(card.get("price", 0))
	app.grant_tickets(price * 3)
	var lc := LeagueContext.new()
	lc.setup("cage", "CARDS")
	var bought := []
	lc.card_bought.connect(func(id: String, _from: Rect2) -> void: bought.push_back(id))
	t.eq(lc.buy_state(id), "idle", "a shop row starts on its price")
	t.ok(lc.find_child("Buy_" + id, true, false) is ShadowCard, "…the gold buy button")
	t.ok(lc.find_child("Level_" + id, true, false) != null, "…and its LVL tag")
	lc.tap_buy(id)
	t.eq(lc.buy_state(id), "ask", "a tap asks")
	t.ok(lc.find_child("Confirm_" + id, true, false) != null and lc.find_child("Cancel_" + id, true, false) != null, "…X and CONFIRM")
	lc.cancel_buy(id)
	t.eq(lc.buy_state(id), "idle", "X drops it")
	lc.tap_buy(id)
	lc._process(LeagueContext.ASK_S + 0.1)
	t.eq(lc.buy_state(id), "idle", "an unanswered CONFIRM drops back after 4 s")
	var before: int = app.tickets()
	var owned_before := CardDefs.owned(app.cards_bucket("cage"), id)
	lc.tap_buy(id)
	lc.tap_buy(id)
	t.eq(lc.buy_state(id), "done", "CONFIRM buys it: +1 ADDED")
	t.ok(lc.find_child("Added_" + id, true, false) is LeagueContext.AddedBox, "…in its dashed box")
	t.eq(app.tickets(), before - price, "the price is paid")
	t.eq(CardDefs.owned(app.cards_bucket("cage"), id), owned_before + 1, "…and the card is yours")
	t.eq(bought, [id], "the home hears of it (the flight)")
	lc._process(LeagueContext.ADDED_S + 0.1)
	t.eq(lc.buy_state(id), "idle", "+1 ADDED gives way to the price again")
	lc.free()


func _float_cards(t, app) -> void:
	var id := _usable(app)
	if id == "":
		return
	var fc := FloatCards.new()
	fc.build("cage")
	var ids := fc.ids()
	t.ok(ids.has(id), "YOUR CARDS shows what you own (%s)" % str(ids))
	var n := fc.count_of(id)
	t.eq(n, CardDefs.owned(app.cards_bucket("cage"), id), "…with its count")
	t.ok((fc.find_child("Count", true, false) as Label).text.ends_with(" AVAILABLE"), "n AVAILABLE in the head")
	fc.bump(id)
	t.eq(fc.count_of(id), n + 1, "a landed card bumps the count")
	fc._process(CssEase.BUMP_S * 0.35)
	var badge: Control = fc.find_child("Own_" + id, true, false).get_node("Badge")
	t.ok(badge.scale.x > 1.4, "…the badge pops (%.2f)" % badge.scale.x)
	fc._process(1.0)
	t.ok(is_equal_approx(badge.scale.x, 1.0), "…and settles")
	var fresh := ""
	for c in CardDefs.all():
		if not ids.has(str(c["id"])):
			fresh = str(c["id"])
	if fresh != "":
		fc.make_room(fresh)
		t.ok(fc.has(fresh), "a new kind gets a slot")
		var slot: Control = fc.find_child("Own_" + fresh, true, false)
		t.eq(slot.custom_minimum_size.x, 0.0, "…shut until the card lands")
		fc.grow(fresh)
		fc._process(CssEase.GROW_S + 0.05)
		t.eq(slot.custom_minimum_size.x, FloatCards.CARD.x + FloatCards.SHADOW, "…then grown open")
	fc.free()
