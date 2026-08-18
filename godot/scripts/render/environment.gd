extends Node3D
## Runtime-assembled Battlefield 2035 environment: terrain, sky, sun, water,
## instanced props, key structures, point arrays, and quality tiers.

const WATER_LEVEL := 0.8
const MAP_THEME_SCRIPT := preload("res://scripts/render/map_theme.gd")
const WEATHER_SCRIPT := preload("res://scripts/render/weather.gd")

var _terrain
var _sky
var _postfx
var _weather
var _props_root: Node3D
var _water_material: ShaderMaterial
var _initialized := false
var _quality := "high"
var _time_of_day := 0.48
var _map_theme_id := "arctic"
var _map_theme: Dictionary = {}
var _last_camera: Camera3D
var _last_update_frame := -1
var _rng := RandomNumberGenerator.new()

var _spawn_points: Array[Vector3] = []
var _nav_points: Array[Vector3] = []
var _cover_points: Array[Vector3] = []
var _density_multimeshes: Array[MultiMesh] = []

var _building_anchors: Array[Vector2] = [
	Vector2(-78.0, 66.0),
	Vector2(46.0, 96.0),
	Vector2(-108.0, -108.0),
	Vector2(62.0, -74.0),
	Vector2(-104.0, -106.0),
	Vector2(-116.0, -98.0),
	Vector2(-100.0, -118.0),
]

var _spawn_local: Array[Vector2] = [
	Vector2(-78.0, 73.0),
	Vector2(-64.0, 74.0),
	Vector2(-8.0, 22.0),
	Vector2(46.0, 96.0),
	Vector2(36.0, 112.0),
	Vector2(84.0, -74.0),
	Vector2(44.0, -62.0),
	Vector2(-98.0, -102.0),
	Vector2(-112.0, -82.0),
	Vector2(10.0, -120.0),
	Vector2(6.0, 118.0),
	Vector2(-30.0, -8.0),
	Vector2(110.0, 20.0),
	Vector2(-20.0, 124.0),
]

var _nav_local: Array[Vector2] = [
	Vector2(-78.0, 73.0),
	Vector2(-64.0, 74.0),
	Vector2(46.0, 96.0),
	Vector2(36.0, 112.0),
	Vector2(84.0, -74.0),
	Vector2(44.0, -62.0),
	Vector2(-98.0, -102.0),
	Vector2(-112.0, -82.0),
	Vector2(-8.0, 22.0),
	Vector2(10.0, -120.0),
	Vector2(6.0, 118.0),
	Vector2(-30.0, -8.0),
	Vector2(110.0, 20.0),
	Vector2(-20.0, 124.0),
	Vector2(-104.0, -96.0),
	Vector2(20.0, 40.0),
	Vector2(-45.0, 20.0),
	Vector2(72.0, 60.0),
	Vector2(-90.0, -40.0),
	Vector2(0.0, -80.0),
	Vector2(-40.0, 90.0),
	Vector2(100.0, -20.0),
]

var _cover_local: Array[Vector2] = [
	Vector2(-78.0, 73.0),
	Vector2(-70.0, 60.0),
	Vector2(-64.0, 74.0),
	Vector2(42.0, 92.0),
	Vector2(52.0, 100.0),
	Vector2(36.0, 108.0),
	Vector2(80.0, -78.0),
	Vector2(62.0, -70.0),
	Vector2(48.0, -58.0),
	Vector2(-104.0, -100.0),
	Vector2(-114.0, -94.0),
	Vector2(-98.0, -112.0),
	Vector2(-8.0, 22.0),
	Vector2(20.0, 40.0),
	Vector2(-45.0, 20.0),
	Vector2(72.0, 60.0),
	Vector2(0.0, -80.0),
	Vector2(-40.0, 90.0),
	Vector2(100.0, -20.0),
	Vector2(110.0, 20.0),
	Vector2(-20.0, 124.0),
	Vector2(12.0, 92.0),
	Vector2(-56.0, 30.0),
	Vector2(92.0, 44.0),
]

var _vehicle_spots: Array[Vector2] = [
	Vector2(-52.0, 58.0),
	Vector2(-34.0, 36.0),
	Vector2(-10.0, 24.0),
	Vector2(14.0, 10.0),
	Vector2(38.0, -26.0),
	Vector2(60.0, -54.0),
	Vector2(84.0, -72.0),
	Vector2(-96.0, -96.0),
	Vector2(-74.0, -104.0),
	Vector2(28.0, 86.0),
]

var _vehicle_yaws: Array[float] = [
	0.8, 0.9, 1.0, 0.7, -1.0, -0.8, -0.9, 0.5, 0.3, 1.3,
]

var _block_spots: Array[Vector2] = [
	Vector2(-62.0, 70.0),
	Vector2(-50.0, 58.0),
	Vector2(-20.0, 34.0),
	Vector2(0.0, 18.0),
	Vector2(30.0, 0.0),
	Vector2(52.0, -44.0),
	Vector2(70.0, -62.0),
	Vector2(90.0, -84.0),
	Vector2(-90.0, -96.0),
	Vector2(-110.0, -90.0),
	Vector2(-102.0, -114.0),
	Vector2(30.0, 80.0),
	Vector2(58.0, 104.0),
	Vector2(-32.0, 106.0),
]

var _sandbag_anchors: Array[Vector2] = [
	Vector2(-68.0, 72.0),
	Vector2(44.0, 94.0),
	Vector2(80.0, -78.0),
	Vector2(-104.0, -102.0),
	Vector2(-8.0, 22.0),
	Vector2(20.0, 40.0),
	Vector2(-45.0, 20.0),
	Vector2(100.0, -20.0),
	Vector2(-20.0, 124.0),
]

var _sandbag_offsets: Array[Vector2] = [
	Vector2(-2.2, -0.8),
	Vector2(-0.7, -0.8),
	Vector2(0.7, -0.8),
	Vector2(2.2, -0.8),
]

var _bunker_spots: Array[Vector2] = [
	Vector2(-104.0, -106.0),
	Vector2(-116.0, -98.0),
	Vector2(-100.0, -118.0),
]


func _ready() -> void:
	_rng.seed = 2035
	setup()


func _process(delta: float) -> void:
	var camera := _last_camera
	if not is_instance_valid(camera):
		var viewport := get_viewport()
		if viewport != null:
			camera = viewport.get_camera_3d()
	_apply_update(delta, camera, _time_of_day)


func setup() -> void:
	if _initialized:
		return
	_initialized = true
	_rng.seed = 2035

	_terrain = _ensure_node("Terrain", "res://scripts/render/terrain.gd")
	_sky = _ensure_node("Sky", "res://scripts/render/sky.gd")
	_postfx = _ensure_node("PostFX", "res://scripts/render/postfx.gd")

	_terrain.setup()
	_sky.setup()
	var sky_resource := _sky.get_sky() as Sky
	var sun_node := _sky.get_sun() as DirectionalLight3D
	_postfx.setup(sky_resource, sun_node, _quality)

	_weather = WEATHER_SCRIPT.new()
	_weather.name = "Weather"
	add_child(_weather)

	_build_water()
	_build_props()
	_build_points()
	set_quality(_quality)
	set_map_theme(_map_theme_id)


func update(delta: float, camera: Camera3D, time_of_day: float) -> void:
	_apply_update(delta, camera, time_of_day)


func _apply_update(delta: float, camera: Camera3D, time_of_day: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_update_frame:
		return
	_last_update_frame = frame
	_time_of_day = time_of_day
	_last_camera = camera
	if _sky != null:
		_sky.update(time_of_day, delta)
	if _postfx != null:
		_postfx.update_time(time_of_day)
	if _water_material != null:
		_water_material.set_shader_parameter("time_of_day", time_of_day)


func terrain_height_at(pos: Vector3) -> float:
	if _terrain != null:
		return _terrain.height_at(pos)
	return 0.0


func get_spawn_points() -> Array[Vector3]:
	return _spawn_points


func get_nav_points() -> Array[Vector3]:
	return _nav_points


func get_cover_points() -> Array[Vector3]:
	return _cover_points


func set_quality(quality: String) -> void:
	if quality == "low" or quality == "medium" or quality == "high" or quality == "ultra":
		_quality = quality
	if _postfx != null:
		_postfx.set_quality(_quality)
	_apply_prop_density()


func get_quality() -> String:
	return _quality


func set_map_theme(theme_id: String) -> void:
	var theme: Dictionary = MAP_THEME_SCRIPT.get_theme(theme_id)
	if theme.is_empty() or theme.get("id", "") != theme_id:
		theme = MAP_THEME_SCRIPT.get_theme("arctic")
	_map_theme_id = theme.get("id", "arctic")
	_map_theme = theme
	_time_of_day = theme.get("time_of_day", _time_of_day)
	if _terrain != null:
		_terrain.set_map_theme(theme)
	if _sky != null:
		_sky.set_map_theme(theme)
	if _postfx != null:
		_postfx.set_map_theme(theme)
	_apply_water_theme(theme)


func get_map_themes() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for theme: Dictionary in MAP_THEME_SCRIPT.get_themes():
		summaries.append({
			"id": theme.get("id", ""),
			"name": theme.get("name", ""),
			"description": theme.get("description", ""),
			"weather": theme.get("weather", "clear"),
		})
	return summaries


func get_current_map_theme() -> String:
	return _map_theme_id


func get_sun() -> DirectionalLight3D:
	if _sky != null:
		return _sky.get_sun() as DirectionalLight3D
	return null


func get_world_environment() -> WorldEnvironment:
	if _postfx != null:
		return _postfx as WorldEnvironment
	return null


func set_weather(type: int, intensity: float = 1.0) -> void:
	if _weather != null:
		_weather.set_weather(type, intensity)


func get_weather_state() -> Dictionary:
	if _weather != null:
		return _weather.get_weather_state()
	return {
		"type": "clear",
		"intensity": 0.0,
		"precipitation": false,
		"fog_density": 0.0,
	}


func get_weather_fog_density() -> float:
	if _weather != null:
		return _weather.get_fog_density()
	return 0.0


func _ensure_node(node_name: String, script_path: String) -> Node:
	var node := get_node_or_null(node_name)
	if node == null:
		node = load(script_path).new()
		node.name = node_name
		add_child(node)
	return node


func _build_water() -> void:
	if get_node_or_null("Water") != null:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 300.0)
	plane.subdivide_width = 40
	plane.subdivide_depth = 60
	var material := ShaderMaterial.new()
	material.shader = _make_water_shader()
	_water_material = material
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.material_override = material
	water.position = Vector3(-112.0, WATER_LEVEL, 0.0)
	add_child(water)


func _make_water_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 shallow_color : source_color = vec3(0.10, 0.28, 0.38);
uniform vec3 deep_color : source_color = vec3(0.03, 0.10, 0.16);
uniform float wave_strength = 0.09;
uniform float alpha = 0.82;
uniform float time_of_day = 0.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_pos.x * 0.32 + TIME * 1.1) * 0.5
		+ sin(world_pos.z * 0.26 - TIME * 0.8) * 0.5;
	VERTEX.y += wave * wave_strength;
}

void fragment() {
	float wave = sin(world_pos.x * 0.55 + TIME * 1.3) * 0.5
		+ sin(world_pos.z * 0.42 - TIME * 1.0) * 0.5;
	float depth_fade = clamp((world_pos.x + 130.0) / 90.0, 0.0, 1.0);
	vec3 base = mix(deep_color, shallow_color, depth_fade);
	float daylight = clamp(sin((time_of_day - 0.25) * 6.2831853), 0.0, 1.0);
	vec3 col = base + vec3(0.015, 0.02, 0.025) * wave * (0.6 + daylight * 0.8);
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.45;
	NORMAL = normalize(NORMAL + vec3(
		sin(world_pos.z * 0.7 + TIME * 1.5) * 0.08,
		0.0,
		cos(world_pos.x * 0.7 + TIME * 1.2) * 0.08
	));
}
"""
	return shader


func _apply_water_theme(theme: Dictionary) -> void:
	if _water_material == null:
		return
	var water_color: Color = theme.get("water_color", Color(0.10, 0.28, 0.38))
	_water_material.set_shader_parameter("shallow_color", water_color)
	_water_material.set_shader_parameter("deep_color", water_color.darkened(0.45))


func _build_props() -> void:
	var existing := get_node_or_null("Props")
	if existing != null:
		_props_root = existing as Node3D
		return
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)

	_build_grass()
	_build_bushes()
	_build_trees()
	_build_boulders()
	_build_vehicles()
	_build_blocks_and_sandbags()
	_build_warehouse()
	_build_bridge()
	_build_watchtower()
	_build_bunkers()
	_build_markers()


func _build_grass() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.55, 0.7)
	var mat := _make_material(Color.WHITE, 1.0)
	mat.albedo_texture = _make_grass_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var count := 700
	var mm := _add_multimesh(plane, mat, count, true, "Grass")
	_density_multimeshes.append(mm)
	for i in range(count):
		var pos := _random_spot(5.0, 16.0)
		var yaw := _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3(0.0, 1.0, 0.0), yaw)
		basis = basis * Basis(Vector3(1.0, 0.0, 0.0), -PI / 2.0)
		basis = basis.scaled(Vector3(scale, scale, scale))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(pos.x, pos.y, pos.z)))
		var shade := _rng.randf_range(0.8, 1.1)
		mm.set_instance_color(i, Color(0.2 * shade, 0.5 * shade, 0.16 * shade, 1.0))


func _build_bushes() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := _make_material(Color(0.18, 0.34, 0.15), 0.9)
	mat.vertex_color_use_as_albedo = true

	var count := 120
	var mm := _add_multimesh(sphere, mat, count, true, "Bushes")
	_density_multimeshes.append(mm)
	for i in range(count):
		var pos := _random_spot(5.0, 18.0)
		var scale := _rng.randf_range(0.55, 1.2)
		var yaw := _rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3(0.0, 1.0, 0.0), yaw).scaled(
			Vector3(scale, scale * 0.75, scale)
		)
		mm.set_instance_transform(
			i,
			Transform3D(basis, Vector3(pos.x, pos.y + scale * 0.15, pos.z))
		)
		var shade := _rng.randf_range(0.75, 1.05)
		mm.set_instance_color(i, Color(0.18 * shade, 0.4 * shade, 0.13 * shade, 1.0))


func _build_trees() -> void:
	var mesh := _make_tree_mesh()
	var count := 60
	var mm := _add_multimesh(mesh, null, count, false, "Trees")
	_density_multimeshes.append(mm)
	for i in range(count):
		var pos := _random_spot(7.0, 22.0)
		var scale := _rng.randf_range(0.7, 1.5)
		var yaw := _rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3(0.0, 1.0, 0.0), yaw).scaled(Vector3(scale, scale, scale))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(pos.x, pos.y, pos.z)))


func _make_tree_mesh() -> ArrayMesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.22
	trunk.height = 2.2
	trunk.radial_segments = 6

	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.0
	canopy.bottom_radius = 1.7
	canopy.height = 2.6
	canopy.radial_segments = 7

	var tree_mesh := ArrayMesh.new()
	var trunk_st := SurfaceTool.new()
	trunk_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	trunk_st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0.0, 1.1, 0.0)))
	tree_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk_st.commit().surface_get_arrays(0))

	var canopy_st := SurfaceTool.new()
	canopy_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	canopy_st.append_from(canopy, 0, Transform3D(Basis(), Vector3(0.0, 3.3, 0.0)))
	tree_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, canopy_st.commit().surface_get_arrays(0))

	tree_mesh.surface_set_material(0, _make_material(Color(0.35, 0.26, 0.16), 1.0))
	tree_mesh.surface_set_material(1, _make_material(Color(0.20, 0.36, 0.16), 0.95))
	return tree_mesh


func _build_boulders() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 0.75
	sphere.radial_segments = 8
	sphere.rings = 5
	var mat := _make_material(Color(0.42, 0.40, 0.36), 0.95)
	mat.vertex_color_use_as_albedo = true

	var count := 80
	var mm := _add_multimesh(sphere, mat, count, true, "Boulders")
	_density_multimeshes.append(mm)
	var body := _make_static_body("BoulderCollision")
	for i in range(count):
		var pos := _random_spot(5.0, 14.0)
		var scale := _rng.randf_range(0.6, 1.8)
		var yaw := _rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3(0.0, 1.0, 0.0), yaw).scaled(
			Vector3(scale, scale * 0.75, scale)
		)
		var origin := Vector3(pos.x, pos.y + scale * 0.25, pos.z)
		mm.set_instance_transform(i, Transform3D(basis, origin))
		var shade := _rng.randf_range(0.85, 1.1)
		mm.set_instance_color(i, Color(0.42 * shade, 0.40 * shade, 0.36 * shade, 1.0))
		_add_box_collision(
			body,
			Vector3(scale, scale * 0.75, scale),
			Transform3D(Basis(Vector3(0.0, 1.0, 0.0), yaw), origin)
		)


func _build_vehicles() -> void:
	var mesh := _make_vehicle_mesh()
	mesh.surface_set_material(0, _make_material(Color(0.36, 0.34, 0.22), 0.9))
	var mm := _add_multimesh(mesh, null, _vehicle_spots.size(), false, "DestroyedVehicles")
	var body := _make_static_body("VehicleCollision")
	for i in range(_vehicle_spots.size()):
		var yaw := _vehicle_yaws[i]
		var pos := _ground_point(_vehicle_spots[i], 0.35)
		var basis := Basis(Vector3(0.0, 1.0, 0.0), yaw)
		mm.set_instance_transform(i, Transform3D(basis, pos))
		_add_box_collision(
			body,
			Vector3(2.6, 1.2, 1.3),
			Transform3D(basis, pos)
		)


func _make_vehicle_mesh() -> ArrayMesh:
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(2.6, 0.9, 1.3)
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.2, 0.7, 1.1)
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.35
	wheel_mesh.bottom_radius = 0.35
	wheel_mesh.height = 0.24
	wheel_mesh.radial_segments = 8

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(body_mesh, 0, Transform3D(Basis(), Vector3(0.0, 0.6, 0.0)))
	st.append_from(cabin_mesh, 0, Transform3D(Basis(), Vector3(0.4, 1.35, 0.0)))
	var wheel_basis := Basis(Vector3(0.0, 0.0, 1.0), PI / 2.0)
	for wheel_x in [-0.85, 0.85]:
		for wheel_z in [-0.65, 0.65]:
			st.append_from(
				wheel_mesh,
				0,
				Transform3D(wheel_basis, Vector3(wheel_x, 0.35, wheel_z))
			)
	return st.commit()


func _build_blocks_and_sandbags() -> void:
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.5, 1.5, 1.5)
	var box_mat := _make_material(Color(0.36, 0.37, 0.38), 0.85)
	var block_mm := _add_multimesh(box_mesh, box_mat, _block_spots.size(), false, "ConcreteBlocks")
	var block_body := _make_static_body("ConcreteBlockCollision")
	for i in range(_block_spots.size()):
		var yaw := _rng.randf_range(0.0, TAU)
		var pos := _ground_point(_block_spots[i], 0.75)
		var basis := Basis(Vector3(0.0, 1.0, 0.0), yaw)
		block_mm.set_instance_transform(i, Transform3D(basis, pos))
		_add_box_collision(
			block_body,
			Vector3(1.5, 1.5, 1.5),
			Transform3D(basis, pos)
		)

	var bag_mesh := BoxMesh.new()
	bag_mesh.size = Vector3(0.55, 0.42, 0.28)
	var bag_mat := _make_material(Color(0.46, 0.38, 0.24), 1.0)
	var bag_mm := _add_multimesh(
		bag_mesh,
		bag_mat,
		_sandbag_anchors.size() * _sandbag_offsets.size(),
		false,
		"Sandbags"
	)
	var bag_body := _make_static_body("SandbagCollision")
	var bag_index := 0
	for anchor in _sandbag_anchors:
		for offset in _sandbag_offsets:
			var local := anchor + offset
			var yaw := _rng.randf_range(0.0, TAU)
			var pos := _ground_point(local, 0.21)
			var basis := Basis(Vector3(0.0, 1.0, 0.0), yaw)
			bag_mm.set_instance_transform(bag_index, Transform3D(basis, pos))
			_add_box_collision(
				bag_body,
				Vector3(0.55, 0.42, 0.28),
				Transform3D(basis, pos)
			)
			bag_index += 1


func _build_warehouse() -> void:
	var center := Vector2(-78.0, 66.0)
	var ground: float = _terrain.height_at(Vector3(center.x, 0.0, center.y))
	var root := Node3D.new()
	root.name = "WarehouseA"
	root.position = Vector3(center.x, ground, center.y)
	_props_root.add_child(root)

	var wall_mat := _make_material(Color(0.45, 0.42, 0.35), 0.9)
	var roof_mat := _make_material(Color(0.32, 0.27, 0.22), 0.8)
	var crate_mat := _make_material(Color(0.36, 0.30, 0.20), 0.9)
	_add_box_mesh(root, Vector3(14.0, 5.0, 0.4), Vector3(0.0, 2.5, 4.6), wall_mat)
	_add_box_mesh(root, Vector3(14.0, 5.0, 0.4), Vector3(0.0, 2.5, -4.6), wall_mat)
	_add_box_mesh(root, Vector3(0.4, 5.0, 9.6), Vector3(-7.0, 2.5, 0.0), wall_mat)
	_add_box_mesh(root, Vector3(0.4, 5.0, 9.6), Vector3(7.0, 2.5, 0.0), wall_mat)
	_add_box_mesh(root, Vector3(14.8, 0.5, 10.4), Vector3(0.0, 5.5, 0.0), roof_mat)
	_add_box_mesh(root, Vector3(3.0, 1.4, 2.4), Vector3(-4.4, 0.7, 2.0), crate_mat)
	_add_box_mesh(root, Vector3(2.2, 1.0, 2.8), Vector3(-1.8, 0.5, -1.8), crate_mat)

	var body := StaticBody3D.new()
	body.name = "WarehouseCollision"
	body.collision_layer = 1
	body.collision_mask = 2
	root.add_child(body)
	_add_box_collision(body, Vector3(14.0, 5.0, 9.8), Transform3D(Basis(), Vector3(0.0, 2.5, 0.0)))


func _build_bridge() -> void:
	var center := Vector2(62.0, -74.0)
	var ground: float = _terrain.height_at(Vector3(center.x, 0.0, center.y))
	var root := Node3D.new()
	root.name = "BrokenBridgeB"
	root.position = Vector3(center.x, ground, center.y)
	root.rotation.y = atan2(-160.0, 140.0)
	_props_root.add_child(root)

	var deck_mat := _make_material(Color(0.27, 0.27, 0.28), 0.9)
	var concrete_mat := _make_material(Color(0.42, 0.42, 0.43), 0.9)
	var rail_mat := _make_material(Color(0.30, 0.31, 0.33), 0.7)
	_add_box_mesh(root, Vector3(13.0, 0.6, 7.0), Vector3(-7.5, 1.1, 0.0), deck_mat)
	var east_deck := _add_box_mesh(root, Vector3(13.0, 0.6, 7.0), Vector3(8.0, 0.85, 0.0), deck_mat)
	east_deck.rotation.z = 0.12
	_add_box_mesh(root, Vector3(1.4, 7.0, 4.0), Vector3(-7.0, 3.5, 0.0), concrete_mat)
	_add_box_mesh(root, Vector3(1.4, 7.0, 4.0), Vector3(7.0, 3.5, 0.0), concrete_mat)
	_add_box_mesh(root, Vector3(13.0, 1.0, 0.16), Vector3(-7.5, 2.2, 3.2), rail_mat)
	_add_box_mesh(root, Vector3(13.0, 1.0, 0.16), Vector3(-7.5, 2.2, -3.2), rail_mat)

	var body := StaticBody3D.new()
	body.name = "BridgeCollision"
	body.collision_layer = 1
	body.collision_mask = 2
	root.add_child(body)
	_add_box_collision(body, Vector3(13.0, 0.6, 7.0), Transform3D(Basis(), Vector3(-7.5, 1.1, 0.0)))
	_add_box_collision(body, Vector3(13.0, 0.6, 7.0), Transform3D(Basis(), Vector3(8.0, 0.85, 0.0)))
	_add_box_collision(body, Vector3(1.4, 7.0, 4.0), Transform3D(Basis(), Vector3(-7.0, 3.5, 0.0)))
	_add_box_collision(body, Vector3(1.4, 7.0, 4.0), Transform3D(Basis(), Vector3(7.0, 3.5, 0.0)))


func _build_watchtower() -> void:
	var center := Vector2(46.0, 96.0)
	var ground: float = _terrain.height_at(Vector3(center.x, 0.0, center.y))
	var root := Node3D.new()
	root.name = "WatchtowerC"
	root.position = Vector3(center.x, ground, center.y)
	_props_root.add_child(root)

	var steel_mat := _make_material(Color(0.30, 0.30, 0.28), 0.7)
	var wood_mat := _make_material(Color(0.36, 0.29, 0.19), 0.9)
	for leg_x in [-1.6, 1.6]:
		for leg_z in [-1.6, 1.6]:
			_add_box_mesh(root, Vector3(0.3, 9.0, 0.3), Vector3(leg_x, 4.5, leg_z), steel_mat)
	_add_box_mesh(root, Vector3(3.5, 0.3, 3.5), Vector3(0.0, 9.2, 0.0), wood_mat)
	_add_box_mesh(root, Vector3(2.4, 2.0, 2.4), Vector3(0.0, 10.9, 0.0), wood_mat)
	_add_box_mesh(root, Vector3(3.6, 0.9, 0.12), Vector3(0.0, 10.0, 1.75), steel_mat)
	_add_box_mesh(root, Vector3(3.6, 0.9, 0.12), Vector3(0.0, 10.0, -1.75), steel_mat)

	var body := StaticBody3D.new()
	body.name = "WatchtowerCollision"
	body.collision_layer = 1
	body.collision_mask = 2
	root.add_child(body)
	for leg_x in [-1.6, 1.6]:
		for leg_z in [-1.6, 1.6]:
			_add_box_collision(body, Vector3(0.3, 9.0, 0.3), Transform3D(Basis(), Vector3(leg_x, 4.5, leg_z)))
	_add_box_collision(body, Vector3(3.5, 0.3, 3.5), Transform3D(Basis(), Vector3(0.0, 9.2, 0.0)))


func _build_bunkers() -> void:
	var concrete_mat := _make_material(Color(0.46, 0.45, 0.42), 0.95)
	var dark_mat := _make_material(Color(0.10, 0.10, 0.10), 0.9)
	for spot in _bunker_spots:
		var ground: float = _terrain.height_at(Vector3(spot.x, 0.0, spot.y))
		var root := Node3D.new()
		root.name = "Bunker"
		root.position = Vector3(spot.x, ground, spot.y)
		_props_root.add_child(root)

		_add_box_mesh(root, Vector3(6.4, 2.2, 5.2), Vector3(0.0, 1.1, 0.0), concrete_mat)
		var dome_mesh := SphereMesh.new()
		dome_mesh.radius = 3.0
		dome_mesh.height = 2.4
		dome_mesh.radial_segments = 10
		var dome := MeshInstance3D.new()
		dome.mesh = dome_mesh
		dome.material_override = concrete_mat
		dome.position = Vector3(0.0, 2.1, 0.0)
		dome.scale = Vector3(1.0, 0.65, 0.85)
		root.add_child(dome)
		_add_box_mesh(root, Vector3(1.8, 1.5, 0.4), Vector3(0.0, 0.8, 2.6), dark_mat)

		var body := StaticBody3D.new()
		body.name = "BunkerCollision"
		body.collision_layer = 1
		body.collision_mask = 2
		root.add_child(body)
		_add_box_collision(body, Vector3(6.4, 2.2, 5.2), Transform3D(Basis(), Vector3(0.0, 1.1, 0.0)))
		_add_box_collision(body, Vector3(5.0, 1.8, 4.2), Transform3D(Basis(), Vector3(0.0, 2.7, 0.0)))


func _build_markers() -> void:
	_add_marker(Vector2(-78.0, 66.0), Color(0.9, 0.2, 0.2), "MarkerA")
	_add_marker(Vector2(62.0, -74.0), Color(0.95, 0.6, 0.15), "MarkerB")
	_add_marker(Vector2(46.0, 96.0), Color(0.2, 0.7, 0.9), "MarkerC")
	_add_marker(Vector2(-108.0, -108.0), Color(0.95, 0.8, 0.2), "MarkerD")


func _add_marker(local: Vector2, color: Color, marker_name: String) -> void:
	var root := Node3D.new()
	root.name = marker_name
	root.position = _ground_point(local, 0.0)
	_props_root.add_child(root)
	_add_box_mesh(
		root,
		Vector3(0.12, 4.5, 0.12),
		Vector3(0.0, 2.25, 0.0),
		_make_material(Color(0.2, 0.2, 0.2), 0.6)
	)
	_add_box_mesh(
		root,
		Vector3(1.1, 0.7, 0.06),
		Vector3(0.62, 4.35, 0.0),
		_make_material(color, 0.7)
	)


func _build_points() -> void:
	_spawn_points.clear()
	_nav_points.clear()
	_cover_points.clear()
	for local in _spawn_local:
		_spawn_points.append(_point_at(local, 0.5))
	for local in _nav_local:
		_nav_points.append(_point_at(local, 0.2))
	for local in _cover_local:
		_cover_points.append(_point_at(local, 0.1))


func _point_at(local: Vector2, lift: float) -> Vector3:
	var y: float = _terrain.height_at(Vector3(local.x, 0.0, local.y)) + lift
	return Vector3(local.x, y, local.y)


func _random_spot(min_road_dist: float, building_radius: float) -> Vector3:
	for attempt in range(14):
		var x := _rng.randf_range(-140.0, 140.0)
		var z := _rng.randf_range(-140.0, 140.0)
		var point := Vector2(x, z)
		if _terrain.height_at(Vector3(x, 0.0, z)) < WATER_LEVEL + 0.6:
			continue
		if _terrain.road_distance_at(point) < min_road_dist:
			continue
		if _near_building(point, building_radius):
			continue
		return Vector3(x, _terrain.height_at(Vector3(x, 0.0, z)), z)
	var fallback := Vector2(_rng.randf_range(-120.0, 120.0), _rng.randf_range(-120.0, 120.0))
	return Vector3(fallback.x, _terrain.height_at(Vector3(fallback.x, 0.0, fallback.y)), fallback.y)


func _near_building(point: Vector2, radius: float) -> bool:
	for anchor in _building_anchors:
		if point.distance_to(anchor) < radius:
			return true
	return false


func _ground_point(local: Vector2, lift: float) -> Vector3:
	var y: float = _terrain.height_at(Vector3(local.x, 0.0, local.y)) + lift
	return Vector3(local.x, y, local.y)


func _add_multimesh(
	mesh: Mesh,
	material: Material,
	count: int,
	use_colors: bool,
	node_name: String
) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if material != null:
		mmi.material_override = material
	_props_root.add_child(mmi)
	return mm


func _make_material(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _make_grass_texture() -> ImageTexture:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for py in range(64):
		for px in range(64):
			var n := _rng.randf_range(0.0, 1.0)
			if n > 0.45:
				image.set_pixel(
					px,
					py,
					Color(0.18 + n * 0.18, 0.38 + n * 0.25, 0.12, 0.95)
				)
	return ImageTexture.create_from_image(image)


func _add_box_mesh(
	parent: Node,
	size: Vector3,
	local_pos: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = local_pos
	parent.add_child(mi)
	return mi


func _make_static_body(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 2
	_props_root.add_child(body)
	return body


func _add_box_collision(body: StaticBody3D, size: Vector3, transform: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.transform = transform
	body.add_child(collision_shape)


func _apply_prop_density() -> void:
	var density := 1.0
	match _quality:
		"low":
			density = 0.45
		"medium":
			density = 0.7
		"high":
			density = 1.0
		"ultra":
			density = 1.0
	for mm in _density_multimeshes:
		mm.visible_instance_count = maxi(1, int(ceil(mm.instance_count * density)))
