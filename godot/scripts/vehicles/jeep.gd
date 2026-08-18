extends RigidBody3D

signal destroyed()

const MAX_FORWARD_SPEED := 10.0
const MAX_REVERSE_SPEED := 5.0
const ACCELERATION := 8.0
const COAST_DECELERATION := 3.0
const BRAKE_DECELERATION := 16.0
const LATERAL_DAMP := 9.0
const MAX_STEER_RATE := 1.7
const STEER_FULL_SPEED := 4.0
const WHEEL_RADIUS := 0.38
const WHEEL_WIDTH := 0.28
const SEAT_OFFSET := 1.8

var max_health := 220.0
var health := 220.0
var alive := true

var _throttle := 0.0
var _steer := 0.0
var _brake := false
var _forward_speed := 0.0
var _wheel_spin := 0.0
var _camera: Camera3D
var _collision_shape: CollisionShape3D
var _model: Node3D
var _wheels: Array[Node3D] = []
var _front_wheel_count := 0
var _ai_driver := false
var _ready_done := false
var _pending_setup := false
var _pending_position := Vector3.ZERO
var _pending_yaw := 0.0
var _body_pitch: float = 0.0
var _body_roll: float = 0.0
var _camera_dip: float = 0.0
var _anim_speed: float = 0.0
var _anim_throttle: float = 0.0
var _anim_steer: float = 0.0
var _forward_blocked := false
var _forward_hit_distance := 0.0


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


func set_ai_driver(value: bool) -> void:
	_ai_driver = value


func is_ai_driven() -> bool:
	return _ai_driver


func ai_drive(throttle: float, steer: float, brake: bool, delta: float) -> void:
	drive(throttle, steer, brake, delta)


func get_ai_drive_state() -> Dictionary:
	return {
		"position": global_position,
		"speed": _forward_speed,
		"alive": alive,
		"steer": _steer,
		"throttle": _throttle,
		"forward_blocked": _forward_blocked,
		"forward_hit_distance": _forward_hit_distance,
	}


func is_forward_blocked() -> bool:
	return _forward_blocked


func _process(delta: float) -> void:
	if _model == null:
		return
	if not alive:
		var weight: float = 1.0 - exp(-delta * 8.0)
		_body_pitch = lerpf(_body_pitch, 0.0, weight)
		_body_roll = lerpf(_body_roll, 0.0, weight)
		_camera_dip = lerpf(_camera_dip, 0.0, weight)
		_anim_speed = lerpf(_anim_speed, 0.0, weight)
		_anim_throttle = lerpf(_anim_throttle, 0.0, weight)
		_anim_steer = lerpf(_anim_steer, 0.0, weight)
	_apply_animation_pose()


func _physics_process(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_origin: Vector3 = global_position + Vector3.UP * 0.7
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin - global_transform.basis.z * 4.0,
		1
	)
	query.hit_back_faces = true
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	var hit_position: Vector3 = result.get("position", ray_origin)
	var hit_distance: float = ray_origin.distance_to(hit_position)
	if not result.is_empty() and hit_distance < 3.2:
		_forward_blocked = true
		_forward_hit_distance = hit_distance
	else:
		_forward_blocked = false
		_forward_hit_distance = 0.0


func get_animation_snapshot() -> Dictionary:
	return {
		"speed": _anim_speed,
		"throttle": _anim_throttle,
		"steer": _anim_steer,
		"wheel_spin": _wheel_spin,
		"body_pitch": _body_pitch,
		"body_roll": _body_roll,
		"camera_dip": _camera_dip,
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
	if animation.has("throttle") and animation["throttle"] != null:
		_anim_throttle = float(animation["throttle"])
	if animation.has("steer") and animation["steer"] != null:
		_anim_steer = float(animation["steer"])
	if animation.has("wheel_spin") and animation["wheel_spin"] != null:
		_wheel_spin = float(animation["wheel_spin"])
	if animation.has("body_pitch") and animation["body_pitch"] != null:
		_body_pitch = float(animation["body_pitch"])
	if animation.has("body_roll") and animation["body_roll"] != null:
		_body_roll = float(animation["body_roll"])
	if animation.has("camera_dip") and animation["camera_dip"] != null:
		_camera_dip = float(animation["camera_dip"])


func get_seat_position() -> Vector3:
	return global_position - global_transform.basis.x * SEAT_OFFSET


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

	var body_pitch_target: float = 0.0
	if _brake:
		body_pitch_target = 0.06
	else:
		body_pitch_target = -_throttle * 0.045
	var body_roll_target: float = _steer * steer_ratio * 0.09
	var camera_dip_target: float = 0.0
	if _brake or absf(_throttle) > 0.8:
		camera_dip_target = 0.04
	var anim_weight: float = 1.0 - exp(-delta * 8.0)
	_body_pitch = lerpf(_body_pitch, body_pitch_target, anim_weight)
	_body_roll = lerpf(_body_roll, body_roll_target, anim_weight)
	_camera_dip = lerpf(_camera_dip, camera_dip_target, anim_weight)

	_update_wheels(delta)


func _apply_animation_pose() -> void:
	if _model != null:
		var model_rotation: Vector3 = _model.rotation
		model_rotation.x = _body_pitch
		model_rotation.z = _body_roll
		_model.rotation = model_rotation
	if _camera != null:
		_camera.position.y = 1.45 - _camera_dip


func _apply_setup(spawn_position: Vector3, yaw: float) -> void:
	alive = true
	health = max_health
	_throttle = 0.0
	_steer = 0.0
	_brake = false
	_forward_speed = 0.0
	_wheel_spin = 0.0
	_anim_speed = 0.0
	_anim_throttle = 0.0
	_anim_steer = 0.0
	_body_pitch = 0.0
	_body_roll = 0.0
	_camera_dip = 0.0
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


func _destroy() -> void:
	alive = false
	_ai_driver = false
	_throttle = 0.0
	_steer = 0.0
	_brake = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	if _collision_shape != null:
		_collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	destroyed.emit()


func _update_wheels(delta: float) -> void:
	if _wheels.is_empty():
		return
	var spin_delta := _forward_speed * delta / WHEEL_RADIUS
	_wheel_spin += spin_delta
	for i in range(_wheels.size()):
		var wheel := _wheels[i]
		wheel.rotation.x = _wheel_spin
		if i < _front_wheel_count:
			wheel.rotation.y = -_steer * 0.45


func _ensure_collision() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		_collision_shape.position = Vector3(0.0, 0.5, 0.0)
		add_child(_collision_shape)
	if _collision_shape.shape == null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.15, 1.0, 4.5)
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
		_camera.position = Vector3(0.0, 1.45, -0.25)
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

	var body_mat := _make_material(Color(0.31, 0.38, 0.22), 0.72, 0.32)
	var dark_mat := _make_material(Color(0.08, 0.09, 0.09), 0.9, 0.0)
	var metal_mat := _make_material(Color(0.38, 0.39, 0.36), 0.5, 0.8)
	var seat_mat := _make_material(Color(0.12, 0.16, 0.12), 0.95, 0.0)
	var glass_mat := _make_material(Color(0.32, 0.45, 0.42), 0.1, 0.4)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color.a = 0.55
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_add_box(_model, Vector3(2.15, 0.7, 4.45), Vector3(0.0, 0.8, 0.0), body_mat)
	_add_box(_model, Vector3(1.85, 0.16, 1.15), Vector3(0.0, 1.05, 1.3), body_mat)
	_add_box(_model, Vector3(1.95, 0.12, 1.0), Vector3(0.0, 1.2, -1.55), body_mat)
	_add_box(_model, Vector3(2.05, 0.22, 0.45), Vector3(0.0, 0.9, 2.05), body_mat)
	_add_box(_model, Vector3(2.05, 0.18, 0.3), Vector3(0.0, 1.16, -2.1), metal_mat)

	_add_box(_model, Vector3(0.07, 0.62, 0.06), Vector3(-0.88, 1.42, 0.55), dark_mat)
	_add_box(_model, Vector3(0.07, 0.62, 0.06), Vector3(0.88, 1.42, 0.55), dark_mat)
	_add_box(_model, Vector3(1.83, 0.07, 0.06), Vector3(0.0, 1.76, 0.55), dark_mat)
	_add_box(_model, Vector3(1.72, 0.05, 0.05), Vector3(0.0, 1.25, 0.53), dark_mat)
	_add_box(_model, Vector3(1.65, 0.55, 0.02), Vector3(0.0, 1.5, 0.58), glass_mat)

	for seat_x in [-0.55, 0.55]:
		_add_box(_model, Vector3(0.6, 0.3, 0.55), Vector3(seat_x, 1.0, -0.4), seat_mat)
		_add_box(_model, Vector3(0.6, 0.62, 0.1), Vector3(seat_x, 1.3, -0.7), seat_mat)
	_add_box(_model, Vector3(1.9, 0.26, 0.55), Vector3(0.0, 1.02, -1.35), seat_mat)
	_add_box(_model, Vector3(1.9, 0.62, 0.1), Vector3(0.0, 1.28, -1.63), seat_mat)

	_add_box(_model, Vector3(0.06, 0.7, 0.06), Vector3(-0.88, 1.55, -1.25), dark_mat)
	_add_box(_model, Vector3(0.06, 0.7, 0.06), Vector3(0.88, 1.55, -1.25), dark_mat)
	_add_box(_model, Vector3(1.82, 0.07, 0.06), Vector3(0.0, 1.94, -1.25), dark_mat)

	_front_wheel_count = 0
	for wheel_x in [-1.02, 1.02]:
		for wheel_z in [-1.45, 1.45]:
			var wheel := _make_wheel_node(Vector3(wheel_x, 0.38, wheel_z), dark_mat, metal_mat)
			_wheels.append(wheel)
			if wheel_z > 0.0:
				_front_wheel_count += 1

	var spare_mesh := CylinderMesh.new()
	spare_mesh.top_radius = WHEEL_RADIUS * 0.92
	spare_mesh.bottom_radius = WHEEL_RADIUS * 0.92
	spare_mesh.height = WHEEL_WIDTH
	spare_mesh.radial_segments = 14
	var spare := MeshInstance3D.new()
	spare.mesh = spare_mesh
	spare.material_override = dark_mat
	spare.position = Vector3(0.0, 0.95, -2.2)
	spare.rotation_degrees.x = 90.0
	_model.add_child(spare)


func _make_wheel_node(wheel_position: Vector3, tire_mat: StandardMaterial3D, hub_mat: StandardMaterial3D) -> Node3D:
	var wheel := Node3D.new()
	wheel.name = "Wheel"
	wheel.position = wheel_position
	_model.add_child(wheel)

	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = WHEEL_RADIUS
	tire_mesh.bottom_radius = WHEEL_RADIUS
	tire_mesh.height = WHEEL_WIDTH
	tire_mesh.radial_segments = 14
	var tire_instance := MeshInstance3D.new()
	tire_instance.mesh = tire_mesh
	tire_instance.material_override = tire_mat
	tire_instance.rotation_degrees.z = 90.0
	wheel.add_child(tire_instance)

	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.12
	hub_mesh.bottom_radius = 0.12
	hub_mesh.height = WHEEL_WIDTH + 0.04
	hub_mesh.radial_segments = 10
	var hub_instance := MeshInstance3D.new()
	hub_instance.mesh = hub_mesh
	hub_instance.material_override = hub_mat
	hub_instance.rotation_degrees.z = 90.0
	wheel.add_child(hub_instance)
	return wheel


func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


func _make_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
