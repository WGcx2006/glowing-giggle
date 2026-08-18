extends Node3D

signal objective_changed(text: String)
signal game_over(winner: String)
signal sector_advanced(sector_index: int)
signal deploy_points_changed()

const SECTOR_ZONES := [["A"], ["B"], ["C"], ["D"]]
const SECTOR_NAMES := ["仓库区", "断桥区", "瞭望塔区", "碉堡区"]
const BASE_POSITION := Vector3(-30.0, 0.0, -8.0)
const STARTING_ATTACK_TICKETS := 100.0
const TICKETS_PER_SECTOR := 30.0
const MAX_ATTACK_TICKETS := 250.0
const MATCH_DURATION := 600.0

var _player: Node3D = null
var _enemy_system: Node = null
var _capture_zones: Node = null
var _attack_tickets := STARTING_ATTACK_TICKETS
var _sector_index := 0
var _time_remaining := MATCH_DURATION
var _winner := ""
var _last_objective := ""


func setup(player: Node3D, enemy_system: Node, capture_zones: Node) -> void:
	_player = player
	_enemy_system = enemy_system
	_capture_zones = capture_zones
	_reset_match_state()
	_sync_zone_locks()
	_update_objective()


func get_state() -> Dictionary:
	return {
		"attack_tickets": int(round(_attack_tickets)),
		"sector_index": _sector_index,
		"sector_name": get_sector_name(_sector_index),
		"sectors_total": SECTOR_ZONES.size(),
		"time_remaining": _time_remaining,
		"winner": _winner,
		"active": _winner == "",
		"deploy_points": get_deploy_points(),
	}


func get_deploy_points() -> Array[Vector3]:
	var points: Array[Vector3] = [BASE_POSITION]
	if _capture_zones == null or not is_instance_valid(_capture_zones):
		return points
	var state: Dictionary = _capture_zones.get_control_state()
	var zones: Array = state.get("zones", [])
	for zone: Variant in zones:
		var zone_dict: Dictionary = zone
		if String(zone_dict.get("team", "")) == "blue":
			points.append(Vector3(zone_dict.get("position", Vector3.ZERO)))
	return points


func get_current_sector_zones() -> Array[String]:
	var result: Array[String] = []
	if _sector_index < 0 or _sector_index >= SECTOR_ZONES.size():
		return result
	for id: Variant in SECTOR_ZONES[_sector_index]:
		result.append(str(id))
	return result


func get_sector_name(index: int) -> String:
	if index < 0 or index >= SECTOR_NAMES.size():
		return "?"
	return SECTOR_NAMES[index]


func get_current_sector_position() -> Vector3:
	if _capture_zones == null or not is_instance_valid(_capture_zones):
		return BASE_POSITION
	var state: Dictionary = _capture_zones.get_control_state()
	var zones: Array = state.get("zones", [])
	var current: Array[String] = get_current_sector_zones()
	for zone: Variant in zones:
		var zone_dict: Dictionary = zone
		if current.has(String(zone_dict.get("id", ""))):
			return Vector3(zone_dict.get("position", BASE_POSITION))
	return BASE_POSITION


func on_player_died() -> void:
	if _winner != "":
		return
	_attack_tickets = maxf(_attack_tickets - 1.0, 0.0)
	if _check_ticket_end():
		return
	_update_objective()


func on_ally_killed() -> void:
	if _winner != "":
		return
	_attack_tickets = maxf(_attack_tickets - 0.5, 0.0)
	if _check_ticket_end():
		return
	_update_objective()


func on_enemy_killed(team: String) -> void:
	if team == "blue":
		on_ally_killed()


func update(delta: float) -> void:
	if _winner != "":
		return
	_time_remaining = maxf(_time_remaining - delta, 0.0)
	_check_sector_advance()
	if _winner != "":
		return
	if _time_remaining <= 0.0:
		_finish_game("red")
		return
	_update_objective()


func restart() -> void:
	_reset_match_state()
	if _capture_zones != null and is_instance_valid(_capture_zones):
		_capture_zones.reset_zones()
	if _enemy_system != null and is_instance_valid(_enemy_system):
		_enemy_system.spawn_teams()
	_sync_zone_locks()
	_update_objective()


func _check_sector_advance() -> void:
	if _capture_zones == null or not is_instance_valid(_capture_zones):
		return
	var current: Array[String] = get_current_sector_zones()
	if current.is_empty():
		return
	var state: Dictionary = _capture_zones.get_control_state()
	var zones: Array = state.get("zones", [])
	var all_captured := true
	for zone: Variant in zones:
		var zone_dict: Dictionary = zone
		if current.has(String(zone_dict.get("id", ""))) and String(zone_dict.get("team", "")) != "blue":
			all_captured = false
			break
	if not all_captured:
		return
	_sector_index += 1
	_attack_tickets = minf(_attack_tickets + TICKETS_PER_SECTOR, MAX_ATTACK_TICKETS)
	_sync_zone_locks()
	if _sector_index >= SECTOR_ZONES.size():
		_finish_game("blue")
		return
	sector_advanced.emit(_sector_index)
	deploy_points_changed.emit()


func _sync_zone_locks() -> void:
	if _capture_zones == null or not is_instance_valid(_capture_zones) or not _capture_zones.has_method("set_active_zones"):
		return
	_capture_zones.set_active_zones(get_current_sector_zones())


func _check_ticket_end() -> bool:
	if _attack_tickets <= 0.0:
		_finish_game("red")
		return true
	return false


func _finish_game(winner: String) -> void:
	_winner = winner
	var result_text := "比赛结束 - 防守方胜利"
	if winner == "blue":
		result_text = "比赛结束 - 进攻方胜利"
	objective_changed.emit(result_text)
	game_over.emit(winner)


func _update_objective() -> void:
	if _winner != "":
		return
	var text := "突破模式 - 扇区 %d/%d（%s）- 进攻资源 %d - 占领该扇区全部据点后推进 - 剩余 %02d:%02d"
	text = text % [
		_sector_index + 1,
		SECTOR_ZONES.size(),
		get_sector_name(_sector_index),
		int(round(_attack_tickets)),
		int(_time_remaining) / 60,
		int(_time_remaining) % 60,
	]
	if text != _last_objective:
		_last_objective = text
		objective_changed.emit(text)


func _reset_match_state() -> void:
	_attack_tickets = STARTING_ATTACK_TICKETS
	_sector_index = 0
	_time_remaining = MATCH_DURATION
	_winner = ""
	_last_objective = ""
