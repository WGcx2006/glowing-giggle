extends Node

signal remote_entity_spawned(entity_id: String, node: Node)
signal remote_entity_despawned(entity_id: String)
signal spawn_request_failed(entity_id: String, reason: String)

var PACKET_PREFIX := PackedByteArray([0x42, 0x33, 0x35, 0x31])

var _network_manager
var _entity_sync
var _remote_nodes: Dictionary = {}


func setup(network_manager, entity_sync) -> void:
	if network_manager == null or not is_instance_valid(network_manager):
		return
	if _network_manager != null:
		_disconnect_network_signals()
	_network_manager = network_manager
	_entity_sync = entity_sync
	_connect_network_signals()


func request_spawn(target_peer_id: int, entity_id: String, scene_path: String, initial_state: Dictionary) -> bool:
	if _network_manager == null or not is_instance_valid(_network_manager):
		return false
	if entity_id.is_empty() or scene_path.is_empty():
		return false
	var packet: PackedByteArray = _encode_packet({
		"type": "spawn_entity",
		"entity_id": entity_id,
		"scene_path": scene_path,
		"state": initial_state,
	})
	return _network_manager.send_packet(target_peer_id, packet)


func request_despawn(target_peer_id: int, entity_id: String) -> bool:
	if _network_manager == null or not is_instance_valid(_network_manager):
		return false
	if entity_id.is_empty():
		return false
	var packet: PackedByteArray = _encode_packet({
		"type": "despawn_entity",
		"entity_id": entity_id,
	})
	return _network_manager.send_packet(target_peer_id, packet)


func remove_remote_entity(entity_id: String) -> void:
	if entity_id.is_empty() or not _remote_nodes.has(entity_id):
		return
	var remote_node: Node = _remote_nodes[entity_id]
	if _entity_sync != null and is_instance_valid(_entity_sync):
		_entity_sync.unregister_entity(entity_id)
	if remote_node != null and is_instance_valid(remote_node):
		remote_node.queue_free()
	_remote_nodes.erase(entity_id)
	remote_entity_despawned.emit(entity_id)


func _on_packet_received(_peer_id: int, packet: PackedByteArray) -> void:
	if packet.size() <= PACKET_PREFIX.size() or packet.slice(0, PACKET_PREFIX.size()) != PACKET_PREFIX:
		return
	var decoded: Variant = bytes_to_var(packet.slice(PACKET_PREFIX.size(), packet.size()))
	if not decoded is Dictionary:
		return
	var message: Dictionary = decoded
	match str(message.get("type", "")):
		"spawn_entity":
			_handle_spawn_entity(message)
		"despawn_entity":
			var entity_id: String = str(message.get("entity_id", ""))
			if not entity_id.is_empty():
				remove_remote_entity(entity_id)


func _on_session_left(_mode: String) -> void:
	for entity_id: String in _remote_nodes.keys():
		remove_remote_entity(entity_id)


func get_remote_entity(entity_id: String) -> Node:
	if entity_id.is_empty():
		return null
	return _remote_nodes.get(entity_id) as Node


func get_remote_entity_count() -> int:
	return _remote_nodes.size()


func get_state() -> Dictionary:
	return {
		"count": get_remote_entity_count(),
		"entity_ids": _remote_nodes.keys(),
	}


func _handle_spawn_entity(message: Dictionary) -> void:
	var entity_id: String = str(message.get("entity_id", ""))
	var scene_path: String = str(message.get("scene_path", ""))
	var state: Variant = message.get("state", {})
	if entity_id.is_empty():
		spawn_request_failed.emit(entity_id, "spawn message is missing entity_id")
		return
	if scene_path.is_empty():
		spawn_request_failed.emit(entity_id, "spawn message is missing scene_path")
		return
	if not state is Dictionary:
		spawn_request_failed.emit(entity_id, "spawn message state must be a Dictionary")
		return
	if _remote_nodes.has(entity_id):
		remove_remote_entity(entity_id)

	if not ResourceLoader.exists(scene_path):
		spawn_request_failed.emit(entity_id, "failed to load scene path: %s" % scene_path)
		return
	var scene_resource: Variant = load(scene_path)
	if scene_resource == null:
		spawn_request_failed.emit(entity_id, "failed to load scene path: %s" % scene_path)
		return
	var remote_node: Node = _instantiate_resource(scene_resource)
	if remote_node == null:
		spawn_request_failed.emit(entity_id, "failed to instantiate scene path: %s" % scene_path)
		return

	add_child(remote_node)
	if remote_node.has_method("get_network_snapshot") and remote_node.has_method("apply_network_snapshot"):
		if _entity_sync != null and is_instance_valid(_entity_sync):
			_entity_sync.register_entity(entity_id, remote_node)
		remote_node.apply_network_snapshot(state)
	_remote_nodes[entity_id] = remote_node
	remote_entity_spawned.emit(entity_id, remote_node)


func _instantiate_resource(scene_resource: Variant) -> Node:
	if scene_resource is PackedScene:
		return scene_resource.instantiate()
	if scene_resource is GDScript:
		var instance: Variant = scene_resource.new()
		if instance is Node:
			return instance
	return null


func _encode_packet(message: Dictionary) -> PackedByteArray:
	var payload: PackedByteArray = var_to_bytes(message)
	return PACKET_PREFIX + payload


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
