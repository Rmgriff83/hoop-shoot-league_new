extends RefCounted
## MatchProtocol (docs/BACKEND.md → Phase 3): the messages, their checks,
## the heat config both phones derive from one `start`, the opponent slot.


func run(t) -> void:
	var launch := {"angle_deg": 51.234567891, "speed": 7.1, "vz": 0.2, "backspin": 3.0, "rx": 0.0, "ry": 1.8, "rz": 0.0, "bx": 0.1, "bz": -0.1, "roll": 0.5, "dist": 2.9, "aim_time": 0.4}
	var s := MatchProtocol.shot(4, launch)
	t.eq(s["t"], "shot", "a shot message")
	t.eq(s["n"], 4, "numbered")
	t.ok(not s["launch"].has("dist") and not s["launch"].has("aim_time"), "only what the sim reads")
	t.close(float(s["launch"]["angle_deg"]), 51.234568, 1e-9, "rounded to a millionth")
	var text := MatchProtocol.encode(s)
	t.ok(text.length() < 300, "a shot is a few hundred bytes (%d)" % text.length())
	var back := MatchProtocol.parse(text)
	t.eq(back["t"], "shot", "parses back")
	t.close(float(back["launch"]["speed"]), 7.1, 1e-9, "with its numbers")
	t.eq(MatchProtocol.parse("not json"), {}, "garbage → {}")
	t.eq(MatchProtocol.parse('{"t":"dance"}'), {}, "an unknown message → {}")
	t.eq(MatchProtocol.parse('{"t":"shot","n":1,"launch":{"angle_deg":"x","speed":7}}'), {}, "a shot with a string angle → {}")
	t.eq(MatchProtocol.parse('{"t":"shot","n":1,"launch":{"angle_deg":50,"speed":7,"evil":1}}'), {}, "a stray launch key → {}")
	t.eq(MatchProtocol.parse('{"t":"shot","n":1,"launch":{"angle_deg":50,"speed":7}}')["n"], 1, "a minimal shot is fine")
	t.eq(MatchProtocol.parse("x".repeat(MatchProtocol.MAX_BYTES + 1)), {}, "too long → {}")
	t.eq(MatchProtocol.parse('{"t":"outcome","n":1,"score":3}')["score"], 3, "an outcome")
	t.eq(MatchProtocol.parse('{"t":"outcome","n":1}'), {}, "an outcome without a score → {}")
	var pe := MatchProtocol.period_end(1, 12, {"score": 12, "makes": 8})
	t.eq(MatchProtocol.parse(MatchProtocol.encode(pe))["totals"]["makes"], 8, "a period report round-trips")
	t.eq(MatchProtocol.parse('{"t":"period_end","period":0,"score":1}'), {}, "a report without totals → {}")
	t.eq(MatchProtocol.parse('{"t":"start","seed":5,"area":"beach"}')["area"], "beach", "a start")
	t.eq(MatchProtocol.parse('{"t":"start","area":"beach"}'), {}, "a start without a seed → {}")
	t.eq(MatchProtocol.parse('{"t":"pong"}')["t"], "pong", "a pong")
	# The heat config from one start, on both phones.
	var start := {"t": "start", "seed": 987654, "area": "beach", "seconds": 90, "ot_seconds": 20, "ball_return_s": 1.0}
	var peer := {"id": "11111111-2222-4333-8444-555555555555", "name": "GLASS WIZARD", "tag": "07"}
	var cfg := MatchProtocol.heat_cfg(start, peer)
	t.eq(cfg["mode"], "heat_beach", "the beach's heat mode")
	t.eq(int(cfg["seed"]), 987654, "the room's seed")
	t.ok(bool(cfg["remote"]), "remote")
	t.eq(cfg["league"], null, "no league")
	t.eq(cfg["player_cards"], [], "no cards")
	t.eq(cfg["calib_key"], "beach", "the beach calibration")
	t.eq(MatchProtocol.heat_cfg({"seed": 1, "area": "cage"}, peer)["mode"], "heat", "the cage's heat mode")
	t.eq(MatchProtocol.heat_cfg({"seed": 1, "area": "cage"}, peer)["calib_key"], "arcade", "…and calibration")
	t.eq(MatchProtocol.heat_cfg({"seed": 1, "area": "city"}, peer)["mode"], "heat_city", "the city's")
	var opp: Dictionary = cfg["opponent"]
	t.eq(opp["name"], "GLASS WIZARD 07", "the other phone's handle in the slot")
	t.eq(opp["number"], 7, "their tag as the number")
	t.ok(str(opp["colors"]["primary"]).begins_with("#"), "a colour from the palette")
	t.eq(MatchProtocol.opponent(peer)["colors"]["primary"], opp["colors"]["primary"], "the same handle, the same colour")
	t.ok(App.MODES.has(cfg["mode"]), "the mode exists")
	var chip := HeatCopy.opponent_chip({"opponent": opp})
	t.eq(chip["text"], "GLASS", "their first word on the chip")
