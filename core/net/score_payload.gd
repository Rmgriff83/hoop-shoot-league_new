class_name ScorePayload
extends RefCounted
## A finished time trial as the leaderboard server takes it (docs/BACKEND.md
## → Scores), and the plausibility gate the server applies — mirrored here by
## hand (server/src/rules.ts) so the suite proves both sides agree and the
## game never queues a run the server would bounce. Pure: no nodes, no net.

const AREAS := ["cage", "beach", "city"]
## A 60 s trial with a ball return never gets more shots off than this.
const MAX_ATTEMPTS := 80
## The hottest make pays 4 + 1 for the swish (core/match/streak_rules.gd).
const MAX_POINTS_PER_MAKE := 5
## How far a run's playedAt may sit from the server clock (the offline outbox).
const PLAYED_AT_SLACK_MS := 2 * 24 * 3600 * 1000
const FIELDS := ["runId", "area", "score", "makes", "attempts", "swishes", "bestStreak", "bonus", "iced", "playedAt", "version"]


## The wire payload for a saved run record (SaveService.put_score's doc).
static func from_run(run: Dictionary, version: String) -> Dictionary:
	return {
		"runId": str(run.get("id", "")),
		"area": str(run.get("location", "cage")),
		"score": int(run.get("score", 0)),
		"makes": int(run.get("makes", 0)),
		"attempts": int(run.get("attempts", 0)),
		"swishes": int(run.get("swishes", 0)),
		"bestStreak": int(run.get("bestStreak", 0)),
		"bonus": int(run.get("bonus", 0)),
		"iced": int(run.get("iced", 0)),
		"playedAt": int(run.get("playedAt", 0)),
		"version": version,
	}


## The field that makes the payload impossible, or "" when it passes. The
## same checks, in the same order, as the server's `plausible`.
static func why_implausible(p: Dictionary, now_ms: int) -> String:
	if not _is_uuid(str(p.get("runId", ""))):
		return "runId"
	if not AREAS.has(str(p.get("area", ""))):
		return "area"
	for k in ["score", "makes", "attempts", "swishes", "bestStreak", "bonus", "iced"]:
		if not _is_count(p.get(k)):
			return k
	if not (p.get("version") is String) or str(p["version"]).length() > 32:
		return "version"
	if not _is_count(p.get("playedAt")):
		return "playedAt"
	if int(p["attempts"]) > MAX_ATTEMPTS:
		return "attempts"
	if int(p["makes"]) > int(p["attempts"]):
		return "makes"
	if int(p["swishes"]) > int(p["makes"]):
		return "swishes"
	if int(p["bestStreak"]) > int(p["makes"]):
		return "bestStreak"
	if int(p["score"]) > int(p["makes"]) * MAX_POINTS_PER_MAKE:
		return "score"
	if int(p["bonus"]) > int(p["score"]):
		return "bonus"
	if absi(int(p["playedAt"]) - now_ms) > PLAYED_AT_SLACK_MS:
		return "playedAt"
	return ""


static func plausible(p: Dictionary, now_ms: int) -> bool:
	return why_implausible(p, now_ms) == ""


static func _is_count(v: Variant) -> bool:
	if v is int:
		return int(v) >= 0
	if v is float:   # JSON round-trips ints as floats
		return float(v) >= 0.0 and float(v) == floorf(float(v))
	return false


static func _is_uuid(s: String) -> bool:
	var re := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	return re.search(s) != null
