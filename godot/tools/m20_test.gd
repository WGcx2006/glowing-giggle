extends Node3D

const IFV_SCENE := preload("res://scenes/vehicles/ifv.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const MAIN_READY_TIMEOUT_FRAMES := 180

var _ifv: Node3D
var _game: Node3D
var _phase := 0
var _frames := 0
var _failed: Array[String] = []
var _finished := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ifv = IFV_SCENE.instantiate()
	add_child(_ifv)
	_phase = 1


func _physics_process(_delta: float) -> void:
	if _finished:
		return
	match _phase:
		1:
			_frames += 1
			if _frames < 2:
				return
			_test_vehicle()
			if not _failed.is_empty():
				_finish()
				return
			_game = MAIN_SCENE.instantiate()
			add_child(_game)
			_phase = 2
			_frames = 0
		2:
			if _game == null or _game.get_ifv() == null or _game.get_entity_sync() == null \
					or _game.get_entity_broadcaster() == null or _game.get_ifv_engine() == null:
				_frames += 1
				if _frames >= MAIN_READY_TIMEOUT_FRAMES:
					_failed.append("main scene did not expose ifv/entity_sync/entity_broadcaster/ifv_engine")
					_finish()
				return
			_test_main()
			_finish()


func _test_vehicle() -> void:
	if _ifv == null or not is_instance_valid(_ifv):
		_failed.append("IFV instance is not valid")
		return
	_ifv.setup(Vector3(0.0, 2.0, 0.0), 0.5)
	_check(_ifv.is_alive(), "IFV is not alive after setup")
	_check(is_equal_approx(_ifv.health, 350.0), "IFV health is %s after setup, expected 350.0" % str(_ifv.health))

	_ifv.drive(1.0, 0.0, false, 1.0)
	var animation: Dictionary = _ifv.get_animation_snapshot()
	for key in ["speed", "throttle", "steer", "turret_yaw", "barrel_pitch", "wheel_spin"]:
		_check(animation.has(key), "animation snapshot missing %s" % key)

	var network: Dictionary = _ifv.get_network_snapshot()
	for key in ["position", "yaw", "health", "max_health", "alive", "animation"]:
		_check(network.has(key), "network snapshot missing %s" % key)

	_ifv.apply_network_snapshot({
		"position": Vector3(5, 1, 6),
		"yaw": 1.0,
		"health": 120,
	})
	_check(_ifv.global_position.distance_to(Vector3(5, 1, 6)) <= 0.01,
		"IFV position is %s after apply, expected (5, 1, 6)" % str(_ifv.global_position))
	_check(is_equal_approx(_ifv.health, 120.0), "IFV health is %s after apply, expected 120.0" % str(_ifv.health))

	_check(_ifv.can_fire_cannon(), "IFV cannot fire cannon before first shot")
	_check(_ifv.try_fire_cannon(Vector3(0, 1, 0), Vector3.FORWARD), "IFV first cannon shot returned false")
	_check(not _ifv.can_fire_cannon(), "IFV can fire cannon immediately after first shot")

	_ifv.take_damage(50.0)
	_check(is_equal_approx(_ifv.health, 70.0), "IFV health is %s after 50 damage, expected 70.0" % str(_ifv.health))


func _test_main() -> void:
	var main_ifv = _game.get_ifv()
	var entity_sync = _game.get_entity_sync()
	var entity_broadcaster = _game.get_entity_broadcaster()
	var ifv_engine = _game.get_ifv_engine()

	if main_ifv == null:
		_failed.append("main get_ifv() returned null")
	elif not is_instance_valid(main_ifv):
		_failed.append("main IFV is not valid")
	elif not main_ifv.is_alive():
		_failed.append("main IFV is not alive")

	if entity_sync == null:
		_failed.append("main get_entity_sync() returned null")
	elif entity_sync.get_entity_node("ifv") == null:
		_failed.append("entity_sync has no entity node for ifv")

	if entity_broadcaster == null:
		_failed.append("main get_entity_broadcaster() returned null")
	elif not entity_broadcaster.get_entity_ids().has("ifv"):
		_failed.append("entity_broadcaster entity ids do not contain ifv")

	if ifv_engine == null:
		_failed.append("main get_ifv_engine() returned null")
	elif not is_instance_valid(ifv_engine):
		_failed.append("main IFV engine is not valid")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed.append(message)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _failed.is_empty():
		print("[M20Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M20Test] FAILED: %s" % entry)
		print("[M20Test] failed")
		get_tree().quit(1)
