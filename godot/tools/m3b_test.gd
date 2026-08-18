extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

const SETTLE_FRAMES := 40
const VAULT_END_FRAMES := 80
const CLIMB_END_FRAMES := 100

var _game
var _player
var _animator
var _vehicle
var _failed: Array[String] = []
var _phase := 0
var _frames := 0
var _drive_frames := 0
var _vault_snapshot_ok := false
var _climb_snapshot_ok := false


func _ready() -> void:
	process_physics_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)
	get_tree().paused = false


func _physics_process(delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_player() == null or _game.get_animator() == null:
				return
			_player = _game.get_player()
			_animator = _game.get_animator()
			_vehicle = _game.get_vehicle()
			_prepare_course()
			_player.spawn(Vector3(0.0, 1.0, 4.5), PI)
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= SETTLE_FRAMES:
				var started: bool = _player.try_start_vault()
				if not started:
					_failed.append("try_start_vault() 返回 false")
					_finish()
					return
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if not _player.is_vaulting():
				_failed.append("vault 开始后 is_vaulting() 为 false")
			var vault_snapshot: Dictionary = _animator.get_pose_snapshot()
			if str(vault_snapshot.get("pose_name", "")) == "vault" \
					or float(vault_snapshot.get("vault_progress", 0.0)) > 0.0:
				_vault_snapshot_ok = true
			if _frames >= VAULT_END_FRAMES:
				if _player.is_vaulting():
					_failed.append("vault 超时后仍未结束")
				if _player.global_position.z <= 6.2:
					_failed.append("vault 未越过障碍：z=%s" % str(_player.global_position.z))
				if not _vault_snapshot_ok:
					_failed.append("vault 期间动画快照未体现 vault 姿势")
				_player.spawn(Vector3(0.0, 1.0, 14.5), PI)
				_phase = 3
				_frames = 0
		3:
			_frames += 1
			if _frames >= SETTLE_FRAMES:
				var started: bool = _player.try_start_climb()
				if not started:
					_failed.append("try_start_climb() 返回 false")
					_finish()
					return
				_phase = 4
				_frames = 0
		4:
			_frames += 1
			if not _player.is_climbing():
				_failed.append("climb 开始后 is_climbing() 为 false")
			var climb_snapshot: Dictionary = _animator.get_pose_snapshot()
			if str(climb_snapshot.get("pose_name", "")) == "climb" \
					or float(climb_snapshot.get("climb_progress", 0.0)) > 0.0:
				_climb_snapshot_ok = true
			if _frames >= CLIMB_END_FRAMES:
				if _player.is_climbing():
					_failed.append("climb 超时后仍未结束")
				if _player.global_position.y <= 2.0:
					_failed.append("climb 未登上墙顶：y=%s" % str(_player.global_position.y))
				if not _climb_snapshot_ok:
					_failed.append("climb 期间动画快照未体现 climb 姿势")
				_phase = 5
				_frames = 0
		5:
			_drive_frames += 1
			_vehicle.drive(1.0, 0.6, false, delta)
			if _drive_frames >= 12:
				var snapshot: Dictionary = _vehicle.get_animation_snapshot()
				_verify_vehicle_snapshot(snapshot)
				_finish()


func _prepare_course() -> void:
	var enemies: Node = _game.get_node_or_null("Enemies")
	if enemies != null and enemies.has_method("set_active"):
		enemies.set_active(false)
	var terrain: Node = _game.get_environment().get_node("Terrain")
	for child in terrain.get_children():
		if child is CollisionShape3D:
			child.disabled = true
	var props: Node = _game.get_environment().get_node("Props")
	for child in props.get_children():
		if child is StaticBody3D:
			child.collision_layer = 0
			child.collision_mask = 0
	_add_box_static("M3bFloor", Vector3(0.0, -0.25, 11.0), Vector3(20.0, 0.5, 30.0))
	_add_box_static("M3bVaultBox", Vector3(0.0, 0.45, 6.0), Vector3(3.0, 0.9, 0.4))
	_add_box_static("M3bClimbWall", Vector3(0.0, 1.1, 16.0), Vector3(3.0, 2.2, 0.4))


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


func _verify_vehicle_snapshot(snapshot: Dictionary) -> void:
	var required_keys := [
		"speed",
		"throttle",
		"steer",
		"wheel_spin",
		"body_pitch",
		"body_roll",
		"camera_dip",
	]
	for key in required_keys:
		if not snapshot.has(key):
			_failed.append("载具动画快照缺少键：%s" % key)
	if float(snapshot.get("speed", -1.0)) < 0.0:
		_failed.append("载具动画快照 speed 异常：%s" % str(snapshot.get("speed")))
	var wheel_spin: float = float(snapshot.get("wheel_spin", -1.0))
	var body_pitch: float = float(snapshot.get("body_pitch", 999.0))
	var body_roll: float = float(snapshot.get("body_roll", 999.0))
	if wheel_spin == -1.0 or body_pitch == 999.0 or body_roll == 999.0:
		_failed.append("载具动画快照数值异常")


func _finish() -> void:
	if _failed.is_empty():
		print("[M3bTest] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M3bTest] FAILED: %s" % entry)
		print("[M3bTest] failed")
		get_tree().quit(1)
