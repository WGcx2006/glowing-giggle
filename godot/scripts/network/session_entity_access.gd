extends Node

signal remote_access_enabled
signal remote_access_disabled
signal peer_access_requested(peer_id: int)
signal peer_access_failed(peer_id: int, reason: String)

var _network_manager
var _remote_factory
var _remote_player_path: String = ""
var _remote_vehicle_path: String = ""
var _enabled := false


func setup(network_manager, remote_factory, remote_player_path: String, remote_vehicle_path: String) -> void:
	_network_manager = network_manager
	_remote_factory = remote_factory
	_remote_player_path = remote_player_path
	_remote_vehicle_path = remote_vehicle_path


func enable() -> void:
	if _enabled:
		return
	if _network_manager == null or not is_instance_valid(_network_manager):
		return
	if not _network_manager.peer_connected.is_connected(_on_peer_connected):
		_network_manager.peer_connected.connect(_on_peer_connected)
	_enabled = true
	remote_access_enabled.emit()


func disable() -> void:
	if not _enabled:
		return
	if _network_manager != null and is_instance_valid(_network_manager):
		if _network_manager.peer_connected.is_connected(_on_peer_connected):
			_network_manager.peer_connected.disconnect(_on_peer_connected)
	_enabled = false
	remote_access_disabled.emit()


func is_enabled() -> bool:
	return _enabled


func _on_peer_connected(peer_id: int) -> void:
	if not _enabled or _remote_factory == null or not is_instance_valid(_remote_factory):
		return

	var player_spawn_ok: bool = _remote_factory.request_spawn(
		peer_id,
		"remote_player_%d" % peer_id,
		_remote_player_path,
		{
			"position": Vector3(0, 2, 10),
			"yaw": 0.0,
			"health": 100,
			"marker": peer_id,
			"display_name": "Player %d" % peer_id,
		}
	)
	var vehicle_spawn_ok: bool = _remote_factory.request_spawn(
		peer_id,
		"remote_jeep_%d" % peer_id,
		_remote_vehicle_path,
		{
			"position": Vector3(0, 0, -6),
			"yaw": 0.0,
			"health": 220.0,
			"marker": peer_id,
			"display_name": "Jeep %d" % peer_id,
			"vehicle_type": "jeep",
			"animation": {
				"speed": 0.0,
				"throttle": 0.0,
				"steer": 0.0,
			},
		}
	)

	if not player_spawn_ok:
		peer_access_failed.emit(peer_id, "player spawn request failed for peer %d" % peer_id)
	if not vehicle_spawn_ok:
		peer_access_failed.emit(peer_id, "vehicle spawn request failed for peer %d" % peer_id)
	if player_spawn_ok and vehicle_spawn_ok:
		peer_access_requested.emit(peer_id)


func get_state() -> Dictionary:
	return {
		"enabled": _enabled,
		"remote_player_path": _remote_player_path,
		"remote_vehicle_path": _remote_vehicle_path,
	}
