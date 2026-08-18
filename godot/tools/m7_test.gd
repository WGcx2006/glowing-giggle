extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _performance_monitor
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _snapshot_a: Dictionary = {}
var _snapshot_b: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_performance_monitor() == null:
				return
			_performance_monitor = _game.get_performance_monitor()
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
			if _frames >= 120:
				_snapshot_a = _performance_monitor.get_performance_snapshot()
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 120:
				_snapshot_b = _performance_monitor.get_performance_snapshot()
				_verify_snapshot(_snapshot_a, "第一采样")
				_verify_snapshot(_snapshot_b, "第二采样")
				var avg_a: float = float(_snapshot_a.get("avg_fps", 0.0))
				var avg_b: float = float(_snapshot_b.get("avg_fps", 0.0))
				if avg_a <= 0.0:
					_failed.append("性能采样 avg_fps 无效：%s" % str(avg_a))
				if avg_b < avg_a * 0.5:
					_failed.append("性能明显劣化：%s -> %s" % [str(avg_a), str(avg_b)])
				if int(_snapshot_a.get("object_count", 0)) <= 0:
					_failed.append("对象计数异常：%s" % str(_snapshot_a.get("object_count")))
				_game.get_environment().set_quality("low")
				_phase = 3
				_frames = 0
		3:
			_frames += 1
			if _frames >= 30:
				var snapshot_c: Dictionary = _performance_monitor.get_performance_snapshot()
				if str(snapshot_c.get("quality_recommendation", "")) == "":
					_failed.append("质量建议为空")
				if float(snapshot_c.get("avg_fps", 0.0)) <= 0.0:
					_failed.append("低画质切换后性能采样异常")
				_finish()


func _verify_snapshot(snapshot: Dictionary, label: String) -> void:
	var required_keys := [
		"fps",
		"avg_fps",
		"min_fps",
		"frame_time_ms",
		"process_time_ms",
		"physics_time_ms",
		"object_count",
		"node_count",
		"physics_active_objects",
		"memory_static_mb",
		"memory_dynamic_mb",
		"quality_recommendation",
	]
	for key in required_keys:
		if not snapshot.has(key):
			_failed.append("%s 缺少键：%s" % [label, key])


func _finish() -> void:
	if _failed.is_empty():
		print("[M7Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M7Test] FAILED: %s" % entry)
		print("[M7Test] failed")
		get_tree().quit(1)
