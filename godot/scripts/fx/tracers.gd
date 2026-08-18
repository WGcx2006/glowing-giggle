extends Node3D

const POOL_SIZE := 64

class TracerInstance extends MeshInstance3D:
	var life := 0.0
	var duration := 0.055
	var start_alpha := 1.0

var _pool: Array = []
var _box_mesh: BoxMesh
var _box_material: StandardMaterial3D


func _ready() -> void:
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.012, 0.012, 1.0)
	_box_material = StandardMaterial3D.new()
	_box_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_material.no_depth_test = false
	for i in POOL_SIZE:
		var tracer := TracerInstance.new()
		tracer.name = "Tracer%d" % i
		tracer.mesh = _box_mesh
		tracer.material_override = _box_material.duplicate()
		tracer.visible = false
		tracer.life = 0.0
		add_child(tracer)
		_pool.append(tracer)


func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var tracer := _acquire()
	if tracer == null:
		return
	var offset := to - from
	var length := offset.length()
	if length < 0.01:
		tracer.life = 0.0
		tracer.visible = false
		return
	var dir := offset / length
	tracer.life = 0.0
	tracer.duration = 0.055
	tracer.start_alpha = maxf(color.a, 0.6)
	tracer.global_position = from + offset * 0.5
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) >= 0.999:
		up = Vector3.RIGHT
	tracer.look_at(to, up)
	tracer.scale = Vector3(1.0, 1.0, length)
	var mat := tracer.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color
	tracer.visible = true


func update(delta: float) -> void:
	for tracer in _pool:
		if tracer.life <= 0.0:
			continue
		tracer.life += delta
		var t := clampf(tracer.life / tracer.duration, 0.0, 1.0)
		var mat := tracer.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = tracer.start_alpha * (1.0 - t * t)
		if t >= 1.0:
			tracer.visible = false
			tracer.life = 0.0


func clear() -> void:
	for tracer in _pool:
		tracer.visible = false
		tracer.life = 0.0


func _acquire() -> TracerInstance:
	for tracer in _pool:
		if tracer.life <= 0.0:
			return tracer
	return null
