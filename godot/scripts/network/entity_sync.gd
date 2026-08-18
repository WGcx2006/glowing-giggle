extends Node

signal entity_state_received(peer_id: int, entity_id: String, state: Dictionary)
signal entity_registered(entity_id: String)
signal entity_unregistered(entity_id: String)

var PACKET_PREFIX := PackedByteArray([0x42, 0x33, 0x35, 0x31])

var _network_manager
var _entities: Dictionary = {}
var _last_states: Dictionary = {}


func setup(network_manager) -> void:
	if network_manager == null or not is_instance_valid(network_manager):
		return
	if _network_manager != null:
		_disconnect_network_signals()
	_network_manager = network_manager
	_connect_network_signals()


func register_entity(entity_id: String, node: Node) -> void:
	if entity_id.is_empty() or node == null or not is_instance_valid(node):
		return
	if not node.has_method("get_network_snapshot") or not node.has_method("apply_network_snapshot"):
		return
	_entities[entity_id] = node
	entity_registered.emit(entity_id)


func unregister_entity(entity_id: String) -> void:
	if entity_id.is_empty():
		return
	if not _entities.has(entity_id):
		return
	_entities.erase(entity_id)
	entity_unregistered.emit(entity_id)


func get_entity_node(entity_id: String) -> Node:
	return _entities.get(entity_id) as Node


func get_entity_state(entity_id: String) -> Dictionary:
	var entity_node: Node = get_entity_node(entity_id)
	if entity_node == null or not is_instance_valid(entity_node) or not entity_node.has_method("get_network_snapshot"):
		return {}
	return entity_node.get_network_snapshot()


func broadcast_entity_state(entity_id: String, reliable: bool = false) -> bool:
	if _network_manager == null or not is_instance_valid(_network_manager):
		return false
	var entity_node: Node = get_entity_node(entity_id)
	if entity_node == null or not is_instance_valid(entity_node):
		return false
	var state: Dictionary = get_entity_state(entity_id)
	var packet: PackedByteArray = _encode_packet({
		"type": "entity_state",
		"entity_id": entity_id,
		"state": state,
	})
	# NetworkManager currently broadcasts reliable packets; the flag is kept for API compatibility.
	return _network_manager.broadcast_packet(packet)


func send_entity_state_to(peer_id: int, entity_id: String) -> bool:
	if _network_manager == null or not is_instance_valid(_network_manager):
		return false
	var entity_node: Node = get_entity_node(entity_id)
	if entity_node == null or not is_instance_valid(entity_node):
		return false
	var state: Dictionary = get_entity_state(entity_id)
	var packet: PackedByteArray = _encode_packet({
		"type": "entity_state",
		"entity_id": entity_id,
		"state": state,
	})
	return _network_manager.send_packet(peer_id, packet)


func broadcast_all_entity_states() -> void:
	for entity_id: String in _entities.keys():
		broadcast_entity_state(entity_id)


func _encode_packet(message: Dictionary) -> PackedByteArray:
	var payload := var_to_bytes(message)
	return PACKET_PREFIX + payload


func _on_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	if packet.size() <= PACKET_PREFIX.size() or packet.slice(0, PACKET_PREFIX.size()) != PACKET_PREFIX:
		return
	var decoded: Variant = bytes_to_var(packet.slice(PACKET_PREFIX.size(), packet.size()))
	if not decoded is Dictionary:
		return
	var message: Dictionary = decoded
	if message.get("type", "") != "entity_state":
		return
	if not message.has("entity_id") or not message.has("state"):
		return
	var entity_id: String = str(message.get("entity_id"))
	var state: Variant = message.get("state")
	if entity_id.is_empty() or not state is Dictionary:
		return

	var entity_node: Node = _entities.get(entity_id)
	if entity_node != null and is_instance_valid(entity_node) and entity_node.has_method("apply_network_snapshot"):
		entity_node.apply_network_snapshot(state)

	_last_states[entity_id] = state
	entity_state_received.emit(peer_id, entity_id, state)


func _on_session_left(_mode: String) -> void:
	_last_states.clear()


func _connect_network_signals() -> void:
	if _network_manager == null or not is_instance_valid(_network_manager):
		return
	if not _network_manager.packet_received.is_connected(_on_packet_received):
		_network_manager.packet_received.connect(_on_packet_received)
	if not _network_manager.session_left.is_connected(_on_session_left):
		_network_manager.session_left.connect(_on_session_left)


func _disconnect_network_signals() -> void:
	if _network_manager == null or not is_instance_valid(_network_manager):
		return
	if _network_manager.packet_received.is_connected(_on_packet_received):
		_network_manager.packet_received.disconnect(_on_packet_received)
	if _network_manager.session_left.is_connected(_on_session_left):
		_network_manager.session_left.disconnect(_on_session_left)
