extends Node3D

var vehicle_type := "jeep"
var health := 220.0
var marker := 0
var display_name := "Remote Vehicle"
var _label: Label3D
var _anim_speed := 0.0
var _anim_throttle := 0.0
var _anim_steer := 0.0


func _ready() -> void:
	add_to_group("remote_vehicles")
	_create_visuals()


func get_network_snapshot() -> Dictionary:
	return {
		"position": global_position,
		"yaw": rotation.y,
		"health": health,
		"marker": marker,
		"display_name": display_name,
		"vehicle_type": vehicle_type,
		"animation": {
			"speed": _anim_speed,
			"throttle": _anim_throttle,
			"steer": _anim_steer,
		},
	}


func apply_network_snapshot(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("position") and state["position"] is Vector3:
		global_position = state["position"]
	if state.has("yaw") and state["yaw"] != null:
		rotation.y = float(state["yaw"])
	if state.has("health") and state["health"] != null:
		health = float(state["health"])
	if state.has("marker") and state["marker"] != null:
		marker = int(state["marker"])
	if state.has("display_name") and state["display_name"] != null:
		set_display_name(str(state["display_name"]))
	if state.has("vehicle_type") and state["vehicle_type"] != null:
		var new_type := str(state["vehicle_type"])
		if new_type != vehicle_type:
			vehicle_type = new_type
			_create_visuals()
	if not (state.has("animation") and state["animation"] is Dictionary):
		return
	var animation: Dictionary = state["animation"]
	if animation.has("speed") and animation["speed"] != null:
		_anim_speed = float(animation["speed"])
	if animation.has("throttle") and animation["throttle"] != null:
		_anim_throttle = float(animation["throttle"])
	if animation.has("steer") and animation["steer"] != null:
		_anim_steer = float(animation["steer"])


func set_display_name(value: String) -> void:
	display_name = value
	if _label != null and is_instance_valid(_label):
		_label.text = display_name


func _create_visuals() -> void:
	for child in get_children():
		child.queue_free()
	_label = null
	match vehicle_type:
		"tank":
			_add_box_visual(Vector3(3.2, 1.6, 6.0), Vector3(0.0, 0.8, 0.0), Color(0.25, 0.4, 0.25))
			_add_box_visual(Vector3(1.8, 0.5, 2.6), Vector3(0.0, 1.85, -0.5), Color(0.25, 0.4, 0.25))
		_:
			_add_box_visual(Vector3(2.2, 1.0, 4.5), Vector3(0.0, 0.5, 0.0), Color(0.35, 0.45, 0.55))

	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 64
	_label.pixel_size = 0.01
	_label.position = Vector3(0.0, 2.6, 0.0)
	add_child(_label)


func _add_box_visual(size: Vector3, position: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	add_child(mesh_instance)
