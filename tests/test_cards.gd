extends RefCounted
## Power-up cards: definitions, inventory/loadout, consumption, effects on a
## Heat (Ice on either side follows the cold-streak rules), the AI policy,
## reward rolls.


func _tick(h: Heat, seconds: float) -> void:
	for i in ceili(seconds / SimConstants.SIM_DT):
		h.tick(SimConstants.SIM_DT)


func run(t) -> void:
	t.eq(CardDefs.validate(), PackedStringArray(), "card data validates")
	t.ok(not CardDefs.get_card("ice").is_empty(), "ice card exists")
	t.ok(CardDefs.get_card("nope").is_empty(), "unknown card → empty")
	t.ok(not CardDefs.get_card("fire7").is_empty(), "fire7 card exists")
	t.eq(CardDefs.target_of("fire7"), "self", "fire is a self card")
	t.eq(CardDefs.target_of("ice"), "opponent", "ice is an opponent card")
	t.eq(CardDefs.target_of("nope"), "opponent", "unknown → opponent")
	t.eq(Progression.card_level(CardDefs.get_card("ice")), 1, "Deep Freeze is a level-1 card")
	t.eq(Progression.card_level(CardDefs.get_card("fire7")), 3, "Heat Check is level 3")
	_run_art(t)
	# The save doc: one bucket per league (docs/ECONOMY.md).
	var full := CardDefs.empty_doc()
	t.eq(full["v"], CardDefs.DOC_VERSION, "fresh doc carries the version")
	t.eq(full["leagues"], {}, "no buckets until a league is touched")
	var cage := CardDefs.league_doc(full, "cage")
	t.eq(full["leagues"].keys(), ["cage"], "touching a league creates its bucket")
	t.eq(int(cage["coins"]), 0, "a bucket starts with no coins")
	CardDefs.add(cage, "ice", 2)
	t.eq(CardDefs.count(CardDefs.league_doc(full, "cage"), "ice"), 2, "the bucket is a live reference into the doc")
	t.eq(CardDefs.count(CardDefs.league_doc(full, "beach"), "ice"), 0, "cage cards never show in the beach bucket")
	t.eq(CardDefs.coins(full, "beach"), 0, "coins are per league too")
	# Inventory + loadout on a bucket: slots hold real copies, played cards empty their slot.
	var d := CardDefs.empty_bucket()
	t.eq(CardDefs.loadout_ids(d), [], "empty hand")
	t.ok(not CardDefs.equip(d, 0, "ice"), "cannot equip an unowned card")
	CardDefs.add(d, "ice", 2)
	t.eq(CardDefs.count(d, "ice"), 2, "two spare ice cards")
	t.ok(CardDefs.equip(d, 0, "ice"), "equip slot 0")
	t.eq(CardDefs.count(d, "ice"), 1, "equipping takes a copy out of the inventory")
	t.eq(CardDefs.owned(d, "ice"), 2, "still two owned")
	t.ok(CardDefs.equip(d, 2, "ice"), "equip slot 2")
	t.eq(CardDefs.count(d, "ice"), 0, "no spares left")
	t.ok(not CardDefs.equip(d, 1, "ice"), "a third slot needs a third copy")
	t.ok(not CardDefs.equip(d, 3, "ice"), "slot 3 does not exist")
	t.eq(CardDefs.loadout_ids(d), ["ice", "ice"], "hand lists equipped cards")
	t.eq(CardDefs.loadout_slots(d), ["ice", null, "ice"], "slots keep their positions")
	t.ok(not CardDefs.consume_slot(d, 1, "ice"), "an empty slot cannot be played")
	t.ok(CardDefs.consume_slot(d, 0, "ice"), "play slot 0")
	t.eq(CardDefs.loadout_slots(d), [null, null, "ice"], "the played card's slot empties")
	t.eq(CardDefs.count(d, "ice"), 0, "nothing returns to the inventory on play")
	t.eq(CardDefs.owned(d, "ice"), 1, "one owned after the play")
	CardDefs.unequip(d, 2)
	t.eq(d["loadout"][2], null, "unequip clears the slot")
	t.eq(CardDefs.count(d, "ice"), 1, "unequip returns the copy")
	t.ok(not CardDefs.consume(d, "ice"), "nothing equipped → nothing to play")
	CardDefs.add(d, "ice", 1)
	CardDefs.equip(d, 2, "ice")
	t.ok(CardDefs.consume(d, "ice"), "consume by id finds the slot")
	t.eq(CardDefs.loadout_slots(d), [null, null, null], "and empties it")
	t.ok(CardDefs.equip(d, 1, "ice"), "re-equip")
	t.ok(CardDefs.equip(d, 1, "ice") == false, "same slot again needs a spare")
	CardDefs.add(d, "ice", 1)
	t.ok(CardDefs.equip(d, 1, "ice"), "replace the slot's copy")
	t.eq(CardDefs.count(d, "ice"), 1, "the replaced copy went back to the inventory")
	# Older docs (one global inventory, one global wallet) are wiped: the
	# economy is per league now.
	var old := {"updatedAt": 0, "v": 2, "inventory": {"ice": 3}, "loadout": ["ice", null, "ice"]}
	t.ok(CardDefs.migrate(old), "a v2 doc migrates")
	t.eq(old["v"], CardDefs.DOC_VERSION, "stamped v3")
	t.eq(old.get("leagues", null), {}, "…as an empty per-league doc")
	t.ok(not old.has("inventory"), "the global inventory is gone")
	t.ok(not CardDefs.migrate(old), "migrate is idempotent")
	var v1 := {"updatedAt": 0, "inventory": {"ice": 1}, "loadout": ["ice", "ice", "ice"]}
	t.ok(CardDefs.migrate(v1) and v1["leagues"] == {}, "a v1 doc is wiped the same way")
	# Heat: the player ices the AI; the effect refuses a second time.
	var geo := SimGeometry.arcade()
	var h := Heat.new({"geo": geo, "seconds": 30.0, "ai": AiRatings.make(0.9, 0.9, 2.0), "seed": 5,
		"calib_key": "arcade", "player_cards": ["ice", "ice"], "ai_cards": []})
	_tick(h, TimeTrial.COUNTDOWN_SECONDS + 0.1)
	t.ok(h.can_play(Heat.PLAYER, "ice"), "ice playable at the start")
	t.ok(h.play_card(Heat.PLAYER, "ice"), "ice applied to the AI")
	t.ok(h.ai.iced and h.ai.geo.ice, "AI rim iced")
	t.eq(h.hands[Heat.PLAYER].size(), 1, "one card left in hand")
	t.ok(not h.can_play(Heat.PLAYER, "ice"), "cannot ice an iced rim")
	t.ok(not h.play_card(Heat.PLAYER, "ice"), "second ice refused")
	t.eq(h.hands[Heat.PLAYER].size(), 1, "refused card not consumed")
	h.tick(SimConstants.SIM_DT)
	var played := 0
	for ev in h.drain_events():
		if ev["kind"] == "card_played":
			played += 1
			t.eq(ev["target"], Heat.AI, "card targets the AI")
	t.eq(played, 2, "two card_played events (one ok, one refused)")
	# The AI must break it: it will (sharpshooter) — a swish through or a catch.
	_tick(h, 20.0)
	var kinds := []
	for ev in h.drain_events():
		if ev.get("side", "") == Heat.AI and ev["kind"] in ["ice_break", "ice_caught"]:
			kinds.push_back(ev["kind"])
	t.ok(kinds.has("ice_break"), "AI broke the ice under the cold-streak rules (%s)" % str(kinds))
	t.eq(h.result().get("sides", {}).get("player", {}).get("cardsPlayed", []) if h.done else h.cards_played[Heat.PLAYER], ["ice"], "cards played recorded")
	# AI policy: it plays Ice when the player streaks, never in the first 10 s, once per card.
	var h2 := Heat.new({"geo": geo, "seconds": 60.0, "ai": AiRatings.make(0.5, 0.5, 3.0), "seed": 9,
		"calib_key": "arcade", "player_cards": [], "ai_cards": ["ice"]})
	_tick(h2, TimeTrial.COUNTDOWN_SECONDS + 0.1)
	h2.player.streak = 4
	_tick(h2, 5.0)
	t.eq(h2.hands[Heat.AI].size(), 1, "AI holds its card in the first 10 s")
	_tick(h2, 8.0)
	t.ok(h2.player.iced, "AI iced the streaking player once allowed")
	t.eq(h2.hands[Heat.AI].size(), 0, "AI card consumed")
	var ai_played := 0
	for ev in h2.drain_events():
		if ev["kind"] == "card_played" and ev["side"] == Heat.AI:
			ai_played += 1
	t.eq(ai_played, 1, "AI played exactly once")
	# Fire card: acts on the side that plays it; the AI plays its own on itself.
	var h3 := Heat.new({"geo": geo, "seconds": 60.0, "ai": AiRatings.make(0.9, 0.9, 2.0), "seed": 11,
		"calib_key": "arcade", "player_cards": ["fire7"], "ai_cards": ["fire7"]})
	t.ok(not h3.can_play(Heat.PLAYER, "fire7"), "fire not playable in the countdown")
	_tick(h3, TimeTrial.COUNTDOWN_SECONDS + 0.1)
	t.ok(h3.can_play(Heat.PLAYER, "fire7"), "fire playable once running")
	t.ok(h3.play_card(Heat.PLAYER, "fire7"), "fire applied")
	t.ok(h3.player.fire_card, "player's own rim burns")
	t.eq(h3.player.streak, StreakRules.FIRE_AT, "player streak at FIRE_AT")
	t.ok(not h3.ai.fire_card, "AI rim untouched")
	t.eq(h3.hands[Heat.PLAYER].size(), 0, "fire card consumed")
	h3.tick(SimConstants.SIM_DT)
	var targets := []
	for ev in h3.drain_events():
		if ev["kind"] == "card_played":
			targets.push_back(ev["target"])
	t.eq(targets, [Heat.PLAYER], "fire card targets its player")
	_tick(h3, 30.0)
	t.eq(h3.hands[Heat.AI].size(), 0, "AI played its fire card")
	var ai_fire := false
	for ev in h3.drain_events():
		if ev["kind"] == "card_played" and ev["side"] == Heat.AI:
			ai_fire = ev["target"] == Heat.AI and ev["ok"]
	t.ok(ai_fire, "AI's fire card lit its own rim")
	# Rewards: deterministic, within odds.
	t.eq(CardRewards.roll(true, false, 77), CardRewards.roll(true, false, 77), "roll replays from the seed")
	var wins := 0
	var losses := 0
	for i in 2000:
		if CardRewards.roll(true, false, i) != "":
			wins += 1
		if CardRewards.roll(false, false, 100000 + i) != "":
			losses += 1
	t.ok(absf(wins / 2000.0 - 0.6) < 0.05, "win drop rate ≈ 60 %% (%.3f)" % (wins / 2000.0))
	t.ok(absf(losses / 2000.0 - 0.25) < 0.05, "loss drop rate ≈ 25 %% (%.3f)" % (losses / 2000.0))
	var ids := {}
	for i in 2000:
		var id := CardRewards.roll(true, false, 5000 + i)
		if id != "":
			ids[id] = int(ids.get(id, 0)) + 1
	t.ok(ids.has("ice") and ids.has("fire7"), "both cards drop (%s)" % str(ids))
	t.ok(int(ids.get("fire7", 0)) > int(ids.get("ice", 0)), "the common fire card drops more often than the rare ice")
	for id in ids:
		t.ok(not CardDefs.get_card(str(id)).is_empty(), "drops are real card ids")
	# The policy is side-agnostic: a player bot plays its ice on the streaking AI.
	# (A sharpshooter AI, so the streak it is handed survives its own shots.)
	var h4 := Heat.new({"geo": geo, "seconds": 60.0, "ai": AiRatings.make(0.95, 0.9, 3.0), "player_bot": AiRatings.make(0.5, 0.5, 3.0),
		"seed": 13, "calib_key": "arcade", "player_cards": ["ice"], "ai_cards": []})
	_tick(h4, TimeTrial.COUNTDOWN_SECONDS + 0.1)
	h4.ai.streak = 4
	_tick(h4, 5.0)
	t.eq(h4.hands[Heat.PLAYER].size(), 1, "player bot holds its card in the first 10 s")
	h4.ai.streak = maxi(h4.ai.streak, 4)
	_tick(h4, 8.0)
	t.ok(h4.ai.iced or h4.ai.times_iced > 0, "player bot iced the streaking AI once allowed")
	t.eq(h4.hands[Heat.PLAYER].size(), 0, "player bot's card consumed")
	t.eq(h4.cards_played[Heat.PLAYER], ["ice"], "recorded on the player side")
	# The card lab: seeded, paired, and it says whether the card was played.
	var short_league := LeagueData.league("cage").duplicate(true)
	short_league["heat_seconds"] = 15
	short_league["ot_seconds"] = 5
	var m := CardLab.measure("ice", short_league, 2, 99)
	t.eq(int(m["n"]), 2, "lab reports its n")
	t.ok(m.has("power") and m.has("se") and m.has("with") and m.has("without") and m.has("played"), "lab result shape")
	t.ok(float(m["se"]) >= 0.0, "standard error is non-negative")
	t.ok(float(m["played"]) >= 0.0 and float(m["played"]) <= 1.0, "played is a share")
	t.eq(CardLab.measure("ice", short_league, 2, 99), m, "lab replays from its seed")
	var both := CardLab.measure_all(["ice", "fire7"], short_league, 2, 99)
	t.close(float(both["ice"]["without"]), float(m["without"]), 1e-9, "one control heat per seed serves every card")


## The faces and their loops (design "Card Icons" 9a): every file exists,
## the sheet is `frames` frames of the sprite rect side by side, the chip
## sprite fits, and the frame clock steps and wraps.
func _run_art(t) -> void:
	for c in CardDefs.all():
		var id := str(c["id"])
		t.eq(CardDefs.validate_fx(c), PackedStringArray(), "%s fx row validates" % id)
		var fx: Dictionary = c["fx"]
		for key in ["art", "fx/sheet", "fx/glyph"]:
			var path := str(c["art"]) if key == "art" else str(fx[key.substr(3)])
			t.ok(ResourceLoader.exists(path), "%s %s exists (%s)" % [id, key, path])
		var sheet := load(str(fx["sheet"])) as Texture2D
		var face := load(str(c["art"])) as Texture2D
		if sheet != null and face != null:
			t.eq([face.get_width(), face.get_height()], [CardDefs.FACE_W, CardDefs.FACE_H], "%s face is 96x128" % id)
			t.eq(sheet.get_width(), int(fx["frames"]) * int(fx["rect"][2]), "%s sheet is frames x rect.w wide" % id)
			t.eq(sheet.get_height(), int(fx["rect"][3]), "%s sheet is rect.h tall" % id)
	var bad := CardDefs.get_card("ice").duplicate(true)
	bad["fx"]["rect"] = [40, 80, 64, 64]
	t.ok(not CardDefs.validate_fx(bad).is_empty(), "a rect off the face fails")
	bad["fx"] = {}
	t.ok(CardDefs.validate_fx(bad).size() >= 7, "an empty fx row lists every missing key")
	t.eq(CardFace.frame_at(0, 16, 12.0), 0, "frame 0 at t=0")
	t.eq(CardFace.frame_at(500, 16, 12.0), 6, "12 fps: frame 6 at 500 ms")
	t.eq(CardFace.frame_at(1333, 16, 12.0), 15, "the last frame just before the loop")
	t.eq(CardFace.frame_at(1334, 16, 12.0), 0, "and it wraps")
	t.eq(CardFace.frame_at(1600, 12, 7.5), 0, "7.5 fps x 12 frames: 1.6 s loop")
	t.eq(CardFace.frame_at(999, 1, 12.0), 0, "a single frame never moves")
	var face := CardFace.new(CardDefs.get_card("fire7"), Vector2(168, 224))
	t.eq(face.frames, 16, "the face reads its frame count")
	face.set_frame(9)
	t.eq(face.frame_now(), 9, "a pinned frame holds")
	face.set_frame(-1)
	t.ok(face.frame_now() >= 0 and face.frame_now() < 16, "released: back on the clock")
	face.free()
	var chip := ModeCards.chip(CardDefs.get_card("ice")) as ModeCards.Chip
	t.eq(chip.bg, Color.html("#2E6AA6"), "the ice chip sits on the card's blue")
	t.ok(chip.get_node("Sprite") is CardFace and (chip.get_node("Sprite") as CardFace).sprite_only, "the chip runs the sprite alone")
	chip.free()
	var deal := ModeCards.art(CardDefs.get_card("fire7"), Vector2(96, 128), 6.0, true)
	t.ok(deal.get_node("Face") is CardFace and deal.get_meta("button") is TextureButton, "art holder: a face and its tap target")
	deal.free()
