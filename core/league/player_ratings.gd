class_name PlayerRatings
extends RefCounted
## The player's rolling self-sim ratings (ported from playerRatings.ts): an
## EWMA of their own live heats, used by QuickSim when they sim a day.

const ALPHA := 0.25
const BASELINE := {"accuracy": 0.45, "swishRate": 0.35}


static func init_self() -> Dictionary:
	return {"accuracy": BASELINE["accuracy"], "swishRate": BASELINE["swishRate"], "gamesPlayed": 0}


## Fold one live heat in: game = {makes, swishes, shots}.
static func update_self(self_: Dictionary, game: Dictionary) -> void:
	var shots := int(game.get("shots", 0))
	if shots == 0:
		return
	var make_rate := float(game.get("makes", 0)) / shots
	var swish_share := (float(game.get("swishes", 0)) / int(game["makes"])) if int(game.get("makes", 0)) > 0 else 0.0
	self_["accuracy"] = float(self_["accuracy"]) + ALPHA * (make_rate - float(self_["accuracy"]))
	self_["swishRate"] = float(self_["swishRate"]) + ALPHA * (swish_share - float(self_["swishRate"]))
	self_["gamesPlayed"] = int(self_.get("gamesPlayed", 0)) + 1


## Full AiRatings so QuickSim can treat the player like any shooter (inverts
## the empirical swish-share formula share ≈ 0.05 + 0.3·acc·swishRate).
static func as_ai(self_: Dictionary) -> AiRatings:
	var acc := float(self_["accuracy"])
	var swish := clampf((float(self_["swishRate"]) - 0.05) / maxf(0.3 * acc, 0.05), 0.05, 0.95)
	return AiRatings.make(acc, swish, 4.0, 0.6, 0.4, 0.75)
