class_name ShotClassify
extends RefCounted
## Turn a finished ball state into a scored, named outcome. Nothing here decides
## physics — it only reads the event log the sim produced. Swish is emergent:
## 2 points strictly means the ball touched nothing on the way in.
## Ported from src/core/shot/classify.ts.
## ShotOutcome Dictionary: { "made", "points", "type", "entry_angle_deg" (NAN if
## never crossed inside the cylinder), "rim_contacts", "board_contacts",
## "flight_time", "events", "max_penetration" }.

const SWISH := "SWISH"
const MAKE := "MAKE"
const BANK := "BANK"
const SHOOTERS_ROLL := "SHOOTERS_ROLL"
const IN_AND_OUT := "IN_AND_OUT"
const FRONT_RIM := "FRONT_RIM"
const BACK_RIM := "BACK_RIM"
const SIDE_RIM := "SIDE_RIM"
const BOARD_MISS := "BOARD_MISS"
const AIRBALL := "AIRBALL"
## Cold streak: the rim ice grabbed a would-be make and popped it out (no points).
const ICE_CAUGHT := "ICE_CAUGHT"


static func classify_shot(s: BallState) -> Dictionary:
	var rim: Array[Dictionary] = []
	var board: Array[Dictionary] = []
	for ev in s.events:
		if ev["kind"] == Colliders.KIND_RIM:
			rim.push_back(ev)
		elif ev["kind"] == Colliders.KIND_BOARD:
			board.push_back(ev)
	var rim_contacts := rim.size()
	var board_contacts := board.size()

	var type: String
	if s.ice_caught:
		type = ICE_CAUGHT
	elif s.made:
		if rim_contacts == 0 and board_contacts == 0:
			type = SWISH
		elif board_contacts > 0:
			type = BANK
		elif rim_contacts >= 3:
			type = SHOOTERS_ROLL
		else:
			type = MAKE
	elif s.ever_entered:
		type = IN_AND_OUT
	elif rim_contacts > 0:
		var az: float = rim[0].get("azimuth_deg", 0.0)
		type = FRONT_RIM if az < 55.0 else (BACK_RIM if az > 125.0 else SIDE_RIM)
	elif board_contacts > 0:
		type = BOARD_MISS
	else:
		type = AIRBALL

	var points := 0
	if s.made:
		points = 2 if type == SWISH else 1

	var flight_time := s.t
	if not s.events.is_empty():
		flight_time = s.events[0]["t"]

	return {
		"made": s.made,
		"points": points,
		"type": type,
		"entry_angle_deg": s.entry_angle_deg,
		"rim_contacts": rim_contacts,
		"board_contacts": board_contacts,
		"flight_time": flight_time,
		"events": s.events,
		"max_penetration": s.max_penetration,
		"vortex": s.vortex_caught,
	}
