extends AudioStreamPlayer3D

const SAMPLE_RATE: int = 22050
const WIND_DURATION: float = 2.0
const WIND_LFO_CYCLES: float = 2.0
const TAU: float = 6.283185307179586

var _ambient_level: float = 0.8
var _setup_done: bool = false


func _ready() -> void:
	_ambient_level = randf_range(0.6, 1.0)
	stream = _make_wind_wav()
	volume_db = -22.0
	unit_size = 40.0
	max_db = 0.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_setup_done = true
	add_to_group("bf_ambient_audio")
	play()


func _exit_tree() -> void:
	stop()


func get_ambient_level() -> float:
	return _ambient_level


func get_ambient_active() -> bool:
	return _setup_done and playing


func _make_wind_wav() -> AudioStreamWAV:
	var count: int = int(WIND_DURATION * float(SAMPLE_RATE))
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2036
	var noise_buffer: PackedFloat32Array = PackedFloat32Array()
	noise_buffer.resize(count)
	var low_pass: float = 0.0
	for i in count:
		var noise: float = rng.randf() * 2.0 - 1.0
		low_pass += 0.055 * (noise - low_pass)
		noise_buffer[i] = low_pass
	var blend_count: int = int(0.25 * float(SAMPLE_RATE))
	for i in blend_count:
		var weight: float = float(i) / float(blend_count)
		var head: float = noise_buffer[i]
		var tail_index: int = count - blend_count + i
		var tail: float = noise_buffer[tail_index]
		noise_buffer[i] = lerpf(head, tail, weight)
		noise_buffer[tail_index] = lerpf(tail, head, weight)
	for i in count:
		var t: float = float(i) / float(SAMPLE_RATE)
		var lfo: float = 0.78 + 0.22 * sin(TAU * WIND_LFO_CYCLES * t)
		var sample_value: float = noise_buffer[i] * lfo * 0.9
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
