extends Node3D

signal capture_progress(zone_id: String, team: String, progress: float)
signal zone_captured(zone_id: String, team: String)

const DEFAULT_ZONE_DATA := [
	{"id": "A", "position": Vector3(-42.0, 0.0, -42.0), "radius": 6.5, "height": 4.0},
	{"id": "B", "position": Vector3(42.0, 0.0, -42.0), "radius": 6.5, "height": 4.0},
	{"id": "C", "position": Vector3(-42.0, 0.0, 42.0), "radius": 6.5, "height": 4.0},
	{"id": "D", "position": Vector3(42.0, 0.0, 42.0), "radius": 6.5, "height": 4.0},
]
const CAPTURE_RATE := 16.0
const DECAY_RATE := 5.0
const NUDGE_STEP := 2.0
const NUDGE_MAX_STEPS := 16

var _zones: Array = []
var _present: Dictionary = {}
var _progress: Dictionary = {}
var _team: Dictionary = {}
var _initial_team: Dictionary = {}
var _active_zones: Array = []
var _all_active := true
var _contested: Dictionary = {}
var _captured_emitted: Dictionary = {}
var _last_progress: Dictionary = {}
var _last_team: Dictionary = {}
var _last_contested: Dictionary = {}
var _marker_materials: Dictionary = {}
var _initialized := false
var _nudge_checked := false


func _ready() -> void:
	if not _initialized:
		setup(DEFAULT_ZONE_DATA)


func set_active_zones(zone_ids: Array) -> void:
	_active_zones = []
	for id: Variant in zone_ids:
		_active_zones.append(str(id))
	_all_active = _active_zones.is_empty()
	for entry in _zones:
		var zone_entry: Dictionary = entry as Dictionary
		var id: String = str(zone_entry.get("id", "A"))
		if not _is_active(id):
			_force_team_state(id)
		_update_zone_visuals(id)


func get_active_zones() -> Array:
	return _active_zones.duplicate()


func set_zone_team(zone_id: String, team: String) -> void:
	_team[zone_id] = team
	_progress[zone_id] = 100.0 if team != "" else 0.0
	_captured_emitted[zone_id] = team != ""
	_update_zone_visuals(zone_id)


func set_zone_progress(zone_id: String, progress: float) -> void:
	_progress[zone_id] = clampf(progress, 0.0, 100.0)


func _is_active(zone_id: String) -> bool:
	if _all_active:
		return true
	return _active_zones.has(zone_id)


func _force_team_state(zone_id: String) -> void:
	if String(_team.get(zone_id, "")) == "":
		_team[zone_id] = _initial_team.get(zone_id, "")
	_progress[zone_id] = 100.0 if String(_team.get(zone_id, "")) != "" else 0.0
	_captured_emitted[zone_id] = String(_team.get(zone_id, "")) != ""


func setup(zone_data: Array) -> void:
	_clear_state()
	var data := zone_data
	if data.is_empty():
		data = DEFAULT_ZONE_DATA
	for entry in data:
		var id: String = str(entry.get("id", "A"))
		var zone := get_node_or_null(id) as Area3D
		if zone == null:
			zone = _create_zone_area(id)
			add_child(zone)
		var zone_entry: Dictionary = (entry as Dictionary).duplicate()
		var position: Vector3 = zone_entry.get("position", Vector3.ZERO)
		zone_entry["position"] = _nudge_out_of_buildings(position)
		_configure_zone(zone, zone_entry)
		_zones.append(zone_entry)
		_progress[id] = 0.0
		_team[id] = ""
		var initial_team: String = str(zone_entry.get("team", ""))
		_initial_team[id] = initial_team
		if initial_team != "":
			_progress[id] = 100.0
			_team[id] = initial_team
		_contested[id] = false
		_captured_emitted[id] = initial_team != ""
		_last_progress[id] = -1.0
		_last_team[id] = ""
		_last_contested[id] = false
		if not _present.has(id):
			_present[id] = []
		else:
			_present[id].clear()
		_update_zone_visuals(id)
	_initialized = true


func update(delta: float) -> void:
	if not _nudge_checked:
		_nudge_checked = true
		_recheck_nudge()
	for entry in _zones:
		var zone_entry: Dictionary = entry as Dictionary
		var id: String = str(zone_entry.get("id", "A"))
		_update_zone(id, delta)


func get_control_state() -> Dictionary:
	var zone_states: Array = []
	for entry in _zones:
		var zone_entry: Dictionary = entry as Dictionary
		var id: String = str(zone_entry.get("id", "A"))
		var position: Vector3 = zone_entry.get("position", Vector3.ZERO)
		var radius: float = float(zone_entry.get("radius", 6.5))
		zone_states.append({
			"id": id,
			"position": position,
			"radius": radius,
			"team": _team.get(id, ""),
			"progress": _progress.get(id, 0.0),
			"contested": _contested.get(id, false),
			"active": _is_active(id),
		})
	var red_captured := 0
	var blue_captured := 0
	for zone in zone_states:
		var zone_team: String = zone.get("team", "")
		if zone_team == "red":
			red_captured += 1
		elif zone_team == "blue":
			blue_captured += 1
	return {
		"zones": zone_states,
		"red_captured": red_captured,
		"blue_captured": blue_captured,
		"total": zone_states.size(),
	}


func reset_zones() -> void:
	if _zones.is_empty():
		setup(DEFAULT_ZONE_DATA)
		return
	for entry in _zones:
		var zone_entry: Dictionary = entry as Dictionary
		var id: String = str(zone_entry.get("id", "A"))
		var initial_team: String = _initial_team.get(id, "")
		_progress[id] = 100.0 if initial_team != "" else 0.0
		_team[id] = initial_team
		_contested[id] = false
		_captured_emitted[id] = initial_team != ""
		_last_progress[id] = -1.0
		_last_team[id] = ""
		_last_contested[id] = false
		if not _present.has(id):
			_present[id] = []
		_update_zone_visuals(id)


func _create_zone_area(id: String) -> Area3D:
	var zone := Area3D.new()
	zone.name = id
	zone.collision_layer = 0
	zone.collision_mask = 0xFFFFFFFF
	zone.monitoring = true
	zone.monitorable = false
	zone.body_entered.connect(_on_body_entered.bind(id))
	zone.body_exited.connect(_on_body_exited.bind(id))
	return zone


func _configure_zone(zone: Area3D, entry: Dictionary) -> void:
	var position: Vector3 = entry.get("position", Vector3.ZERO)
	var radius: float = float(entry.get("radius", 6.5))
	var height: float = float(entry.get("height", 4.0))
	zone.position = position
	zone.collision_layer = 0
	zone.collision_mask = 0xFFFFFFFF
	zone.monitoring = true
	zone.monitorable = false
	var shape_node := zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		zone.add_child(shape_node)
	var shape := shape_node.shape as CylinderShape3D
	if shape == null:
		shape = CylinderShape3D.new()
		shape_node.shape = shape
	shape.radius = radius
	shape.height = height
	shape_node.position = Vector3(0.0, height * 0.5, 0.0)
	_ensure_visuals(zone, str(entry.get("id", "A")), radius, height)


func _ensure_visuals(zone: Area3D, id: String, radius: float, height: float) -> void:
	var marker := zone.get_node_or_null("Marker") as MeshInstance3D
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "Marker"
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = 0.08
		mesh.radial_segments = 32
		marker.mesh = mesh
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.8, 0.8, 0.9, 0.28)
		marker.material_override = material
		marker.position = Vector3(0.0, 0.04, 0.0)
		zone.add_child(marker)
		_marker_materials[id] = material
	else:
		if marker.mesh is CylinderMesh:
			var cylinder := marker.mesh as CylinderMesh
			cylinder.top_radius = radius
			cylinder.bottom_radius = radius
		var material := marker.material_override as StandardMaterial3D
		if material != null:
			_marker_materials[id] = material
	var label := zone.get_node_or_null("Label") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "Label"
		label.text = id
		label.font_size = 96
		label.pixel_size = 0.012
		label.position = Vector3(0.0, height + 0.6, 0.0)
		zone.add_child(label)
	else:
		label.position = Vector3(0.0, height + 0.6, 0.0)


func _update_zone(zone_id: String, delta: float) -> void:
	if not _is_active(zone_id):
		_contested[zone_id] = false
		_force_team_state(zone_id)
		_update_zone_visuals(zone_id)
		return
	var present: Array = _present.get(zone_id, [])
	var red_count := 0
	var blue_count := 0
	for body in present:
		if not is_instance_valid(body):
			continue
		if body.is_in_group("team_red"):
			red_count += 1
		elif body.is_in_group("team_blue"):
			blue_count += 1
	var contested := red_count > 0 and blue_count > 0
	var team: String = _team.get(zone_id, "")
	var progress: float = _progress.get(zone_id, 0.0)
	_contested[zone_id] = contested
	if contested:
		_emit_progress(zone_id, team, progress)
		_update_zone_visuals(zone_id)
		return
	if red_count == 0 and blue_count == 0:
		if team == "" and progress > 0.0:
			progress = maxf(0.0, progress - DECAY_RATE * delta)
			_progress[zone_id] = progress
			_emit_progress(zone_id, team, progress)
	elif blue_count > 0:
		_advance_capture(zone_id, "blue", delta)
	elif red_count > 0:
		_advance_capture(zone_id, "red", delta)
	_update_zone_visuals(zone_id)


func _advance_capture(zone_id: String, capturing_team: String, delta: float) -> void:
	var team: String = _team.get(zone_id, "")
	var progress: float = _progress.get(zone_id, 0.0)
	if team != "" and team != capturing_team:
		team = ""
		progress = 0.0
		_team[zone_id] = team
	progress = minf(100.0, progress + CAPTURE_RATE * delta)
	_progress[zone_id] = progress
	if progress >= 100.0 and team != capturing_team:
		team = capturing_team
		_team[zone_id] = team
		_captured_emitted[zone_id] = false
	if progress >= 100.0 and not bool(_captured_emitted.get(zone_id, false)):
		_captured_emitted[zone_id] = true
		zone_captured.emit(zone_id, team)
	_emit_progress(zone_id, team, progress)


func _emit_progress(zone_id: String, team: String, progress: float) -> void:
	var key := int(round(progress))
	var last_key: int = int(_last_progress.get(zone_id, -1))
	var last_team: String = _last_team.get(zone_id, "")
	var last_contested: bool = _last_contested.get(zone_id, false)
	if key != last_key or team != last_team or _contested.get(zone_id, false) != last_contested:
		_last_progress[zone_id] = float(key)
		_last_team[zone_id] = team
		_last_contested[zone_id] = _contested.get(zone_id, false)
		capture_progress.emit(zone_id, team, progress)


func _update_zone_visuals(zone_id: String) -> void:
	var zone := get_node_or_null(zone_id) as Area3D
	if zone == null:
		return
	var material: StandardMaterial3D = _marker_materials.get(zone_id)
	if material == null:
		return
	var team: String = _team.get(zone_id, "")
	if team == "blue":
		material.albedo_color = Color(0.15, 0.45, 0.9, 0.45)
	elif team == "red":
		material.albedo_color = Color(0.9, 0.18, 0.15, 0.45)
	elif bool(_contested.get(zone_id, false)):
		material.albedo_color = Color(0.95, 0.75, 0.15, 0.5)
	else:
		material.albedo_color = Color(0.8, 0.8, 0.9, 0.28)


func _on_body_entered(body: Node3D, zone_id: String) -> void:
	if not _is_combatant(body):
		return
	if not _present.has(zone_id):
		_present[zone_id] = []
	var present: Array = _present[zone_id]
	if not present.has(body):
		present.append(body)


func _on_body_exited(body: Node3D, zone_id: String) -> void:
	if not _present.has(zone_id):
		return
	var present: Array = _present[zone_id]
	present.erase(body)


func _is_combatant(body: Node) -> bool:
	return body.is_in_group("combatants") and (body.is_in_group("team_red") or body.is_in_group("team_blue"))


func _clear_state() -> void:
	_zones.clear()
	_progress.clear()
	_team.clear()
	_contested.clear()
	_captured_emitted.clear()
	_last_progress.clear()
	_last_team.clear()
	_last_contested.clear()
	_nudge_checked = false


func _nudge_out_of_buildings(position: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	var candidate := position
	for step in range(NUDGE_MAX_STEPS + 1):
		params.transform = Transform3D(Basis(), candidate)
		if not _blocked_by_static(space, params):
			return candidate
		candidate = position + Vector3(0.0, 0.0, float(step + 1) * NUDGE_STEP)
	return position


func _recheck_nudge() -> void:
	for entry in _zones:
		var zone_entry: Dictionary = entry as Dictionary
		var id: String = str(zone_entry.get("id", "A"))
		var pos: Vector3 = zone_entry.get("position", Vector3.ZERO)
		var safe := _nudge_out_of_buildings(pos)
		if safe == pos:
			continue
		zone_entry["position"] = safe
		var zone := get_node_or_null(id) as Area3D
		if zone != null:
			zone.position = safe
		_update_zone_visuals(id)


func _blocked_by_static(space: PhysicsDirectSpaceState3D, params: PhysicsShapeQueryParameters3D) -> bool:
	for hit in space.intersect_shape(params, 16):
		var collider = hit.get("collider")
		if collider != null and collider is Node and str(collider.name) != "Terrain":
			return true
	return false
