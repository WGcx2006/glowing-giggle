extends Node3D

const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const SERVER_PORT := 7790
const CLIENT_LAUNCH_DELAY_FRAMES := 10
const PACKET_TIMEOUT_FRAMES := 600
const MAIN_READY_TIMEOUT_FRAMES := 180

var _network_manager
var _hud
var _game
var _phase := 0
var _frames := 0
var _packet_peer_id := -1
var _packet := PackedByteArray()
var _packet_received := false
var _client_pid := -1
var _failed: Array[String] = []
var _finished := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_network_manager = NETWORK_MANAGER_SCRIPT.new()
	_network_manager.name = "NetworkManager"
	add_child(_network_manager)
	_network_manager.packet_received.connect(_on_packet_received)
	if not _network_manager.host_session("M15Test", SERVER_PORT):
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
			if _packet_received:
				_verify_network_packet()
				_network_manager.leave_session()
				var state: Dictionary = _network_manager.get_network_state()
				if str(state.get("mode", "")) != "offline":
					_failed.append("leave_session did not return offline: %s" % str(state))
				_phase = 2
				_frames = 0
				return
			_frames += 1
			if _frames > PACKET_TIMEOUT_FRAMES:
				var current_state: Dictionary = _network_manager.get_network_state()
				_failed.append("packet timeout after %d frames: %s" % [PACKET_TIMEOUT_FRAMES, str(current_state)])
				_finish()
		2:
			_test_hud()
			_phase = 3
			_frames = 0
		3:
			if _game == null:
				_game = MAIN_SCENE.instantiate()
				add_child(_game)
				_frames = 0
				return
			if _game.get_hud() == null or _game.get_network_manager() == null:
				_frames += 1
				if _frames >= MAIN_READY_TIMEOUT_FRAMES:
					_failed.append("main scene did not expose hud/network_manager")
					_finish()
				return
			_test_main()
			_finish()


func _launch_client() -> void:
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"res://tools/m15_client_test.tscn",
	])
	_client_pid = OS.create_process(OS.get_executable_path(), args)
	if _client_pid <= 0:
		_fail("OS.create_process returned %d" % _client_pid)
		return
	_phase = 1
	_frames = 0


func _on_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	if _packet_received:
		return
	_packet_peer_id = peer_id
	_packet = packet.duplicate()
	_packet_received = true


func _verify_network_packet() -> void:
	if _packet.size() != 2 or _packet[0] != 42 or _packet[1] != 7:
		_failed.append("unexpected packet from peer %d: %s" % [_packet_peer_id, str(_packet)])


func _test_hud() -> void:
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.set_network_state({"mode": "host", "session_name": "M15Test", "connected_peers": 1})
	var host_text: String = _hud.get_network_status_text()
	if not host_text.contains("主机"):
		_failed.append("HUD host status missing 主机: %s" % host_text)
	_hud.set_network_state({"mode": "offline"})
	var offline_text: String = _hud.get_network_status_text()
	if not offline_text.contains("离线"):
		_failed.append("HUD offline status missing 离线: %s" % offline_text)
	_hud.get_parent().remove_child(_hud)
	_hud.free()
	_hud = null


func _test_main() -> void:
	var network_manager = _game.get_network_manager()
	_game.call("_on_host_session_requested", "MainM15")
	var host_state: Dictionary = network_manager.get_network_state()
	if str(host_state.get("mode", "")) != "host":
		_failed.append("Main host mode error: %s" % str(host_state))
	_game.call("_on_leave_session_requested")
	var offline_state: Dictionary = network_manager.get_network_state()
	if str(offline_state.get("mode", "")) != "offline":
		_failed.append("Main leave mode error: %s" % str(offline_state))
	var hud_state: Dictionary = _game.call("_build_hud_state")
	if not hud_state.has("game_mode"):
		_failed.append("Main _build_hud_state missing game_mode")


func _fail(message: String) -> void:
	_failed.append(message)
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _failed.is_empty():
		print("[M15Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M15Test] FAILED: %s" % entry)
		print("[M15Test] failed")
		get_tree().quit(1)
