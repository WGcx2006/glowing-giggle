extends Control

const MAP_HALF_SIZE := 150.0

const _PADDING := 14.0
const _BG := Color(0.035, 0.05, 0.075, 0.82)
const _BORDER := Color(0.38, 0.58, 0.72, 0.6)
const _GRID := Color(0.3, 0.42, 0.5, 0.16)
const _BLUE := Color(0.2, 0.64, 0.96)
const _RED := Color(0.94, 0.28, 0.22)
const _NEUTRAL := Color(0.58, 0.64, 0.7)
const _YELLOW := Color(1.0, 0.78, 0.16)
const _WHITE := Color(0.94, 0.97, 1.0)

var _state: Dictionary = {}
var _enabled := true
var _bg_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = _BG
	_bg_style.border_color = _BORDER
	_bg_style.set_border_width_all(1)
	_bg_style.set_corner_radius_all(6)


func set_state(state: Dictionary) -> void:
	_state = state
	queue_redraw()


func get_state() -> Dictionary:
	return _state


func set_enabled(value: bool) -> void:
	_enabled = value
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


func _draw() -> void:
	if not _enabled:
		return
	if _bg_style == null:
		_bg_style = StyleBoxFlat.new()
		_bg_style.bg_color = _BG
		_bg_style.border_color = _BORDER
		_bg_style.set_border_width_all(1)
		_bg_style.set_corner_radius_all(6)
	_draw_background()
	_draw_grid()
	_draw_zones()
	_draw_enemies()
	_draw_vehicles()
	_draw_player()
	_draw_north()


func _draw_background() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_bg_style, rect)


func _draw_grid() -> void:
	var map_rect := _map_rect()
	var top_left := map_rect.position
	var bottom_right := map_rect.position + map_rect.size
	var step := 50.0
	var grid_count := int(MAP_HALF_SIZE * 2.0 / step)
	for i in range(1, grid_count):
		var world := -MAP_HALF_SIZE + step * float(i)
		var x := _map_x(world)
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), _GRID, 1.0)
		var y := _map_z(world)
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), _GRID, 1.0)
	draw_line(top_left, Vector2(bottom_right.x, top_left.y), _BORDER, 1.2)
	draw_line(Vector2(bottom_right.x, top_left.y), bottom_right, _BORDER, 1.2)
	draw_line(bottom_right, Vector2(top_left.x, bottom_right.y), _BORDER, 1.2)
	draw_line(Vector2(top_left.x, bottom_right.y), top_left, _BORDER, 1.2)


func _map_rect() -> Rect2:
	var map_size := minf(size.x, size.y) - _PADDING * 2.0
	map_size = maxf(map_size, 16.0)
	var left := (size.x - map_size) * 0.5
	var top := (size.y - map_size) * 0.5
	return Rect2(left, top, map_size, map_size)


func _map_x(world_x: float) -> float:
	var map_rect := _map_rect()
	var normalized := (clampf(world_x, -MAP_HALF_SIZE, MAP_HALF_SIZE) + MAP_HALF_SIZE) / (MAP_HALF_SIZE * 2.0)
	return clampf(map_rect.position.x + normalized * map_rect.size.x, 0.0, maxf(size.x, 0.0))


func _map_z(world_z: float) -> float:
	var map_rect := _map_rect()
	var normalized := (MAP_HALF_SIZE - clampf(world_z, -MAP_HALF_SIZE, MAP_HALF_SIZE)) / (MAP_HALF_SIZE * 2.0)
	return clampf(map_rect.position.y + normalized * map_rect.size.y, 0.0, maxf(size.y, 0.0))


func _clamp_point(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 0.0, maxf(size.x, 0.0)), clampf(point.y, 0.0, maxf(size.y, 0.0)))


func _world_position(point: Variant) -> Vector2:
	if point is Vector3:
		var pos3: Vector3 = point
		return Vector2(pos3.x, pos3.z)
	if point is Vector2:
		var pos2: Vector2 = point
		return Vector2(pos2.x, pos2.y)
	if point is Array:
		var arr: Array = point
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	if point is Dictionary:
		var pos_dict: Dictionary = point
		if pos_dict.has("x") and pos_dict.has("z"):
			return Vector2(float(pos_dict["x"]), float(pos_dict["z"]))
		if pos_dict.has("x") and pos_dict.has("y"):
			return Vector2(float(pos_dict["x"]), float(pos_dict["y"]))
	return Vector2.ZERO


func _team_color(team: String) -> Color:
	var normalized := team.to_lower()
	if normalized == "blue" or normalized == "ally" or normalized == "player":
		return _BLUE
	if normalized == "red" or normalized == "enemy":
		return _RED
	return _NEUTRAL


func _draw_zones() -> void:
	var zones: Variant = _state.get("zones", [])
	if not (zones is Array):
		return
	for zone: Variant in (zones as Array):
		if zone is Dictionary:
			_draw_zone(zone as Dictionary)


func _draw_zone(zone: Dictionary) -> void:
	var pos := _world_position(zone.get("position", Vector3.ZERO))
	var team := String(zone.get("team", ""))
	var contested := bool(zone.get("contested", false))
	var fill := _team_color(team)
	if contested:
		fill = _YELLOW
	var radius := 9.0
	var center := _clamp_point(pos)
	center.x = clampf(center.x, radius, maxf(size.x - radius, radius))
	center.y = clampf(center.y, radius, maxf(size.y - radius, radius))
	draw_circle(center, radius, Color(fill.r, fill.g, fill.b, 0.26))
	draw_arc(center, radius, 0.0, TAU, 24, fill, 1.5)
	var id_text := String(zone.get("id", ""))
	if id_text != "":
		var font: Font = ThemeDB.fallback_font
		var text_pos := _clamp_point(Vector2(center.x - 5.0, center.y + 4.0))
		draw_string(font, text_pos, id_text, HORIZONTAL_ALIGNMENT_LEFT, 96.0, 12, fill)


func _draw_enemies() -> void:
	var enemies: Variant = _state.get("enemies", [])
	if not (enemies is Array):
		return
	for enemy: Variant in (enemies as Array):
		if not (enemy is Dictionary):
			continue
		var entry: Dictionary = enemy
		if not bool(entry.get("alive", false)):
			continue
		var pos := _world_position(entry.get("position", Vector3.ZERO))
		var team := String(entry.get("team", "red"))
		var color := _team_color(team)
		if color == _NEUTRAL:
			color = _RED
		var center := _clamp_point(pos)
		center.x = clampf(center.x, 4.0, maxf(size.x - 4.0, 4.0))
		center.y = clampf(center.y, 4.0, maxf(size.y - 4.0, 4.0))
		draw_circle(center, 3.5, color)


func _draw_vehicles() -> void:
	var vehicles: Variant = _state.get("vehicles", [])
	if not (vehicles is Array):
		return
	for vehicle: Variant in (vehicles as Array):
		var pos := Vector2.ZERO
		if vehicle is Dictionary:
			pos = _world_position((vehicle as Dictionary).get("position", Vector3.ZERO))
		else:
			pos = _world_position(vehicle)
		var half := 4.0
		var rect_pos := Vector2(
			clampf(pos.x - half, 0.0, maxf(size.x - half * 2.0, 0.0)),
			clampf(pos.y - half, 0.0, maxf(size.y - half * 2.0, 0.0))
		)
		draw_rect(Rect2(rect_pos, Vector2(half * 2.0, half * 2.0)), _YELLOW)


func _draw_player() -> void:
	var pos := _world_position(_state.get("player_pos", Vector3.ZERO))
	var yaw := float(_state.get("player_yaw", 0.0))
	var direction := Vector2(-sin(yaw), -cos(yaw))
	if direction.length_squared() < 0.0001:
		direction = Vector2.UP
	direction = direction.normalized()
	var side := Vector2(-direction.y, direction.x)
	var center := _clamp_point(pos)
	var margin_x := minf(10.0, size.x * 0.5)
	var margin_y := minf(10.0, size.y * 0.5)
	center.x = clampf(center.x, margin_x, maxf(size.x - margin_x, margin_x))
	center.y = clampf(center.y, margin_y, maxf(size.y - margin_y, margin_y))
	var tip := _clamp_point(center + direction * 9.0)
	var back := _clamp_point(center - direction * 6.0)
	var left := _clamp_point(back + side * 5.0)
	var right := _clamp_point(back - side * 5.0)
	var points := PackedVector2Array([tip, left, right])
	draw_colored_polygon(points, _WHITE)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), _WHITE, 1.2)


func _draw_north() -> void:
	var map_rect := _map_rect()
	var center_x := clampf(map_rect.position.x + map_rect.size.x * 0.5, 0.0, maxf(size.x, 0.0))
	var top_y := clampf(map_rect.position.y, 0.0, maxf(size.y, 0.0))
	draw_line(Vector2(center_x, top_y), Vector2(center_x, clampf(top_y + 6.0, 0.0, maxf(size.y, 0.0))), _BORDER, 1.0)
	var font: Font = ThemeDB.fallback_font
	var text_pos := Vector2(clampf(center_x - 8.0, 0.0, maxf(size.x, 0.0)), clampf(top_y + 9.0, 0.0, maxf(size.y, 0.0)))
	draw_string(font, text_pos, "N", HORIZONTAL_ALIGNMENT_LEFT, 48.0, 13, _WHITE)
