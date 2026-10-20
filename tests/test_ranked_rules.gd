extends RefCounted
## The ranked ladder's display rules (docs/BACKEND.md → Ranked): RankedRules
## mirrors server/src/rank.ts over data/ranked.json, pinned to the shared
## tests/fixtures/ranked_ladder.json on both sides; the badge words.


func run(t) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ranked_ladder.json"))
	t.ok(parsed is Dictionary and parsed.has("cases"), "the ladder fixture loads")
	for c in parsed["cases"]:
		var got := RankedRules.band_of(float(c["cons"]))
		t.eq([got["tier"], got["division"]], [str(c["tier"]), int(c["division"])], "cons %s → %s %s" % [c["cons"], c["tier"], c["division"]])
	for c in parsed["conservative"]:
		t.close(RankedRules.conservative(float(c["mu"]), float(c["rd"])), float(c["cons"]), 1e-9, "conservative %s/%s" % [c["mu"], c["rd"]])
	t.eq(RankedRules.tiers().size(), 6, "six tiers")
	t.eq(RankedRules.tier_name("allstar"), "ALL-STAR", "the tier word")
	t.ok(RankedRules.is_top_tier("legend") and not RankedRules.is_top_tier("mvp"), "LEGEND is the top")
	t.eq(RankedRules.badge_text({"tier": "pro", "division": 2, "games": 5}), "PRO II", "a badge")
	t.eq(RankedRules.badge_text({"tier": "legend", "division": 1, "position": 12, "games": 5}), "LEGEND #12", "the top tier shows the position")
	t.eq(RankedRules.badge_text({"tier": "legend", "division": 1, "games": 5}), "LEGEND", "…or just the word without one")
	t.eq(RankedRules.badge_text({}), "UNRANKED", "nothing yet")
	t.eq(RankedRules.division_numeral(3), "III", "III")
	t.ok(RankedRules.outranks({"tier": "pro", "division": 3}, {"tier": "pro", "division": 1}), "division 1 outranks 3")
	t.ok(RankedRules.outranks({"tier": "pro", "division": 1}, {"tier": "allstar", "division": 3}), "a tier up outranks")
	t.ok(not RankedRules.outranks({"tier": "mvp", "division": 2}, {"tier": "mvp", "division": 2}), "equal is not")
	t.eq(int(RankedRules.queue_cfg().get("poll_s", 0)), 4, "the queue poll from data")
	t.eq(int(RankedRules.prematch_cfg().get("seconds", 0)), 20, "the pre-match clock from data")
	# The copy.
	t.eq(MatchCopy.card_online({"rank": {"tier": "pro", "division": 2, "wins": 12, "losses": 9, "games": 21}}), "PRO II · 12-9", "the card's online line")
	t.eq(MatchCopy.card_online({"rank": {"tier": "rookie", "division": 3, "games": 0}}), "ONLINE · UNRANKED", "no rated game yet")
	t.eq(MatchCopy.rank_delta_line({"ranked": true, "rating": {"delta": 18.4}, "rank": {"tier": "pro", "division": 2}, "events": ["promoted"]}), "RATING +18 · PRO II · PROMOTED", "the post-match rank line")
	t.eq(MatchCopy.rank_delta_line({"ranked": true, "rating": {"delta": -7}, "rank": {"tier": "starter", "division": 3}, "events": ["floored"]}), "RATING -7 · STARTER III · FLOOR HELD", "a floored loss")
	t.eq(MatchCopy.rank_delta_line({"ranked": true, "won": false, "reason": "void"}), "RATED · NO CHANGE", "a void")
	t.eq(MatchCopy.rank_delta_line({"ranked": false, "won": true}), "", "nothing for a casual match")
	t.eq(MatchCopy.cap_line(3), "CARD CAP · LVL 3 · THE LOWER LEVEL PLAYS", "the cap line")
	t.eq(MatchCopy.cap_line(3, true), "CARD CAP · LVL 3 · YOUR LEVEL", "…and a league heat's")
