extends Node3D

signal enemy_killed(team: String, name: String)
signal enemy_fired(origin: Vector3, direction: Vector3, weapon_type: String, team: String)
signal enemy_hit_player(point: Vector3, normal: Vector3)
signal explosion_detonated(position: Vector3, radius: float, power: float, type: String, source: String)
signal support_requested(position: Vector3, team: String)

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const RED_COUNT := 6
const BLUE_COUNT := 5
const MAX_ENGAGE_RANGE := 75.0
const RED_RESPAWN_TIME := 6.0
const BLUE_RESPAWN_TIME := 15.0
const DEFENSE_SPAWN_RADIUS := 16.0
const DEPLOY_SPAWN_RADIUS := 10.0

var _player: Node3D = null
var _spawn_points: Array[Vector3] = []
var _nav_points: Array[Vector3] = []
var _cover_points: Array[Vector3] = []
var _units: Array = []
var _player_alive := true
var _spawned := false
var _active := true
var _capture_zones = null
var _vehicle = null
var _vehicle_driver = null
var _vehicle_blocked_timer := 0.0
var _support_requests: Array = []
var _defense_point := Vector3.ZERO
var _defense_radius := 6.0
var _deploy_points: Array[Vector3] = []
var _respawn_timers: Dictionary = {}
var _rng := RandomNumberGenerator.new()



func setup(player: CharacterBody3D, spawn_points: Array, nav_points: Array, cover_points: Array) -> void:
	_player = player
	_spawn_points = _as_vector3_array(spawn_points)
	_nav_points = _as_vector3_array(nav_points)
	_cover_points = _as_vector3_array(cover_points)
	_rng.seed = 2035
	if is_instance_valid(_player):
		if not _player.is_in_group("team_blue"):
			_player.add_to_group("team_blue")
		if not _player.is_in_group("combatants"):
			_player.add_to_group("combatants")


func set_defense_point(position: Vector3, radius: float) -> void:
	_defense_point = position
	_defense_radius = radius


func set_deploy_points(points: Array) -> void:
	_deploy_points = _as_vector3_array(points)


func spawn_teams() -> void:
	_clear_units()
	_spawned = false
	_spawn_rechecked = false
	_respawn_timers.clear()
	for i in RED_COUNT:
		_spawn_unit("red", "Red-%d" % (i + 1), i, _red_spawn_position())
	for i in BLUE_COUNT:
		_spawn_unit("blue", "Ally-%d" % (i + 1), i + RED_COUNT, _blue_spawn_position())
	_spawned = true


func update(delta: float) -> void:
	if not _active:
		return
	if not _spawn_rechecked:
		_spawn_rechecked = true
		_recheck_spawn_safety()





	_age_support_requests(delta)
	_handle_respawns(delta)
	for unit in _units:
		if is_instance_valid(unit):
			unit.tick(delta)
	update_vehicle_ai(delta)


func _handle_respawns(delta: float) -> void:
	var to_revive: Array = []
	for unit in _units:
		if not is_instance_valid(unit) or unit.alive:
			continue
		var remaining: float = float(_respawn_timers.get(unit, 0.0))
		remaining -= delta
		_respawn_timers[unit] = remaining
		if remaining <= 0.0:
			to_revive.append(unit)
	for unit: Node3D in to_revive:
		var respawn_pos := _red_spawn_position() if unit.team == "red" else _blue_spawn_position()
		var safe_pos := _nudge_spawn_clear(respawn_pos)
		unit.revive(safe_pos)
		if unit.team == "red" and _defense_point != Vector3.ZERO:
			unit.assign_defend_task(_defense_point)
		_respawn_timers.erase(unit)


func _red_spawn_position() -> Vector3:
	var fallback := _defense_point
	if fallback == Vector3.ZERO and not _spawn_points.is_empty():
		fallback = _spawn_points[0]
	if fallback == Vector3.ZERO:
		fallback = Vector3(0.0, 0.0, 0.0)
	var offset := Vector3(
		_rng.randf_range(-DEFENSE_SPAWN_RADIUS, DEFENSE_SPAWN_RADIUS),
		0.0,
		_rng.randf_range(-DEFENSE_SPAWN_RADIUS, DEFENSE_SPAWN_RADIUS)
	)
	var result := fallback + offset
	result.y = _ground_y_at(result) + 0.5
	return result


func _blue_spawn_position() -> Vector3:
	var base := Vector3(-30.0, 0.0, -8.0)
	if not _deploy_points.is_empty():
		base = _deploy_points[_rng.randi_range(0, _deploy_points.size() - 1)]
	var offset := Vector3(
		_rng.randf_range(-DEPLOY_SPAWN_RADIUS, DEPLOY_SPAWN_RADIUS),
		0.0,
		_rng.randf_range(-DEPLOY_SPAWN_RADIUS, DEPLOY_SPAWN_RADIUS)
	)
	var result := base + offset
	result.y = _ground_y_at(result) + 0.5
	return result


func _ground_y_at(position: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * 50.0,
		position + Vector3.DOWN * 50.0,
		1
	)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return position.y
	return float(hit.get("position", Vector3.ZERO).y)


func set_active(value: bool) -> void:
	_active = value


func get_alive_counts() -> Dictionary:
	var red := 0
	var blue := 0
	for unit in _units:
		if is_instance_valid(unit) and unit.alive:
			if unit.team == "red":
				red += 1
			else:
				blue += 1
	if _player_alive and is_instance_valid(_player):
		blue += 1
	return {"red": red, "blue": blue}


func damage_enemy(enemy, amount: float, point: Vector3) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not enemy.is_in_group("enemy_ai") or not enemy.has_method("take_damage"):
		return
	var was_alive: bool = enemy.alive
	enemy.take_damage(amount, point)
	if was_alive and not enemy.alive:
		enemy_killed.emit(enemy.team, enemy.unit_name)


func emit_enemy_fired(origin: Vector3, direction: Vector3, weapon_type: String, firing_team: String) -> void:
	enemy_fired.emit(origin, direction, weapon_type, firing_team)


func emit_enemy_hit_player(point: Vector3, normal: Vector3) -> void:
	enemy_hit_player.emit(point, normal)


func set_capture_zones(capture_zones) -> void:
	_capture_zones = capture_zones


func get_objective_zones() -> Array:
	if _capture_zones == null or not is_instance_valid(_capture_zones) or not _capture_zones.has_method("get_control_state"):
		return []
	var control: Dictionary = _capture_zones.get_control_state()
	var zones: Array = []
	var raw: Variant = control.get("zones", [])
	if raw is Array:
		zones = raw
	return zones


func set_vehicle(vehicle) -> void:
	_vehicle = vehicle


func get_vehicle() -> Node3D:
	return _vehicle as Node3D


func request_support(position: Vector3, team: String) -> void:
	_clean_support_requests()
	if _support_requests.size() >= 4:
		_support_requests.pop_front()
	_support_requests.append({"position": position, "team": team, "age": 0.0})
	support_requested.emit(position, team)


func get_nearest_support_request(from_position: Vector3, team: String) -> Vector3:
	_clean_support_requests()
	var best_index := -1
	var best_dist := INF
	for i in range(_support_requests.size()):
		var request: Dictionary = _support_requests[i]
		if String(request.get("team", "")) != team:
			continue
		var pos: Vector3 = request.get("position", Vector3.ZERO)
		var dist := from_position.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_index = i
	if best_index < 0:
		return Vector3.ZERO
	var result: Vector3 = _support_requests[best_index].get("position", Vector3.ZERO)
	_support_requests.remove_at(best_index)
	return result


func emit_enemy_explosion(position: Vector3, radius: float, power: float, type: String, team: String) -> void:
	explosion_detonated.emit(position, radius, power, type, team)


func update_vehicle_ai(delta: float) -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return
	if not _vehicle.has_method("is_alive") or not _vehicle.is_alive():
		release_vehicle_driver()
		return
	var objective := _nearest_red_objective()
	if objective.is_empty():
		if _vehicle_driver != null:
			release_vehicle_driver()
		return
	if _vehicle_driver == null:
		assign_vehicle_driver()
	if _vehicle_driver == null or not is_instance_valid(_vehicle_driver):
		return
	var driver = _vehicle_driver
	if not driver.alive:
		release_vehicle_driver()
		return
	var target: Vector3 = objective.get("position", Vector3.ZERO)
	var seat: Vector3 = _vehicle.get_seat_position()
	driver.global_position = seat
	driver.visible = false
	driver.collision_layer = 0
	driver.collision_mask = 0
	if _vehicle.global_position.distance_to(target) <= 6.0:
		release_vehicle_driver()
		return
	var to_target: Vector3 = target - _vehicle.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance < 0.01:
		release_vehicle_driver()
		return
	var forward: Vector3 = -_vehicle.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = _vehicle.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var to_dir: Vector3 = to_target / distance
	var forward_amount: float = to_dir.dot(forward)
	var lateral: float = to_dir.dot(right)
	if _vehicle.has_method("is_forward_blocked") and _vehicle.is_forward_blocked():
		_vehicle_blocked_timer += delta
	else:
		_vehicle_blocked_timer = maxf(_vehicle_blocked_timer - delta * 2.0, 0.0)
	var throttle: float
	var steer: float
	var brake: bool
	if _vehicle_blocked_timer > 0.45:
		throttle = -0.7
		steer = -signf(lateral) * 1.0 if lateral != 0.0 else 1.0
		brake = false
	else:
		throttle = 1.0 if distance > 8.0 else 0.0
		steer = clampf(lateral * 2.0, -1.0, 1.0)
		brake = distance < 8.0
	_vehicle.ai_drive(throttle, steer, brake, delta)


func assign_vehicle_driver() -> void:
	if _vehicle_driver != null and is_instance_valid(_vehicle_driver):
		return
	if _vehicle == null or not is_instance_valid(_vehicle) or not _vehicle.has_method("is_alive") or not _vehicle.is_alive():
		return
	var best: Node3D = null
	var best_dist := INF
	for unit in _units:
		if not is_instance_valid(unit) or not unit.alive or unit.team != "red":
			continue
		if unit._vehicle_driver:
			continue
		var dist: float = unit.global_position.distance_squared_to(_vehicle.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	if best == null:
		return
	best._vehicle_driver = true
	best.visible = false
	best.collision_layer = 0
	best.collision_mask = 0
	_vehicle_driver = best
	if _vehicle.has_method("set_ai_driver"):
		_vehicle.set_ai_driver(true)


func release_vehicle_driver() -> void:
	_vehicle_blocked_timer = 0.0
	if _vehicle_driver != null and is_instance_valid(_vehicle_driver):
		var driver = _vehicle_driver
		driver._vehicle_driver = false
		if driver.alive:
			driver.visible = true
			driver.collision_layer = 2 if driver.team == "red" else 4
			driver.collision_mask = 1
	_vehicle_driver = null
	if _vehicle != null and is_instance_valid(_vehicle) and _vehicle.has_method("set_ai_driver"):
		_vehicle.set_ai_driver(false)


func get_ai_summary() -> Dictionary:
	var counts := get_alive_counts()
	var unit_states: Array[String] = []
	for unit in _units:
		if is_instance_valid(unit) and unit.has_method("get_state_summary"):
			unit_states.append(str(unit.get_state_summary()))
	return {
		"red_alive": int(counts.get("red", 0)),
		"blue_alive": int(counts.get("blue", 0)),
		"objective_zones": get_objective_zones().size(),
		"support_requests": _support_requests.size(),
		"vehicle_driven": _vehicle_driver != null,
		"unit_states": unit_states,
	}


func get_nearest_hostile(unit, from_position: Vector3, require_los: bool) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for candidate in _units:
		if candidate == unit or not is_instance_valid(candidate):
			continue
		if not candidate.alive or candidate.team == unit.team:
			continue
		if bool(candidate.get("_vehicle_driver")):
			continue
		var candidate_pos: Vector3 = candidate.global_position
		var dist := from_position.distance_to(candidate_pos)
		if dist > MAX_ENGAGE_RANGE or dist >= best_dist:
			continue
		if require_los:
			if not unit.has_method("has_line_of_sight_to") or unit.has_line_of_sight_to(candidate_pos + Vector3.UP * 1.2):
				best = candidate
				best_dist = dist
		else:
			best = candidate
			best_dist = dist
	if _player_alive and is_instance_valid(_player) and unit.team != "blue":
		var player_pos: Vector3 = _player.global_position
		var dist := from_position.distance_to(player_pos)
		if dist <= MAX_ENGAGE_RANGE and dist < best_dist:
			var los_ok: bool = not require_los or not unit.has_method("has_line_of_sight_to") or unit.has_line_of_sight_to(player_pos + Vector3.UP * 1.2)
			if los_ok:
				best = _player
				best_dist = dist
	return best


func get_cover_points() -> Array[Vector3]:
	return _cover_points


func get_nav_points() -> Array[Vector3]:
	return _nav_points


func get_player() -> Node3D:
	return _player


func is_cover_occupied(point: Vector3, ignore: Node3D) -> bool:
	for unit in _units:
		if unit == ignore or not is_instance_valid(unit) or not unit.alive:
			continue
		if unit.global_position.distance_to(point) < 1.5:
			return true
	return false


func set_player_alive(value: bool) -> void:
	_player_alive = value
	if not is_instance_valid(_player):
		return
	if value:
		if not _player.is_in_group("team_blue"):
			_player.add_to_group("team_blue")
		if not _player.is_in_group("combatants"):
			_player.add_to_group("combatants")
	else:
		_player.remove_from_group("team_blue")
		_player.remove_from_group("combatants")


func is_spawned() -> bool:
	return _spawned


func _spawn_unit(unit_team: String, display_name: String, index: int, spawn_position: Vector3) -> void:
	var unit = ENEMY_SCENE.instantiate()
	unit.name = "%s_%d" % [unit_team, index]
	add_child(unit)
	var roles := ["assault", "defender", "grenadier", "support"]

	unit.setup_unit(self, unit_team, display_name, _nudge_spawn_clear(spawn_position), _nav_points, _cover_points, roles[index % roles.size()])
	if unit_team == "red" and _defense_point != Vector3.ZERO:
		unit.assign_defend_task(_defense_point)
	_units.append(unit)


const SPAWN_CLEAR_OFFSETS: Array[Vector3] = [
	Vector3(2.0, 0.0, 0.0),
	Vector3(-2.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 2.0),
	Vector3(0.0, 0.0, -2.0),
	Vector3(2.0, 0.0, 2.0),
	Vector3(-2.0, 0.0, -2.0),
	Vector3(2.0, 0.0, -2.0),
	Vector3(-2.0, 0.0, 2.0),
	Vector3(4.0, 0.0, 0.0),
	Vector3(-4.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 4.0),
	Vector3(0.0, 0.0, -4.0),
]

var _spawn_rechecked := false


func _nudge_spawn_clear(position: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	var candidates: Array[Vector3] = [position]
	for offset: Vector3 in SPAWN_CLEAR_OFFSETS:
		candidates.append(position + offset)
	for candidate in candidates:
		params.transform = Transform3D(Basis(), candidate + Vector3.UP * 0.9)
		if not _blocked_by_static(space, params):
			return candidate
	return position


func _recheck_spawn_safety() -> void:
	for unit in _units:
		if not is_instance_valid(unit) or not unit.alive:
			continue
		var safe := _nudge_spawn_clear(unit.global_position)
		if safe != unit.global_position:
			unit.global_position = safe
		if unit.team == "red" and _player != null and is_instance_valid(_player):
			var away: Vector3 = unit.global_position - _player.global_position
			away.y = 0.0
			if away.length_squared() < 25.0:
				var offset_dir := away.normalized()
				if away.length_squared() < 0.01:
					offset_dir = Vector3(4.0, 0.0, 0.0)
				unit.global_position = _player.global_position + offset_dir * 5.0


func _blocked_by_static(space: PhysicsDirectSpaceState3D, params: PhysicsShapeQueryParameters3D) -> bool:
	for hit in space.intersect_shape(params, 16):
		var collider = hit.get("collider")
		if collider != null and collider is Node and str(collider.name) != "Terrain":
			return true
	return false


func _clear_units() -> void:
	release_vehicle_driver()
	for unit in _units:
		if is_instance_valid(unit):
			unit.queue_free()
	_units.clear()


func _as_vector3_array(values: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for value in values:
		var point: Vector3 = value
		result.append(point)
	return result


func _age_support_requests(delta: float) -> void:
	for request in _support_requests:
		var entry: Dictionary = request
		entry["age"] = float(entry.get("age", 0.0)) + delta
	_clean_support_requests()


func _clean_support_requests() -> void:
	var i := _support_requests.size() - 1
	while i >= 0:
		var entry: Dictionary = _support_requests[i]
		if float(entry.get("age", 0.0)) > 10.0:
			_support_requests.remove_at(i)
		i -= 1


func _nearest_red_objective() -> Dictionary:
	if _defense_point != Vector3.ZERO:
		return {"position": _defense_point, "radius": _defense_radius}
	var best := {}
	var best_dist := INF
	if _vehicle == null or not is_instance_valid(_vehicle):
		return best
	for zone in get_objective_zones():
		var zone_dict: Dictionary = zone
		if String(zone_dict.get("team", "")) == "red":
			continue
		var pos: Vector3 = zone_dict.get("position", Vector3.ZERO)
		var dist: float = _vehicle.global_position.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = zone_dict
	return best
