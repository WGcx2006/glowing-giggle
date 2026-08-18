extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")
const JEEP_SCENE := preload("res://scenes/vehicles/jeep.tscn")
const TANK_SCENE := preload("res://scenes/vehicles/tank.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const SERVER_PORT := 7792
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
var _stub_entity
var _jeep
var _tank
var _game
var _phase := 0
var _frames := 0
var _client_pid := -1
var _state_broadcast := false
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

	_network_manager.peer_connected.connect(_on_peer_connected)
	_network_manager.packet_received.connect(_on_packet_received)
	if not _network_manager.host_session("M16Test", SERVER_PORT):
		_fail("host_session returned false")


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
				_network_manager.leave_session()
				_phase = 2
				_frames = 0
				return
			_frames += 1
			if _frames > PACKET_TIMEOUT_FRAMES:
				_failed.append("ack timeout after %d frames" % PACKET_TIMEOUT_FRAMES)
				_finish()
		2:
			_jeep = JEEP_SCENE.instantiate()
			add_child(_jeep)
			_phase = 3
			_frames = 0
		3:
			_frames += 1
			if _frames < 2:
				return
			_test_vehicle(_jeep, "jeep")
			_tank = TANK_SCENE.instantiate()
			add_child(_tank)
			_phase = 4
			_frames = 0
		4:
			_frames += 1
			if _frames < 2:
				return
			_test_vehicle(_tank, "tank")
			_phase = 5
			_frames = 0
		5:
			if _game == null:
				_game = MAIN_SCENE.instantiate()
				add_child(_game)
				_phase = 6
				_frames = 0
				return
		6:
			if _game == null or _game.get_entity_sync() == null or _game.get_player() == null:
				_frames += 1
				if _frames >= MAIN_READY_TIMEOUT_FRAMES:
					_failed.append("main scene did not expose entity_sync/player")
					_finish()
				return
			_test_main()
			_finish()


func _launch_client() -> void:
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"res://tools/m16_client_test.tscn",
	])
	_client_pid = OS.create_process(OS.get_executable_path(), args)
	if _client_pid <= 0:
		_fail("OS.create_process returned %d" % _client_pid)
		return
	_phase = 1
	_frames = 0


func _on_peer_connected(_peer_id: int) -> void:
	if _state_broadcast:
		return
	_state_broadcast = true
	_stub_entity.state = {
		"position": Vector3(12.5, 0.0, -8.0),
		"yaw": 0.8,
		"marker": 7,
	}
	if not _entity_sync.broadcast_entity_state("player_1"):
		_failed.append("broadcast_entity_state returned false")
		_finish()


func _on_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	if _ack_received:
		return
	_ack_peer_id = peer_id
	_ack = packet.duplicate()
	_ack_received = true


func _verify_ack() -> void:
	if _ack.size() != 2 or _ack[0] != 99 or _ack[1] != 1:
		_failed.append("unexpected ack from peer %d: %s" % [_ack_peer_id, str(_ack)])


func _test_vehicle(vehicle, label: String) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		_failed.append("%s is not valid" % label)
		return
	var snapshot: Dictionary = vehicle.get_network_snapshot()
	for key in ["position", "yaw", "health", "max_health", "alive", "animation"]:
		if not snapshot.has(key):
			_failed.append("%s snapshot missing %s" % [label, key])
	vehicle.apply_network_snapshot({
		"position": Vector3(1.0, 2.0, 3.0),
		"yaw": 0.5,
		"health": 99,
	})
	if vehicle.global_position.distance_to(Vector3(1.0, 2.0, 3.0)) > 0.01:
		_failed.append("%s position mismatch after apply: %s" % [label, str(vehicle.global_position)])
	if vehicle.health != 99.0:
		_failed.append("%s health mismatch after apply: %s" % [label, str(vehicle.health)])


func _test_main() -> void:
	var entity_sync = _game.get_entity_sync()
	var player = _game.get_player()
	if entity_sync == null:
		_failed.append("main entity_sync is null")
		return
	if player == null:
		_failed.append("main player is null")
		return
	for entity_id in ["player", "jeep", "tank"]:
		if entity_sync.get_entity_node(entity_id) == null:
			_failed.append("main entity_sync missing %s" % entity_id)
	var player_snapshot: Dictionary = player.get_network_snapshot()
	if not player_snapshot.has("health"):
		_failed.append("player snapshot missing health")
	player.apply_network_snapshot({
		"position": Vector3(5.0, 0.0, 5.0),
		"yaw": 1.0,
		"health": 77,
	})
	var applied_snapshot: Dictionary = player.get_network_snapshot()
	if int(applied_snapshot.get("health", -1)) != 77:
		_failed.append("player health mismatch after apply: %s" % str(applied_snapshot.get("health")))


func _fail(message: String) -> void:
	_failed.append(message)
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _failed.is_empty():
		print("[M16Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M16Test] FAILED: %s" % entry)
		print("[M16Test] failed")
		get_tree().quit(1)
