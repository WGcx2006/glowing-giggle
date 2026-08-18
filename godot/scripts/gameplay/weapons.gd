extends Node3D

signal fired(origin: Vector3, direction: Vector3, weapon_type: String)
signal ammo_changed(current: int, reserve: int, weapon_name: String)
signal weapon_switched(name: String)
signal muzzle_flash(position: Vector3, direction: Vector3, weapon_type: String)
signal reload_started()
signal reload_finished()
signal dry_fire()

const WEAPON_DATA := [
	{
		"name": "AR-7 Vanguard",
		"type": "assault_rifle",
		"damage": 24.0,
		"fire_interval": 0.085,
		"spread_deg": 1.5,
		"recoil": 0.011,
		"reload_time": 1.8,
		"mag_size": 30,
		"reserve": 120,
		"auto": true,
		"range": 320.0,
		"body_color": Color(0.16, 0.18, 0.21),
		"accent_color": Color(0.78, 0.35, 0.08),
		"viewmodel_pos": Vector3(0.26, -0.25, -0.40),
		"aim_pos": Vector3(0.05, -0.15, -0.36),
		"viewmodel_rot": Vector3(0.0, 0.0, 0.0),
		"muzzle_pos": Vector3(0.0, -0.012, -0.55),
	},
	{
		"name": "SMG-9 Hive",
		"type": "smg",
		"damage": 16.0,
		"fire_interval": 0.058,
		"spread_deg": 2.2,
		"recoil": 0.007,
		"reload_time": 1.5,
		"mag_size": 32,
		"reserve": 160,
		"auto": true,
		"range": 220.0,
		"body_color": Color(0.12, 0.14, 0.16),
		"accent_color": Color(0.55, 0.75, 0.95),
		"viewmodel_pos": Vector3(0.30, -0.27, -0.34),
		"aim_pos": Vector3(0.05, -0.16, -0.32),
		"viewmodel_rot": Vector3(0.0, 0.0, 0.02),
		"muzzle_pos": Vector3(0.0, -0.005, -0.44),
	},
	{
		"name": "Mk-17 Longbow",
		"type": "dmr",
		"damage": 70.0,
		"fire_interval": 0.26,
		"spread_deg": 0.7,
		"recoil": 0.018,
		"reload_time": 2.3,
		"mag_size": 10,
		"reserve": 40,
		"auto": false,
		"range": 420.0,
		"body_color": Color(0.20, 0.19, 0.16),
		"accent_color": Color(0.42, 0.72, 0.34),
		"viewmodel_pos": Vector3(0.20, -0.22, -0.50),
		"aim_pos": Vector3(0.02, -0.14, -0.40),
		"viewmodel_rot": Vector3(0.0, 0.0, -0.02),
		"muzzle_pos": Vector3(0.0, -0.01, -0.80),
	},
	{
		"name": "M72 Hellstorm",
		"type": "rocket_launcher",
		"projectile": "rocket",
		"damage": 95.0,
		"fire_interval": 1.2,
		"spread_deg": 0.4,
		"recoil": 0.035,
		"reload_time": 3.0,
		"mag_size": 1,
		"reserve": 4,
		"auto": false,
		"range": 320.0,
		"body_color": Color(0.14, 0.17, 0.15),
		"accent_color": Color(0.82, 0.42, 0.12),
		"viewmodel_pos": Vector3(0.32, -0.30, -0.44),
		"aim_pos": Vector3(0.05, -0.18, -0.38),
		"viewmodel_rot": Vector3(0.0, 0.0, 0.0),
		"muzzle_pos": Vector3(0.0, 0.01, -0.92),
	},
	{
		"name": "M67 Frag",
		"type": "grenade",
		"projectile": "grenade",
		"damage": 80.0,
		"fire_interval": 1.4,
		"spread_deg": 0.8,
		"recoil": 0.025,
		"reload_time": 2.2,
		"mag_size": 1,
		"reserve": 4,
		"auto": false,
		"range": 90.0,
		"body_color": Color(0.16, 0.23, 0.18),
		"accent_color": Color(0.48, 0.34, 0.18),
		"viewmodel_pos": Vector3(0.22, -0.22, -0.42),
		"aim_pos": Vector3(0.04, -0.13, -0.34),
		"viewmodel_rot": Vector3(0.0, 0.0, 0.0),
		"muzzle_pos": Vector3(0.0, -0.02, -0.42),
	},
]

var _guns: Array[Node3D] = []
var _muzzles: Array[Node3D] = []
var _flash_nodes: Array[Node3D] = []
var _flash_lights: Array[Node3D] = []
var _mag_ammo: Array[int] = []
var _reserve_ammo: Array[int] = []
var _available_indices: Array[int] = []
var _current_index := 0
var _fire_cooldown := 0.0
var _reloading := false
var _reload_timer := 0.0
var _aiming := false
var _aiming_amount := 0.0
var _pending_recoil := 0.0
var _viewmodel_kick := 0.0
var _switch_animation := 1.0
var _muzzle_flash_timer := 0.0
var _player: Node3D
var _projectiles: Node3D
var _audio: AudioStreamPlayer
var _shot_streams: Dictionary = {}
var _reload_stream: AudioStreamWAV
var _dry_stream: AudioStreamWAV


func _ready() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "ProceduralAudio"
	add_child(_audio)
	for i in WEAPON_DATA.size():
		var gun := _build_gun(i)
		_guns.append(gun)
		add_child(gun)
		_muzzles.append(gun.get_node("Muzzle") as Node3D)
		_mag_ammo.append(int(WEAPON_DATA[i]["mag_size"]))
		_reserve_ammo.append(int(WEAPON_DATA[i]["reserve"]))
		gun.visible = i == 0
	_available_indices = [0, 1, 2, 3, 4]
	_build_audio_streams()


func setup(player: Node3D, camera: Camera3D, projectiles: Node3D) -> void:
	_player = player
	_projectiles = projectiles


func update(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
	_viewmodel_kick = lerpf(_viewmodel_kick, 0.0, 1.0 - exp(-delta * 16.0))
	if _switch_animation < 1.0:
		_switch_animation = minf(_switch_animation + delta * 4.0, 1.0)
	_muzzle_flash_timer -= delta
	if _muzzle_flash_timer <= 0.0:
		_muzzle_flash_timer = 0.0
		_hide_muzzle_flash()
	_update_gun_transforms(delta)


func try_fire(origin: Vector3, direction: Vector3, aiming: bool) -> bool:
	_aiming = aiming
	if _reloading or _fire_cooldown > 0.0:
		return false
	if _projectiles == null:
		return false
	var data: Dictionary = WEAPON_DATA[_current_index]
	if not data["auto"] and not Input.is_action_just_pressed("fire"):
		return false
	if _mag_ammo[_current_index] <= 0:
		dry_fire.emit()
		_play_stream(_dry_stream)
		reload()
		return false
	var spread_rad := deg_to_rad(float(data["spread_deg"]) * (0.45 if aiming else 1.0))
	var shot_dir := _apply_spread(direction, spread_rad)
	var muzzle: Node3D = _muzzles[_current_index]
	var muzzle_pos := muzzle.global_position
	if data.has("projectile"):
		_projectiles.fire_projectile(muzzle_pos, shot_dir, str(data["type"]), str(data["projectile"]), _player)
	else:
		_projectiles.fire_hitscan(muzzle_pos, shot_dir, float(data["damage"]), str(data["type"]), _player)
	_mag_ammo[_current_index] -= 1
	_fire_cooldown = float(data["fire_interval"])
	_pending_recoil = float(data["recoil"])
	_viewmodel_kick = 0.055
	_show_muzzle_flash(_current_index)
	fired.emit(muzzle_pos, shot_dir, str(data["type"]))
	muzzle_flash.emit(muzzle_pos, shot_dir, str(data["type"]))
	ammo_changed.emit(_mag_ammo[_current_index], _reserve_ammo[_current_index], str(data["name"]))
	_play_stream(_shot_streams.get(str(data["type"]), _shot_streams["assault_rifle"]) as AudioStreamWAV)
	return true


func fire(origin: Vector3, direction: Vector3, weapon_type: String) -> bool:
	var index := _index_for_type(weapon_type)
	if index < 0 or _projectiles == null:
		return false
	var data: Dictionary = WEAPON_DATA[index]
	var shot_dir := _apply_spread(direction, deg_to_rad(float(data["spread_deg"])))
	if data.has("projectile"):
		_projectiles.fire_projectile(origin, shot_dir, weapon_type, str(data["projectile"]), _player)
	else:
		_projectiles.fire_hitscan(origin, shot_dir, float(data["damage"]), weapon_type, _player)
	fired.emit(origin, shot_dir, weapon_type)
	if index == _current_index:
		_mag_ammo[index] = maxi(_mag_ammo[index] - 1, 0)
		_fire_cooldown = float(data["fire_interval"])
		_pending_recoil = float(data["recoil"])
		_viewmodel_kick = 0.05
		_show_muzzle_flash(index)
		muzzle_flash.emit(origin, shot_dir, weapon_type)
		ammo_changed.emit(_mag_ammo[index], _reserve_ammo[index], str(data["name"]))
	return true


func switch_weapon(index: int) -> bool:
	if _available_indices.is_empty():
		if index < 0 or index >= WEAPON_DATA.size():
			return false
	elif not _available_indices.has(index):
		return false
	if index == _current_index:
		return false
	_current_index = index
	_reloading = false
	_reload_timer = 0.0
	_switch_animation = 0.0
	_fire_cooldown = maxf(_fire_cooldown, 0.2)
	_pending_recoil = 0.0
	_viewmodel_kick = 0.0
	for i in _guns.size():
		_guns[i].visible = i == _current_index
	var data: Dictionary = WEAPON_DATA[_current_index]
	weapon_switched.emit(str(data["name"]))
	ammo_changed.emit(_mag_ammo[_current_index], _reserve_ammo[_current_index], str(data["name"]))
	return true


func set_available_indices(indices: Array[int]) -> void:
	var unique: Array[int] = []
	for index in indices:
		if unique.has(index) or index < 0 or index >= WEAPON_DATA.size():
			continue
		unique.append(index)
	if unique.is_empty():
		for i in WEAPON_DATA.size():
			unique.append(i)
	_available_indices = unique
	_current_index = _available_indices[0]
	for i in _guns.size():
		_guns[i].visible = i == _current_index
	_reloading = false
	_reload_timer = 0.0
	_fire_cooldown = 0.0
	_pending_recoil = 0.0
	_viewmodel_kick = 0.0
	_switch_animation = 1.0
	_hide_muzzle_flash()
	for index in _available_indices:
		_mag_ammo[index] = int(WEAPON_DATA[index]["mag_size"])
		_reserve_ammo[index] = int(WEAPON_DATA[index]["reserve"])
	var data: Dictionary = WEAPON_DATA[_current_index]
	ammo_changed.emit(_mag_ammo[_current_index], _reserve_ammo[_current_index], str(data["name"]))
	weapon_switched.emit(str(data["name"]))


func get_available_indices() -> Array[int]:
	return _available_indices


func get_weapon_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for i in WEAPON_DATA.size():
		list.append({
			"index": i,
			"name": str(WEAPON_DATA[i]["name"]),
			"type": str(WEAPON_DATA[i]["type"]),
			"damage": float(WEAPON_DATA[i]["damage"]),
		})
	return list


func reload() -> bool:
	if _reloading:
		return false
	var data: Dictionary = WEAPON_DATA[_current_index]
	if _mag_ammo[_current_index] >= int(data["mag_size"]) or _reserve_ammo[_current_index] <= 0:
		return false
	_reloading = true
	_reload_timer = float(data["reload_time"])
	reload_started.emit()
	_play_stream(_reload_stream)
	return true


func set_aiming(value: bool) -> void:
	_aiming = value


func get_aiming() -> bool:
	return _aiming


func get_current_type() -> String:
	return str(WEAPON_DATA[_current_index]["type"])


func get_ammo() -> Dictionary:
	var data: Dictionary = WEAPON_DATA[_current_index]
	var progress := 0.0
	if _reloading:
		progress = clampf(1.0 - _reload_timer / float(data["reload_time"]), 0.0, 1.0)
	return {
		"current": _mag_ammo[_current_index],
		"reserve": _reserve_ammo[_current_index],
		"name": str(data["name"]),
		"type": str(data["type"]),
		"reloading": _reloading,
		"reload_progress": progress,
	}


func consume_recoil() -> float:
	var value := _pending_recoil
	_pending_recoil = 0.0
	return value


func reset() -> void:
	var first_index: int = 0
	if not _available_indices.is_empty():
		first_index = _available_indices[0]
	_current_index = first_index
	_reloading = false
	_reload_timer = 0.0
	_fire_cooldown = 0.0
	_pending_recoil = 0.0
	_viewmodel_kick = 0.0
	_switch_animation = 1.0
	_aiming = false
	_aiming_amount = 0.0
	_muzzle_flash_timer = 0.0
	_hide_muzzle_flash()
	for i in WEAPON_DATA.size():
		_mag_ammo[i] = int(WEAPON_DATA[i]["mag_size"])
		_reserve_ammo[i] = int(WEAPON_DATA[i]["reserve"])
		_guns[i].visible = i == first_index
	var data: Dictionary = WEAPON_DATA[first_index]
	ammo_changed.emit(_mag_ammo[first_index], _reserve_ammo[first_index], str(data["name"]))
	weapon_switched.emit(str(data["name"]))


func _build_gun(index: int) -> Node3D:
	var data: Dictionary = WEAPON_DATA[index]
	var body: Color = data["body_color"]
	var accent: Color = data["accent_color"]
	var gun := Node3D.new()
	gun.name = str(data["name"])
	if index == 0:
		_build_assault_rifle(gun, body, accent)
	elif index == 1:
		_build_smg(gun, body, accent)
	elif index == 2:
		_build_dmr(gun, body, accent)
	elif index == 3:
		_build_rocket_launcher(gun, body, accent)
	else:
		_build_grenade(gun, body, accent)
	gun.position = data["viewmodel_pos"]
	gun.rotation = data["viewmodel_rot"]
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = data["muzzle_pos"]
	gun.add_child(muzzle)
	var flash := MeshInstance3D.new()
	flash.name = "MuzzleFlash"
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.035
	flash_mesh.height = 0.07
	flash.mesh = flash_mesh
	flash.visible = false
	flash.material_override = _make_flash_material()
	muzzle.add_child(flash)
	_flash_nodes.append(flash)
	var flash_light := OmniLight3D.new()
	flash_light.name = "FlashLight"
	flash_light.light_color = Color(1.0, 0.65, 0.2)
	flash_light.light_energy = 2.5
	flash_light.omni_range = 2.5
	flash_light.visible = false
	muzzle.add_child(flash_light)
	_flash_lights.append(flash_light)
	return gun


func _build_assault_rifle(root: Node3D, body: Color, accent: Color) -> void:
	var receiver := BoxMesh.new()
	receiver.size = Vector3(0.07, 0.10, 0.34)
	_add_part(root, receiver, Vector3(0.0, 0.0, -0.04), Vector3.ZERO, body)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.016
	barrel.bottom_radius = 0.016
	barrel.height = 0.34
	barrel.radial_segments = 10
	_add_part(root, barrel, Vector3(0.0, 0.012, -0.34), Vector3(deg_to_rad(90.0), 0.0, 0.0), body)
	var stock := BoxMesh.new()
	stock.size = Vector3(0.055, 0.09, 0.20)
	_add_part(root, stock, Vector3(0.0, -0.005, 0.21), Vector3(0.0, 0.0, -0.08), body)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.05, 0.13, 0.07)
	_add_part(root, grip, Vector3(0.0, -0.075, 0.09), Vector3(deg_to_rad(-18.0), 0.0, 0.0), body)
	var magazine := BoxMesh.new()
	magazine.size = Vector3(0.045, 0.16, 0.075)
	_add_part(root, magazine, Vector3(0.0, -0.095, -0.08), Vector3(deg_to_rad(18.0), 0.0, 0.0), accent)
	var sight := BoxMesh.new()
	sight.size = Vector3(0.018, 0.05, 0.09)
	_add_part(root, sight, Vector3(0.0, 0.075, -0.14), Vector3.ZERO, body)
	var handguard := BoxMesh.new()
	handguard.size = Vector3(0.065, 0.075, 0.16)
	_add_part(root, handguard, Vector3(0.0, 0.0, -0.24), Vector3.ZERO, accent)
	var muzzle_brake := CylinderMesh.new()
	muzzle_brake.top_radius = 0.022
	muzzle_brake.bottom_radius = 0.022
	muzzle_brake.height = 0.07
	muzzle_brake.radial_segments = 8
	_add_part(root, muzzle_brake, Vector3(0.0, 0.012, -0.51), Vector3(deg_to_rad(90.0), 0.0, 0.0), accent)


func _build_smg(root: Node3D, body: Color, accent: Color) -> void:
	var receiver := BoxMesh.new()
	receiver.size = Vector3(0.06, 0.09, 0.24)
	_add_part(root, receiver, Vector3(0.0, 0.0, -0.02), Vector3.ZERO, body)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.014
	barrel.bottom_radius = 0.014
	barrel.height = 0.20
	barrel.radial_segments = 8
	_add_part(root, barrel, Vector3(0.0, 0.0, -0.22), Vector3(deg_to_rad(90.0), 0.0, 0.0), body)
	var suppressor := CylinderMesh.new()
	suppressor.top_radius = 0.026
	suppressor.bottom_radius = 0.026
	suppressor.height = 0.16
	suppressor.radial_segments = 10
	_add_part(root, suppressor, Vector3(0.0, 0.0, -0.36), Vector3(deg_to_rad(90.0), 0.0, 0.0), accent)
	var stock := BoxMesh.new()
	stock.size = Vector3(0.05, 0.08, 0.12)
	_add_part(root, stock, Vector3(0.0, 0.0, 0.16), Vector3(0.0, 0.0, -0.06), body)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.045, 0.11, 0.06)
	_add_part(root, grip, Vector3(0.0, -0.07, 0.07), Vector3(deg_to_rad(-15.0), 0.0, 0.0), body)
	var magazine := BoxMesh.new()
	magazine.size = Vector3(0.04, 0.15, 0.06)
	_add_part(root, magazine, Vector3(0.0, -0.095, -0.05), Vector3(deg_to_rad(28.0), 0.0, 0.0), accent)
	var sight := BoxMesh.new()
	sight.size = Vector3(0.016, 0.045, 0.07)
	_add_part(root, sight, Vector3(0.0, 0.07, -0.10), Vector3.ZERO, body)
	var foregrip := BoxMesh.new()
	foregrip.size = Vector3(0.04, 0.06, 0.05)
	_add_part(root, foregrip, Vector3(0.0, -0.06, -0.16), Vector3.ZERO, accent)


func _build_dmr(root: Node3D, body: Color, accent: Color) -> void:
	var receiver := BoxMesh.new()
	receiver.size = Vector3(0.07, 0.10, 0.40)
	_add_part(root, receiver, Vector3(0.0, 0.0, -0.12), Vector3.ZERO, body)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.016
	barrel.bottom_radius = 0.016
	barrel.height = 0.46
	barrel.radial_segments = 10
	_add_part(root, barrel, Vector3(0.0, 0.0, -0.45), Vector3(deg_to_rad(90.0), 0.0, 0.0), body)
	var scope := CylinderMesh.new()
	scope.top_radius = 0.028
	scope.bottom_radius = 0.028
	scope.height = 0.22
	scope.radial_segments = 12
	_add_part(root, scope, Vector3(0.0, 0.08, -0.12), Vector3(0.0, 0.0, deg_to_rad(90.0)), accent)
	var stock := BoxMesh.new()
	stock.size = Vector3(0.06, 0.10, 0.24)
	_add_part(root, stock, Vector3(0.0, 0.0, 0.25), Vector3(0.0, 0.0, -0.10), body)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.05, 0.14, 0.07)
	_add_part(root, grip, Vector3(0.0, -0.08, 0.10), Vector3(deg_to_rad(-14.0), 0.0, 0.0), body)
	var magazine := BoxMesh.new()
	magazine.size = Vector3(0.05, 0.17, 0.08)
	_add_part(root, magazine, Vector3(0.0, -0.10, -0.14), Vector3(deg_to_rad(12.0), 0.0, 0.0), accent)
	var bipod_left := BoxMesh.new()
	bipod_left.size = Vector3(0.02, 0.16, 0.04)
	_add_part(root, bipod_left, Vector3(-0.025, -0.13, -0.40), Vector3(0.0, 0.0, deg_to_rad(8.0)), body)
	var bipod_right := BoxMesh.new()
	bipod_right.size = Vector3(0.02, 0.16, 0.04)
	_add_part(root, bipod_right, Vector3(0.025, -0.13, -0.40), Vector3(0.0, 0.0, deg_to_rad(-8.0)), body)


func _build_rocket_launcher(root: Node3D, body: Color, accent: Color) -> void:
	var tube := CylinderMesh.new()
	tube.top_radius = 0.045
	tube.bottom_radius = 0.045
	tube.height = 0.76
	tube.radial_segments = 10
	_add_part(root, tube, Vector3(0.0, 0.01, -0.36), Vector3(deg_to_rad(90.0), 0.0, 0.0), body)
	var muzzle_ring := CylinderMesh.new()
	muzzle_ring.top_radius = 0.055
	muzzle_ring.bottom_radius = 0.055
	muzzle_ring.height = 0.10
	muzzle_ring.radial_segments = 10
	_add_part(root, muzzle_ring, Vector3(0.0, 0.01, -0.76), Vector3(deg_to_rad(90.0), 0.0, 0.0), accent)
	var stock := BoxMesh.new()
	stock.size = Vector3(0.09, 0.12, 0.24)
	_add_part(root, stock, Vector3(0.0, -0.02, 0.24), Vector3(0.0, 0.0, -0.08), body)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.08, 0.16, 0.10)
	_add_part(root, grip, Vector3(0.0, -0.10, 0.10), Vector3(deg_to_rad(-20.0), 0.0, 0.0), body)
	var sight := BoxMesh.new()
	sight.size = Vector3(0.02, 0.06, 0.10)
	_add_part(root, sight, Vector3(0.0, 0.09, -0.22), Vector3.ZERO, accent)
	var foregrip := BoxMesh.new()
	foregrip.size = Vector3(0.06, 0.08, 0.06)
	_add_part(root, foregrip, Vector3(0.0, -0.07, -0.24), Vector3.ZERO, accent)


func _build_grenade(root: Node3D, body: Color, accent: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.085
	sphere.height = 0.17
	sphere.radial_segments = 10
	sphere.rings = 8
	_add_part(root, sphere, Vector3(0.0, -0.02, -0.30), Vector3.ZERO, body)
	var handle := BoxMesh.new()
	handle.size = Vector3(0.05, 0.10, 0.05)
	_add_part(root, handle, Vector3(0.0, 0.07, -0.30), Vector3.ZERO, accent)
	var lever := CylinderMesh.new()
	lever.top_radius = 0.012
	lever.bottom_radius = 0.012
	lever.height = 0.08
	lever.radial_segments = 6
	_add_part(root, lever, Vector3(0.0, 0.13, -0.30), Vector3(deg_to_rad(90.0), 0.0, 0.0), accent)


func _add_part(parent: Node3D, mesh: Mesh, position: Vector3, rotation: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	part.material_override = _make_material(color)
	parent.add_child(part)
	return part


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.55
	material.roughness = 0.42
	return material


func _make_flash_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.75, 0.25)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.18)
	material.emission_energy_multiplier = 4.0
	return material


func _build_audio_streams() -> void:
	_shot_streams = {
		"assault_rifle": _make_wav(0.09, 165.0, 0.85),
		"smg": _make_wav(0.055, 220.0, 0.9),
		"dmr": _make_wav(0.14, 120.0, 0.7),
		"rocket_launcher": _make_wav(0.22, 90.0, 0.55),
		"grenade": _make_wav(0.12, 150.0, 0.7),
	}
	_reload_stream = _make_wav(0.16, 520.0, 0.45)
	_dry_stream = _make_wav(0.07, 340.0, 0.55)


func _make_wav(duration: float, frequency: float, noise_amount: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(duration * float(sample_rate))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(sample_rate)
		var envelope := pow(1.0 - t / duration, 2.0)
		var tone := sin(t * TAU * frequency)
		var noise := randf_range(-1.0, 1.0) * noise_amount
		var sample_value := (tone * (1.0 - noise_amount) + noise) * envelope
		var sample_int := int(clampf(sample_value, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, sample_int)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _play_stream(stream: AudioStreamWAV) -> void:
	if _audio == null or stream == null:
		return
	_audio.stream = stream
	_audio.play()


func _apply_spread(direction: Vector3, spread_rad: float) -> Vector3:
	var forward := direction.normalized()
	if spread_rad <= 0.0:
		return forward
	var side := forward.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(forward).normalized()
	var offset := (side * randf_range(-1.0, 1.0) + up * randf_range(-1.0, 1.0)) * tan(spread_rad)
	return (forward + offset).normalized()


func _index_for_type(weapon_type: String) -> int:
	for i in WEAPON_DATA.size():
		if str(WEAPON_DATA[i]["type"]) == weapon_type:
			return i
	return -1


func _finish_reload() -> void:
	var data: Dictionary = WEAPON_DATA[_current_index]
	var needed := int(data["mag_size"]) - _mag_ammo[_current_index]
	var taken := mini(needed, _reserve_ammo[_current_index])
	_mag_ammo[_current_index] += taken
	_reserve_ammo[_current_index] -= taken
	_reloading = false
	ammo_changed.emit(_mag_ammo[_current_index], _reserve_ammo[_current_index], str(data["name"]))
	reload_finished.emit()


func _show_muzzle_flash(index: int) -> void:
	if index < _flash_nodes.size():
		_flash_nodes[index].visible = true
		_flash_lights[index].visible = true
	_muzzle_flash_timer = 0.045


func _hide_muzzle_flash() -> void:
	for node in _flash_nodes:
		node.visible = false
	for node in _flash_lights:
		node.visible = false


func _update_gun_transforms(delta: float) -> void:
	_aiming_amount = lerpf(_aiming_amount, 1.0 if _aiming else 0.0, 1.0 - exp(-delta * 12.0))
	for i in _guns.size():
		var gun := _guns[i]
		if not gun.visible:
			continue
		var data: Dictionary = WEAPON_DATA[i]
		var base_pos: Vector3 = data["viewmodel_pos"]
		var aim_pos: Vector3 = data["aim_pos"]
		var target_pos := base_pos.lerp(aim_pos, _aiming_amount)
		var reload_y := 0.0
		if _reloading and i == _current_index:
			reload_y = -0.10
		var switch_y := 0.0
		if _switch_animation < 1.0:
			switch_y = -sin(_switch_animation * PI) * 0.12
		gun.position = Vector3(
			target_pos.x,
			target_pos.y - _viewmodel_kick + reload_y + switch_y,
			target_pos.z + _viewmodel_kick * 0.6
		)
		var base_rot: Vector3 = data["viewmodel_rot"]
		gun.rotation = Vector3(base_rot.x + _viewmodel_kick * 2.4, base_rot.y, base_rot.z)
