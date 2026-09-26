class_name AiMood
extends RefCounted
## Per-game mutable mood (ported from src/core/ai/mood.ts): a two-state
## hot/cold Markov chain plus a per-game form offset. Everything lands as a
## shift on *effective accuracy*, which AimError converts to physical error.

var streak_state := 1      # +1 hot, -1 cold
var game_offset := 0.0     # drawn at tip-off from (1 - consistency)


static func init_mood(ratings: AiRatings, rng: DetRng) -> AiMood:
	var m := AiMood.new()
	m.streak_state = 1 if rng.next() < 0.5 else -1
	m.game_offset = (1.0 - ratings.consistency) * 0.08 * rng.normal()
	return m


## Advance the hot/cold chain after each shot. Stickiness ∝ streakiness.
func update(ratings: AiRatings, rng: DetRng) -> void:
	var stay := 0.5 + 0.45 * ratings.streakiness
	if rng.next() > stay:
		streak_state = -1 if streak_state == 1 else 1


## Effective accuracy for this shot with mood and pressure applied.
## situation: {"score_diff": own − opponent, "time_left": s}
static func effective_accuracy(ratings: AiRatings, mood: AiMood, situation: Dictionary) -> float:
	var acc := ratings.accuracy
	acc += mood.game_offset
	acc += float(mood.streak_state) * 0.06 * ratings.streakiness
	var pressure := clampf(-float(situation.get("score_diff", 0)) / 10.0, 0.0, 1.0)
	acc += (ratings.composure - 0.5) * 0.1 * pressure
	return clampf(acc, 0.05, 0.97)
