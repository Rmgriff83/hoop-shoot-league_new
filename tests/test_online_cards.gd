extends RefCounted
## A played online card never returns to its player (Ross, 2026-10-26: a
## code match's winner saw his played card back on the next pre-match
## page). The phone's side: the slot empties on the play, the ledger mirror
## never re-fills it, a pre-match page built after shows it empty; a play
## the room receipted is spent even if the sim refuses it; every settle
## re-reads the ledger.


func run(t) -> void:
	var app: Node = Engine.get_main_loop().root.get_node_or_null("App")
	var net: Node = Engine.get_main_loop().root.get_node_or_null("Net")
	if app == null or net == null:
		t.ok(false, "the autoloads are up")
		return
	var saved := SaveService.get_cards()
	app.add_card("ice", 1, "online")
	t.ok(app.equip_card(0, "ice", "online"), "one ice, equipped in slot 0")
	t.eq(app.loadout_slots("online"), ["ice", null, null], "…the online loadout")
	t.ok(app.consume_slot(0, "ice", "online"), "the play empties the slot first")
	t.eq(app.loadout_slots("online"), [null, null, null], "…gone from the loadout")
	t.eq(app.card_count("ice", "online"), 0, "…and no spare")
	# The ledger's word after the match: nothing comes back.
	net._apply_cards({"inventory": {}, "level": 5})
	t.eq(app.loadout_slots("online"), [null, null, null], "the mirror keeps the slot empty")
	t.eq(app.card_count("ice", "online"), 0, "…and adds no spare")
	# A pre-match page built now (a rematch) shows it empty.
	var pre := PreMatchPage.new()
	var root: Control = pre.build({"peer": {"id": "p", "name": "GLASS WIZARD", "tag": "07"}, "cap": 5, "seconds": 20.0, "countdown_s": 5.0, "side": "a"}, "online")
	t.ok(root != null, "the pre-match page builds")
	t.eq(pre.slots(), [null, null, null], "…with three empty slots")
	pre.free()
	# A ledger that still holds a copy (the friend's spoils, a drop) shows it as a spare, never re-equipped.
	net._apply_cards({"inventory": {"ice": 1}, "level": 5})
	t.eq(app.loadout_slots("online"), [null, null, null], "a copy the ledger holds is not re-equipped")
	t.eq(app.card_count("ice", "online"), 1, "…it is a spare")
	SaveService.put_cards(saved)
	# The code paths.
	var heat := FileAccess.get_file_as_string("res://game/screens/heat_screen.gd")
	t.ok(heat.find("_deploy(slot, str(msg[\"id\"]), true)") >= 0, "the room's receipt deploys as receipted")
	t.ok(heat.find("\telif receipted:\n\t\t_tray_ids[i] = \"used\"") >= 0, "a refusal after the receipt keeps the slot used")
	t.eq(heat.count("_restore_slot("), 3, "_restore_slot: its definition, the room's error path, the offline refusal — nothing else")
	var appsrc := FileAccess.get_file_as_string("res://game/autoload/app.gd")
	var settle := appsrc.substr(appsrc.find("func settled_online("), 900)
	t.ok(settle.find("Net.refresh_cards()") >= 0, "every settle re-reads the ledger")
