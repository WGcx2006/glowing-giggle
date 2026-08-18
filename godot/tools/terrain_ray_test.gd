extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _game
var _failed: Array[String] = []
var _phase := 0
var _frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_environment() == null:
				return
			_verify_terrain_rays()
			_finish()


func _verify_terrain_rays() -> void:
	var space: PhysicsDirectSpaceState3D = _game.get_player().get_world_3d().direct_space_state
	var probe_points := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(-70.0, 0.0, 80.0),
		Vector3(30.0, 0.0, -30.0),
		Vector3(-30.0, 0.0, -6.0),
		Vector3(46.0, 0.0, 96.0),
	]
	for point in probe_points:
		var default_params := PhysicsRayQueryParameters3D.create(
			Vector3(point.x, 60.0, point.z),
			Vector3(point.x, -60.0, point.z),
			1
		)
		var default_hit: Dictionary = space.intersect_ray(default_params)
		if default_hit.is_empty():
			_failed.append("默认射线未命中地形：%s" % str(point))
			continue
		var hit_y: float = float(default_hit.get("position", Vector3.ZERO).y)
		if hit_y < -20.0 or hit_y > 40.0:
			_failed.append("地形命中高度异常：%s y=%s" % [str(point), str(hit_y)])
		var back_params := PhysicsRayQueryParameters3D.create(
			Vector3(point.x, 60.0, point.z),
			Vector3(point.x, -60.0, point.z),
			1
		)
		back_params.hit_back_faces = true
		var back_hit: Dictionary = space.intersect_ray(back_params)
		if back_hit.is_empty():
			_failed.append("背面射线未命中地形：%s" % str(point))


func _finish() -> void:
	if _failed.is_empty():
		print("[TerrainRayTest] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[TerrainRayTest] FAILED: %s" % entry)
		print("[TerrainRayTest] failed")
		get_tree().quit(1)
