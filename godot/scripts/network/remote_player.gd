extends Node3D

var health := 100
var marker := 0
var display_name := "Remote"
var _label: Label3D


func _ready() -> void:
	add_to_group("remote_players")
	_create_visuals()


func get_network_snapshot() -> Dictionary:
	return {
		"position": global_position,
		"yaw": rotation.y,
		"health": health,
		"marker": marker,
		"display_name": display_name,
	}


func apply_network_snapshot(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("position") and state["position"] is Vector3:
		global_position = state["position"]
	if state.has("yaw") and state["yaw"] != null:
		rotation.y = float(state["yaw"])
	if state.has("health") and state["health"] != null:
		health = int(state["health"])
	if state.has("marker") and state["marker"] != null:
		marker = int(state["marker"])
	if state.has("display_name") and state["display_name"] != null:
		set_display_name(str(state["display_name"]))


func set_display_name(value: String) -> void:
	display_name = value
	if _label != null and is_instance_valid(_label):
		_label.text = display_name


func _create_visuals() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.55, 0.85)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = capsule
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(0, 0.9, 0)
	add_child(mesh_instance)

	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 64
	_label.pixel_size = 0.01
	_label.position = Vector3(0, 2.0, 0)
	add_child(_label)
