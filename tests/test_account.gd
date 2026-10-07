extends RefCounted
## The device account part, the leaderboard outbox and the mirror seam in
## SaveService (docs/BACKEND.md): round trips, the pending cap, dropping a
## sent run, part docs / restore / clear_dirty, all surviving a reload. Never
## touches the network.

const SaveServiceScript := preload("res://game/autoload/save_service.gd")


func _wipe() -> void:
	var dir := ProjectSettings.globalize_path("user://save")
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + "/" + f)


func _fresh() -> Node:
	var svc: Node = SaveServiceScript.new()
	svc.load_all()
	return svc


func _payload(i: int) -> Dictionary:
	return {"runId": "%08x-0000-4000-8000-000000000000" % i, "area": "cage", "score": i, "makes": i, "attempts": i + 1,
		"swishes": 0, "bestStreak": 0, "bonus": 0, "iced": 0, "playedAt": 1000 + i, "version": "t"}


func run(t) -> void:
	_wipe()
	var svc := _fresh()
	t.eq(svc.get_account(), {}, "no account before the first launch mints one")
	svc.put_account({"playerId": "p", "secret": "s", "name": "BRICK BARON", "tag": "42", "registered": false})
	t.eq(svc.get_account()["name"], "BRICK BARON", "account round-trips")
	t.ok(int(svc.get_account().get("updatedAt", 0)) > 0, "stamped")
	t.ok(not svc.dirty_parts().has("account"), "the account never syncs (the secret stays on the device)")
	# The outbox's pending scores.
	t.eq(svc.pending_scores(), [], "nothing pending")
	svc.queue_score(_payload(1))
	svc.queue_score(_payload(2))
	svc.queue_score(_payload(1))
	t.eq(svc.pending_scores().size(), 2, "a run is queued once")
	t.eq(int(svc.pending_scores()[0]["score"]), 1, "oldest first")
	svc.drop_score(_payload(1)["runId"])
	t.eq(svc.pending_scores().size(), 1, "a sent run leaves")
	t.eq(int(svc.pending_scores()[0]["score"]), 2, "…the other stays")
	for i in range(10, 10 + svc.PENDING_SCORES_KEEP + 5):
		svc.queue_score(_payload(i))
	t.eq(svc.pending_scores().size(), svc.PENDING_SCORES_KEEP, "capped")
	t.eq(int(svc.pending_scores()[0]["score"]), 15, "the oldest fell off")
	svc.put_score({"score": 3, "makes": 2, "swishes": 1, "attempts": 5, "bestStreak": 2})
	t.ok(svc.dirty_parts().has("time_trial_scores"), "dirty parts still work beside the pending scores")
	# The mirror seam: part docs with stamps, restore, clean flags.
	t.eq(svc.part_doc("nope"), {}, "an unknown part is {}")
	t.ok(svc.part_updated_at("time_trial_scores") > 0, "a written part carries its stamp")
	t.ok(svc.part_doc("progress").has("xp"), "the progress part doc")
	svc.clear_dirty("time_trial_scores")
	t.ok(not svc.dirty_parts().has("time_trial_scores"), "clear_dirty takes the flag")
	var newer := {"updatedAt": 9999999999999, "xp": 777, "seasonXp": 7, "seasonKey": "beach:3"}
	t.ok(svc.restore_part("progress", newer), "a stamped progress doc restores")
	t.eq(int(svc.get_progress()["xp"]), 777, "…and is what we read now")
	t.ok(not svc.dirty_parts().has("progress"), "a restored part is clean")
	t.ok(not svc.restore_part("progress", {"xp": 1}), "no stamp, no restore")
	t.ok(not svc.restore_part("account", {"updatedAt": 1, "secret": "x"}), "the account never restores")
	t.ok(not svc.restore_part("time_trial_scores", {"updatedAt": 1, "docs": "bad"}), "a scores part needs its docs list")
	svc.restore_part("time_trial_scores", {"updatedAt": 9999999999999, "docs": [{"id": "r", "score": 44, "playedAt": 5, "location": "city"}]})
	t.eq(int(svc.top_scores(1, "city")[0]["score"]), 44, "restored runs are the board")
	t.eq(svc.last_sync_at(), 0, "never synced")
	svc.set_last_sync(123456)
	t.eq(svc.last_sync_at(), 123456, "the sync stamp")
	svc.put_score({"score": 4, "makes": 3, "swishes": 0, "attempts": 6, "bestStreak": 2})
	t.ok(svc.dirty_parts().has("time_trial_scores"), "a write after a restore dirties the part again")
	# Everything survives a reload.
	var svc2 := _fresh()
	t.eq(int(svc2.get_progress()["xp"]), 777, "a restored part survives reload")
	t.eq(svc2.last_sync_at(), 123456, "the sync stamp survives reload")
	t.eq(svc2.get_account()["tag"], "42", "account survives reload")
	t.eq(svc2.pending_scores().size(), svc.PENDING_SCORES_KEEP, "pending scores survive reload")
	t.ok(svc2.dirty_parts().has("time_trial_scores"), "dirty parts survive reload")
	svc.free()
	svc2.free()
	_wipe()
