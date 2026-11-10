extends Node
## Audio service (autoload "Audio"). All sounds are original, procedurally synthesised
## WAV files produced by tools/audio/gen_audio.py into res://gta/generated/audio.
## One-shots are played through small pools; loops are owned by their emitters.

const DIR := "res://gta/generated/audio/"
const POOL_3D := 28
const POOL_2D := 10

var _streams: Dictionary = {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _underwater := false
var _lowpass: AudioEffectLowPassFilter
var _last_play: Dictionary = {}

func _enter_tree() -> void:
	_setup_buses()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		p.max_distance = 90.0
		p.panning_strength = 0.8
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.bus = &"UI"
		add_child(p2)
		_pool2d.append(p2)

func _setup_buses() -> void:
	# Master -> [SFX, Ambient, Music, UI]; SFX/Ambient share an underwater low-pass.
	for bus_name: String in ["SFX", "Ambient", "Music", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	var sfx := AudioServer.get_bus_index("SFX")
	AudioServer.add_bus_effect(sfx, _lowpass)
	var amb := AudioServer.get_bus_index("Ambient")
	AudioServer.add_bus_effect(amb, _lowpass)
	var lim := AudioEffectLimiter.new()
	AudioServer.add_bus_effect(0, lim)

## Gameplay names that map onto a sound of the library (tools/audio/SPEC_AUDIO.md).
const ALIAS := {
	&"ui_select": &"ui_click", &"ui_move": &"ui_hover", &"ui_back": &"ui_close", &"ui_wheel_open": &"ui_open",
	&"ui_phone": &"phone_beep", &"ui_camera": &"camera_shutter", &"ui_repair": &"wrench_ratchet", &"ui_eat": &"pickup_item",
	&"ui_heal": &"pickup_health", &"ui_armor": &"pickup_item", &"ui_ammo": &"pickup_weapon", &"ui_treasure": &"ui_success",
}

func stream(sound: StringName) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	if ALIAS.has(sound) and not ResourceLoader.exists(DIR + String(sound) + ".wav"):
		var real := stream(ALIAS[sound])
		_streams[sound] = real
		return real
	var path := DIR + String(sound) + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_streams[sound] = s
	return s

## Looping variant of a stream (configured once on the shared resource).
func loop_stream(sound: StringName) -> AudioStream:
	var s := stream(sound)
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			# loop points are in sample frames whatever the storage format (PCM or QOA)
			w.loop_begin = 0
			w.loop_end = int(round(w.get_length() * float(w.mix_rate)))
			if w.format == AudioStreamWAV.FORMAT_16_BITS or w.format == AudioStreamWAV.FORMAT_8_BITS:
				var bytes_per := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
				w.loop_end = w.data.size() / (bytes_per * (2 if w.stereo else 1))
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return s

## Fire-and-forget positional sound.
func play(sound: StringName, pos: Vector3, vol_db := 0.0, pitch := 1.0, vary := 0.06, max_dist := 90.0, bus := &"SFX") -> void:
	var s := stream(sound)
	if s == null:
		return
	# de-duplicate identical sounds fired in the same few milliseconds (shotgun pellets etc.)
	var now := Time.get_ticks_msec()
	var key := String(sound)
	if _last_play.has(key) and now - int(_last_play[key]) < 25:
		return
	_last_play[key] = now
	var p := _pool3d[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	p.stop()
	p.stream = s
	p.bus = bus
	p.global_position = pos
	p.volume_db = vol_db
	p.max_distance = max_dist
	p.unit_size = clampf(max_dist / 12.0, 2.0, 30.0)
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-vary, vary)))
	p.play()

## Non-positional sound (UI, player feedback).
func play_ui(sound: StringName, vol_db := 0.0, pitch := 1.0, bus := &"UI") -> void:
	var s := stream(sound)
	if s == null:
		return
	var p := _pool2d[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	p.stop()
	p.stream = s
	p.bus = bus
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.05, pitch)
	p.play()

## Create a looping 3D emitter parented to `parent` (engine, siren, rotor, fire...). Caller owns it.
func make_loop(sound: StringName, parent: Node3D, vol_db := 0.0, max_dist := 70.0, autoplay := true, bus := &"SFX") -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = loop_stream(sound)
	p.bus = bus
	p.volume_db = vol_db
	p.max_distance = max_dist
	p.unit_size = clampf(max_dist / 10.0, 2.0, 30.0)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	if autoplay and p.stream != null:
		p.play()
	return p

## Create a looping non-positional player (ambience, radio, rain).
func make_loop_2d(sound: StringName, vol_db := 0.0, bus := &"Ambient") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = loop_stream(sound)
	p.bus = bus
	p.volume_db = vol_db
	add_child(p)
	return p

func set_underwater(on: bool) -> void:
	if on == _underwater:
		return
	_underwater = on
	var tw := create_tween()
	tw.tween_property(_lowpass, "cutoff_hz", 650.0 if on else 20000.0, 0.25)
