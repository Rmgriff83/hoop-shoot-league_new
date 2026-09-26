class_name CardPolicy
extends RefCounted
## When a bot shooter plays a card (seeded, deterministic). Opponent cards
## (Ice): when the other side is on ≥ 3 straight, or leads by ≥ 4 with under
## 45 s left. Self cards (Fire): once it has a ball in hand and its rim can
## take it. Never in the first 10 s; at most once per card in hand. Returns
## the card id to play or "". Side-agnostic: the AI uses it against the
## player, and the card lab's player bot uses it against the AI.

const MIN_ELAPSED := 10.0


## The AI side's pick (the live game).
static func choose(hand: Array, heat: Heat, rng: DetRng) -> String:
	return choose_for(Heat.AI, hand, heat, rng)


## `side_name`'s pick from its own hand, judged against the other side.
static func choose_for(side_name: String, hand: Array, heat: Heat, rng: DetRng) -> String:
	if hand.is_empty():
		return ""
	var me := heat.side(side_name)
	var other_name := Heat.other_side(side_name)
	var them := heat.side(other_name)
	var elapsed := heat.seconds - me.time_left
	if heat.ot == 0 and elapsed < MIN_ELAPSED:
		return ""
	var lead := them.score - me.score
	var trigger := them.streak >= 3 or (lead >= 4 and them.time_left < 45.0)
	for id in hand:
		var card := CardDefs.get_card(str(id))
		if card.is_empty():
			continue
		var kind := str(card["effect"]["kind"])
		if str(card.get("target", "opponent")) == "self":
			# Boost itself when it is holding a ball (about to shoot).
			if me.holding and CardEffects.can_apply(kind, heat, side_name) and rng.next() < 0.05:
				return str(id)
		elif trigger and CardEffects.can_apply(kind, heat, other_name):
			# A little hesitation so it doesn't fire on the exact frame.
			if rng.next() < 0.35:
				return str(id)
	return ""
