extends Node3D
## 100% procedurally synthesised audio (no external assets): SFX, loops, ambience, radio stations.

const SR := 22050
const STATIONS := ["Radio off", "Cinder FM (synth)", "Low Tide (chill)", "Rustbelt (rock)", "Night Shift (funk)"]

var streams := {}
var ready_flag := false
var _thread: Thread
var _p3: Array = []
var _p3i := 0
var _p2: Array = []
var _p2i := 0
var amb := {}
var radio: AudioStreamPlayer
var station := 1
var radio_on := false
var _lp_sfx: AudioEffectLowPassFilter
var volume_master := 0.8


func _ready() -> void:
	for b in ["SFX", "Music", "Amb"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
	_lp_sfx = AudioEffectLowPassFilter.new()
	_lp_sfx.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), _lp_sfx)
	AudioServer.set_bus_volume_db(0, linear_to_db(volume_master))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -8.0)
	for i in 14:
		var p = AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 9.0
		p.max_distance = 170.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_p3.append(p)
	for i in 6:
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2.append(p)
	for n in ["city", "ocean", "wind", "rain", "chatter", "industrial"]:
		var p = AudioStreamPlayer.new()
		p.bus = "Amb"
		p.volume_db = -60.0
		add_child(p)
		amb[n] = p
	radio = AudioStreamPlayer.new()
	radio.bus = "Music"
	add_child(radio)
	_thread = Thread.new()
	_thread.start(_generate)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func _done(d: Dictionary) -> void:
	streams = d
	ready_flag = true
	for n in amb:
		amb[n].stream = streams.get("amb_" + n)
		if amb[n].stream:
			amb[n].play()
	print("[audio] synthesised %d streams" % streams.size())


# ------------------------------------------------------------------ playback
func play(name: String, vol := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var p: AudioStreamPlayer = _p2[_p2i]
	_p2i = (_p2i + 1) % _p2.size()
	p.stream = streams[name]
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()


func play3d(name: String, pos: Vector3, vol := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var cam = get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(pos) > 170.0 * 170.0:
		return
	var p: AudioStreamPlayer3D = _p3[_p3i]
	_p3i = (_p3i + 1) % _p3.size()
	p.stream = streams[name]
	p.global_position = pos
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()


## Looping positional emitter owned by the caller (engines, sirens...). Returns null until synthesis is done.
func loop3d(name: String, parent: Node3D, vol := 0.0, unit := 7.0) -> AudioStreamPlayer3D:
	if not streams.has(name):
		return null
	var p = AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = streams[name]
	p.volume_db = vol
	p.unit_size = unit
	p.max_distance = 140.0
	parent.add_child(p)
	p.play()
	return p


func set_radio(on: bool) -> void:
	radio_on = on
	_apply_radio()


func next_station() -> void:
	station = (station + 1) % STATIONS.size()
	_apply_radio()
	G.notify("Radio: " + STATIONS[station], 2.0)


func _apply_radio() -> void:
	if not radio_on or station == 0 or not streams.has("radio%d" % station):
		radio.stop()
		return
	var s: AudioStream = streams["radio%d" % station]
	if radio.stream != s or not radio.playing:
		radio.stream = s
		radio.play()


func _process(dt: float) -> void:
	if not ready_flag or G.player == null:
		return
	var p = G.player_pos()
	var uw: bool = G.env.underwater if G.env else false
	_lp_sfx.cutoff_hz = lerpf(_lp_sfx.cutoff_hz, 500.0 if uw else 20000.0, clamp(dt * 6.0, 0.0, 1.0))
	var shore: float = clamp(1.0 - (min(min(300.0 - abs(p.x), 214.0 - p.z), 300.0 + p.z)) / 90.0, 0.0, 1.0)
	var urban: float = clamp(1.0 - Vector2(p.x, p.z).length() / 260.0, 0.0, 1.0)
	var high: float = clamp(p.y / 60.0, 0.0, 1.0)
	var rain: float = G.env.w.rain if G.env else 0.0
	var night: float = G.env.night if G.env else 0.0
	var ind: float = clamp(1.0 - abs(p.x - 190.0) / 90.0, 0.0, 1.0)
	_amb("city", urban * (0.55 - 0.25 * night) * (1.0 - high * 0.5), dt)
	_amb("ocean", shore * 0.6, dt)
	_amb("wind", 0.12 + high * 0.6 + (G.env.w.cloud * 0.15 if G.env else 0.0), dt)
	_amb("rain", rain * 0.8, dt)
	_amb("chatter", urban * 0.28 * (1.0 - night * 0.7) * (1.0 - high), dt)
	_amb("industrial", ind * 0.35 * (1.0 - high), dt)


func _amb(n: String, target: float, dt: float) -> void:
	var p: AudioStreamPlayer = amb[n]
	var cur = db_to_linear(p.volume_db)
	p.volume_db = linear_to_db(max(0.0005, lerpf(cur, target * (0.25 if G.env and G.env.underwater else 1.0), clamp(dt * 1.5, 0.0, 1.0))))


# ------------------------------------------------------------------ synthesis (runs in a worker thread)
func _wav(data: PackedFloat32Array, loop := false, rate := SR) -> AudioStreamWAV:
	var bytes = PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clamp(data[i], -1.0, 1.0) * 32000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


func _burst(r: RandomNumberGenerator, dur: float, ndecay: float, lp: float, f0: float, f1: float, tamp: float, namp: float, tail := 0.0) -> PackedFloat32Array:
	var n = int(dur * SR)
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	var ph = 0.0
	for i in n:
		var t = float(i) / SR
		var k = t / dur
		y += lp * (r.randf_range(-1.0, 1.0) - y)
		ph += TAU * lerpf(f0, f1, min(1.0, k * 3.0)) / SR
		var env = exp(-t * ndecay) + tail * exp(-t * 4.0)
		out[i] = (y * namp * env + sin(ph) * tamp * exp(-t * ndecay * 0.6)) * min(1.0, t * 800.0)
	return out


func _tone(dur: float, freqs: Array, decay: float, amp := 0.5, sweep := 1.0) -> PackedFloat32Array:
	var n = int(dur * SR)
	var out = PackedFloat32Array()
	out.resize(n)
	var phs = []
	for f in freqs:
		phs.append(0.0)
	for i in n:
		var t = float(i) / SR
		var v = 0.0
		for j in freqs.size():
			phs[j] += TAU * freqs[j] * lerpf(1.0, sweep, t / dur) / SR
			v += sin(phs[j])
		out[i] = v / freqs.size() * amp * exp(-t * decay) * min(1.0, t * 400.0) * min(1.0, (dur - t) * 200.0)
	return out


func _seq(parts: Array) -> PackedFloat32Array:
	var out = PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


func _silence(dur: float) -> PackedFloat32Array:
	var o = PackedFloat32Array()
	o.resize(int(dur * SR))
	return o


func _loop_noise(r: RandomNumberGenerator, dur: float, lp: float, am_hz: float, am_depth: float, amp: float, hp := 0.0) -> PackedFloat32Array:
	var n = int(dur * SR)
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	var y2 = 0.0
	for i in n:
		var t = float(i) / SR
		var x = r.randf_range(-1.0, 1.0)
		y += lp * (x - y)
		y2 += hp * (y - y2)
		var v = y - y2 if hp > 0.0 else y
		out[i] = v * amp * (1.0 - am_depth + am_depth * (0.5 + 0.5 * sin(TAU * am_hz * t)))
	# crossfade ends for a seamless loop
	var xf = int(0.08 * SR)
	for i in xf:
		var k = float(i) / xf
		out[i] = out[i] * k + out[n - xf + i] * (1.0 - k)
	out.resize(n - xf)
	return out


func _engine(dur: float, f: float, harm: Array, noise: float, am_hz := 0.0, r: RandomNumberGenerator = null) -> PackedFloat32Array:
	var n = int(dur * SR)
	var cycles: float = round(f * dur)
	f = cycles / dur
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	for i in n:
		var t = float(i) / SR
		var v = 0.0
		for h in harm.size():
			var ph = fmod(f * (h + 1) * t, 1.0)
			v += (ph * 2.0 - 1.0) * harm[h]
		if r:
			y += 0.2 * (r.randf_range(-1.0, 1.0) - y)
			v += y * noise
		if am_hz > 0.0:
			v *= 0.55 + 0.45 * sin(TAU * round(am_hz * dur) / dur * t)
		out[i] = v * 0.35
	return out


func _music(r: RandomNumberGenerator, style: int) -> PackedFloat32Array:
	var rate = 16000
	var bpm: float = [0.0, 112.0, 80.0, 132.0, 100.0][style]
	var beat = 60.0 / bpm
	var bars = 4
	var n = int(beat * 4 * bars * rate)
	var out = PackedFloat32Array()
	out.resize(n)
	var roots: Array = [[], [45, 41, 48, 43], [48, 45, 41, 43], [40, 40, 43, 45], [38, 41, 43, 36]][style]
	var ny = 0.0
	for i in n:
		var t = float(i) / rate
		var bar = int(t / (beat * 4)) % bars
		var bt = fmod(t, beat)
		var b16 = int(t / (beat / 4.0))
		var st = fmod(t, beat / 4.0)
		var root: float = 440.0 * pow(2.0, (roots[bar] - 69) / 12.0)
		var v = 0.0
		ny += 0.5 * (r.randf_range(-1.0, 1.0) - ny)
		match style:
			1:
				v += (fmod(root * t, 1.0) * 2.0 - 1.0) * 0.22 * exp(-st * 9.0)
				var arp: float = root * 4.0 * [1.0, 1.2, 1.5, 2.0][b16 % 4]
				v += sin(TAU * arp * t) * 0.12 * exp(-st * 14.0)
				v += sin(TAU * 55.0 * bt * exp(-bt * 6.0) * 2.0) * 0.5 * exp(-bt * 14.0)
				if b16 % 2 == 1:
					v += ny * 0.1 * exp(-st * 60.0)
			2:
				for m in [1.0, 1.26, 1.5, 1.89]:
					v += sin(TAU * root * 2.0 * m * t + sin(t * 0.7) * 0.6) * 0.07
				v += sin(TAU * root * 0.5 * t) * 0.18
				v += sin(TAU * root * 4.0 * [1.0, 1.5, 1.26, 2.0][int(t / beat) % 4] * t) * 0.07 * exp(-bt * 3.0)
			3:
				var sq = 1.0 if fmod(root * 2.0 * t, 1.0) < 0.5 else -1.0
				var sq2 = 1.0 if fmod(root * 3.0 * t, 1.0) < 0.5 else -1.0
				var gate = 1.0 if [1, 1, 0, 1, 1, 0, 1, 0][b16 % 8] == 1 else 0.0
				v += (sq + sq2) * 0.09 * gate * exp(-st * 5.0)
				v += sin(TAU * 60.0 * bt * exp(-bt * 5.0) * 2.0) * 0.5 * exp(-bt * 12.0)
				if int(t / beat) % 2 == 1:
					v += ny * 0.3 * exp(-bt * 18.0)
				v += ny * 0.06 * exp(-st * 50.0)
			4:
				var pat: float = [1.0, 0.0, 2.0, 1.0, 0.0, 1.5, 0.0, 1.19][b16 % 8]
				if pat > 0.0:
					v += (fmod(root * pat * t, 1.0) * 2.0 - 1.0) * 0.2 * exp(-st * 8.0)
				v += sin(TAU * 58.0 * bt * exp(-bt * 6.0) * 2.0) * 0.45 * exp(-bt * 14.0)
				if b16 % 4 == 2:
					v += ny * 0.18 * exp(-st * 30.0)
				v += sin(TAU * root * 4.0 * 1.5 * t) * 0.05 * (1.0 if b16 % 8 in [3, 6] else 0.0) * exp(-st * 10.0)
		out[i] = v * 0.8
	return out


func _generate() -> void:
	var r = RandomNumberGenerator.new()
	r.seed = 77
	var d = {}
	d["shot_handgun"] = _wav(_burst(r, 0.3, 26.0, 0.55, 220, 70, 0.6, 0.9))
	d["shot_smg"] = _wav(_burst(r, 0.2, 34.0, 0.7, 260, 90, 0.45, 0.85))
	d["shot_rifle"] = _wav(_burst(r, 0.4, 20.0, 0.6, 190, 55, 0.7, 0.95, 0.12))
	d["shot_shotgun"] = _wav(_burst(r, 0.55, 13.0, 0.35, 140, 45, 0.9, 1.0, 0.15))
	d["shot_sniper"] = _wav(_burst(r, 0.9, 9.0, 0.5, 170, 40, 0.9, 1.0, 0.3))
	d["shot_heavy"] = _wav(_burst(r, 0.6, 7.0, 0.12, 300, 90, 0.4, 0.9, 0.2))
	d["shot_silenced"] = _wav(_burst(r, 0.12, 60.0, 0.25, 500, 200, 0.15, 0.5))
	d["explosion"] = _wav(_burst(r, 2.2, 2.6, 0.08, 95, 28, 1.0, 1.0, 0.25))
	d["thunder"] = _wav(_burst(r, 3.2, 1.3, 0.03, 60, 30, 0.5, 1.0, 0.3))
	d["reload"] = _wav(_seq([_burst(r, 0.06, 80, 0.8, 900, 600, 0.3, 0.6), _silence(0.5), _burst(r, 0.07, 70, 0.8, 700, 500, 0.3, 0.7), _silence(0.25), _burst(r, 0.08, 60, 0.9, 1200, 500, 0.3, 0.8)]))
	d["empty"] = _wav(_burst(r, 0.05, 90, 0.9, 1400, 900, 0.3, 0.4))
	d["equip"] = _wav(_burst(r, 0.07, 70, 0.6, 800, 400, 0.3, 0.5))
	d["punch"] = _wav(_burst(r, 0.16, 28, 0.25, 150, 50, 0.9, 0.6))
	d["hit"] = _wav(_burst(r, 0.14, 34, 0.35, 240, 80, 0.6, 0.6))
	d["thud"] = _wav(_burst(r, 0.2, 22, 0.15, 110, 45, 0.9, 0.5))
	d["whoosh"] = _wav(_burst(r, 0.22, 16, 0.12, 0, 0, 0.0, 0.5))
	d["metal"] = _wav(_tone(0.5, [523.0, 1187.0, 1741.0, 2637.0], 11.0, 0.7))
	d["glass"] = _wav(_seq([_burst(r, 0.1, 40, 0.95, 3000, 2000, 0.2, 0.8), _tone(0.4, [2400.0, 3300.0, 4100.0, 5200.0], 14.0, 0.5)]))
	d["ricochet"] = _wav(_tone(0.25, [2400.0, 3100.0], 16.0, 0.4, 0.35))
	d["step"] = _wav(_burst(r, 0.08, 55, 0.3, 160, 80, 0.3, 0.6))
	d["splash"] = _wav(_burst(r, 0.7, 6.0, 0.5, 0, 0, 0.0, 0.8))
	d["crash"] = _wav(_seq([_burst(r, 0.35, 12, 0.45, 180, 50, 0.8, 1.0), _tone(0.3, [320.0, 870.0, 1310.0], 12.0, 0.4)]))
	d["ui_move"] = _wav(_tone(0.05, [880.0], 30.0, 0.35))
	d["ui_ok"] = _wav(_seq([_tone(0.07, [660.0], 20.0, 0.4), _tone(0.12, [990.0], 14.0, 0.4)]))
	d["ui_bad"] = _wav(_seq([_tone(0.09, [300.0], 14.0, 0.45), _tone(0.16, [210.0], 10.0, 0.45)]))
	d["pickup"] = _wav(_seq([_tone(0.06, [784.0], 18.0, 0.4), _tone(0.06, [988.0], 18.0, 0.4), _tone(0.14, [1319.0], 10.0, 0.4)]))
	d["cash"] = _wav(_seq([_tone(0.08, [1568.0, 2093.0], 16.0, 0.4), _tone(0.3, [2093.0, 2637.0, 3136.0], 9.0, 0.45)]))
	d["wanted"] = _wav(_seq([_tone(0.12, [440.0, 554.0], 8.0, 0.5), _tone(0.3, [622.0, 784.0], 6.0, 0.5)]))
	d["busted"] = _wav(_seq([_tone(0.25, [392.0, 494.0], 5.0, 0.5), _tone(0.25, [330.0, 415.0], 5.0, 0.5), _tone(0.7, [262.0, 311.0], 3.0, 0.5)]))
	d["wasted"] = _wav(_tone(1.6, [110.0, 116.5, 55.0], 1.6, 0.7, 0.8))
	d["heal"] = _wav(_seq([_tone(0.1, [523.0], 12.0, 0.4), _tone(0.1, [659.0], 12.0, 0.4), _tone(0.25, [784.0, 1047.0], 7.0, 0.4)]))
	d["repair"] = _wav(_seq([_burst(r, 0.05, 80, 0.9, 1500, 800, 0.3, 0.6), _silence(0.07), _burst(r, 0.05, 80, 0.9, 1500, 800, 0.3, 0.6), _silence(0.07), _burst(r, 0.05, 80, 0.9, 1700, 800, 0.3, 0.6), _silence(0.07), _burst(r, 0.12, 40, 0.9, 1900, 700, 0.3, 0.7)]))
	d["spray"] = _wav(_burst(r, 0.6, 3.0, 0.9, 0, 0, 0.0, 0.35))
	d["whistle"] = _wav(_tone(0.45, [1900.0], 3.0, 0.4, 1.35))
	d["scream"] = _wav(_tone(0.55, [820.0, 1650.0, 2480.0], 3.5, 0.5, 1.25))
	d["chute"] = _wav(_burst(r, 0.5, 7.0, 0.2, 90, 50, 0.4, 0.8))
	d["door"] = _wav(_seq([_burst(r, 0.07, 50, 0.4, 300, 120, 0.5, 0.5), _silence(0.12), _burst(r, 0.1, 40, 0.25, 160, 70, 0.8, 0.5)]))
	d["engine"] = _wav(_engine(1.0, 55.0, [1.0, 0.5, 0.33, 0.2], 0.5, 0.0, r), true)
	d["engine_big"] = _wav(_engine(1.0, 38.0, [1.0, 0.7, 0.4, 0.3, 0.2], 0.7, 0.0, r), true)
	d["engine_bike"] = _wav(_engine(1.0, 82.0, [1.0, 0.8, 0.6, 0.5, 0.3], 0.3, 0.0, r), true)
	d["heli"] = _wav(_engine(1.0, 60.0, [0.6, 0.4, 0.2], 2.2, 11.0, r), true)
	d["prop"] = _wav(_engine(1.0, 72.0, [1.0, 0.6, 0.5, 0.2], 0.6, 36.0, r), true)
	d["jet"] = _wav(_seq([_loop_noise(r, 1.6, 0.6, 0.0, 0.0, 0.5, 0.05)]), true)
	d["boat"] = _wav(_engine(1.0, 46.0, [1.0, 0.6, 0.3], 1.4, 6.0, r), true)
	d["train"] = _wav(_engine(1.0, 100.0, [0.5, 0.2, 0.3], 0.8, 4.0, r), true)
	d["skid"] = _wav(_loop_noise(r, 1.0, 0.5, 17.0, 0.3, 0.5, 0.2), true)
	d["fire"] = _wav(_loop_noise(r, 1.4, 0.15, 9.0, 0.5, 0.9), true)
	# siren: wail between 650 and 1250 Hz
	var n = int(1.6 * SR)
	var s = PackedFloat32Array()
	s.resize(n)
	var ph = 0.0
	for i in n:
		var t = float(i) / SR
		var f = 950.0 + 300.0 * sin(TAU * t / 1.6)
		ph += TAU * f / SR
		s[i] = (sin(ph) + 0.3 * sin(ph * 2.0) + 0.15 * sin(ph * 3.0)) * 0.3
	d["siren"] = _wav(s, true)
	var hn = int(0.5 * SR)
	var hs = PackedFloat32Array()
	hs.resize(hn)
	for i in hn:
		var t = float(i) / SR
		hs[i] = ((1.0 if fmod(420.0 * t, 1.0) < 0.5 else -1.0) + (1.0 if fmod(530.0 * t, 1.0) < 0.5 else -1.0)) * 0.16
	d["horn"] = _wav(hs, true)
	d["amb_city"] = _wav(_loop_noise(r, 4.0, 0.02, 0.25, 0.3, 2.2), true)
	d["amb_ocean"] = _wav(_loop_noise(r, 5.0, 0.12, 0.2, 0.75, 0.9), true)
	d["amb_wind"] = _wav(_loop_noise(r, 4.0, 0.06, 0.25, 0.5, 1.2, 0.004), true)
	d["amb_rain"] = _wav(_loop_noise(r, 2.0, 0.8, 0.0, 0.0, 0.45, 0.3), true)
	d["amb_chatter"] = _wav(_loop_noise(r, 4.0, 0.12, 3.7, 0.85, 0.9, 0.03), true)
	d["amb_industrial"] = _wav(_engine(2.0, 49.0, [0.5, 0.2, 0.1], 1.0, 1.5, r), true)
	for st in [1, 2, 3, 4]:
		var mus = _music(r, st)
		d["radio%d" % st] = _wav(mus, true, 16000)
	_done.call_deferred(d)
