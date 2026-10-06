extends RefCounted
## The device account part and the leaderboard outbox in SaveService
## (docs/BACKEND.md): round trips, the pending cap, dropping a sent run,
## and all of it surviving a reload. Never touches the network.

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
	# Everything survives a reload.
	var svc2 := _fresh()
	t.eq(svc2.get_account()["tag"], "42", "account survives reload")
	t.eq(svc2.pending_scores().size(), svc.PENDING_SCORES_KEEP, "pending scores survive reload")
	t.ok(svc2.dirty_parts().has("time_trial_scores"), "dirty parts survive reload")
	svc.free()
	svc2.free()
	_wipe()
