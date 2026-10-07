extends RefCounted
## SaveCodec (docs/BACKEND.md → Phase 2): a part's JSON gzipped whole and
## back, garbage refused, the sync-part list the server shares.


func run(t) -> void:
	t.eq(SaveCodec.SYNC_PARTS, ["time_trial_scores", "cosmetics", "settings", "campaign", "liveGames", "cards", "progress"], "the seven parts that sync")
	t.ok(SaveCodec.is_sync_part("progress") and not SaveCodec.is_sync_part("account") and not SaveCodec.is_sync_part("tuning"), "the secret and the scratchpad never sync")
	var doc := {"updatedAt": 1234, "docs": [{"score": 31, "location": "beach"}], "nested": {"a": [1, 2.5, "x"]}}
	var bytes := SaveCodec.encode(doc)
	t.ok(bytes.size() > 18 and bytes[0] == 0x1f and bytes[1] == 0x8b, "gzip magic")
	var back := SaveCodec.decode(bytes)
	t.eq(int(back["updatedAt"]), 1234, "the stamp survives")
	t.eq(str(back["docs"][0]["location"]), "beach", "the docs survive")
	t.eq(float(back["nested"]["a"][1]), 2.5, "numbers survive")
	t.eq(SaveCodec.decode(PackedByteArray()), {}, "nothing → {}")
	t.eq(SaveCodec.decode("not gzip at all, just some text".to_utf8_buffer()), {}, "plain text → {}")
	var broken := bytes.duplicate()
	broken.resize(bytes.size() / 2)
	t.eq(SaveCodec.decode(broken), {}, "a truncated stream → {}")
	t.eq(SaveCodec.decode(SaveCodec.encode({})), {}, "an empty object → {}")
	var big := {"updatedAt": 1, "docs": []}
	for i in 300:
		big["docs"].push_back({"id": "%032x" % i, "score": i, "playedAt": 1000 + i, "location": "cage"})
	t.ok(SaveCodec.encode(big).size() < SaveCodec.PART_MAX_BYTES / 8, "300 runs gzip well under the cap")
