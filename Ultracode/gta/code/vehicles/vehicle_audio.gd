class_name VehicleAudio
extends RefCounted
## Per-vehicle sound: engine loop (pitch / volume from RPM and load), tyre skid loop, horn,
## siren loop, crash / door / start one-shots, plus the AI noise events that belong to them.
## Players are created lazily through the Audio autoload, so a vehicle that never runs its
## engine near the listener costs nothing. Unknown / missing sound ids stay silent.

const ENGINE_RANGE := 65.0
const SIREN_RANGE := 150.0

var v: VehicleBase = null
var engine: AudioStreamPlayer3D = null
var skid: AudioStreamPlayer3D = null
var horn: AudioStreamPlayer3D = null
var siren: AudioStreamPlayer3D = null
var horn_sound: String = ""            ## override from the horn mod ("" = spec default)
var horn_pitch: float = 1.0

var _siren_noise_t: float = 0.0
var _horn_noise_t: float = 0.0
var _crash_cd_msec: int = 0


func setup(vehicle: VehicleBase) -> void:
	v = vehicle


func _make(sound_id: String, max_dist: float, bus: String, local_pos: Vector3) -> AudioStreamPlayer3D:
	if sound_id == "":
		return null
	var p: AudioStreamPlayer3D = Audio.make_loop_player(sound_id, v, max_dist, bus)
	if p != null:
		p.position = local_pos
		p.volume_db = -18.0
	return p


func _usable(p: AudioStreamPlayer3D) -> bool:
	return p != null and is_instance_valid(p) and p.stream != null


func update(delta: float) -> void:
	if not v.is_inside_tree():
		return
	var active := v.audio_active and not v.destroyed

	# --- engine
	if active and v.engine_on:
		if engine == null:
			engine = _make(v.spec.sound_engine, ENGINE_RANGE, "Engine", v.global_transform.affine_inverse() * v.get_engine_position())
		if _usable(engine):
			var rf := v.get_rpm_factor()
			var load_f := v.get_engine_load()
			engine.pitch_scale = lerpf(v.spec.engine_pitch_min, v.spec.engine_pitch_max, rf)
			var target := lerpf(-14.0, -2.0, clampf(load_f * 0.65 + rf * 0.35, 0.0, 1.0))
			engine.volume_db = lerpf(engine.volume_db, target, clampf(delta * 8.0, 0.0, 1.0))
			if not engine.playing:
				engine.play()
	elif _usable(engine) and engine.playing:
		engine.stop()

	# --- tyre skid
	var sk := v.get_skid_amount() if active else 0.0
	if sk > 0.12:
		if skid == null:
			skid = _make("tire_skid_loop", 55.0, "SFX", Vector3(0.0, 0.3, 0.6))
		if _usable(skid):
			skid.volume_db = lerpf(-20.0, -3.0, sk)
			skid.pitch_scale = lerpf(0.85, 1.15, sk)
			if not skid.playing:
				skid.play()
	elif _usable(skid) and skid.playing:
		skid.stop()

	# --- horn
	if v.horn_on and v.detail_level <= 1:
		if horn == null:
			horn = _make(horn_sound if horn_sound != "" else v.spec.sound_horn, 70.0, "SFX", Vector3(0.0, 0.7, -1.2))
		if _usable(horn):
			horn.volume_db = -2.0
			horn.pitch_scale = horn_pitch
			if not horn.playing:
				horn.play()
		_horn_noise_t += delta
		if _horn_noise_t > 1.0:
			_horn_noise_t = 0.0
			EventBus.noise_emitted.emit(v.global_position, 30.0, "horn", v.driver if v.driver != null else v)
	else:
		_horn_noise_t = 0.0
		if _usable(horn) and horn.playing:
			horn.stop()

	# --- siren
	if v.siren_on and not v.destroyed:
		_siren_noise_t += delta
		if _siren_noise_t > 1.5:
			_siren_noise_t = 0.0
			EventBus.noise_emitted.emit(v.global_position, 70.0, "siren", v.driver if v.driver != null else v)
		if v.detail_level <= 1:
			if siren == null:
				siren = _make(v.spec.sound_siren, SIREN_RANGE, "SFX", Vector3(0.0, 1.5, 0.0))
			if _usable(siren):
				siren.volume_db = -3.0
				if not siren.playing:
					siren.play()
		elif _usable(siren) and siren.playing:
			siren.stop()
	elif _usable(siren) and siren.playing:
		siren.stop()


## Call after the horn mod changed so the next honk uses the new sample.
func reset_horn() -> void:
	if horn != null and is_instance_valid(horn):
		horn.queue_free()
	horn = null


func stop_all() -> void:
	for p: AudioStreamPlayer3D in [engine, skid, horn, siren]:
		if p != null and is_instance_valid(p) and p.playing:
			p.stop()


func play_start() -> void:
	if v.is_inside_tree() and v.audio_active:
		Audio.play_at("engine_start", v.get_engine_position(), -5.0, 1.0, 45.0)


func play_door(opening: bool) -> void:
	if v.is_inside_tree() and v.audio_active:
		Audio.play_at("door_open" if opening else "door_close", v.global_position + Vector3.UP * 0.9, -6.0, randf_range(0.95, 1.05), 30.0)


func play_crash(dv: float, pos: Vector3) -> void:
	var now := VehicleBase.now_msec()
	if now < _crash_cd_msec:
		return
	_crash_cd_msec = now + 140
	var big := dv > 7.0
	var vol := clampf(-14.0 + dv * 1.3, -14.0, 3.0)
	Audio.play_at("crash_large" if big else "crash_small", pos, vol, randf_range(0.88, 1.12), 110.0 if big else 70.0)
