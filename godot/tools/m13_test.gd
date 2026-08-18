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
			if _frames == 5:
				_hud.show_damage_number(24.0, Vector2(100.0, 100.0))
				_hud.show_damage_number(36.0, Vector2(140.0, 80.0))
			if _frames >= 10:
				if int(_hud.get_active_damage_numbers()) < 2:
					_failed.append("伤害数字未显示：%s" % str(_hud.get_active_damage_numbers()))
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 150:
				if int(_hud.get_active_damage_numbers()) != 0:
					_failed.append("伤害数字未消失：%s" % str(_hud.get_active_damage_numbers()))
				if not _game.has_method("_show_damage_number"):
					_failed.append("main.gd 缺少 _show_damage_number")
				_finish()


func _finish() -> void:
	if _failed.is_empty():
		print("[M13Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M13Test] FAILED: %s" % entry)
		print("[M13Test] failed")
		get_tree().quit(1)
