extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _network_manager
var _save_manager
var _failed: Array[String] = []
var _phase := 0
var _frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_network_manager() == null or _game.get_save_manager() == null:
				return
			_network_manager = _game.get_network_manager()
			_save_manager = _game.get_save_manager()
			_save_manager.clear_profile()
			_verify_network_contract()
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= 5:
				_verify_save_contract()
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 5:
				_verify_deploy_save()
				_finish()


func _verify_network_contract() -> void:
	if not _network_manager.host_session("M6Test"):
		_failed.append("host_session() 返回 false")
	var host_state: Dictionary = _network_manager.get_network_state()
	if str(host_state.get("mode", "")) != "host":
		_failed.append("host 状态错误：%s" % str(host_state))
	_network_manager.leave_session()
	if not _network_manager.join_session("127.0.0.1"):
		_failed.append("join_session() 返回 false")
	var client_state: Dictionary = _network_manager.get_network_state()
	if str(client_state.get("mode", "")) != "client":
		_failed.append("client 状态错误：%s" % str(client_state))
	_network_manager.leave_session()
	var offline_state: Dictionary = _network_manager.get_network_state()
	if str(offline_state.get("mode", "")) != "offline":
		_failed.append("leave 后状态不是 offline：%s" % str(offline_state))


func _verify_save_contract() -> void:
	var test_data := {
		"quality": "ultra",
		"sensitivity": 1.2,
		"loadout": {"class_id": "recon", "primary_index": 2, "secondary_index": 1},
	}
	if not _save_manager.save_profile(test_data):
		_failed.append("save_profile() 返回 false")
		return
	var loaded: Dictionary = _save_manager.load_profile()
	if str(loaded.get("quality", "")) != "ultra" or absf(float(loaded.get("sensitivity", 0.0)) - 1.2) > 0.001:
		_failed.append("存档读写不一致：%s" % str(loaded))
	_save_manager.clear_profile()
	var after_clear: Dictionary = _save_manager.load_profile()
	if not after_clear.is_empty():
		_failed.append("clear_profile() 后档案仍存在：%s" % str(after_clear))


func _verify_deploy_save() -> void:
	var loadout := {
		"class_id": "recon",
		"primary_index": 2,
		"secondary_index": 1,
	}
	_game.call("_on_deploy_requested", loadout, 0)
	var saved: Dictionary = _save_manager.load_profile()
	var saved_loadout: Variant = saved.get("loadout", {})
	if not (saved_loadout is Dictionary) or str(saved_loadout.get("class_id", "")) != "recon":
		_failed.append("部署后未保存玩家配装：%s" % str(saved))
	if get_tree().paused:
		_failed.append("部署后游戏仍暂停")


func _finish() -> void:
	if _failed.is_empty():
		print("[M6Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M6Test] FAILED: %s" % entry)
		print("[M6Test] failed")
		get_tree().quit(1)
