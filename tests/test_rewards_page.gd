extends RefCounted
## The rewards page (game/ui/rewards_page.gd) off-tree from the fixture
## answer: the meter line, the pending rows with CLAIM, the login line, the
## milestone grid with the unlocked ones gold; CLAIM emits once and flips.


func run(t) -> void:
	var fx: Variant = JSON.parse_string(FileAccess.open("res://tests/fixtures/rewards.json", FileAccess.READ).get_as_text())
	t.ok(fx is Dictionary, "the rewards fixture loads")
	var page := RewardsPage.new()
	var root := page.build(fx)
	t.eq((root.find_child("Title", true, false) as Label).text, "REWARDS", "the title")
	t.eq(page.meter_text(), "METER 14/22 · 82% COMMON · 18% RARE", "the meter line from the answer")
	t.close((root.find_child("MeterFill", true, false) as ColorRect).anchor_right, 14.0 / 22.0, 1e-6, "the bar's fill")
	t.ok(root.find_child("Grant_login_day_3", true, false) != null and root.find_child("Grant_first_ranked_win", true, false) != null, "two pending rows")
	t.eq(page.pending_count(), 2, "pending count")
	t.eq((root.find_child("LoginLine", true, false) as Label).text, "LOGIN DAYS · 3 · NEXT CARD AT DAY 7", "the login line")
	var gold: Label = root.find_child("Milestone_first_ranked_win", true, false)
	var dim: Label = root.find_child("Milestone_ranked_wins_10", true, false)
	t.ok(gold != null and dim != null, "the milestone grid lists both")
	t.ok(gold.text.begins_with("+ ") and dim.text.begins_with("- "), "unlocked marked, locked not")
	t.ok(dim.modulate.a < 1.0 and gold.modulate.a == 1.0, "the locked one is dim")
	var claims := []
	page.claim.connect(func(k: String) -> void: claims.push_back(k))
	var b: ShadowCard = root.find_child("Grant_login_day_3", true, false).find_child("Claim", true, false)
	t.eq(b.text, "CLAIM", "the button says CLAIM")
	b.pressed.emit()
	b.pressed.emit()
	t.eq(claims, ["login_day_3"], "CLAIM emits once")
	t.eq(b.text, "CLAIMED", "…and flips")
	t.ok(b.disabled, "…and is dead")
	# Nothing pending, nothing unlocked.
	page.set_data({"pending": [], "unlocked": [], "login_days": 0, "meter": {"progress": 0, "size": 22, "odds": {"common": 1.0, "rare": 0.0, "epic": 0.0}}})
	t.ok(root.find_child("NothingPending", true, false) != null, "the empty line")
	t.eq(page.meter_text(), "METER 0/22 · 100% COMMON", "an empty meter")
	# Three odds (EPIC in the pool) ran the line, and the whole page, off the
	# right of the screen (Ross, 2026-10-28): it breaks after METER n/n, and
	# nothing on the page asks for more width than the frame has.
	page.set_data({"pending": [], "unlocked": [], "login_days": 5, "meter": {"progress": 14, "size": 22, "odds": {"common": 0.75, "rare": 0.22, "epic": 0.03}}})
	t.eq(page.meter_text(), "METER 14/22\n75% COMMON · 22% RARE · 3% EPIC", "a wide meter line breaks after the count")
	t.ok(page.body.get_combined_minimum_size().x <= HomePage.FRAME_SIZE.x - 2.0 * HomePage.PAD, "the page never asks for more width than the frame (%.0f)" % page.body.get_combined_minimum_size().x)
	t.ok(page.body.size.x <= HomePage.FRAME_SIZE.x - 2.0 * HomePage.PAD, "…and the body stays inside it (%.0f)" % page.body.size.x)
	# Offline with nothing cached: the one line.
	var cold := RewardsPage.new()
	cold.build({})
	cold.set_offline()
	t.ok(cold.root.find_child("Offline", true, false) != null, "offline copy when nothing is cached")
	cold.free()
	page.free()
