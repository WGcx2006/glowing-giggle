extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")
const REMOTE_ENTITY_FACTORY_SCRIPT := preload("res://scripts/network/remote_entity_factory.gd")

const SERVER_ADDRESS := "127.0.0.1"
const SERVER_PORT := 7795
const FRAME_TIMEOUT := 600
const PASS_DELAY_FRAMES := 5

var _network_manager
var _entity_sync
var _remote_entity_factory
var _frames := 0
var _pass_frames := 0
var _spawned_ids: Array[String] = []
var _ack_sent := false
var _finished := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_network_manager = NETWORK_MANAGER_SCRIPT.new()
	_network_manager.name = "NetworkManager"
	add_child(_network_manager)

	_entity_sync = ENTITY_SYNC_SCRIPT.new()
	_entity_sync.name = "EntitySync"
	add_child(_entity_sync)
	_entity_sync.setup(_network_manager)

	_remote_entity_factory = REMOTE_ENTITY_FACTORY_SCRIPT.new()
	_remote_entity_factory.name = "RemoteEntityFactory"
	add_child(_remote_entity_factory)
	_remote_entity_factory.setup(_network_manager, _entity_sync)

	_remote_entity_factory.remote_entity_spawned.connect(_on_remote_entity_spawned)
	_network_manager.connection_failed.connect(_on_connection_failed)
	_network_manager.server_disconnected.connect(_on_server_disconnected)

	if not _network_manager.join_session(SERVER_ADDRESS, SERVER_PORT):
		_fail("join_session returned false")


func _process(_delta: float) -> void:
	if _finished:
		return
	if _ack_sent:
		_pass_frames += 1
		if _pass_frames >= PASS_DELAY_FRAMES:
			_finish()
		return
	_frames += 1
	if _frames > FRAME_TIMEOUT:
		var reason := "timeout waiting for remote entity spawn after %d frames" % FRAME_TIMEOUT
		if not _spawned_ids.is_empty():
			reason = "timeout waiting for all remote entity spawns after %d frames; got %s" % [FRAME_TIMEOUT, str(_spawned_ids)]
		_fail(reason)


func _on_remote_entity_spawned(entity_id: String, node: Node) -> void:
	if _finished or _ack_sent:
		return
	_spawned_ids.append(entity_id)
	if _spawned_ids.size() < 2:
		return

	var failures: Array[String] = []
	var player_id := ""
	var vehicle_id := ""
	var player_node: Node = null
	var vehicle_node: Node = null

	for spawned_id: String in _spawned_ids:
		var spawned_node: Node = _remote_entity_factory.get_remote_entity(spawned_id)
		if spawned_node == null or not is_instance_valid(spawned_node):
			failures.append("spawned node missing for %s" % spawned_id)
			continue
		if spawned_id.begins_with("remote_player_"):
			player_id = spawned_id
			player_node = spawned_node
		elif spawned_id.begins_with("remote_jeep_"):
			vehicle_id = spawned_id
			vehicle_node = spawned_node
		else:
			failures.append("unexpected entity_id: %s" % spawned_id)

	if player_id.is_empty():
		failures.append("missing entity_id starting with remote_player_")
	if vehicle_id.is_empty():
		failures.append("missing entity_id starting with remote_jeep_")
	if player_node != null and is_instance_valid(player_node):
		_validate_player(player_node, failures)
	if vehicle_node != null and is_instance_valid(vehicle_node):
		_validate_vehicle(vehicle_node, failures)

	if not failures.is_empty():
		_fail("remote entity spawn validation failed: %s" % "; ".join(failures))
		return

	if not _network_manager.send_packet(1, PackedByteArray([95, 1])):
		_fail("send_packet returned false")
		return
	_ack_sent = true
	_frames = 0


func _validate_player(node: Node, failures: Array[String]) -> void:
	if not node.has_method("get_network_snapshot"):
		failures.append("remote player missing get_network_snapshot")
		return
	var snapshot: Variant = node.get_network_snapshot()
	if not snapshot is Dictionary:
		failures.append("remote player snapshot is not Dictionary: %s" % str(snapshot))
		return
	if int(snapshot.get("health", -1)) != 100:
		failures.append("remote player health mismatch: %s" % str(snapshot.get("health")))
	var display_name := str(snapshot.get("display_name", ""))
	if not display_name.begins_with("Player"):
		failures.append("remote player display_name mismatch: %s" % display_name)


func _validate_vehicle(node: Node, failures: Array[String]) -> void:
	if not node.has_method("get_network_snapshot"):
		failures.append("remote vehicle missing get_network_snapshot")
		return
	var snapshot: Variant = node.get_network_snapshot()
	if not snapshot is Dictionary:
		failures.append("remote vehicle snapshot is not Dictionary: %s" % str(snapshot))
		return
	if str(snapshot.get("vehicle_type", "")) != "jeep":
		failures.append("remote vehicle vehicle_type mismatch: %s" % str(snapshot.get("vehicle_type")))
	if float(snapshot.get("health", -1.0)) != 220.0:
		failures.append("remote vehicle health mismatch: %s" % str(snapshot.get("health")))


func _on_connection_failed() -> void:
	_fail("connection_failed emitted")


func _on_server_disconnected() -> void:
	if _finished or _ack_sent:
		return
	_fail("server disconnected before spawn ack")


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	print("[M19ClientTest] FAILED: %s" % message)
	print("[M19ClientTest] failed")
	get_tree().quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[M19ClientTest] passed")
	get_tree().quit(0)
