class_name QaFakePeer
extends Node
## A stand-in for MatchClient with no network (tools/qa_driver.gd --qa-multi,
## and any hand test): the "other phone" is a seeded bot Heat running here,
## whose AI side goes out as the same MatchProtocol messages a real room
## would relay — shot on release, outcome when it lands, period_end at its
## buzzer. What our screen sends is kept in `sent` for inspection.

signal opened
signal message(msg: Dictionary)
signal closed(reason: String)

var peer := {"id": "qa-peer", "name": "GLASS WIZARD", "tag": "07", "level": 4, "town": "SALT HARBOR"}
var start: Dictionary = {}
var sent: Array = []
var side := "a"
## Settle as a rated match (docs/BACKEND.md → Ranked): a fake rating change
## and badge on `settled`, the way the real room sends them.
var ranked := true

var _heat: Heat
var _hand: Array = []
var _our_score := 0
var _our_reported := false
var _settled := false
var _n := 0
var _reported := 0
var _was_done := false
var _open := false


## The bot heat mirrors the config both sides derive from `start_msg`.
func stage(start_msg: Dictionary, geo: SimGeometry, spots: Array = [], shuffle := false) -> void:
	start = start_msg
	# Our side of the wire is "a"; the fake peer plays "b" with the hand the
	# start dealt it, through the same card policy a league bot uses.
	var hands: Dictionary = start_msg.get("hands", {}) if start_msg.get("hands") is Dictionary else {}
	_hand = Array(hands.get("b", [])).filter(func(x: Variant) -> bool: return str(x) != "")
	_heat = Heat.new({
		"geo": geo, "seconds": float(start_msg.get("seconds", 20.0)), "ot_seconds": float(start_msg.get("ot_seconds", 6.0)),
		"ball_return_s": float(start_msg.get("ball_return_s", 1.0)), "ai": AiRatings.make(0.6, 0.5),
		"seed": int(start_msg.get("seed", 1)), "calib_key": str(start_msg.get("calib_key", "beach")),
		"ai_cards": _hand.duplicate(),
	})
	_heat.set_spots(spots, shuffle)
	_open = true
	opened.emit.call_deferred()


## What our screen sends: a card gets its receipt, a period report settles
## the match once the fake side has reported too.
func send(msg: Dictionary) -> void:
	sent.push_back(msg)
	match str(msg.get("t", "")):
		MatchProtocol.CARD:
			message.emit.call_deferred({"t": MatchProtocol.CARD_OK, "id": str(msg["id"])})
		MatchProtocol.LOADOUT:
			# The real room validates, tells the other phone, and starts on both READY; the staged
			# peer answers as if it had picked an ice and readied the moment we did.
			message.emit.call_deferred({"t": MatchProtocol.PEER_LOADOUT, "slots": ["ice", "", ""], "ready": bool(msg.get("ready", false)), "from": "b"})
		MatchProtocol.REMATCH:
			# The fake always wants another go; a real room would then send rematch_go.
			message.emit.call_deferred({"t": MatchProtocol.REMATCH, "from": "b"})
		MatchProtocol.OUTCOME:
			_our_score = int(msg.get("score", 0))
		MatchProtocol.PERIOD_END:
			_our_score = int(msg.get("score", 0))
			_our_reported = true
			_maybe_settle()


## Both reports in and the scores apart: the room's payout, as the real one
## would send it (we are level 1, the fake peer level 4).
func _maybe_settle() -> void:
	if _settled or not _our_reported or _heat == null or _heat.ai.phase != TimeTrial.PHASE_DONE or _our_score == _heat.ai.score:
		return
	_settled = true
	var won := _our_score > _heat.ai.score
	message.emit.call_deferred(settle_message(won))


## The room's `settled` as the real one sends it (docs/BACKEND.md → Ranked →
## Stage B): the rating as {mu, rd, cons} objects, the rank, then the payout —
## a win takes the fake peer's played ice as SPOILS and fills the meter; a
## loss loses the Heat Check, keeps the ice (insured) and lands the streak Ice.
func settle_message(won: bool) -> Dictionary:
	var settle := {"t": MatchProtocol.SETTLED, "won": won, "reason": "played", "ranked": ranked}
	if not ranked:
		return settle
	var before := {"mu": 1500.0, "rd": 350.0, "cons": 800.0}
	var after := {"mu": 1518.0 if won else 1483.0, "rd": 290.0, "cons": 938.0 if won else 903.0}
	settle["rating"] = {"before": before, "after": after, "delta": float(after["mu"]) - float(before["mu"])}
	settle["rank"] = {"tier": "rookie", "division": 2 if won else 3, "games": 1, "wins": 1 if won else 0, "losses": 0 if won else 1}
	settle["events"] = ["promoted"] if won else []
	settle["peak"] = {"tier": "rookie", "division": 2 if won else 3}
	var tk := RankedRules.tickets_cfg()
	settle["pay"] = true
	settle["tickets"] = int(tk.get("win", 30)) if won else int(tk.get("loss", 14))
	var size := OnlineDrops.meter_size()
	var odds := OnlineDrops.odds_for("rookie", 1)
	if won:
		settle["spoils"] = {"captured": ["ice"], "lost": [], "insured": null}
		settle["meter"] = {"before": size - 4, "after": 10, "size": size, "odds": odds}
		settle["granted"] = [{"why": "meter", "card": "ice"}]
		settle["milestones"] = ["first_ranked_match", "first_ranked_win", "first_capture"]
		settle["loss_streak"] = 0
	else:
		settle["spoils"] = {"captured": [], "lost": ["fire7"], "insured": "ice"}
		settle["meter"] = {"before": 6, "after": 14, "size": size, "odds": odds}
		settle["granted"] = [{"why": "loss_streak", "card": "ice"}]
		settle["milestones"] = ["first_ranked_match"]
		settle["loss_streak"] = 4
	return settle


## The room's `matched`, for the pre-match page (the driver calls it).
func matched_message() -> Dictionary:
	return {"t": MatchProtocol.MATCHED, "peer": peer, "levels": {"a": 1, "b": 4},
		"tiers": {"a": {"tier": "rookie", "division": 3, "games": 0}, "b": {"tier": "pro", "division": 2, "games": 21, "wins": 12, "losses": 9}},
		"stats": {"a": {"cons": 800, "games": 0, "wins": 0, "losses": 0, "position": 0}, "b": {"cons": 1480, "games": 21, "wins": 12, "losses": 9, "position": 142}},
		"cap": 1, "seconds": 20.0, "countdown_s": 10.0}


## Their side asks first (the QA driver stages the wanted state).
func ask_rematch() -> void:
	message.emit({"t": MatchProtocol.REMATCH, "from": "b"})


func is_open() -> bool:
	return _open


func close(reason := "bye") -> void:
	if not _open:
		return
	_open = false
	closed.emit(reason)


func _process(dt: float) -> void:
	if _heat == null or not _open or _heat.done:
		return
	_heat.tick(dt)
	for ev in _heat.drain_events():
		if ev.get("side", "") != Heat.AI:
			continue
		if ev["kind"] == "release":
			_n += 1
			message.emit(MatchProtocol.shot(_n, ev["launch"]))
		elif ev["kind"] == "outcome":
			message.emit(MatchProtocol.outcome(_n, _heat.ai.score))
		elif ev["kind"] == "card_played" and bool(ev.get("ok", false)):
			message.emit({"t": MatchProtocol.CARD, "id": str(ev["card"]), "from": "b"})
	var is_done := _heat.ai.phase == TimeTrial.PHASE_DONE
	if is_done and not _was_done:
		message.emit(MatchProtocol.period_end(_reported, _heat.ai.score, Heat.totals_of(_heat.ai)))
		_reported += 1
		_maybe_settle()
	_was_done = is_done
