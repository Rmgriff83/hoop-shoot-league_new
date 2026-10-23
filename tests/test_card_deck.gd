extends RefCounted
## The online deck sheet (docs/BACKEND.md → Cards online) off-tree on the
## `online` bucket: slots, LOADOUT spares equip into the first empty slot, a
## slot tap unequips, SHOP shows every card with the level chip gold only
## once reached and BUY off under the price; the lobby strip reads the same
## bucket. Never touches the network (the online bucket is a cache the test
## seeds by hand).

const SaveServiceScript := preload("res://game/autoload/save_service.gd")


func _svc() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("SaveService")


func run(t) -> void:
	var svc := _svc()
	if svc == null:
		t.ok(false, "SaveService autoload present")
		return
	# Seed the cache: one spare ice, nothing equipped; 150 tickets in the wallet.
	var d: Dictionary = svc.get_cards()
	CardDefs.migrate(d)   # the autoload's doc may predate v4 in a scratch user://
	var b := CardDefs.league_doc(d, "online")
	b["inventory"] = {"ice": 1}
	b["loadout"] = [null, null, null]
	svc.put_cards(d)
	var cos_before: Dictionary = svc.get_cosmetics()
	var cos: Dictionary = svc.get_cosmetics()
	cos["tickets"] = 150
	svc.put_cosmetics(cos)
	var sheet := CardDeckSheet.new()
	sheet.build("online", "ONLINE CARDS")
	t.ok(sheet.find_child("Tickets", true, false) == null, "the online sheet shows no wallet: online cards are never bought")
	t.ok(sheet.find_child("Sub_SHOP", true, false) == null and sheet.find_child("Sub_LOADOUT", true, false) != null, "…and has no SHOP tab, LOADOUT only")
	t.eq(sheet.sub(), "LOADOUT", "opens on the loadout")
	t.ok(sheet.find_child("Spare_ice", true, false) != null, "the spare ice shows")
	t.ok((sheet.find_child("Slot0", true, false) as Button).disabled, "an empty slot is not a button")
	var spare: Control = sheet.find_child("Spare_ice", true, false)
	(spare.get_meta("button") as TextureButton).pressed.emit()
	t.eq(App.loadout_slots("online"), ["ice", null, null], "tapping a spare equips it into the first slot")
	t.ok(sheet.find_child("Spare_ice", true, false) == null, "…and it leaves the spares")
	t.ok(not (sheet.find_child("Slot0", true, false) as Button).disabled, "the slot is now a button")
	(sheet.find_child("Slot0", true, false) as Button).pressed.emit()
	t.eq(App.loadout_slots("online"), [null, null, null], "tapping the slot takes it out again")
	t.eq(App.card_count("ice", "online"), 1, "…back to the spares")
	# A card above your level is owned but not equipped (docs/PROGRESSION.md).
	var vortex := CardDefs.get_card("magnet6")
	if not Progression.can_use(App.level(), vortex):
		d = svc.get_cards()
		CardDefs.league_doc(d, "online")["inventory"] = {"ice": 1, "magnet6": 1}
		svc.put_cards(d)
		t.ok(not App.can_equip("magnet6"), "Magnet waits for level 5")
		t.ok(not App.equip_card(0, "magnet6", "online"), "…so equip_card refuses it")
		t.eq(App.loadout_slots("online"), [null, null, null], "…and the slot stays empty")
		sheet.build("online", "ONLINE CARDS")
		t.ok(sheet.find_child("Lock_magnet6", true, false) != null, "the spare wears its LVL chip")
		var locked: Control = sheet.find_child("Spare_magnet6", true, false)
		(locked.get_meta("button") as TextureButton).pressed.emit()
		t.eq(App.loadout_slots("online"), [null, null, null], "tapping it equips nothing")
		t.ok(sheet.status_text().begins_with("REACH LEVEL 5"), "…and says why (%s)" % sheet.status_text())
		t.ok(App.can_equip("ice"), "a level-1 card equips as ever")
		# …and cannot be bought below its level in a league either.
		var cd_doc: Dictionary = svc.get_cards()
		var cage_before: Dictionary = CardDefs.league_doc(cd_doc, "cage").duplicate(true)
		svc.put_cards(cd_doc)
		var rich: Dictionary = svc.get_cosmetics()
		rich["tickets"] = 1000
		svc.put_cosmetics(rich)
		t.ok(not App.try_buy_card("magnet6", "cage"), "the league shop refuses Magnet under level 5 with the tickets in hand")
		t.eq(App.tickets(), 1000, "…and takes nothing")
		cd_doc = svc.get_cards()
		cd_doc["leagues"]["cage"] = cage_before
		svc.put_cards(cd_doc)
		rich["tickets"] = 150
		svc.put_cosmetics(rich)
		d = svc.get_cards()
		CardDefs.league_doc(d, "online")["inventory"] = {"ice": 1}
		svc.put_cards(d)
	# The shop: a league's sheet, priced in tickets (the online bucket has none).
	sheet.build("online", "ONLINE CARDS", "SHOP")
	t.eq(sheet.sub(), "LOADOUT", "asking the online sheet for the SHOP lands on the loadout")
	var cage_doc: Dictionary = svc.get_cards()
	var cage_was: Dictionary = CardDefs.league_doc(cage_doc, "cage").duplicate(true)
	CardDefs.league_doc(cage_doc, "cage")["inventory"] = {"ice": 1}
	svc.put_cards(cage_doc)
	sheet.build("cage", "CAGE CARDS", "SHOP")
	t.eq(sheet.sub(), "SHOP", "the shop")
	t.eq((sheet.find_child("Tickets", true, false) as Label).text, "150 TICKETS", "the wallet in the head")
	for id in ["ice", "fire7", "magnet6"]:
		t.ok(sheet.find_child("Shop_" + id, true, false) != null, "%s is on the shelf" % id)
	t.eq((sheet.find_child("Owned_ice", true, false) as Label).text, "OWNED 1", "owned count")
	t.ok(not (sheet.find_child("Buy_ice", true, false) as Button).disabled, "ice (80) is affordable at 150")
	t.ok(not (sheet.find_child("Buy_fire7", true, false) as Button).disabled or not App.can_equip("fire7"), "Heat Check (140) is affordable at 150 once its level is reached")
	t.ok((sheet.find_child("Buy_magnet6", true, false) as Button).disabled, "Magnet is above the level anyway")
	t.ok(App.try_buy_card("ice", "cage"), "the cage shop sells an ice for tickets")
	t.eq(App.tickets(), 70, "…80 tickets gone")
	t.eq(App.card_count("ice", "cage"), 2, "…and the ice is in the cage bucket")
	cage_doc = svc.get_cards()
	cage_doc["leagues"]["cage"] = cage_was
	svc.put_cards(cage_doc)
	t.ok(not App.try_buy_card("ice", "online"), "the save never sells online cards")
	t.eq(App.tickets(), 70, "…so the tickets stay")
	svc.put_cosmetics(cos_before)
	# Net's cache rule: copies owned minus the ones equipped, a dead slot emptied.
	var fake_net: Node = load("res://game/net/net_client.gd").new()
	App.equip_card(0, "ice", "online")
	fake_net._apply_cards({"inventory": {"ice": 2, "fire7": 1}, "level": 3})
	t.ok(not CardDefs.league_doc(svc.get_cards(), "online").has("coins"), "the ledger sends no wallet")
	t.eq(App.loadout_slots("online"), ["ice", null, null], "the equipped ice stays equipped")
	t.eq(App.card_count("ice", "online"), 1, "one ice spare (two owned, one equipped)")
	t.eq(App.card_count("fire7", "online"), 1, "the Heat Check spare")
	fake_net._apply_cards({"inventory": {}, "level": 3})
	t.eq(App.loadout_slots("online"), [null, null, null], "a slot the ledger no longer covers empties")
	fake_net.free()
	sheet.free()
	# The pre-match pick (docs/BACKEND.md → Ranked): the loadout and the spares
	# on the page, under the card cap.
	d = svc.get_cards()
	CardDefs.league_doc(d, "online")["inventory"] = {"ice": 1, "magnet6": 1}
	CardDefs.league_doc(d, "online")["loadout"] = [null, null, null]
	svc.put_cards(d)
	var pre := PreMatchPage.new()
	var root := pre.build({"peer": {"name": "GLASS WIZARD", "tag": "07", "level": 4, "town": "SALT HARBOR"}, "levels": {"a": 1, "b": 4},
		"tiers": {"a": {"tier": "rookie", "division": 3, "games": 0}, "b": {"tier": "pro", "division": 2, "games": 21, "wins": 12, "losses": 9}},
		"cap": 1, "seconds": 20.0, "side": "a"}, "online")
	t.ok(root.find_child("Slot0", true, false) != null and root.find_child("Slot2", true, false) != null, "three loadout slots")
	t.ok(root.find_child("Spares", true, false) != null, "the spares row")
	t.ok((root.find_child("LoadoutLine", true, false) as Label).text.ends_with("OF 3 · TAP TO REMOVE"), "n OF 3 · TAP TO REMOVE")
	t.eq(pre.cap_text(), "CARD CAP · LVL 1 · THE LOWER LEVEL PLAYS", "the cap line")
	t.eq(pre.opp_name(), "GLASS WIZARD", "their name")
	t.eq(pre.opp_online_text(), "PRO II · 12-9", "their badge and record")
	t.ok(root.find_child("Lock_magnet6", true, false) != null, "a Magnet above the cap wears its level")
	t.ok(root.find_child("Lock_ice", true, false) == null, "an ice under the cap does not")
	var picks := []
	pre.picked.connect(func(s: Array) -> void: picks.push_back(s))
	(root.find_child("Spare_magnet6", true, false).get_meta("button") as TextureButton).pressed.emit()
	t.eq(App.loadout_slots("online"), [null, null, null], "tapping the capped Magnet does nothing")
	(root.find_child("Spare_ice", true, false).get_meta("button") as TextureButton).pressed.emit()
	t.eq(App.loadout_slots("online"), ["ice", null, null], "tapping the ice equips it")
	t.eq(picks.size(), 1, "…and the provisional pick goes out")
	var readied := []
	pre.readied.connect(func(s: Array) -> void: readied.push_back(s))
	t.ok(not pre.is_ready(), "not ready yet")
	pre.advance(5.0)
	t.ok(pre.seconds_left() < 15.1 and pre.seconds_left() > 14.9, "the clock runs")
	t.ok((root.find_child("TimerLine", true, false) as Label).text.begins_with("TIP-OFF IN 15"), "the timer line")
	pre.press_ready()
	t.ok(pre.is_ready() and readied == [["ice", null, null]], "READY sends the slots")
	t.eq((root.find_child("Ready", true, false) as ShadowCard).text, "WAITING FOR THEM", "…and waits for them")
	# A league heat's pick (docs/CARDS.md § Drops): the next opponent as the
	# peer, the league as the place, the record as the line, the cap at your level.
	if App.enter_league("cage"):
		var info: Dictionary = App.league_pre_match_info(App.league_doc("cage"), App.league_cfg("cage"))
		t.eq(info["bucket"], "cage", "the league's bucket")
		t.eq(int(info["cap"]), App.level(), "the cap at your level")
		t.close(float(info["seconds"]), CardDefs.prematch_seconds("league"), 1e-9, "the short league clock from data")
		t.ok(str(info["peer"]["place_text"]).begins_with("ARCADE LEAGUE"), "the league as their place (%s)" % info["peer"]["place_text"])
		t.ok(str(info["peer"]["online_text"]).ends_with("THIS SEASON"), "their record as the line (%s)" % info["peer"]["online_text"])
		var lp := PreMatchPage.new()
		lp.build(info, str(info["bucket"]))
		t.ok(lp.is_league(), "a league pick")
		t.eq(lp.opp_online_text(), str(info["peer"]["online_text"]), "the record on the card")
		t.eq(lp.cap_text(), "CARD CAP · LVL %d · YOUR LEVEL" % App.level(), "a league cap is your own level")
		t.ok(lp.you_online_text().ends_with("THIS SEASON"), "your season record, not the ladder (%s)" % lp.you_online_text())
		lp.free()
	t.close(CardDefs.prematch_seconds("league"), 12.0, 1e-9, "12 s before a league heat")
	var pre2 := PreMatchPage.new()
	pre2.build({"peer": {"name": "X", "tag": "01"}, "cap": 3, "seconds": 2.0}, "online")
	var auto := [0]
	pre2.readied.connect(func(_s: Array) -> void: auto[0] += 1)
	pre2.advance(2.5)
	t.eq(auto[0], 1, "at zero the page readies itself")
	pre2.free()
	pre.free()
	# Clean the cache we seeded.
	d = svc.get_cards()
	d["leagues"].erase("online")
	svc.put_cards(d)
