extends CanvasLayer

const MINIMAP_SCRIPT := preload("res://scripts/ui/minimap.gd")
const DAMAGE_NUMBER_COUNT := 16

signal restart_requested
signal quality_changed(value: String)
signal sensitivity_changed(value: float)
signal mouse_capture_toggled(value: bool)
signal pause_toggled(value: bool)
signal start_game_requested
signal deploy_requested(loadout: Dictionary, spawn_index: int)
signal quit_requested
signal host_session_requested(session_name: String)
signal join_session_requested(address: String)
signal leave_session_requested

class Crosshair extends Control:
	var spread := 8.0
	var gap := 8.0
	var thickness := 2.0
	var length := 12.0
	var color := Color(0.9, 0.95, 1.0, 0.95)

	func _draw() -> void:
		var c := size * 0.5
		var g := gap + spread
		var t := thickness
		var h := length
		draw_rect(Rect2(c.x - t * 0.5, c.y - g - h, t, h), color)
		draw_rect(Rect2(c.x - t * 0.5, c.y + g, t, h), color)
		draw_rect(Rect2(c.x - g - h, c.y - t * 0.5, h, t), color)
		draw_rect(Rect2(c.x + g, c.y - t * 0.5, h, t), color)
		draw_rect(Rect2(c.x - 1.5, c.y - 1.5, 3.0, 3.0), Color(color.r, color.g, color.b, color.a * 0.7))

	func set_spread(value: float) -> void:
		if not is_equal_approx(spread, value):
			spread = value
			queue_redraw()


class HitMarker extends Control:
	var thickness := 3.0
	var length := 14.0
	var gap := 6.0
	var color := Color(1.0, 1.0, 1.0, 1.0)

	func _draw() -> void:
		var c := size * 0.5
		var t := thickness
		var h := length
		var g := gap
		draw_rect(Rect2(c.x - t * 0.5, c.y - g - h, t, h), color)
		draw_rect(Rect2(c.x - t * 0.5, c.y + g, t, h), color)
		draw_rect(Rect2(c.x - g - h, c.y - t * 0.5, h, t), color)
		draw_rect(Rect2(c.x + g, c.y - t * 0.5, h, t), color)


var _root: Control
var _minimap: Control = null
var _crosshair: Crosshair
var _hit_marker: HitMarker
var _objective_label: Label
var _message_label: Label
var _damage_numbers: Array = []
var _damage_number_timers: Array = []
var _weapon_label: Label
var _ammo_label: Label
var _health_bar: ProgressBar
var _health_label: Label
var _damage_rect: ColorRect
var _low_health_rect: ColorRect
var _game_over_overlay: ColorRect
var _game_over_panel: PanelContainer
var _game_over_result: Label
var _conquest_label: Label
var _game_over_summary_label: Label
var _menu_overlay: ColorRect
var _menu_panel: PanelContainer
var _quality_option: OptionButton
var _sensitivity_slider: HSlider
var _sensitivity_label: Label
var _mouse_capture_button: CheckButton
var _feed_box: VBoxContainer
var _feed_style: StyleBoxFlat
var _zone_bars: Dictionary = {}
var _zone_labels: Dictionary = {}
var _zone_teams: Dictionary = {}
var _zone_targets: Dictionary = {}
var _zone_neutral_fill: StyleBoxFlat
var _zone_blue_fill: StyleBoxFlat
var _zone_red_fill: StyleBoxFlat
var _feed_items: Array = []
var _pending_message: Array = []
var _pending_quality := ""
var _last_feed_entry: Variant = null

var _health := 100.0
var _max_health := 100.0
var _ammo := 30
var _reserve := 90
var _last_feed_text := ""
var _hit_timer := 0.0
var _damage_timer := 0.0
var _message_timer := 0.0
var _pulse_time := 0.0
var _crosshair_spread := 8.0
var _target_spread := 8.0
var _menu_open := false
var _game_over_visible := false
var _initialized := false
var _main_menu_overlay: ColorRect
var _main_menu_panel: PanelContainer
var _deploy_overlay: ColorRect
var _deploy_panel: PanelContainer
var _class_buttons: Dictionary = {}
var _weapon_buttons: Array = []
var _spawn_buttons: Array = []
var _deploy_classes: Array = []
var _deploy_weapons: Array = []
var _deploy_spawns: Array = []
var _selected_class := ""
var _selected_weapon_index := -1
var _selected_spawn_index := 0
var _quit_pending := false
var _main_menu_open := false
var _deploy_open := false
var _menu_label: Label
var _session_name_edit: LineEdit
var _server_address_edit: LineEdit
var _network_status_label: Label
var _class_list: VBoxContainer
var _weapon_list: VBoxContainer
var _spawn_list: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if _pending_quality != "":
		set_quality_menu(_pending_quality)
	if _pending_message.size() >= 2:
		show_message(String(_pending_message[0]), _pending_message[1])
	_initialized = true


func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _game_over_visible or _main_menu_open or _deploy_open:
			get_viewport().set_input_as_handled()
			return
		toggle_menu()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _root == null or not _root.visible:
		return
	_pulse_time += delta
	_damage_timer = maxf(_damage_timer - delta, 0.0)
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_message_timer = maxf(_message_timer - delta, 0.0)
	_damage_rect.color.a = clampf(_damage_timer / 0.4, 0.0, 1.0) * 0.55
	_hit_marker.modulate.a = clampf(_hit_timer / 0.25, 0.0, 1.0)
	_message_label.modulate.a = clampf(_message_timer / 0.6, 0.0, 1.0)
	if not _game_over_visible and _health <= 30.0:
		var pulse := 0.1 + 0.1 * (0.5 + 0.5 * sin(_pulse_time * 7.0))
		_low_health_rect.color.a = pulse
	else:
		_low_health_rect.color.a = maxf(_low_health_rect.color.a - delta * 0.7, 0.0)
	_crosshair_spread = lerpf(_crosshair_spread, _target_spread, minf(delta * 12.0, 1.0))
	_crosshair.set_spread(_crosshair_spread)
	_update_capture_bars(delta)
	_update_feed(delta)
	_update_damage_numbers(delta)


func update_state(state: Dictionary) -> void:
	if _root == null or not _root.visible:
		return
	var previous_health := _health
	_max_health = maxf(1.0, float(state.get("max_health", _max_health)))
	_health = clampf(float(state.get("health", _health)), 0.0, _max_health)
	if _initialized and _health < previous_health - 0.25:
		_damage_timer = maxf(_damage_timer, 0.45)
	_health_bar.max_value = _max_health
	_health_bar.value = _health
	_health_label.text = "%d / %d" % [int(round(_health)), int(round(_max_health))]
	if _health > 30.0:
		_health_bar.modulate = Color.WHITE
	else:
		_health_bar.modulate = Color(1.0, 0.55, 0.45, 1.0)
	if state.has("ammo") or state.has("magazine"):
		_ammo = int(state.get("ammo", state.get("magazine", _ammo)))
	if state.has("reserve"):
		_reserve = int(state.get("reserve", _reserve))
	var reloading := bool(state.get("reloading", false))
	_ammo_label.text = _format_ammo(reloading)
	if state.has("weapon_name"):
		_weapon_label.text = _localize_weapon(String(state.get("weapon_name", "")))
	if state.has("objective"):
		_objective_label.text = String(state.get("objective", ""))
	if state.has("spread"):
		_target_spread = 8.0 + float(state.get("spread", 0.0)) * 28.0
	var damage := float(state.get("damage", 0.0))
	if damage > 0.02:
		_damage_timer = maxf(_damage_timer, clampf(damage * 0.7, 0.15, 0.7))
	if bool(state.get("hit_marker", false)) or bool(state.get("hit", false)):
		_hit_timer = 0.3
	if state.has("message"):
		var message := String(state.get("message", ""))
		if message != "":
			show_message(message, Color.WHITE)
	_update_capture_from_state(state)
	_update_feed_from_state(state)
	if _minimap != null and state.has("minimap"):
		(_minimap as MINIMAP_SCRIPT).set_state(state["minimap"])
	if state.has("game_mode") and state["game_mode"] is Dictionary:
		var mode: Dictionary = state["game_mode"]
		var blue: int = int(mode.get("blue_tickets", 0))
		var red: int = int(mode.get("red_tickets", 0))
		var time_left: float = float(mode.get("time_remaining", 0.0))
		var minutes: int = int(time_left) / 60
		var seconds: int = int(time_left) % 60
		_conquest_label.text = "蓝方 %d  |  红方 %d  |  %02d:%02d" % [blue, red, minutes, seconds]
	_initialized = true


func show_message(text: String, color: Color = Color.WHITE) -> void:
	if _message_label == null:
		_pending_message = [text, color]
		return
	_message_label.text = text
	_message_label.modulate = Color(color.r, color.g, color.b, 1.0)
	_message_timer = 4.0


func show_hit() -> void:
	_hit_timer = 0.3


func show_damage_number(value: float, screen_position: Vector2) -> void:
	if _damage_numbers.is_empty():
		return
	var index: int = -1
	for i in _damage_numbers.size():
		if float(_damage_number_timers[i]) <= 0.0:
			index = i
			break
	if index < 0:
		index = 0
	var label: Label = _damage_numbers[index]
	label.text = str(int(value))
	label.global_position = screen_position
	label.modulate = Color.WHITE
	label.visible = true
	_damage_number_timers[index] = 1.0


func get_active_damage_numbers() -> int:
	var count: int = 0
	for timer: Variant in _damage_number_timers:
		if float(timer) > 0.0:
			count += 1
	return count


func get_score_text() -> String:
	if _conquest_label == null:
		return ""
	return _conquest_label.text


func get_game_over_summary_text() -> String:
	if _game_over_summary_label == null:
		return ""
	return _game_over_summary_label.text


func show_game_over(winner: String, summary: Dictionary = {}) -> void:
	if _game_over_overlay == null or _game_over_result == null:
		return
	_game_over_visible = true
	_game_over_overlay.visible = true
	_game_over_result.text = _winner_text(winner)
	if not summary.is_empty() and summary.has("blue_tickets") and summary.has("red_tickets"):
		var blue: int = int(summary.get("blue_tickets", 0))
		var red: int = int(summary.get("red_tickets", 0))
		var time_left: float = float(summary.get("time_remaining", 0.0))
		var minutes: int = int(time_left) / 60
		var seconds: int = int(time_left) % 60
		_game_over_summary_label.text = "蓝方 %d  -  红方 %d  -  剩余 %02d:%02d" % [blue, red, minutes, seconds]
	else:
		_game_over_summary_label.text = ""
	set_menu_open(false)


func hide_game_over() -> void:
	if _game_over_overlay == null:
		return
	_game_over_visible = false
	_game_over_overlay.visible = false


func set_quality_menu(value: String) -> void:
	if _quality_option == null:
		_pending_quality = value
		return
	for i in _quality_option.item_count:
		if String(_quality_option.get_item_metadata(i)) == value:
			_quality_option.select(i)
			return


func set_hud_visible(value: bool) -> void:
	if _root != null:
		_root.visible = value


func get_minimap() -> Control:
	return _minimap


func toggle_menu() -> void:
	if _game_over_visible:
		return
	set_menu_open(not _menu_open)


func set_menu_open(value: bool) -> void:
	if _menu_overlay == null or _menu_panel == null:
		return
	if _game_over_visible and value:
		return
	if _menu_open == value:
		return
	_menu_open = value
	_menu_overlay.visible = value
	_menu_panel.visible = value
	pause_toggled.emit(value)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_damage_layers()
	_build_damage_numbers()
	_build_crosshair()
	_build_center_text()
	_build_ammo_panel()
	_build_health_panel()
	_build_capture_row()
	_build_kill_feed()
	_build_menu()
	_build_game_over()
	_build_main_menu()
	_build_deployment()
	var minimap: Control = MINIMAP_SCRIPT.new()
	minimap.name = "Minimap"
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -224.0
	minimap.offset_top = 120.0
	minimap.offset_right = -12.0
	minimap.offset_bottom = 344.0
	_root.add_child(minimap)
	_minimap = minimap


func _build_damage_layers() -> void:
	_damage_rect = ColorRect.new()
	_damage_rect.name = "DamageVignette"
	_damage_rect.color = Color(0.65, 0.0, 0.0, 0.0)
	_damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_damage_rect)
	_low_health_rect = ColorRect.new()
	_low_health_rect.name = "LowHealthPulse"
	_low_health_rect.color = Color(0.42, 0.0, 0.0, 0.0)
	_low_health_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_health_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_low_health_rect)


func _build_damage_numbers() -> void:
	for i in DAMAGE_NUMBER_COUNT:
		var label: Label = Label.new()
		label.name = "DamageNumber%d" % (i + 1)
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.62, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.06, 0.9))
		label.add_theme_constant_override("outline_size", 3)
		_root.add_child(label)
		_damage_numbers.append(label)
		_damage_number_timers.append(0.0)


func _build_crosshair() -> void:
	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -80.0
	_crosshair.offset_top = -80.0
	_crosshair.offset_right = 80.0
	_crosshair.offset_bottom = 80.0
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)
	_hit_marker = HitMarker.new()
	_hit_marker.name = "HitMarker"
	_hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	_hit_marker.offset_left = -60.0
	_hit_marker.offset_top = -60.0
	_hit_marker.offset_right = 60.0
	_hit_marker.offset_bottom = 60.0
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_marker.modulate.a = 0.0
	_root.add_child(_hit_marker)


func _build_center_text() -> void:
	_objective_label = Label.new()
	_objective_label.name = "Objective"
	_objective_label.text = "占领目标点"
	_objective_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective_label.offset_top = 18.0
	_objective_label.offset_bottom = 56.0
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 26)
	_objective_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 0.95))
	_objective_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_objective_label.add_theme_constant_override("shadow_offset_x", 2)
	_objective_label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_objective_label)
	_message_label = Label.new()
	_message_label.name = "Message"
	_message_label.text = ""
	_message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_message_label.offset_top = 58.0
	_message_label.offset_bottom = 92.0
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 20)
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55, 1.0))
	_message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_message_label.add_theme_constant_override("shadow_offset_x", 2)
	_message_label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_message_label)
	_conquest_label = Label.new()
	_conquest_label.name = "Conquest"
	_conquest_label.text = "蓝方 100  |  红方 100  |  10:00"
	_conquest_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_conquest_label.offset_top = 92.0
	_conquest_label.offset_bottom = 128.0
	_conquest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_conquest_label.add_theme_font_size_override("font_size", 18)
	_conquest_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 0.95))
	_conquest_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_conquest_label.add_theme_constant_override("shadow_offset_x", 2)
	_conquest_label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_conquest_label)


func _build_ammo_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "AmmoPanel"
	panel.add_theme_stylebox_override("panel", _make_style(
		Color(0.04, 0.06, 0.09, 0.82), Color(0.3, 0.65, 0.95, 0.35), 4))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -320.0
	panel.offset_top = 16.0
	panel.offset_right = -20.0
	panel.offset_bottom = 110.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_weapon_label = Label.new()
	_weapon_label.text = "未装备"
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_label.add_theme_font_size_override("font_size", 20)
	_weapon_label.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0, 0.95))
	_ammo_label = Label.new()
	_ammo_label.text = "30 / 90"
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 30)
	_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3, 1.0))
	box.add_child(_weapon_label)
	box.add_child(_ammo_label)
	panel.add_child(box)
	_root.add_child(panel)


func _build_health_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "HealthPanel"
	panel.add_theme_stylebox_override("panel", _make_style(
		Color(0.04, 0.06, 0.09, 0.82), Color(0.15, 0.8, 0.35, 0.35), 4))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 20.0
	panel.offset_top = -110.0
	panel.offset_right = 300.0
	panel.offset_bottom = -20.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = "生命值"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.8, 0.95, 0.85, 0.9))
	_health_label = Label.new()
	_health_label.text = "100 / 100"
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_health_label.add_theme_font_size_override("font_size", 18)
	_health_label.add_theme_color_override("font_color", Color.WHITE)
	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0.0
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(240.0, 14.0)
	_health_bar.add_theme_stylebox_override("background", _make_style(
		Color(0.08, 0.1, 0.12, 0.9), Color(0.2, 0.25, 0.28, 0.8), 3))
	_health_bar.add_theme_stylebox_override("fill", _make_fill(Color(0.15, 0.8, 0.35)))
	box.add_child(title)
	box.add_child(_health_bar)
	box.add_child(_health_label)
	panel.add_child(box)
	_root.add_child(panel)


func _build_capture_row() -> void:
	var row := HBoxContainer.new()
	row.name = "CaptureRow"
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -72.0
	row.offset_bottom = -24.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_root.add_child(row)
	_zone_neutral_fill = _make_fill(Color(0.35, 0.38, 0.42))
	_zone_blue_fill = _make_fill(Color(0.16, 0.62, 0.95))
	_zone_red_fill = _make_fill(Color(0.9, 0.28, 0.24))
	for zone_id in ["A", "B", "C", "D"]:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var label := Label.new()
		label.text = zone_id
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(72.0, 8.0)
		bar.add_theme_stylebox_override("background", _make_style(
			Color(0.05, 0.07, 0.1, 0.85), Color(0.25, 0.3, 0.35, 0.8), 3))
		bar.add_theme_stylebox_override("fill", _zone_neutral_fill)
		box.add_child(label)
		box.add_child(bar)
		row.add_child(box)
		_zone_labels[zone_id] = label
		_zone_bars[zone_id] = bar
		_zone_targets[zone_id] = 0.0


func _build_kill_feed() -> void:
	_feed_box = VBoxContainer.new()
	_feed_box.name = "KillFeed"
	_feed_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_feed_box.offset_left = -360.0
	_feed_box.offset_top = -260.0
	_feed_box.offset_right = -20.0
	_feed_box.offset_bottom = -92.0
	_feed_box.alignment = BoxContainer.ALIGNMENT_END
	_feed_box.add_theme_constant_override("separation", 4)
	_feed_style = _make_style(Color(0.03, 0.05, 0.08, 0.62), Color(0.4, 0.6, 0.8, 0.2), 3)
	_root.add_child(_feed_box)


func _build_menu() -> void:
	_menu_overlay = ColorRect.new()
	_menu_overlay.name = "MenuOverlay"
	_menu_overlay.color = Color(0.02, 0.03, 0.06, 0.45)
	_menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_overlay.visible = false
	_root.add_child(_menu_overlay)
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "MenuPanel"
	_menu_panel.add_theme_stylebox_override("panel", _make_style(
		Color(0.05, 0.07, 0.1, 0.94), Color(0.3, 0.65, 0.95, 0.5), 8))
	_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_menu_panel.offset_left = -260.0
	_menu_panel.offset_top = -210.0
	_menu_panel.offset_right = 260.0
	_menu_panel.offset_bottom = 210.0
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	vbox.add_child(title)
	var quality_row := HBoxContainer.new()
	quality_row.add_theme_constant_override("separation", 8)
	var quality_label := Label.new()
	quality_label.text = "画质"
	quality_label.custom_minimum_size = Vector2(100.0, 0.0)
	_quality_option = OptionButton.new()
	_quality_option.custom_minimum_size = Vector2(180.0, 0.0)
	var qualities := [["低", "low"], ["中", "medium"], ["高", "high"], ["超高", "ultra"]]
	for quality in qualities:
		_quality_option.add_item(quality[0])
		var index: int = _quality_option.item_count - 1
		_quality_option.set_item_metadata(index, quality[1])
	_quality_option.select(2)
	_quality_option.item_selected.connect(_on_quality_selected)
	quality_row.add_child(quality_label)
	quality_row.add_child(_quality_option)
	vbox.add_child(quality_row)
	var sensitivity_row := HBoxContainer.new()
	sensitivity_row.add_theme_constant_override("separation", 8)
	var sensitivity_label := Label.new()
	sensitivity_label.text = "灵敏度"
	sensitivity_label.custom_minimum_size = Vector2(100.0, 0.0)
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0.05
	_sensitivity_slider.max_value = 3.0
	_sensitivity_slider.step = 0.05
	_sensitivity_slider.value = 1.0
	_sensitivity_slider.custom_minimum_size = Vector2(220.0, 0.0)
	_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_sensitivity_label = Label.new()
	_sensitivity_label.text = "1.00"
	_sensitivity_label.custom_minimum_size = Vector2(56.0, 0.0)
	sensitivity_row.add_child(sensitivity_label)
	sensitivity_row.add_child(_sensitivity_slider)
	sensitivity_row.add_child(_sensitivity_label)
	vbox.add_child(sensitivity_row)
	_mouse_capture_button = CheckButton.new()
	_mouse_capture_button.text = "鼠标捕获"
	_mouse_capture_button.button_pressed = true
	_mouse_capture_button.toggled.connect(_on_mouse_capture_toggled)
	vbox.add_child(_mouse_capture_button)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 10)
	var restart_button := Button.new()
	restart_button.text = "重新开始"
	restart_button.pressed.connect(_on_restart_pressed)
	var close_button := Button.new()
	close_button.text = "继续"
	close_button.pressed.connect(_on_close_menu_pressed)
	button_row.add_child(restart_button)
	button_row.add_child(close_button)
	vbox.add_child(button_row)
	_menu_panel.add_child(vbox)
	_menu_overlay.add_child(_menu_panel)


func _build_game_over() -> void:
	_game_over_overlay = ColorRect.new()
	_game_over_overlay.name = "GameOverOverlay"
	_game_over_overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	_game_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_overlay.visible = false
	_root.add_child(_game_over_overlay)
	_game_over_panel = PanelContainer.new()
	_game_over_panel.name = "GameOverPanel"
	_game_over_panel.add_theme_stylebox_override("panel", _make_style(
		Color(0.05, 0.07, 0.1, 0.95), Color(0.9, 0.4, 0.25, 0.55), 8))
	_game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	_game_over_panel.offset_left = -240.0
	_game_over_panel.offset_top = -170.0
	_game_over_panel.offset_right = 240.0
	_game_over_panel.offset_bottom = 170.0
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "战斗结束"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6, 1.0))
	_game_over_result = Label.new()
	_game_over_result.text = ""
	_game_over_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_result.add_theme_font_size_override("font_size", 24)
	_game_over_result.add_theme_color_override("font_color", Color.WHITE)
	var restart_button := Button.new()
	restart_button.text = "重新开始"
	restart_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(title)
	vbox.add_child(_game_over_result)
	_game_over_summary_label = Label.new()
	_game_over_summary_label.name = "GameOverSummary"
	_game_over_summary_label.text = ""
	_game_over_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_summary_label.add_theme_font_size_override("font_size", 16)
	_game_over_summary_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 0.9))
	vbox.add_child(_game_over_summary_label)
	vbox.add_child(restart_button)
	_game_over_panel.add_child(vbox)
	_game_over_overlay.add_child(_game_over_panel)


func _build_main_menu() -> void:
	_main_menu_overlay = ColorRect.new()
	_main_menu_overlay.name = "MainMenuOverlay"
	_main_menu_overlay.color = Color(0.01, 0.02, 0.04, 0.82)
	_main_menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu_overlay.visible = false
	_root.add_child(_main_menu_overlay)
	_root.move_child(_main_menu_overlay, _menu_overlay.get_index())

	_main_menu_panel = PanelContainer.new()
	_main_menu_panel.name = "MainMenuPanel"
	_main_menu_panel.add_theme_stylebox_override("panel", _make_style(
		Color(0.04, 0.06, 0.09, 0.96), Color(0.3, 0.65, 0.95, 0.55), 8))
	_main_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_main_menu_panel.offset_left = -270.0
	_main_menu_panel.offset_top = -360.0
	_main_menu_panel.offset_right = 270.0
	_main_menu_panel.offset_bottom = 360.0
	_main_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu_panel.visible = false
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_menu_label = Label.new()
	_menu_label.text = "战地2035"
	_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_label.add_theme_font_size_override("font_size", 44)
	_menu_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	_menu_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	_menu_label.add_theme_constant_override("shadow_offset_x", 2)
	_menu_label.add_theme_constant_override("shadow_offset_y", 2)
	var subtitle := Label.new()
	subtitle.text = "MODERN WARFARE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0, 0.9))
	var accent := ColorRect.new()
	accent.color = Color(0.35, 0.7, 1.0, 0.8)
	accent.custom_minimum_size = Vector2(180.0, 3.0)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	var start_button := Button.new()
	start_button.text = "开始游戏"
	start_button.custom_minimum_size = Vector2(280.0, 46.0)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(_on_main_start_pressed)
	_apply_button_style(start_button, true)
	var settings_button := Button.new()
	settings_button.text = "设置"
	settings_button.custom_minimum_size = Vector2(280.0, 46.0)
	settings_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	settings_button.pressed.connect(_on_main_settings_pressed)
	_apply_button_style(settings_button, false)
	var quit_button := Button.new()
	quit_button.text = "退出"
	quit_button.custom_minimum_size = Vector2(280.0, 46.0)
	quit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_button.pressed.connect(_on_main_quit_pressed)
	_apply_button_style(quit_button, false)
	vbox.add_child(_menu_label)
	vbox.add_child(subtitle)
	vbox.add_child(accent)
	vbox.add_child(spacer)
	vbox.add_child(start_button)
	vbox.add_child(settings_button)
	vbox.add_child(quit_button)

	var mp_title := Label.new()
	mp_title.text = "多人游戏"
	mp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_title.add_theme_font_size_override("font_size", 22)
	mp_title.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0, 1.0))
	vbox.add_child(mp_title)

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	_session_name_edit = LineEdit.new()
	_session_name_edit.text = "Battlefield2035"
	_session_name_edit.placeholder_text = "房间名"
	_session_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var host_button := Button.new()
	host_button.text = "创建房间"
	host_button.custom_minimum_size = Vector2(140.0, 42.0)
	host_button.pressed.connect(_on_host_session_pressed)
	_apply_button_style(host_button, false)
	host_row.add_child(_session_name_edit)
	host_row.add_child(host_button)
	vbox.add_child(host_row)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_server_address_edit = LineEdit.new()
	_server_address_edit.text = "127.0.0.1"
	_server_address_edit.placeholder_text = "服务器地址"
	_server_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join_button := Button.new()
	join_button.text = "加入房间"
	join_button.custom_minimum_size = Vector2(140.0, 42.0)
	join_button.pressed.connect(_on_join_session_pressed)
	_apply_button_style(join_button, false)
	join_row.add_child(_server_address_edit)
	join_row.add_child(join_button)
	vbox.add_child(join_row)

	var leave_button := Button.new()
	leave_button.text = "离开房间"
	leave_button.custom_minimum_size = Vector2(280.0, 42.0)
	leave_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_button.pressed.connect(_on_leave_session_pressed)
	_apply_button_style(leave_button, false)
	vbox.add_child(leave_button)

	_network_status_label = Label.new()
	_network_status_label.text = "网络：离线"
	_network_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_network_status_label.add_theme_font_size_override("font_size", 16)
	_network_status_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.95))
	vbox.add_child(_network_status_label)
	_main_menu_panel.add_child(vbox)
	_main_menu_overlay.add_child(_main_menu_panel)


func _build_deployment() -> void:
	_deploy_overlay = ColorRect.new()
	_deploy_overlay.name = "DeployOverlay"
	_deploy_overlay.color = Color(0.02, 0.04, 0.07, 0.82)
	_deploy_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deploy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_deploy_overlay.visible = false
	_root.add_child(_deploy_overlay)

	_deploy_panel = PanelContainer.new()
	_deploy_panel.name = "DeployPanel"
	_deploy_panel.add_theme_stylebox_override("panel", _make_style(
		Color(0.03, 0.05, 0.08, 0.94), Color(0.25, 0.55, 0.8, 0.45), 8))
	_deploy_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deploy_panel.offset_left = 24.0
	_deploy_panel.offset_top = 20.0
	_deploy_panel.offset_right = -24.0
	_deploy_panel.offset_bottom = -20.0
	_deploy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_deploy_panel.visible = false
	var root_box := VBoxContainer.new()
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", 14)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "部署配置"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	var subtitle := Label.new()
	subtitle.text = "选择兵种 / 武器 / 出生点"
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95, 0.85))
	header.add_child(title)
	header.add_child(subtitle)
	root_box.add_child(header)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	var class_result: Array = _make_deploy_column("兵种选择", 230.0)
	var class_panel: PanelContainer = class_result[0] as PanelContainer
	_class_list = class_result[1] as VBoxContainer
	content.add_child(class_panel)
	var weapon_result: Array = _make_deploy_column("武器选择", 300.0)
	var weapon_panel: PanelContainer = weapon_result[0] as PanelContainer
	_weapon_list = weapon_result[1] as VBoxContainer
	content.add_child(weapon_panel)
	var spawn_result: Array = _make_deploy_column("出生点选择", 190.0)
	var spawn_panel: PanelContainer = spawn_result[0] as PanelContainer
	_spawn_list = spawn_result[1] as VBoxContainer
	content.add_child(spawn_panel)
	root_box.add_child(content)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	var deploy_button := Button.new()
	deploy_button.text = "部署"
	deploy_button.custom_minimum_size = Vector2(220.0, 48.0)
	deploy_button.pressed.connect(_on_deploy_pressed)
	_apply_button_style(deploy_button, true)
	footer.add_child(deploy_button)
	root_box.add_child(footer)
	_deploy_panel.add_child(root_box)
	_deploy_overlay.add_child(_deploy_panel)


func _make_deploy_column(title_text: String, min_width: float) -> Array:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(
		Color(0.04, 0.06, 0.1, 0.92), Color(0.25, 0.5, 0.75, 0.45), 6))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	box.add_child(scroll)
	panel.add_child(box)
	return [panel, list]


func _on_quality_selected(index: int) -> void:
	quality_changed.emit(String(_quality_option.get_item_metadata(index)))


func _on_sensitivity_changed(value: float) -> void:
	_sensitivity_label.text = "%.2f" % value
	sensitivity_changed.emit(value)


func _on_mouse_capture_toggled(value: bool) -> void:
	mouse_capture_toggled.emit(value)


func _on_restart_pressed() -> void:
	set_menu_open(false)
	restart_requested.emit()


func _on_close_menu_pressed() -> void:
	set_menu_open(false)


func _on_main_start_pressed() -> void:
	start_game_requested.emit()


func _on_main_settings_pressed() -> void:
	set_menu_open(true)


func _on_main_quit_pressed() -> void:
	if _quit_pending:
		return
	_quit_pending = true
	_stop_all_audio()
	get_tree().create_timer(0.15, true).timeout.connect(_emit_quit_requested)


func _emit_quit_requested() -> void:
	if not _quit_pending:
		return
	_quit_pending = false
	quit_requested.emit()


func _stop_all_audio() -> void:
	var audio_manager_node := get_tree().get_first_node_in_group("bf_audio_manager")
	if audio_manager_node != null and audio_manager_node.has_method("stop_all"):
		audio_manager_node.call("stop_all")


func _on_host_session_pressed() -> void:
	host_session_requested.emit(get_session_name())


func _on_join_session_pressed() -> void:
	join_session_requested.emit(get_server_address())


func _on_leave_session_pressed() -> void:
	leave_session_requested.emit()


func get_session_name() -> String:
	if _session_name_edit == null:
		return ""
	return _session_name_edit.text


func get_server_address() -> String:
	if _server_address_edit == null:
		return ""
	return _server_address_edit.text


func set_network_state(state: Dictionary) -> void:
	if _network_status_label == null:
		return
	var mode_name := String(state.get("mode", "offline"))
	var peers := int(state.get("connected_peers", 0))
	if mode_name == "host":
		var name := String(state.get("session_name", ""))
		_network_status_label.text = "网络：主机 %s（%d 人）" % [name, peers]
	elif mode_name == "client":
		var server_address := String(state.get("address", ""))
		_network_status_label.text = "网络：客户端 %s" % server_address
	else:
		_network_status_label.text = "网络：离线"


func get_network_status_text() -> String:
	if _network_status_label == null:
		return ""
	return _network_status_label.text


func _on_class_button_pressed(class_id: String) -> void:
	select_class(class_id)


func _on_weapon_button_pressed(index: int) -> void:
	select_weapon(index)


func _on_spawn_button_pressed(index: int) -> void:
	select_spawn(index)


func _on_deploy_pressed() -> void:
	deploy_requested.emit(get_selected_loadout(), get_selected_spawn())


func show_main_menu() -> void:
	if _main_menu_overlay == null:
		return
	_main_menu_open = true
	_main_menu_overlay.visible = true
	_main_menu_panel.visible = true
	if _root != null:
		_root.visible = true


func hide_main_menu() -> void:
	if _main_menu_overlay == null:
		return
	_main_menu_open = false
	_main_menu_overlay.visible = false
	_main_menu_panel.visible = false


func is_main_menu_open() -> bool:
	return _main_menu_open


func show_deployment_menu() -> void:
	if _deploy_overlay == null:
		return
	_deploy_open = true
	_deploy_overlay.visible = true
	_deploy_panel.visible = true
	if _root != null:
		_root.visible = true


func hide_deployment_menu() -> void:
	if _deploy_overlay == null:
		return
	_deploy_open = false
	_deploy_overlay.visible = false
	_deploy_panel.visible = false


func is_deployment_open() -> bool:
	return _deploy_open


func set_deployment_options(classes: Array, weapons: Array, spawn_points: Array) -> void:
	_deploy_classes = classes.duplicate()
	_deploy_weapons = weapons.duplicate()
	_deploy_spawns = spawn_points.duplicate()
	_rebuild_class_buttons()
	_rebuild_spawn_buttons()
	if _deploy_classes.size() > 0 and _deploy_classes[0] is Dictionary:
		var first_class: Dictionary = _deploy_classes[0]
		select_class(_dict_text(first_class, ["id", "class_id", "class"]))
	else:
		_selected_class = ""
		_selected_weapon_index = -1
		_rebuild_weapon_buttons()
	if _deploy_spawns.size() > 0:
		select_spawn(0)


func select_class(class_id: String) -> void:
	if class_id == "":
		return
	_selected_class = class_id
	_update_class_button_styles()
	_rebuild_weapon_buttons()
	var default_index := _default_weapon_index()
	if default_index >= 0:
		select_weapon(default_index)
	else:
		_selected_weapon_index = -1
		_update_weapon_button_styles()


func select_weapon(index: int) -> void:
	if index < 0 or index >= _deploy_weapons.size():
		_selected_weapon_index = -1
		_update_weapon_button_styles()
		return
	if not _available_weapon_indices().has(index):
		_selected_weapon_index = -1
		_update_weapon_button_styles()
		return
	_selected_weapon_index = index
	_update_weapon_button_styles()


func select_spawn(index: int) -> void:
	if index < 0 or index >= _deploy_spawns.size():
		return
	_selected_spawn_index = index
	_update_spawn_button_styles()


func get_selected_loadout() -> Dictionary:
	var class_data := _get_class_data(_selected_class)
	var secondary := _index_array(class_data, ["secondary_indices", "secondary", "secondaries"])
	var secondary_index := -1
	if secondary.size() > 0:
		secondary_index = int(secondary[0])
	return {
		"class_id": _selected_class,
		"primary_index": _selected_weapon_index,
		"secondary_index": secondary_index,
	}


func get_selected_spawn() -> int:
	return _selected_spawn_index


func _rebuild_class_buttons() -> void:
	if _class_list == null:
		return
	_clear_children(_class_list)
	_class_buttons.clear()
	for entry in _deploy_classes:
		if not (entry is Dictionary):
			continue
		var class_data: Dictionary = entry
		var class_id := _dict_text(class_data, ["id", "class_id", "class"])
		if class_id == "":
			continue
		var class_title := _dict_text(class_data, ["name", "display_name", "title"])
		if class_title == "":
			class_title = class_id
		var description := _dict_text(class_data, ["description", "desc", "info"])
		var button := Button.new()
		button.text = class_title
		if description != "":
			button.text = class_title + "\n" + description
		button.custom_minimum_size = Vector2(0.0, 62.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_class_button_pressed.bind(class_id))
		_apply_button_style(button, false)
		_class_list.add_child(button)
		_class_buttons[class_id] = button
	_update_class_button_styles()


func _rebuild_weapon_buttons() -> void:
	if _weapon_list == null:
		return
	_clear_children(_weapon_list)
	_weapon_buttons.clear()
	var indices := _available_weapon_indices()
	for index: Variant in indices:
		var weapon_index := int(index)
		if weapon_index < 0 or weapon_index >= _deploy_weapons.size():
			continue
		if not (_deploy_weapons[weapon_index] is Dictionary):
			continue
		var weapon_data: Dictionary = _deploy_weapons[weapon_index]
		var weapon_name := _dict_text(weapon_data, ["name", "display_name", "id"])
		if weapon_name == "":
			weapon_name = "武器 %d" % (weapon_index + 1)
		var weapon_type := _dict_text(weapon_data, ["type", "weapon_type", "category", "class"])
		var button := Button.new()
		button.text = weapon_name
		if weapon_type != "":
			button.text = weapon_name + "\n" + weapon_type
		button.custom_minimum_size = Vector2(0.0, 56.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_meta("weapon_index", weapon_index)
		button.pressed.connect(_on_weapon_button_pressed.bind(weapon_index))
		_apply_button_style(button, false)
		_weapon_list.add_child(button)
		_weapon_buttons.append(button)
	if _weapon_buttons.is_empty():
		var empty := Label.new()
		empty.text = "无可用武器"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75, 1.0))
		_weapon_list.add_child(empty)
	_update_weapon_button_styles()


func _rebuild_spawn_buttons() -> void:
	if _spawn_list == null:
		return
	_clear_children(_spawn_list)
	_spawn_buttons.clear()
	for i in _deploy_spawns.size():
		var button := Button.new()
		if i == 0:
			button.text = "基地部署点"
		else:
			button.text = "已占领据点 %d" % i
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_spawn_button_pressed.bind(i))
		_apply_button_style(button, false)
		_spawn_list.add_child(button)
		_spawn_buttons.append(button)
	_update_spawn_button_styles()


func _update_class_button_styles() -> void:
	for class_id in _class_buttons:
		var button: Button = _class_buttons[class_id]
		_apply_button_style(button, class_id == _selected_class)


func _update_weapon_button_styles() -> void:
	for weapon_button: Button in _weapon_buttons:
		var weapon_index: int = int(weapon_button.get_meta("weapon_index", -1))
		_apply_button_style(weapon_button, weapon_index == _selected_weapon_index)


func _update_spawn_button_styles() -> void:
	for i in _spawn_buttons.size():
		var spawn_button: Button = _spawn_buttons[i]
		_apply_button_style(spawn_button, i == _selected_spawn_index)


func _available_weapon_indices() -> Array:
	var result: Array = []
	if _selected_class == "":
		return result
	var class_data := _get_class_data(_selected_class)
	var primary := _index_array(class_data, ["primary_indices", "primary", "primaries"])
	var secondary := _index_array(class_data, ["secondary_indices", "secondary", "secondaries"])
	for index: Variant in primary:
		_append_weapon_index(result, int(index))
	for index: Variant in secondary:
		_append_weapon_index(result, int(index))
	return result


func _append_weapon_index(indices: Array, index: int) -> void:
	if index >= 0 and index < _deploy_weapons.size() and not indices.has(index):
		indices.append(index)


func _default_weapon_index() -> int:
	var class_data := _get_class_data(_selected_class)
	var primary := _index_array(class_data, ["primary_indices", "primary", "primaries"])
	if primary.size() > 0:
		return int(primary[0])
	var secondary := _index_array(class_data, ["secondary_indices", "secondary", "secondaries"])
	if secondary.size() > 0:
		return int(secondary[0])
	return -1


func _get_class_data(class_id: String) -> Dictionary:
	for entry in _deploy_classes:
		if entry is Dictionary:
			var class_data: Dictionary = entry
			if _dict_text(class_data, ["id", "class_id", "class"]) == class_id:
				return class_data
	return {}


func _dict_text(data: Dictionary, keys: Array) -> String:
	for key: Variant in keys:
		if data.has(key):
			return String(data[key])
	return ""


func _index_array(data: Dictionary, keys: Array) -> Array:
	for key: Variant in keys:
		if data.has(key):
			var raw: Variant = data[key]
			if raw is Array:
				return raw.duplicate()
			var result: Array = []
			if raw is PackedInt32Array:
				for item: Variant in raw:
					result.append(item)
				return result
			return [raw]
	return []


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _apply_button_style(button: Button, selected: bool) -> void:
	var normal := _make_style(Color(0.05, 0.08, 0.12, 0.92), Color(0.25, 0.45, 0.65, 0.55), 4)
	var hover := _make_style(Color(0.09, 0.15, 0.22, 0.95), Color(0.35, 0.65, 0.95, 0.8), 4)
	var pressed := _make_style(Color(0.1, 0.2, 0.28, 1.0), Color(0.45, 0.85, 1.0, 0.9), 4)
	var focus := _make_style(Color(0.07, 0.12, 0.18, 0.95), Color(0.4, 0.8, 1.0, 0.7), 4)
	if selected:
		normal = _make_style(Color(0.08, 0.28, 0.42, 1.0), Color(0.42, 0.85, 1.0, 0.95), 4)
		hover = normal
		pressed = _make_style(Color(0.1, 0.34, 0.5, 1.0), Color(0.5, 0.9, 1.0, 1.0), 4)
		focus = normal
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 15)


func _update_capture_bars(delta: float) -> void:
	for zone_id in _zone_bars:
		var bar: ProgressBar = _zone_bars[zone_id]
		var target := float(_zone_targets.get(zone_id, 0.0))
		bar.value = lerpf(bar.value, target, minf(delta * 8.0, 1.0))


func _update_capture_from_state(state: Dictionary) -> void:
	var zones: Variant = state.get("capture_zones", null)
	if zones == null:
		zones = state.get("captures", null)
	if zones == null:
		zones = state.get("zones", null)
	if zones == null:
		return
	if zones is Dictionary:
		for zone_id in zones:
			_apply_zone_value(String(zone_id), zones[zone_id])
	elif zones is Array:
		for zone in zones:
			if zone is Dictionary:
				_apply_zone_value(String(zone.get("id", "?")), zone)


func _apply_zone_value(zone_id: String, value: Variant) -> void:
	if not _zone_bars.has(zone_id):
		return
	var progress := 0.0
	var team := ""
	if value is Dictionary:
		progress = float(value.get("progress", value.get("value", 0.0)))
		team = String(value.get("team", value.get("controlling_team", "")))
	else:
		progress = float(value)
	if progress > 1.0:
		progress /= 100.0
	progress = clampf(progress, 0.0, 1.0)
	_zone_targets[zone_id] = progress * 100.0
	var current_team := String(_zone_teams.get(zone_id, ""))
	if team != current_team:
		_zone_teams[zone_id] = team
		var fill := _zone_neutral_fill
		if team == "blue" or team == "ally" or team == "player" or team == "盟军":
			fill = _zone_blue_fill
		elif team == "red" or team == "enemy" or team == "红军":
			fill = _zone_red_fill
		var bar: ProgressBar = _zone_bars[zone_id]
		bar.add_theme_stylebox_override("fill", fill)
		var label: Label = _zone_labels[zone_id]
		if fill == _zone_blue_fill:
			label.modulate = Color(0.5, 0.8, 1.0, 1.0)
		elif fill == _zone_red_fill:
			label.modulate = Color(1.0, 0.55, 0.5, 1.0)
		else:
			label.modulate = Color.WHITE


func _update_feed_from_state(state: Dictionary) -> void:
	var feed: Variant = state.get("kill_feed", null)
	if feed == null:
		return
	if feed is Array:
		var feed_array: Array = feed as Array
		var size: int = feed_array.size()
		var start := 0
		if _last_feed_entry != null and size > 0:
			var found := _find_feed_entry(feed_array, _last_feed_entry)
			if found >= 0:
				start = found + 1
		for i in range(start, size):
			_add_feed_entry(feed_array[i])
	elif feed is String:
		var text := String(feed)
		if text != "" and text != _last_feed_text:
			_add_feed_entry(text)
			_last_feed_text = text


func _find_feed_entry(feed: Array, entry: Variant) -> int:
	for i in range(feed.size() - 1, -1, -1):
		if feed[i] == entry:
			return i
	return -1


func _add_feed_entry(entry: Variant) -> void:
	var text := ""
	var color := Color(0.92, 0.96, 1.0, 0.95)
	if entry is Dictionary:
		var entry_dict: Dictionary = entry
		if entry_dict.has("text"):
			text = String(entry_dict["text"])
		else:
			var killer := String(entry_dict.get("killer", ""))
			var victim := String(entry_dict.get("victim", ""))
			var weapon := String(entry_dict.get("weapon", ""))
			text = killer + " 击杀 " + victim
			if weapon != "":
				text += " - " + weapon
		if entry_dict.has("color") and entry_dict["color"] is Color:
			color = entry_dict["color"]
	elif entry is String:
		text = String(entry)
	if text == "":
		return
	_last_feed_entry = entry
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_stylebox_override("normal", _feed_style)
	label.modulate = color
	_feed_box.add_child(label)
	_feed_box.move_child(label, 0)
	_feed_items.append({"label": label, "age": 0.0})
	while _feed_items.size() > 6:
		var oldest: Dictionary = _feed_items.pop_front()
		if is_instance_valid(oldest["label"]):
			oldest["label"].queue_free()


func _update_feed(delta: float) -> void:
	for i in range(_feed_items.size() - 1, -1, -1):
		var item: Dictionary = _feed_items[i]
		var age := float(item["age"]) + delta
		item["age"] = age
		var label: Label = item["label"]
		if is_instance_valid(label):
			label.modulate.a = clampf((5.0 - age) / 0.5, 0.0, 1.0)
		if age >= 5.0:
			if is_instance_valid(label):
				label.queue_free()
			_feed_items.remove_at(i)


func _update_damage_numbers(delta: float) -> void:
	for i in _damage_numbers.size():
		var remaining: float = maxf(float(_damage_number_timers[i]) - delta, 0.0)
		_damage_number_timers[i] = remaining
		var label: Label = _damage_numbers[i]
		if remaining > 0.0:
			label.position.y -= 24.0 * delta
			label.modulate.a = clampf(remaining / 1.0, 0.0, 1.0)
		else:
			label.visible = false


func _format_ammo(reloading: bool) -> String:
	if reloading:
		return "装填中..."
	return "%d / %d" % [_ammo, _reserve]


func _localize_weapon(name: String) -> String:
	if name == "assault_rifle" or name == "rifle":
		return "突击步枪"
	if name == "smg":
		return "冲锋枪"
	if name == "sniper" or name == "sniper_rifle" or name == "marksman":
		return "狙击步枪"
	if name == "pistol":
		return "手枪"
	if name == "shotgun":
		return "霰弹枪"
	if name == "rocket" or name == "launcher" or name == "rpg":
		return "火箭筒"
	return name


func _winner_text(winner: String) -> String:
	if winner == "blue" or winner == "ally" or winner == "盟军":
		return "蓝军获胜"
	if winner == "red" or winner == "enemy" or winner == "红军":
		return "红军获胜"
	if winner == "draw" or winner == "tie" or winner == "平局":
		return "平局"
	return "战斗结束：%s" % winner


func _make_style(bg: Color, border: Color, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


func _make_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style
