extends AudioStreamPlayer3D

const SAMPLE_RATE: int = 22050
const ENGINE_DURATION: float = 0.6
const ENGINE_FREQ: float = 55.0
const PULSE_RATE: float = 20.0
const PULSE_COUNT: int = 12
const TAU: float = 6.283185307179586

var _vehicle: Node
var _rpm: float = 0.0
var _setup_done: bool = false
var _silent: bool = false


func setup(vehicle: Node) -> void:
	_vehicle = vehicle
	stream = _make_engine_wav()
	max_db = 6.0
	unit_size = 14.0
	volume_db = -18.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	pitch_scale = 0.75
	_rpm = 0.0
	_setup_done = true
	_silent = false
	add_to_group("bf_vehicle_engine")
	play()


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if not _setup_done:
		return
	var vehicle_valid: bool = _vehicle != null and is_instance_valid(_vehicle)
	var vehicle_alive: bool = true
	if vehicle_valid:
		if "alive" in _vehicle:
			vehicle_alive = bool(_vehicle.get("alive"))
	if vehicle_valid and vehicle_alive and _vehicle.has_method("get_animation_snapshot"):
		if _silent:
			_silent = false
			play()
		var snapshot: Dictionary = _vehicle.call("get_animation_snapshot")
		var speed: float = absf(float(snapshot.get("speed", 0.0)))
		_rpm = clampf(speed / 10.0, 0.0, 1.0)
		var volume_target: float = -20.0 + _rpm * 16.0
		var weight: float = 1.0 - exp(-delta * 6.0)
		pitch_scale = 0.75 + _rpm * 0.55
		volume_db = lerpf(volume_db, volume_target, weight)
		return
	var decay_weight: float = 1.0 - exp(-delta * 4.0)
	_rpm = lerpf(_rpm, 0.0, decay_weight)
	pitch_scale = lerpf(pitch_scale, 0.4, decay_weight)
	volume_db = lerpf(volume_db, -45.0, decay_weight)
	if volume_db <= -44.0 and not _silent:
		stop()
		_silent = true


func get_rpm() -> float:
	return _rpm


func get_engine_pitch() -> float:
	return pitch_scale


func get_engine_active() -> bool:
	return _setup_done and not _silent


func _make_engine_wav() -> AudioStreamWAV:
	var count: int = int(ENGINE_DURATION * float(SAMPLE_RATE))
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2035
	var pulse_gains: PackedFloat32Array = PackedFloat32Array()
	var pulse_noise_a: PackedFloat32Array = PackedFloat32Array()
	var pulse_noise_b: PackedFloat32Array = PackedFloat32Array()
	pulse_gains.resize(PULSE_COUNT)
	pulse_noise_a.resize(PULSE_COUNT)
	pulse_noise_b.resize(PULSE_COUNT)
	for i in PULSE_COUNT:
		pulse_gains[i] = 0.55 + rng.randf() * 0.65
		pulse_noise_a[i] = rng.randf() * 2.0 - 1.0
		pulse_noise_b[i] = rng.randf() * 2.0 - 1.0
	for i in count:
		var t: float = float(i) / float(SAMPLE_RATE)
		var phase: float = fmod(t * ENGINE_FREQ, 1.0)
		var saw: float = phase * 2.0 - 1.0
		var square: float = 1.0
		if phase >= 0.5:
			square = -1.0
		var pulse_index: int = int(t * PULSE_RATE) % PULSE_COUNT
		var pulse_local: float = fmod(t * PULSE_RATE, 1.0)
		var pulse_noise: float = pulse_noise_a[pulse_index] * 0.6 + pulse_noise_b[pulse_index] * 0.4
		var pulse: float = exp(-pulse_local * 32.0) * pulse_noise * pulse_gains[pulse_index]
		var envelope: float = 0.78 + 0.22 * sin(TAU * 4.0 * t)
		var sample_value: float = (saw * 0.34 + square * 0.22 + pulse * 0.9) * envelope * 0.8
		sample_value = clampf(sample_value, -1.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, count)


func _to_wav(bytes: PackedByteArray, sample_count: int) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = bytes
	return stream
