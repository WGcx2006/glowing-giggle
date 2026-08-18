extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _tank
var _player
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _prepared := false
var _destroyed_seen := false
var _speed_max := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)
	get_tree().paused = false


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_tank() == null:
				return
			_tank = _game.get_tank()
			_player = _game.get_player()
			if not _tank.is_in_group("vehicle"):
				_failed.append("坦克未加入 vehicle 组")
			if not _tank.is_alive():
				_failed.append("坦克初始未存活")
			_tank.destroyed.connect(_on_tank_destroyed)
			_request_prepare()
		1:
			_frames += 1
			_tank.drive(1.0, 0.0, false, _delta)
			var snapshot: Dictionary = _tank.get_animation_snapshot()
			_speed_max = maxf(_speed_max, float(snapshot.get("speed", 0.0)))
			if _frames == 10:
				var cannon_ok: bool = _tank.try_fire_cannon(_tank.global_position, Vector3.FORWARD)
				if not cannon_ok:
					_failed.append("坦克主炮首次开火返回 false")
				if _tank.try_fire_cannon(_tank.global_position, Vector3.FORWARD):
					_failed.append("坦克主炮冷却未生效")
				var projectiles: Node = _player.get_node("Projectiles")
				if projectiles.get_child_count() <= 0:
					_failed.append("主炮开火未生成弹体")
			if _frames >= 120:
				if _speed_max <= 0.5:
					_failed.append("坦克驱动速度过低：%s" % str(_speed_max))
				_verify_enter_exit()
				_finish()


func _request_prepare() -> void:
	_prepared = false
	_phase = 1
	_frames = 0


func _process(_delta: float) -> void:
	if not _prepared:
		_prepare_course()
		_prepared = true


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
	_add_box_static("M9Floor", Vector3(0.0, -0.25, 0.0), Vector3(60.0, 0.5, 60.0))
	if _tank.has_method("_apply_setup"):
		_tank.call("_apply_setup", Vector3(0.0, 0.6, 0.0), 0.0)
	else:
		_tank.global_position = Vector3(0.0, 0.6, 0.0)
		_tank.rotation = Vector3(0.0, 0.0, 0.0)
		_tank.linear_velocity = Vector3.ZERO
		_tank.angular_velocity = Vector3.ZERO


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


func _verify_enter_exit() -> void:
	_player.global_position = _tank.global_position + Vector3(0.0, 0.0, 4.0)
	_game.enter_vehicle(_tank)
	if not _game.is_in_vehicle():
		_failed.append("进入坦克失败")
		return
	if not _tank.get_camera().current:
		_failed.append("坦克相机未成为当前相机")
	_game.exit_vehicle()
	if _game.is_in_vehicle():
		_failed.append("退出坦克失败")
	var health_before: float = _tank.health
	_tank.take_damage(50.0)
	if _tank.health >= health_before:
		_failed.append("坦克伤害未生效")
	_tank.take_damage(99999.0)
	if _tank.is_alive():
		_failed.append("坦克被摧毁后仍存活")
	if not _destroyed_seen:
		_failed.append("坦克 destroyed 信号未触发")


func _on_tank_destroyed() -> void:
	_destroyed_seen = true


func _finish() -> void:
	if _failed.is_empty():
		print("[M9Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M9Test] FAILED: %s" % entry)
		print("[M9Test] failed")
		get_tree().quit(1)
