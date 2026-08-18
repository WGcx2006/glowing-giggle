extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _hud
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
			if _game == null or _game.get_hud() == null:
				return
			_hud = _game.get_hud()
			var loadout := {
				"class_id": "assault",
				"primary_index": 0,
				"secondary_index": 1,
			}
			_game.call("_on_deploy_requested", loadout, 0)
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= 30:
				_verify_hud_state()
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 5:
				_verify_minimap_control()
				_finish()


func _verify_hud_state() -> void:
	var hud_state: Dictionary = _game.call("_build_hud_state")
	if not hud_state.has("minimap"):
		_failed.append("HUD 状态缺少 minimap")
		return
	var minimap_state: Dictionary = hud_state["minimap"]
	var required_keys := ["player_pos", "player_yaw", "enemies", "vehicles", "zones"]
	for key in required_keys:
		if not minimap_state.has(key):
			_failed.append("minimap 缺少键：%s" % key)
	var zones: Array = minimap_state.get("zones", [])
	if zones.size() < 4:
		_failed.append("minimap 据点数量不足：%s" % str(zones.size()))
	var enemies: Array = minimap_state.get("enemies", [])
	if enemies.size() <= 0:
		_failed.append("minimap 未包含敌军信息")


func _verify_minimap_control() -> void:
	var minimap: Control = _hud.get_minimap()
	if minimap == null:
		_failed.append("HUD 未创建 Minimap 控件")
		return
	if minimap.name != "Minimap":
		_failed.append("Minimap 节点名错误：%s" % minimap.name)
	var test_state := {
		"player_pos": Vector3(10.0, 0.0, 20.0),
		"player_yaw": 0.5,
		"zones": [
			{"id": "A", "position": Vector3(-78.0, 0.0, 66.0), "team": "blue", "contested": false},
		],
		"enemies": [],
		"vehicles": [],
	}
	minimap.set_state(test_state)
	var state: Dictionary = minimap.get_state()
	if state.get("player_pos") != test_state["player_pos"]:
		_failed.append("Minimap 状态未保存")
	if not minimap.is_enabled():
		_failed.append("Minimap 默认未启用")


func _finish() -> void:
	if _failed.is_empty():
		print("[M10Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M10Test] FAILED: %s" % entry)
		print("[M10Test] failed")
		get_tree().quit(1)
