extends RigidBody3D

signal destroyed()
signal cannon_fired(origin: Vector3, direction: Vector3)

const MAX_FORWARD_SPEED := 9.0
const MAX_REVERSE_SPEED := 4.5
const ACCELERATION := 7.5
const COAST_DECELERATION := 3.0
const BRAKE_DECELERATION := 16.0
const LATERAL_DAMP := 12.0
const MAX_STEER_RATE := 1.25
const STEER_FULL_SPEED := 4.0
const CANNON_COOLDOWN := 0.35
const SEAT_OFFSET := 2.0
const TURRET_TURN_RATE := 1.8
const TRACK_WHEEL_RADIUS := 0.34

var max_health := 350.0
var health := 350.0
var alive := true

var _throttle := 0.0
var _steer := 0.0
var _brake := false
var _forward_speed := 0.0
var _cannon_cooldown := 0.0
var _camera: Camera3D
var _collision_shape: CollisionShape3D
var _model: Node3D
var _turret: Node3D
var _barrel: Node3D
var _muzzle: Node3D
var _ready_done := false
var _pending_setup := false
var _pending_position := Vector3.ZERO
var _pending_yaw := 0.0
var _track_wheels: Array[Node3D] = []
var _wheel_spin := 0.0
var _turret_yaw := 0.0
var _barrel_pitch := 0.0
var _anim_speed := 0.0
var _anim_throttle := 0.0
var _anim_steer := 0.0


func _ready() -> void:
	add_to_group("vehicle")
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	_ensure_collision()
	_ensure_camera()
	_build_model()
	_ready_done = true
	if _pending_setup:
		_pending_setup = false
		_apply_setup(_pending_position, _pending_yaw)


func setup(spawn_position: Vector3, yaw: float) -> void:
	if not _ready_done:
		_pending_setup = true
		_pending_position = spawn_position
		_pending_yaw = yaw
		return
	_apply_setup(spawn_position, yaw)


func drive(throttle: float, steer: float, brake: bool, delta: float) -> void:
	if not alive:
		return
	_throttle = clampf(throttle, -1.0, 1.0)
	_steer = clampf(steer, -1.0, 1.0)
	_brake = brake
	if sleeping:
		sleeping = false


func try_fire_cannon(origin: Vector3, direction: Vector3) -> bool:
	if not alive or _cannon_cooldown > 0.0:
		return false
	_cannon_cooldown = CANNON_COOLDOWN
	cannon_fired.emit(origin, direction)
	return true


func get_cannon_cooldown() -> float:
	return _cannon_cooldown


func can_fire_cannon() -> bool:
	return alive and _cannon_cooldown <= 0.0


func get_animation_snapshot() -> Dictionary:
	return {
		"speed": _anim_speed,
		"throttle": _anim_throttle,
		"steer": _anim_steer,
		"turret_yaw": _turret_yaw,
		"barrel_pitch": _barrel_pitch,
		"wheel_spin": _wheel_spin,
	}


func get_network_snapshot() -> Dictionary:
	return {
		"position": global_position,
		"yaw": rotation.y,
		"health": health,
		"max_health": max_health,
		"alive": alive,
		"animation": get_animation_snapshot(),
	}


func apply_network_snapshot(state: Dictionary) -> void:
	if state.has("position") and state["position"] is Vector3:
		global_position = state["position"]
	if state.has("yaw") and state["yaw"] != null:
		rotation.y = float(state["yaw"])
	if state.has("health") and state["health"] != null:
		health = clampf(float(state["health"]), 0.0, max_health)
	if state.has("alive") and state["alive"] != null:
		alive = bool(state["alive"])
	if not (state.has("animation") and state["animation"] is Dictionary):
		return
	var animation: Dictionary = state["animation"]
	if animation.has("speed") and animation["speed"] != null:
		_anim_speed = float(animation["speed"])
		_forward_speed = _anim_speed
	if animation.has("throttle") and animation["throttle"] != null:
		_anim_throttle = float(animation["throttle"])
	if animation.has("steer") and animation["steer"] != null:
		_anim_steer = float(animation["steer"])
	if animation.has("turret_yaw") and animation["turret_yaw"] != null:
		_turret_yaw = float(animation["turret_yaw"])
	if animation.has("barrel_pitch") and animation["barrel_pitch"] != null:
		_barrel_pitch = float(animation["barrel_pitch"])
	if animation.has("wheel_spin") and animation["wheel_spin"] != null:
		_wheel_spin = float(animation["wheel_spin"])
	_sync_track_wheels()


func get_seat_position() -> Vector3:
	return global_position + global_transform.basis.z * SEAT_OFFSET


func get_camera() -> Camera3D:
	if _camera == null:
		_ensure_camera()
	return _camera


func take_damage(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_destroy()


func is_alive() -> bool:
	return alive


func get_cannon_muzzle() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return global_position - global_transform.basis.z * 4.2 + Vector3.UP * 2.1


func _process(delta: float) -> void:
	_cannon_cooldown = maxf(_cannon_cooldown - delta, 0.0)
	if not alive:
		var decay_weight: float = 1.0 - exp(-delta * 8.0)
		_anim_speed = lerpf(_anim_speed, 0.0, decay_weight)
		_anim_throttle = lerpf(_anim_throttle, 0.0, decay_weight)
		_anim_steer = lerpf(_anim_steer, 0.0, decay_weight)
	if _turret != null:
		_turret_yaw = move_toward(_turret_yaw, 0.0, TURRET_TURN_RATE * delta)
		var turret_rotation: Vector3 = _turret.rotation
		turret_rotation.y = _turret_yaw
		_turret.rotation = turret_rotation
	if _barrel != null:
		_barrel_pitch = move_toward(_barrel_pitch, 0.0, 0.6 * delta)
		var barrel_rotation: Vector3 = _barrel.rotation
		barrel_rotation.x = _barrel_pitch
		_barrel.rotation = barrel_rotation


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not alive:
		state.linear_velocity = Vector3(0.0, state.linear_velocity.y, 0.0)
		state.angular_velocity = Vector3.ZERO
		return

	var delta := state.step
	var forward := -state.transform.basis.z
	var horizontal_velocity := Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z)
	var forward_speed := horizontal_velocity.dot(forward)
	var target_speed := 0.0
	var acceleration := COAST_DECELERATION

	if _brake:
		acceleration = BRAKE_DECELERATION
	elif _throttle > 0.0:
		target_speed = _throttle * MAX_FORWARD_SPEED
		acceleration = ACCELERATION
	elif _throttle < 0.0:
		target_speed = _throttle * MAX_REVERSE_SPEED
		acceleration = ACCELERATION
	elif absf(forward_speed) < 0.5:
		acceleration = BRAKE_DECELERATION

	var new_speed := move_toward(forward_speed, target_speed, acceleration * delta)
	var lateral := horizontal_velocity - forward * forward_speed
	var lateral_scale := maxf(0.0, 1.0 - LATERAL_DAMP * delta)
	var new_horizontal := forward * new_speed + lateral * lateral_scale
	state.linear_velocity = Vector3(new_horizontal.x, state.linear_velocity.y, new_horizontal.z)

	var speed_magnitude := absf(forward_speed)
	var steer_ratio := clampf((speed_magnitude + 0.8) / STEER_FULL_SPEED, 0.0, 1.0)
	var steer_direction := signf(forward_speed)
	if steer_direction == 0.0:
		steer_direction = signf(_throttle)
	state.angular_velocity = Vector3(0.0, -_steer * MAX_STEER_RATE * steer_ratio * steer_direction, 0.0)

	_forward_speed = new_speed
	_anim_speed = absf(new_speed)
	_anim_throttle = _throttle
	_anim_steer = _steer
	_update_tracks(delta)


func _apply_setup(spawn_position: Vector3, yaw: float) -> void:
	alive = true
	health = max_health
	_throttle = 0.0
	_steer = 0.0
	_brake = false
	_forward_speed = 0.0
	_cannon_cooldown = 0.0
	_turret_yaw = 0.0
	_barrel_pitch = 0.0
	_wheel_spin = 0.0
	_anim_speed = 0.0
	_anim_throttle = 0.0
	_anim_steer = 0.0
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 4
	collision_mask = 7
	_ensure_collision()
	if _collision_shape != null:
		_collision_shape.disabled = false
	global_position = spawn_position
	rotation = Vector3(0.0, yaw, 0.0)
	if _model != null:
		_model.rotation = Vector3.ZERO
	if _turret != null:
		_turret.rotation = Vector3.ZERO
	if _barrel != null:
		_barrel.rotation = Vector3.ZERO
	_sync_track_wheels()


func _destroy() -> void:
	alive = false
	_throttle = 0.0
	_steer = 0.0
	_brake = false
	_forward_speed = 0.0
	_cannon_cooldown = 0.0
	_turret_yaw = 0.0
	_barrel_pitch = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	if _collision_shape != null:
		_collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	destroyed.emit()


func _update_tracks(delta: float) -> void:
	if _track_wheels.is_empty():
		return
	_wheel_spin += _forward_speed * delta / TRACK_WHEEL_RADIUS
	_sync_track_wheels()


func _sync_track_wheels() -> void:
	for wheel in _track_wheels:
		var wheel_rotation: Vector3 = wheel.rotation
		wheel_rotation.z = _wheel_spin
		wheel.rotation = wheel_rotation


func _ensure_collision() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		_collision_shape.position = Vector3(0.0, 0.625, 0.0)
		add_child(_collision_shape)
	if _collision_shape.shape == null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.8, 1.25, 5.4)
		_collision_shape.shape = shape
	if physics_material_override == null:
		var grip := PhysicsMaterial.new()
		grip.friction = 0.2
		grip.rough = false
		grip.bounce = 0.0
		physics_material_override = grip


func _ensure_camera() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.position = Vector3(0.0, 2.2, -0.3)
		_camera.fov = 70.0
		_camera.near = 0.05
		_camera.current = true
		add_child(_camera)


func _build_model() -> void:
	if _model != null:
		return
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var olive_mat := _make_material(Color(0.31, 0.35, 0.19), 0.78, 0.2)
	var dark_green_mat := _make_material(Color(0.13, 0.17, 0.11), 0.92, 0.0)
	var dark_gray_mat := _make_material(Color(0.10, 0.10, 0.10), 0.95, 0.0)

	_add_box(_model, Vector3(2.6, 0.8, 5.2), Vector3(0.0, 0.65, 0.0), olive_mat)
	_add_box(_model, Vector3(2.6, 0.42, 0.95), Vector3(0.0, 0.78, -2.42), olive_mat, Vector3(-22.0, 0.0, 0.0))
	_add_box(_model, Vector3(2.5, 0.4, 0.8), Vector3(0.0, 0.72, 2.42), olive_mat, Vector3(24.0, 0.0, 0.0))
	_add_box(_model, Vector3(2.35, 0.45, 3.2), Vector3(0.0, 1.08, 0.35), olive_mat)
	_add_box(_model, Vector3(0.1, 0.6, 5.3), Vector3(-1.4, 0.62, 0.0), dark_green_mat)
	_add_box(_model, Vector3(0.1, 0.6, 5.3), Vector3(1.4, 0.62, 0.0), dark_green_mat)
	_add_box(_model, Vector3(0.62, 0.8, 5.5), Vector3(-1.7, 0.55, 0.0), dark_gray_mat)
	_add_box(_model, Vector3(0.62, 0.8, 5.5), Vector3(1.7, 0.55, 0.0), dark_gray_mat)
	_add_box(_model, Vector3(0.2, 0.18, 0.3), Vector3(-0.95, 1.05, -2.68), dark_gray_mat)
	_add_box(_model, Vector3(0.2, 0.18, 0.3), Vector3(0.95, 1.05, -2.68), dark_gray_mat)

	for side in [-1.0, 1.0]:
		for wheel_z in [-2.2, -1.4, -0.6, 0.2, 1.0, 1.8]:
			var wheel := _add_road_wheel(Vector3(side * 1.8, 0.32, wheel_z), dark_gray_mat)
			_track_wheels.append(wheel)

	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0.0, 1.4, -0.2)
	_model.add_child(_turret)

	_add_cylinder(_turret, 0.6, 0.52, Vector3(0.0, 0.25, 0.0), olive_mat)
	_add_cylinder(_turret, 0.1, 0.56, Vector3(0.0, 0.58, 0.0), dark_green_mat)
	_add_box(_turret, Vector3(0.95, 0.45, 0.35), Vector3(0.0, 0.3, -0.72), olive_mat, Vector3(-6.0, 0.0, 0.0))
	_add_box(_turret, Vector3(0.34, 0.12, 0.5), Vector3(-0.38, 0.68, -0.28), dark_green_mat)
	_add_box(_turret, Vector3(0.34, 0.12, 0.5), Vector3(0.38, 0.68, -0.28), dark_green_mat)
	_add_cylinder(_turret, 0.18, 0.22, Vector3(0.0, 0.72, 0.25), dark_gray_mat)

	_barrel = Node3D.new()
	_barrel.name = "Barrel"
	_barrel.position = Vector3(0.0, 0.42, -0.4)
	_turret.add_child(_barrel)

	_add_cylinder(_barrel, 4.4, 0.07, Vector3(0.0, 0.0, -2.15), dark_green_mat, Vector3(-90.0, 0.0, 0.0))
	_add_cylinder(_barrel, 0.4, 0.1, Vector3(0.0, 0.0, -1.75), dark_gray_mat, Vector3(-90.0, 0.0, 0.0))
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, 0.0, -4.2)
	_barrel.add_child(_muzzle)
	_add_cylinder(_muzzle, 0.35, 0.11, Vector3.ZERO, dark_gray_mat, Vector3(-90.0, 0.0, 0.0))

	_add_box(_model, Vector3(0.35, 0.2, 0.14), Vector3(-1.05, 1.0, -2.88), dark_gray_mat)
	_add_box(_model, Vector3(0.35, 0.2, 0.14), Vector3(1.05, 1.0, -2.88), dark_gray_mat)


func _add_road_wheel(wheel_position: Vector3, material: StandardMaterial3D) -> Node3D:
	var wheel := Node3D.new()
	wheel.name = "RoadWheel"
	wheel.position = wheel_position
	_model.add_child(wheel)
	_add_cylinder(wheel, 0.42, TRACK_WHEEL_RADIUS, Vector3.ZERO, material, Vector3(90.0, 0.0, 0.0))
	return wheel


func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: StandardMaterial3D, rotation_degrees: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	parent.add_child(instance)
	return instance


func _add_cylinder(parent: Node3D, height: float, radius: float, position: Vector3, material: StandardMaterial3D, rotation_degrees: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	parent.add_child(instance)
	return instance


func _make_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
