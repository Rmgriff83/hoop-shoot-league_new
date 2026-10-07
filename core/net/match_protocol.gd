class_name MatchProtocol
extends RefCounted
## The 1v1 wire (docs/BACKEND.md → Phase 3): the few small JSON messages two
## phones trade through a match room, built and checked here so the screen
## and the tests speak the same words as server/src/match_room.ts. Pure.

## Messages a phone sends.
const SHOT := "shot"           # {t, n, launch}            one per release
const OUTCOME := "outcome"     # {t, n, score}             the sender's running score after it landed
const PERIOD_END := "period_end"  # {t, period, score, totals}
const PING := "ping"
## Messages the room sends.
const JOINED := "joined"       # {t, side, room, area, peer|null}
const PEER := "peer"           # {t, peer}                 the other phone arrived
const START := "start"         # {t, seed, area, seconds, ot_seconds, ball_return_s}
const PEER_LEFT := "peer_left"
const EXPIRED := "expired"     # nobody came
const ERROR := "error"
const PONG := "pong"

## The launch keys worth sending: everything ShotSim reads (core/physics/shot_sim.gd).
const LAUNCH_KEYS := ["angle_deg", "speed", "vz", "backspin", "rx", "ry", "rz", "bx", "bz", "roll"]
## Bytes per message the room accepts; a shot is ~250.
const MAX_BYTES := 2048
## Messages per second per phone the room accepts.
const MAX_PER_S := 5

## The handle's colour on the other phone's chip, one of the shooter palette.
const PALETTE := ["#e0562b", "#2b7a78", "#f6c453", "#4a7fd6", "#9b59b6", "#27ae60", "#d35400", "#1b1b24"]


static func shot(n: int, launch: Dictionary) -> Dictionary:
	var l := {}
	for k in LAUNCH_KEYS:
		if launch.has(k):
			l[k] = snappedf(float(launch[k]), 0.000001)
	return {"t": SHOT, "n": n, "launch": l}


static func outcome(n: int, score: int) -> Dictionary:
	return {"t": OUTCOME, "n": n, "score": score}


static func period_end(period: int, score: int, totals: Dictionary) -> Dictionary:
	return {"t": PERIOD_END, "period": period, "score": score, "totals": totals.duplicate(true)}


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


## A message from the wire, or {} when it is not one of ours / malformed.
static func parse(text: String) -> Dictionary:
	if text.length() > MAX_BYTES:
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not parsed.has("t"):
		return {}
	var m: Dictionary = parsed
	match str(m["t"]):
		SHOT:
			if not (m.get("launch") is Dictionary) or not _num(m.get("n")):
				return {}
			var l: Dictionary = m["launch"]
			if not _num(l.get("angle_deg")) or not _num(l.get("speed")):
				return {}
			for k in l:
				if not LAUNCH_KEYS.has(str(k)) or not _num(l[k]):
					return {}
		OUTCOME:
			if not _num(m.get("n")) or not _num(m.get("score")):
				return {}
		PERIOD_END:
			if not _num(m.get("period")) or not _num(m.get("score")) or not (m.get("totals") is Dictionary):
				return {}
		START:
			if not _num(m.get("seed")) or not (m.get("area") is String):
				return {}
		JOINED, PEER, PEER_LEFT, EXPIRED, ERROR, PONG, PING:
			pass
		_:
			return {}
	return m


static func _num(v: Variant) -> bool:
	return v is int or v is float


## The heat config two phones derive from the same `start` (App.start_heat's
## shape): the area's heat mode, the room's seed, no cards, the other phone
## as the opponent.
static func heat_cfg(start: Dictionary, peer: Dictionary) -> Dictionary:
	var area := str(start.get("area", "cage"))
	var mode_id := "heat" if area == "cage" else "heat_" + area
	return {
		"mode": mode_id,
		"seconds": float(start.get("seconds", Heat.DEFAULT_SECONDS)),
		"ot_seconds": float(start.get("ot_seconds", Heat.DEFAULT_OT_SECONDS)),
		"ball_return_s": float(start.get("ball_return_s", Heat.DEFAULT_BALL_RETURN_S)),
		"ai": {}, "err_mult": 1.0,
		"seed": int(start.get("seed", 1)),
		"opponent": opponent(peer),
		"calib_key": area if area != "cage" else "arcade",
		"league": null, "remote": true,
		"player_cards": [], "player_slots": [null, null, null], "ai_cards": [],
	}


## The other phone in the opponent slot's shape ({id, name, number, nickname, colors}).
static func opponent(peer: Dictionary) -> Dictionary:
	var name := str(peer.get("name", "THEM"))
	var tag := str(peer.get("tag", ""))
	var full := HandleWords.display(name, tag)
	var h := DetRng.hash_seed(full)
	return {
		"id": "online:" + str(peer.get("id", full)),
		"name": full, "number": int(tag) if tag.is_valid_int() else 0, "nickname": "",
		"colors": {"primary": PALETTE[absi(h) % PALETTE.size()], "secondary": "#1b1b24", "accent": "#f6c453"},
	}
