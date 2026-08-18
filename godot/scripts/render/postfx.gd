extends WorldEnvironment
## Applies the WorldEnvironment, tonemapping, fog, SSAO, glow, MSAA,
## shadow distance, and vignette settings for a quality tier.

var _quality := "high"
var _sky: Sky
var _sun: DirectionalLight3D
var _fog_light := Color(0.80, 0.86, 0.92)
var _fog_density_scale := 1.0


func _ready() -> void:
	if environment == null:
		environment = Environment.new()
	set_quality(_quality)


func setup(sky: Sky, sun: DirectionalLight3D, quality: String) -> void:
	_sky = sky
	_sun = sun
	if environment == null:
		environment = Environment.new()
	_configure_base_environment()
	set_quality(quality)


func set_quality(quality: String) -> void:
	if quality == "low" or quality == "medium" or quality == "high" or quality == "ultra":
		_quality = quality
	var env := environment
	if env == null:
		return
	_configure_base_environment()

	match _quality:
		"low":
			_apply_fog_density(env)
			env.fog_sky_affect = 0.5
			env.ssao_enabled = false
			env.ssr_enabled = false
			env.glow_enabled = false
			env.glow_intensity = 0.0
			env.volumetric_fog_enabled = false
		"medium":
			_apply_fog_density(env)
			env.fog_sky_affect = 0.3
			env.ssao_enabled = false
			env.ssr_enabled = false
			env.glow_enabled = true
			env.glow_intensity = 0.35
			env.volumetric_fog_enabled = true
		"high":
			_apply_fog_density(env)
			env.fog_sky_affect = 0.22
			env.ssao_enabled = true
			env.ssr_enabled = false
			env.glow_enabled = true
			env.glow_intensity = 0.45
			env.volumetric_fog_enabled = true
		"ultra":
			_apply_fog_density(env)
			env.fog_sky_affect = 0.18
			env.ssao_enabled = true
			env.ssr_enabled = true
			env.glow_enabled = true
			env.glow_intensity = 0.62
			env.volumetric_fog_enabled = true

	env.fog_light_color = _fog_light
	env.volumetric_fog_albedo = _fog_light
	_apply_viewport_aa()

	if _sun != null:
		match _quality:
			"low":
				_sun.directional_shadow_max_distance = 70.0
			"medium":
				_sun.directional_shadow_max_distance = 130.0
			"high":
				_sun.directional_shadow_max_distance = 190.0
			"ultra":
				_sun.directional_shadow_max_distance = 280.0


func _apply_viewport_aa() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	match _quality:
		"low":
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"medium":
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"high", "ultra":
			viewport.msaa_3d = Viewport.MSAA_4X
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func update_time(time_of_day: float) -> void:
	var env := environment
	if env == null:
		return
	var daylight := clampf(sin((time_of_day - 0.25) * TAU), 0.0, 1.0)
	var night_fog := _fog_light.darkened(0.72)
	env.ambient_light_energy = lerpf(0.22, 1.0, daylight)
	env.fog_light_color = night_fog.lerp(_fog_light, daylight)
	env.fog_light_energy = lerpf(0.18, 1.0, daylight)
	env.fog_sun_scatter = lerpf(0.04, 0.38, daylight)
	env.volumetric_fog_albedo = env.fog_light_color


func set_map_theme(theme: Dictionary) -> void:
	_fog_light = theme.get("fog_light", _fog_light)
	_fog_density_scale = theme.get("fog_density_scale", _fog_density_scale)
	var env := environment
	if env == null:
		return
	env.fog_light_color = _fog_light
	env.volumetric_fog_albedo = _fog_light
	_apply_fog_density(env)


func _base_fog_density(quality: String) -> float:
	match quality:
		"low":
			return 0.007
		"medium":
			return 0.0035
		"high":
			return 0.0018
		"ultra":
			return 0.0012
	return 0.0018


func _apply_fog_density(env: Environment) -> void:
	env.fog_density = _base_fog_density(_quality) * _fog_density_scale
	match _quality:
		"medium":
			env.volumetric_fog_density = 0.04 * _fog_density_scale
		"high":
			env.volumetric_fog_density = 0.025 * _fog_density_scale
		"ultra":
			env.volumetric_fog_density = 0.015 * _fog_density_scale


func get_quality() -> String:
	return _quality


func _configure_base_environment() -> void:
	var env := environment
	if env == null:
		return
	env.background_mode = Environment.BG_SKY if _sky != null else Environment.BG_COLOR
	if _sky != null:
		env.sky = _sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02

	env.fog_enabled = true
	env.fog_aerial_perspective = 0.15
	env.fog_sun_scatter = 0.35
	env.fog_light_color = _fog_light

	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.ssao_radius = 0.9
	env.ssao_intensity = 1.4

	env.volumetric_fog_albedo = _fog_light
	env.volumetric_fog_emission = Color(0.8, 0.72, 0.5)
	env.volumetric_fog_emission_energy = 0.7
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 3.0
	env.volumetric_fog_ambient_inject = 0.6
	env.volumetric_fog_sky_affect = 0.25

	env.adjustment_enabled = true
	env.adjustment_brightness = 0.98
	env.adjustment_contrast = 1.22
	env.adjustment_saturation = 1.35
