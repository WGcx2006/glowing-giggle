extends Node3D

## Runtime weather state and precipitation emitters for Battlefield 2035.

enum WeatherType { CLEAR, RAIN, SNOW, FOG }

const RAIN_BASE_AMOUNT: int = 400
const SNOW_BASE_AMOUNT: int = 200
const EMISSION_EXTENTS: Vector3 = Vector3(30.0, 15.0, 30.0)
const FOG_SCALE: float = 0.012
const TRANSITION_RATE: float = 4.0

var _current: WeatherType = WeatherType.CLEAR
var _target: WeatherType = WeatherType.CLEAR
var _target_intensity: float = 0.0
var _intensity: float = 0.0
var _transition_speed: float = 0.25
var _rain_particles: CPUParticles3D
var _snow_particles: CPUParticles3D
var _fog_density: float = 0.0


func _ready() -> void:
	_rain_particles = _create_precipitation("Rain", true)
	_snow_particles = _create_precipitation("Snow", false)


func _process(delta: float) -> void:
	_follow_camera()
	var target := _target_intensity_for(_target, _target_intensity)
	var blend := 1.0 - exp(-delta * _transition_speed * TRANSITION_RATE)
	_intensity = lerpf(_intensity, target, blend)
	_fog_density = FOG_SCALE * _intensity
	_update_precipitation()


func set_weather(type: int, intensity: float = 1.0) -> void:
	if type >= WeatherType.CLEAR and type <= WeatherType.FOG:
		_target = type
	else:
		_target = WeatherType.CLEAR
	_current = _target
	_target_intensity = clampf(intensity, 0.0, 1.0)


func get_weather_state() -> Dictionary:
	var type_name := ""
	match _current:
		WeatherType.RAIN:
			type_name = "rain"
		WeatherType.SNOW:
			type_name = "snow"
		WeatherType.FOG:
			type_name = "fog"
		_:
			type_name = "clear"
	return {
		"type": type_name,
		"intensity": _intensity,
		"precipitation": _intensity > 0.05 and (
			_current == WeatherType.RAIN or _current == WeatherType.SNOW
		),
		"fog_density": _fog_density,
	}


func get_fog_density() -> float:
	return _fog_density


func _target_intensity_for(weather_type: int, requested: float) -> float:
	match weather_type:
		WeatherType.RAIN:
			return 1.0 * requested
		WeatherType.SNOW:
			return 1.0 * requested
		WeatherType.FOG:
			return 0.7 * requested
		_:
			return 0.0


func _update_precipitation() -> void:
	if _rain_particles == null or _snow_particles == null:
		return
	var emitting := _intensity > 0.05
	_rain_particles.emitting = emitting
	_snow_particles.emitting = emitting
	_rain_particles.amount = maxi(1, int(round(RAIN_BASE_AMOUNT * _intensity)))
	_snow_particles.amount = maxi(1, int(round(SNOW_BASE_AMOUNT * _intensity)))


func _follow_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	global_position = camera.global_position


func _create_precipitation(node_name: String, is_rain: bool) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.mesh = _make_mesh(is_rain)
	particles.material_override = _make_material(is_rain)
	particles.amount = RAIN_BASE_AMOUNT if is_rain else SNOW_BASE_AMOUNT
	particles.lifetime = 2.4 if is_rain else 5.5
	particles.lifetime_randomness = 0.12
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.randomness = 0.15
	particles.preprocess = 1.5
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = EMISSION_EXTENTS
	particles.direction = Vector3.DOWN
	particles.spread = 4.0 if is_rain else 16.0
	particles.initial_velocity_min = 14.0 if is_rain else 0.8
	particles.initial_velocity_max = 20.0 if is_rain else 1.8
	particles.gravity = Vector3(0.0, -34.0, 0.0) if is_rain else Vector3(0.0, -0.8, 0.0)
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 1.25
	particles.color = Color(0.8, 0.88, 1.0, 0.65) if is_rain else Color(0.95, 0.97, 1.0, 0.9)
	particles.visible = true
	particles.emitting = false
	add_child(particles)
	return particles


func _make_mesh(is_rain: bool) -> Mesh:
	if is_rain:
		var rain_mesh := BoxMesh.new()
		rain_mesh.size = Vector3(0.035, 0.18, 0.035)
		return rain_mesh
	var snow_mesh := SphereMesh.new()
	snow_mesh.radius = 0.06
	snow_mesh.height = 0.12
	snow_mesh.radial_segments = 6
	snow_mesh.rings = 3
	return snow_mesh


func _make_material(is_rain: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	material.albedo_color = Color(0.8, 0.88, 1.0, 0.65) if is_rain else Color(0.95, 0.97, 1.0, 0.9)
	return material
