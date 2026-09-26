extends RefCounted
## StreakRules: the points table, the swish bonus, fire threshold, next tier.


func run(t) -> void:
	var expected := {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 2, 7: 2, 8: 3, 9: 3, 10: 3, 11: 4, 12: 4, 30: 4}
	for n in expected:
		var streak: int = n
		t.eq(StreakRules.base_points(streak), expected[n], "base points at %d straight" % streak)
		t.eq(StreakRules.points_for(streak, false), expected[n], "make at %d straight" % streak)
		t.eq(StreakRules.points_for(streak, true), int(expected[n]) + 1, "swish at %d straight" % streak)
	t.ok(not StreakRules.is_lit(4), "not lit at 4")
	t.ok(StreakRules.is_lit(5), "lit at 5")
	t.ok(StreakRules.is_lit(40), "still lit at 40")
	t.eq(StreakRules.next_tier(0), {"at": 5, "points": 1}, "next from 0 is the fire")
	t.eq(StreakRules.next_tier(5), {"at": 6, "points": 2}, "next from 5")
	t.eq(StreakRules.next_tier(7), {"at": 8, "points": 3}, "next from 7")
	t.eq(StreakRules.next_tier(10), {"at": 11, "points": 4}, "next from 10")
	t.eq(StreakRules.next_tier(11), {}, "no tier above the top")
	t.eq(StreakRules.next_tier(25), {}, "no tier above the top (deep)")
	t.eq(StreakRules.COLD_AT, 7, "ice at 7 misses")
	t.eq(StreakRules.ICE_BREAK_HITS, 3, "three rim hits break the ice")
