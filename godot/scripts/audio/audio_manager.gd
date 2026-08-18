extends Node3D

const SAMPLE_RATE := 44100
const PLAYER_POOL_SIZE := 20

var _camera: Camera3D
var _players: Array = []
var _player_active: Array = []
var _cursor := 0

var _shot_streams: Array = []
var _explosion_stream: AudioStreamWAV
var _impact_stream: AudioStreamWAV
var _footstep_stream: AudioStreamWAV
var _hit_stream: AudioStreamWAV
var _reload_stream: AudioStreamWAV
var _enemy_shot_stream: AudioStreamWAV
var _radio_chatter_stream: AudioStreamWAV
var _capture_announce_stream: AudioStreamWAV
var _round_end_stream: AudioStreamWAV


func _ready() -> void:
	_generate_sounds()
	_build_player_pool()
	add_to_group("bf_audio_manager")


func _exit_tree() -> void:
	for player in _players:
		if player != null and is_instance_valid(player):
			player.stop()
	_stop_group("bf_ambient_audio")
	_stop_group("bf_vehicle_engine")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_all()
		get_tree().auto_accept_quit = false
		get_tree().create_timer(0.15, true).timeout.connect(_complete_quit)


func stop_all() -> void:
	for player in _players:
		if player != null and is_instance_valid(player):
			player.stop()
	_stop_group("bf_ambient_audio")
	_stop_group("bf_vehicle_engine")


func _stop_group(group_name: String) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		var player := node as AudioStreamPlayer3D
		if player != null:
			player.stop()


func _complete_quit() -> void:
	get_tree().quit()


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func play_shot(weapon_type: String, distance: float) -> void:
	if _shot_streams.is_empty():
		return
	var variant := 0
	if weapon_type == "sniper" or weapon_type == "sniper_rifle":
		variant = 2
	elif weapon_type == "dmr" or weapon_type == "marksman":
		variant = 3
	elif weapon_type == "smg" or weapon_type == "pistol" or weapon_type == "carbine":
		variant = 1
	elif weapon_type == "rocket" or weapon_type == "launcher" or weapon_type == "rpg" or weapon_type == "rocket_launcher":
		variant = 4
	elif weapon_type == "grenade":
		variant = 5
	variant = clampi(variant, 0, _shot_streams.size() - 1)
	var db := 0.0
	if weapon_type == "smg" or weapon_type == "pistol":
		db = -2.5
	elif weapon_type == "rocket" or weapon_type == "launcher" or weapon_type == "rpg" or weapon_type == "rocket_launcher":
		db = 2.0
	elif weapon_type == "grenade":
		db = -6.0
	var stream: AudioStreamWAV = _shot_streams[variant]
	_play_world(stream, distance, db, 8.0)


func play_impact(volume: float) -> void:
	var db := clampf(-10.0 + volume * 12.0, -18.0, 2.0)
	_play_ui(_impact_stream, db)


func play_explosion(distance: float) -> void:
	_play_world(_explosion_stream, distance, 2.0, 24.0)


func play_footstep(volume: float) -> void:
	var db := clampf(-16.0 + volume * 8.0, -24.0, -4.0)
	_play_ui(_footstep_stream, db)


func play_hit() -> void:
	_play_ui(_hit_stream, -3.0)


func play_reload() -> void:
	_play_ui(_reload_stream, -5.0)


func play_enemy_shot(distance: float) -> void:
	_play_world(_enemy_shot_stream, distance, -2.0, 10.0)


func play_radio_chatter(volume: float) -> void:
	if _radio_chatter_stream == null:
		return
	var db := clampf(-14.0 + volume * 8.0, -24.0, -2.0)
	_play_ui(_radio_chatter_stream, db)


func play_capture_announce(team: String) -> void:
	if _capture_announce_stream == null:
		return
	var key := team.to_lower()
	var db := -8.0
	var pitch := 1.08
	if key.contains("red"):
		db = -5.0
		pitch = 0.9
	_play_ui(_capture_announce_stream, db, pitch)


func play_round_end(winner: String) -> void:
	if _round_end_stream == null:
		return
	var key := winner.to_lower()
	var db := -5.0
	var pitch := 1.06
	if key.contains("draw") or key.contains("tie") or key == "none" or key == "stalemate":
		db = -8.0
		pitch = 0.78
	elif key.contains("red"):
		db = -4.0
		pitch = 0.92
	_play_ui(_round_end_stream, db, pitch)


func _play_world(stream: AudioStreamWAV, distance: float, db: float, unit_size: float) -> void:
	var player := _acquire_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = 1.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = unit_size
	player.max_db = 0.0
	_place_at_distance(player, distance)
	player.play()


func _play_ui(stream: AudioStreamWAV, db: float, pitch: float = 1.0) -> void:
	var player := _acquire_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = pitch
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_db = 3.0
	if _camera != null and is_instance_valid(_camera):
		player.global_position = _camera.global_position
	else:
		player.global_position = Vector3.ZERO
	player.play()


func _place_at_distance(player: AudioStreamPlayer3D, distance: float) -> void:
	var d := maxf(distance, 0.5)
	if _camera != null and is_instance_valid(_camera):
		var forward := -_camera.global_transform.basis.z
		player.global_position = _camera.global_position + forward * d
	else:
		player.global_position = Vector3(0.0, 0.0, -d)


func _acquire_player() -> AudioStreamPlayer3D:
	if _players.is_empty():
		return null
	for i in _player_active.size():
		var idx := (_cursor + i) % _player_active.size()
		if not _player_active[idx]:
			_cursor = idx + 1
			_player_active[idx] = true
			return _players[idx]
	var steal_idx := _cursor % _player_active.size()
	var stolen: AudioStreamPlayer3D = _players[steal_idx]
	stolen.stop()
	_cursor = steal_idx + 1
	_player_active[steal_idx] = true
	return stolen


func _on_player_finished(player: AudioStreamPlayer3D) -> void:
	for i in _player_active.size():
		if _players[i] == player:
			_player_active[i] = false
			return


func _generate_sounds() -> void:
	_shot_streams.append(_make_shot_stream(0.95, 11))
	_shot_streams.append(_make_shot_stream(1.0, 23))
	_shot_streams.append(_make_shot_stream(1.13, 37))
	_shot_streams.append(_make_dmr_stream())
	_shot_streams.append(_make_launcher_stream())
	_shot_streams.append(_make_grenade_stream())
	_explosion_stream = _make_explosion_stream()
	_impact_stream = _make_impact_stream()
	_footstep_stream = _make_footstep_stream()
	_hit_stream = _make_hit_stream()
	_reload_stream = _make_reload_stream()
	_enemy_shot_stream = _make_shot_stream(0.85, 41)
	_radio_chatter_stream = _make_radio_chatter_stream()
	_capture_announce_stream = _make_capture_announce_stream()
	_round_end_stream = _make_round_end_stream()


func _build_player_pool() -> void:
	for i in PLAYER_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "AudioPlayer%d" % i
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = 8.0
		player.max_db = 0.0
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_players.append(player)
		_player_active.append(false)


func _make_shot_stream(pitch_scale: float, seed: int) -> AudioStreamWAV:
	var duration := 0.36
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lp := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		lp += 0.16 * (noise - lp)
		var env := minf(t * 220.0, 1.0)
		var crack := noise * exp(-t * 34.0)
		var boom := lp * exp(-t * 7.0) * 0.9
		var sub := sin(6.283185307 * 58.0 * pitch_scale * t) * exp(-t * 9.0) * 0.6
		var sample_value := (crack * 0.8 + boom * 1.0 + sub * 0.5) * 0.62 * env
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_dmr_stream() -> AudioStreamWAV:
	var duration := 0.52
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var lp := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		lp += 0.16 * (noise - lp)
		var env := minf(t * 220.0, 1.0)
		var crack := noise * exp(-t * 30.0)
		var boom := lp * exp(-t * 5.4) * 0.95
		var sub := sin(6.283185307 * 58.0 * 1.05 * t) * exp(-t * 6.6) * 0.65
		var sample_value := (crack * 0.8 + boom * 1.0 + sub * 0.55) * 0.62 * env
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_launcher_stream() -> AudioStreamWAV:
	var duration := 0.82
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var lp := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		lp += 0.07 * (noise - lp)
		var env := minf(t * 120.0, 1.0) * exp(-t * 0.9)
		var thump := sin(6.283185307 * 42.0 * t) * exp(-t * 9.0) * 1.0
		var whoosh := sin(6.283185307 * (48.0 + t * 70.0) * t) * exp(-t * 1.4) * 0.85
		var hiss := noise * exp(-t * 8.0) * 0.55
		var sample_value := (lp * 1.8 + thump + whoosh + hiss) * 0.68 * env
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_grenade_stream() -> AudioStreamWAV:
	var duration := 0.16
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 59
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		var env := minf(t * 420.0, 1.0) * exp(-t * 13.0)
		var thump := sin(6.283185307 * 168.0 * t) * exp(-t * 24.0) * 0.75
		var click := noise * exp(-t * 95.0) * 0.45
		var sample_value := (click + thump) * 0.42 * env
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_explosion_stream() -> AudioStreamWAV:
	var duration := 1.35
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var lp1 := 0.0
	var lp2 := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		lp1 += 0.09 * (noise - lp1)
		lp2 += 0.018 * (lp1 - lp2)
		var env := minf(t * 100.0, 1.0) * exp(-t * 1.25)
		var rumble := sin(6.283185307 * 38.0 * t) * exp(-t * 2.2) * 0.8
		var hiss := noise * exp(-t * 14.0) * 0.5
		var sample_value := (lp2 * 2.6 + rumble + hiss) * 0.72 * env
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_impact_stream() -> AudioStreamWAV:
	var duration := 0.18
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 83
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		var sample_value := (noise * exp(-t * 42.0) * 0.55
			+ sin(6.283185307 * 95.0 * t) * exp(-t * 28.0) * 0.9) * minf(t * 300.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_footstep_stream() -> AudioStreamWAV:
	var duration := 0.16
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		var sample_value := (noise * exp(-t * 55.0) * 0.7
			+ sin(6.283185307 * 62.0 * t) * exp(-t * 24.0) * 1.0) * minf(t * 320.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_hit_stream() -> AudioStreamWAV:
	var duration := 0.14
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var tone_a := 0.0
		var tone_b := 0.0
		if t < 0.07:
			tone_a = sin(6.283185307 * 1350.0 * t) * exp(-t * 45.0) * 0.8
		var tb := t - 0.065
		if tb >= 0.0:
			tone_b = sin(6.283185307 * 1850.0 * tb) * exp(-tb * 50.0) * 0.7
		var sample_value := (tone_a + tone_b) * 0.6 * minf(t * 600.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_reload_stream() -> AudioStreamWAV:
	var duration := 1.0
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 109
	var click_times := [0.0, 0.17, 0.38, 0.61, 0.84]
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		var sample_value := 0.0
		for click in click_times:
			var dt: float = t - float(click)
			if dt >= 0.0 and dt < 0.025:
				sample_value += noise * exp(-dt * 170.0) * 0.75
		if t >= 0.28 and t <= 0.52:
			var u := (t - 0.28) / 0.24
			sample_value += sin(6.283185307 * (300.0 + u * 420.0) * t) * 0.24
		sample_value = clampf(sample_value, -1.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_radio_chatter_stream() -> AudioStreamWAV:
	var duration := 0.9
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	var bursts: Array[float] = [0.0, 0.11, 0.24, 0.38, 0.55, 0.71]
	for i in count:
		var t: float = float(i) / float(SAMPLE_RATE)
		var noise: float = rng.randf() * 2.0 - 1.0
		var burst_gain: float = 0.0
		for burst: float in bursts:
			var dt: float = t - burst
			if dt >= 0.0 and dt < 0.16:
				burst_gain += exp(-dt * 26.0) * 0.55
		var carrier: float = sin(6.283185307 * 1200.0 * t) * burst_gain
		var hiss: float = noise * burst_gain * 0.45
		var beep: float = sin(6.283185307 * 420.0 * t) * exp(-t * 3.5) * 0.2
		var sample_value: float = (carrier + hiss + beep) * exp(-t * 2.2) * minf(t * 180.0, 1.0)
		sample_value = clampf(sample_value, -1.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_capture_announce_stream() -> AudioStreamWAV:
	var duration := 0.4
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 127
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		var tone := 0.0
		if t < 0.18:
			tone = sin(6.283185307 * 880.0 * t) * exp(-maxf(t - 0.02, 0.0) * 18.0)
		else:
			var t2 := t - 0.22
			if t2 >= 0.0:
				tone = sin(6.283185307 * 1170.0 * t2) * exp(-maxf(t2 - 0.02, 0.0) * 22.0)
		var radio := noise * exp(-t * 16.0) * 0.16
		var sample_value := (tone + radio) * minf(t * 480.0, 1.0)
		sample_value = clampf(sample_value, -1.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _make_round_end_stream() -> AudioStreamWAV:
	var duration := 1.2
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 131
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var note_starts := [0.0, 0.18, 0.36, 0.58]
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		var melody := 0.0
		for n in notes.size():
			var dt := t - float(note_starts[n])
			if dt >= 0.0 and dt < 0.34:
				var attack := minf(dt * 130.0, 1.0)
				var release := exp(-dt * 11.0)
				melody += sin(6.283185307 * float(notes[n]) * dt) * attack * release * 0.26
				melody += sin(6.283185307 * float(notes[n]) * 2.0 * dt) * attack * release * 0.07
		var bass := sin(6.283185307 * 130.81 * t) * exp(-t * 1.8) * 0.14
		var shimmer := noise * exp(-maxf(t - 0.72, 0.0) * 9.0) * 0.06
		var sample_value := (melody + bass + shimmer) * minf(t * 110.0, 1.0)
		sample_value = clampf(sample_value, -1.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(sample_value * 32767.0), -32768, 32767))
	return _to_wav(bytes, duration)


func _to_wav(bytes: PackedByteArray, duration: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
