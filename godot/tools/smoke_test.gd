extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _elapsed := 0.0
var _game: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = MAIN_SCENE.instantiate()
	add_child(_game)
	get_tree().paused = false


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 6.0:
		print("[SmokeTest] passed")
		get_tree().quit(0)
