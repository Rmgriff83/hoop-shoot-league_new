extends RefCounted
## PEGGY, the locker's drop machine (docs/LOCKER.md): the board physics is
## deterministic, lands every drop, never tunnels and has the measured
## shape (edges rarest, aim shifts the mass); the prize rules pay only
## unowned balls, gate rarities by level, promote exhausted plates and refund
## empty ones; the cabinet glb mirrors the board's peg table; the App API
## spends, grants and flags unseen balls.


func run(t) -> void:
	_board(t)
	_prizes(t)
	_economy(t)
	_cabinet(t)
	_app(t)


func _board(t) -> void:
	var a := PeggyBoard.simulate(0.3, 99)
	var b := PeggyBoard.simulate(0.3, 99)
	t.eq(a["slot"], b["slot"], "same seed, same slot")
	t.eq(a["path"], b["path"], "same seed, same path")
	t.eq(a["hits"], b["hits"], "same seed, same hits")
	var c := PeggyBoard.simulate(0.3, 100)
	t.ok(c["path"] != a["path"], "another seed, another path")
	t.ok(a["landed"] and a["duration"] < PeggyBoard.MAX_T, "a drop lands inside the cap (%.2f s)" % a["duration"])
	t.ok(a["hits"].size() >= 6, "a drop rings several pegs (%d)" % a["hits"].size())
	for aim in [0.0, -PeggyBoard.AIM_MAX, PeggyBoard.AIM_MAX]:
		var all_land := true
		for s in 120:
			var r := PeggyBoard.simulate(aim, 500 + s)
			if not r["landed"]:
				all_land = false
		t.ok(all_land, "every drop lands (aim %.1f)" % aim)
	# No tunnelling: with every step sampled the puck is never inside a peg
	# and never jumps further than its own radius between steps.
	var fine := PeggyBoard.simulate(-0.4, 31, true)
	var inside := 0
	var longest := 0.0
	var prev: Array = fine["path"][0]
	for s in fine["path"]:
		for c2 in PeggyBoard.pegs():
			var dx: float = s[0] - c2["x"]
			var dy: float = s[1] - c2["y"]
			if sqrt(dx * dx + dy * dy) < PeggyBoard.PUCK_R + float(c2["r"]) - 1e-6:
				inside += 1
		longest = maxf(longest, absf(s[0] - prev[0]) + absf(s[1] - prev[1]))
		prev = s
	t.eq(inside, 0, "the puck never sits inside a peg")
	t.ok(longest < PeggyBoard.PUCK_R, "no step longer than the puck's radius (%.3f)" % longest)
	t.ok(fine["path"][fine["path"].size() - 1][1] <= PeggyBoard.PUCK_R + 1e-9, "the path ends on the slot floor")
	# Geometry.
	var pegs := PeggyBoard.pegs()
	t.eq(pegs.size(), 81, "55 pegs + 20 bumpers + 6 divider tops")
	t.eq(pegs[0]["kind"], "bumper", "the table starts with row 0's left bumper")
	var pockets := 0
	for i in pegs.size():
		for j in range(i + 1, pegs.size()):
			if pegs[i]["row"] != pegs[j]["row"] or int(pegs[i]["row"]) < 0:
				continue
			var gap: float = absf(float(pegs[i]["x"]) - float(pegs[j]["x"])) - float(pegs[i]["r"]) - float(pegs[j]["r"])
			if gap < 2.0 * PeggyBoard.PUCK_R + 0.05 and gap > -0.01:
				pockets += 1
	t.eq(pockets, 0, "no same-row gap tighter than the puck (wedge pockets)")
	t.eq(PeggyBoard.slot_of(-3.4), 0, "far left is slot 0")
	t.eq(PeggyBoard.slot_of(0.0), 3, "centre is slot 3")
	t.eq(PeggyBoard.slot_of(3.49), 6, "far right is slot 6")
	t.close(PeggyBoard.clamp_aim(-9.0), -PeggyBoard.AIM_MAX, 0.0, "aim clamps to the rail's travel")
	# Odds shape.
	var p := PeggyBoard.odds(0.0, 300)
	var sum := 0.0
	for v in p:
		sum += v
	t.close(sum, 1.0, 1e-9, "odds sum to one")
	t.ok(p[0] + p[6] < p[1] + p[5], "edge slots are rarer than the second pair (%.2f < %.2f)" % [p[0] + p[6], p[1] + p[5]])
	t.ok(p[1] + p[5] < p[2] + p[3] + p[4], "the second pair is rarer than the middle three")
	t.ok(p[3] > 0.18, "the centre slot is the likeliest (%.2f)" % p[3])
	t.ok(p[0] < 0.10 and p[6] < 0.10, "an edge slot from the centre is occasional (%.2f / %.2f)" % [p[0], p[6]])
	var left := PeggyBoard.odds(-PeggyBoard.AIM_MAX, 300)
	t.ok(left[0] + left[1] + left[2] > 0.55, "aiming left shifts the mass left (%.2f)" % (left[0] + left[1] + left[2]))
	t.ok(left[0] > 0.08, "the rail's end makes the near edge reachable (%.2f)" % left[0])
	t.ok(left[0] < 0.30, "but not a sure thing (%.2f)" % left[0])
	var right := PeggyBoard.odds(PeggyBoard.AIM_MAX, 300)
	t.ok(right[6] > 0.08 and right[4] + right[5] + right[6] > 0.55, "mirrored to the right")
	var ro := PeggyBoard.rarity_odds_from(p, PeggyPrizes.layout(3))
	t.close(float(ro["common"]) + float(ro["rare"]) + float(ro["epic"]), 1.0, 1e-9, "rarity odds partition the slots")
	t.ok(float(ro["epic"]) < float(ro["rare"]) and float(ro["rare"]) < float(ro["common"]), "rarer is rarer at level 3")


static func _roster() -> Array:
	var out := []
	var counts := {"common": 5, "rare": 4, "epic": 3, "legend": 2}
	for r in PeggyPrizes.RARITIES:
		for i in int(counts[r]):
			out.push_back({"id": "%s%d" % [r, i], "rarity": r})
	return out


func _prizes(t) -> void:
	t.eq(PeggyPrizes.visible_rarities(1), ["common", "rare"], "level 1 sees common and rare")
	t.eq(PeggyPrizes.visible_rarities(3), ["common", "rare", "epic"], "level 3 adds epic")
	t.eq(PeggyPrizes.visible_rarities(5).size(), 4, "level 5 adds legend")
	t.eq(PeggyPrizes.top_rarity(4), "epic", "top rarity at level 4")
	t.ok(not PeggyPrizes.layout(1).has("epic"), "level 1's plates have no epic")
	t.eq(PeggyPrizes.layout(3)[0], "epic", "level 3's outer plate is epic")
	t.eq(PeggyPrizes.layout(5)[0], "legend", "level 5's outer plate is legend")
	t.eq(PeggyPrizes.layout(5)[3], "common", "the centre plate stays common")
	t.eq(PeggyPrizes.layout(2).size(), 7, "seven plates")
	var balls := _roster()
	var rng := DetRng.new(5)
	t.ok(PeggyPrizes.prize_for("epic", 3, [], balls, rng).begins_with("epic"), "an epic plate pays an epic")
	t.ok(PeggyPrizes.prize_for("epic", 1, [], balls, rng).begins_with("rare"), "below level 3 an 'epic' plate can only pay what the level allows")
	var all_epics := ["epic0", "epic1", "epic2"]
	t.ok(PeggyPrizes.prize_for("epic", 3, all_epics, balls, rng).begins_with("rare"), "epics exhausted at level 3 → the plate falls back to rare")
	t.ok(PeggyPrizes.prize_for("epic", 5, all_epics, balls, rng).begins_with("legend"), "epics exhausted at level 5 → promotes to legend first")
	var all_common := ["common0", "common1", "common2", "common3", "common4"]
	t.ok(PeggyPrizes.prize_for("common", 1, all_common, balls, rng).begins_with("rare"), "commons exhausted → a common plate promotes to rare")
	var everything := []
	for b in balls:
		everything.push_back(b["id"])
	t.eq(PeggyPrizes.prize_for("common", 9, everything, balls, rng), "", "nothing left → empty plate")
	var slots := PeggyPrizes.slots(3, [], balls, DetRng.new(11))
	t.eq(slots.size(), 7, "seven slots")
	t.ok(slots[0]["ball_id"] != slots[6]["ball_id"], "the two outer plates show different balls")
	var ids := []
	for s in slots:
		t.ok(not ids.has(s["ball_id"]), "every plate shows a different ball (%s)" % s["ball_id"])
		ids.push_back(s["ball_id"])
		t.ok(not everything.has("") and str(s["rarity"]) != "", "every plate names its paid rarity")
	t.eq(slots[0]["rarity"], "epic", "outer plate pays epic at level 3")
	t.eq(PeggyPrizes.slots(3, [], balls, DetRng.new(11)), slots, "same seed, same plates")
	var owned_mix := all_common + ["rare0", "rare1"]
	var promoted := PeggyPrizes.slots(1, owned_mix, balls, DetRng.new(2))
	t.eq(promoted[3]["base"], "common", "a centre plate's base stays common")
	t.eq(promoted[3]["rarity"], "rare", "…but it pays rare once the commons are gone")
	var shown := {}
	for s in promoted:
		shown[s["ball_id"]] = true
	t.eq(shown.size(), 2, "two balls left → both are shown, repeated across the plates")
	var last := PeggyPrizes.slots(1, all_common + ["rare0", "rare1", "rare2"], balls, DetRng.new(2))
	for s in last:
		t.eq(s["ball_id"], "rare3", "the last ball sits on every plate")
	var low_done := PeggyPrizes.slots(1, all_common + ["rare0", "rare1", "rare2", "rare3"], balls, DetRng.new(2))
	t.eq(low_done[0]["ball_id"], "", "everything the level allows owned → empty plates")
	t.eq(PeggyPrizes.refund(low_done[0]), PeggyPrizes.REFUND, "an empty plate refunds")
	t.eq(PeggyPrizes.refund(slots[0]), 0, "a prize plate does not")
	# Expected cost of the whole roster: at least one drop per ball, and
	# finite; -1 when the level cannot complete it.
	var p := PackedFloat64Array([0.04, 0.09, 0.23, 0.28, 0.23, 0.09, 0.04])
	var cost := PeggyPrizes.expected_tickets_to_complete(p, balls, ["common0"], 99, 40)
	t.ok(cost >= 13 * PeggyPrizes.DROP_COST, "collecting 13 balls costs at least 13 drops (%.0f)" % cost)
	t.ok(cost < 13 * PeggyPrizes.DROP_COST * 1.25, "…and not much more (%.0f)" % cost)
	t.ok(PeggyPrizes.expected_tickets_to_complete(p, balls, [], 1, 10) > 0.0, "level 1 collects its commons and rares")


func _economy(t) -> void:
	pass


func _cabinet(t) -> void:
	var scene: PackedScene = load(PeggyMachine.GLB)
	t.ok(scene != null, "the cabinet glb loads (tools/blender/build_peggy.py)")
	if scene == null:
		return
	var root: Node = scene.instantiate()
	for n in ["Puck", "Carriage", "BtnCap", "Ticket", "Glass", "Rail", "EndStopL", "EndStopR", "MarqueeFace"]:
		t.ok(root.find_child(n, true, false) != null, "cabinet has %s" % n)
	for i in 18:
		t.ok(root.find_child("Bulb%03d" % i, true, false) != null, "marquee bulb %d" % i)
	for i in 7:
		for pre in ["SlotPlate", "SlotLight", "Prize", "Frost"]:
			t.ok(root.find_child("%s%d" % [pre, i], true, false) != null, "slot %d has its %s" % [i, pre])
	# Every circle of the core's board is a mesh at the same place (1 u = 0.1 m,
	# the slot floor at BOARD_Y0): the sim and the cabinet never drift apart.
	var table := PeggyBoard.pegs()
	var counts := {"peg": 0, "bumper": 0, "divider": 0}
	var worst := 0.0
	for c in table:
		var kind := str(c["kind"])
		var nm := "%s%03d" % [kind.capitalize(), int(counts[kind])] if kind != "divider" else "Divider%d" % int(counts[kind])
		counts[kind] += 1
		var n: Node3D = root.find_child(nm, true, false)
		t.ok(n != null, "cabinet has %s" % nm)
		if n == null:
			continue
		var want := Vector3(float(c["x"]) * PeggyMachine.U, PeggyMachine.BOARD_Y0 + float(c["y"]) * PeggyMachine.U, 0.0)
		var got := n.position
		got.z = 0.0
		worst = maxf(worst, got.distance_to(want))
	t.eq(counts, {"peg": 55, "bumper": 20, "divider": 6}, "55 pegs, 20 bumpers, 6 dividers in the glb")
	t.ok(worst < 0.001, "every peg sits where the core says (worst %.4f m)" % worst)
	root.free()
	# The machine control builds headless and maps hits onto meshes.
	var m := PeggyMachine.new()
	t.eq(m.peg_count(), 81, "the machine bound every peg")
	var balls := EconomyBudget.peggy_roster()
	m.set_slots(PeggyPrizes.slots(5, ["classic"], balls, DetRng.new(3)))
	t.eq(m.slots().size(), 7, "plates set")
	m.set_aim(5.0)
	t.close(m.aim(), PeggyBoard.AIM_MAX, 0.0, "the aim clamps to the rail's travel")
	m.nudge(-0.25)
	t.close(m.aim(), PeggyBoard.AIM_MAX - 0.25, 1e-9, "nudging moves the aim")
	t.ok(not m.playing(), "idle until a drop")
	m.free()
	var rays := PrizeRays.new(Color.RED)
	rays._process(0.5)
	t.close(rays.angle(), deg_to_rad(PrizeRays.SPEED_DEG) * 0.5, 1e-6, "the rays turn %d°/s" % int(PrizeRays.SPEED_DEG))
	rays.free()


func _app(t) -> void:
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		return
	var cos_before: Dictionary = SaveService.get_cosmetics()
	var set_before: Dictionary = SaveService.get_settings()
	var c := cos_before.duplicate(true)
	c["tickets"] = 0
	c["ball"] = {"selected": "classic", "owned": ["classic"]}
	c["peggy"] = {"drops": 0}
	SaveService.put_cosmetics(c)
	var st := set_before.duplicate(true)
	st["newBalls"] = []
	SaveService.put_settings(st)
	t.ok(not app.spend_tickets(300), "spending 300 with 0 tickets fails")
	t.eq(app.peggy_drop(0.0), {}, "a drop with no tickets does nothing")
	t.eq(app.drop_count(), 0, "…and the drop index stays")
	app.grant_tickets(299)
	t.eq(app.peggy_drop(0.0), {}, "299 tickets is one short")
	app.grant_tickets(1)
	t.ok(app.spend_tickets(100), "spending inside the balance works")
	t.eq(app.tickets(), 200, "…and it is deducted")
	app.grant_tickets(400)
	t.ok(not app.try_buy("ball", "gold"), "balls cannot be bought")
	t.eq(app.owned_count("ball"), 1, "a fresh save owns the starter only")
	var plates: Array = app.peggy_slots()
	t.eq(plates.size(), 7, "seven plates on the board")
	var shown := []
	for p in plates:
		t.ok(not app.owns("ball", str(p["ball_id"])), "plate shows an unowned ball (%s)" % p["ball_id"])
		shown.push_back(p["ball_id"])
	t.eq(app.peggy_slots(), plates, "the plates are stable until a drop happens")
	t.ok(app.peggy_seed(0) != app.peggy_seed(1), "each drop has its own seed")
	var prize: Dictionary = app.peggy_drop(0.3)
	t.ok(not prize.is_empty(), "a funded drop pays")
	t.eq(app.tickets(), 300, "the drop cost 300")
	t.eq(app.drop_count(), 1, "the drop index moved")
	t.ok(shown.has(prize["ball_id"]), "the prize was one of the plates shown (%s)" % prize["ball_id"])
	t.ok(app.owns("ball", str(prize["ball_id"])), "the prize is owned now")
	t.eq(app.unseen_balls(), [prize["ball_id"]], "the new ball is unseen")
	t.eq(app.last_prize, prize, "last_prize holds the record for the pop-up")
	t.ok(prize["result"]["landed"], "the drop's path landed")
	var second: Dictionary = app.peggy_drop(0.0)
	t.ok(second["ball_id"] != prize["ball_id"], "no duplicates: the second drop pays another ball")
	t.eq(app.owned_count("ball"), 3, "two wins and the starter")
	t.eq(app.unseen_balls().size(), 2, "both unseen")
	app.mark_balls_seen()
	t.eq(app.unseen_balls(), [], "the BALLS tab clears the flag")
	t.ok(not app.grant_cosmetic("ball", str(prize["ball_id"])), "granting an owned ball is refused")
	t.ok(app.grant_cosmetic("hoop", "street"), "a hoop can be granted too")
	t.ok(app.owns("hoop", "street") and app.unseen_balls().is_empty(), "…without flagging a ball")
	SaveService.put_cosmetics(cos_before)
	SaveService.put_settings(set_before)
