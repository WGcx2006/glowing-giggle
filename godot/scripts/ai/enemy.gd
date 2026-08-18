extends CharacterBody3D

const RAY_MASK_ALL := 0xFFFFFFFF
const EYE_HEIGHT := 1.55
const TARGET_HEIGHT := 1.25
const BULLET_DAMAGE := 14.0
const BULLET_RANGE := 110.0
const MAX_FIRE_RANGE := 75.0
const PATROL_SPEED := 2.8
const COVER_SPEED := 4.2
const ENGAGE_SPEED := 3.6
const GRAVITY := 20.0

enum AIState {
	PATROL,
	SEEK_COVER,
	COVER,
	ENGAGE,
	SUPPRESS,
	RELOAD,
	DEAD,
	ASSAULT,
	DEFEND,
	SUPPORT,
	GRENADE,
}

const STATE_NAMES := [
	"PATROL",
	"SEEK_COVER",
	"COVER",
	"ENGAGE",
	"SUPPRESS",
	"RELOAD",
	"DEAD",
	"ASSAULT",
	"DEFEND",
	"SUPPORT",
	"GRENADE",
]

var team := "red"
var unit_name := "Enemy"
var max_health := 100.0
var health := 100.0
var alive := true

var _system = null
var _nav_points: Array[Vector3] = []
var _cover_points: Array[Vector3] = []
var _state := AIState.PATROL
var _state_timer := 0.0
var _next_nav_index := 0
var _cover_target := Vector3.ZERO
var _visible_target: Node3D = null
var _last_known_pos := Vector3.ZERO
var _last_known_valid := false
var _last_known_age := 0.0
var _scan_timer := 0.0
var _under_fire_timer := 0.0
var _under_fire := false
var _reload_timer := 0.0
var _resume_state := AIState.PATROL
var _burst_shots := 0
var _burst_pause := 0.0
var _fire_cooldown := 0.0
var _magazine := 30
var _mag_size := 30
var _avoid_timer := 0.0
var _avoid_dir := Vector3.ZERO
var _dead_timer := 0.0
var _death_speed := 3.0
var _death_sign := 1
var _death_axis := Vector3.ZERO
var _body_mesh: MeshInstance3D = null
var _head_mesh: MeshInstance3D = null
var _weapon_mesh: MeshInstance3D = null
var _muzzle := Vector3.ZERO
var _body_material: StandardMaterial3D = null
var _rng := RandomNumberGenerator.new()

var role := "assault"
var _objective_zones: Array = []
var _objective_target := Vector3.ZERO
var _defend_anchor := Vector3.ZERO
var _support_point := Vector3.ZERO
var _grenade_cooldown := 0.0
var _support_call_cooldown := 0.0
var _vehicle_driver := false

var _los_query := PhysicsRayQueryParameters3D.new()
var _shot_query := PhysicsRayQueryParameters3D.new()
var _obstacle_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_rng.randomize()
	_los_query.hit_back_faces = true
	_shot_query.hit_back_faces = true
	_obstacle_query.hit_back_faces = true
	_build_meshes()
	_apply_team()
	collision_layer = 2
	collision_mask = 1


func setup_unit(system, unit_team: String, display_name: String, spawn_position: Vector3, nav_points: Array[Vector3], cover_points: Array[Vector3], role: String = "") -> void:

	_system = system
	team = unit_team
	unit_name = display_name
	if role == "":
		role = _default_role()
	self.role = role
	_nav_points = nav_points
	_cover_points = cover_points
	global_position = spawn_position
	health = max_health
	alive = true
	_state = AIState.PATROL
	_state_timer = 0.0
	_next_nav_index = 0
	_cover_target = Vector3.ZERO
	_visible_target = null
	_last_known_valid = false
	_last_known_age = 0.0
	_scan_timer = 0.0
	_under_fire_timer = 0.0
	_under_fire = false
	_reload_timer = 0.0
	_burst_shots = 0
	_burst_pause = 0.0
	_fire_cooldown = 0.3
	_magazine = _mag_size
	_avoid_timer = 0.0
	_dead_timer = 0.0
	_objective_zones = []
	_objective_target = Vector3.ZERO
	_defend_anchor = Vector3.ZERO
	_support_point = Vector3.ZERO
	_grenade_cooldown = 0.0
	_support_call_cooldown = 0.0
	_vehicle_driver = false
	collision_layer = 2 if team == "red" else 4
	collision_mask = 1
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	_apply_team()
	add_to_group("combatants")
	add_to_group("enemy_ai")
	if team == "red":
		add_to_group("team_red")
	else:
		add_to_group("team_blue")



func tick(delta: float) -> void:
	if not alive:
		_update_death(delta)
		return
	_scan_timer -= delta
	_fire_cooldown -= delta
	_state_timer -= delta
	_grenade_cooldown -= delta
	_support_call_cooldown -= delta
	if _burst_pause > 0.0:
		_burst_pause -= delta
	if _under_fire_timer > 0.0:
		_under_fire_timer -= delta
		if _under_fire_timer <= 0.0:
			_under_fire = false
	if _avoid_timer > 0.0:
		_avoid_timer -= delta

	if _vehicle_driver:
		velocity = Vector3.ZERO
		return

	_refresh_objective_zones()

	if _state == AIState.RELOAD:
		_reload_timer -= delta
		_stand_still(delta)
		if _reload_timer <= 0.0:
			_magazine = _mag_size
			_state = _resume_state
			_state_timer = 1.8 if _resume_state == AIState.SUPPRESS else 0.0
		return

	if _state == AIState.GRENADE:
		_stand_still(delta)
		if _state_timer <= 0.0:
			_state = _resume_state
			_state_timer = 0.0
		return

	var target := _acquire_target()
	if _target_is_alive(target):
		_last_known_pos = _target_center(target)
		_last_known_valid = true
		_last_known_age = 0.0

	if team == "red" and _defend_anchor != Vector3.ZERO and global_position.distance_to(_defend_anchor) > 100.0:
		_visible_target = null
		_last_known_valid = false
		_state = AIState.DEFEND
		_state_timer = 0.0

	if _under_fire and _is_disadvantaged() and _support_call_cooldown <= 0.0:
		_support_call_cooldown = 8.0
		if _system != null and is_instance_valid(_system) and _system.has_method("request_support"):
			_system.request_support(global_position, team)

	if _under_fire and _state != AIState.SEEK_COVER and _state != AIState.COVER:
		_enter_seek_cover()
	elif is_instance_valid(target) and _state != AIState.SEEK_COVER and _state != AIState.COVER:
		_state = AIState.ENGAGE
		_state_timer = 0.0
	elif _state == AIState.ENGAGE or _state == AIState.SUPPRESS:
		if _last_known_valid:
			_last_known_age += delta
			if _last_known_age > 3.0:
				_state = AIState.PATROL
				_state_timer = 0.0
	elif not is_instance_valid(target):
		_update_objective_task()

	match _state:
		AIState.PATROL:
			_update_patrol(delta)
		AIState.SEEK_COVER:
			_update_seek_cover(delta)
		AIState.COVER:
			_update_cover(delta)
		AIState.ENGAGE:
			_update_engage(delta, target)
		AIState.SUPPRESS:
			_update_suppress(delta)
		AIState.RELOAD:
			velocity = Vector3.ZERO
		AIState.DEAD:
			pass
		AIState.ASSAULT:
			_update_assault(delta)
		AIState.DEFEND:
			_update_defend(delta)
		AIState.SUPPORT:
			_update_support(delta)
		AIState.GRENADE:
			velocity = Vector3.ZERO


func take_damage(amount: float, point: Vector3) -> void:
	if not alive:
		return
	health -= amount
	_under_fire = true
	_under_fire_timer = 2.5
	_last_known_valid = true
	_last_known_pos = _infer_attacker_position(point)
	_last_known_age = 0.0
	if health <= 0.0:
		health = 0.0
		_die()


func has_line_of_sight_to(point: Vector3) -> bool:
	_los_query.from = _eye_position()
	_los_query.to = point
	_los_query.collision_mask = RAY_MASK_ALL
	_los_query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_los_query)
	if hit.is_empty():
		return true
	var collider = hit.get("collider")
	if collider != null and collider is Node3D and _is_hostile(collider):
		return true
	return false


func _build_meshes() -> void:
	_body_mesh = MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.42
	body_mesh.height = 1.2
	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.8
	_body_material.metallic = 0.1
	_body_mesh.mesh = body_mesh
	_body_mesh.material_override = _body_material
	_body_mesh.position = Vector3(0.0, 0.9, 0.0)
	add_child(_body_mesh)

	_head_mesh = MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.24
	head_mesh.height = 0.48
	_head_mesh.mesh = head_mesh
	_head_mesh.material_override = _body_material
	_head_mesh.position = Vector3(0.0, 1.62, 0.0)
	add_child(_head_mesh)

	var weapon_material := StandardMaterial3D.new()
	weapon_material.albedo_color = Color(0.12, 0.13, 0.15)
	weapon_material.metallic = 0.6
	weapon_material.roughness = 0.45

	_weapon_mesh = MeshInstance3D.new()
	var weapon_mesh := BoxMesh.new()
	weapon_mesh.size = Vector3(0.12, 0.16, 0.8)
	_weapon_mesh.mesh = weapon_mesh
	_weapon_mesh.material_override = weapon_material
	_weapon_mesh.position = Vector3(0.34, 1.05, -0.45)
	add_child(_weapon_mesh)

	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.025
	barrel_mesh.bottom_radius = 0.025
	barrel_mesh.height = 0.5
	barrel_mesh.radial_segments = 8
	barrel.mesh = barrel_mesh
	barrel.material_override = weapon_material
	barrel.position = Vector3(0.34, 1.05, -0.95)
	add_child(barrel)
	_muzzle = Vector3(0.34, 1.05, -1.15)


func _apply_team() -> void:
	if _body_material == null:
		return
	if team == "red":
		_body_material.albedo_color = Color(0.58, 0.13, 0.12)
	else:
		_body_material.albedo_color = Color(0.10, 0.30, 0.60)


func _acquire_target() -> Node3D:
	if _system == null or not is_instance_valid(_system):
		return null
	if _scan_timer > 0.0:
		return _visible_target if _target_is_alive(_visible_target) else null
	_scan_timer = 0.15
	_visible_target = _system.get_nearest_hostile(self, _eye_position(), true)
	return _visible_target if _target_is_alive(_visible_target) else null


func get_state_summary() -> Dictionary:
	var state_name := "UNKNOWN"
	if _state >= 0 and _state < STATE_NAMES.size():
		state_name = STATE_NAMES[_state]
	var target_pos := Vector3.ZERO
	if _target_is_alive(_visible_target):
		target_pos = _target_center(_visible_target)
	elif _last_known_valid:
		target_pos = _last_known_pos
	return {
		"name": unit_name,
		"team": team,
		"role": role,
		"state": state_name,
		"alive": alive,
		"health": health,
		"position": global_position,
		"objective": _objective_target,
		"target": target_pos,
	}


func throw_grenade(target_pos: Vector3) -> bool:
	if _grenade_cooldown > 0.0:
		return false
	var dist := global_position.distance_to(target_pos)
	if dist > 10.0:
		return false
	if not has_line_of_sight_to(target_pos):
		return false
	var grenade := _EnemyGrenade.new()
	grenade._system = _system
	grenade._team = team
	add_child(grenade)
	grenade.global_position = global_position + Vector3.UP * 0.9
	grenade.launch(target_pos)
	_grenade_cooldown = 6.0
	return true


func _refresh_objective_zones() -> void:
	if _system == null or not is_instance_valid(_system) or not _system.has_method("get_objective_zones"):
		_objective_zones = []
		return
	var zones: Array = _system.get_objective_zones()
	_objective_zones = zones if zones != null else []


func _is_disadvantaged() -> bool:
	if _system == null or not is_instance_valid(_system) or not _system.has_method("get_alive_counts"):
		return false
	var counts: Dictionary = _system.get_alive_counts()
	var red := int(counts.get("red", 0))
	var blue := int(counts.get("blue", 0))
	if team == "red":
		return red < blue
	return blue < red


func _default_role() -> String:
	var parts := String(name).rsplit("_", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		var roles := ["assault", "defender", "grenadier", "support"]
		return roles[posmod(int(parts[1]), roles.size())]
	return "assault"


func _update_objective_task() -> void:
	if _state != AIState.PATROL:
		return
	if _objective_zones.is_empty():
		if _try_accept_support_request():
			return
		return
	if role == "defender" or role == "support":
		var own := _nearest_zone_for_team(team)
		if not own.is_empty():
			_assign_zone_task(own)
			return
	var hostile := _nearest_hostile_zone()
	if hostile.is_empty():
		if _try_accept_support_request():
			return
		return
	_assign_zone_task(hostile)


func _nearest_zone_for_team(zone_team: String) -> Dictionary:
	var best := {}
	var best_dist := INF
	for zone in _objective_zones:
		var zone_dict: Dictionary = zone
		if String(zone_dict.get("team", "")) != zone_team:
			continue
		var pos: Vector3 = zone_dict.get("position", Vector3.ZERO)
		var dist := global_position.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = zone_dict
	return best


func _nearest_hostile_zone() -> Dictionary:
	var best := {}
	var best_dist := INF
	for zone in _objective_zones:
		var zone_dict: Dictionary = zone
		if String(zone_dict.get("team", "")) == team:
			continue
		var pos: Vector3 = zone_dict.get("position", Vector3.ZERO)
		var dist := global_position.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = zone_dict
	return best


func _assign_zone_task(zone: Dictionary) -> void:
	_objective_target = zone.get("position", Vector3.ZERO)
	if role == "defender" or role == "support":
		_defend_anchor = _objective_target
		_state = AIState.DEFEND
	else:
		_state = AIState.ASSAULT
	_state_timer = 0.0


func _try_accept_support_request() -> bool:
	if role != "support":
		return false
	if _system == null or not is_instance_valid(_system) or not _system.has_method("get_nearest_support_request"):
		return false
	var request_pos: Vector3 = _system.get_nearest_support_request(global_position, team)
	if request_pos == Vector3.ZERO:
		return false
	_support_point = request_pos
	_state = AIState.SUPPORT
	_state_timer = 12.0
	return true


func _update_patrol(delta: float) -> void:
	if _state_timer > 0.0:
		velocity = Vector3.ZERO
		return
	if _nav_points.is_empty():
		velocity = Vector3.ZERO
		return
	var waypoint := _patrol_waypoint()
	var offset := _horizontal_dir_to(waypoint)
	if offset.length_squared() < 0.25:
		_next_nav_index += 1
		_state_timer = 0.4
		velocity = Vector3.ZERO
		return
	_face_towards(waypoint)
	var move_dir := _steer(offset)
	_move_with_gravity(move_dir, PATROL_SPEED, delta)


func _patrol_waypoint() -> Vector3:
	var anchor := _defend_anchor
	if anchor == Vector3.ZERO:
		anchor = _objective_target
	if team != "red" or anchor == Vector3.ZERO:
		return _nav_points[_next_nav_index % _nav_points.size()]
	for attempt in range(_nav_points.size()):
		var index := (_next_nav_index + attempt) % _nav_points.size()
		var point := _nav_points[index]
		if point.distance_to(anchor) <= 90.0:
			_next_nav_index = index
			return point
	return _nav_points[_next_nav_index % _nav_points.size()]


func _update_seek_cover(delta: float) -> void:
	if _state_timer <= 0.0:
		_state = AIState.COVER
		_state_timer = 0.0
		velocity = Vector3.ZERO
		return
	var offset := _horizontal_dir_to(_cover_target)
	if offset.length_squared() < 1.0:
		_state = AIState.COVER
		_state_timer = 0.0
		velocity = Vector3.ZERO
		return
	_face_towards(_cover_target)
	var move_dir := _steer(offset)
	_move_with_gravity(move_dir, COVER_SPEED, delta)


func _update_cover(delta: float) -> void:
	_stand_still(delta)
	if _last_known_valid:
		_face_towards(_last_known_pos)
		_try_fire_burst(_last_known_pos, true)
	if not _under_fire:
		_state = AIState.PATROL
		_state_timer = 0.0


func _update_engage(delta: float, target: Node3D) -> void:
	if not _target_is_alive(target):
		_state = AIState.SUPPRESS
		_state_timer = 1.8
		velocity = Vector3.ZERO
		return
	var target_pos := _target_center(target)
	_face_towards(target_pos)
	var dist := global_position.distance_to(target.global_position)
	if _try_throw_grenade(target_pos, AIState.ENGAGE):
		return
	if dist > 45.0:
		var move_dir := _steer(_horizontal_dir_to(target.global_position))
		_move_with_gravity(move_dir, ENGAGE_SPEED, delta)
	else:
		_stand_still(delta)
	if _fire_cooldown <= 0.0:
		_try_fire_burst(target_pos, false)


func _update_assault(delta: float) -> void:
	if role == "grenadier":
		var grenade_target: Node3D = _visible_target if _target_is_alive(_visible_target) else null
		if grenade_target != null and global_position.distance_to(grenade_target.global_position) <= 10.0:
			if _try_throw_grenade(_target_center(grenade_target), AIState.ASSAULT):
				return
	var zone := _find_objective_zone()
	if zone.is_empty():
		_state = AIState.PATROL
		_state_timer = 0.0
		return
	if not bool(zone.get("active", true)):
		_state = AIState.PATROL
		_state_timer = 0.0
		return
	if String(zone.get("team", "")) == team:
		_defend_anchor = _objective_target
		_state = AIState.DEFEND
		_state_timer = 0.0
		velocity = Vector3.ZERO
		return
	var radius := _zone_radius(zone)
	var offset := _horizontal_dir_to(_objective_target)
	if offset.length_squared() <= radius * radius:
		_stand_still(delta)
		_face_towards(_objective_target)
		if _under_fire:
			_enter_seek_cover()
		return
	_face_towards(_objective_target)
	var move_dir := _steer(offset)
	_move_with_gravity(move_dir, ENGAGE_SPEED, delta)


func _update_defend(delta: float) -> void:
	var zone := _find_objective_zone()
	if zone.is_empty() and _defend_anchor != Vector3.ZERO:
		zone = {"position": _defend_anchor, "radius": 6.0, "team": team, "active": true}
	if zone.is_empty():
		_state = AIState.PATROL
		_state_timer = 0.0
		return
	if not bool(zone.get("active", true)):
		_state = AIState.PATROL
		_state_timer = 0.0
		return
	var anchor: Vector3 = zone.get("position", _defend_anchor)
	var radius := _zone_radius(zone)
	_defend_anchor = anchor
	if String(zone.get("team", "")) != team and team == "blue":
		_objective_target = anchor
		_state = AIState.ASSAULT
		_state_timer = 0.0
		return
	var offset := _horizontal_dir_to(anchor)
	if offset.length_squared() > radius * radius:
		_face_towards(anchor)
		var move_dir := _steer(offset)
		_move_with_gravity(move_dir, ENGAGE_SPEED, delta)
		return
	_stand_still(delta)
	var threat := _nearest_hostile_position()
	if threat != Vector3.ZERO:
		_face_towards(threat)
		_try_fire_burst(threat, true)
	elif _last_known_valid:
		_face_towards(_last_known_pos)
		_try_fire_burst(_last_known_pos, true)


func _update_support(delta: float) -> void:
	if _support_point == Vector3.ZERO or _state_timer <= 0.0:
		_support_point = Vector3.ZERO
		_state = AIState.COVER if _under_fire else AIState.PATROL
		_state_timer = 0.0
		return
	var offset := _horizontal_dir_to(_support_point)
	if offset.length_squared() < 1.0:
		_support_point = Vector3.ZERO
		_state = AIState.COVER if _under_fire else AIState.PATROL
		_state_timer = 0.0
		return
	_face_towards(_support_point)
	var move_dir := _steer(offset)
	_move_with_gravity(move_dir, PATROL_SPEED, delta)


func _try_throw_grenade(target_pos: Vector3, resume_state: int) -> bool:
	if role != "grenadier" or _grenade_cooldown > 0.0:
		return false
	if not throw_grenade(target_pos):
		return false
	_resume_state = resume_state
	_state = AIState.GRENADE
	_state_timer = 0.5
	velocity = Vector3.ZERO
	return true


func _find_objective_zone() -> Dictionary:
	for zone in _objective_zones:
		var zone_dict: Dictionary = zone
		if zone_dict.get("position", Vector3.ZERO) == _objective_target:
			return zone_dict
	return {}


func _zone_radius(zone: Dictionary) -> float:
	return float(zone.get("radius", 6.0))


func _nearest_hostile_position() -> Vector3:
	if _system != null and is_instance_valid(_system) and _system.has_method("get_nearest_hostile"):
		var enemy: Node3D = _system.get_nearest_hostile(self, _eye_position(), false)
		if _target_is_alive(enemy):
			return _target_center(enemy)
	if _last_known_valid:
		return _last_known_pos
	return Vector3.ZERO


func _update_suppress(delta: float) -> void:
	_stand_still(delta)
	if _last_known_valid:
		_face_towards(_last_known_pos)
		_try_fire_burst(_last_known_pos, true)
	else:
		_state = AIState.PATROL
		_state_timer = 0.0
		return
	if _state_timer <= 0.0:
		_state = AIState.COVER if _under_fire else AIState.PATROL
		_state_timer = 0.0


func _enter_seek_cover() -> void:
	_state = AIState.SEEK_COVER
	_state_timer = 6.0
	_cover_target = _choose_cover_point()


func _choose_cover_point() -> Vector3:
	if _system == null or not is_instance_valid(_system):
		return _fallback_cover_point()
	var points: Array = _system.get_cover_points()
	if points.is_empty():
		return _fallback_cover_point()
	var best := Vector3.ZERO
	var best_score := -INF
	var anchor := _defend_anchor
	if anchor == Vector3.ZERO:
		anchor = _objective_target
	for i in range(points.size()):
		var point: Vector3 = points[i]
		if team == "red" and anchor != Vector3.ZERO and point.distance_to(anchor) > 90.0:
			continue
		if _system.is_cover_occupied(point, self):
			continue
		var score := -global_position.distance_to(point)
		if _last_known_valid:
			score += (global_position.distance_to(_last_known_pos) - point.distance_to(_last_known_pos)) * 0.6
		if score > best_score:
			best_score = score
			best = point
	if best_score == -INF:
		return _fallback_cover_point()
	return best


func _fallback_cover_point() -> Vector3:
	var dir := Vector3(1.0, 0.0, 0.0)
	if _last_known_valid:
		var away := global_position - _last_known_pos
		away.y = 0.0
		if away.length_squared() > 0.01:
			dir = away.normalized()
	return global_position + dir * 7.0 + Vector3(0.0, 0.0, _rng.randf_range(-3.0, 3.0))


func _try_fire_burst(target_pos: Vector3, suppression: bool) -> void:
	if _burst_pause > 0.0 or _fire_cooldown > 0.0:
		return
	if global_position.distance_to(target_pos) > MAX_FIRE_RANGE:
		return
	if _magazine <= 0:
		_start_reload(AIState.SUPPRESS if suppression else AIState.ENGAGE)
		return
	var burst_max := 6 if suppression else 4
	if _burst_shots >= burst_max:
		_burst_shots = 0
		_burst_pause = 0.45
		return
	_fire_weapon(target_pos)
	_burst_shots += 1
	_fire_cooldown = 0.13


func _fire_weapon(target_pos: Vector3) -> void:
	_magazine -= 1
	var origin := to_global(_muzzle)
	var aim := target_pos - origin
	var spread := 0.035 if _state == AIState.SUPPRESS or _state == AIState.COVER else 0.018
	var dir := aim.normalized()
	dir += Vector3(
		_rng.randf_range(-spread, spread),
		_rng.randf_range(-spread, spread),
		_rng.randf_range(-spread, spread)
	)
	dir = dir.normalized()
	if _system != null and is_instance_valid(_system):
		_system.emit_enemy_fired(origin, dir, "rifle", team)
	_apply_shot(origin, dir)


func _apply_shot(origin: Vector3, direction: Vector3) -> void:
	_shot_query.from = origin
	_shot_query.to = origin + direction * BULLET_RANGE
	_shot_query.collision_mask = RAY_MASK_ALL
	_shot_query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_shot_query)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider == null or not (collider is Node):
		return
	var hit_pos: Vector3 = hit.get("position", origin)
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	var player: Node3D = null
	if _system != null and is_instance_valid(_system):
		player = _system.get_player()
	if collider.is_in_group("enemy_ai") and _is_hostile(collider):
		if _system != null and is_instance_valid(_system):
			_system.damage_enemy(collider, BULLET_DAMAGE, hit_pos)
		elif collider.has_method("take_damage"):
			collider.take_damage(BULLET_DAMAGE, hit_pos)
	elif collider == player and _is_hostile(collider):
		collider.take_damage(BULLET_DAMAGE)
		if _system != null and is_instance_valid(_system):
			_system.emit_enemy_hit_player(hit_pos, hit_normal)
	elif collider.is_in_group("vehicle") and _is_hostile(collider) and collider.has_method("take_damage"):
		collider.take_damage(BULLET_DAMAGE)


func _is_hostile(body: Node) -> bool:
	if body == self:
		return false
	if body.is_in_group("team_red"):
		return team != "red"
	if body.is_in_group("team_blue"):
		return team != "blue"
	if body.is_in_group("vehicle"):
		return team == "red"
	if _system != null and is_instance_valid(_system) and body == _system.get_player():
		return team == "red"
	return false


func _start_reload(resume_state: int) -> void:
	_state = AIState.RELOAD
	_reload_timer = 1.7
	_resume_state = resume_state
	_burst_shots = 0
	_burst_pause = 0.0
	velocity = Vector3.ZERO


func _infer_attacker_position(point: Vector3) -> Vector3:
	var away := point - global_position
	if away.length_squared() < 0.01:
		return point
	return point + away.normalized() * 3.0


func _steer(wish_dir: Vector3) -> Vector3:
	if wish_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var forward := wish_dir.normalized()
	if _avoid_timer > 0.0 and _avoid_dir.length_squared() > 0.01:
		return _avoid_dir
	var origin := global_position + Vector3.UP * 1.0
	_obstacle_query.from = origin
	_obstacle_query.to = origin + forward * 2.0
	_obstacle_query.collision_mask = RAY_MASK_ALL
	_obstacle_query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_obstacle_query)
	if not hit.is_empty():
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if normal.y > 0.6:
			return forward
		var side := Vector3(-normal.z, 0.0, normal.x)
		if side.length_squared() < 0.01:
			side = Vector3(1.0, 0.0, 0.0)
		side = side.normalized()
		if side.dot(forward) < 0.0:
			side = -side
		_avoid_dir = side
		_avoid_timer = 0.55
		return side
	return forward


func _move_with_gravity(move_dir: Vector3, speed: float, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	move_and_slide()


func _stand_still(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
	else:
		velocity = Vector3.ZERO


func _face_towards(point: Vector3) -> void:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		return
	look_at(global_position + offset, Vector3.UP)
	rotation.x = 0.0
	rotation.z = 0.0


func _eye_position() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func _target_center(node: Node3D) -> Vector3:
	return node.global_position + Vector3.UP * TARGET_HEIGHT


func _target_is_alive(target) -> bool:
	if not is_instance_valid(target):
		return false
	if target.is_in_group("enemy_ai"):
		return target.alive
	return true


func _horizontal_dir_to(point: Vector3) -> Vector3:
	var offset := point - global_position
	offset.y = 0.0
	return offset


func _die() -> void:
	alive = false
	health = 0.0
	if team == "red":
		remove_from_group("team_red")
	else:
		remove_from_group("team_blue")
	_state = AIState.DEAD
	_state_timer = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_dead_timer = 1.1
	_death_speed = _rng.randf_range(2.6, 4.2)
	_death_sign = -1 if _rng.randf() < 0.5 else 1
	_death_axis = Vector3(0.0, 0.0, 1.0) if _rng.randf() < 0.5 else Vector3(1.0, 0.0, 0.0)


func assign_defend_task(point: Vector3) -> void:
	_defend_anchor = point
	_objective_target = point
	_state = AIState.DEFEND
	_state_timer = 0.0


func revive(spawn_position: Vector3) -> void:
	global_position = spawn_position
	health = max_health
	alive = true
	_state = AIState.PATROL
	_state_timer = 0.0
	_next_nav_index = 0
	_cover_target = Vector3.ZERO
	_visible_target = null
	_last_known_valid = false
	_last_known_age = 0.0
	_scan_timer = 0.0
	_under_fire_timer = 0.0
	_under_fire = false
	_reload_timer = 0.0
	_burst_shots = 0
	_burst_pause = 0.0
	_fire_cooldown = 0.3
	_magazine = _mag_size
	_avoid_timer = 0.0
	_dead_timer = 0.0
	_objective_target = Vector3.ZERO
	_defend_anchor = Vector3.ZERO
	_support_point = Vector3.ZERO
	_grenade_cooldown = 0.0
	_support_call_cooldown = 0.0
	_vehicle_driver = false
	collision_layer = 2 if team == "red" else 4
	collision_mask = 1
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	add_to_group("combatants")
	add_to_group("enemy_ai")
	if team == "red":
		add_to_group("team_red")
	else:
		add_to_group("team_blue")


func _update_death(delta: float) -> void:
	if _dead_timer <= 0.0:
		return
	_dead_timer -= delta
	var step := _death_speed * delta
	if _death_axis.z > 0.5:
		rotation.z += step * _death_sign
		rotation.x += step * 0.25
	else:
		rotation.x += step * _death_sign
		rotation.z += step * 0.25


class _EnemyGrenade:
	extends Node3D

	const FUSE_TIME := 1.8
	const GRAVITY := 18.0
	const INITIAL_SPEED := 13.0
	const LIFT := 4.0

	var _system = null
	var _team := ""
	var _velocity := Vector3.ZERO
	var _fuse := FUSE_TIME


	func _ready() -> void:
		set_physics_process(true)
		var mesh_instance := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.18, 0.2, 0.16)
		material.metallic = 0.7
		material.roughness = 0.35
		mesh_instance.mesh = sphere
		mesh_instance.material_override = material
		add_child(mesh_instance)


	func launch(target_pos: Vector3) -> void:
		var offset := target_pos - global_position
		offset.y = 0.0
		var dir := Vector3.FORWARD
		if offset.length_squared() > 0.01:
			dir = offset.normalized()
		_velocity = dir * INITIAL_SPEED + Vector3.UP * LIFT


	func _physics_process(delta: float) -> void:
		_velocity.y -= GRAVITY * delta
		global_position += _velocity * delta
		_fuse -= delta
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.new()
		query.hit_back_faces = true
		query.from = global_position
		query.to = global_position + Vector3.DOWN * 0.25
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if _fuse <= 0.0 or not hit.is_empty():
			_detonate()


	func _detonate() -> void:
		if _system != null and is_instance_valid(_system) and _system.has_method("emit_enemy_explosion"):
			_system.emit_enemy_explosion(global_position, 8.0, 80.0, "grenade", _team)
		queue_free()
