extends Node3D
## Dynamic procedural sky and cascaded sun for the battlefield.

const MAP_THEME_SCRIPT := preload("res://scripts/render/map_theme.gd")

var sun: DirectionalLight3D
var sky: Sky
var sky_material: ProceduralSkyMaterial
var _time_of_day := 0.48
var _built := false
var _theme_top := Color(0.16, 0.30, 0.48)
var _theme_horizon := Color(0.82, 0.88, 0.93)
var _theme_ground := Color(0.25, 0.31, 0.36)
var _theme_sun_color := Color(1.0, 0.93, 0.84)
var _theme_sun_energy := 0.95
var _theme_time_of_day := 0.34


func _ready() -> void:
	setup()


func setup() -> void:
	if _built:
		return
	_built = true
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 6.0
	sky_material.sun_curve = 0.9

	sky = Sky.new()
	sky.sky_material = sky_material

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.16
	sun.directional_shadow_split_2 = 0.36
	sun.directional_shadow_split_3 = 0.72
	add_child(sun)

	set_map_theme(MAP_THEME_SCRIPT.get_theme("arctic"))


func set_map_theme(theme: Dictionary) -> void:
	_theme_top = theme.get("sky_top", _theme_top)
	_theme_horizon = theme.get("sky_horizon", _theme_horizon)
	_theme_ground = theme.get("ground_bottom", _theme_ground)
	_theme_sun_color = theme.get("sun_color", _theme_sun_color)
	_theme_sun_energy = theme.get("sun_energy", _theme_sun_energy)
	_theme_time_of_day = theme.get("time_of_day", _theme_time_of_day)
	if _built:
		update(_theme_time_of_day, 0.0)


func update(time_of_day: float, delta: float) -> void:
	_time_of_day = time_of_day
	var sun_angle := (time_of_day - 0.25) * TAU
	var elevation := sin(sun_angle) * 52.0
	var daylight := clampf(sin(sun_angle), 0.0, 1.0)

	sun.rotation_degrees = Vector3(-elevation, (0.5 - time_of_day) * 360.0, 0.0)
	sun.light_color = _theme_sun_color
	sun.light_energy = _theme_sun_energy * lerpf(0.12, 1.0, daylight)

	var night_top := _theme_top.darkened(0.55)
	var night_horizon := _theme_horizon.darkened(0.58)
	var night_ground := _theme_ground.darkened(0.5)
	sky_material.sky_top_color = night_top.lerp(_theme_top, daylight)
	sky_material.sky_horizon_color = night_horizon.lerp(_theme_horizon, daylight)
	sky_material.ground_bottom_color = night_ground.lerp(_theme_ground, daylight)
	sky_material.energy_multiplier = lerpf(0.14, 0.9, daylight)


func get_sun() -> DirectionalLight3D:
	return sun


func get_sky() -> Sky:
	return sky
