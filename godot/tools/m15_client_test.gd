extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")

const SERVER_ADDRESS := "127.0.0.1"
const SERVER_PORT := 7790
const FRAME_TIMEOUT := 600
const PASS_DELAY_FRAMES := 5

var _network_manager
var _frames := 0
var _pass_frames := 0
var _sent := false
var _finished := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_network_manager = NETWORK_MANAGER_SCRIPT.new()
	_network_manager.name = "NetworkManager"
	add_child(_network_manager)
	_network_manager.connection_failed.connect(_on_connection_failed)
	_network_manager.server_disconnected.connect(_on_server_disconnected)
	if not _network_manager.join_session(SERVER_ADDRESS, SERVER_PORT):
		_fail("join_session returned false")


func _process(_delta: float) -> void:
	if _finished:
		return
	if _sent:
		_pass_frames += 1
		if _pass_frames >= PASS_DELAY_FRAMES:
			_finish()
		return
	_frames += 1
	if _frames > FRAME_TIMEOUT:
		_fail("timeout waiting for connection (%d frames)" % FRAME_TIMEOUT)
		return
	var state: Dictionary = _network_manager.get_network_state()
	if str(state.get("connection_status", "")) == "disconnected":
		_fail("connection dropped before send: %s" % str(state))
		return
	if str(state.get("mode", "")) == "client" and str(state.get("connection_status", "")) == "connected":
		if not _network_manager.send_packet(1, PackedByteArray([42, 7])):
			_fail("send_packet returned false")
			return
		_sent = true
		_pass_frames = 0


func _on_connection_failed() -> void:
	_fail("connection_failed emitted")


func _on_server_disconnected() -> void:
	if not _sent:
		_fail("server disconnected before send")


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	print("[M15ClientTest] FAILED: %s" % message)
	print("[M15ClientTest] failed")
	get_tree().quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[M15ClientTest] passed")
	get_tree().quit(0)
