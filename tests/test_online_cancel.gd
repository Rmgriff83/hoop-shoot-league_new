extends RefCounted
## Backing out of an online search (the 2026-10-26 TestFlight crash): a
## MatchClient's close emits `closed` before it frees itself, and the handler
## App wires on every room re-enters cancel_online while `room` is still that
## client. cancel_online must clear `room` first, so the handler stays out and
## nothing is called on a null or freed room (a segfault in a release build).


func run(t) -> void:
	var app: Node = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		t.ok(false, "the App autoload is up")
		return
	var was_room: Node = app.room
	var was_how: String = app.match_how
	var client := MatchClient.new()
	app.add_child(client)
	app.room = client
	app.match_how = ""   # no lobby leave request from the test
	# The handler App's _open_room connects: re-enter cancel_online while
	# `room` is still this client and the room never started.
	var reentered := [0]
	client.closed.connect(func(_reason: String) -> void:
		if app.room == client and client.start.is_empty():
			reentered[0] += 1
			app.cancel_online())
	app.cancel_online()
	t.ok(app.room == null, "cancel_online leaves no room")
	t.eq(reentered[0], 0, "the closed handler sees the room already cleared and stays out")
	t.ok(not is_instance_valid(client) or client.is_queued_for_deletion(), "the client frees itself")
	# A second cancel with nothing open is harmless.
	app.cancel_online()
	t.ok(app.room == null, "a second cancel is a no-op")
	# A non-client room node (a test double) is freed by App itself.
	var plain := Node.new()
	app.add_child(plain)
	app.room = plain
	app.cancel_online()
	t.ok(app.room == null and (not is_instance_valid(plain) or plain.is_queued_for_deletion()), "a plain room node is freed")
	app.room = was_room
	app.match_how = was_how
