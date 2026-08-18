extends Node

# Profile save system for Battlefield 2035.
# Stores the local player profile as JSON under the user data directory.

signal save_completed(path: String)
signal load_completed(data: Dictionary)

const SAVE_FILENAME: String = "battlefield2035_profile.json"

var _save_path: String = ""


func _ready() -> void:
	_save_path = "user://" + SAVE_FILENAME


func get_save_path() -> String:
	return _save_path


func save_profile(data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		return false
	var json_text: String = JSON.stringify(data)
	file.store_string(json_text)
	var success: bool = file.get_error() == OK
	file.close()
	if not success:
		return false
	save_completed.emit(_save_path)
	return true


func load_profile() -> Dictionary:
	if not FileAccess.file_exists(_save_path):
		return {}
	var json_text: String = FileAccess.get_file_as_string(_save_path)
	var json := JSON.new()
	var parse_error: Error = json.parse(json_text)
	if parse_error != OK:
		return {}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary = parsed
	load_completed.emit(result)
	return result


func clear_profile() -> void:
	if FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(_save_path)
