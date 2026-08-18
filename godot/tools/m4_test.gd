extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _enemy_system
var _vehicle
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _explosion_seen := false
var _objective_states_ok := false
var _vehicle_driven_ok := false
var _support_ok := false
var _zones_ok := false
var _grenade_unit = null
var _ai_command_seen := false


func _ready() -> void:
	process_physics_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)
	get_tree().paused = false


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_node_or_null("Enemies") == null:
				return
			_enemy_system = _game.get_node("Enemies")
			_vehicle = _game.get_vehicle()
			if _enemy_system.has_method("set_active"):
				_enemy_system.set_active(true)
			_verify_contracts()
			_enemy_system.explosion_detonated.connect(_on_test_explosion)
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= 30:
				_verify_zones()
				_verify_support()
				_find_grenade_unit()
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames == 5 and _grenade_unit != null:
				var grenade_ok := false
				var offsets := [
					Vector3(0.0, 0.0, 4.0),
					Vector3(0.0, 0.0, -4.0),
					Vector3(4.0, 0.0, 0.0),
					Vector3(-4.0, 0.0, 0.0),
					Vector3(0.0, 2.0, 4.0),
				]
				for offset in offsets:
					if _grenade_unit.throw_grenade(_grenade_unit.global_position + offset):
						grenade_ok = true
						break
				if not grenade_ok:
					_failed.append("throw_grenade() 返回 false")
			if _frames >= 240:
				if not _explosion_seen:
					_failed.append("AI 手雷未触发爆炸信号")
				_verify_objective_states()
				_phase = 3
				_frames = 0
		3:
			if _frames == 0:
				_prepare_vehicle_area()
			var drive_state: Dictionary = _vehicle.get_ai_drive_state()
			if float(drive_state.get("throttle", 0.0)) != 0.0 or float(drive_state.get("steer", 0.0)) != 0.0:
				_ai_command_seen = true
			_frames += 1
			if _frames >= 240:
				_verify_vehicle_ai()
				_finish()


func _verify_contracts() -> void:
	var required_methods := [
		"set_capture_zones",
		"set_vehicle",
		"get_objective_zones",
		"request_support",
		"get_nearest_support_request",
		"emit_enemy_explosion",
		"update_vehicle_ai",
		"get_ai_summary",
	]
	for method_name in required_methods:
		if not _enemy_system.has_method(method_name):
			_failed.append("enemy_system 缺少方法：%s" % method_name)
	if _vehicle == null or not _vehicle.has_method("ai_drive") or not _vehicle.has_method("get_ai_drive_state"):
		_failed.append("载具缺少 ai_drive/get_ai_drive_state")


func _verify_zones() -> void:
	var zones: Array = _enemy_system.get_objective_zones()
	if zones.size() < 4:
		_failed.append("get_objective_zones() 数量不足：%s" % str(zones.size()))
		return
	for zone in zones:
		var entry: Dictionary = zone
		if not entry.has("position") or not entry.has("radius"):
			_failed.append("据点状态缺少 position/radius：%s" % str(entry))
			return
	_zones_ok = true


func _verify_support() -> void:
	var request_pos := Vector3(20.0, 0.0, 20.0)
	_enemy_system.request_support(request_pos, "red")
	var nearest: Vector3 = _enemy_system.get_nearest_support_request(Vector3(18.0, 0.0, 18.0), "red")
	if nearest.distance_to(request_pos) > 2.0:
		_failed.append("get_nearest_support_request() 未返回请求点：%s" % str(nearest))
		return
	_support_ok = true


func _find_grenade_unit() -> void:
	for child in _enemy_system.get_children():
		if child.has_method("throw_grenade") and child.has_method("get_state_summary"):
			_grenade_unit = child
			return
	if _grenade_unit == null:
		_failed.append("未找到可投掷手雷的 AI 单位")


func _verify_objective_states() -> void:
	var states: Array = []
	var any_objective := false
	for child in _enemy_system.get_children():
		if not child.has_method("get_state_summary"):
			continue
		var summary: Dictionary = child.get_state_summary()
		var state_name: String = str(summary.get("state", ""))
		states.append(state_name)
		if state_name in ["ASSAULT", "DEFEND", "SUPPORT", "GRENADE", "ENGAGE", "SEEK_COVER", "COVER"]:
			any_objective = true
	if not any_objective:
		_failed.append("AI 单位未进入据点/战术状态：%s" % str(states))
		return
	_objective_states_ok = true


func _verify_vehicle_ai() -> void:
	var summary: Dictionary = _enemy_system.get_ai_summary()
	var driven: bool = bool(summary.get("vehicle_driven", false))
	if not driven:
		_failed.append("get_ai_summary().vehicle_driven 为 false")
		return
	if not _ai_command_seen:
		_failed.append("AI 未向载具发出驾驶指令")
		return
	_vehicle_driven_ok = true


func _prepare_vehicle_area() -> void:
	if not _vehicle.has_method("set_ai_driver"):
		return
	_vehicle.sleeping = false
	_vehicle.freeze = false


func _on_test_explosion(_position: Vector3, _radius: float, _power: float, _type: String, _source: String) -> void:
	_explosion_seen = true


func _finish() -> void:
	if _failed.is_empty():
		print("[M4Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M4Test] FAILED: %s" % entry)
		print("[M4Test] failed")
		get_tree().quit(1)
