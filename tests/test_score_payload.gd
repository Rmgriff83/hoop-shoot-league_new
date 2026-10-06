extends RefCounted
## ScorePayload (docs/BACKEND.md → Scores): the run record → wire payload
## mapping and the plausibility gate, verdict for verdict the server's
## (server/test/api.test.ts "plausibility catches each rule").


func _run(over := {}) -> Dictionary:
	var p := {"runId": "9b2c4d6e-1f2a-4b3c-8d9e-0f1a2b3c4d5e", "area": "cage", "score": 20, "makes": 12, "attempts": 20,
		"swishes": 6, "bestStreak": 7, "bonus": 2, "iced": 0, "playedAt": 1791300000000, "version": "test"}
	p.merge(over, true)
	return p


func run(t) -> void:
	var now := 1791300000000
	var run := {"id": "9b2c4d6e-1f2a-4b3c-8d9e-0f1a2b3c4d5e", "score": 31, "makes": 14, "attempts": 22, "swishes": 8,
		"bestStreak": 9, "bonus": 5, "iced": 1, "location": "beach", "playedAt": now, "updatedAt": now + 5}
	var p := ScorePayload.from_run(run, "0.3")
	t.eq(p.keys().size(), ScorePayload.FIELDS.size(), "exactly the wire fields")
	for k in ScorePayload.FIELDS:
		t.ok(p.has(k), "payload has %s" % k)
	t.eq(p["runId"], run["id"], "the run's id is the runId")
	t.eq(p["area"], "beach", "location → area")
	t.eq(p["score"], 31, "score carried")
	t.eq(p["version"], "0.3", "the build version rides along")
	t.eq(ScorePayload.from_run({"id": "9b2c4d6e-1f2a-4b3c-8d9e-0f1a2b3c4d5e", "score": 3}, "x")["area"], "cage", "a run before locations is the cage")
	t.ok(ScorePayload.plausible(p, now), "a real run passes")
	# The gate, rule by rule — the same verdicts as the server.
	t.eq(ScorePayload.why_implausible(_run(), now), "", "the fixture passes")
	t.eq(ScorePayload.why_implausible(_run({"area": "moon"}), now), "area", "an unknown area")
	t.eq(ScorePayload.why_implausible(_run({"attempts": 81}), now), "attempts", "too many shots")
	t.eq(ScorePayload.why_implausible(_run({"makes": 21}), now), "makes", "more makes than shots")
	t.eq(ScorePayload.why_implausible(_run({"swishes": 13}), now), "swishes", "more swishes than makes")
	t.eq(ScorePayload.why_implausible(_run({"bestStreak": 13}), now), "bestStreak", "a streak longer than the makes")
	t.eq(ScorePayload.why_implausible(_run({"score": 61}), now), "score", "more than 5 a make")
	t.eq(ScorePayload.why_implausible(_run({"bonus": 21}), now), "bonus", "more bonus than score")
	t.eq(ScorePayload.why_implausible(_run({"playedAt": now - 3 * 86400000}), now), "playedAt", "played three days ago")
	t.eq(ScorePayload.why_implausible(_run({"playedAt": now - 1 * 86400000}), now), "", "yesterday is fine (the offline outbox)")
	t.eq(ScorePayload.why_implausible(_run({"score": -1}), now), "score", "negative")
	t.eq(ScorePayload.why_implausible(_run({"score": 1.5}), now), "score", "a fraction")
	t.eq(ScorePayload.why_implausible(_run({"score": 20.0}), now), "", "a whole float (JSON) is a count")
	t.eq(ScorePayload.why_implausible(_run({"runId": "nope"}), now), "runId", "a bad id")
	t.eq(ScorePayload.why_implausible(_run({"version": "x".repeat(40)}), now), "version", "a long version string")
	t.eq(ScorePayload.why_implausible(_run({"score": 60, "makes": 12}), now), "", "the cap itself passes")
