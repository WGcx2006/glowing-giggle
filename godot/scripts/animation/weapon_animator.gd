extends Node3D

## M3a first-person weapon animation module.
## This animator owns the WeaponViewmodel root transform only. Child gun
## transforms are owned by weapons.gd and are intentionally left untouched.

const INSPECT_DURATION := 2.2

const IDLE_SWAY_FREQUENCY := 1.35
const IDLE_POS_AMPLITUDE := Vector3(0.005, 0.0032, 0.003)
const IDLE_ROT_AMPLITUDE := Vector3(0.0018, 0.0024, 0.0016)

const RELOAD_DIP := Vector3(0.0, -0.055, 0.04)
const RELOAD_PITCH := 0.035

const SPRINT_OFFSET := Vector3(0.0, -0.038, -0.024)
const SPRINT_PITCH := 0.026
const SPRINT_BOB_POS := Vector3(0.004, 0.006, 0.0)
const SPRINT_BOB_ROLL := 0.006

const INSPECT_OFFSET := Vector3(0.13, -0.16, 0.10)
const INSPECT_ROTATION := Vector3(0.32, 0.16, -0.23) # pitch/yaw/roll radians
const INSPECT_WOBBLE := 0.035

const VAULT_OFFSET := Vector3(0.0, -0.10, -0.16)
const VAULT_ROTATION := Vector3(0.18, 0.0, -0.10)
const CLIMB_OFFSET := Vector3(0.05, 0.10, -0.08)
const CLIMB_ROTATION := Vector3(-0.22, 0.0, 0.08)

var _player: Node3D
var _weapons: Node3D
var _camera: Camera3D
var _base_position := Vector3.ZERO
var _base_rotation := Vector3.ZERO
var _base_captured := false

var _sway_time := 0.0
var _sprint_phase := 0.0
var _moving_amount := 0.0
var _reload_amount := 0.0
var _sprint_amount := 0.0
var _aim_amount := 0.0
var _crouch_amount := 0.0
var _prone_amount := 0.0
var _weapon_sway_scale := 1.0

var _inspect_time := 0.0
var _inspect_active := false
var _inspect_progress := 0.0
var _vault_amount: float = 0.0
var _climb_amount: float = 0.0
var _vault_progress: float = 0.0
var _climb_progress: float = 0.0
var _pose_name: String = "idle"
var _current_offset := Vector3.ZERO


func setup(player: Node3D, weapons: Node, camera: Camera3D) -> void:
	if _base_captured and is_instance_valid(_weapons):
		_weapons.position = _base_position
		_weapons.rotation = _base_rotation
	_player = player
	_camera = camera
	_weapons = weapons as Node3D
	_base_captured = false
	if is_instance_valid(_weapons):
		_base_position = _weapons.position
		_base_rotation = _weapons.rotation
		_base_captured = true
	_reset_pose_state()


func update(delta: float) -> void:
	if _player == null or _weapons == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_weapons):
		return
	if _camera != null and not is_instance_valid(_camera):
		return
	if not _base_captured:
		_capture_base()
	_sway_time += delta * TAU * IDLE_SWAY_FREQUENCY
	_read_state(delta)
	_advance_inspect(delta)
	_set_pose_priority()
	_apply_pose()


func play_inspect() -> void:
	if _weapons == null or not is_instance_valid(_weapons):
		return
	_inspect_time = 0.0
	_inspect_active = true
	_inspect_progress = 0.0
	_pose_name = "inspect"


## sway_offset is the total position offset applied to the viewmodel root.
func get_pose_snapshot() -> Dictionary:
	return {
		"inspect_progress": _inspect_progress,
		"vault_progress": _vault_progress,
		"climb_progress": _climb_progress,
		"sway_offset": _current_offset,
		"pose_name": _pose_name,
	}


func _capture_base() -> void:
	if _weapons != null and is_instance_valid(_weapons):
		_base_position = _weapons.position
		_base_rotation = _weapons.rotation
		_base_captured = true


func _reset_pose_state() -> void:
	_sway_time = 0.0
	_sprint_phase = 0.0
	_moving_amount = 0.0
	_reload_amount = 0.0
	_sprint_amount = 0.0
	_aim_amount = 0.0
	_crouch_amount = 0.0
	_prone_amount = 0.0
	_weapon_sway_scale = 1.0
	_inspect_time = 0.0
	_inspect_active = false
	_inspect_progress = 0.0
	_vault_amount = 0.0
	_climb_amount = 0.0
	_vault_progress = 0.0
	_climb_progress = 0.0
	_pose_name = "idle"
	_current_offset = Vector3.ZERO


func _read_state(delta: float) -> void:
	var player_state: Dictionary = {}
	var ammo_state: Dictionary = {}
	if _player.has_method("get_state"):
		player_state = _player.get_state()
	if _weapons.has_method("get_ammo"):
		ammo_state = _weapons.get_ammo()
	var weapon_name := str(ammo_state.get("name", ""))
	_weapon_sway_scale = _sway_scale_for_name(weapon_name)
	_moving_amount = _exp_blend(_moving_amount, bool(player_state.get("moving", false)), delta, 9.0)
	_reload_amount = _exp_blend(_reload_amount, bool(ammo_state.get("reloading", false)), delta, 9.0)
	_sprint_amount = _exp_blend(_sprint_amount, bool(player_state.get("sprinting", false)), delta, 8.0)
	var aiming := bool(player_state.get("aiming", false)) or bool(ammo_state.get("aiming", false))
	_aim_amount = _exp_blend(_aim_amount, aiming, delta, 12.0)
	_crouch_amount = _exp_blend(_crouch_amount, bool(player_state.get("crouching", false)), delta, 10.0)
	_prone_amount = _exp_blend(_prone_amount, bool(player_state.get("prone", false)), delta, 6.0)
	_vault_amount = _exp_blend(_vault_amount, bool(player_state.get("vaulting", false)), delta, 9.0)
	_climb_amount = _exp_blend(_climb_amount, bool(player_state.get("climbing", false)), delta, 9.0)
	_vault_progress = clampf(float(player_state.get("vault_progress", 0.0)), 0.0, 1.0)
	_climb_progress = clampf(float(player_state.get("climb_progress", 0.0)), 0.0, 1.0)
	if _sprint_amount > 0.1:
		_sprint_phase += delta * TAU * 1.6
	else:
		_sprint_phase = lerpf(_sprint_phase, 0.0, 1.0 - exp(-delta * 5.0))


func _set_pose_priority() -> void:
	if _inspect_active:
		_pose_name = "inspect"
	elif _climb_amount > 0.5:
		_pose_name = "climb"
	elif _vault_amount > 0.5:
		_pose_name = "vault"
	else:
		_pose_name = "idle"


func _advance_inspect(delta: float) -> void:
	if not _inspect_active:
		_inspect_progress = 0.0
		return
	_inspect_time += delta
	if _inspect_time >= INSPECT_DURATION:
		_inspect_time = 0.0
		_inspect_active = false
		_inspect_progress = 0.0
		_pose_name = "idle"
		return
	var phase := _inspect_time / INSPECT_DURATION
	var triangle := 1.0 - absf(phase * 2.0 - 1.0)
	_inspect_progress = smoothstep(0.0, 1.0, triangle)
	_pose_name = "inspect"


func _apply_pose() -> void:
	var motion := _compute_motion_offset()
	var rotation_offset := _compute_rotation_offset()
	_current_offset = motion
	_weapons.position = _base_position + motion
	_weapons.rotation = _base_rotation + rotation_offset


func _compute_motion_offset() -> Vector3:
	var stability := maxf(1.0 - _aim_amount * 0.7 - _crouch_amount * 0.25 - _prone_amount * 0.45, 0.25)
	var sway := _idle_sway_position() * stability * _weapon_sway_scale
	sway *= 1.0 - _moving_amount * 0.35
	var sprint := Vector3(
		sin(_sprint_phase * 2.0) * SPRINT_BOB_POS.x,
		SPRINT_OFFSET.y + sin(_sprint_phase * 2.0) * SPRINT_BOB_POS.y,
		SPRINT_OFFSET.z
	) * _sprint_amount
	var reload := RELOAD_DIP * _reload_amount
	var inspect := INSPECT_OFFSET * _inspect_progress
	var vault_curve: float = sin(PI * clampf(_vault_progress, 0.0, 1.0))
	var vault: Vector3 = VAULT_OFFSET * _vault_amount * vault_curve
	var climb_scale: float = clampf(_climb_progress, 0.0, 1.0)
	var climb: Vector3 = CLIMB_OFFSET * _climb_amount * climb_scale
	return sway + sprint + reload + inspect + vault + climb


func _compute_rotation_offset() -> Vector3:
	var stability := maxf(1.0 - _aim_amount * 0.8 - _crouch_amount * 0.2 - _prone_amount * 0.35, 0.2)
	var sway := _idle_sway_rotation() * stability * _weapon_sway_scale
	sway *= 1.0 - _moving_amount * 0.3
	var sprint := Vector3(SPRINT_PITCH, 0.0, sin(_sprint_phase) * SPRINT_BOB_ROLL) * _sprint_amount
	var reload := Vector3(RELOAD_PITCH, 0.0, 0.0) * _reload_amount
	var wobble := Vector3(
		sin(_inspect_time * TAU * 1.7) * INSPECT_WOBBLE,
		sin(_inspect_time * TAU * 1.1) * INSPECT_WOBBLE * 0.6,
		sin(_inspect_time * TAU * 1.4) * INSPECT_WOBBLE * 0.8
	) * _inspect_progress
	var inspect := (INSPECT_ROTATION + wobble) * _inspect_progress
	var vault_curve: float = sin(PI * clampf(_vault_progress, 0.0, 1.0))
	var vault: Vector3 = VAULT_ROTATION * _vault_amount * vault_curve
	var climb_scale: float = clampf(_climb_progress, 0.0, 1.0)
	var climb: Vector3 = CLIMB_ROTATION * _climb_amount * climb_scale
	return sway + sprint + reload + inspect + vault + climb


func _idle_sway_position() -> Vector3:
	return Vector3(
		sin(_sway_time) * IDLE_POS_AMPLITUDE.x,
		sin(_sway_time * 0.63 + 1.1) * IDLE_POS_AMPLITUDE.y,
		cos(_sway_time * 0.81) * IDLE_POS_AMPLITUDE.z
	)


func _idle_sway_rotation() -> Vector3:
	return Vector3(
		sin(_sway_time * 0.47 + 0.6) * IDLE_ROT_AMPLITUDE.x,
		sin(_sway_time * 0.71) * IDLE_ROT_AMPLITUDE.y,
		sin(_sway_time * 0.89 + 1.4) * IDLE_ROT_AMPLITUDE.z
	)


func _sway_scale_for_name(weapon_name: String) -> float:
	if weapon_name.contains("Longbow") or weapon_name.contains("Hellstorm"):
		return 0.75
	if weapon_name.contains("M67") or weapon_name.contains("Frag"):
		return 0.85
	return 1.0


func _exp_blend(current: float, target: bool, delta: float, rate: float) -> float:
	return lerpf(current, 1.0 if target else 0.0, 1.0 - exp(-delta * rate))
