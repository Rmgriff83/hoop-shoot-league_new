class_name AiRatings
extends RefCounted
## Difficulty/performance ratings of an AI shooter (ported from
## src/core/ai/types.ts). All 0..1 except pace (seconds per shot cycle).
## Ratings tune the *magnitude* of physical aim error — never outcomes.

var accuracy := 0.5      # base make probability → speed-error sigma
var swish_rate := 0.5    # of makes, share that are clean → launch-angle window
var pace := 4.0          # seconds per shot cycle
var composure := 0.5     # performance shift under pressure
var streakiness := 0.5   # hot/cold variance vs. metronome
var consistency := 0.75  # game-to-game clustering


static func make(p_accuracy: float, p_swish_rate: float, p_pace := 4.0, p_composure := 0.5,
		p_streakiness := 0.0, p_consistency := 1.0) -> AiRatings:
	var r := AiRatings.new()
	r.accuracy = p_accuracy
	r.swish_rate = p_swish_rate
	r.pace = p_pace
	r.composure = p_composure
	r.streakiness = p_streakiness
	r.consistency = p_consistency
	return r


static func from_dict(d: Dictionary) -> AiRatings:
	return make(float(d.get("accuracy", 0.5)), float(d.get("swishRate", d.get("swish_rate", 0.5))),
		float(d.get("pace", 4.0)), float(d.get("composure", 0.5)),
		float(d.get("streakiness", 0.5)), float(d.get("consistency", 0.75)))


func to_dict() -> Dictionary:
	return {"accuracy": accuracy, "swishRate": swish_rate, "pace": pace, "composure": composure,
		"streakiness": streakiness, "consistency": consistency}
