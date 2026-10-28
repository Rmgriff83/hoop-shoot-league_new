class_name MatchClient
extends Node
## One phone's end of a match room (docs/BACKEND.md → Phase 3): a
## WebSocketPeer to `wss://…/v1/match/room/{id}`, polled every frame,
## bearer in the handshake. `message(msg)` relays each parsed message
## (MatchProtocol.parse), `closed(reason)` the end of the line. Outgoing
## messages (the pings too) pass a 4-a-second gate under the room's cap,
## and a 30 s ping keeps the socket alive.
##
## A line that drops once the match is on (the carrier cut it, a radio
## stall, the room closing a burst it took for a flood) is not the end: the
## client opens the same room again — the room keeps a dropped phone's seat
## for its grace and sends `start` (resumed) and the other side's buzzer
## report again — and only `closed` when RECONNECT_FOR_S of trying failed
## (Ross, 2026-10-27: a phone that lost its line was told it won). `dropped`
## / `restored` tell the screen. The queue rides across the gap.

signal opened
signal message(msg: Dictionary)
signal closed(reason: String)
## The line dropped mid-match and the client is getting it back.
signal dropped
## …and has it back (the room sent `start` again, resumed).
signal restored

const PING_EVERY_S := 30.0
## A touch under the room's cap, so jitter never lands six in one of its seconds.
const SEND_GAP_S := 1.25 / float(MatchProtocol.MAX_PER_S)
const CONNECT_TIMEOUT_S := 10.0
## Mid-match: keep opening the room again this long (inside the room's
## 20 s grace) before the line counts as lost.
const RECONNECT_FOR_S := 15.0
const RECONNECT_GAP_S := 1.0
## Close reasons the room means: no line to get back.
const FINAL_REASONS := ["over", "expired", "replaced"]

var room := ""
var area := ""
var side := ""
var peer: Dictionary = {}
var start: Dictionary = {}

var _ws: WebSocketPeer
var _url := ""
var _headers: PackedStringArray
var _queue: Array[String] = []
var _last_send := -1.0
var _last_ping := 0.0
var _opened := false
var _connect_at := 0.0
var _done := false
var _closing := ""
var _close_deadline := 0.0
## When the line dropped mid-match (-1: it has not).
var _dropped_at := -1.0
var _retry_at := 0.0
## Grace for the queue to drain on close (a period report must not be lost).
const CLOSE_DRAIN_S := 2.0


## Open the room. The loadout follows later, in the pre-match step
## (`loadout` once the room says `matched`; docs/BACKEND.md → Ranked).
## False when the net is off.
func open(p_room: String, p_area: String) -> bool:
	room = p_room
	area = p_area
	var base := NetConfig.base_url()
	if base == "" or not Net.enabled or not Net.registered():
		return false
	_url = base.replace("https://", "wss://").replace("http://", "ws://") + "/v1/match/room/%s?area=%s" % [room, area]
	# The hometown for the other phone's face-off card (design 37a); the room cleans it.
	var town := App.hometown()
	if town != "":
		_url += "&town=" + town.uri_encode()
	var a: Dictionary = Net.account()
	_headers = PackedStringArray(["Authorization: Bearer %s.%s" % [str(a.get("playerId", "")), str(a.get("secret", ""))]])
	return _connect()


## A socket to the room (the first, or one more while getting the line back).
func _connect() -> bool:
	_ws = WebSocketPeer.new()
	_ws.handshake_headers = _headers
	_ws.inbound_buffer_size = 64 * 1024
	_ws.outbound_buffer_size = 64 * 1024
	var err := _ws.connect_to_url(_url)
	if err != OK:
		_ws = null
		return false
	_connect_at = _now()
	_last_ping = _now()
	return true


## Queue a message (sent in order, never faster than the room allows).
func send(msg: Dictionary) -> void:
	if _done:
		return
	_queue.push_back(MatchProtocol.encode(msg))


func is_open() -> bool:
	return _opened and not _done


## Is the line down and being got back?
func reconnecting() -> bool:
	return _dropped_at >= 0.0 and not _done


## Close — after anything still queued has gone out (a buzzer report closed
## away was read as a forfeit). The node frees itself once closed.
func close(reason := "bye") -> void:
	if _done or _closing != "":
		return
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not _queue.is_empty():
		_closing = reason
		_close_deadline = _now() + CLOSE_DRAIN_S
		return
	_finish_close(reason)


func _finish_close(reason: String) -> void:
	if _done:
		return
	_done = true
	if _ws != null and _ws.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]:
		_ws.close(1000, reason)
	closed.emit(reason)
	queue_free()


func _process(_dt: float) -> void:
	if _done:
		return
	if _ws == null:
		if _dropped_at >= 0.0:
			_retry()
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_CONNECTING:
			if _now() - _connect_at > CONNECT_TIMEOUT_S:
				if _dropped_at >= 0.0:
					_ws = null   # this try hung; the next waits its gap
					_retry_at = _now() + RECONNECT_GAP_S
				else:
					close("timeout")
		WebSocketPeer.STATE_OPEN:
			if not _opened:
				_opened = true
				opened.emit()
			if _dropped_at >= 0.0:
				_dropped_at = -1.0
				_last_send = -1.0
				restored.emit()
			while _ws.get_available_packet_count() > 0:
				var text := _ws.get_packet().get_string_from_utf8()
				var msg := MatchProtocol.parse(text)
				if msg.is_empty():
					continue
				_absorb(msg)
				message.emit(msg)
			_pump()
			if _closing != "" and (_queue.is_empty() or _now() > _close_deadline):
				_finish_close(_closing)
		WebSocketPeer.STATE_CLOSED:
			var reason := _ws.get_close_reason()
			_ws = null
			if _done:
				return
			if _closing == "" and _can_resume(reason):
				if _dropped_at < 0.0:
					_dropped_at = _now()
					dropped.emit()
				_retry_at = _now() + RECONNECT_GAP_S
				return
			_done = true
			closed.emit(reason if reason != "" else "closed")
			queue_free()


## A drop worth getting back: the match was on (`start` landed), the room did
## not mean it, and the budget is not spent.
func _can_resume(reason: String) -> bool:
	if start.is_empty() or reason in FINAL_REASONS:
		return false
	return _dropped_at < 0.0 or _now() - _dropped_at < RECONNECT_FOR_S


## One more try at the room, or the end of the line once the budget is spent.
func _retry() -> void:
	if _now() - _dropped_at >= RECONNECT_FOR_S:
		_done = true
		closed.emit("lost")
		queue_free()
		return
	if _now() < _retry_at:
		return
	if not _connect():
		_retry_at = _now() + RECONNECT_GAP_S


## The room's bookkeeping messages, kept for whoever asks later.
func _absorb(msg: Dictionary) -> void:
	match str(msg["t"]):
		MatchProtocol.JOINED:
			side = str(msg.get("side", ""))
			var p: Variant = msg.get("peer", null)
			if p is Dictionary:
				peer = p
		MatchProtocol.PEER:
			peer = Dictionary(msg.get("peer", {}))
		MatchProtocol.START:
			start = msg


func _pump() -> void:
	var now := _now()
	if _queue.is_empty() and now - _last_ping >= PING_EVERY_S:
		# Through the queue like everything else: a ping counts against the room's cap too.
		_last_ping = now
		_queue.push_back(MatchProtocol.encode({"t": MatchProtocol.PING}))
	if not _queue.is_empty() and Backoff.can_fire(now, _last_send, SEND_GAP_S):
		_ws.send_text(_queue.pop_front())
		_last_send = now


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
