class_name MatchProtocol
extends RefCounted
## The 1v1 wire (docs/BACKEND.md → Phase 3): the few small JSON messages two
## phones trade through a match room, built and checked here so the screen
## and the tests speak the same words as server/src/match_room.ts. Pure.

## Messages a phone sends.
const SHOT := "shot"           # {t, n, launch}            one per release
const OUTCOME := "outcome"     # {t, n, score}             the sender's running score after it landed
const PERIOD_END := "period_end"  # {t, period, score, totals}
const CARD := "card"           # {t, id}                   a card out of the hand the room dealt
const REMATCH := "rematch"     # {t}                       on the post-match page: another go?
const PING := "ping"
## Messages the room sends.
const JOINED := "joined"       # {t, side, room, area, peer|null}
const PEER := "peer"           # {t, peer}                 the other phone arrived
const START := "start"         # {t, seed, area, seconds, ot_seconds, ball_return_s, hands: {a, b}, levels: {a, b}}
const CARD_OK := "card_ok"     # {t, id}                   the room took our card
const SETTLED := "settled"     # {t, coins, mult, won, reason, wallet}  the payout
const REMATCH_GO := "rematch_go"  # {t, room, area}        both asked: the fresh room
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


static func card(id: String) -> Dictionary:
	return {"t": CARD, "id": id}


static func rematch() -> Dictionary:
	return {"t": REMATCH}


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
		CARD, CARD_OK:
			if not (m.get("id") is String) or CardDefs.get_card(str(m["id"])).is_empty():
				return {}
		SETTLED:
			if not _num(m.get("coins")):
				return {}
		REMATCH_GO:
			if not (m.get("room") is String) or not _is_uuid(str(m["room"])) or not (m.get("area") is String):
				return {}
		REMATCH:
			pass
		JOINED, PEER, PEER_LEFT, EXPIRED, ERROR, PONG, PING:
			pass
		_:
			return {}
	return m


static func _num(v: Variant) -> bool:
	return v is int or v is float


static func _is_uuid(s: String) -> bool:
	return RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").search(s) != null


## The hand the room dealt a side, as the tray's three slots (null = blank).
static func hand_slots(start: Dictionary, side: String) -> Array:
	var hands: Dictionary = start.get("hands", {}) if start.get("hands") is Dictionary else {}
	var raw: Array = hands.get(side, []) if hands.get(side) is Array else []
	var out := [null, null, null]
	for i in mini(raw.size(), CardDefs.SLOTS):
		var id := str(raw[i])
		if id != "" and not CardDefs.get_card(id).is_empty():
			out[i] = id
	return out


static func _ids(slots: Array) -> Array:
	var out := []
	for s in slots:
		if s != null:
			out.push_back(str(s))
	return out


## The heat config two phones derive from the same `start` (App.start_heat's
## shape): the area's heat mode, the room's seed, each side's dealt hand
## (ours in the tray, theirs on the opponent's chips), the other phone as the
## opponent. Cards online come from the `online` bucket.
static func heat_cfg(start: Dictionary, peer: Dictionary, side := "a") -> Dictionary:
	var area := str(start.get("area", "cage"))
	var mode_id := "heat" if area == "cage" else "heat_" + area
	var mine := hand_slots(start, side)
	var theirs := hand_slots(start, "b" if side == "a" else "a")
	var levels: Dictionary = start.get("levels", {}) if start.get("levels") is Dictionary else {}
	return {
		"mode": mode_id,
		"seconds": float(start.get("seconds", Heat.DEFAULT_SECONDS)),
		"ot_seconds": float(start.get("ot_seconds", Heat.DEFAULT_OT_SECONDS)),
		"ball_return_s": float(start.get("ball_return_s", Heat.DEFAULT_BALL_RETURN_S)),
		"ai": {}, "err_mult": 1.0,
		"seed": int(start.get("seed", 1)),
		"opponent": opponent(peer),
		"calib_key": area if area != "cage" else "arcade",
		"league": null, "remote": true, "online": true, "bucket": "online",
		"player_cards": _ids(mine), "player_slots": mine, "ai_cards": _ids(theirs),
		"their_level": int(levels.get("b" if side == "a" else "a", 1)),
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
