extends RefCounted
## SaveService behavior: UUIDs, updatedAt stamps, leaderboard ordering, outbox,
## atomic persistence across a reload.

const SaveServiceScript := preload("res://game/autoload/save_service.gd")


func _fresh() -> Node:
	# Point the service at a scratch dir by nuking any prior test save state.
	var svc: Node = SaveServiceScript.new()
	svc.load_all()
	return svc


func _wipe() -> void:
	var dir := ProjectSettings.globalize_path("user://save")
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + "/" + f)


func run(t) -> void:
	_wipe()
	var svc := _fresh()

	# meta: client id is a valid UUIDv4, persisted across reload.
	var cid: String = svc.get_client_id()
	var uuid_re := RegEx.create_from_string(
		"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	)
	t.ok(uuid_re.search(cid) != null, "clientId is UUIDv4 (%s)" % cid)

	# uuid4 uniqueness sanity.
	var seen := {}
	for i in 200:
		seen[SaveServiceScript.uuid4()] = true
	t.eq(seen.size(), 200, "uuid4 does not collide in 200 draws")

	# put_score stamps id + updatedAt and orders correctly.
	var a: Dictionary = svc.put_score({"score": 12, "makes": 8, "swishes": 4, "attempts": 15, "bestStreak": 5, "playedAt": 1000})
	svc.put_score({"score": 20, "makes": 12, "swishes": 8, "attempts": 18, "bestStreak": 7, "playedAt": 2000})
	svc.put_score({"score": 12, "makes": 9, "swishes": 3, "attempts": 16, "bestStreak": 4, "playedAt": 500})
	t.ok(uuid_re.search(a["id"]) != null, "score doc gets UUIDv4 id")
	t.ok(a["updatedAt"] > 0, "score doc gets updatedAt")
	var top: Array = svc.top_scores(10)
	t.eq(top.size(), 3, "three docs stored")
	t.eq(top[0]["score"], 20, "highest first")
	t.eq(top[1]["playedAt"], 500, "tie broken by earlier playedAt")
	t.eq(top[2]["playedAt"], 1000, "later tie run last")
	t.ok(svc.is_best(21), "21 is a new best")
	t.ok(not svc.is_best(20), "20 ties, not best")

	# Per-court leaderboards: a location filter; legacy docs count as the cage.
	svc.put_score({"score": 9, "makes": 5, "swishes": 1, "attempts": 12, "bestStreak": 3, "playedAt": 3000, "location": "beach"})
	t.eq(svc.top_scores(10, "beach").size(), 1, "beach board lists only beach runs")
	t.eq(svc.top_scores(10, "cage").size(), 3, "legacy runs count as arcade cage")
	t.eq(svc.top_scores(10).size(), 4, "no filter → every court")
	t.ok(svc.is_best(10, "beach"), "10 is a beach best")
	t.ok(not svc.is_best(10, "cage"), "10 is not a cage best")

	# Outbox marked dirty by writes.
	t.ok(svc.dirty_parts().has("time_trial_scores"), "scores part marked dirty")

	# Tuning scratchpad: off by default, round-trips, and is device-local.
	t.eq(svc.get_tuning().get("tuningMode", null), false, "tuning mode defaults off")
	t.ok(svc.get_tuning().get("fields", null) is Dictionary, "tuning fields default to {}")
	svc.put_tuning(true, {"angle_low": 42.0})
	t.ok(svc.get_tuning().get("undo", {}).is_empty(), "no undo snapshot by default")
	svc.put_tuning_undo({"angle_low": 41.0})
	t.close(float(svc.get_tuning()["undo"]["angle_low"]), 41.0, 1e-9, "undo snapshot stored")
	svc.put_tuning(true, {"angle_low": 42.0})
	t.close(float(svc.get_tuning()["undo"]["angle_low"]), 41.0, 1e-9, "put_tuning keeps the undo snapshot")
	t.ok(not svc.dirty_parts().has("tuning"), "tuning part is never marked dirty (not synced)")

	# settings: player preferences. Unlike tuning these DO sync, and a save
	# written before the key existed must fall back rather than break.
	t.eq(svc.get_settings().get("shotHelp", null), 0, "shot help defaults off")
	var st: Dictionary = svc.get_settings()
	st["shotHelp"] = 2
	st["darkMode"] = true
	svc.put_settings(st)
	t.ok(svc.dirty_parts().has("settings"), "settings part is marked dirty (player state)")

	# Cosmetics: starter defaults, round-trip, marked dirty (player state).
	var cos: Dictionary = svc.get_cosmetics()
	t.eq(cos["hoop"]["selected"], "classic", "starter hoop selected")
	t.ok(Array(cos["ball"]["owned"]).has("classic"), "starter ball owned")
	t.eq(int(cos["coins"]), 0, "no coins to start")
	cos["coins"] = 250
	cos["hoop"]["owned"].push_back("neon")
	cos["hoop"]["selected"] = "neon"
	svc.put_cosmetics(cos)
	t.ok(svc.dirty_parts().has("cosmetics"), "cosmetics part marked dirty")

	# Persistence: a brand-new instance reads the same state (atomic writes landed).
	var svc2 := _fresh()
	t.eq(svc2.get_client_id(), cid, "clientId stable across reload")
	t.eq(svc2.top_scores(10).size(), 4, "scores survive reload")
	t.ok(svc2.dirty_parts().has("time_trial_scores"), "outbox survives reload")
	t.eq(svc2.get_tuning()["tuningMode"], true, "tuning mode survives reload")
	t.eq(int(svc2.get_settings()["shotHelp"]), 2, "shot help mode survives reload")
	t.eq(bool(svc2.get_settings().get("darkMode", false)), true, "dark mode survives reload")
	t.eq(int(svc2.get_cosmetics()["coins"]), 250, "coins survive reload")
	t.eq(svc2.get_cosmetics()["hoop"]["selected"], "neon", "hoop selection survives reload")
	t.close(float(svc2.get_tuning()["fields"]["angle_low"]), 42.0, 1e-9, "tuning field survives reload")
	t.close(float(svc2.get_tuning().get("undo", {}).get("angle_low", 0.0)), 41.0, 1e-9, "undo snapshot survives reload")

	# League parts: campaign docs + live games round-trip and prune.
	var svc3 := _fresh()
	t.eq(svc3.get_campaign()["leagues"].size(), 0, "no leagues yet")
	svc3.put_league_doc("cage", {"leagueId": "cage", "year": 1})
	t.ok(svc3.league_doc("cage")["id"] != "", "league doc gets a uuid")
	t.ok(svc3.dirty_parts().has("campaign"), "campaign part marked dirty")
	for i in 55:
		svc3.put_live_game({"leagueId": "cage", "playerScore": i, "oppScore": 3})
	t.eq(svc3.live_games("cage", 100).size(), 50, "live games pruned to 50")
	t.eq(int(svc3.live_games("cage", 1)[0]["playerScore"]), 54, "best score first")
	t.eq(svc3.live_games("beach").size(), 0, "filtered by league")
	var svc4 := _fresh()
	t.eq(svc4.league_doc("cage")["year"], 1, "league doc survives reload")
	t.eq(svc4.live_games("cage", 100).size(), 50, "live games survive reload")
	# Cards part.
	t.eq(svc3.get_cards()["loadout"].size(), 3, "three loadout slots by default")
	var cd: Dictionary = svc3.get_cards()
	CardDefs.add(cd, "ice", 1)
	CardDefs.equip(cd, 1, "ice")
	svc3.put_cards(cd)
	t.ok(svc3.dirty_parts().has("cards"), "cards part marked dirty")
	var svc5 := _fresh()
	t.eq(CardDefs.owned(svc5.get_cards(), "ice"), 1, "card ownership survives reload")
	t.eq(svc5.get_cards()["loadout"][1], "ice", "loadout survives reload")
	t.eq(svc5.get_cards().get("v", 0), CardDefs.DOC_VERSION, "cards doc carries the version")
	svc5.free()
	svc3.free()
	svc4.free()
	svc.free()
	svc2.free()
	_wipe()
