extends StaticBody3D
## Procedural 300x300m battlefield terrain with hills, a valley, roads,
## building pads, and a coastal shelf. Geometry and collision are built once.

const HALF_SIZE := 150.0
const STEP := 2.0
const WATER_LEVEL := 0.8
const ROAD_WIDTH := 7.0

const MAP_THEME_SCRIPT := preload("res://scripts/render/map_theme.gd")

var _noise_base: FastNoiseLite
var _noise_hills: FastNoiseLite
var _noise_detail: FastNoiseLite
var _roads: Array = []
var _building_pads: Array[Vector2] = []
var _built := false
var _theme: Dictionary = {}
var _terrain_mesh: ArrayMesh
var _mesh_instance: MeshInstance3D
var _terrain_material: StandardMaterial3D
var _terrain_vertices: PackedVector3Array
var _vertex_slopes: PackedFloat32Array
var _detail_texture: ImageTexture


func _ready() -> void:
	setup()


func setup() -> void:
	if _built:
		return
	_built = true
	if _theme.is_empty():
		_theme = MAP_THEME_SCRIPT.get_theme("arctic")
	_create_noise()
	_building_pads = [
		Vector2(-78.0, 66.0),
		Vector2(46.0, 96.0),
		Vector2(-108.0, -108.0),
	]
	_roads = [
		PackedVector2Array([
			Vector2(-70.0, 80.0),
			Vector2(-10.0, 20.0),
			Vector2(70.0, -80.0),
		]),
		PackedVector2Array([
			Vector2(40.0, 100.0),
			Vector2(-10.0, 20.0),
			Vector2(-108.0, -100.0),
		]),
	]
	_build_mesh_and_collision()


func _create_noise() -> void:
	_noise_base = FastNoiseLite.new()
	_noise_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_base.seed = 2035
	_noise_base.frequency = 0.011

	_noise_hills = FastNoiseLite.new()
	_noise_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_hills.seed = 317
	_noise_hills.frequency = 0.016
	_noise_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_hills.fractal_octaves = 4
	_noise_hills.fractal_gain = 0.5
	_noise_hills.fractal_lacunarity = 2.1

	_noise_detail = FastNoiseLite.new()
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_detail.seed = 921
	_noise_detail.frequency = 0.055


func height_at(pos: Vector3) -> float:
	return get_height(pos.x, pos.z)


func get_height(x: float, z: float) -> float:
	var base := _noise_base.get_noise_2d(x, z)
	var hills := _noise_hills.get_noise_2d(x, z)
	var detail := _noise_detail.get_noise_2d(x + 41.0, z - 17.0)
	var ridge := maxf(0.0, hills)
	var hill_height := pow(ridge, 1.7) * 20.0 * (0.55 + 0.45 * (detail * 0.5 + 0.5))
	var h := base * 6.0 + hill_height

	var valley := 1.0 - smoothstep(0.0, 1.0, absf(x - 4.0) / 46.0)
	h -= valley * 7.0

	var west := 1.0 - smoothstep(-122.0, -98.0, x)
	if west > 0.0:
		var sea_target := -5.0 + base * 1.2 + hills * 0.8
		h = lerpf(h, sea_target, west)

	var road := 1.0 - smoothstep(0.0, 1.0, road_distance_at(Vector2(x, z)) / ROAD_WIDTH)
	if road > 0.0:
		var flat_road := base * 6.0 + 1.2
		h = lerpf(h, flat_road, road)

	h = _flatten_building_pads(h, x, z)
	return h


func road_distance_at(point: Vector2) -> float:
	var nearest := 1e9
	for road in _roads:
		for i in range(road.size() - 1):
			nearest = minf(nearest, _segment_distance(point, road[i], road[i + 1]))
	return nearest


func _flatten_building_pads(h: float, x: float, z: float) -> float:
	for pad in _building_pads:
		var d := Vector2(x, z).distance_to(pad)
		var influence := 1.0 - smoothstep(0.0, 1.0, d / 18.0)
		if influence > 0.0:
			var flat := _noise_base.get_noise_2d(x, z) * 4.0 + 1.0
			h = lerpf(h, flat, influence)
	return h


func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _build_mesh_and_collision() -> void:
	var resolution := int(HALF_SIZE * 2.0 / STEP) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slopes := PackedFloat32Array()
	slopes.resize(resolution * resolution)

	for iz in range(resolution):
		for ix in range(resolution):
			var x := -HALF_SIZE + ix * STEP
			var z := -HALF_SIZE + iz * STEP
			var slope := absf(get_height(x + 2.0, z) - get_height(x - 2.0, z))
			slope += absf(get_height(x, z + 2.0) - get_height(x, z - 2.0))
			slopes[iz * resolution + ix] = slope
			st.set_uv(Vector2(x / 72.0, z / 72.0))
			st.add_vertex(Vector3(x, get_height(x, z), z))

	for iz in range(resolution - 1):
		for ix in range(resolution - 1):
			var i0 := iz * resolution + ix
			var i1 := i0 + 1
			var i2 := i0 + resolution
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i3)

	st.generate_normals()
	var source_mesh := st.commit()
	var arrays := source_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_terrain_vertices = vertices
	_vertex_slopes = slopes
	arrays[Mesh.ARRAY_COLOR] = _make_vertex_colors(vertices)

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_terrain_material = _make_terrain_material()
	mesh.surface_set_material(0, _terrain_material)
	_terrain_mesh = mesh

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = _terrain_mesh
	add_child(mesh_instance)
	_mesh_instance = mesh_instance

	var collision := HeightMapShape3D.new()
	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	for iz in range(resolution):
		for ix in range(resolution):
			heights[iz * resolution + ix] = get_height(-HALF_SIZE + ix * STEP, -HALF_SIZE + iz * STEP)
	collision.map_width = resolution
	collision.map_depth = resolution
	collision.map_data = heights
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = collision
	collision_shape.scale = Vector3(STEP, 1.0, STEP)
	add_child(collision_shape)

	collision_layer = 1
	collision_mask = 2


func _make_terrain_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if _detail_texture == null:
		_detail_texture = _make_albedo_texture()
	mat.albedo_texture = _detail_texture
	mat.albedo_color = _theme.get("terrain_grass", Color(0.28, 0.39, 0.18))
	mat.roughness_texture = _make_roughness_texture()
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


func _make_albedo_texture() -> ImageTexture:
	var resolution := 256
	var image := Image.create_empty(resolution, resolution, true, Image.FORMAT_RGB8)
	for py in range(resolution):
		for px in range(resolution):
			var x := -HALF_SIZE + (px + 0.5) / resolution * (HALF_SIZE * 2.0)
			var z := -HALF_SIZE + (py + 0.5) / resolution * (HALF_SIZE * 2.0)
			var h := get_height(x, z)
			var road := 1.0 - smoothstep(0.0, 1.0, road_distance_at(Vector2(x, z)) / (ROAD_WIDTH + 1.0))
			var color := Color(0.86, 0.86, 0.84)
			if h < WATER_LEVEL + 0.6:
				color = Color(0.78, 0.76, 0.72)
			if road > 0.0:
				color = color.lerp(Color(0.52, 0.53, 0.55), road)
			var variation := _noise_detail.get_noise_2d(x * 0.7, z * 0.7) * 0.5 + 0.5
			color = color * (0.82 + variation * 0.32)
			image.set_pixel(px, py, color)
	return ImageTexture.create_from_image(image)


func set_map_theme(theme: Dictionary) -> void:
	if theme.is_empty() or not theme.has("terrain_grass"):
		return
	_theme = theme
	if _terrain_material != null:
		_terrain_material.albedo_color = theme["terrain_grass"]
	if _terrain_mesh != null and _mesh_instance != null and _terrain_vertices.size() > 0:
		var arrays := _terrain_mesh.surface_get_arrays(0)
		arrays[Mesh.ARRAY_COLOR] = _make_vertex_colors(_terrain_vertices)
		var updated := ArrayMesh.new()
		updated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		updated.surface_set_material(0, _terrain_material)
		_terrain_mesh = updated
		_mesh_instance.mesh = _terrain_mesh


func _make_vertex_colors(vertices: PackedVector3Array) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	var grass: Color = _theme.get("terrain_grass", Color(0.28, 0.39, 0.18))
	var dirt: Color = _theme.get("terrain_dirt", Color(0.42, 0.39, 0.34))
	var sand: Color = _theme.get("terrain_sand", Color(0.68, 0.61, 0.43))
	for i in range(vertices.size()):
		var vertex := vertices[i]
		var color := grass.lerp(Color.WHITE, 0.32)
		if vertex.y < WATER_LEVEL + 0.6:
			color = sand.lerp(Color.WHITE, 0.24)
		elif i < _vertex_slopes.size() and _vertex_slopes[i] > 2.8:
			color = dirt.lerp(Color.WHITE, 0.12)
		elif vertex.y > 18.0:
			color = grass.lerp(dirt, 0.32).lerp(Color.WHITE, 0.24)
		var road := 1.0 - smoothstep(0.0, 1.0, road_distance_at(Vector2(vertex.x, vertex.z)) / (ROAD_WIDTH + 1.0))
		if road > 0.0:
			color = color.lerp(Color(0.70, 0.70, 0.70), road * 0.6)
		var variation := _noise_detail.get_noise_2d(vertex.x * 0.7, vertex.z * 0.7) * 0.5 + 0.5
		colors[i] = color * (0.86 + variation * 0.28)
	return colors


func _make_roughness_texture() -> ImageTexture:
	var resolution := 128
	var image := Image.create_empty(resolution, resolution, true, Image.FORMAT_R8)
	for py in range(resolution):
		for px in range(resolution):
			var x := -HALF_SIZE + (px + 0.5) / resolution * (HALF_SIZE * 2.0)
			var z := -HALF_SIZE + (py + 0.5) / resolution * (HALF_SIZE * 2.0)
			var n := _noise_detail.get_noise_2d(x * 0.8, z * 0.8) * 0.5 + 0.5
			var v := clampf(0.5 + n * 0.4, 0.0, 1.0)
			image.set_pixel(px, py, Color(v, v, v))
	return ImageTexture.create_from_image(image)
