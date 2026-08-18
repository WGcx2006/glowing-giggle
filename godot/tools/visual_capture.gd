extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")
const OUTPUT_DIR := "res://screenshots"

var _shots := [
	{
		"name": "godot-aerial-ultra",
		"position": Vector3(0.0, 58.0, 104.0),
		"look": Vector3(2.0, 4.0, -42.0),
		"fov": 62.0,
	},
	{
		"name": "godot-combat-ultra",
		"position": Vector3(-58.0, 2.2, 68.0),
		"look": Vector3(34.0, 1.8, -12.0),
		"fov": 72.0,
	},
	{
		"name": "godot-hero-ultra",
		"position": Vector3(12.0, 2.0, 76.0),
		"look": Vector3(-42.0, 1.4, -36.0),
		"fov": 66.0,
	},
	{
		"name": "godot-sunset-ultra",
		"position": Vector3(-118.0, 4.5, -118.0),
		"look": Vector3(22.0, 1.2, 34.0),
		"fov": 70.0,
	},
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var game := MAIN_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var capture_camera := Camera3D.new()
	capture_camera.name = "CaptureCamera"
	add_child(capture_camera)
	capture_camera.make_current()

	if game.has_method("get_hud"):
		game.get_hud().set_hud_visible(false)
	if game.has_method("get_environment"):
		game.get_environment().set_quality("ultra")

	for shot in _shots:
		var from: Vector3 = shot["position"]
		var target: Vector3 = shot["look"]
		capture_camera.global_position = from
		capture_camera.look_at(target, Vector3.UP)
		capture_camera.fov = shot["fov"]
		await _wait_frames(18)
		var image := get_viewport().get_texture().get_image()
		if image == null:
			print("[VisualCapture] headless 模式无法截屏，跳过 %s" % shot["name"])
			continue
		var path := "%s/%s.png" % [OUTPUT_DIR, shot["name"]]
		image.save_png(path)
		print("[VisualCapture] saved %s" % path)

	print("[VisualCapture] done")
	get_tree().quit(0)


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
