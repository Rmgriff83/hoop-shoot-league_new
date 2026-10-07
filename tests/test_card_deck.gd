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
	# Seed the cache: 150 online coins, one spare ice, nothing equipped.
	var d: Dictionary = svc.get_cards()
	CardDefs.migrate(d)   # the autoload's doc may predate v3 in a scratch user://
	var b := CardDefs.league_doc(d, "online")
	b["coins"] = 150
	b["inventory"] = {"ice": 1}
	b["loadout"] = [null, null, null]
	svc.put_cards(d)
	var sheet := CardDeckSheet.new()
	sheet.build("online", "ONLINE CARDS")
	t.eq((sheet.find_child("Coins", true, false) as Label).text, "150 COINS", "the coins in the head")
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
	# The shop.
	sheet.build("online", "ONLINE CARDS", "SHOP")
	t.eq(sheet.sub(), "SHOP", "the shop")
	for id in ["ice", "fire7", "vortex6"]:
		t.ok(sheet.find_child("Shop_" + id, true, false) != null, "%s is on the shelf" % id)
	t.eq((sheet.find_child("Owned_ice", true, false) as Label).text, "OWNED 1", "owned count")
	t.ok(not (sheet.find_child("Buy_ice", true, false) as Button).disabled, "ice (100) is affordable at 150")
	t.ok((sheet.find_child("Buy_fire7", true, false) as Button).disabled, "Heat Check (170) is not")
	t.ok((sheet.find_child("Buy_vortex6", true, false) as Button).disabled, "Vortex is above the level anyway")
	t.ok(not App.try_buy_card("ice", "online"), "the save never sells online cards (the server does)")
	t.eq(App.league_coins("online"), 150, "…so the coins stay")
	# Net's cache rule: copies owned minus the ones equipped, a dead slot emptied.
	var fake_net: Node = load("res://game/net/net_client.gd").new()
	App.equip_card(0, "ice", "online")
	fake_net._apply_cards({"coins": 300, "inventory": {"ice": 2, "fire7": 1}, "level": 3})
	t.eq(App.league_coins("online"), 300, "the ledger's coins")
	t.eq(App.loadout_slots("online"), ["ice", null, null], "the equipped ice stays equipped")
	t.eq(App.card_count("ice", "online"), 1, "one ice spare (two owned, one equipped)")
	t.eq(App.card_count("fire7", "online"), 1, "the Heat Check spare")
	fake_net._apply_cards({"coins": 0, "inventory": {}, "level": 3})
	t.eq(App.loadout_slots("online"), [null, null, null], "a slot the ledger no longer covers empties")
	fake_net.free()
	sheet.free()
	# The lobby strip.
	var lobby := MatchLobbyPage.new()
	var root := lobby.build("cage")
	t.eq((root.find_child("OnlineCoins", true, false) as Label).text, "0 COINS", "the strip's coins")
	t.ok(root.find_child("Cards", true, false) != null, "CARDS >")
	var opened := [0]
	lobby.cards.connect(func() -> void: opened[0] += 1)
	(root.find_child("Cards", true, false) as Button).pressed.emit()
	t.eq(opened[0], 1, "…opens the deck")
	lobby.free()
	# Clean the cache we seeded.
	d = svc.get_cards()
	d["leagues"].erase("online")
	svc.put_cards(d)
