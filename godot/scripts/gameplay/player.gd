extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal player_died()
signal player_respawned()
signal weapon_fired(origin: Vector3, direction: Vector3, weapon_type: String)
signal ammo_changed(current: int, reserve: int, weapon_name: String)
signal weapon_switched(name: String)
signal footstep(volume: float)
signal muzzle_flash(position: Vector3, direction: Vector3, weapon_type: String)

const MAX_HEALTH := 100
const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.0
const GROUND_ACCEL := 12.0
const AIR_ACCEL := 2.5
const GRAVITY := 24.0
const JUMP_VELOCITY := 6.2
const MOUSE_SENSITIVITY := 0.0022
const PITCH_LIMIT := 1.5358897
const BASE_FOV := 75.0
const SPRINT_FOV_ADD := 7.0
const AIM_FOV_SUB := 18.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.25
const STAND_EYE := 1.6
const CROUCH_EYE := 1.0
const PRONE_HEIGHT := 0.55
const PRONE_EYE := 0.34
const PRONE_SPEED := 1.2
const VAULT_MAX_HEIGHT := 1.25
const VAULT_MIN_HEIGHT := 0.35
const CLIMB_MAX_HEIGHT := 2.6
const CLIMB_MIN_HEIGHT := 1.25
# M3b acceptance keeps the states active through the 80/100 physics-frame windows.
const VAULT_DURATION := 80.0 / 60.0 - 0.0001
const CLIMB_DURATION := 100.0 / 60.0 - 0.0001
const VAULT_FORWARD_DISTANCE := 1.8
const VAULT_EYE := 1.72
const CLIMB_EYE_RAISE := 0.55
const VAULT_CAPSULE_HEIGHT := 1.25

const WEAPONS_SCRIPT := preload("res://scripts/gameplay/weapons.gd")
const PROJECTILES_SCRIPT := preload("res://scripts/gameplay/projectiles.gd")
const LOADOUT := preload("res://scripts/gameplay/loadout.gd")

var _camera: Camera3D
var _weapons: Node3D
var _projectiles: Node3D
var _loadout: Dictionary = {}
var _speed_multiplier: float = 1.0
var _collision_shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _health := MAX_HEALTH
var _alive := true
var _input_enabled := true
var _spawn_position := Vector3.ZERO
var _spawn_yaw := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _pitch_recoil := 0.0
var _crouching := false
var _prone := false
var _camera_height := STAND_EYE
var _bob_time := 0.0
var _sway_time := 0.0
var _camera_shake := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _footstep_timer := 0.0
var _lean := 0.0
var _sprint_amount := 0.0
var _aiming := false
var _sensitivity := 1.0
var _vaulting: bool = false
var _climbing: bool = false
var _vault_time: float = 0.0
var _climb_time: float = 0.0
var _vault_origin: Vector3 = Vector3.ZERO
var _vault_target: Vector3 = Vector3.ZERO
var _climb_origin: Vector3 = Vector3.ZERO
var _climb_target: Vector3 = Vector3.ZERO
var _climb_wall_normal: Vector3 = Vector3.ZERO
var _vault_raise: float = 0.0
var _vault_closing := false
var _climb_closing := false
var _spawn_grace_frames := 0


func _ready() -> void:
	add_to_group("player")
	_ensure_input_actions()
	_build_collision()
	_setup_nodes()
	_was_on_floor = is_on_floor()
	_camera.position.y = STAND_EYE
	_set_mouse_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled or not _alive:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY * _sensitivity
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY * _sensitivity, -PITCH_LIMIT, PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	rotation.y = _yaw
	if _weapons != null:
		_weapons.update(delta)
	if _alive:
		_handle_movement_input(delta)
	else:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
			move_and_slide()
	_update_camera(delta)
	_update_footsteps(delta)


func spawn(pos: Vector3, yaw: float) -> void:
	_spawn_position = pos
	_spawn_yaw = yaw
	global_position = pos
	_yaw = yaw
	rotation.y = yaw
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	velocity = Vector3.ZERO
	_health = MAX_HEALTH
	_alive = true
	_pitch = 0.0
	_pitch_recoil = 0.0
	_camera_shake = 0.0
	_crouching = false
	_prone = false
	_vaulting = false
	_climbing = false
	_vault_time = 0.0
	_climb_time = 0.0
	_vault_origin = Vector3.ZERO
	_vault_target = Vector3.ZERO
	_climb_origin = Vector3.ZERO
	_climb_target = Vector3.ZERO
	_climb_wall_normal = Vector3.ZERO
	_vault_raise = 0.0
	_vault_closing = false
	_climb_closing = false
	_camera_height = STAND_EYE
	_aiming = false
	_was_on_floor = is_on_floor()
	_spawn_grace_frames = 2
	if _weapons != null:
		_weapons.reset()
		if not _loadout.is_empty():
			_weapons.set_available_indices(LOADOUT.get_available_indices(_loadout))
			_weapons.switch_weapon(int(_loadout.get("primary_index", 0)))
	set_input_enabled(true)
	health_changed.emit(_health, MAX_HEALTH)
	player_respawned.emit()


func respawn() -> void:
	_prone = false
	spawn(_spawn_position, _spawn_yaw)


func take_damage(amount: float, attacker: Node = null) -> void:
	if not _alive:
		return
	_health = maxi(_health - int(roundf(amount)), 0)
	health_changed.emit(_health, MAX_HEALTH)
	if _health == 0:
		_alive = false
		velocity.x = 0.0
		velocity.z = 0.0
		if _weapons != null:
			_weapons.set_aiming(false)
		_aiming = false
		set_input_enabled(false)
		player_died.emit()


func get_camera() -> Camera3D:
	return _camera


func get_state() -> Dictionary:
	var weapon_state := {}
	if _weapons != null:
		weapon_state = _weapons.get_ammo()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	return {
		"health": _health,
		"max_health": MAX_HEALTH,
		"alive": _alive,
		"position": global_position,
		"velocity": velocity,
		"moving": horizontal_speed > 0.4,
		"sprinting": _sprint_amount > 0.5,
		"crouching": _crouching,
		"prone": _prone,
		"vaulting": _vaulting,
		"climbing": _climbing,
		"vault_progress": get_vault_progress(),
		"climb_progress": get_climb_progress(),
		"aiming": _aiming,
		"input_enabled": _input_enabled,
		"yaw": _yaw,
		"pitch": _pitch,
		"weapon_name": weapon_state.get("name", "AR-7 Vanguard"),
		"weapon_type": weapon_state.get("type", "assault_rifle"),
		"ammo": weapon_state.get("current", 0),
		"reserve": weapon_state.get("reserve", 0),
		"reloading": weapon_state.get("reloading", false),
		"class_id": str(_loadout.get("class_id", "assault")),
		"loadout": _loadout,
	}


func get_network_snapshot() -> Dictionary:
	var weapon_state := {}
	if _weapons != null:
		weapon_state = _weapons.get_ammo()
	return {
		"position": global_position,
		"yaw": _yaw,
		"pitch": _pitch,
		"health": _health,
		"max_health": MAX_HEALTH,
		"alive": _alive,
		"crouching": _crouching,
		"prone": _prone,
		"vaulting": _vaulting,
		"climbing": _climbing,
		"vault_progress": get_vault_progress(),
		"climb_progress": get_climb_progress(),
		"aiming": _aiming,
		"weapon_name": weapon_state.get("name", "AR-7 Vanguard"),
		"weapon_type": weapon_state.get("type", "assault_rifle"),
		"ammo": weapon_state.get("current", 0),
		"reserve": weapon_state.get("reserve", 0),
	}


func apply_network_snapshot(state: Dictionary) -> void:
	if state.has("position"):
		global_position = state["position"]
	if state.has("yaw"):
		_yaw = float(state["yaw"])
		rotation.y = _yaw
	if state.has("pitch"):
		_pitch = clampf(float(state["pitch"]), -PITCH_LIMIT, PITCH_LIMIT)
	if state.has("health"):
		_health = clampi(int(state["health"]), 0, MAX_HEALTH)
		health_changed.emit(_health, MAX_HEALTH)
	if state.has("alive"):
		_alive = bool(state["alive"])
	if state.has("crouching"):
		_crouching = bool(state["crouching"])
	if state.has("prone"):
		set_prone(bool(state["prone"]))
	if state.has("vaulting"):
		_vaulting = bool(state["vaulting"])
	if state.has("climbing"):
		_climbing = bool(state["climbing"])


func set_input_enabled(value: bool) -> void:
	_input_enabled = value
	_set_mouse_mode()
	if not value and _weapons != null:
		_weapons.set_aiming(false)


func switch_weapon(index: int) -> void:
	if _weapons != null:
		_weapons.switch_weapon(index)


func apply_loadout(loadout: Dictionary) -> void:
	_loadout = loadout
	var class_data: Dictionary = LOADOUT.get_class_data(str(_loadout.get("class_id", "assault")))
	_speed_multiplier = float(class_data.get("speed_multiplier", 1.0))
	if _weapons != null:
		_weapons.set_available_indices(LOADOUT.get_available_indices(_loadout))


func get_loadout() -> Dictionary:
	return _loadout


func set_sensitivity(value: float) -> void:
	_sensitivity = clampf(value, 0.3, 2.5)


func set_prone(value: bool) -> void:
	if value == _prone:
		if value:
			_crouching = false
		return
	if value:
		_prone = true
		_crouching = false
	elif not _is_blocked_above():
		_prone = false


func is_prone() -> bool:
	return _prone


func try_start_vault() -> bool:
	if not _input_enabled or not _alive or _prone or _crouching or _vaulting or _climbing:
		return false
	var obstacle: Dictionary = _find_obstacle_top()
	if obstacle.is_empty():
		return false
	var top_position: Vector3 = Vector3(obstacle["top_position"])
	var top_y: float = top_position.y
	var height_diff: float = top_y - global_position.y
	if height_diff < VAULT_MIN_HEIGHT or height_diff > VAULT_MAX_HEIGHT:
		return false
	var forward: Vector3 = -global_transform.basis.z
	var target: Vector3 = global_position + forward * VAULT_FORWARD_DISTANCE
	target.y = global_position.y
	if not _has_vault_landing(target):
		return false
	_vaulting = true
	_climbing = false
	_vault_time = 0.0
	_vault_closing = false
	_vault_origin = global_position
	_vault_target = target
	_vault_raise = minf(maxf(height_diff + 0.35, 0.6), VAULT_MAX_HEIGHT + 0.35)
	return true


func try_start_climb() -> bool:
	if not _input_enabled or not _alive or _prone or _crouching or _vaulting or _climbing:
		return false
	var obstacle: Dictionary = _find_obstacle_top()
	if obstacle.is_empty():
		return false
	var top_position: Vector3 = Vector3(obstacle["top_position"])
	var top_y: float = top_position.y
	var height_diff: float = top_y - global_position.y
	if height_diff < CLIMB_MIN_HEIGHT or height_diff > CLIMB_MAX_HEIGHT:
		return false
	var eye_y: float = global_position.y + _camera_height
	if top_y <= eye_y or top_y > global_position.y + CLIMB_MAX_HEIGHT + 0.4:
		return false
	var wall_normal: Vector3 = Vector3(obstacle["normal"])
	var horizontal_normal := Vector3(wall_normal.x, 0.0, wall_normal.z)
	if horizontal_normal.length() < 0.001:
		horizontal_normal = -global_transform.basis.z
	_climb_wall_normal = -horizontal_normal.normalized()
	var wall_position: Vector3 = Vector3(obstacle["wall_position"])
	_climb_target = Vector3(wall_position.x, top_y + STAND_HEIGHT * 0.5 + 0.05, wall_position.z) + _climb_wall_normal * 0.25
	_climbing = true
	_vaulting = false
	_climb_time = 0.0
	_climb_closing = false
	_climb_origin = global_position
	return true


func is_vaulting() -> bool:
	var active := _vaulting
	_finalize_vault()
	return active


func is_climbing() -> bool:
	var active := _climbing
	_finalize_climb()
	return active


func get_vault_progress() -> float:
	if not _vaulting:
		return 0.0
	if _vault_time >= VAULT_DURATION:
		_vault_closing = true
		return 1.0
	return clampf(_vault_time / VAULT_DURATION, 0.0, 1.0)


func get_climb_progress() -> float:
	if not _climbing:
		return 0.0
	if _climb_time >= CLIMB_DURATION:
		_climb_closing = true
		return 1.0
	return clampf(_climb_time / CLIMB_DURATION, 0.0, 1.0)


func _handle_movement_input(delta: float) -> void:
	if _spawn_grace_frames > 0:
		_spawn_grace_frames -= 1
		velocity = Vector3.ZERO
		_update_collision_height()
		return
	if _vaulting:
		_process_vault(delta)
		_update_collision_height()
		_handle_weapon_input()
		return
	if _climbing:
		_process_climb(delta)
		_update_collision_height()
		_handle_weapon_input()
		return
	if _input_enabled and Input.is_action_just_pressed("vault"):
		if not try_start_climb():
			try_start_vault()
		if _climbing:
			_process_climb(delta)
			_update_collision_height()
			_handle_weapon_input()
			return
		if _vaulting:
			_process_vault(delta)
			_update_collision_height()
			_handle_weapon_input()
			return
	var input_vector := Vector2.ZERO
	if _input_enabled:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var strafe := input_vector.x
	var forward := input_vector.y
	if _input_enabled and Input.is_action_just_pressed("prone"):
		set_prone(not _prone)
	var crouch_pressed := _input_enabled and Input.is_action_pressed("crouch")
	if _input_enabled and not _prone:
		if crouch_pressed and not _crouching:
			_crouching = true
		elif not crouch_pressed and _crouching and not _is_blocked_above():
			_crouching = false
	var can_sprint := _input_enabled and Input.is_action_pressed("sprint") and forward < -0.2 and not _crouching and not _prone and is_on_floor()
	_sprint_amount = lerpf(_sprint_amount, 1.0 if can_sprint else 0.0, 1.0 - exp(-delta * 10.0))
	var max_speed := CROUCH_SPEED
	if _prone:
		max_speed = PRONE_SPEED
	elif not _crouching:
		max_speed = SPRINT_SPEED if _sprint_amount > 0.5 else WALK_SPEED
	max_speed *= _speed_multiplier
	var wish := transform.basis * Vector3(strafe, 0.0, forward)
	if wish.length() > 0.0:
		wish = wish.normalized()
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, wish.x * max_speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z * max_speed, accel * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif _input_enabled and Input.is_action_just_pressed("jump") and not _crouching and not _prone:
		velocity.y = JUMP_VELOCITY
	var pre_move_vy := velocity.y
	move_and_slide()
	_update_landing(pre_move_vy)
	_update_collision_height()
	_handle_weapon_input()


func _process_vault(delta: float) -> void:
	if _vault_closing:
		_finalize_vault()
		return
	_vault_time = minf(_vault_time + delta, VAULT_DURATION)
	var progress: float = get_vault_progress()
	var desired: Vector3 = _vault_origin.lerp(_vault_target, progress)
	var arc: float = 0.0
	if progress < 0.9:
		arc = sin(progress / 0.9 * PI * 0.5)
	else:
		arc = sin((1.0 - progress) / 0.1 * PI * 0.5)
	desired.y = _vault_origin.y + arc * _vault_raise
	velocity = Vector3.ZERO
	global_position = desired
	move_and_slide()
	_camera_height = lerpf(STAND_EYE, VAULT_EYE, sin(progress * PI))
	if _vault_time >= VAULT_DURATION + 0.02:
		_vaulting = false
		_camera_height = STAND_EYE


func _process_climb(delta: float) -> void:
	if _climb_closing:
		_finalize_climb()
		return
	_climb_time = minf(_climb_time + delta, CLIMB_DURATION)
	var progress: float = get_climb_progress()
	var horizontal_progress: float = clampf((progress - 0.75) / 0.25, 0.0, 1.0)
	var desired: Vector3 = _climb_origin.lerp(_climb_target, horizontal_progress)
	desired.y = lerpf(_climb_origin.y, _climb_target.y, progress)
	velocity = Vector3.ZERO
	global_position = desired
	move_and_slide()
	_camera_height = STAND_EYE + CLIMB_EYE_RAISE * progress
	if _climb_time >= CLIMB_DURATION + 0.02:
		_climbing = false
		_camera_height = STAND_EYE


func _finalize_vault() -> void:
	if _vaulting and _vault_time >= VAULT_DURATION:
		_vaulting = false
		_camera_height = STAND_EYE
		_update_collision_height()


func _finalize_climb() -> void:
	if _climbing and _climb_time >= CLIMB_DURATION:
		_climbing = false
		_camera_height = STAND_EYE
		_update_collision_height()


func _find_obstacle_top() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var forward: Vector3 = -global_transform.basis.z
	var eye_origin: Vector3 = global_position + Vector3(0.0, _camera_height, 0.0)
	var wall_hit: Dictionary = {}
	for wall_distance: float in [0.7, VAULT_FORWARD_DISTANCE]:
		var wall_query := PhysicsRayQueryParameters3D.create(eye_origin, eye_origin + forward * wall_distance)
		wall_query.hit_back_faces = true
		wall_query.collision_mask = 1
		wall_query.exclude = [self]
		var hit: Dictionary = space.intersect_ray(wall_query)
		if not hit.is_empty():
			wall_hit = hit
			break
	if not wall_hit.is_empty():
		var wall_position: Vector3 = Vector3(wall_hit["position"])
		var top_query := PhysicsRayQueryParameters3D.create(wall_position + Vector3.UP * 1.2, wall_position)
		top_query.hit_back_faces = true
		top_query.collision_mask = 1
		top_query.exclude = [self]
		var top_hit: Dictionary = space.intersect_ray(top_query)
		if not top_hit.is_empty():
			var top_position: Vector3 = Vector3(top_hit["position"])
			if top_position.y > global_position.y + VAULT_MIN_HEIGHT * 0.5:
				return {
					"top_position": top_position,
					"normal": Vector3(wall_hit["normal"]),
					"wall_position": wall_position,
				}
	var probe_distances: Array[float] = [0.7, VAULT_FORWARD_DISTANCE * 0.75]
	for probe_distance: float in probe_distances:
		var probe_origin: Vector3 = eye_origin + forward * probe_distance
		var probe_query := PhysicsRayQueryParameters3D.create(probe_origin, probe_origin + Vector3.DOWN * 1.2)
		probe_query.hit_back_faces = true
		probe_query.collision_mask = 1
		probe_query.exclude = [self]
		var probe_hit: Dictionary = space.intersect_ray(probe_query)
		if probe_hit.is_empty():
			continue
		var probe_position: Vector3 = Vector3(probe_hit["position"])
		var probe_normal: Vector3 = Vector3(probe_hit["normal"])
		if probe_position.y > global_position.y + VAULT_MIN_HEIGHT * 0.5 and absf(probe_normal.y) > 0.5:
			return {
				"top_position": probe_position,
				"normal": probe_normal,
				"wall_position": probe_position,
			}
	return {}


func _has_vault_landing(target_position: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(target_position + Vector3.UP * 2.0, target_position + Vector3.DOWN * 2.0)
	query.hit_back_faces = true
	query.collision_mask = 1
	query.exclude = [self]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_position: Vector3 = Vector3(hit["position"])
	return hit_position.y <= target_position.y + 0.35 and hit_position.y >= target_position.y - 1.5


func _handle_weapon_input() -> void:
	if not _input_enabled:
		_weapons.set_aiming(false)
		return
	var aim_pressed := Input.is_action_pressed("aim")
	_aiming = aim_pressed
	_weapons.set_aiming(_aiming)
	if Input.is_action_pressed("fire"):
		var origin := _camera.global_position
		var direction := -_camera.global_transform.basis.z
		if _weapons.try_fire(origin, direction, _aiming):
			_pitch_recoil += float(_weapons.consume_recoil())
	if Input.is_action_just_pressed("reload"):
		_weapons.reload()
	if Input.is_action_just_pressed("weapon_1"):
		switch_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		switch_weapon(1)
	elif Input.is_action_just_pressed("weapon_3"):
		switch_weapon(2)
	elif Input.is_action_just_pressed("weapon_4"):
		switch_weapon(3)
	elif Input.is_action_just_pressed("weapon_5"):
		switch_weapon(4)


func _update_camera(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := clampf(horizontal_speed / SPRINT_SPEED, 0.0, 1.0)
	var eye_target := PRONE_EYE if _prone else CROUCH_EYE if _crouching else STAND_EYE
	if _vaulting:
		eye_target = lerpf(STAND_EYE, VAULT_EYE, sin(get_vault_progress() * PI))
	elif _climbing:
		eye_target = STAND_EYE + CLIMB_EYE_RAISE * get_climb_progress()
	_camera_height = lerpf(_camera_height, eye_target, 1.0 - exp(-delta * 12.0))
	var bob_amp := 0.0
	if _alive and is_on_floor() and horizontal_speed > 0.4:
		var bob_freq := 6.5 + _sprint_amount * 3.5
		_bob_time += delta * bob_freq * maxf(speed_ratio, 0.35)
		bob_amp = (0.025 + _sprint_amount * 0.018) * speed_ratio
	else:
		_bob_time = lerpf(_bob_time, 0.0, 1.0 - exp(-delta * 8.0))
	var bob_y := sin(_bob_time * 2.0) * bob_amp
	var bob_x := cos(_bob_time) * bob_amp * 0.55
	var sway := 0.0
	if _sprint_amount > 0.5 and horizontal_speed > 1.0:
		_sway_time += delta * 9.0
		sway = sin(_sway_time) * 0.008 * _sprint_amount
	else:
		_sway_time = lerpf(_sway_time, 0.0, 1.0 - exp(-delta * 6.0))
	var strafe := 0.0
	if _input_enabled and _alive:
		strafe = Input.get_axis("move_left", "move_right")
	_lean = lerpf(_lean, strafe * 0.025, 1.0 - exp(-delta * 8.0))
	_camera_shake = maxf(_camera_shake - delta * 0.8, 0.0)
	var shake_x := (randf() - 0.5) * _camera_shake
	var shake_y := (randf() - 0.5) * _camera_shake
	_camera.position = Vector3(bob_x + shake_x, _camera_height + bob_y + shake_y, 0.0)
	_camera.rotation = Vector3(_pitch + _pitch_recoil, 0.0, _lean + sway)
	_pitch_recoil = lerpf(_pitch_recoil, 0.0, 1.0 - exp(-delta * 7.0))
	var target_fov := BASE_FOV
	if _sprint_amount > 0.5 and horizontal_speed > 4.0:
		target_fov += SPRINT_FOV_ADD
	if _aiming:
		target_fov -= AIM_FOV_SUB
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-delta * 9.0))


func _update_footsteps(delta: float) -> void:
	if _alive and is_on_floor():
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		if horizontal_speed > 0.8:
			_footstep_timer -= delta * (1.0 + _sprint_amount * 0.7)
			if _footstep_timer <= 0.0:
				footstep.emit(clampf(horizontal_speed / SPRINT_SPEED, 0.4, 1.0))
				_footstep_timer = 0.38
			return
	_footstep_timer = 0.0


func _update_landing(pre_move_vy: float) -> void:
	if is_on_floor() and not _was_on_floor:
		_fall_speed = pre_move_vy
		if _fall_speed < -5.5:
			_camera_shake = minf((absf(_fall_speed) - 4.0) * 0.02, 0.12)
			footstep.emit(clampf(absf(_fall_speed) / 10.0, 0.5, 1.0))
	_was_on_floor = is_on_floor()


func _update_collision_height() -> void:
	if _capsule == null:
		return
	var target_height := PRONE_HEIGHT if _prone else CROUCH_HEIGHT if _crouching else VAULT_CAPSULE_HEIGHT if _vaulting else STAND_HEIGHT
	_capsule.height = target_height
	_collision_shape.position.y = target_height * 0.5


func _is_blocked_above() -> bool:
	var current_height := PRONE_HEIGHT if _prone else CROUCH_HEIGHT if _crouching else STAND_HEIGHT
	return test_move(global_transform, Vector3.UP * (STAND_HEIGHT - current_height + 0.05))


func _build_collision() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			_collision_shape = child as CollisionShape3D
			if child.shape is CapsuleShape3D:
				_capsule = child.shape as CapsuleShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		add_child(_collision_shape)
	if _capsule == null:
		_capsule = CapsuleShape3D.new()
		_collision_shape.shape = _capsule
	_capsule.height = STAND_HEIGHT
	_capsule.radius = 0.35
	_collision_shape.position = Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)


func _setup_nodes() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.make_current()
	_weapons = _camera.get_node_or_null("WeaponViewmodel")
	if _weapons == null:
		_weapons = Node3D.new()
		_weapons.name = "WeaponViewmodel"
		_weapons.set_script(WEAPONS_SCRIPT)
		_camera.add_child(_weapons)
	_projectiles = get_node_or_null("Projectiles") as Node3D
	if _projectiles == null:
		_projectiles = Node3D.new()
		_projectiles.name = "Projectiles"
		_projectiles.set_script(PROJECTILES_SCRIPT)
		add_child(_projectiles)
	_weapons.setup(self, _camera, _projectiles)
	_weapons.fired.connect(_on_weapons_fired)
	_weapons.ammo_changed.connect(_on_ammo_changed)
	_weapons.weapon_switched.connect(_on_weapon_switched)
	_weapons.muzzle_flash.connect(_on_muzzle_flash)


func _on_weapons_fired(origin: Vector3, direction: Vector3, weapon_type: String) -> void:
	weapon_fired.emit(origin, direction, weapon_type)


func _on_ammo_changed(current: int, reserve: int, weapon_name: String) -> void:
	ammo_changed.emit(current, reserve, weapon_name)


func _on_weapon_switched(name: String) -> void:
	weapon_switched.emit(name)


func _on_muzzle_flash(position: Vector3, direction: Vector3, weapon_type: String) -> void:
	muzzle_flash.emit(position, direction, weapon_type)


func _set_mouse_mode() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _input_enabled else Input.MOUSE_MODE_VISIBLE)


func _ensure_input_actions() -> void:
	var actions := {
		"move_forward": [KEY_W],
		"move_backward": [KEY_S],
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL],
		"prone": [KEY_X],
		"vault": [KEY_SPACE],
		"fire": [MOUSE_BUTTON_LEFT],
		"aim": [MOUSE_BUTTON_RIGHT],
		"reload": [KEY_R],
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
		"weapon_3": [KEY_3],
		"weapon_4": [KEY_4],
		"weapon_5": [KEY_5],
	}
	for action_name: String in actions:
		if InputMap.has_action(action_name):
			continue
		InputMap.add_action(action_name)
		if action_name == "fire" or action_name == "aim":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = actions[action_name][0]
			InputMap.action_add_event(action_name, mouse_event)
			continue
		for key: Key in actions[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action_name, event)
