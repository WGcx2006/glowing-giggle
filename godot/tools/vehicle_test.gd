extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _vehicle
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _start_position := Vector3.ZERO
var _start_yaw := 0.0
var _unpaused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(delta: float) -> void:
	if not _unpaused:
		if _game == null or _game.get_hud() == null:
			return
		_unpaused = true
		_game.get_hud().hide_main_menu()
		_game.get_hud().hide_deployment_menu()
		_game.get_tree().paused = false
		_game.get_player().set_input_enabled(true)
		return
	match _phase:
		0:
			if _game == null or _game.get_vehicle() == null:
				return
			_vehicle = _game.get_vehicle()
			_verify_basic_state()
			_phase = 1
			_start_position = _vehicle.global_position
			_frames = 0
		1:
			_vehicle.drive(1.0, 0.0, false, delta)
			_frames += 1
			if _frames % 15 == 0:
				var space: PhysicsDirectSpaceState3D = _vehicle.get_world_3d().direct_space_state
				var params := PhysicsRayQueryParameters3D.create(
					_vehicle.global_position + Vector3.UP * 5.0,
					_vehicle.global_position + Vector3.DOWN * 30.0,
					0xFFFFFFFF
				)
				params.exclude = [_vehicle.get_rid()]
				var hit := space.intersect_ray(params)
				var hit_info := "无"
				if not hit.is_empty():
					hit_info = "%s @y=%.2f" % [str(hit.get("collider").name), float(hit.get("position", Vector3.ZERO).y)]
				print("[VehicleTest] frame=%d pos=%s vel=%s yaw=%.3f ground_hit=%s" % [
					_frames,
					str(_vehicle.global_position.round()),
					str(_vehicle.linear_velocity.round()),
					_vehicle.rotation.y,
					hit_info
				])
			if _frames >= 60:
				_verify_forward_motion()
				_phase = 2
				_start_yaw = _vehicle.rotation.y
				_frames = 0
		2:
			_vehicle.drive(0.0, 1.0, false, delta)
			_frames += 1
			if _frames >= 60:
				_verify_yaw_change()
				_phase = 3
		3:
			_verify_enter_exit()
			_phase = 4
		4:
			_verify_damage()
			_finish()


func _verify_basic_state() -> void:
	if _vehicle == null:
		_failed.append("get_vehicle() 返回空")
		return
	if not _vehicle.is_alive():
		_failed.append("is_alive() 初始不为 true")
	if not is_equal_approx(float(_vehicle.health), 220.0):
		_failed.append("health 初始值不是 220，实际 %s" % str(_vehicle.health))


func _verify_forward_motion() -> void:
	var displacement: float = _vehicle.global_position.distance_to(_start_position)
	if displacement <= 1.0:
		_failed.append("前进位移 %.3f 米，未超过 1 米" % displacement)


func _verify_yaw_change() -> void:
	var yaw_delta: float = absf(_vehicle.rotation.y - _start_yaw)
	if yaw_delta <= 0.1:
		_failed.append("转向后 yaw 变化 %.4f 弧度，过小" % yaw_delta)


func _verify_enter_exit() -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		_failed.append("进入/退出测试时车辆不可用")
		return
	_game.enter_vehicle(_vehicle)
	if not _game.is_in_vehicle():
		_failed.append("enter_vehicle() 后 is_in_vehicle() 不为 true")
	_game.exit_vehicle()
	if _game.is_in_vehicle():
		_failed.append("exit_vehicle() 后 is_in_vehicle() 不为 false")


func _verify_damage() -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		_failed.append("伤害测试时车辆不可用")
		return
	_vehicle.take_damage(50.0)
	if not is_equal_approx(float(_vehicle.health), 170.0):
		_failed.append("take_damage(50) 后 health 不是 170，实际 %s" % str(_vehicle.health))
	_vehicle.take_damage(999.0)
	if _vehicle.is_alive():
		_failed.append("take_damage(999) 后 is_alive() 仍为 true")


func _finish() -> void:
	if _failed.is_empty():
		print("[VehicleTest] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[VehicleTest] FAILED: %s" % entry)
		print("[VehicleTest] failed")
		get_tree().quit(1)
