extends RefCounted
## League banners: the arena sets carry valid anchors, and the banner node
## lays out the standings / bracket / label content.


func run(t) -> void:
	var beach: ArenaSet = CosmeticLibrary.get_arena("beach")
	var cage: ArenaSet = CosmeticLibrary.get_arena("cage")
	t.eq(beach.league_banner_kind, "standings", "beach shows the standings/bracket banner")
	t.eq(beach.league_banner_style, "chalk", "beach board is a chalkboard")
	t.ok(beach.league_banner_size.x > 0.5 and beach.league_banner_size.y > 0.3, "beach banner has a size")
	t.ok(beach.league_banner_pos.x > 5.0 and beach.league_banner_pos.z > 0.5, "beach banner on the back fence, shooter's right")
	# The cage's painted sash is gone: it now carries a live LED ribbon board
	# across the back wall instead (see test_ticker_text.gd).
	t.eq(cage.league_banner_kind, "", "cage hangs no cloth banner any more")
	t.ok(not FileAccess.file_exists("res://assets/textures/sash.png"), "the sash texture is gone with it")

	var b := LeagueBanner.new()
	b._ready()
	b.set_layout(beach.league_banner_pos, beach.league_banner_size, beach.league_banner_yaw_deg, beach.league_banner_lit)
	t.eq((b.mesh_instance.mesh as QuadMesh).size, beach.league_banner_size, "quad sized from the arena set")
	t.eq(b.position, beach.league_banner_pos, "placed at the anchor")
	var league := LeagueData.league("cage")
	var ids := LeagueData.team_ids(league)
	var state := Season.create(league, ids, 1, 3)
	var ratings := LeagueData.league_ratings(league)
	for d in 6:
		Season.resolve_day(state, ratings, "player", AiRatings.make(0.55, 0.5), {})
	var table := Standings.table(ids, state["schedule"], 3)
	var clinches := Standings.compute_clinches(ids, state["schedule"], 4)
	var names := {"player": "You"}
	for id in ids:
		if id != "player":
			names[id] = LeagueData.shooter(id)["name"]
	b.show_standings("Arcade League", table, clinches, names, "player")
	t.eq(b.kind, "standings", "standings kind")
	t.ok(b.rows()[0].ends_with("standings"), "title row (chalk)")
	t.ok(b._chalk_font != null, "chalk handwriting font loaded")
	t.eq(b.rows().size(), 1 + 8 * 3, "title + 8 rows × (rank, name, record)")
	t.ok(b.rows().has("You") or b.rows().filter(func(r): return r.begins_with("You")).size() == 1, "player row present")
	var wl: Array = b.rows().filter(func(r): return r.match("* - *") and not r.ends_with("standings"))
	t.eq(wl.size(), 8, "eight W - L cells")
	b.set_style("nope")
	t.eq(b.style, "chalk", "unknown style falls back to chalk")
	# Bracket after the season.
	while state["phase"] == "regular":
		Season.resolve_day(state, ratings, "player", AiRatings.make(0.55, 0.5), {})
	b.show_bracket("Arcade League", state["series"], names, "")
	t.eq(b.kind, "bracket", "bracket kind")
	t.ok(b.rows().has("semifinals") and b.rows().has("final"), "round headings")
	t.eq(b.rows().filter(func(r): return r.contains(" - ") and not r.ends_with("standings")).size(), 2, "two semifinal lines")
	t.ok(b.rows().has("tbd"), "final still tbd")
	b.show_bracket("Arcade League", [], names, "", 14)
	t.ok(b.rows().filter(func(r): return r.begins_with("bracket forms")).size() == 1, "empty bracket message")
	# Label.
	b.show_label("LEAGUE MATCH")
	t.eq(b.kind, "label", "label kind")
	t.eq(b.rows(), ["LEAGUE MATCH"] as Array[String], "label text")
	t.eq(b.viewport.size, LeagueBanner.LABEL_SIZE, "label uses the short viewport")
	b.free()
