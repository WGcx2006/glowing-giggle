extends Node

signal broadcast_tick(entity_id: String)
signal broadcast_enabled_changed(enabled: bool)

var _entity_sync
var _entity_ids: Array = []
var _enabled := false
var _interval := 0.1
var _timer := 0.0
var _broadcast_count := 0
var _last_broadcast_time := -1.0


func setup(entity_sync) -> void:
	_entity_sync = entity_sync


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	broadcast_enabled_changed.emit(_enabled)


func is_enabled() -> bool:
	return _enabled


func set_interval(seconds: float) -> void:
	_interval = maxf(0.02, seconds)


func get_interval() -> float:
	return _interval


func add_entity_id(entity_id: String) -> void:
	if entity_id.is_empty():
		return
	if _entity_ids.has(entity_id):
		return
	_entity_ids.append(entity_id)


func remove_entity_id(entity_id: String) -> void:
	_entity_ids.erase(entity_id)


func get_entity_ids() -> Array:
	return _entity_ids.duplicate()


func broadcast_once() -> int:
	if _entity_sync == null or not is_instance_valid(_entity_sync):
		return 0
	var success_count := 0
	for entity_id: String in _entity_ids:
		if _entity_sync.broadcast_entity_state(entity_id) == true:
			success_count += 1
			_broadcast_count += 1
			broadcast_tick.emit(entity_id)
	return success_count


func _process(delta: float) -> void:
	if not _enabled or _entity_sync == null or not is_instance_valid(_entity_sync):
		_timer = 0.0
		return
	_timer += delta
	if _timer >= _interval:
		broadcast_once()
		_timer = 0.0
		_last_broadcast_time = Time.get_ticks_msec()


func get_broadcast_count() -> int:
	return _broadcast_count


func get_last_broadcast_time() -> int:
	return int(_last_broadcast_time)


func get_state() -> Dictionary:
	return {
		"enabled": _enabled,
		"interval": _interval,
		"entity_ids": _entity_ids.duplicate(),
		"broadcast_count": _broadcast_count,
		"last_broadcast_time": get_last_broadcast_time(),
	}
