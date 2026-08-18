extends Node

## Performance monitor for headless and GPU-backed frame-rate sampling.
## Used for pre-release performance regression checks and QA acceptance.
## NOTE: Headless render metrics do not represent a real GPU workload.
## NOTE: Godot 4.7.1 removed MEMORY_DYNAMIC and PHYSICS_ACTIVE_OBJECTS;
## the snapshot keeps the requested keys using current engine monitors.

const WINDOW_SIZE := 120

var _samples: Array[float] = []
var _min_fps := INF
var _last_delta := 0.0


func _process(delta: float) -> void:
	sample(delta)


func sample(delta: float) -> void:
	_last_delta = delta
	var fps: float = Engine.get_frames_per_second()
	_samples.append(fps)
	if _samples.size() > WINDOW_SIZE:
		_samples.pop_front()
	if fps < _min_fps:
		_min_fps = fps


func reset() -> void:
	_samples.clear()
	_min_fps = INF
	_last_delta = 0.0


func get_avg_fps() -> float:
	if _samples.is_empty():
		return 0.0
	var total := 0.0
	for fps: float in _samples:
		total += fps
	return total / _samples.size()


func get_quality_recommendation() -> String:
	var avg_fps := get_avg_fps()
	if avg_fps >= 55.0:
		return "ultra"
	if avg_fps >= 40.0:
		return "high"
	if avg_fps >= 28.0:
		return "medium"
	return "low"


func get_performance_snapshot() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"avg_fps": get_avg_fps(),
		"min_fps": 0.0 if _samples.is_empty() else _min_fps,
		"frame_time_ms": _last_delta * 1000.0,
		"process_time_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_time_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"physics_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"memory_dynamic_mb": Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX) / 1048576.0,
		"quality_recommendation": get_quality_recommendation(),
	}
