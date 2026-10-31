extends RefCounted
## NEW PLAYER (design 35a): the form pre-fills and validates, the preview
## follows, rolls change things, and LET'S PLAY (App.create_player) sets the
## account's name and tag, the hometown, the created flag and the landing.


func run(t) -> void:
	var app = Engine.get_main_loop().root.get_node("App")
	var save = Engine.get_main_loop().root.get_node("SaveService")
	var net = Engine.get_main_loop().root.get_node("Net")
	var was_account: Dictionary = save.get_account()
	var was_settings: Dictionary = save.get_settings()
	var was_fresh: bool = app.qa_fresh
	# A fresh install: the splash says NEW GAME, registration waits.
	app.qa_fresh = true
	t.ok(not app.player_created(), "qa_fresh: no player yet")
	t.eq(load("res://game/screens/splash_screen.gd").primary_label(app.player_created()), "NEW GAME", "the splash offers NEW GAME")
	var was_enabled: bool = net.enabled
	net.enabled = true
	var reg: bool = await net._register()
	t.ok(not reg, "registration refuses before the player is created")
	net.enabled = was_enabled
	# The page, seeded.
	var page := NewPlayerPage.new()
	page.rng = DetRng.new(11)
	page._ready()
	t.ok(page.is_valid(), "pre-filled and valid at once (%s)" % str(page.values()))
	var v: Dictionary = page.values()
	t.ok(HandleWords.valid(str(v["name"])) and str(v["tag"]).length() == 2 and Towns.valid(str(v["town"])), "a handle with a two-digit tag and a town")
	var ne: TextEdit = page.find_child("NameEdit", true, false)
	var te: LineEdit = page.find_child("TownEdit", true, false)
	t.ok(ne.text == str(v["name"]) and te.text == str(v["town"]), "typed straight onto the gold card (2026-10-30)")
	t.ok(page.find_child("Card", true, false).find_child("NameEdit", true, false) != null and page.find_child("Card", true, false).find_child("TownEdit", true, false) != null, "…both fields inside it")
	t.eq((page.find_child("Tag", true, false) as Label).text, "#" + str(v["tag"]), "the #tag beside PLAYER NAME")
	t.ok(ne.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY, "a long name wraps onto a second line")
	t.eq(page.wash_alpha(), 0.0, "the splash's wall stays bare behind it")
	t.eq((page.find_child("Status", true, false) as Label).text, NewPlayerPage.HINT, "the hint while everything is fine")
	var play: ShadowCard = page.find_child("Play", true, false)
	t.ok(play != null and not play.disabled and play.modulate.a == 1.0, "LET'S PLAY lit")
	# Rolls.
	var name0 := str(v["name"])
	var town0 := str(v["town"])
	(page.find_child("RollName", true, false) as ShadowCard).pressed.emit()
	t.ok(page.values()["name"] != name0 and page.values()["town"] == town0, "the name die rolls only the name")
	(page.find_child("RollTown", true, false) as ShadowCard).pressed.emit()
	t.ok(page.values()["town"] != town0, "the town die rolls the town")
	var same := NewPlayerPage.new()
	same.rng = DetRng.new(11)
	same._ready()
	t.eq(same.values(), v, "same seed, same pre-fill")
	same.free()
	# Typing: tidied in place; the rules dim LET'S PLAY with a reason.
	ne.text = "ab"
	ne.text_changed.emit()
	t.eq(ne.text, "AB", "typing is upper-cased")
	t.eq((page.find_child("Status", true, false) as Label).text, "NAME NEEDS 3 OR MORE LETTERS", "too short")
	t.ok(play.disabled and play.modulate.a < 1.0, "…LET'S PLAY dimmed")
	ne.text = "ok  fuck!\n"
	ne.text_changed.emit()
	t.eq(ne.text, "OK FUCK", "punctuation, line breaks and double spaces go")
	t.eq(page.problem(), "NAME NOT ALLOWED", "a blocked word")
	ne.text = "BRICK BARON "
	ne.text_changed.emit()
	t.eq(ne.text, "BRICK BARON ", "a trailing space survives while typing")
	t.eq(page.name_value(), "BRICK BARON", "…and is trimmed in the value")
	te.text = ""
	te.text_changed.emit("")
	t.eq(page.problem(), "PICK A HOMETOWN", "an empty hometown")
	te.text = "salt harbor"
	te.text_changed.emit("salt harbor")
	t.ok(page.is_valid() and page.values()["town"] == "SALT HARBOR", "a typed town")
	t.eq(NewPlayerPage.clean_typing("a very long hometown name", Towns.TOWN_MAX), "A VERY LONG HOME", "typing caps at the max")
	# LET'S PLAY: the account, the settings, the landing.
	save.put_account({})
	app.pending_welcome = {}
	app.home_open_league = ""
	app.create_player("BRICK BARON", "42", "SALT HARBOR", false)
	var a: Dictionary = save.get_account()
	t.ok(a.get("name", "") == "BRICK BARON" and a.get("tag", "") == "42" and not bool(a.get("registered", true)), "the account carries the chosen name and tag, unregistered (%s)" % str(a))
	t.ok(a.get("playerId", "") != "" and a.get("secret", "") != "", "…with an identity minted")
	t.eq(app.hometown(), "SALT HARBOR", "the hometown is a setting")
	t.ok(app.player_created() and not app.qa_fresh, "the player exists now")
	t.ok(app.home_open_league == "" and app.home_card == 0 and not app.show_archive, "lands on the Arcade Cage home with its cards, no archive (the walkthrough points at them)")
	t.eq(app.pending_walkthrough, "home", "the home walkthrough is queued (design 36a)")
	t.ok(app.pending_welcome.get("name", "") == "BRICK BARON" and app.pending_welcome.get("town", "") == "SALT HARBOR", "the welcome toast is queued")
	t.ok(app.current_league == "cage" and not app.league_doc("cage").is_empty(), "the cage league is entered")
	t.eq(load("res://game/screens/splash_screen.gd").primary_label(app.player_created()), "CONTINUE", "the splash says CONTINUE from now on")
	page.free()
	# Put the world back.
	app.pending_welcome = {}
	app.home_open_league = ""
	app.pending_walkthrough = ""
	app.qa_fresh = was_fresh
	save.put_settings(was_settings)
	if was_account.is_empty():
		save.put_account({})
	else:
		save.put_account(was_account)
