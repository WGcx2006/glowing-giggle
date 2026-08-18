extends Node3D

const MAIN_SCENE := preload("res://scenes/main.tscn")
const EXPECTED_IDS: Array[String] = [
	"arctic",
	"desert",
	"jungle",
	"urban",
	"coast",
	"night_ops",
]

var _game
var _failed: Array[String] = []


func _ready() -> void:
	_game = MAIN_SCENE.instantiate()
	add_child(_game)
	await _wait_frames(3)
	await _run_theme_checks()
	if _failed.is_empty():
		print("[ThemeTest] passed")
		get_tree().quit(0)
	else:
		for entry in _failed:
			print("[ThemeTest] FAILED: %s" % entry)
		print("[ThemeTest] failed")
		get_tree().quit(1)


func _run_theme_checks() -> void:
	var env = _game.get_environment()
	if env == null or not is_instance_valid(env):
		_failed.append("get_environment() 返回空或无效节点")
		return
	if not env.has_method("get_map_themes") or not env.has_method("get_current_map_theme"):
		_failed.append("environment 缺少 get_map_themes()/get_current_map_theme()")
		return

	_verify_theme_ids(env)
	_verify_initial_theme(env)

	var signatures: Array[String] = []
	for theme_id: String in EXPECTED_IDS:
		_game.set_map_theme(theme_id)
		await _wait_frames(2)
		_verify_theme_state(theme_id, env)
		var signature: String = _capture_signature(env)
		signatures.append(signature)
		print("[ThemeTest] %s signature=%s" % [theme_id, signature])
	_verify_signatures(signatures)


func _verify_theme_ids(env) -> void:
	var themes: Array = env.get_map_themes()
	if themes.size() != EXPECTED_IDS.size():
		_failed.append("get_map_themes() 返回 %d 个主题，期望 %d" % [themes.size(), EXPECTED_IDS.size()])
		return
	var found: Array[String] = []
	for item in themes:
		var theme: Dictionary = item
		found.append(str(theme.get("id", "")))
	var expected: Array[String] = EXPECTED_IDS.duplicate()
	expected.sort()
	found.sort()
	if found != expected:
		_failed.append("主题 id 集合不符，实际 %s，期望 %s" % [str(found), str(expected)])


func _verify_initial_theme(env) -> void:
	var game_theme: String = _game.get_map_theme()
	var env_theme: String = env.get_current_map_theme()
	if game_theme != "arctic":
		_failed.append("初始 game.get_map_theme() 为 %s，期望 arctic" % game_theme)
	if env_theme != "arctic":
		_failed.append("初始 env.get_current_map_theme() 为 %s，期望 arctic" % env_theme)


func _verify_theme_state(theme_id: String, env) -> void:
	var game_theme: String = _game.get_map_theme()
	var env_theme: String = env.get_current_map_theme()
	if game_theme != theme_id:
		_failed.append("切换 %s 后 game.get_map_theme() 为 %s" % [theme_id, game_theme])
	if env_theme != theme_id:
		_failed.append("切换 %s 后 env.get_current_map_theme() 为 %s" % [theme_id, env_theme])


func _capture_signature(env) -> String:
	var sky: Node = env.get_node("Sky")
	var sky_material = sky.sky_material
	var sky_top: Color = sky_material.sky_top_color
	var sun_node = sky.sun
	var light_energy: float = sun_node.light_energy
	var postfx: Node = env.get_node("PostFX")
	var postfx_env = postfx.environment
	var fog_light: Color = postfx_env.fog_light_color
	return "sky_top=%s sun_energy=%.4f fog_light=%s" % [
		sky_top.to_html(false),
		light_energy,
		fog_light.to_html(false),
	]


func _verify_signatures(signatures: Array[String]) -> void:
	var unique: Dictionary = {}
	for signature: String in signatures:
		unique[signature] = true
	if unique.size() < 5:
		_failed.append("视觉签名唯一数 %d，期望至少 5 个" % unique.size())


func _wait_frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
