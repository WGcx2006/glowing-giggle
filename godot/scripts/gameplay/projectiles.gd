extends Node3D

signal shot_fired(origin: Vector3, direction: Vector3, weapon_type: String)
signal hit_target(target: Object, damage: float, point: Vector3, normal: Vector3)
signal explosion_detonated(position: Vector3, radius: float, power: float, type: String, source: String)

const RANGES := {
	"assault_rifle": 320.0,
	"smg": 220.0,
	"dmr": 420.0,
	"rocket_launcher": 320.0,
	"grenade": 90.0,
}

const COLLISION_MASK := 3  # environment (1) | player (2)
const PROJECTILE_SCRIPT := preload("res://scripts/gameplay/projectile_body.gd")


func fire_projectile(origin: Vector3, direction: Vector3, weapon_type: String, projectile: String, shooter: Node = null) -> Node3D:
	var body: CharacterBody3D = PROJECTILE_SCRIPT.new() as CharacterBody3D
	body.name = "%s_%d" % [projectile, get_child_count()]
	add_child(body)
	body.fire(origin, direction, weapon_type, projectile, shooter, self)
	return body


func detonate_projectile(body, point: Vector3) -> void:
	if body == null or not is_instance_valid(body):
		return
	explosion_detonated.emit(point, float(body.radius), float(body.power), str(body.projectile_type), str(body.source))


func fire_hitscan(origin: Vector3, direction: Vector3, damage: float, weapon_type: String, shooter: Node = null) -> Dictionary:
	var forward := direction.normalized()
	if forward == Vector3.ZERO:
		return {}
	var max_range: float = RANGES.get(weapon_type, 300.0)
	var exclude: Array[RID] = []
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		exclude.append(shooter.get_rid())
	var params := PhysicsRayQueryParameters3D.create(origin, origin + forward * max_range, COLLISION_MASK, exclude)
	params.hit_back_faces = true
	shot_fired.emit(origin, forward, weapon_type)
	var result := get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return {}
	var point: Vector3 = result.get("position", origin + forward * max_range)
	var normal: Vector3 = result.get("normal", Vector3.UP)
	hit_target.emit(result.get("collider"), damage, point, normal)
	return result
