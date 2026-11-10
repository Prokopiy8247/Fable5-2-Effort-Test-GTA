extends Node
## Audio bank + pooled players + buses (autoload "Sfx"). All streams are project-generated (tools/audio/gen_audio.py).

const DIR := "res://gta/generated/audio/"
const POOL_3D := 28
const POOL_2D := 8

var _streams: Dictionary = {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _lowpass: AudioEffectLowPassFilter
var world_bus := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in ["World", "Ambient", "Music", "UI"]:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master" if bus_name != "Ambient" else "World")
	world_bus = AudioServer.get_bus_index("World")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 600.0
	AudioServer.add_bus_effect(world_bus, _lowpass)
	AudioServer.set_bus_effect_enabled(world_bus, 0, false)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -8.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), -6.0)
	for i in range(POOL_3D):
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		add_child(p)
		_pool3d.append(p)
	for i in range(POOL_2D):
		var p2 := AudioStreamPlayer.new()
		p2.bus = "UI"
		add_child(p2)
		_pool2d.append(p2)


func stream(sname: String, loop: bool = false) -> AudioStream:
	var key := sname + ("#l" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var path := DIR + sname + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if loop and s is AudioStreamWAV:
			s = s.duplicate()
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
	_streams[key] = s
	return s


func play3d(sname: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0, max_dist: float = 90.0) -> void:
	var s := stream(sname)
	if s == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > max_dist * 1.2:
		return
	var p := _pool3d[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.max_distance = max_dist
	p.unit_size = max_dist / 9.0
	p.play()


func play(sname: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := stream(sname)
	if s == null:
		return
	var p := _pool2d[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func ui(kind: String) -> void:
	match kind:
		"click":
			play("ui_click", -6.0)
		"move":
			play("ui_move", -10.0)
		"buy":
			play("ui_buy", -4.0)
		"deny":
			play("ui_deny", -6.0)
		_:
			play(kind, -4.0)


func loop3d(parent: Node3D, sname: String, max_dist: float = 70.0, vol_db: float = 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sname, true)
	p.bus = "World"
	p.max_distance = max_dist
	p.unit_size = max_dist / 8.0
	p.volume_db = vol_db
	parent.add_child(p)
	return p


func loop2d(sname: String, bus: String = "Ambient", vol_db: float = -80.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream(sname, true)
	p.bus = bus
	p.volume_db = vol_db
	add_child(p)
	if p.stream:
		p.play()
	return p


func set_underwater(on: bool) -> void:
	AudioServer.set_bus_effect_enabled(world_bus, 0, on)
