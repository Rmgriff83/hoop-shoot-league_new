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

var peer := {"id": "qa-peer", "name": "GLASS WIZARD", "tag": "07"}
var start: Dictionary = {}
var sent: Array = []
var side := "a"

var _heat: Heat
var _n := 0
var _reported := 0
var _was_done := false
var _open := false


## The bot heat mirrors the config both sides derive from `start_msg`.
func stage(start_msg: Dictionary, geo: SimGeometry, spots: Array = [], shuffle := false) -> void:
	start = start_msg
	_heat = Heat.new({
		"geo": geo, "seconds": float(start_msg.get("seconds", 20.0)), "ot_seconds": float(start_msg.get("ot_seconds", 6.0)),
		"ball_return_s": float(start_msg.get("ball_return_s", 1.0)), "ai": AiRatings.make(0.6, 0.5),
		"seed": int(start_msg.get("seed", 1)), "calib_key": str(start_msg.get("calib_key", "beach")),
	})
	_heat.set_spots(spots, shuffle)
	_open = true
	opened.emit.call_deferred()


func send(msg: Dictionary) -> void:
	sent.push_back(msg)


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
	var is_done := _heat.ai.phase == TimeTrial.PHASE_DONE
	if is_done and not _was_done:
		message.emit(MatchProtocol.period_end(_reported, _heat.ai.score, Heat.totals_of(_heat.ai)))
		_reported += 1
	_was_done = is_done
