extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _enemy_system
var _vehicle
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _start_pos := Vector3.ZERO
var _blocked_seen := false
var _speed_max := 0.0
var _request_prepare := false
var _prepared := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)
	get_tree().paused = false


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_vehicle() == null or _game.get_node_or_null("Enemies") == null:
				return
			_enemy_system = _game.get_node("Enemies")
			_vehicle = _game.get_vehicle()
			if _enemy_system.has_method("set_active"):
				_enemy_system.set_active(true)
			_request_prepare = true
		1:
			_frames += 1
			var drive_state: Dictionary = _vehicle.get_ai_drive_state()
			if bool(drive_state.get("forward_blocked", false)):
				_blocked_seen = true
			_speed_max = maxf(_speed_max, float(drive_state.get("speed", 0.0)))
			if _frames >= 240:
				_verify_ai_driving()
				_finish()


func _process(_delta: float) -> void:
	if _request_prepare and not _prepared:
		_prepare_course()
		_prepared = true
		_phase = 1
		_frames = 0


func _prepare_course() -> void:
	var terrain: Node = _game.get_environment().get_node("Terrain")
	for child in terrain.get_children():
		if child is CollisionShape3D:
			child.disabled = true
	var props: Node = _game.get_environment().get_node("Props")
	for child in props.get_children():
		if child is StaticBody3D:
			child.collision_layer = 0
			child.collision_mask = 0
	_add_box_static("M8Floor", Vector3(0.0, -0.25, 0.0), Vector3(60.0, 0.5, 60.0))
	_add_box_static("M8Obstacle", Vector3(0.0, 0.8, -3.0), Vector3(4.0, 1.6, 0.5))
	_start_pos = Vector3(0.0, 0.5, 0.0)
	_vehicle.freeze = true
	_vehicle.call("_apply_setup", _start_pos, 0.0)
	_vehicle.freeze = true
	var rid: RID = _vehicle.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), _start_pos))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	_vehicle.freeze = false
	_vehicle.sleeping = false


func _add_box_static(node_name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	body.add_child(collision_shape)
	body.global_position = center
	return body


func _verify_ai_driving() -> void:
	var summary: Dictionary = _enemy_system.get_ai_summary()
	if not bool(summary.get("vehicle_driven", false)):
		_failed.append("AI 未分配载具司机")
	if not _blocked_seen:
		_failed.append("未检测到前方障碍")
	var drive_state: Dictionary = _vehicle.get_ai_drive_state()
	if not drive_state.has("forward_blocked") or not drive_state.has("forward_hit_distance"):
		_failed.append("载具 AI 状态缺少 forward_blocked/forward_hit_distance")
	var displaced: float = Vector2(_vehicle.global_position.x, _vehicle.global_position.z).distance_to(
		Vector2(_start_pos.x, _start_pos.z))
	if _speed_max <= 0.5 and displaced < 0.5:
		_failed.append("AI 载具未移动：speed_max=%s displaced=%s" % [str(_speed_max), str(displaced)])


func _finish() -> void:
	if _failed.is_empty():
		print("[M8Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M8Test] FAILED: %s" % entry)
		print("[M8Test] failed")
		get_tree().quit(1)
