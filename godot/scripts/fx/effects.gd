extends Node3D

const TRACER_SCRIPT := preload("res://scripts/fx/tracers.gd")

const MUZZLE_CORE_COUNT := 12
const MUZZLE_OUTER_COUNT := 12
const IMPACT_SPARK_COUNT := 14
const IMPACT_DUST_COUNT := 12
const EXPLOSION_FIRE_COUNT := 6
const EXPLOSION_SPARK_COUNT := 8
const EXPLOSION_SMOKE_COUNT := 8
const EXPLOSION_DUST_COUNT := 6
const RING_COUNT := 8
const LIGHT_COUNT := 12
const CASING_COUNT := 14

class PooledParticle extends CPUParticles3D:
	var life := 0.0
	var duration := 0.1

class PooledLight extends OmniLight3D:
	var life := 0.0
	var duration := 0.15
	var start_range := 2.0
	var start_energy := 1.0

class PooledRing extends MeshInstance3D:
	var life := 0.0
	var duration := 0.6
	var start_scale := 0.2
	var end_scale := 2.0
	var start_alpha := 1.0

class PooledCasing extends RigidBody3D:
	var life := 0.0
	var duration := 1.2

var _camera: Camera3D
var _tracers

var _particle_mesh: SphereMesh
var _spark_mesh: BoxMesh
var _cube_mesh: BoxMesh
var _casing_mesh: BoxMesh
var _ring_mesh: TorusMesh
var _particle_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _casing_material: StandardMaterial3D

var _muzzle_core_pool: Array = []
var _muzzle_outer_pool: Array = []
var _impact_spark_pool: Array = []
var _impact_dust_pool: Array = []
var _explosion_fire_pool: Array = []
var _explosion_spark_pool: Array = []
var _explosion_smoke_pool: Array = []
var _explosion_dust_pool: Array = []
var _ring_pool: Array = []
var _light_pool: Array = []
var _casing_pool: Array = []


func _ready() -> void:
	_build_materials()
	_build_meshes()
	_build_pools()
	_tracers = TRACER_SCRIPT.new()
	_tracers.name = "Tracers"
	add_child(_tracers)


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func muzzle_flash(pos: Vector3, dir: Vector3, weapon_type: String) -> void:
	var d := dir
	if d.length_squared() < 0.0001:
		d = Vector3.BACK
	d = d.normalized()
	var scale := _weapon_scale(weapon_type)
	var core := _acquire_particle(_muzzle_core_pool)
	if core != null:
		_activate_particle(core, pos + d * 0.05, 0.12, d, 14.0, 0.2, 0.8,
			0.25 * scale, 0.7 * scale, Color(1.0, 0.95, 0.7, 1.0), Vector3.ZERO,
			int(14.0 * scale), 0.1, 0.03)
	var outer := _acquire_particle(_muzzle_outer_pool)
	if outer != null:
		_activate_particle(outer, pos + d * 0.04, 0.16, d, 45.0, 1.2, 3.2,
			0.12 * scale, 0.32 * scale, Color(1.0, 0.6, 0.2, 1.0),
			Vector3(0.0, 0.4, 0.0), int(18.0 * scale), 0.14, 0.04)
	_spawn_light(_light_pool, pos + d * 0.05, 0.12, 2.5 * scale,
		Color(1.0, 0.8, 0.45), 2.0 * scale)


func impact(pos: Vector3, normal: Vector3) -> void:
	var n := normal
	if n.length_squared() < 0.0001:
		n = Vector3.UP
	n = n.normalized()
	var spark := _acquire_particle(_impact_spark_pool)
	if spark != null:
		_activate_particle(spark, pos + n * 0.02, 0.5, n, 95.0, 1.5, 5.0,
			0.06, 0.18, Color(1.0, 0.8, 0.35, 1.0), Vector3(0.0, -11.0, 0.0),
			14, 0.4, 0.02)
	var dust := _acquire_particle(_impact_dust_pool)
	if dust != null:
		_activate_particle(dust, pos + n * 0.03, 0.9, n, 150.0, 0.4, 1.5,
			0.3, 0.8, Color(0.55, 0.52, 0.48, 1.0), Vector3(0.0, -0.4, 0.0),
			10, 0.8, 0.05)


func explosion(pos: Vector3, radius: float) -> void:
	var r := clampf(radius, 0.5, 20.0)
	var amount_scale := clampf(r * 0.22, 0.6, 2.4)
	var fire := _acquire_particle(_explosion_fire_pool)
	if fire != null:
		_activate_particle(fire, pos, 0.65, Vector3.UP, 180.0,
			1.5 + r * 0.25, minf(4.0 + r * 0.5, 10.0),
			0.5 + r * 0.06, 1.0 + r * 0.12, Color(1.0, 0.9, 0.55, 1.0),
			Vector3(0.0, -0.5, 0.0), int(30.0 * amount_scale), 0.6, r * 0.3)
	var spark := _acquire_particle(_explosion_spark_pool)
	if spark != null:
		_activate_particle(spark, pos, 0.9, Vector3.UP, 180.0,
			5.0 + r * 0.4, minf(11.0 + r * 0.6, 22.0),
			0.07 + r * 0.005, 0.2 + r * 0.012, Color(1.0, 0.72, 0.3, 1.0),
			Vector3(0.0, -13.0, 0.0), int(20.0 * amount_scale), 0.8, r * 0.25)
	var smoke := _acquire_particle(_explosion_smoke_pool)
	if smoke != null:
		_activate_particle(smoke, pos, 2.6, Vector3.UP, 35.0,
			1.0 + r * 0.1, minf(3.0 + r * 0.15, 8.0),
			0.8 + r * 0.04, 2.2 + r * 0.12, Color(0.16, 0.16, 0.18, 1.0),
			Vector3(0.0, -0.1, 0.0), int(16.0 * amount_scale), 2.4, r * 0.25)
	var dust := _acquire_particle(_explosion_dust_pool)
	if dust != null:
		_activate_particle(dust, pos, 1.2, Vector3.UP, 170.0,
			0.8 + r * 0.1, minf(2.5 + r * 0.2, 7.0),
			0.5 + r * 0.05, 1.4 + r * 0.1, Color(0.45, 0.42, 0.38, 1.0),
			Vector3(0.0, -0.3, 0.0), int(14.0 * amount_scale), 1.1, r * 0.4)
	_spawn_ring(pos, r)
	_spawn_light(_light_pool, pos, 0.35, 8.0 + r * 3.0, Color(1.0, 0.65, 0.2),
		6.0 + r * 2.0)


func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	if _tracers != null:
		_tracers.tracer(from, to, color)


func casing(pos: Vector3, dir: Vector3) -> void:
	var body := _acquire_casing()
	if body == null:
		return
	var d := dir
	if d.length_squared() < 0.0001:
		d = Vector3.RIGHT
	d = d.normalized()
	body.global_position = pos
	body.visible = true
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = d * randf_range(1.8, 3.0) + Vector3(
		randf_range(-0.3, 0.3), randf_range(1.0, 2.4), randf_range(-0.3, 0.3))
	body.angular_velocity = Vector3(
		randf_range(-12.0, 12.0), randf_range(-18.0, 18.0), randf_range(-12.0, 12.0))
	body.life = 0.0
	body.duration = randf_range(0.9, 1.5)


func update(delta: float) -> void:
	_update_particle_pool(_muzzle_core_pool, delta)
	_update_particle_pool(_muzzle_outer_pool, delta)
	_update_particle_pool(_impact_spark_pool, delta)
	_update_particle_pool(_impact_dust_pool, delta)
	_update_particle_pool(_explosion_fire_pool, delta)
	_update_particle_pool(_explosion_spark_pool, delta)
	_update_particle_pool(_explosion_smoke_pool, delta)
	_update_particle_pool(_explosion_dust_pool, delta)
	_update_light_pool(_light_pool, delta)
	_update_ring_pool(delta)
	_update_casing_pool(delta)
	if _tracers != null:
		_tracers.update(delta)


func _weapon_scale(weapon_type: String) -> float:
	if weapon_type == "sniper" or weapon_type == "sniper_rifle" or weapon_type == "marksman":
		return 1.35
	if weapon_type == "shotgun":
		return 1.4
	if weapon_type == "rocket" or weapon_type == "launcher" or weapon_type == "rpg":
		return 1.5
	if weapon_type == "pistol":
		return 0.7
	if weapon_type == "smg":
		return 0.9
	return 1.0


func _acquire_particle(pool: Array) -> PooledParticle:
	for p in pool:
		if p.life <= 0.0:
			return p
	return null


func _activate_particle(p: PooledParticle, pos: Vector3, duration: float,
		direction: Vector3, spread: float, velocity_min: float, velocity_max: float,
		scale_min: float, scale_max: float, color: Color, gravity: Vector3,
		amount: int, lifetime: float, emission_radius: float = 0.0) -> void:
	p.life = 0.0
	p.duration = duration
	p.amount = amount
	p.lifetime = lifetime
	p.global_position = pos
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = velocity_min
	p.initial_velocity_max = velocity_max
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.color = color
	p.gravity = gravity
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = emission_radius
	p.emitting = false
	p.restart()
	p.visible = true
	p.emitting = true


func _acquire_casing() -> PooledCasing:
	for casing in _casing_pool:
		if casing.life <= 0.0:
			return casing
	return null


func _spawn_light(pool: Array, pos: Vector3, duration: float, light_range: float,
		color: Color, energy: float) -> void:
	for light in pool:
		if light.life <= 0.0:
			light.life = 0.0
			light.duration = duration
			light.start_range = light_range
			light.start_energy = energy
			light.global_position = pos
			light.light_color = color
			light.omni_range = light_range
			light.light_energy = energy
			light.visible = true
			return


func _spawn_ring(pos: Vector3, radius: float) -> void:
	for ring in _ring_pool:
		if ring.life <= 0.0:
			ring.global_position = pos
			ring.life = 0.0
			ring.duration = 0.6
			ring.start_scale = maxf(radius * 0.12, 0.05)
			ring.end_scale = maxf(radius * 2.0, 0.5)
			ring.start_alpha = 0.9
			ring.scale = Vector3(ring.start_scale, ring.start_scale, ring.start_scale)
			var mat := ring.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color.a = ring.start_alpha
			ring.visible = true
			return


func _build_materials() -> void:
	_particle_material = StandardMaterial3D.new()
	_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_particle_material.vertex_color_use_as_albedo = true
	_particle_material.disable_receive_shadows = true
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	_ring_material.no_depth_test = true
	_casing_material = StandardMaterial3D.new()
	_casing_material.metallic = 0.85
	_casing_material.roughness = 0.35
	_casing_material.albedo_color = Color(0.75, 0.55, 0.22, 1.0)


func _build_meshes() -> void:
	_particle_mesh = SphereMesh.new()
	_particle_mesh.radius = 0.05
	_particle_mesh.height = 0.1
	_particle_mesh.radial_segments = 8
	_particle_mesh.rings = 4
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.025, 0.025, 0.025)
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3.ONE
	_casing_mesh = BoxMesh.new()
	_casing_mesh.size = Vector3(0.014, 0.05, 0.014)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.45
	_ring_mesh.outer_radius = 0.5
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 48


func _build_pools() -> void:
	var muzzle_core_ramp := Gradient.new()
	muzzle_core_ramp.set_color(0.0, Color(1.0, 1.0, 0.85, 1.0))
	muzzle_core_ramp.set_color(0.6, Color(1.0, 0.72, 0.32, 0.8))
	muzzle_core_ramp.set_color(1.0, Color(0.6, 0.2, 0.05, 0.0))
	var muzzle_outer_ramp := Gradient.new()
	muzzle_outer_ramp.set_color(0.0, Color(1.0, 0.7, 0.3, 1.0))
	muzzle_outer_ramp.set_color(1.0, Color(0.45, 0.1, 0.02, 0.0))
	var spark_ramp := Gradient.new()
	spark_ramp.set_color(0.0, Color(1.0, 0.85, 0.4, 1.0))
	spark_ramp.set_color(1.0, Color(0.35, 0.12, 0.02, 0.0))
	var dust_ramp := Gradient.new()
	dust_ramp.set_color(0.0, Color(0.6, 0.57, 0.52, 0.8))
	dust_ramp.set_color(1.0, Color(0.25, 0.24, 0.22, 0.0))
	var fire_ramp := Gradient.new()
	fire_ramp.set_color(0.0, Color(1.0, 1.0, 0.85, 1.0))
	fire_ramp.set_color(0.35, Color(1.0, 0.62, 0.2, 1.0))
	fire_ramp.set_color(1.0, Color(0.3, 0.08, 0.02, 0.0))
	var smoke_ramp := Gradient.new()
	smoke_ramp.set_color(0.0, Color(0.18, 0.17, 0.16, 0.55))
	smoke_ramp.set_color(1.0, Color(0.12, 0.12, 0.13, 0.0))

	_build_particle_pool(_muzzle_core_pool, MUZZLE_CORE_COUNT, _particle_mesh, muzzle_core_ramp)
	_build_particle_pool(_muzzle_outer_pool, MUZZLE_OUTER_COUNT, _particle_mesh, muzzle_outer_ramp)
	_build_particle_pool(_impact_spark_pool, IMPACT_SPARK_COUNT, _spark_mesh, spark_ramp)
	_build_particle_pool(_impact_dust_pool, IMPACT_DUST_COUNT, _cube_mesh, dust_ramp)
	_build_particle_pool(_explosion_fire_pool, EXPLOSION_FIRE_COUNT, _particle_mesh, fire_ramp)
	_build_particle_pool(_explosion_spark_pool, EXPLOSION_SPARK_COUNT, _spark_mesh, spark_ramp)
	_build_particle_pool(_explosion_smoke_pool, EXPLOSION_SMOKE_COUNT, _cube_mesh, smoke_ramp)
	_build_particle_pool(_explosion_dust_pool, EXPLOSION_DUST_COUNT, _cube_mesh, dust_ramp)

	for i in LIGHT_COUNT:
		var light := PooledLight.new()
		light.name = "FlashLight%d" % i
		light.visible = false
		light.light_color = Color(1.0, 0.75, 0.35, 1.0)
		light.omni_range = 2.0
		light.light_energy = 1.0
		add_child(light)
		_light_pool.append(light)

	for i in RING_COUNT:
		var ring := PooledRing.new()
		ring.name = "ShockwaveRing%d" % i
		ring.mesh = _ring_mesh
		ring.material_override = _ring_material.duplicate()
		ring.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		ring.visible = false
		add_child(ring)
		_ring_pool.append(ring)

	for i in CASING_COUNT:
		var casing := PooledCasing.new()
		casing.name = "Casing%d" % i
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.014, 0.05, 0.014)
		collision.shape = shape
		casing.add_child(collision)
		var casing_mesh := MeshInstance3D.new()
		casing_mesh.mesh = _casing_mesh
		casing_mesh.material_override = _casing_material
		casing.add_child(casing_mesh)
		casing.mass = 0.04
		casing.gravity_scale = 2.0
		casing.collision_layer = 0
		casing.collision_mask = 1
		casing.can_sleep = true
		casing.freeze = true
		casing.visible = false
		add_child(casing)
		_casing_pool.append(casing)


func _build_particle_pool(pool: Array, count: int, mesh: Mesh, ramp: Gradient) -> void:
	for i in count:
		var p := PooledParticle.new()
		p.name = "Particle%d" % i
		p.mesh = mesh
		p.material_override = _particle_material
		p.amount = 12
		p.lifetime = 0.25
		p.one_shot = true
		p.explosiveness = 1.0
		p.randomness = 0.12
		p.lifetime_randomness = 0.1
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.0
		p.local_coords = false
		p.color_ramp = ramp
		p.visible = false
		p.emitting = false
		p.life = 0.0
		p.duration = 0.25
		add_child(p)
		pool.append(p)


func _update_particle_pool(pool: Array, delta: float) -> void:
	for p in pool:
		if p.life <= 0.0:
			continue
		p.life += delta
		if p.life >= p.duration:
			p.emitting = false
			p.visible = false
			p.life = 0.0


func _update_light_pool(pool: Array, delta: float) -> void:
	for light in pool:
		if light.life <= 0.0:
			continue
		light.life += delta
		var t := clampf(light.life / light.duration, 0.0, 1.0)
		light.omni_range = maxf(0.05, light.start_range * (1.0 - t * t))
		light.light_energy = maxf(0.0, light.start_energy * (1.0 - t))
		if t >= 1.0:
			light.visible = false
			light.life = 0.0


func _update_ring_pool(delta: float) -> void:
	for ring in _ring_pool:
		if ring.life <= 0.0:
			continue
		ring.life += delta
		var t := clampf(ring.life / ring.duration, 0.0, 1.0)
		var s := lerpf(ring.start_scale, ring.end_scale, t)
		ring.scale = Vector3(s, s, s)
		var mat := ring.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = ring.start_alpha * (1.0 - t) * (1.0 - t)
		if t >= 1.0:
			ring.visible = false
			ring.life = 0.0


func _update_casing_pool(delta: float) -> void:
	for casing in _casing_pool:
		if casing.life <= 0.0:
			continue
		casing.life += delta
		if casing.life >= casing.duration:
			casing.freeze = true
			casing.linear_velocity = Vector3.ZERO
			casing.angular_velocity = Vector3.ZERO
			casing.visible = false
			casing.life = 0.0
