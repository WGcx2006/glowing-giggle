extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")
const REMOTE_ENTITY_FACTORY_SCRIPT := preload("res://scripts/network/remote_entity_factory.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const SERVER_PORT := 7794
const CLIENT_LAUNCH_DELAY_FRAMES := 10
const PACKET_TIMEOUT_FRAMES := 600
const MAIN_READY_TIMEOUT_FRAMES := 180

enum Phase {
	LAUNCH_CLIENT,
	WAIT_SPAWN_ACK,
	WAIT_DESPAWN_ACK,
	ADD_LOCAL_REMOTE,
	WAIT_LOCAL_REMOTE_FRAME,
	ADD_MAIN,
	WAIT_MAIN,
}

var _network_manager
var _entity_sync
var _remote_entity_factory
var _local_remote: Node3D
var _game: Node3D
var _phase := Phase.LAUNCH_CLIENT
var _frames := 0
var _client_pid := -1
var _connected_peer_id := -1
var _spawn_ack_received := false
var _despawn_ack_received := false
var _failed: Array[String] = []
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

	_network_manager.peer_connected.connect(_on_peer_connected)
	_network_manager.peer_disconnected.connect(_on_peer_disconnected)
	_network_manager.packet_received.connect(_on_packet_received)

	if not _network_manager.host_session("M18Test", SERVER_PORT):
		_fail("host_session returned false")


func _physics_process(_delta: float) -> void:
	if _finished:
		return
	match _phase:
		Phase.LAUNCH_CLIENT:
			_frames += 1
			if _frames >= CLIENT_LAUNCH_DELAY_FRAMES:
				_launch_client()
		Phase.WAIT_SPAWN_ACK:
			_frames += 1
			if _frames > PACKET_TIMEOUT_FRAMES:
				_failed.append("spawn ack timeout after %d frames" % PACKET_TIMEOUT_FRAMES)
				_finish()
		Phase.WAIT_DESPAWN_ACK:
			_frames += 1
			if _frames > PACKET_TIMEOUT_FRAMES:
				_failed.append("despawn ack timeout after %d frames" % PACKET_TIMEOUT_FRAMES)
				_finish()
		Phase.ADD_LOCAL_REMOTE:
			if _add_local_remote():
				_phase = Phase.WAIT_LOCAL_REMOTE_FRAME
				_frames = 0
		Phase.WAIT_LOCAL_REMOTE_FRAME:
			_frames += 1
			if _frames >= 1:
				_test_local_remote()
				if not _failed.is_empty():
					_finish()
					return
				if _local_remote != null and is_instance_valid(_local_remote):
					_local_remote.queue_free()
				_local_remote = null
				_phase = Phase.ADD_MAIN
				_frames = 0
		Phase.ADD_MAIN:
			_game = MAIN_SCENE.instantiate()
			add_child(_game)
			_phase = Phase.WAIT_MAIN
			_frames = 0
		Phase.WAIT_MAIN:
			if _game == null or _game.get_remote_entity_factory() == null or _game.get_entity_sync() == null:
				_frames += 1
				if _frames >= MAIN_READY_TIMEOUT_FRAMES:
					_failed.append("main scene did not expose remote_entity_factory/entity_sync")
					_finish()
				return
			_test_main()
			_finish()


func _launch_client() -> void:
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"res://tools/m18_client_test.tscn",
	])
	_client_pid = OS.create_process(OS.get_executable_path(), args)
	if _client_pid <= 0:
		_fail("OS.create_process returned %d" % _client_pid)
		return
	_phase = Phase.WAIT_SPAWN_ACK
	_frames = 0


func _on_peer_connected(peer_id: int) -> void:
	if _connected_peer_id != -1:
		return
	_connected_peer_id = peer_id
	if not _remote_entity_factory.request_spawn(
		peer_id,
		"remote_1",
		"res://scripts/network/remote_player.gd",
		{
			"position": Vector3(20.0, 0.0, -10.0),
			"yaw": 0.5,
			"health": 80,
			"marker": 3,
			"display_name": "HostPlayer",
		}
	):
		_fail("request_spawn returned false")


func _on_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	if _finished:
		return
	if not _spawn_ack_received:
		if not _is_ack(packet, 97, 1):
			_fail("unexpected spawn ack from peer %d: %s" % [peer_id, str(packet)])
			return
		_spawn_ack_received = true
		if _connected_peer_id <= 0:
			_fail("received spawn ack without peer id")
			return
		if not _remote_entity_factory.request_despawn(_connected_peer_id, "remote_1"):
			_fail("request_despawn returned false")
			return
		_phase = Phase.WAIT_DESPAWN_ACK
		_frames = 0
		return
	if not _despawn_ack_received:
		if not _is_ack(packet, 97, 2):
			_fail("unexpected despawn ack from peer %d: %s" % [peer_id, str(packet)])
			return
		_despawn_ack_received = true
		_network_manager.leave_session()
		_phase = Phase.ADD_LOCAL_REMOTE
		_frames = 0


func _on_peer_disconnected(_peer_id: int) -> void:
	if not _spawn_ack_received or not _despawn_ack_received:
		_fail("peer disconnected before M18 flow completed")


func _is_ack(packet: PackedByteArray, first: int, second: int) -> bool:
	return packet.size() == 2 and packet[0] == first and packet[1] == second


func _add_local_remote() -> bool:
	var remote_script: Variant = load("res://scripts/network/remote_player.gd")
	if remote_script == null:
		_failed.append("failed to load remote_player.gd")
		_finish()
		return false
	var remote: Node = remote_script.new()
	if remote == null or not remote is Node3D:
		_failed.append("remote_player.gd did not instantiate a Node3D")
		_finish()
		return false
	_local_remote = remote as Node3D
	add_child(_local_remote)
	return true


func _test_local_remote() -> void:
	if _local_remote == null or not is_instance_valid(_local_remote):
		_failed.append("local remote player is not valid")
		return
	_local_remote.apply_network_snapshot({
		"position": Vector3(3, 4, 5),
		"yaw": 1.0,
		"health": 66,
		"marker": 9,
		"display_name": "LocalRemote",
	})
	if _local_remote.global_position.distance_to(Vector3(3, 4, 5)) > 0.01:
		_failed.append("local remote position mismatch: %s" % str(_local_remote.global_position))
	if _local_remote.health != 66:
		_failed.append("local remote health mismatch: %s" % str(_local_remote.health))
	if _local_remote.marker != 9:
		_failed.append("local remote marker mismatch: %s" % str(_local_remote.marker))
	var snapshot: Dictionary = _local_remote.get_network_snapshot()
	if str(snapshot.get("display_name", "")) != "LocalRemote":
		_failed.append("local remote display_name mismatch: %s" % str(snapshot.get("display_name")))


func _test_main() -> void:
	var factory = _game.get_remote_entity_factory()
	var entity_sync = _game.get_entity_sync()
	if factory == null:
		_failed.append("main remote_entity_factory is null")
		return
	if entity_sync == null:
		_failed.append("main entity_sync is null")
		return
	if not factory.has_method("get_state"):
		_failed.append("main remote_entity_factory missing get_state")
		return
	var state: Variant = factory.get_state()
	if not state is Dictionary:
		_failed.append("factory.get_state did not return Dictionary: %s" % str(state))
	elif not state.has("count"):
		_failed.append("factory.get_state missing count")


func _fail(message: String) -> void:
	if _finished:
		return
	_failed.append(message)
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _failed.is_empty():
		print("[M18Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M18Test] FAILED: %s" % entry)
		print("[M18Test] failed")
		get_tree().quit(1)
