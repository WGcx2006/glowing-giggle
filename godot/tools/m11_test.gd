extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _jeep_engine
var _tank_engine
var _ambient
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _initial_pitch := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_jeep_engine() == null:
				return
			_jeep_engine = _game.get_jeep_engine()
			_tank_engine = _game.get_tank_engine()
			_ambient = _game.get_ambient_audio()
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
			_game.get_vehicle().drive(1.0, 0.0, false, _delta)
			if _frames == 5:
				_initial_pitch = float(_jeep_engine.get_engine_pitch())
			if _frames >= 60:
				var rpm: float = float(_jeep_engine.get_rpm())
				var pitch: float = float(_jeep_engine.get_engine_pitch())
				if not bool(_jeep_engine.get_engine_active()):
					_failed.append("吉普引擎未激活")
				if rpm <= 0.1:
					_failed.append("吉普引擎 RPM 未随速度上升：%s" % str(rpm))
				if pitch <= _initial_pitch + 0.01:
					_failed.append("吉普引擎音高未随速度变化：%s -> %s" % [str(_initial_pitch), str(pitch)])
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 5:
				if not bool(_tank_engine.get_engine_active()):
					_failed.append("坦克引擎未激活")
				if not bool(_ambient.get_ambient_active()):
					_failed.append("环境风噪未激活")
				var level: float = float(_ambient.get_ambient_level())
				if level < 0.5 or level > 1.0:
					_failed.append("环境强度异常：%s" % str(level))
				_finish()


func _finish() -> void:
	if _failed.is_empty():
		print("[M11Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M11Test] FAILED: %s" % entry)
		print("[M11Test] failed")
		get_tree().quit(1)
