extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")
const ENTITY_BROADCASTER_SCRIPT := preload("res://scripts/network/entity_broadcaster.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const SERVER_PORT := 7793
const BROADCAST_INTERVAL := 0.05
const CLIENT_LAUNCH_DELAY_FRAMES := 10
const PACKET_TIMEOUT_FRAMES := 600
const MAIN_READY_TIMEOUT_FRAMES := 180


class StubEntity extends Node3D:
	var state: Dictionary = {
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"marker": 0,
	}

	func get_network_snapshot() -> Dictionary:
		return state

	func apply_network_snapshot(snapshot: Dictionary) -> void:
		state = snapshot.duplicate(true)


var _network_manager
var _entity_sync
var _entity_broadcaster
var _stub_entity
var _game
var _phase := 0
var _frames := 0
var _client_pid := -1
var _peer_connected := false
var _ack_peer_id := -1
var _ack := PackedByteArray()
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

	_stub_entity = StubEntity.new()
	_stub_entity.name = "StubEntity"
	add_child(_stub_entity)
	_entity_sync.register_entity("player_1", _stub_entity)

	_entity_broadcaster = ENTITY_BROADCASTER_SCRIPT.new()
	_entity_broadcaster.name = "EntityBroadcaster"
	add_child(_entity_broadcaster)
	_entity_broadcaster.setup(_entity_sync)
	_entity_broadcaster.add_entity_id("player_1")
	_entity_broadcaster.set_interval(BROADCAST_INTERVAL)

	_network_manager.peer_connected.connect(_on_peer_connected)
	_network_manager.packet_received.connect(_on_packet_received)

	if not _network_manager.host_session("M17Test", SERVER_PORT):
		_fail("host_session returned false")
		return
	_entity_broadcaster.set_enabled(true)


func _physics_process(_delta: float) -> void:
	if _finished:
		return
	match _phase:
		0:
			_frames += 1
			if _frames >= CLIENT_LAUNCH_DELAY_FRAMES:
				_launch_client()
		1:
			if _ack_received:
				_verify_ack()
				if not _failed.is_empty():
					_finish()
					return
				if _entity_broadcaster.get_broadcast_count() <= 0:
					_failed.append("broadcast_count is 0 after client ack")
				if not _entity_broadcaster.is_enabled():
					_failed.append("broadcaster is not enabled after client ack")
				if not _failed.is_empty():
					_finish()
					return
				_network_manager.leave_session()
				_entity_broadcaster.set_enabled(false)
				_phase = 2
				_frames = 0
				return
			_frames += 1
			if _frames > PACKET_TIMEOUT_FRAMES:
				_failed.append("ack timeout after %d frames" % PACKET_TIMEOUT_FRAMES)
				_finish()
		2:
			if _game == null:
				_game = MAIN_SCENE.instantiate()
				add_child(_game)
				_phase = 3
				_frames = 0
				return
		3:
			if _game == null or _game.get_entity_broadcaster() == null or _game.get_entity_sync() == null:
				_frames += 1
				if _frames >= MAIN_READY_TIMEOUT_FRAMES:
					_failed.append("main scene did not expose entity_broadcaster/entity_sync")
					_finish()
				return
			_test_main()
			_finish()


func _launch_client() -> void:
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"res://tools/m17_client_test.tscn",
	])
	_client_pid = OS.create_process(OS.get_executable_path(), args)
	if _client_pid <= 0:
		_fail("OS.create_process returned %d" % _client_pid)
		return
	_phase = 1
	_frames = 0


func _on_peer_connected(_peer_id: int) -> void:
	if _peer_connected:
		return
	_peer_connected = true
	_stub_entity.state = {
		"position": Vector3(12.5, 0.0, -8.0),
		"yaw": 0.8,
		"marker": 7,
	}


func _on_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	if _ack_received:
		return
	_ack_peer_id = peer_id
	_ack = packet.duplicate()
	_ack_received = true


func _verify_ack() -> void:
	if _ack.size() != 2 or _ack[0] != 98 or _ack[1] != 1:
		_failed.append("unexpected ack from peer %d: %s" % [_ack_peer_id, str(_ack)])


func _test_main() -> void:
	var entity_sync = _game.get_entity_sync()
	var broadcaster = _game.get_entity_broadcaster()
	if entity_sync == null or broadcaster == null:
		_failed.append("main entity_sync/broadcaster is null")
		return

	_game._on_host_session_requested("MainM17")
	if not broadcaster.is_enabled():
		_failed.append("main broadcaster not enabled after host session")
	var entity_ids: Array = broadcaster.get_entity_ids()
	for entity_id in ["player", "jeep", "tank"]:
		if not entity_ids.has(entity_id):
			_failed.append("main broadcaster missing entity id: %s" % entity_id)

	_game._on_leave_session_requested()
	if broadcaster.is_enabled():
		_failed.append("main broadcaster still enabled after leave session")


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	print("[M17Test] FAILED: %s" % message)
	print("[M17Test] failed")
	get_tree().quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _failed.is_empty():
		print("[M17Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M17Test] FAILED: %s" % entry)
		print("[M17Test] failed")
		get_tree().quit(1)
