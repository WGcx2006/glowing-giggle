extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")
const REMOTE_ENTITY_FACTORY_SCRIPT := preload("res://scripts/network/remote_entity_factory.gd")

const SERVER_ADDRESS := "127.0.0.1"
const SERVER_PORT := 7794
const FRAME_TIMEOUT := 600
const PASS_DELAY_FRAMES := 5

var _network_manager
var _entity_sync
var _remote_entity_factory
var _frames := 0
var _pass_frames := 0
var _spawn_ack_sent := false
var _despawn_ack_sent := false
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
	_remote_entity_factory.remote_entity_despawned.connect(_on_remote_entity_despawned)
	_network_manager.connection_failed.connect(_on_connection_failed)
	_network_manager.server_disconnected.connect(_on_server_disconnected)

	if not _network_manager.join_session(SERVER_ADDRESS, SERVER_PORT):
		_fail("join_session returned false")


func _process(_delta: float) -> void:
	if _finished:
		return
	if _despawn_ack_sent:
		_pass_frames += 1
		if _pass_frames >= PASS_DELAY_FRAMES:
			_finish()
		return
	_frames += 1
	if _frames > FRAME_TIMEOUT:
		if _spawn_ack_sent:
			_fail("timeout waiting for remote entity despawn after %d frames" % FRAME_TIMEOUT)
		else:
			_fail("timeout waiting for remote entity spawn after %d frames" % FRAME_TIMEOUT)


func _on_remote_entity_spawned(entity_id: String, node: Node) -> void:
	if _finished or _spawn_ack_sent:
		return
	var failures: Array[String] = []
	if entity_id != "remote_1":
		failures.append("unexpected entity_id: %s" % entity_id)
	if node == null or not is_instance_valid(node):
		failures.append("remote node is not valid")
	else:
		if not node.has_method("get_network_snapshot"):
			failures.append("remote node missing get_network_snapshot")
		else:
			var snapshot: Variant = node.get_network_snapshot()
			if not snapshot is Dictionary:
				failures.append("snapshot is not Dictionary: %s" % str(snapshot))
			else:
				if int(snapshot.get("health", -1)) != 80:
					failures.append("health mismatch: %s" % str(snapshot.get("health")))
				if int(snapshot.get("marker", -1)) != 3:
					failures.append("marker mismatch: %s" % str(snapshot.get("marker")))
				if str(snapshot.get("display_name", "")) != "HostPlayer":
					failures.append("display_name mismatch: %s" % str(snapshot.get("display_name")))
				var received_position: Variant = snapshot.get("position")
				if not received_position is Vector3:
					failures.append("position is not Vector3: %s" % str(received_position))
				elif received_position.distance_to(Vector3(20.0, 0.0, -10.0)) > 0.01:
					failures.append("position mismatch: %s" % str(received_position))
	if not failures.is_empty():
		_fail("remote entity spawn validation failed: %s" % "; ".join(failures))
		return
	if not _network_manager.send_packet(1, PackedByteArray([97, 1])):
		_fail("send_packet returned false")
		return
	_spawn_ack_sent = true
	_frames = 0


func _on_remote_entity_despawned(entity_id: String) -> void:
	if _finished or _despawn_ack_sent:
		return
	if entity_id != "remote_1":
		_fail("unexpected remote_entity_despawned entity_id: %s" % entity_id)
		return
	if not _network_manager.send_packet(1, PackedByteArray([97, 2])):
		_fail("send_packet returned false")
		return
	_despawn_ack_sent = true
	_pass_frames = 0


func _on_connection_failed() -> void:
	_fail("connection_failed emitted")


func _on_server_disconnected() -> void:
	if not _despawn_ack_sent:
		_fail("server disconnected before despawn ack")


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	print("[M18ClientTest] FAILED: %s" % message)
	print("[M18ClientTest] failed")
	get_tree().quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[M18ClientTest] passed")
	get_tree().quit(0)
