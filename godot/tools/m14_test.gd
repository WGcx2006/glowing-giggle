extends Node3D

const GAME_MODE_SCRIPT := preload("res://scripts/game/game_mode.gd")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const AUDIO_SCRIPT := preload("res://scripts/audio/audio_manager.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

class CaptureZoneStub:
	extends RefCounted

	var state: Dictionary = {
		"blue_captured": 0,
		"red_captured": 0,
		"total": 4,
	}

	func get_control_state() -> Dictionary:
		return state

	func reset_zones() -> void:
		state = {
			"blue_captured": 0,
			"red_captured": 0,
			"total": 4,
		}


var _failed: Array[String] = []
var _game: Node3D
var _phase := 0
var _frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_test_game_mode()
	_test_hud()
	_test_audio()
	_game = MAIN_SCENE.instantiate()
	add_child(_game)


func _physics_process(_delta: float) -> void:
	match _phase:
		0:
			if _game == null or _game.get_game_mode() == null:
				return
			var loadout := {
				"class_id": "assault",
				"primary_index": 0,
				"secondary_index": 1,
			}
			_game.call("_on_deploy_requested", loadout, 0)
			var state: Dictionary = _game.get_game_mode().get_state()
			_check(
				int(state.get("blue_tickets", -1)) == 100
					and int(state.get("red_tickets", -1)) == 100,
				"主流程部署后票数不是 100/100"
			)
			_game.call("_on_enemy_killed", "red", "Bot")
			state = _game.get_game_mode().get_state()
			_check(int(state.get("red_tickets", -1)) == 99, "主流程击杀红方后红方票数不是 99")
			_game.call("_on_player_died")
			state = _game.get_game_mode().get_state()
			_check(int(state.get("blue_tickets", -1)) == 99, "主流程玩家阵亡后蓝方票数不是 99")
			var hud_state: Dictionary = _game.call("_build_hud_state")
			_check(hud_state.has("game_mode"), "主流程 HUD 状态缺少 game_mode")
			_phase = 1
			_frames = 0
		1:
			_frames += 1
			if _frames >= 5:
				_finish()


func _test_game_mode() -> void:
	var stub := CaptureZoneStub.new()
	var mode = GAME_MODE_SCRIPT.new()
	mode.setup(null, null, stub)
	var state: Dictionary = mode.get_state()
	_check(int(state.get("blue_tickets", -1)) == 100, "GameMode 初始蓝方票数不是 100")
	_check(int(state.get("red_tickets", -1)) == 100, "GameMode 初始红方票数不是 100")
	_check(bool(state.get("active", false)), "GameMode 初始 active 不是 true")

	mode.on_enemy_killed("red")
	state = mode.get_state()
	_check(int(state.get("red_tickets", -1)) == 99, "击杀红方后红方票数不是 99")
	mode.on_player_died()
	state = mode.get_state()
	_check(int(state.get("blue_tickets", -1)) == 99, "玩家阵亡后蓝方票数不是 99")

	stub.state = {
		"blue_captured": 2,
		"red_captured": 0,
		"total": 4,
	}
	mode.update(1.0)
	state = mode.get_state()
	_check(int(state.get("red_tickets", -1)) == 98, "双据点流血后红方票数不是 98")

	var winners: Array[String] = []
	mode.game_over.connect(func(winner: String): winners.append(winner))
	for i in 100:
		mode.on_enemy_killed("red")
	_check(winners.size() == 1 and winners[0] == "blue", "红方票数归零未触发 blue 胜利")

	winners.clear()
	mode.restart()
	mode.update(601.0)
	_check(winners.size() == 1 and winners[0] == "draw", "同票数超时未触发 draw 胜利")
	mode.free()


func _test_hud() -> void:
	var hud = HUD_SCENE.instantiate()
	add_child(hud)
	var mode_state := {
		"blue_tickets": 80,
		"red_tickets": 64,
		"time_remaining": 125.0,
	}
	hud.update_state({"game_mode": mode_state})
	var score: String = hud.get_score_text()
	_check(
		score.contains("80") and score.contains("64") and score.contains("02:05"),
		"HUD 分数文本缺少 80/64/02:05：%s" % score
	)
	hud.show_game_over("blue", mode_state)
	var summary: String = hud.get_game_over_summary_text()
	_check(
		summary.contains("80") and summary.contains("64"),
		"HUD 结算文本缺少 80/64：%s" % summary
	)
	hud.get_parent().remove_child(hud)
	hud.free()


func _test_audio() -> void:
	var audio = AUDIO_SCRIPT.new()
	add_child(audio)
	_check(audio.has_method("play_capture_announce"), "AudioManager 缺少 play_capture_announce")
	_check(audio.has_method("play_round_end"), "AudioManager 缺少 play_round_end")
	audio.call("play_capture_announce", "blue")
	audio.call("play_round_end", "red")
	for child in audio.get_children():
		if child is AudioStreamPlayer3D:
			child.stop()
	audio.get_parent().remove_child(audio)
	audio.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed.append(message)


func _finish() -> void:
	if _failed.is_empty():
		print("[M14Test] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[M14Test] FAILED: %s" % entry)
		print("[M14Test] failed")
		get_tree().quit(1)
