class_name MatchClient
extends Node
## One phone's end of a match room (docs/BACKEND.md → Phase 3): a
## WebSocketPeer to `wss://…/v1/match/room/{id}`, polled every frame,
## bearer in the handshake. `message(msg)` relays each parsed message
## (MatchProtocol.parse), `closed(reason)` the end of the line. Outgoing
## messages pass a 5-a-second gate (the room's cap) and a 30 s ping keeps
## the socket alive; a phone that stops talking is a phone that left.

signal opened
signal message(msg: Dictionary)
signal closed(reason: String)

const PING_EVERY_S := 30.0
const SEND_GAP_S := 1.0 / float(MatchProtocol.MAX_PER_S)
const CONNECT_TIMEOUT_S := 10.0

var room := ""
var area := ""
var side := ""
var peer: Dictionary = {}
var start: Dictionary = {}

var _ws: WebSocketPeer
var _queue: Array[String] = []
var _last_send := -1.0
var _last_ping := 0.0
var _opened := false
var _connect_at := 0.0
var _done := false


## Open the room with the three loadout slots we want to bring (null = blank;
## the server keeps only what the ledger covers). False when the net is off.
func open(p_room: String, p_area: String, slots: Array = []) -> bool:
	room = p_room
	area = p_area
	var base := NetConfig.base_url()
	if base == "" or not Net.enabled or not Net.registered():
		return false
	var ids := PackedStringArray()
	for i in CardDefs.SLOTS:
		ids.append("" if i >= slots.size() or slots[i] == null else str(slots[i]).uri_encode())
	var url := base.replace("https://", "wss://").replace("http://", "ws://") + "/v1/match/room/%s?area=%s&slots=%s" % [room, area, ",".join(ids)]
	_ws = WebSocketPeer.new()
	var a: Dictionary = Net.account()
	_ws.handshake_headers = PackedStringArray(["Authorization: Bearer %s.%s" % [str(a.get("playerId", "")), str(a.get("secret", ""))]])
	_ws.inbound_buffer_size = 64 * 1024
	_ws.outbound_buffer_size = 64 * 1024
	var err := _ws.connect_to_url(url)
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


func close(reason := "bye") -> void:
	if _done:
		return
	_done = true
	if _ws != null and _ws.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]:
		_ws.close(1000, reason)
	closed.emit(reason)


func _process(_dt: float) -> void:
	if _ws == null or _done:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_CONNECTING:
			if _now() - _connect_at > CONNECT_TIMEOUT_S:
				close("timeout")
		WebSocketPeer.STATE_OPEN:
			if not _opened:
				_opened = true
				opened.emit()
			while _ws.get_available_packet_count() > 0:
				var text := _ws.get_packet().get_string_from_utf8()
				var msg := MatchProtocol.parse(text)
				if msg.is_empty():
					continue
				_absorb(msg)
				message.emit(msg)
			_pump()
		WebSocketPeer.STATE_CLOSED:
			var reason := _ws.get_close_reason()
			_ws = null
			if not _done:
				_done = true
				closed.emit(reason if reason != "" else "closed")


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
	if not _queue.is_empty() and Backoff.can_fire(now, _last_send, SEND_GAP_S):
		_ws.send_text(_queue.pop_front())
		_last_send = now
	if _queue.is_empty() and now - _last_ping >= PING_EVERY_S:
		_last_ping = now
		_ws.send_text(MatchProtocol.encode({"t": MatchProtocol.PING}))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
