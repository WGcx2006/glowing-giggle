extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")

const SERVER_ADDRESS := "127.0.0.1"
const SERVER_PORT := 7793
const FRAME_TIMEOUT := 600
const PASS_DELAY_FRAMES := 5


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
var _frames := 0
var _pass_frames := 0
var _state_received := false
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

	_stub_entity = StubEntity.new()
	_stub_entity.name = "StubEntity"
	add_child(_stub_entity)
	_entity_sync.register_entity("player_1", _stub_entity)

	_entity_sync.entity_state_received.connect(_on_entity_state_received)
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
		_fail("timeout waiting for entity_state after %d frames" % FRAME_TIMEOUT)


func _on_entity_state_received(peer_id: int, entity_id: String, state: Dictionary) -> void:
	if _state_received:
		return
	_state_received = true

	var failures: Array[String] = []
	if peer_id != 1:
		failures.append("unexpected peer_id: %d" % peer_id)
	if entity_id != "player_1":
		failures.append("unexpected entity_id: %s" % entity_id)
	if int(state.get("marker", -1)) != 7:
		failures.append("marker mismatch: %s" % str(state.get("marker")))
	var received_position: Variant = state.get("position")
	if not received_position is Vector3:
		failures.append("position is not Vector3: %s" % str(received_position))
	elif received_position.distance_to(Vector3(12.5, 0.0, -8.0)) > 0.01:
		failures.append("position mismatch: %s" % str(received_position))

	if not failures.is_empty():
		_fail("entity_state validation failed: %s" % "; ".join(failures))
		return
	if not _network_manager.send_packet(1, PackedByteArray([98, 1])):
		_fail("send_packet returned false")
		return
	_ack_sent = true
	_pass_frames = 0


func _on_connection_failed() -> void:
	_fail("connection_failed emitted")


func _on_server_disconnected() -> void:
	if not _ack_sent:
		_fail("server disconnected before ack")


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	print("[M17ClientTest] FAILED: %s" % message)
	print("[M17ClientTest] failed")
	get_tree().quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[M17ClientTest] passed")
	get_tree().quit(0)
