extends Node

signal session_started(mode: String, session_name: String)
signal session_joined(address: String)
signal session_left(mode: String)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed
signal server_disconnected
signal packet_received(peer_id: int, packet: PackedByteArray)
signal network_state_changed

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 16

enum Mode { OFFLINE, HOST, CLIENT }

var mode: Mode = Mode.OFFLINE
var session_name: String = ""
var address: String = ""
var port: int = 0
var max_players: int = MAX_PLAYERS
var _peer: ENetMultiplayerPeer


func host_session(session_label: String = "Battlefield2035", port: int = DEFAULT_PORT) -> bool:
	if mode != Mode.OFFLINE:
		return false

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_players)
	if error != OK:
		peer.close()
		return false

	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()
	_peer = peer
	mode = Mode.HOST
	session_name = session_label
	self.port = port
	session_started.emit("host", session_label)
	network_state_changed.emit()
	return true


func join_session(server_address: String, port: int = DEFAULT_PORT) -> bool:
	if mode != Mode.OFFLINE:
		return false

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(server_address, port)
	if error != OK:
		peer.close()
		return false

	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()
	_peer = peer
	mode = Mode.CLIENT
	address = server_address
	self.port = port
	session_joined.emit(server_address)
	network_state_changed.emit()
	return true


func leave_session() -> void:
	var previous_mode_name: String = get_mode_name()
	_disconnect_multiplayer_signals()
	if _peer != null and is_instance_valid(_peer):
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	mode = Mode.OFFLINE
	session_name = ""
	address = ""
	port = 0
	session_left.emit(previous_mode_name)
	network_state_changed.emit()


func send_packet(peer_id: int, data: PackedByteArray) -> bool:
	if mode == Mode.OFFLINE or multiplayer == null or multiplayer.multiplayer_peer == null:
		return false
	if peer_id != 0 and not multiplayer.get_peers().has(peer_id):
		return false
	return multiplayer.send_bytes(data, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE) == OK


func broadcast_packet(data: PackedByteArray) -> bool:
	if mode == Mode.OFFLINE or multiplayer == null or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.send_bytes(data, 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE) == OK


func get_network_state() -> Dictionary:
	return {
		"mode": get_mode_name(),
		"session_name": session_name,
		"address": address,
		"port": port,
		"max_players": max_players,
		"connected_peers": _get_connected_peer_count(),
		"connection_status": _get_connection_status(),
		"reserved": false,
	}


func get_mode_name() -> String:
	match mode:
		Mode.HOST:
			return "host"
		Mode.CLIENT:
			return "client"
		_:
			return "offline"


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)


func _disconnect_multiplayer_signals() -> void:
	if multiplayer == null:
		return
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	if multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.disconnect(_on_peer_packet)


func _get_connected_peer_count() -> int:
	if mode == Mode.OFFLINE or multiplayer == null or multiplayer.multiplayer_peer == null:
		return 0
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0
	return multiplayer.get_peers().size()


func _get_connection_status() -> String:
	if mode == Mode.OFFLINE:
		return "offline"
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return "disconnected"
	match multiplayer.multiplayer_peer.get_connection_status():
		MultiplayerPeer.CONNECTION_CONNECTING:
			return "connecting"
		MultiplayerPeer.CONNECTION_CONNECTED:
			return "connected"
		_:
			return "disconnected"


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)
	network_state_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)
	network_state_changed.emit()


func _on_connected_to_server() -> void:
	network_state_changed.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()
	network_state_changed.emit()
	leave_session()


func _on_server_disconnected() -> void:
	server_disconnected.emit()
	network_state_changed.emit()
	leave_session()


func _on_peer_packet(id: int, packet: PackedByteArray) -> void:
	packet_received.emit(id, packet)
