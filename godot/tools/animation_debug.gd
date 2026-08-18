extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _player
var _probe
var _frames := 0
var _phase := 0


func _ready() -> void:
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(_delta: float) -> void:
	if _player == null:
		if _game == null or not is_instance_valid(_game) or _game.get_player() == null:
			return
		_player = _game.get_player()
		var spawn: Vector3 = _game.get_environment().get_spawn_points()[3]
		print("[Debug] spawn=%s player=%s" % [str(spawn), str(_player.global_position)])
		return
	_frames += 1
	if _phase == 0:
		if _frames % 10 == 0:
			var pos: Vector3 = _player.global_position
			var terrain_y: float = float(_game.get_environment().terrain_height_at(pos))
			var on_floor: bool = bool(_player.is_on_floor())
			var vy: float = float(_player.velocity.y)
			print("[Debug] frame=%d pos=%s terrain_y=%.4f floor=%s vy=%.4f" % [_frames, str(pos), terrain_y, str(on_floor), vy])
		if _frames >= 60:
			_frames = 0
			_phase = 1
			_teleport_to_safe_spot()
	elif _phase == 1:
		if _frames == 30:
			_print_ground_state("safe settled")
			_player.set_prone(true)
		elif _frames == 60:
			_print_prone_state("prone entered")
			_player.set_prone(false)
		elif _frames == 90:
			_print_prone_state("prone exited")
			_frames = 0
			_phase = 2
			_create_probe()
	elif _phase == 2:
		if _probe != null:
			if not _probe.is_on_floor():
				_probe.velocity.y -= 24.0 * _delta
			_probe.move_and_slide()
		if _frames == 60:
			var pos: Vector3 = _probe.global_position
			var ground: float = float(_game.get_environment().terrain_height_at(pos))
			print("[Debug] probe pos=%s terrain_y=%.4f floor=%s vy=%.4f" % [str(pos), ground, str(_probe.is_on_floor()), float(_probe.velocity.y)])
			get_tree().quit(0)


func _teleport_to_safe_spot() -> void:
	var spawn_points: Array = _game.get_environment().get_spawn_points()
	if spawn_points.size() <= 2:
		return
	var point: Vector3 = spawn_points[2]
	var ground: float = float(_game.get_environment().terrain_height_at(point))
	point.y = ground + 0.5
	_player.global_position = point
	_player.velocity = Vector3.ZERO
	print("[Debug] teleport point=%s ground=%.4f" % [str(point), ground])


func _print_ground_state(label: String) -> void:
	var pos: Vector3 = _player.global_position
	var terrain_y: float = float(_game.get_environment().terrain_height_at(pos))
	var on_floor: bool = bool(_player.is_on_floor())
	print("[Debug] %s pos=%s terrain_y=%.4f floor=%s" % [label, str(pos), terrain_y, str(on_floor)])


func _print_prone_state(label: String) -> void:
	var prone: bool = bool(_player.is_prone())
	var camera: Camera3D = _player.get_camera()
	var camera_y: float = camera.position.y
	var pos: Vector3 = _player.global_position
	var terrain_y: float = float(_game.get_environment().terrain_height_at(pos))
	print("[Debug] %s is_prone=%s camera_y=%.4f player_y=%.4f terrain_y=%.4f" % [label, str(prone), camera_y, pos.y, terrain_y])


func _create_probe() -> void:
	var terrain: StaticBody3D = _game.get_environment().get_node("Terrain")
	var collision_shape: CollisionShape3D = terrain.get_child(1)
	print("[Debug] terrain layer=%d mask=%d collision_disabled=%s shape=%s" % [
		int(terrain.collision_layer),
		int(terrain.collision_mask),
		str(collision_shape.disabled),
		str(collision_shape.shape),
	])
	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 1
	probe.floor_snap_length = 0.2
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var probe_shape := CollisionShape3D.new()
	probe_shape.shape = shape
	probe_shape.position.y = 0.9
	probe.add_child(probe_shape)
	add_child(probe)
	var point: Vector3 = _game.get_environment().get_spawn_points()[2]
	var ground: float = float(_game.get_environment().terrain_height_at(point))
	probe.global_position = Vector3(point.x, ground + 1.0, point.z)
	probe.velocity = Vector3.ZERO
	_probe = probe
	print("[Debug] probe created pos=%s ground=%.4f" % [str(probe.global_position), ground])
