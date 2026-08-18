extends CharacterBody3D

const COLLISION_MASK := 3  # environment (1) | player (2)
const ROCKET_RADIUS := 0.12
const GRENADE_RADIUS := 0.16

var projectile_type := "rocket"
var weapon_type := "rocket_launcher"
var source := "player"
var radius := 7.0
var power := 95.0

var _speed := 32.0
var _gravity := 0.6
var _fuse := 7.0
var _direct_damage := 45.0
var _velocity := Vector3.ZERO
var _age := 0.0
var _bounces := 0
var _entity_hit := false
var _resting := false
var _detonated := false
var _parent: Node = null
var _mesh_root: Node3D = null


func fire(origin: Vector3, direction: Vector3, weapon_type_arg: String, projectile: String, shooter: Node = null, parent: Node = null) -> void:
	weapon_type = weapon_type_arg
	projectile_type = projectile
	_parent = parent
	var owner: Node = _parent.get_parent() if _parent != null else null
	source = "player" if (shooter != null and shooter == owner) else "world"
	top_level = true
	global_position = origin
	collision_layer = 0
	collision_mask = COLLISION_MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if shooter is CollisionObject3D:
		add_collision_exception_with(shooter)
	_configure_projectile(direction)
	_build_collision()
	_build_mesh()


func _physics_process(delta: float) -> void:
	if _parent == null or not is_instance_valid(_parent):
		queue_free()
		return
	_age += delta
	if _fuse > 0.0 and _age >= _fuse:
		_detonate(global_position)
		return
	if _resting:
		_velocity = Vector3.ZERO
	else:
		_velocity.y -= _gravity * delta
	var collision := move_and_collide(_velocity * delta)
	if collision:
		var point: Vector3 = collision.get_position()
		var normal: Vector3 = collision.get_normal()
		if projectile_type == "rocket":
			_direct_hit(collision.get_collider(), point, normal)
			_detonate(point)
			return
		_bounce(collision, point, normal)
	_look_at_velocity()


func _configure_projectile(direction: Vector3) -> void:
	var forward := direction.normalized()
	if projectile_type == "grenade":
		_speed = 13.0
		_gravity = 18.0
		_fuse = 2.8
		radius = 8.0
		power = 80.0
		_direct_damage = 12.0
		_velocity = forward * _speed
		_velocity.y += 5.0
	else:
		_speed = 32.0
		_gravity = 0.6
		_fuse = 7.0
		radius = 7.0
		power = 95.0
		_direct_damage = 45.0
		_velocity = forward * _speed


func _build_collision() -> void:
	var shape := SphereShape3D.new()
	shape.radius = GRENADE_RADIUS if projectile_type == "grenade" else ROCKET_RADIUS
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	add_child(collision_shape)


func _build_mesh() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "Visual"
	add_child(_mesh_root)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.18, 0.24, 0.21)
	body_mat.metallic = 0.55
	body_mat.roughness = 0.42
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.62, 0.28, 0.18)
	accent_mat.metallic = 0.35
	accent_mat.roughness = 0.5
	if projectile_type == "grenade":
		var body_mesh := SphereMesh.new()
		body_mesh.radius = 0.075
		body_mesh.height = 0.15
		body_mesh.radial_segments = 10
		body_mesh.rings = 8
		var body_instance := MeshInstance3D.new()
		body_instance.mesh = body_mesh
		body_instance.material_override = body_mat
		_mesh_root.add_child(body_instance)
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(0.035, 0.09, 0.035)
		var handle_instance := MeshInstance3D.new()
		handle_instance.mesh = handle_mesh
		handle_instance.material_override = accent_mat
		handle_instance.position = Vector3(0.0, 0.06, 0.0)
		_mesh_root.add_child(handle_instance)
		return
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = 0.045
	tube_mesh.bottom_radius = 0.045
	tube_mesh.height = 0.6
	tube_mesh.radial_segments = 8
	var tube_instance := MeshInstance3D.new()
	tube_instance.mesh = tube_mesh
	tube_instance.material_override = body_mat
	tube_instance.rotation_degrees.x = -90.0
	_mesh_root.add_child(tube_instance)
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 0.045
	nose_mesh.height = 0.16
	nose_mesh.radial_segments = 8
	var nose_instance := MeshInstance3D.new()
	nose_instance.mesh = nose_mesh
	nose_instance.material_override = accent_mat
	nose_instance.rotation_degrees.x = -90.0
	nose_instance.position.z = -0.38
	_mesh_root.add_child(nose_instance)


func _direct_hit(collider, point: Vector3, normal: Vector3) -> void:
	if collider == null or _entity_hit:
		return
	_entity_hit = true
	if collider.is_in_group("enemy_ai"):
		_parent.hit_target.emit(collider, _direct_damage, point, normal)


func _bounce(collision: KinematicCollision3D, point: Vector3, normal: Vector3) -> void:
	var reflected := _velocity.bounce(normal) * 0.48
	reflected.x *= 0.8
	reflected.z *= 0.8
	global_position = point + normal * 0.02
	_bounces += 1
	if reflected.length_squared() < 0.4 or normal.y > 0.65:
		_velocity = Vector3.ZERO
		_resting = true
	else:
		_velocity = reflected


func _detonate(point: Vector3) -> void:
	if _detonated:
		return
	_detonated = true
	if _parent != null and is_instance_valid(_parent):
		_parent.detonate_projectile(self, point)
	queue_free()


func _look_at_velocity() -> void:
	if _mesh_root == null or _velocity.length_squared() < 0.0001:
		return
	var forward := _velocity.normalized()
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.999:
		up = Vector3.FORWARD
	_mesh_root.look_at(global_position + forward, up)
