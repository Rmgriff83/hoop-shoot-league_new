extends RefCounted
## The rewards page (game/ui/rewards_page.gd, design 37a's REWARDS view,
## 2026-10-30) off-tree from the fixture answer: DAY n and the ten-day strip,
## the pending rows with CLAIM, the milestone chips with the unlocked ones
## gold, the rank ladder; CLAIM emits once and flips.


func run(t) -> void:
	var fx: Variant = JSON.parse_string(FileAccess.open("res://tests/fixtures/rewards.json", FileAccess.READ).get_as_text())
	t.ok(fx is Dictionary, "the rewards fixture loads")
	var page := RewardsPage.new()
	var root := page.build(fx)
	t.eq((root.find_child("Title", true, false) as Label).text, "REWARDS", "the title")
	t.ok(root.find_child("Back", true, false) is ShadowCard, "< back in the head")
	t.ok(root.find_child("Close", true, false) == null and root.find_child("MeterBar", true, false) == null, "no CLOSE and no drop meter (37a)")
	# LOGIN DAYS: day 3, the next card at 7.
	t.eq(page.login_text(), "DAY 3 · 4 MORE TO A CARD", "DAY n and how far the card is")
	var days := page.login_days()
	t.eq(days.size(), 10, "ten cells")
	t.eq([days[0]["day"], days[9]["day"]], [1, 10], "…days 1 to 10 while the card is in reach")
	t.eq([days[2]["got"], days[3]["got"]], [true, false], "…gold up to today")
	t.eq([days[6]["card"], days[9]["card"], days[4]["card"], days[0]["card"]], [true, true, false, false], "…a star on each card day ahead")
	t.eq(RewardsPage.login_window(25, 30, [1, 3, 7, 10, 30]).map(func(e: Dictionary) -> int: return e["day"]), range(21, 31), "a far card: the ten days ending on it")
	t.eq(RewardsPage.login_window(40, 0, [1, 3, 7, 10, 30])[9], {"day": 40, "got": true, "card": false}, "every card earned: the last ten days, all gold")
	# WAITING FOR YOU.
	t.ok(root.find_child("Grant_login_day_3", true, false) != null and root.find_child("Grant_first_ranked_win", true, false) != null, "two pending rows")
	t.eq(page.pending_count(), 2, "pending count")
	t.eq((root.find_child("Waiting", true, false).find_child("Note", true, false) as Label).text, "2 TO CLAIM", "the waiting note")
	# MILESTONES: the firsts and win counts as chips; the steps on the ladder.
	var gold: RewardsPage.DotBox = root.find_child("Milestone_first_ranked_win", true, false)
	var dim: RewardsPage.DotBox = root.find_child("Milestone_ranked_wins_10", true, false)
	t.ok(gold != null and dim != null, "chips for both")
	t.ok(gold.on and not dim.on, "unlocked gold, locked dim")
	t.ok(root.find_child("Milestone_tier_pro", true, false) == null, "rank steps are not chips")
	var keys := OnlineDrops.all_milestone_keys()
	t.eq((root.find_child("MilestonesSection", true, false).find_child("Note", true, false) as Label).text, "3 / %d" % keys.size(), "the milestone count")
	t.eq(page.ladder(), [["next", "ROOKIE"]], "no step reached: just NEXT")
	var steps := keys.filter(func(k: String) -> bool: return MilestoneCopy.is_step(k))
	t.eq(RewardsPage.ladder_rows(steps, ["tier_rookie", "division_rookie_3", "division_rookie_2", "division_rookie_1", "tier_starter", "division_starter_3"]),
		[["next", "STARTER II"], ["you", "STARTER III"], ["past", "STARTER"], ["past", "ROOKIE I"], ["past", "ROOKIE II"], ["past", "ROOKIE III"], ["past", "ROOKIE"]],
		"the ladder: next, you, then every step below")
	t.eq(RewardsPage.ladder_rows(["tier_mvp", "tier_legend"], ["tier_mvp", "tier_legend"])[0], ["you", "LEGEND"], "at the top: no NEXT")
	# CLAIM.
	var claims := []
	page.claim.connect(func(k: String) -> void: claims.push_back(k))
	var b: ShadowCard = root.find_child("Grant_login_day_3", true, false).find_child("Claim", true, false)
	t.eq(b.text, "CLAIM", "the button says CLAIM")
	b.pressed.emit()
	b.pressed.emit()
	t.eq(claims, ["login_day_3"], "CLAIM emits once")
	t.eq(b.text, "CLAIMED", "…and flips")
	t.ok(b.disabled, "…and is dead")
	t.eq((root.find_child("Waiting", true, false).find_child("Note", true, false) as Label).text, "1 TO CLAIM", "…and the note counts down")
	# Nothing pending, nothing unlocked.
	page.set_data({"pending": [], "unlocked": [], "login_days": 0})
	t.ok(root.find_child("NothingPending", true, false) != null, "the empty line")
	# Many grants, a long name: nothing on the page asks for more width than
	# the frame (Ross saw a wide line push the page right, 2026-10-28).
	var many := []
	for i in 6:
		many.push_back({"key": "division_allstar_%d" % (i % 3 + 1), "kind": "milestone", "card": "fire7"})
	page.set_data({"pending": many, "unlocked": keys, "login_days": 12})
	t.ok(page.body.get_combined_minimum_size().x <= HomePage.FRAME_SIZE.x - 2.0 * HomePage.PAD, "the page never asks for more width than the frame (%.0f)" % page.body.get_combined_minimum_size().x)
	t.ok(page.body.get_combined_minimum_size().y <= HomePage.FRAME_SIZE.y - 2.0 * HomePage.PAD, "…nor more height than the short frame (%.0f)" % page.body.get_combined_minimum_size().y)
	# Offline with nothing cached: the one line.
	var cold := RewardsPage.new()
	cold.build({})
	cold.set_offline()
	t.ok(cold.root.find_child("Offline", true, false) != null, "offline copy when nothing is cached")
	cold.free()
	page.free()
