extends Node3D

const ENVIRONMENT_SCENE := preload("res://scenes/environment.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMIES_SCENE := preload("res://scenes/enemies.tscn")
const CAPTURE_ZONES_SCENE := preload("res://scenes/capture_zones.tscn")
const FX_SCENE := preload("res://scenes/fx.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const AUDIO_SCRIPT := preload("res://scripts/audio/audio_manager.gd")
const GAME_MODE_SCRIPT := preload("res://scripts/game/game_mode.gd")
const JEEP_SCENE := preload("res://scenes/vehicles/jeep.tscn")
const TANK_SCENE := preload("res://scenes/vehicles/tank.tscn")
const IFV_SCENE := preload("res://scenes/vehicles/ifv.tscn")
const MAP_THEME_SCRIPT := preload("res://scripts/render/map_theme.gd")
const ANIMATOR_SCRIPT := preload("res://scripts/animation/weapon_animator.gd")
const LOADOUT_SCRIPT := preload("res://scripts/gameplay/loadout.gd")
const NETWORK_MANAGER_SCRIPT := preload("res://scripts/network/network_manager.gd")
const ENTITY_SYNC_SCRIPT := preload("res://scripts/network/entity_sync.gd")
const ENTITY_BROADCASTER_SCRIPT := preload("res://scripts/network/entity_broadcaster.gd")
const REMOTE_ENTITY_FACTORY_SCRIPT := preload("res://scripts/network/remote_entity_factory.gd")
const REMOTE_VEHICLE_SCRIPT := preload("res://scripts/network/remote_vehicle.gd")
const SESSION_ENTITY_ACCESS_SCRIPT := preload("res://scripts/network/session_entity_access.gd")
const SAVE_MANAGER_SCRIPT := preload("res://scripts/save/save_manager.gd")
const PERFORMANCE_MONITOR_SCRIPT := preload("res://scripts/performance/performance_monitor.gd")
const VEHICLE_ENGINE_SCRIPT := preload("res://scripts/audio/vehicle_engine.gd")
const AMBIENT_AUDIO_SCRIPT := preload("res://scripts/audio/ambient_audio.gd")

const ZONE_DATA := [
	{"id": "A", "position": Vector3(-78.0, 0.0, 66.0), "radius": 8.0, "height": 5.0, "team": "red"},
	{"id": "B", "position": Vector3(62.0, 0.0, -74.0), "radius": 8.0, "height": 5.0, "team": "red"},
	{"id": "C", "position": Vector3(46.0, 0.0, 96.0), "radius": 8.0, "height": 5.0, "team": "red"},
	{"id": "D", "position": Vector3(-108.0, 0.0, -108.0), "radius": 8.0, "height": 5.0, "team": "red"},
]

var _environment
var _player
var _enemy_system
var _capture_zones
var _fx
var _hud
var _audio
var _game_mode
var _vehicle
var _tank
var _ifv
var _current_vehicle
var _in_vehicle := false
var _animator
var _network_manager
var _entity_sync
var _entity_broadcaster
var _remote_entity_factory
var _session_entity_access
var _save_manager
var _performance_monitor
var _jeep_engine
var _tank_engine
var _ifv_engine
var _ambient_audio

var _time_of_day := 0.63
var _map_theme := "arctic"
var _quality := "high"
var _objective_text := "占领 A/B/C/D 或消灭红队"
var _winner := ""
var _respawn_timer := 0.0
var _kill_feed: Array = []
var _hud_dirty := true
var _hud_state: Dictionary = {}
var _spawn_points: Array = []
var _sensitivity := 1.0
var _last_network_packet: Array = []


func _ready() -> void:
	_setup_input_actions()
	_build_game()
	_environment.set_quality(_quality)
	_apply_map_theme()
	_enter_main_menu()
	print("[Battlefield 2035] Godot integration ready")


func _process(delta: float) -> void:
	if _player == null or _hud == null or _environment == null:
		return
	if _performance_monitor != null:
		_performance_monitor.sample(delta)
	if _winner == "" and _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_open_deployment_menu()

	var camera: Camera3D = _player.get_camera()
	if _in_vehicle and is_instance_valid(_vehicle):
		camera = _vehicle.get_camera()
	_environment.update(delta, camera, _time_of_day)
	_enemy_system.update(delta)
	_capture_zones.update(delta)
	_game_mode.update(delta)
	_fx.update(delta)

	if _winner == "":
		if _in_vehicle:
			_handle_vehicle_driving(delta)
		else:
			_handle_vehicle_interact()
			if Input.is_action_just_pressed("inspect") and _animator != null and is_instance_valid(_animator):
				_animator.play_inspect()
			if _animator != null and is_instance_valid(_animator):
				_animator.update(delta)

	if _hud_dirty:
		_hud_state = _build_hud_state()
		_hud.update_state(_hud_state)
		_hud_dirty = false


func _build_hud_state() -> Dictionary:
	var state: Dictionary = _player.get_state()
	state["objective"] = _objective_text
	state["capture_zones"] = _capture_zones.get_control_state().get("zones", [])
	state["kill_feed"] = _kill_feed
	state["minimap"] = _build_minimap_state()
	state["game_mode"] = _game_mode.get_state()
	return state


func _build_minimap_state() -> Dictionary:
	var enemy_entries: Array = []
	if _enemy_system != null and is_instance_valid(_enemy_system):
		for child in _enemy_system.get_children():
			if not is_instance_valid(child) or not child.has_method("get_state_summary"):
				continue
			var summary: Dictionary = child.get_state_summary()
			enemy_entries.append({
				"position": summary.get("position", Vector3.ZERO),
				"team": summary.get("team", "red"),
				"alive": summary.get("alive", false),
			})
	var vehicle_entries: Array = []
	if _vehicle != null and is_instance_valid(_vehicle):
		vehicle_entries.append(_vehicle.global_position)
	if _tank != null and is_instance_valid(_tank):
		vehicle_entries.append(_tank.global_position)
	if _ifv != null and is_instance_valid(_ifv):
		vehicle_entries.append(_ifv.global_position)
	var zone_entries: Array = []
	if _capture_zones != null and is_instance_valid(_capture_zones):
		var control: Dictionary = _capture_zones.get_control_state()
		for zone in control.get("zones", []):
			var zone_entry: Dictionary = zone
			zone_entries.append({
				"id": zone_entry.get("id", ""),
				"position": zone_entry.get("position", Vector3.ZERO),
				"team": zone_entry.get("team", ""),
				"contested": zone_entry.get("contested", false),
			})
	return {
		"player_pos": _player.global_position,
		"player_yaw": _player.rotation.y,
		"enemies": enemy_entries,
		"vehicles": vehicle_entries,
		"zones": zone_entries,
	}


func get_hud() -> CanvasLayer:
	return _hud


func get_game_mode() -> Node:
	return _game_mode


func get_environment() -> Node3D:
	return _environment


func get_player() -> CharacterBody3D:
	return _player


func get_vehicle() -> Node3D:
	return _vehicle


func get_tank() -> Node3D:
	return _tank


func get_ifv() -> Node3D:
	return _ifv


func get_map_theme() -> String:
	return _map_theme


func get_animator() -> Node3D:
	return _animator


func set_map_theme(theme_id: String) -> void:
	_map_theme = theme_id
	_apply_map_theme()
	_hud_dirty = true


func _apply_map_theme() -> void:
	if _environment == null or not is_instance_valid(_environment):
		return
	_environment.set_map_theme(_map_theme)
	var theme: Dictionary = MAP_THEME_SCRIPT.get_theme(_map_theme)
	_time_of_day = float(theme.get("time_of_day", 0.63))


func is_in_vehicle() -> bool:
	return _in_vehicle


func _build_game() -> void:
	_environment = ENVIRONMENT_SCENE.instantiate()
	add_child(_environment)

	_player = PLAYER_SCENE.instantiate()
	add_child(_player)

	_fx = FX_SCENE.instantiate()
	add_child(_fx)

	_audio = AUDIO_SCRIPT.new()
	_audio.name = "Audio"
	add_child(_audio)

	_hud = HUD_SCENE.instantiate()
	add_child(_hud)

	_enemy_system = ENEMIES_SCENE.instantiate()
	add_child(_enemy_system)

	_capture_zones = CAPTURE_ZONES_SCENE.instantiate()
	add_child(_capture_zones)

	_game_mode = GAME_MODE_SCRIPT.new()
	_game_mode.name = "GameMode"
	add_child(_game_mode)

	_animator = ANIMATOR_SCRIPT.new()
	_animator.name = "WeaponAnimator"
	add_child(_animator)
	_animator.setup(_player, _player.get_node("Camera3D/WeaponViewmodel"), _player.get_camera())

	_network_manager = NETWORK_MANAGER_SCRIPT.new()
	_network_manager.name = "NetworkManager"
	add_child(_network_manager)

	_entity_sync = ENTITY_SYNC_SCRIPT.new()
	_entity_sync.name = "EntitySync"
	add_child(_entity_sync)

	_entity_broadcaster = ENTITY_BROADCASTER_SCRIPT.new()
	_entity_broadcaster.name = "EntityBroadcaster"
	add_child(_entity_broadcaster)

	_remote_entity_factory = REMOTE_ENTITY_FACTORY_SCRIPT.new()
	_remote_entity_factory.name = "RemoteEntityFactory"
	add_child(_remote_entity_factory)

	_session_entity_access = SESSION_ENTITY_ACCESS_SCRIPT.new()
	_session_entity_access.name = "SessionEntityAccess"
	add_child(_session_entity_access)

	_save_manager = SAVE_MANAGER_SCRIPT.new()
	_save_manager.name = "SaveManager"
	add_child(_save_manager)

	_performance_monitor = PERFORMANCE_MONITOR_SCRIPT.new()
	_performance_monitor.name = "PerformanceMonitor"
	add_child(_performance_monitor)

	_vehicle = JEEP_SCENE.instantiate()
	_vehicle.name = "Jeep"
	add_child(_vehicle)
	_vehicle.destroyed.connect(_on_vehicle_destroyed.bind(_vehicle))

	_tank = TANK_SCENE.instantiate()
	_tank.name = "Tank"
	add_child(_tank)
	_tank.destroyed.connect(_on_vehicle_destroyed.bind(_tank))

	_jeep_engine = VEHICLE_ENGINE_SCRIPT.new()
	_jeep_engine.name = "JeepEngine"
	_vehicle.add_child(_jeep_engine)
	_jeep_engine.setup(_vehicle)

	_tank_engine = VEHICLE_ENGINE_SCRIPT.new()
	_tank_engine.name = "TankEngine"
	_tank.add_child(_tank_engine)
	_tank_engine.setup(_tank)

	_ifv = IFV_SCENE.instantiate()
	_ifv.name = "IFV"
	add_child(_ifv)
	_ifv.destroyed.connect(_on_vehicle_destroyed.bind(_ifv))

	_ifv_engine = VEHICLE_ENGINE_SCRIPT.new()
	_ifv_engine.name = "IFVEngine"
	_ifv.add_child(_ifv_engine)
	_ifv_engine.setup(_ifv)

	_ambient_audio = AMBIENT_AUDIO_SCRIPT.new()
	_ambient_audio.name = "AmbientAudio"
	add_child(_ambient_audio)

	_wire_signals()
	_setup_world()


func _wire_signals() -> void:
	var camera: Camera3D = _player.get_camera()
	_fx.set_camera(camera)
	_audio.set_camera(camera)

	_player.health_changed.connect(_on_health_changed)
	_player.player_died.connect(_on_player_died)
	_player.player_respawned.connect(_on_player_respawned)
	_player.weapon_fired.connect(_on_player_weapon_fired)
	_player.footstep.connect(_on_footstep)
	_player.muzzle_flash.connect(_on_muzzle_flash)

	var projectiles: Node = _player.get_node("Projectiles")
	projectiles.hit_target.connect(_on_hit_target)
	projectiles.explosion_detonated.connect(_on_explosion_detonated)

	var weapons: Node = _player.get_node("Camera3D/WeaponViewmodel")
	weapons.ammo_changed.connect(_on_ammo_changed)
	weapons.weapon_switched.connect(_on_weapon_switched)
	weapons.reload_started.connect(_on_reload_started)
	weapons.reload_finished.connect(_on_reload_finished)

	_enemy_system.enemy_killed.connect(_on_enemy_killed)
	_enemy_system.enemy_fired.connect(_on_enemy_fired)
	_enemy_system.enemy_hit_player.connect(_on_enemy_hit_player)
	_enemy_system.explosion_detonated.connect(_on_explosion_detonated)
	_enemy_system.support_requested.connect(_on_support_requested)
	_tank.cannon_fired.connect(_on_tank_cannon_fired)
	_ifv.cannon_fired.connect(_on_ifv_cannon_fired)
	_capture_zones.zone_captured.connect(_on_zone_captured)
	_capture_zones.capture_progress.connect(_on_capture_changed)
	_game_mode.objective_changed.connect(_on_objective_changed)
	_game_mode.game_over.connect(_on_game_over)
	_game_mode.sector_advanced.connect(_on_sector_advanced)

	_hud.restart_requested.connect(_on_restart_requested)
	_hud.quality_changed.connect(_on_quality_changed)
	_hud.sensitivity_changed.connect(_on_sensitivity_changed)
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.start_game_requested.connect(_on_start_game_requested)
	_hud.deploy_requested.connect(_on_deploy_requested)
	_hud.quit_requested.connect(_on_quit_requested)
	_hud.host_session_requested.connect(_on_host_session_requested)
	_hud.join_session_requested.connect(_on_join_session_requested)
	_hud.leave_session_requested.connect(_on_leave_session_requested)
	_network_manager.session_started.connect(_on_network_session_event)
	_network_manager.session_joined.connect(_on_network_session_event)
	_network_manager.session_left.connect(_on_network_session_event)
	_network_manager.connection_failed.connect(_on_network_connection_event)
	_network_manager.server_disconnected.connect(_on_network_connection_event)
	_network_manager.peer_connected.connect(_on_network_peer_event)
	_network_manager.peer_disconnected.connect(_on_network_peer_event)
	_network_manager.packet_received.connect(_on_network_packet_received)
	_network_manager.network_state_changed.connect(_on_network_state_changed)


func _setup_world() -> void:
	var spawn_points: Array = _environment.get_spawn_points()
	_spawn_points = spawn_points
	var nav_points: Array = _environment.get_nav_points()
	var cover_points: Array = _environment.get_cover_points()
	var spawn := Vector3(-30.0, 2.0, -8.0)
	_player.spawn(spawn, 0.0)

	_enemy_system.setup(_player, spawn_points, nav_points, cover_points)

	var zone_data: Array = []
	for entry: Dictionary in ZONE_DATA:
		var zone_entry: Dictionary = entry.duplicate()
		var pos: Vector3 = entry["position"]
		var ground_y: float = _environment.terrain_height_at(pos)
		zone_entry["position"] = Vector3(pos.x, ground_y, pos.z)
		zone_data.append(zone_entry)
	_capture_zones.setup(zone_data)

	_game_mode.setup(_player, _enemy_system, _capture_zones)
	_enemy_system.set_defense_point(_game_mode.get_current_sector_position(), 8.0)
	_enemy_system.set_deploy_points(_game_mode.get_deploy_points())
	_enemy_system.spawn_teams()
	_hud.set_quality_menu(_quality)
	_spawn_vehicle()
	_spawn_tank()
	_spawn_ifv()
	_enemy_system.set_capture_zones(_capture_zones)
	_enemy_system.set_vehicle(_vehicle)
	_entity_sync.setup(_network_manager)
	_entity_sync.register_entity("player", _player)
	_entity_sync.register_entity("jeep", _vehicle)
	_entity_sync.register_entity("tank", _tank)
	_entity_sync.register_entity("ifv", _ifv)
	_entity_broadcaster.setup(_entity_sync)
	_entity_broadcaster.add_entity_id("player")
	_entity_broadcaster.add_entity_id("jeep")
	_entity_broadcaster.add_entity_id("tank")
	_entity_broadcaster.add_entity_id("ifv")
	_remote_entity_factory.setup(_network_manager, _entity_sync)
	_session_entity_access.setup(
		_network_manager,
		_remote_entity_factory,
		"res://scripts/network/remote_player.gd",
		"res://scripts/network/remote_vehicle.gd"
	)


func _spawn_vehicle() -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return
	var spawn := Vector3(-34.0, 0.0, -6.0)
	var ground_y: float = _environment.terrain_height_at(spawn)
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var ray_params := PhysicsRayQueryParameters3D.create(
		Vector3(spawn.x, 80.0, spawn.z),
		Vector3(spawn.x, -80.0, spawn.z),
		1
	)
	ray_params.hit_back_faces = true
	var ground_hit: Dictionary = space.intersect_ray(ray_params)
	if not ground_hit.is_empty():
		ground_y = float(ground_hit.get("position", Vector3.ZERO).y)
	spawn.y = ground_y + 0.5
	_vehicle.setup(spawn, 0.0)
	_vehicle.get_camera().current = false


func _spawn_tank() -> void:
	if _tank == null or not is_instance_valid(_tank):
		return
	var spawn := Vector3(-26.0, 0.0, 4.0)
	var ground_y: float = _environment.terrain_height_at(spawn)
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var ray_params := PhysicsRayQueryParameters3D.create(
		Vector3(spawn.x, 80.0, spawn.z),
		Vector3(spawn.x, -80.0, spawn.z),
		1
	)
	ray_params.hit_back_faces = true
	var ground_hit: Dictionary = space.intersect_ray(ray_params)
	if not ground_hit.is_empty():
		ground_y = float(ground_hit.get("position", Vector3.ZERO).y)
	spawn.y = ground_y + 0.8
	_tank.setup(spawn, 0.0)
	_tank.get_camera().current = false


func _spawn_ifv() -> void:
	if _ifv == null or not is_instance_valid(_ifv):
		return
	var spawn := Vector3(-42.0, 0.0, 4.0)
	var ground_y: float = _environment.terrain_height_at(spawn)
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var ray_params := PhysicsRayQueryParameters3D.create(
		Vector3(spawn.x, 80.0, spawn.z),
		Vector3(spawn.x, -80.0, spawn.z),
		1
	)
	ray_params.hit_back_faces = true
	var ground_hit: Dictionary = space.intersect_ray(ray_params)
	if not ground_hit.is_empty():
		ground_y = float(ground_hit.get("position", Vector3.ZERO).y)
	spawn.y = ground_y + 0.8
	_ifv.setup(spawn, 0.0)
	_ifv.get_camera().current = false


func _handle_vehicle_interact() -> void:
	if _respawn_timer > 0.0:
		return
	var candidates: Array = []
	if _vehicle != null and is_instance_valid(_vehicle) and _vehicle.is_alive():
		candidates.append(_vehicle)
	if _tank != null and is_instance_valid(_tank) and _tank.is_alive():
		candidates.append(_tank)
	if _ifv != null and is_instance_valid(_ifv) and _ifv.is_alive():
		candidates.append(_ifv)
	if candidates.is_empty():
		return
	if Input.is_action_just_pressed("interact"):
		var nearest = null
		var nearest_dist := INF
		for candidate in candidates:
			var dist: float = _player.global_position.distance_to(candidate.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = candidate
		if nearest != null and nearest_dist < 3.5:
			_enter_vehicle(nearest)


func _handle_vehicle_driving(delta: float) -> void:
	var throttle := 0.0
	if Input.is_action_pressed("move_forward"):
		throttle += 1.0
	if Input.is_action_pressed("move_backward"):
		throttle -= 1.0
	var steer := 0.0
	if Input.is_action_pressed("move_left"):
		steer -= 1.0
	if Input.is_action_pressed("move_right"):
		steer += 1.0
	var brake := Input.is_action_pressed("jump") or Input.is_action_pressed("sprint")
	if _current_vehicle != null and is_instance_valid(_current_vehicle):
		_current_vehicle.drive(throttle, steer, brake, delta)
	if _current_vehicle == _tank and Input.is_action_pressed("fire"):
		var tank_camera: Camera3D = _tank.get_camera()
		_tank.try_fire_cannon(tank_camera.global_position, -tank_camera.global_transform.basis.z)
	if _current_vehicle == _ifv and Input.is_action_pressed("fire"):
		var ifv_camera: Camera3D = _ifv.get_camera()
		_ifv.try_fire_cannon(ifv_camera.global_position, -ifv_camera.global_transform.basis.z)
	if Input.is_action_just_pressed("interact"):
		_exit_vehicle()


func enter_vehicle(vehicle) -> void:
	_enter_vehicle(vehicle)


func exit_vehicle() -> void:
	_exit_vehicle()


func _enter_vehicle(vehicle) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.is_alive() or _in_vehicle:
		return
	_current_vehicle = vehicle
	_in_vehicle = true
	_player.set_input_enabled(false)
	_current_vehicle.get_camera().current = true
	_player.get_camera().current = false
	var vehicle_name := "IFV" if vehicle == _ifv else ("坦克" if vehicle == _tank else "吉普")
	_hud.show_message("%s驾驶中：W/S 油门/刹车，A/D 转向，E 下车" % vehicle_name, Color(0.5, 0.85, 1.0))


func _exit_vehicle() -> void:
	if not _in_vehicle:
		return
	if _current_vehicle != null and is_instance_valid(_current_vehicle):
		_player.global_position = _current_vehicle.get_seat_position()
	_eject_from_vehicle(true)
	_hud.show_message("已下车", Color(0.8, 0.95, 1.0))


func _eject_from_vehicle(restore_input: bool) -> void:
	if _current_vehicle == null or not is_instance_valid(_current_vehicle) or not _in_vehicle:
		return
	_in_vehicle = false
	_current_vehicle.get_camera().current = false
	_player.get_camera().current = true
	_current_vehicle = null
	if restore_input:
		_player.set_input_enabled(true)


func _on_vehicle_destroyed(vehicle) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	_fx.explosion(vehicle.global_position, 4.0)
	_audio.play_explosion(_player.global_position.distance_to(vehicle.global_position))
	if _in_vehicle and _current_vehicle == vehicle:
		_eject_from_vehicle(false)
		_player.take_damage(35.0)


func _on_tank_cannon_fired(origin: Vector3, direction: Vector3) -> void:
	if _player == null:
		return
	var projectiles: Node = _player.get_node("Projectiles")
	projectiles.fire_projectile(origin, direction, "rocket_launcher", "rocket", _player)
	_audio.play_shot("rocket_launcher", 0.0)
	_fx.muzzle_flash(origin, direction.normalized(), "rocket_launcher")


func _on_ifv_cannon_fired(origin: Vector3, direction: Vector3) -> void:
	if _player == null:
		return
	var projectiles: Node = _player.get_node("Projectiles")
	projectiles.fire_hitscan(origin, direction, 28.0, "assault_rifle", _player)
	_audio.play_shot("assault_rifle", 0.0)
	_fx.muzzle_flash(origin, direction.normalized(), "assault_rifle")


func _ray_endpoint(origin: Vector3, direction: Vector3, max_range: float) -> Vector3:
	var forward := direction.normalized()
	var params := PhysicsRayQueryParameters3D.create(origin, origin + forward * max_range, 3)
	var result := get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return origin + forward * max_range
	return result.get("position", origin + forward * max_range)


func _on_player_weapon_fired(origin: Vector3, direction: Vector3, weapon_type: String) -> void:
	_audio.play_shot(weapon_type, 0.0)
	if weapon_type == "rocket_launcher" or weapon_type == "grenade":
		return
	var end := _ray_endpoint(origin, direction, 400.0)
	_fx.tracer(origin, end, Color(1.0, 0.88, 0.5, 0.85))
	var camera: Camera3D = _player.get_camera()
	var right: Vector3 = camera.global_transform.basis.x
	var up: Vector3 = camera.global_transform.basis.y
	_fx.casing(camera.global_position - up * 0.18 + right * 0.16, right)


func _on_muzzle_flash(position: Vector3, direction: Vector3, weapon_type: String) -> void:
	_fx.muzzle_flash(position, direction, weapon_type)


func _on_footstep(volume: float) -> void:
	_audio.play_footstep(volume)


func _on_hit_target(target: Object, damage: float, point: Vector3, normal: Vector3) -> void:
	if target != null and target.is_in_group("enemy_ai"):
		_enemy_system.damage_enemy(target, damage, point)
		_hud.show_hit()
		_audio.play_impact(0.85)
		_show_damage_number(damage, point)
	elif target != null and target.is_in_group("vehicle"):
		target.take_damage(damage)
		_audio.play_impact(0.75)
		_show_damage_number(damage, point)
	_fx.impact(point, normal)


func _show_damage_number(damage: float, point: Vector3) -> void:
	if _hud == null or not _hud.has_method("show_damage_number") or _player == null:
		return
	var camera: Camera3D = _player.get_camera()
	if camera == null:
		return
	var screen_position: Vector2 = camera.unproject_position(point)
	_hud.show_damage_number(damage, screen_position)


func _on_enemy_fired(origin: Vector3, direction: Vector3, weapon_type: String, team: String) -> void:
	var forward := direction.normalized()
	var end := _ray_endpoint(origin, forward, 220.0)
	var tracer_color := Color(0.35, 0.75, 1.0, 0.8) if team == "blue" else Color(1.0, 0.55, 0.18, 0.8)
	_fx.tracer(origin, end, tracer_color)
	_fx.muzzle_flash(origin, forward, weapon_type)
	if _player != null and is_instance_valid(_player) and _player.get_camera() != null:
		_audio.play_enemy_shot(_player.get_camera().global_position.distance_to(origin))


func _on_enemy_hit_player(point: Vector3, normal: Vector3) -> void:
	_fx.impact(point, normal)
	_audio.play_impact(0.9)


func _on_support_requested(position: Vector3, team: String) -> void:
	if _hud != null and is_instance_valid(_hud):
		var label := "红方" if team == "red" else "蓝方"
		_hud.show_message("%s呼叫支援" % label, Color(1.0, 0.6, 0.3) if team == "red" else Color(0.4, 0.7, 1.0))
	if _audio != null and is_instance_valid(_audio):
		_audio.play_radio_chatter(0.7)


func _on_explosion_detonated(position: Vector3, radius: float, power: float, type: String, source: String) -> void:
	_fx.explosion(position, radius)
	if _player != null and is_instance_valid(_player):
		var distance: float = _player.global_position.distance_to(position)
		_audio.play_explosion(distance)
		if distance <= radius:
			var falloff: float = 1.0 - distance / maxf(radius, 0.01)
			_player.take_damage(maxf(1.0, power * falloff * 0.9))
	var friendly_blue := source == "player" or source == "blue"
	var friendly_red := source == "red"
	for enemy in get_tree().get_nodes_in_group("enemy_ai"):
		if not is_instance_valid(enemy):
			continue
		var enemy_team: String = enemy.team
		if friendly_blue and enemy_team == "blue":
			continue
		if friendly_red and enemy_team == "red":
			continue
		var enemy_distance: float = enemy.global_position.distance_to(position)
		if enemy_distance <= radius:
			var enemy_falloff: float = 1.0 - enemy_distance / maxf(radius, 0.01)
			_enemy_system.damage_enemy(enemy, maxf(1.0, power * enemy_falloff * 0.9), enemy.global_position)
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(vehicle):
			continue
		var vehicle_distance: float = vehicle.global_position.distance_to(position)
		if vehicle_distance <= radius:
			var vehicle_falloff: float = 1.0 - vehicle_distance / maxf(radius, 0.01)
			vehicle.take_damage(maxf(1.0, power * vehicle_falloff * 1.2))


func _on_ammo_changed(current: int, reserve: int, weapon_name: String) -> void:
	_hud_state["ammo"] = current
	_hud_state["reserve"] = reserve
	_hud_state["weapon_name"] = weapon_name
	_hud_state["reloading"] = false
	_hud_dirty = true


func _on_weapon_switched(name: String) -> void:
	_hud_state["weapon_name"] = name
	_hud_state["reloading"] = false
	_hud_dirty = true


func _on_reload_started() -> void:
	_hud_state["reloading"] = true
	_hud_dirty = true


func _on_reload_finished() -> void:
	_hud_state["reloading"] = false
	_hud_dirty = true


func _on_capture_changed(_zone_id: String, _team: String, _progress: float) -> void:
	_hud_dirty = true


func _on_enemy_killed(team: String, name: String) -> void:
	_game_mode.on_enemy_killed(team)
	var entry := {"text": "%s 被消灭" % name, "color": Color(0.95, 0.35, 0.25, 1.0) if team == "red" else Color(0.35, 0.75, 1.0, 1.0)}
	_kill_feed.append(entry)
	if _kill_feed.size() > 6:
		_kill_feed.pop_front()
	_audio.play_impact(0.6)
	_hud_dirty = true


func _on_zone_captured(zone_id: String, team: String) -> void:
	_hud.show_message("%s 阵地已被 %s 占领" % [zone_id, "蓝方" if team == "blue" else "红方"], Color(0.45, 0.8, 1.0) if team == "blue" else Color(1.0, 0.45, 0.35))
	_audio.play_explosion(12.0)
	_audio.play_capture_announce(team)
	_hud_dirty = true


func _on_objective_changed(text: String) -> void:
	_objective_text = text
	_hud_dirty = true


func _on_sector_advanced(sector_index: int) -> void:
	_enemy_system.set_defense_point(_game_mode.get_current_sector_position(), 8.0)
	_enemy_system.set_deploy_points(_game_mode.get_deploy_points())
	var sector_name: String = _game_mode.get_sector_name(sector_index)
	_hud.show_message("扇区突破！下一扇区：%s - 进攻资源 +30" % sector_name, Color(0.5, 1.0, 0.6))
	_hud_dirty = true


func _on_health_changed(current: int, maximum: int) -> void:
	_hud_state["health"] = current
	_hud_state["max_health"] = maximum
	_hud_dirty = true
	if current <= 0:
		_audio.play_impact(1.0)


func _on_player_died() -> void:
	_eject_from_vehicle(false)
	_game_mode.on_player_died()
	if _winner == "":
		_respawn_timer = 3.0
		_enemy_system.set_player_alive(false)
		_hud.show_message("你已阵亡，3 秒后可选择部署点", Color(1.0, 0.35, 0.3))


func _open_deployment_menu() -> void:
	if _winner != "":
		return
	if _hud == null or _player == null:
		return
	_respawn_timer = -1.0
	get_tree().paused = true
	_player.set_input_enabled(false)
	_enemy_system.set_active(false)
	if _hud.has_method("set_deployment_options"):
		var weapons: Node = _player.get_node("Camera3D/WeaponViewmodel")
		_hud.set_deployment_options(LOADOUT_SCRIPT.get_classes(), weapons.get_weapon_list(), _game_mode.get_deploy_points())
		_hud.show_deployment_menu()
		_hud.set_menu_open(true)
	_hud_dirty = true


func _on_player_respawned() -> void:
	if _winner == "":
		_enemy_system.set_player_alive(true)
		_player.set_input_enabled(true)


func _on_game_over(winner: String) -> void:
	_eject_from_vehicle(false)
	_winner = winner
	_player.set_input_enabled(false)
	_enemy_system.set_player_alive(false)
	_audio.play_round_end(winner)
	_hud.show_game_over(winner, _game_mode.get_state())


func _on_restart_requested() -> void:
	_eject_from_vehicle(false)
	_winner = ""
	_respawn_timer = 0.0
	_kill_feed.clear()
	_game_mode.restart()
	_enemy_system.set_defense_point(_game_mode.get_current_sector_position(), 8.0)
	_enemy_system.set_deploy_points(_game_mode.get_deploy_points())
	_player.respawn()
	_enemy_system.set_player_alive(true)
	_player.set_input_enabled(true)
	_hud.hide_game_over()
	_spawn_vehicle()
	_spawn_ifv()
	_hud_dirty = true


func _on_quality_changed(value: String) -> void:
	_quality = value
	_environment.set_quality(value)
	_save_profile()


func _on_sensitivity_changed(value: float) -> void:
	_sensitivity = value
	if _player != null and _player.has_method("set_sensitivity"):
		_player.set_sensitivity(value)
	_save_profile()


func get_network_manager() -> Node:
	return _network_manager


func get_entity_sync() -> Node:
	return _entity_sync


func get_entity_broadcaster() -> Node:
	return _entity_broadcaster


func get_remote_entity_factory() -> Node:
	return _remote_entity_factory


func get_session_entity_access() -> Node:
	return _session_entity_access


func get_last_network_packet() -> Array:
	return _last_network_packet.duplicate()


func get_save_manager() -> Node:
	return _save_manager


func get_performance_monitor() -> Node:
	return _performance_monitor


func get_jeep_engine() -> Node:
	return _jeep_engine


func get_tank_engine() -> Node:
	return _tank_engine


func get_ifv_engine() -> Node:
	return _ifv_engine


func get_ambient_audio() -> Node:
	return _ambient_audio


func _on_pause_toggled(value: bool) -> void:
	if _hud != null and (_hud.is_main_menu_open() or _hud.is_deployment_open()):
		return
	if _player != null:
		_player.set_input_enabled(not value)


func _enter_main_menu() -> void:
	get_tree().paused = true
	_player.set_input_enabled(false)
	_enemy_system.set_active(false)
	_apply_saved_profile()
	if _hud != null and _hud.has_method("set_deployment_options"):
		var weapons: Node = _player.get_node("Camera3D/WeaponViewmodel")
		_hud.set_deployment_options(LOADOUT_SCRIPT.get_classes(), weapons.get_weapon_list(), _game_mode.get_deploy_points())
		_hud.show_main_menu()
	if _hud != null and _hud.has_method("set_network_state"):
		_hud.set_network_state(_network_manager.get_network_state())


func _apply_saved_profile() -> void:
	if _save_manager == null:
		return
	var profile: Dictionary = _save_manager.load_profile()
	if profile.has("quality"):
		_quality = str(profile.get("quality", _quality))
		_environment.set_quality(_quality)
		_hud.set_quality_menu(_quality)
	if profile.has("sensitivity"):
		_sensitivity = float(profile.get("sensitivity", 1.0))
		_player.set_sensitivity(_sensitivity)
	if profile.has("loadout"):
		var loadout: Variant = profile.get("loadout")
		if loadout is Dictionary:
			_player.apply_loadout(loadout)


func _save_profile() -> void:
	if _save_manager == null:
		return
	var profile := {
		"quality": _quality,
		"sensitivity": _sensitivity,
		"loadout": _player.get_loadout(),
	}
	_save_manager.save_profile(profile)


func _on_start_game_requested() -> void:
	if _hud == null:
		return
	_hud.hide_main_menu()
	_hud.show_deployment_menu()


func _on_deploy_requested(loadout: Dictionary, spawn_index: int) -> void:
	var deploy_points: Array = _game_mode.get_deploy_points()
	var spawn := Vector3(0.0, 2.0, 20.0)
	if deploy_points.size() > 0:
		spawn = deploy_points[clampi(spawn_index, 0, deploy_points.size() - 1)]
	spawn.y = _environment.terrain_height_at(spawn) + 0.5
	_player.apply_loadout(loadout)
	_player.spawn(spawn, 0.0)
	_save_profile()
	_enemy_system.set_active(true)
	_enemy_system.set_player_alive(true)
	_player.set_input_enabled(true)
	_hud.hide_deployment_menu()
	_hud.set_menu_open(false)
	_hud_dirty = true
	get_tree().paused = false
	_hud.show_message("部署完成 - %s" % _game_mode.get_state().get("sector_name", ""), Color(0.7, 1.0, 0.8))


func _on_quit_requested() -> void:
	get_tree().quit()


func _on_host_session_requested(session_name: String) -> void:
	if _network_manager.host_session(session_name):
		_entity_broadcaster.set_enabled(true)
		_session_entity_access.enable()
		_hud.set_network_state(_network_manager.get_network_state())
		_hud.show_message("已创建房间：%s" % session_name, Color(0.5, 0.9, 1.0))
	else:
		_hud.show_message("创建房间失败", Color(1.0, 0.5, 0.4))


func _on_join_session_requested(server_address: String) -> void:
	if _network_manager.join_session(server_address):
		_hud.set_network_state(_network_manager.get_network_state())
		_hud.show_message("正在加入 %s" % server_address, Color(0.5, 0.9, 1.0))
	else:
		_hud.show_message("加入房间失败", Color(1.0, 0.5, 0.4))


func _on_leave_session_requested() -> void:
	_network_manager.leave_session()
	_entity_broadcaster.set_enabled(false)
	_session_entity_access.disable()
	_hud.set_network_state(_network_manager.get_network_state())
	_hud.show_message("已离开房间", Color(0.8, 0.95, 1.0))


func _on_network_session_event(_value: Variant = null, _value2: Variant = null) -> void:
	_on_network_state_changed()


func _on_network_connection_event() -> void:
	_on_network_state_changed()


func _on_network_peer_event(peer_id: int) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.show_message("玩家 %d 加入/离开房间" % peer_id, Color(0.6, 0.9, 1.0))
	_on_network_state_changed()


func _on_network_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	_last_network_packet = [peer_id, packet.duplicate()]


func _on_network_state_changed() -> void:
	if _hud != null and _hud.has_method("set_network_state"):
		_hud.set_network_state(_network_manager.get_network_state())


func _setup_input_actions() -> void:
	var actions := {
		"move_forward": [KEY_W],
		"move_backward": [KEY_S],
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL],
		"fire": [MOUSE_BUTTON_LEFT],
		"aim": [MOUSE_BUTTON_RIGHT],
		"reload": [KEY_R],
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
		"weapon_3": [KEY_3],
		"weapon_4": [KEY_4],
		"weapon_5": [KEY_5],
		"interact": [KEY_E],
		"inspect": [KEY_G],
		"prone": [KEY_X],
		"vault": [KEY_SPACE],
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
