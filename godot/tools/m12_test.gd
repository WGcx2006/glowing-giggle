extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _environment
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
			if _game == null or _game.get_environment() == null:
				return
			_environment = _game.get_environment()
			var loadout := {
				"class_id": "assault",
				"primary_index": 0,
				"secondary_index": 1,
			}
			_game.call("_on_deploy_requested", loadout, 0)
			_environment.set_weather(1, 0.8)
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= 60:
				_verify_weather("rain")
				_environment.set_weather(2)
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 60:
				_verify_weather("snow")
				_environment.set_weather(0)
				_phase = 3
				_frames = 0
		3:
			_frames += 1
			if _frames >= 90:
				var state: Dictionary = _environment.get_weather_state()
				if str(state.get("type", "")) != "clear":
					_failed.append("清空天气类型错误：%s" % str(state))
				if float(state.get("intensity", 1.0)) >= 0.2:
					_failed.append("清空后强度未衰减：%s" % str(state.get("intensity")))
				if bool(state.get("precipitation", true)):
					_failed.append("清空后降水仍开启")
				_finish()


func _verify_weather(expected: String) -> void:
	var state: Dictionary = _environment.get_weather_state()
	if str(state.get("type", "")) != expected:
		_failed.append("天气类型错误，期望 %s：%s" % [expected, str(state)])
	if expected == "rain" and float(state.get("intensity", 0.0)) <= 0.4:
		_failed.append("雨天强度不足：%s" % str(state.get("intensity")))
	if bool(state.get("precipitation", false)) != (expected != "clear"):
		_failed.append("降水状态错误：%s" % str(state))
	if float(state.get("fog_density", -1.0)) < 0.0:
		_failed.append("雾密度异常：%s" % str(state.get("fog_density")))
	if not _environment.has_method("get_weather_fog_density"):
		_failed.append("环境缺少 get_weather_fog_density")


func _finish() -> void:
	if _failed.is_empty():
		print("[M12Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M12Test] FAILED: %s" % entry)
		print("[M12Test] failed")
		get_tree().quit(1)
