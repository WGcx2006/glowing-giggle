extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")
const REMOTE_ENTITY_FACTORY_SCRIPT := preload("res://scripts/network/remote_entity_factory.gd")
const SESSION_ENTITY_ACCESS_SCRIPT := preload("res://scripts/network/session_entity_access.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const SERVER_PORT := 7795
const CLIENT_LAUNCH_DELAY_FRAMES := 10
const PACKET_TIMEOUT_FRAMES := 600
const MAIN_READY_TIMEOUT_FRAMES := 180

enum Phase {
	LAUNCH_CLIENT,
	WAIT_ACK,
	ADD_LOCAL_REMOTE,
	WAIT_LOCAL_REMOTE_FRAME,
	ADD_MAIN,
	WAIT_MAIN,
}

var _network_manager
var _entity_sync
var _remote_entity_factory
var _session_entity_access
var _local_remote: Node3D
var _game: Node3D
var _phase := Phase.LAUNCH_CLIENT
var _frames := 0
var _client_pid := -1
var _ack_received := false
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

	_session_entity_access = SESSION_ENTITY_ACCESS_SCRIPT.new()
	_session_entity_access.name = "SessionEntityAccess"
	add_child(_session_entity_access)
	_session_entity_access.setup(
		_network_manager,
		_remote_entity_factory,
		"res://scripts/network/remote_player.gd",
		"res://scripts/network/remote_vehicle.gd"
	)

	_network_manager.peer_disconnected.connect(_on_peer_disconnected)
	_network_manager.packet_received.connect(_on_packet_received)

	if not _network_manager.host_session("M19Test", SERVER_PORT):
		_fail("host_session returned false")
		return
	_session_entity_access.enable()
	if not _session_entity_access.is_enabled():
		_fail("session entity access did not enable after host_session")


func _physics_process(_delta: float) -> void:
	if _finished:
		return
	match _phase:
		Phase.LAUNCH_CLIENT:
			_frames += 1
			if _frames >= CLIENT_LAUNCH_DELAY_FRAMES:
				_launch_client()
		Phase.WAIT_ACK:
			_frames += 1
			if _frames > PACKET_TIMEOUT_FRAMES:
				_failed.append("client ack timeout after %d frames" % PACKET_TIMEOUT_FRAMES)
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
			if not _is_main_ready():
				_frames += 1
				if _frames >= MAIN_READY_TIMEOUT_FRAMES:
					_failed.append("main scene did not expose session_entity_access/remote_entity_factory/entity_sync")
					_finish()
				return
			_test_main()
			_finish()


func _launch_client() -> void:
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"res://tools/m19_client_test.tscn",
	])
	_client_pid = OS.create_process(OS.get_executable_path(), args)
	if _client_pid <= 0:
		_fail("OS.create_process returned %d" % _client_pid)
		return
	_phase = Phase.WAIT_ACK
	_frames = 0


func _on_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	if _finished or _ack_received or _phase != Phase.WAIT_ACK:
		return
	if packet.size() != 2 or packet[0] != 95 or packet[1] != 1:
		_fail("unexpected client packet from peer %d: %s" % [peer_id, str(packet)])
		return
	_ack_received = true
	_session_entity_access.disable()
	if _session_entity_access.is_enabled():
		_fail("session entity access remained enabled after disable")
		return
	_network_manager.leave_session()
	_phase = Phase.ADD_LOCAL_REMOTE
	_frames = 0


func _on_peer_disconnected(_peer_id: int) -> void:
	if _finished or _ack_received:
		return
	_fail("peer disconnected before client ack")


func _add_local_remote() -> bool:
	var remote_script: Variant = load("res://scripts/network/remote_vehicle.gd")
	if remote_script == null:
		_failed.append("failed to load remote_vehicle.gd")
		_finish()
		return false
	var remote: Node = remote_script.new()
	if remote == null or not remote is Node3D:
		_failed.append("remote_vehicle.gd did not instantiate a Node3D")
		_finish()
		return false
	_local_remote = remote as Node3D
	add_child(_local_remote)
	return true


func _test_local_remote() -> void:
	if _local_remote == null or not is_instance_valid(_local_remote):
		_failed.append("local remote vehicle is not valid")
		return
	_local_remote.apply_network_snapshot({
		"position": Vector3(4, 1, 2),
		"yaw": 0.3,
		"health": 120.0,
		"marker": 5,
		"display_name": "LocalVehicle",
		"vehicle_type": "tank",
	})
	if _local_remote.global_position.distance_to(Vector3(4, 1, 2)) > 0.01:
		_failed.append("local remote vehicle position mismatch: %s" % str(_local_remote.global_position))
	if _local_remote.health != 120.0:
		_failed.append("local remote vehicle health mismatch: %s" % str(_local_remote.health))
	var snapshot: Dictionary = _local_remote.get_network_snapshot()
	if str(snapshot.get("display_name", "")) != "LocalVehicle":
		_failed.append("local remote vehicle display_name mismatch: %s" % str(snapshot.get("display_name")))


func _is_main_ready() -> bool:
	if _game == null or not is_instance_valid(_game):
		return false
	if _game.get_session_entity_access() == null:
		return false
	if _game.get_remote_entity_factory() == null:
		return false
	if _game.get_entity_sync() == null:
		return false
	return true


func _test_main() -> void:
	var access = _game.get_session_entity_access()
	var factory = _game.get_remote_entity_factory()
	var entity_sync = _game.get_entity_sync()
	if access == null:
		_failed.append("main session_entity_access is null")
		return
	if factory == null:
		_failed.append("main remote_entity_factory is null")
		return
	if entity_sync == null:
		_failed.append("main entity_sync is null")
		return
	if not access.has_method("is_enabled"):
		_failed.append("main session_entity_access missing is_enabled")
		return
	if access.is_enabled():
		_failed.append("main session_entity_access enabled before host session")
		return
	_game._on_host_session_requested("MainM19")
	if not access.is_enabled():
		_failed.append("main session_entity_access did not enable after host session request")
		return
	_game._on_leave_session_requested()
	if access.is_enabled():
		_failed.append("main session_entity_access remained enabled after leave session request")


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
		print("[M19Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M19Test] FAILED: %s" % entry)
		print("[M19Test] failed")
		get_tree().quit(1)
