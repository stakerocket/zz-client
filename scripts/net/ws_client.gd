extends Node
class_name ZZWSClient

signal connected
signal disconnected
signal message_received(data: Dictionary)

var _peer: WebSocketPeer = WebSocketPeer.new()
var _url: String = ZZServerConfig.ws_url()
var _active: bool = false
var _was_open: bool = false


func is_open() -> bool:
	return _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func connect_to_server(url: String = "") -> void:
	_url = url if url != "" else ZZServerConfig.ws_url()
	var err := _peer.connect_to_url(_url)
	if err != OK:
		push_error("WebSocket connect failed: %s" % err)
		return
	_active = true
	_was_open = false


func disconnect_from_server() -> void:
	_active = false
	_peer.close()


func send_dict(data: Dictionary) -> void:
	if not is_open():
		push_warning("WS not open, drop: %s" % data)
		return
	_peer.send_text(JSON.stringify(data))


func _process(_delta: float) -> void:
	if not _active:
		return
	_peer.poll()
	var state := _peer.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connected.emit()
			while _peer.get_available_packet_count() > 0:
				var packet := _peer.get_packet().get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(packet)
				if typeof(parsed) == TYPE_DICTIONARY:
					message_received.emit(parsed)
				else:
					push_warning("Bad WS payload: %s" % packet)
		WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
			if _was_open or _active:
				_active = false
				_was_open = false
				disconnected.emit()
