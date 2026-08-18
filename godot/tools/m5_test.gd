extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _hud
var _player
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _deploy_loadout: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_hud() == null or _game.get_player() == null:
				return
			_hud = _game.get_hud()
			_player = _game.get_player()
			if not _hud.is_main_menu_open():
				_failed.append("初始主菜单未打开")
			if not get_tree().paused:
				_failed.append("主菜单阶段游戏未暂停")
			_hud.start_game_requested.emit()
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= 5:
				if not _hud.is_deployment_open():
					_failed.append("开始游戏后部署界面未打开")
				_hud.select_class("recon")
				_hud.select_weapon(2)
				_hud.select_spawn(0)
				_deploy_loadout = _hud.get_selected_loadout()
				if str(_deploy_loadout.get("class_id", "")) != "recon":
					_failed.append("兵种选择未生效：%s" % str(_deploy_loadout))
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 5:
				_hud.deploy_requested.emit(_deploy_loadout, 0)
				_phase = 3
				_frames = 0
		3:
			_frames += 1
			if _frames >= 20:
				if get_tree().paused:
					_failed.append("部署后游戏仍为暂停")
				var state: Dictionary = _player.get_state()
				if not bool(state.get("input_enabled", false)):
					_failed.append("部署后玩家输入未启用")
				var loadout: Dictionary = _player.get_loadout()
				if str(loadout.get("class_id", "")) != "recon":
					_failed.append("玩家配装未应用：%s" % str(loadout))
				var weapons: Node = _player.get_node("Camera3D/WeaponViewmodel")
				if weapons.has_method("get_current_type") and weapons.get_current_type() != "dmr":
					_failed.append("当前武器不是侦察兵主武器：%s" % str(weapons.get_current_type()))
				_finish()


func _finish() -> void:
	if _failed.is_empty():
		print("[M5Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M5Test] FAILED: %s" % entry)
		print("[M5Test] failed")
		get_tree().quit(1)
