extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _animator
var _player
var _failed: Array[String] = []
var _phase := 0
var _frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)
	get_tree().paused = false


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_animator() == null:
				return
			_animator = _game.get_animator()
			_player = _game.get_player()
			if _animator == null or _player == null:
				_failed.append("get_animator() 或 get_player() 返回空")
				_finish()
				return
			var enemies: Node = _game.get_node_or_null("Enemies")
			if enemies != null and enemies.has_method("set_active"):
				enemies.set_active(false)
			var vehicle = _game.get_vehicle()
			if vehicle != null and is_instance_valid(vehicle):
				vehicle.global_position = Vector3(0.0, -500.0, 0.0)
			_player.set_input_enabled(false)
			_prepare_prone_area()
			_animator.play_inspect()
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= 30:
				_verify_inspect_started()
				_phase = 2
				_frames = 0
		2:
			_frames += 1
			if _frames >= 130:
				_verify_inspect_finished()
				_player.set_prone(true)
				_phase = 3
				_frames = 0
		3:
			_frames += 1
			if _frames >= 30:
				_verify_prone()
				_player.set_prone(false)
				_phase = 4
				_frames = 0
		4:
			_frames += 1
			if _frames >= 30:
				_verify_standing()
				_finish()


func _prepare_prone_area() -> void:
	# Deterministic regression: disable the player capsule so the standing
	# clearance check cannot be blocked by procedural terrain/props.
	var collision_shape: CollisionShape3D = _player.get_node("CollisionShape3D")
	collision_shape.disabled = true
	var ground: float = _game.get_environment().terrain_height_at(Vector3(0.0, 0.0, 20.0))
	_player.global_position = Vector3(0.0, ground + 1.0, 20.0)
	_player.velocity = Vector3.ZERO


func _verify_inspect_started() -> void:
	var snapshot: Dictionary = _animator.get_pose_snapshot()
	var progress: float = float(snapshot.get("inspect_progress", 0.0))
	var pose: String = str(snapshot.get("pose_name", ""))
	if progress <= 0.05:
		_failed.append("Inspect 0.5s 后 inspect_progress 过低：%s" % str(progress))
	if pose != "inspect":
		_failed.append("Inspect 进行中 pose_name 不是 inspect：%s" % pose)


func _verify_inspect_finished() -> void:
	var snapshot: Dictionary = _animator.get_pose_snapshot()
	var progress: float = float(snapshot.get("inspect_progress", 1.0))
	var pose: String = str(snapshot.get("pose_name", ""))
	if progress >= 0.01:
		_failed.append("Inspect 结束后 inspect_progress 未归零：%s" % str(progress))
	if pose != "idle":
		_failed.append("Inspect 结束后 pose_name 不是 idle：%s" % pose)


func _verify_prone() -> void:
	if not _player.is_prone():
		_failed.append("set_prone(true) 后 is_prone() 不为 true")
	var camera_y: float = _player.get_camera().position.y
	if camera_y >= 0.6:
		_failed.append("卧倒后相机高度未下降：%s" % str(camera_y))
	var collision_shape: CollisionShape3D = _player.get_node("CollisionShape3D")
	var capsule_height: float = collision_shape.shape.height
	if capsule_height >= 0.6:
		_failed.append("卧倒后胶囊体高度未降低：%s" % str(capsule_height))


func _verify_standing() -> void:
	if _player.is_prone():
		_failed.append("set_prone(false) 后 is_prone() 仍为 true")
	var camera_y: float = _player.get_camera().position.y
	if camera_y <= 1.2:
		_failed.append("起身后相机高度未恢复：%s" % str(camera_y))
	var collision_shape: CollisionShape3D = _player.get_node("CollisionShape3D")
	var capsule_height: float = collision_shape.shape.height
	if capsule_height <= 1.7:
		_failed.append("起身后胶囊体高度未恢复：%s" % str(capsule_height))


func _finish() -> void:
	if _failed.is_empty():
		print("[AnimationTest] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[AnimationTest] FAILED: %s" % entry)
		print("[AnimationTest] failed")
		get_tree().quit(1)
